class_name DecimalDouble
extends RefCounted
## Exact conversion between decimal text and 64-bit floats. Pure, static only.
##
## Godot's String.to_float() and JSON parser are not correctly rounded for 16 and 17 digit
## decimals (off by up to about 10 units in the last place). A save file must give back the
## same double that was written, so the save reader uses parse() instead.
##
## parse() is correctly rounded, ties to even, like a correct strtod. Small inputs take the
## exact fast path (Clinger). Everything else compares the decimal against the midpoints between
## neighbouring doubles with big integers, starting from the engine's estimate.

const _LIMB_BITS: int = 24
const _LIMB_MASK: int = (1 << 24) - 1
const _INF_BITS: int = 0x7FF0000000000000
const _MANTISSA_BITS: int = 52
## Exact powers of ten, 10^0 to 10^22: every one of them is a double without rounding.
const _POWERS_OF_TEN: PackedFloat64Array = [
	1e0,
	1e1,
	1e2,
	1e3,
	1e4,
	1e5,
	1e6,
	1e7,
	1e8,
	1e9,
	1e10,
	1e11,
	1e12,
	1e13,
	1e14,
	1e15,
	1e16,
	1e17,
	1e18,
	1e19,
	1e20,
	1e21,
	1e22,
]
const _MAX_FAST_DIGITS: int = 15
const _MAX_FAST_EXPONENT: int = 22
const _LARGEST_DOUBLE: float = 1.7976931348623157e308

static var _pow5_cache: Dictionary = {}


## Converts a decimal token to the nearest double. The token must match the JSON number grammar
## (-?int frac? exp?). Overflow gives +/-INF, underflow gives +/-0.0.
static func parse(token: String) -> float:
	var negative: bool = token.begins_with("-")
	var body: String = token.substr(1) if negative else token
	var mantissa: String = body
	var exponent: int = 0
	var e_at: int = body.findn("e")
	if e_at >= 0:
		mantissa = body.substr(0, e_at)
		var exponent_text: String = body.substr(e_at + 1)
		var exponent_digits: String = exponent_text.trim_prefix("+").trim_prefix("-").lstrip("0")
		if exponent_digits.length() > 9:
			exponent = 999999999
		elif not exponent_digits.is_empty():
			exponent = exponent_digits.to_int()
		if exponent_text.begins_with("-"):
			exponent = -exponent
	var dot: int = mantissa.find(".")
	var int_part: String = mantissa if dot < 0 else mantissa.substr(0, dot)
	var frac_part: String = "" if dot < 0 else mantissa.substr(dot + 1)
	var digits: String = (int_part + frac_part).lstrip("0")
	var exp10: int = exponent - frac_part.length()
	var stripped: String = digits.rstrip("0")
	exp10 += digits.length() - stripped.length()
	digits = stripped
	var sign_factor: float = -1.0 if negative else 1.0
	if digits.is_empty():
		return sign_factor * 0.0
	var count: int = digits.length()
	if count + exp10 > 310:
		return sign_factor * INF
	if count + exp10 < -324:
		return sign_factor * 0.0
	if count <= _MAX_FAST_DIGITS and exp10 >= -_MAX_FAST_EXPONENT and exp10 <= _MAX_FAST_EXPONENT:
		var exact: float = float(digits.to_int())
		if exp10 >= 0:
			return sign_factor * exact * _POWERS_OF_TEN[exp10]
		return sign_factor * (exact / _POWERS_OF_TEN[-exp10])
	return sign_factor * _parse_slow(digits, exp10)


## The shortest text that parse() reads back to the same 64-bit pattern, as a JSON number.
## The value must be finite. Whole numbers keep a ".0" so that they stay floats ("35.0", "-0.0").
## Returns "" if no such text was found (the caller must refuse to write it).
static func to_text(value: float) -> String:
	if is_nan(value) or is_inf(value):
		return ""
	var text: String = String.num_scientific(value)
	if not ("." in text or "e" in text):
		text += ".0"
	if _bits_of(parse(text)) == _bits_of(value):
		return text
	return ""


