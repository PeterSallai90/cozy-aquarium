extends GdUnitTestSuite


func _assert_refused(text: String) -> void:
	var json: SaveJson = SaveJson.new()
	var error: Error = json.parse(text)
	assert_int(error).is_not_equal(OK)
	assert_str(json.error_message).is_not_empty()


static func _quoted(inner: String) -> String:
	return '"' + inner + '"'


# --- strict grammar: refusals ---


func test_refuses_empty_and_blank_text() -> void:
	_assert_refused("")
	_assert_refused("   \n")


func test_refuses_trailing_commas() -> void:
	_assert_refused("[1,]")
	_assert_refused("[1, 2,]")
	_assert_refused('{"a": 1,}')


func test_refuses_missing_values_and_commas() -> void:
	_assert_refused("[,1]")
	_assert_refused("[1 2]")
	_assert_refused('{"a" 1}')
	_assert_refused('{"a": }')
	_assert_refused('{"a": 1 "b": 2}')
	_assert_refused("[1")
	_assert_refused('{"a": 1')


func test_refuses_unquoted_and_single_quoted_keys_and_strings() -> void:
	_assert_refused("{a: 1}")
	_assert_refused("{'a': 1}")
	_assert_refused("'abc'")
	_assert_refused("{1: 1}")


func test_refuses_raw_control_characters_in_strings() -> void:
	for code: int in range(1, 0x20):
		_assert_refused(_quoted("a" + char(code) + "b"))


func test_refuses_raw_control_characters_in_keys() -> void:
	_assert_refused('{"a' + char(0x0A) + '": 1}')
	_assert_refused('{"a' + char(0x09) + '": 1}')


func test_refuses_invalid_escapes() -> void:
	for inner: String in ["\\v", "\\x41", "\\a", "\\'", "\\0", "\\U0041", "\\ ", "\\"]:
		_assert_refused(_quoted(inner))


func test_refuses_short_or_non_hex_unicode_escapes() -> void:
	for inner: String in ["\\u", "\\u12", "\\u123", "\\uZZZZ", "\\u12G4", "\\u-123"]:
		_assert_refused(_quoted(inner))


func test_refuses_lone_surrogates() -> void:
	_assert_refused(_quoted("\\ud800"))
	_assert_refused(_quoted("\\uDBFF"))
	_assert_refused(_quoted("\\udc00"))
	_assert_refused(_quoted("\\uDFFF"))
	_assert_refused(_quoted("\\ud800x"))
	_assert_refused(_quoted("\\ud800\\u0041"))
	_assert_refused(_quoted("\\ud800\\ud800"))
	_assert_refused(_quoted("\\udc00\\ud800"))


func test_refuses_unicode_escape_for_nul() -> void:
	_assert_refused(_quoted("\\u0000"))
	_assert_refused(_quoted("a\\u0000b"))
	_assert_refused('{"a\\u0000": 1}')


func test_refuses_unterminated_string() -> void:
	_assert_refused('"abc')
	_assert_refused('"abc\\"')


func test_refuses_leading_zeros() -> void:
	_assert_refused("01")
	_assert_refused("-01")
	_assert_refused("00")
	_assert_refused("[007]")
	_assert_refused("00.5")


func test_refuses_malformed_numbers() -> void:
	for text: String in ["+1", ".5", "1.", "-", "1e", "1e+", "--1", "1.5.2", "0x10", "1_0", "- 1"]:
		_assert_refused(text)


func test_refuses_nan_and_infinity_tokens() -> void:
	for text: String in ["NaN", "nan", "Infinity", "-Infinity", "inf", "[NaN]", '{"a": Infinity}']:
		_assert_refused(text)


func test_refuses_wrong_case_and_partial_literals() -> void:
	for text: String in ["True", "FALSE", "Null", "nul", "tru", "truee", "nulll"]:
		_assert_refused(text)


func test_refuses_trailing_text() -> void:
	_assert_refused("{} x")
	_assert_refused("[] []")
	_assert_refused("1 2")
	_assert_refused("{}}")
	_assert_refused("[]]")
	_assert_refused("true false")
	_assert_refused("{}\n\n,")


func test_refuses_comments() -> void:
	_assert_refused("// c\n{}")
	_assert_refused("{} // c")
	_assert_refused("/* c */ {}")
	_assert_refused("[1, /* c */ 2]")


func test_refuses_non_json_whitespace() -> void:
	_assert_refused(char(0x0C) + "{}")
	_assert_refused("{}" + char(0x0B))
	_assert_refused("{}" + char(0xA0))
	_assert_refused(char(0xFEFF) + "{}")
