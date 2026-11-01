extends GdUnitTestSuite

const MIB: int = 1024 * 1024


static func _parse(text: String) -> SaveJson:
	var json: SaveJson = SaveJson.new()
	json.parse(text)
	return json


static func _quoted(inner: String) -> String:
	return '"' + inner + '"'


static func _nested(open: String, close: String, depth: int) -> String:
	return open.repeat(depth) + close.repeat(depth)


func _assert_refused(text: String) -> void:
	var json: SaveJson = SaveJson.new()
	var error: Error = json.parse(text)
	assert_int(error).is_not_equal(OK)
	assert_str(json.error_message).is_not_empty()


func _assert_parses_to(text: String, expected: Variant) -> void:
	var json: SaveJson = SaveJson.new()
	var error: Error = json.parse(text)
	assert_int(error).is_equal(OK)
	assert_str(json.error_message).is_empty()
	assert_that(json.data).is_equal(expected)


# --- accepted input ---


func test_parses_scalars_and_literals() -> void:
	_assert_parses_to("true", true)
	_assert_parses_to("false", false)
	_assert_parses_to("null", null)
	_assert_parses_to('"abc"', "abc")
	_assert_parses_to("[]", [])
	_assert_parses_to("{}", {})


func test_every_number_is_a_float() -> void:
	var json: SaveJson = _parse("[1, -2, 3.5, 1e2]")
	var items: Array = json.data
	assert_int(items.size()).is_equal(4)
	for item: Variant in items:
		assert_int(typeof(item)).is_equal(TYPE_FLOAT)
	assert_float(items[3]).is_equal(100.0)


func test_numbers_are_read_exactly() -> void:
	var json: SaveJson = _parse("[0.1, 0.3333333333333333, 9007199254740993]")
	var items: Array = json.data
	assert_float(items[0]).is_equal(0.1)
	assert_float(items[1]).is_equal(1.0 / 3.0)
	assert_float(items[2]).is_equal(9007199254740992.0)


func test_negative_zero_keeps_its_sign() -> void:
	var json: SaveJson = _parse("-0")
	var value: float = json.data
	assert_float(value).is_equal(0.0)
	assert_bool(1.0 / value < 0.0).is_true()


func test_huge_exponent_gives_infinity() -> void:
	var json: SaveJson = _parse("[1e999, -1e999]")
	var items: Array = json.data
	assert_float(items[0]).is_equal(INF)
	assert_float(items[1]).is_equal(-INF)


func test_whitespace_between_tokens_is_allowed() -> void:
	_assert_parses_to(' \t\r\n{ "a" :\n[ 1 ,\t2 ] } \n', {"a": [1.0, 2.0]})


func test_valid_escapes_are_decoded() -> void:
	_assert_parses_to(_quoted('\\" \\\\ \\/ \\b \\f \\n \\r \\t'), '" \\ / \b \f \n \r \t')


func test_unicode_escape_accepts_both_hex_cases() -> void:
	_assert_parses_to(_quoted("\\u00e9\\u00E9"), "\u00e9\u00e9")
	_assert_parses_to(_quoted("\\u001f"), char(0x1F))
	_assert_parses_to(_quoted("\\u001F"), char(0x1F))


func test_surrogate_pair_gives_one_code_point() -> void:
	var json: SaveJson = _parse(_quoted("\\uD83D\\uDE00"))
	var text: String = json.data
	assert_int(text.length()).is_equal(1)
	assert_int(text.unicode_at(0)).is_equal(0x1F600)


func test_raw_non_ascii_and_del_are_accepted() -> void:
	var text: String = "\u00e9\u20ac\U0001F600" + char(0x7F)
	_assert_parses_to(_quoted(text), text)


func test_duplicate_key_keeps_the_last_value() -> void:
	_assert_parses_to('{"a": 1, "b": 2, "a": 3}', {"a": 3.0, "b": 2.0})


func test_parse_can_be_reused_after_a_failure() -> void:
	var json: SaveJson = SaveJson.new()
	assert_int(json.parse("[1,]")).is_not_equal(OK)
	assert_str(json.error_message).is_not_empty()
	assert_int(json.parse("[1]")).is_equal(OK)
	assert_str(json.error_message).is_empty()
	assert_that(json.data).is_equal([1.0])


func test_sixteen_mib_string_parses() -> void:
	var payload: String = "A".repeat(16 * MIB)
	var json: SaveJson = _parse(_quoted(payload))
	assert_str(json.error_message).is_empty()
	var text: String = json.data
	assert_int(text.length()).is_equal(16 * MIB)


# --- depth limit ---


func test_depth_64_is_accepted() -> void:
	assert_int(SaveJson.MAX_DEPTH).is_equal(64)
	assert_int(SaveJson.new().parse(_nested("[", "]", 64))).is_equal(OK)
	assert_int(SaveJson.new().parse(_nested("[", "]", 1))).is_equal(OK)


func test_depth_65_is_refused() -> void:
	_assert_refused(_nested("[", "]", 65))


func test_depth_64_and_65_for_objects() -> void:
	var ok_text: String = '{"a":'.repeat(63) + "{}" + "}".repeat(63)
	var bad_text: String = '{"a":'.repeat(64) + "{}" + "}".repeat(64)
	assert_int(SaveJson.new().parse(ok_text)).is_equal(OK)
	_assert_refused(bad_text)


func test_depth_counts_mixed_arrays_and_objects() -> void:
	var ok_text: String = '[{"a":'.repeat(31) + "[{}]" + "}]".repeat(31)
	var bad_text: String = '[{"a":'.repeat(32) + "[]" + "}]".repeat(32)
	assert_int(SaveJson.new().parse(ok_text)).is_equal(OK)
	_assert_refused(bad_text)


func test_depth_2000_is_refused_without_crashing() -> void:
	_assert_refused(_nested("[", "]", 2000))
	_assert_refused('{"a":'.repeat(2000) + "{}" + "}".repeat(2000))


func test_unclosed_deep_nesting_is_refused() -> void:
	_assert_refused("[".repeat(5000))