# --- Slow path ------------------------------------------------------------------------------


## Absolute value of digits x 10^exp10 for inputs outside the fast path.
static func _parse_slow(digits: String, exp10: int) -> float:
	var big: PackedInt64Array = PackedInt64Array()
	var at: int = 0
	while at < digits.length():
		var chunk: String = digits.substr(at, 7)
		var scale: int = roundi(pow(10.0, chunk.length()))
		big = _big_add_small(_big_mul_small(big, scale), chunk.to_int())
		at += 7
	var left: PackedInt64Array = _big_mul_small(big, 2)
	var right_pow: PackedInt64Array = PackedInt64Array([1])
	if exp10 >= 0:
		left = _big_mul(left, _pow5(exp10))
	else:
		right_pow = _pow5(-exp10)
	var approx: float = absf((digits + "e" + str(exp10)).to_float())
	if is_inf(approx):
		approx = _LARGEST_DOUBLE
	var bits: int = _bits_of(approx)
	var where: int = _side(bits, left, exp10, right_pow)
	if where != 0:
		bits = _search(bits, where, left, exp10, right_pow)
	if bits >= _INF_BITS:
		return INF
	return _from_bits(bits)


## Gallops away from the estimate, then bisects. Positive doubles are ordered like their bit
## patterns. `where` is the side (+1 above, -1 below) on which the answer lies.
static func _search(
	start: int, where: int, left: PackedInt64Array, exp10: int, right_pow: PackedInt64Array
) -> int:
	var step: int = 1
	var inner: int = start
	var outer: int = start + where
	while _side(outer, left, exp10, right_pow) == where:
		inner = outer
		step *= 2
		outer = clampi(start + where * step, 0, _INF_BITS)
		if outer == _INF_BITS:
			break
	var low: int = mini(inner, outer)
	var high: int = maxi(inner, outer)
	while low <= high:
		var mid: int = low + (high - low) / 2
		var side: int = _side(mid, left, exp10, right_pow)
		if side == 0:
			return mid
		if side > 0:
			low = mid + 1
		else:
			high = mid - 1
	return start


## +1 when the decimal rounds above the double with these bits, -1 when below, 0 when it rounds
## to it. The bits _INF_BITS stand for infinity: chosen only at or above the midpoint over the
## largest double.
static func _side(
	bits: int, left: PackedInt64Array, exp10: int, right_pow: PackedInt64Array
) -> int:
	if bits >= _INF_BITS:
		var top: int = _compare(left, exp10, right_pow, 2 * ((1 << 53) - 1) + 1, 971)
		return -1 if top < 0 else 0
	var biased: int = bits >> _MANTISSA_BITS
	var frac: int = bits & ((1 << _MANTISSA_BITS) - 1)
	var mantissa: int = frac if biased == 0 else frac | (1 << _MANTISSA_BITS)
	var power: int = -1074 if biased == 0 else biased - 1075
	var upper: int = _compare(left, exp10, right_pow, 2 * mantissa + 1, power)
	if upper > 0 or (upper == 0 and (mantissa & 1) == 1):
		return 1
	if bits > 0:
		var lower: int
		if frac == 0 and biased > 1:
			lower = _compare(left, exp10, right_pow, 4 * mantissa - 1, power - 1)
		else:
			lower = _compare(left, exp10, right_pow, 2 * mantissa - 1, power)
		if lower < 0 or (lower == 0 and (mantissa & 1) == 1):
			return -1
	return 0


## Compares 2 x value (left x 2^exp10, divided by right_pow) with c x 2^power.
static func _compare(
	left: PackedInt64Array, exp10: int, right_pow: PackedInt64Array, c: int, power: int
) -> int:
	var lhs: PackedInt64Array = left
	var rhs: PackedInt64Array = _big_from_int(c)
	if exp10 < 0:
		rhs = _big_mul(rhs, right_pow)
	var shift: int = exp10 - power
	if shift >= 0:
		lhs = _big_shl(lhs, shift)
	else:
		rhs = _big_shl(rhs, -shift)
	return _big_cmp(lhs, rhs)


