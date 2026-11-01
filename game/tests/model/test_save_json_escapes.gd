extends GdUnitTestSuite


static func _parse(text: String) -> SaveJson:
	var json: SaveJson = SaveJson.new()
	json.parse(text)
	return json


static func _quoted(inner: String) -> String:
	return '"' + inner + '"'


# --- writer: escaping rule ---


func test_stringify_short_escapes() -> void:
	assert_str(SaveJson.stringify('"')).is_equal('"\\""')
	assert_str(SaveJson.stringify("\\")).is_equal('"\\\\"')
	assert_str(SaveJson.stringify(char(0x08))).is_equal('"\\b"')
	assert_str(SaveJson.stringify(char(0x09))).is_equal('"\\t"')
	assert_str(SaveJson.stringify(char(0x0A))).is_equal('"\\n"')
	assert_str(SaveJson.stringify(char(0x0C))).is_equal('"\\f"')
	assert_str(SaveJson.stringify(char(0x0D))).is_equal('"\\r"')


func test_stringify_other_control_characters_use_uppercase_u_escape() -> void:
	assert_str(SaveJson.stringify(char(0x01))).is_equal('"\\u0001"')
	assert_str(SaveJson.stringify(char(0x0B))).is_equal('"\\u000B"')
	assert_str(SaveJson.stringify(char(0x0E))).is_equal('"\\u000E"')
	assert_str(SaveJson.stringify(char(0x1A))).is_equal('"\\u001A"')
	assert_str(SaveJson.stringify(char(0x1F))).is_equal('"\\u001F"')


func test_stringify_never_writes_the_v_escape() -> void:
	assert_bool(SaveJson.stringify(char(0x0B)).contains("\\v")).is_false()


func test_stringify_escapes_every_control_character_by_the_rule() -> void:
	var short_forms: Dictionary = {8: "\\b", 9: "\\t", 10: "\\n", 12: "\\f", 13: "\\r"}
	for code: int in range(1, 0x20):
		var expected: String = "\\u%04X" % code
		if short_forms.has(code):
			expected = short_forms[code]
		assert_str(SaveJson.stringify(char(code))).is_equal(_quoted(expected))


func test_stringify_leaves_everything_else_raw() -> void:
	var raw: String = "/ " + char(0x7F) + "\u00e9\u20ac\U0001F600~"
	assert_str(SaveJson.stringify(raw)).is_equal(_quoted(raw))


func test_stringify_escapes_keys_like_values() -> void:
	var text: String = SaveJson.stringify({'a"' + char(0x01): 1})
	assert_str(text).contains('"a\\"\\u0001": 1')


func test_stringify_has_no_raw_control_byte_except_layout_line_feed() -> void:
	var everything: String = ""
	for code: int in range(1, 0x20):
		everything += char(code)
	var text: String = SaveJson.stringify({everything: [everything, 1, true, null]})
	for byte: int in text.to_utf8_buffer():
		assert_bool(byte >= 0x20 or byte == 0x0A).is_true()


func test_escaped_strings_round_trip_through_the_reader() -> void:
	var everything: String = '"\\/'
	for code: int in range(1, 0x20):
		everything += char(code)
	everything += char(0x7F) + "\u00e9\U0001F600"
	var json: SaveJson = _parse(SaveJson.stringify({everything: everything}))
	assert_str(json.error_message).is_empty()
	assert_that(json.data).is_equal({everything: everything})


func test_godot_parser_reads_the_escapes_back() -> void:
	var original: String = "a" + char(0x01) + char(0x0B) + char(0x1F) + '"\\\n'
	var parsed: Variant = JSON.parse_string(SaveJson.stringify(original))
	assert_that(parsed).is_equal(original)


func test_stringify_accepts_string_names() -> void:
	assert_str(SaveJson.stringify(&"abc")).is_equal('"abc"')
	assert_str(SaveJson.stringify({&"k": &"v"})).is_equal('{\n  "k": "v"\n}')
