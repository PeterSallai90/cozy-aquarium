extends GdUnitTestSuite

const TABLE_PATH: String = "res://tests/fixtures/numbers/decimal_to_double.txt"
const MIN_TABLE_LINES: int = 250
const NUMBER_GRAMMAR: String = "^-?(?:0|[1-9][0-9]*)(?:[.][0-9]+)?(?:[eE][+-]?[0-9]+)?$"


static func _bytes_of(value: float) -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	return bytes


static func _hex_of(value: float) -> String:
	var bytes: PackedByteArray = _bytes_of(value)
	return "%08x%08x" % [bytes.decode_u32(4), bytes.decode_u32(0)]


static func _from_halves(high: int, low: int) -> float:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(8)
	bytes.encode_u32(0, low)
	bytes.encode_u32(4, high)
	return bytes.decode_double(0)


static func _is_finite_bits(high: int) -> bool:
	return (high & 0x7FF00000) != 0x7FF00000


func _table_lines() -> PackedStringArray:
	var file: FileAccess = FileAccess.open(TABLE_PATH, FileAccess.READ)
	assert_object(file).is_not_null()
	var text: String = file.get_as_text()
	var lines: PackedStringArray = PackedStringArray()
	for line: String in text.split("\n"):
		if not line.is_empty():
			lines.append(line)
	return lines


func test_fixture_table_is_present_and_large_enough() -> void:
	assert_int(_table_lines().size()).is_greater_equal(MIN_TABLE_LINES)


func test_fixture_table_uses_lf_line_endings() -> void:
	var file: FileAccess = FileAccess.open(TABLE_PATH, FileAccess.READ)
	assert_object(file).is_not_null()
	assert_bool(file.get_as_text().contains("\r")).is_false()


func test_table_decimals_parse_to_exact_ieee_bits() -> void:
	var wrong: PackedStringArray = PackedStringArray()
	for line: String in _table_lines():
		var parts: PackedStringArray = line.split(" ")
		assert_int(parts.size()).is_equal(2)
		var got: String = _hex_of(DecimalDouble.parse(parts[0]))
		if got != parts[1]:
			wrong.append("%s expected %s got %s" % [parts[0], parts[1], got])
	assert_array(wrong).is_empty()


func test_parse_simple_values() -> void:
	assert_float(DecimalDouble.parse("0.1")).is_equal(0.1)
	assert_float(DecimalDouble.parse("-2.5")).is_equal(-2.5)
	assert_float(DecimalDouble.parse("1e3")).is_equal(1000.0)
	assert_float(DecimalDouble.parse("35")).is_equal(35.0)
	assert_str(_hex_of(DecimalDouble.parse("0.3333333333333333"))).is_equal(_hex_of(1.0 / 3.0))


func test_parse_negative_zero_keeps_sign() -> void:
	assert_str(_hex_of(DecimalDouble.parse("-0.0"))).is_equal("8000000000000000")
	assert_str(_hex_of(DecimalDouble.parse("-0"))).is_equal("8000000000000000")
	assert_str(_hex_of(DecimalDouble.parse("0"))).is_equal("0000000000000000")


func test_parse_overflow_gives_infinity() -> void:
	assert_float(DecimalDouble.parse("1e400")).is_equal(INF)
	assert_float(DecimalDouble.parse("-1e400")).is_equal(-INF)
	assert_float(DecimalDouble.parse("1.7976931348623159e308")).is_equal(INF)


func test_parse_underflow_gives_zero() -> void:
	assert_str(_hex_of(DecimalDouble.parse("1e-400"))).is_equal("0000000000000000")
	assert_str(_hex_of(DecimalDouble.parse("-1e-400"))).is_equal("8000000000000000")
	assert_str(_hex_of(DecimalDouble.parse("2.4703282292062327e-324"))).is_equal("0000000000000000")


func test_parse_smallest_subnormal_and_largest_double() -> void:
	assert_str(_hex_of(DecimalDouble.parse("4.9e-324"))).is_equal("0000000000000001")
	assert_str(_hex_of(DecimalDouble.parse("2.4703282292062328e-324"))).is_equal("0000000000000001")
	assert_str(_hex_of(DecimalDouble.parse("1.7976931348623157e308"))).is_equal("7fefffffffffffff")
	assert_str(_hex_of(DecimalDouble.parse("1.7976931348623158e308"))).is_equal("7fefffffffffffff")


