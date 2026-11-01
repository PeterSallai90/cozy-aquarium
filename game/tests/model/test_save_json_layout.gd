extends GdUnitTestSuite


static func _parse(text: String) -> SaveJson:
	var json: SaveJson = SaveJson.new()
	var code: Error = json.parse(text)
	if code == ERR_BUG:
		return null
	return json


static func _quoted(inner: String) -> String:
	return '"' + inner + '"'


# --- writer: layout ---


func test_layout_scalars() -> void:
	assert_str(SaveJson.stringify(null)).is_equal("null")
	assert_str(SaveJson.stringify(true)).is_equal("true")
	assert_str(SaveJson.stringify(false)).is_equal("false")
	assert_str(SaveJson.stringify(42)).is_equal("42")
	assert_str(SaveJson.stringify(-7)).is_equal("-7")
	assert_str(SaveJson.stringify("x")).is_equal('"x"')


func test_layout_empty_containers() -> void:
	assert_str(SaveJson.stringify({})).is_equal("{}")
	assert_str(SaveJson.stringify([])).is_equal("[]")
	assert_str(SaveJson.stringify({"a": [], "b": {}})).is_equal('{\n  "a": [],\n  "b": {}\n}')


func test_layout_has_no_trailing_newline_or_carriage_return() -> void:
	var text: String = SaveJson.stringify({"a": [1, 2], "b": {"c": "d"}})
	assert_bool(text.ends_with("\n")).is_false()
	assert_bool(text.contains("\r")).is_false()


func test_layout_equals_engine_stringify_for_plain_data() -> void:
	var data: Dictionary = {
		"zebra": 1,
		"format_version": 1,
		"name": "Cozy \u00e9 \U0001F600 / tank",
		"flag": true,
		"off": false,
		"nothing": null,
		"empty_list": [],
		"empty_map": {},
		"list": [1, "two", [3, [4, []]], {"five": 5, "alpha": {}}],
		"nested": {"b": {"d": [{"x": 1}, {"y": [true, null]}], "c": 2}, "a": -3},
		"text": 'line\nbreak\ttab "quoted" back\\slash' + char(0x01) + char(0x1F),
	}
	assert_str(SaveJson.stringify(data)).is_equal(JSON.stringify(data, "  ", false))


func test_layout_equals_engine_stringify_for_arrays_and_scalars() -> void:
	var samples: Array = [[], [1], [[], {}], [[[1, 2], [3]], "x"], "text", 5, true, null]
	for sample: Variant in samples:
		assert_str(SaveJson.stringify(sample)).is_equal(JSON.stringify(sample, "  ", false))


func test_layout_keeps_insertion_order() -> void:
	var data: Dictionary = {}
	for key: String in ["m", "z", "a", "q", "b"]:
		data[key] = 1
	assert_str(SaveJson.stringify(data)).is_equal(
		'{\n  "m": 1,\n  "z": 1,\n  "a": 1,\n  "q": 1,\n  "b": 1\n}'
	)


func test_layout_exact_text() -> void:
	var data: Dictionary = {"a": [1, {"b": null}], "c": "d"}
	var expected: String = (
		"{\n"
		+ '  "a": [\n'
		+ "    1,\n"
		+ "    {\n"
		+ '      "b": null\n'
		+ "    }\n"
		+ "  ],\n"
		+ '  "c": "d"\n'
		+ "}"
	)
	assert_str(SaveJson.stringify(data)).is_equal(expected)


func test_stringify_floats_use_decimal_double_text() -> void:
	var data: Dictionary = {"r": 0.1, "s": 1.0 / 3.0, "w": 35.0, "z": -0.0}
	var expected: String = (
		'{\n  "r": %s,\n  "s": %s,\n  "w": %s,\n  "z": %s\n}'
		% [
			DecimalDouble.to_text(0.1),
			DecimalDouble.to_text(1.0 / 3.0),
			DecimalDouble.to_text(35.0),
			DecimalDouble.to_text(-0.0),
		]
	)
	assert_str(SaveJson.stringify(data)).is_equal(expected)


func test_stringified_floats_read_back_bit_exact() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 11
	var values: Array = []
	for _i: int in range(200):
		values.append(rng.randf_range(-TAU, TAU))
	var json: SaveJson = _parse(SaveJson.stringify(values))
	assert_str(json.error_message).is_empty()
	var read: Array = json.data
	assert_int(read.size()).is_equal(values.size())
	for i: int in range(values.size()):
		var expected: float = values[i]
		var actual: float = read[i]
		assert_float(actual).is_equal(expected)


func test_ints_are_written_as_integers() -> void:
	var data: Array = [1, 20, 0, -5, 9007199254740993]
	assert_str(SaveJson.stringify(data)).is_equal(JSON.stringify(data, "  ", false))