# --- Bits -----------------------------------------------------------------------------------


static func _bits_of(value: float) -> int:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	return bytes.decode_s64(0)


static func _from_bits(bits: int) -> float:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(8)
	bytes.encode_s64(0, bits)
	return bytes.decode_double(0)


# --- Big integers: little-endian 24-bit limbs in a PackedInt64Array ---------------------------


static func _big_from_int(value: int) -> PackedInt64Array:
	var result: PackedInt64Array = PackedInt64Array()
	var rest: int = value
	while rest > 0:
		result.append(rest & _LIMB_MASK)
		rest >>= _LIMB_BITS
	return result


static func _big_mul_small(a: PackedInt64Array, factor: int) -> PackedInt64Array:
	var result: PackedInt64Array = a.duplicate()
	var carry: int = 0
	for i: int in result.size():
		var product: int = result[i] * factor + carry
		result[i] = product & _LIMB_MASK
		carry = product >> _LIMB_BITS
	while carry > 0:
		result.append(carry & _LIMB_MASK)
		carry >>= _LIMB_BITS
	return result


static func _big_add_small(a: PackedInt64Array, value: int) -> PackedInt64Array:
	var result: PackedInt64Array = a.duplicate()
	var index: int = 0
	var carry: int = value
	while carry > 0:
		if index == result.size():
			result.append(0)
		var total: int = result[index] + carry
		result[index] = total & _LIMB_MASK
		carry = total >> _LIMB_BITS
		index += 1
	return result


static func _big_mul(a: PackedInt64Array, b: PackedInt64Array) -> PackedInt64Array:
	var result: PackedInt64Array = PackedInt64Array()
	result.resize(a.size() + b.size())
	for i: int in a.size():
		var carry: int = 0
		var a_limb: int = a[i]
		for j: int in b.size():
			var total: int = result[i + j] + a_limb * b[j] + carry
			result[i + j] = total & _LIMB_MASK
			carry = total >> _LIMB_BITS
		var k: int = i + b.size()
		while carry > 0:
			var spill: int = result[k] + carry
			result[k] = spill & _LIMB_MASK
			carry = spill >> _LIMB_BITS
			k += 1
	return _big_trim(result)


static func _big_shl(a: PackedInt64Array, shift: int) -> PackedInt64Array:
	var whole_limbs: int = shift / _LIMB_BITS
	var bits: int = shift % _LIMB_BITS
	var result: PackedInt64Array = PackedInt64Array()
	result.resize(whole_limbs)
	result.append_array(a)
	return _big_mul_small(result, 1 << bits)


static func _big_trim(a: PackedInt64Array) -> PackedInt64Array:
	var used: int = a.size()
	while used > 0 and a[used - 1] == 0:
		used -= 1
	if used != a.size():
		a.resize(used)
	return a


static func _big_cmp(a: PackedInt64Array, b: PackedInt64Array) -> int:
	var left: PackedInt64Array = _big_trim(a.duplicate())
	var right: PackedInt64Array = _big_trim(b.duplicate())
	if left.size() != right.size():
		return 1 if left.size() > right.size() else -1
	for i: int in range(left.size() - 1, -1, -1):
		if left[i] != right[i]:
			return 1 if left[i] > right[i] else -1
	return 0


## 5^n, cached.
static func _pow5(n: int) -> PackedInt64Array:
	if _pow5_cache.has(n):
		return _pow5_cache[n]
	var result: PackedInt64Array = PackedInt64Array([1])
	var left: int = n
	while left >= 13:
		result = _big_mul_small(result, 1220703125)
		left -= 13
	var factor: int = 1
	for i: int in left:
		factor *= 5
	result = _big_mul_small(result, factor)
	_pow5_cache[n] = result
	return result