func test_parse_halfway_rounds_to_even() -> void:
	assert_str(_hex_of(DecimalDouble.parse("9007199254740993"))).is_equal("4340000000000000")
	assert_str(_hex_of(DecimalDouble.parse("9007199254740995"))).is_equal("4340000000000002")


func test_parse_very_long_mantissa() -> void:
	var digits: String = "1." + "0".repeat(400) + "1"
	assert_str(_hex_of(DecimalDouble.parse(digits))).is_equal("3ff0000000000000")
	var above: String = (
		"1.00000000000000011102230246251565404236316680908203125" + "0".repeat(300) + "1"
	)
	assert_str(_hex_of(DecimalDouble.parse(above))).is_equal("3ff0000000000001")


func test_parse_random_decimals_match_to_text_of_same_double() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 77
	for _i: int in range(300):
		var value: float = rng.randf_range(-1000.0, 1000.0)
		assert_str(_hex_of(DecimalDouble.parse(str(value)))).is_equal(_hex_of(float(str(value))))


func test_to_text_round_trips_random_bit_patterns() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 2026
	var wrong: PackedStringArray = PackedStringArray()
	var count: int = 0
	while count < 2000:
		var high: int = rng.randi()
		if not _is_finite_bits(high):
			continue
		var value: float = _from_halves(high, rng.randi())
		count += 1
		var text: String = DecimalDouble.to_text(value)
		if text.is_empty() or _hex_of(DecimalDouble.parse(text)) != _hex_of(value):
			wrong.append("%s for %s" % [text, _hex_of(value)])
	assert_array(wrong).is_empty()


func test_to_text_round_trips_test_shaped_values() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 2026
	var wrong: PackedStringArray = PackedStringArray()
	for _i: int in range(600):
		var values: Array[float] = [
			rng.randf_range(-TAU, TAU), rng.randf_range(0.1, 4.0), rng.randf() * 1e-3
		]
		for value: float in values:
			var text: String = DecimalDouble.to_text(value)
			if text.is_empty() or _hex_of(DecimalDouble.parse(text)) != _hex_of(value):
				wrong.append("%s for %s" % [text, _hex_of(value)])
	assert_array(wrong).is_empty()


func test_to_text_round_trips_edge_values() -> void:
	var edges: Array[float] = [
		0.0,
		-0.0,
		1.0,
		-1.0,
		0.1,
		1.0 / 3.0,
		5e-324,
		2.2250738585072014e-308,
		1.7976931348623157e308,
		-1.7976931348623157e308,
		9007199254740992.0,
		1e22,
		1e23,
		1e-7,
		123456789.123456789,
	]
	for value: float in edges:
		var text: String = DecimalDouble.to_text(value)
		assert_str(text).is_not_empty()
		assert_str(_hex_of(DecimalDouble.parse(text))).is_equal(_hex_of(value))


func test_to_text_is_a_json_number() -> void:
	var grammar: RegEx = RegEx.create_from_string(NUMBER_GRAMMAR)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	for _i: int in range(500):
		var high: int = rng.randi()
		if not _is_finite_bits(high):
			continue
		var text: String = DecimalDouble.to_text(_from_halves(high, rng.randi()))
		assert_object(grammar.search(text)).is_not_null()


func test_to_text_keeps_a_fraction_marker_for_whole_numbers() -> void:
	assert_str(DecimalDouble.to_text(35.0)).is_equal("35.0")
	assert_str(DecimalDouble.to_text(1.0)).is_equal("1.0")
	assert_str(DecimalDouble.to_text(0.0)).is_equal("0.0")


func test_to_text_writes_negative_zero_with_sign() -> void:
	assert_str(DecimalDouble.to_text(-0.0)).is_equal("-0.0")


func test_to_text_is_shortest_for_common_values() -> void:
	assert_str(DecimalDouble.to_text(0.1)).is_equal("0.1")
	assert_str(DecimalDouble.to_text(-2.5)).is_equal("-2.5")
	assert_str(DecimalDouble.to_text(1.0 / 3.0)).is_equal("0.3333333333333333")
