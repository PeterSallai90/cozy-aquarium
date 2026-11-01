class_name SaveRules
extends RefCounted
## Pure rule and conversion helpers of the save format. Used by both the reader and the writer,
## so the two cannot drift apart. Static only, no I/O.

## Format cap for each side of the heightmap.
const MAX_HEIGHTMAP_SIDE: int = 1024
const MAX_VARIANT: int = 255
const UID_LENGTH: int = 8
const STAMP_LENGTH: int = 20
const _DAYS_IN_MONTH: Array[int] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

static var _base64_bad_character: RegEx = RegEx.create_from_string("[^A-Za-z0-9+/=]")


## True for a String of exactly 8 lowercase hex characters.
static func is_uid(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var text: String = value
	if text.length() != UID_LENGTH:
		return false
	for index: int in UID_LENGTH:
		if not _is_hex_digit(text.unicode_at(index), false):
			return false
	return true


## True for YYYY-MM-DDTHH:MM:SSZ with a real Gregorian date and time.
static func is_stamp(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var text: String = value
	if text.length() != STAMP_LENGTH:
		return false
	var separators: Dictionary = {4: "-", 7: "-", 10: "T", 13: ":", 16: ":", 19: "Z"}
	for position: int in separators:
		if text.substr(position, 1) != separators[position]:
			return false
	var year: int = _digits(text, 0, 4)
	var month: int = _digits(text, 5, 2)
	var day: int = _digits(text, 8, 2)
	var hour: int = _digits(text, 11, 2)
	var minute: int = _digits(text, 14, 2)
	var second: int = _digits(text, 17, 2)
	if year < 0 or month < 1 or month > 12 or day < 1 or hour < 0 or minute < 0 or second < 0:
		return false
	return day <= _days_in_month(year, month) and hour <= 23 and minute <= 59 and second <= 59


## True for an int or float that is finite. A bool is never a number.
static func is_number(value: Variant) -> bool:
	var value_type: int = typeof(value)
	if value_type == TYPE_INT:
		return true
	if value_type == TYPE_FLOAT:
		var number: float = value
		return is_finite(number)
	return false


## True for a number equal to its floor.
static func is_whole(value: Variant) -> bool:
	if not is_number(value):
		return false
	var number: float = value
	return number == floorf(number)


## "#RRGGBB" in uppercase, or "#RRGGBBAA" when the alpha byte is not 255. Components are
## clamped to 0..1 and rounded to 8 bits. The components must be finite.
static func colour_to_hex(colour: Color) -> String:
	var red: int = _byte(colour.r)
	var green: int = _byte(colour.g)
	var blue: int = _byte(colour.b)
	var alpha: int = _byte(colour.a)
	if alpha == 255:
		return "#%02X%02X%02X" % [red, green, blue]
	return "#%02X%02X%02X%02X" % [red, green, blue, alpha]


## True for "#" plus exactly 6 or 8 hex digits, in either case.
static func is_hex_colour(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var text: String = value
	if not text.begins_with("#") or (text.length() != 7 and text.length() != 9):
		return false
	for index: int in range(1, text.length()):
		if not _is_hex_digit(text.unicode_at(index), true):
			return false
	return true


## The colour of a string that passed is_hex_colour(). Alpha is 255 for 6 digits.
static func hex_to_colour(hex: String) -> Color:
	var alpha: int = 255
	if hex.length() == 9:
		alpha = hex.substr(7, 2).hex_to_int()
	return Color8(
		hex.substr(1, 2).hex_to_int(),
		hex.substr(3, 2).hex_to_int(),
		hex.substr(5, 2).hex_to_int(),
		alpha
	)


## Raw little-endian float32 values as base64. Flat (no values) gives "".
static func heightmap_to_base64(values: PackedFloat32Array) -> String:
	if values.is_empty():
		return ""
	return Marshalls.raw_to_base64(values.to_byte_array())


## The number of bytes a base64 text decodes to, or -1 when the text is malformed. Checks the
## character set, the length and the padding without decoding, so the engine decoder never sees
## bad input. Empty text gives 0.
static func base64_byte_length(text: String) -> int:
	var length: int = text.length()
	if length % 4 != 0:
		return -1
	if length == 0:
		return 0
	if _base64_bad_character.search(text) != null:
		return -1
	var padding: int = 0
	if text.ends_with("=="):
		padding = 2
	elif text.ends_with("="):
		padding = 1
	if text.count("=") != padding:
		return -1
	return length / 4 * 3 - padding


static func _byte(component: float) -> int:
	return roundi(clampf(component, 0.0, 1.0) * 255.0)


static func _is_hex_digit(code: int, allow_upper: bool) -> bool:
	if code >= 48 and code <= 57:
		return true
	if code >= 97 and code <= 102:
		return true
	return allow_upper and code >= 65 and code <= 70


## The number made of `count` digits from `start`, or -1 if any character is not a digit.
static func _digits(text: String, start: int, count: int) -> int:
	var result: int = 0
	for index: int in range(start, start + count):
		var code: int = text.unicode_at(index)
		if code < 48 or code > 57:
			return -1
		result = result * 10 + (code - 48)
	return result


static func _days_in_month(year: int, month: int) -> int:
	if month == 2 and ((year % 4 == 0 and year % 100 != 0) or year % 400 == 0):
		return 29
	return _DAYS_IN_MONTH[month - 1]
