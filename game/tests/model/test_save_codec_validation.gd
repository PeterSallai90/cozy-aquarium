# gdlint: disable=max-public-methods
extends GdUnitTestSuite

const ModelState := preload("res://tests/helpers/model_state.gd")
const SaveFixtures := preload("res://tests/helpers/save_fixtures.gd")

const NOW := "2026-11-01T12:00:00Z"

const ITEM := ["items", 0]
const FISH := ["fish", 0]
const SUBSTRATE := ["substrate"]
const HEIGHTMAP := ["substrate", "heightmap"]


func _path(base: Array, key: Variant) -> Array:
	var result: Array = base.duplicate()
	result.append(key)
	return result


func _decode(text: String) -> SaveResult:
	return SaveCodec.new().decode(text, NOW)


## Returns one line per row whose decode result is not the expected kind.
func _mismatches(rows: Array, expected: SaveResult.Kind) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	for row: Array in rows:
		var result: SaveResult = _decode(row[1])
		if result.kind != expected:
			failures.append("%s: kind %d, expected %d" % [row[0], result.kind, expected])
		elif expected != SaveResult.Kind.OK and result.model != null:
			failures.append("%s: failed result carries a model" % row[0])
	return failures


func _row(label: String, path: Array, value: Variant) -> Array:
	return [label, SaveFixtures.to_text(SaveFixtures.changed(path, value))]


func _raw_row(label: String, path: Array, raw: String) -> Array:
	return [label, SaveFixtures.changed_raw(path, raw)]


func _bytes_kind(bytes: PackedByteArray) -> int:
	return SaveCodec.new().decode_bytes(bytes, NOW).kind


# --- unparseable files ---------------------------------------------------------------------


func test_unparseable_bytes_are_damaged() -> void:
	var golden: String = SaveFixtures.read_text(SaveFixtures.GOLDEN_PATH)
	var cases: Array = [
		["empty", PackedByteArray()],
		["whitespace only", " \n\t ".to_utf8_buffer()],
		["truncated mid JSON", golden.substr(0, golden.length() / 2).to_utf8_buffer()],
		["truncated after a key", '{"format_version": 1, "name":'.to_utf8_buffer()],
		["not json", "not json".to_utf8_buffer()],
		["top level array", "[1]".to_utf8_buffer()],
		["top level array of objects", '[{"format_version": 1}]'.to_utf8_buffer()],
		["top level number", "42".to_utf8_buffer()],
		["top level string", '"format_version"'.to_utf8_buffer()],
		["top level true", "true".to_utf8_buffer()],
		["top level null", "null".to_utf8_buffer()],
		["trailing garbage", '{"format_version": 1} xyz'.to_utf8_buffer()],
		["two objects", '{"format_version": 1}{"format_version": 1}'.to_utf8_buffer()],
		["single quotes", "{'format_version': 1}".to_utf8_buffer()],
		["invalid utf8 c3 28", SaveFixtures.bytes_with_name(PackedByteArray([0xC3, 0x28]))],
		["invalid utf8 lone ff", SaveFixtures.bytes_with_name(PackedByteArray([0xFF]))],
		["invalid utf8 overlong", SaveFixtures.bytes_with_name(PackedByteArray([0xC0, 0xAF]))],
		["invalid utf8 lone continuation", SaveFixtures.bytes_with_name(PackedByteArray([0x80]))],
		[
			"invalid utf8 surrogate",
			SaveFixtures.bytes_with_name(PackedByteArray([0xED, 0xA0, 0x80]))
		],
	]
	var failures: PackedStringArray = PackedStringArray()
	for case: Array in cases:
		var bytes: PackedByteArray = case[1]
		var result: SaveResult = SaveCodec.new().decode_bytes(bytes, NOW)
		if result.kind != SaveResult.Kind.DAMAGED:
			failures.append("%s: kind %d" % [case[0], result.kind])
		elif result.model != null:
			failures.append("%s: failed result carries a model" % case[0])
		elif result.detail.is_empty():
			failures.append("%s: no developer detail" % case[0])
	assert_array(failures).is_empty()


func test_leading_bom_accepted() -> void:
	var bom: PackedByteArray = PackedByteArray([0xEF, 0xBB, 0xBF])
	var golden: PackedByteArray = SaveFixtures.read_bytes(SaveFixtures.GOLDEN_PATH)
	var with_bom: PackedByteArray = bom + golden
	var result: SaveResult = SaveCodec.new().decode_bytes(with_bom, NOW)
	assert_int(result.kind).is_equal(SaveResult.Kind.OK)
	var expected: AquariumModel = SaveFixtures.golden_expected()
	assert_dict(ModelState.snapshot_8bit(SaveFixtures.model_of(result))).is_equal(
		ModelState.snapshot_8bit(expected)
	)


func test_bom_only_is_damaged() -> void:
	assert_int(_bytes_kind(PackedByteArray([0xEF, 0xBB, 0xBF]))).is_equal(SaveResult.Kind.DAMAGED)


func test_second_bom_is_damaged() -> void:
	var bom: PackedByteArray = PackedByteArray([0xEF, 0xBB, 0xBF])
	var bytes: PackedByteArray = bom + bom + '{"format_version": 1}'.to_utf8_buffer()
	assert_int(_bytes_kind(bytes)).is_equal(SaveResult.Kind.DAMAGED)


func test_decode_with_bad_now_is_internal() -> void:
	var text: String = SaveFixtures.to_text(SaveFixtures.base_dict())
	for bad: String in ["", "now", "2026-13-45T00:00:00Z", "2026-11-01T12:00:00"]:
		var result: SaveResult = SaveCodec.new().decode(text, bad)
		assert_int(result.kind).is_equal(SaveResult.Kind.INTERNAL)
		assert_object(result.model).is_null()


# --- wrong types and nulls -----------------------------------------------------------------


func test_wrong_type_is_damaged() -> void:
	var rows: Array = [
		_row("name number", ["name"], 5),
		_row("name array", ["name"], ["x"]),
		_row("name bool", ["name"], true),
		_row("tank_id number", ["tank_id"], 5),
		_row("substrate array", SUBSTRATE, []),
		_row("substrate string", SUBSTRATE, "x"),
		_row("substrate id number", _path(SUBSTRATE, "id"), 5),
		_row("substrate colour number", _path(SUBSTRATE, "colour"), 5),
		_row("substrate colour bool", _path(SUBSTRATE, "colour"), true),
		_row("heightmap string", HEIGHTMAP, "x"),
		_row("heightmap array", HEIGHTMAP, []),
		_row("heightmap size string", _path(HEIGHTMAP, "size"), "2x1"),
		_row("heightmap size one value", _path(HEIGHTMAP, "size"), [2]),
		_row("heightmap size three values", _path(HEIGHTMAP, "size"), [2, 1, 1]),
		_row("heightmap size empty", _path(HEIGHTMAP, "size"), []),
		_row("heightmap size strings", _path(HEIGHTMAP, "size"), ["2", "1"]),
		_row("heightmap size null element", _path(HEIGHTMAP, "size"), [2, null]),
		_row("heightmap size bool", _path(HEIGHTMAP, "size"), [true, true]),
		_row("heightmap size dictionary", _path(HEIGHTMAP, "size"), {"x": 2, "y": 1}),
		_row("heightmap data number", _path(HEIGHTMAP, "data"), 5),
		_row("heightmap data array", _path(HEIGHTMAP, "data"), []),
		_row("items object", ["items"], {}),
		_row("items number", ["items"], 5),
		_row("items string", ["items"], "x"),
		_row("item is a string", ["items"], ["x"]),
		_row("item is a number", ["items"], [5]),
		_row("item is null", ["items"], [null]),
		_row("item is an array", ["items"], [[]]),
		_row("item uid number", _path(ITEM, "uid"), 5),
		_row("item uid array", _path(ITEM, "uid"), ["a0000001"]),
		_row("item catalog_id number", _path(ITEM, "catalog_id"), 5),
		_row("item position two numbers", _path(ITEM, "position"), [1.0, 2.0]),
		_row("item position four numbers", _path(ITEM, "position"), [1.0, 2.0, 3.0, 4.0]),
		_row("item position empty", _path(ITEM, "position"), []),
		_row("item position string", _path(ITEM, "position"), "1,2,3"),
		_row("item position dictionary", _path(ITEM, "position"), {"x": 1, "y": 2, "z": 3}),
		_row("item position text element", _path(ITEM, "position"), [1.0, "2", 3.0]),
		_row("item position null element", _path(ITEM, "position"), [1.0, null, 3.0]),
		_row("item position bool element", _path(ITEM, "position"), [1.0, true, 3.0]),
		_row("item rotation string", _path(ITEM, "rotation_y"), "90"),
		_row("item rotation bool", _path(ITEM, "rotation_y"), true),
		_row("item scale string", _path(ITEM, "scale"), "1"),
		_row("item scale bool", _path(ITEM, "scale"), true),
		_row("item colour number", _path(ITEM, "colour"), 5),
		_row("item colour bool", _path(ITEM, "colour"), false),
		_row("item colour array", _path(ITEM, "colour"), [1, 0, 0]),
		_row("fish object", ["fish"], {}),
		_row("fish string", ["fish"], "x"),
		_row("fish entry is a string", ["fish"], ["x"]),
		_row("fish entry is null", ["fish"], [null]),
		_row("fish uid number", _path(FISH, "uid"), 5),
		_row("fish species_id number", _path(FISH, "species_id"), 5),
		_row("fish variant string", _path(FISH, "variant"), "2"),
		_row("fish variant bool", _path(FISH, "variant"), true),
		_row("fish variant array", _path(FISH, "variant"), [2]),
		_row("fish nickname number", _path(FISH, "nickname"), 5),
		_row("created number", ["created"], 20261001),
		_row("created array", ["created"], []),
		_row("modified number", ["modified"], 5),
		_row("modified bool", ["modified"], true),
	]
	assert_array(_mismatches(rows, SaveResult.Kind.DAMAGED)).is_empty()


func test_null_is_damaged_except_item_colour() -> void:
	var rows: Array = [
		_row("name null", ["name"], null),
		_row("tank_id null", ["tank_id"], null),
		_row("substrate null", SUBSTRATE, null),
		_row("substrate id null", _path(SUBSTRATE, "id"), null),
		_row("substrate colour null", _path(SUBSTRATE, "colour"), null),
		_row("heightmap null", HEIGHTMAP, null),
		_row("heightmap size null", _path(HEIGHTMAP, "size"), null),
		_row("heightmap data null", _path(HEIGHTMAP, "data"), null),
		_row("items null", ["items"], null),
		_row("item uid null", _path(ITEM, "uid"), null),
		_row("item catalog_id null", _path(ITEM, "catalog_id"), null),
		_row("item position null", _path(ITEM, "position"), null),
		_row("item rotation null", _path(ITEM, "rotation_y"), null),
		_row("item scale null", _path(ITEM, "scale"), null),
		_row("fish null", ["fish"], null),
		_row("fish uid null", _path(FISH, "uid"), null),
		_row("fish species_id null", _path(FISH, "species_id"), null),
		_row("fish variant null", _path(FISH, "variant"), null),
		_row("fish nickname null", _path(FISH, "nickname"), null),
		_row("created null", ["created"], null),
		_row("modified null", ["modified"], null),
	]
	assert_array(_mismatches(rows, SaveResult.Kind.DAMAGED)).is_empty()


func test_item_colour_null_means_no_colour() -> void:
	var text: String = SaveFixtures.to_text(SaveFixtures.changed(_path(ITEM, "colour"), null))
	var result: SaveResult = _decode(text)
	assert_int(result.kind).is_equal(SaveResult.Kind.OK)
	assert_bool(SaveFixtures.model_of(result).get_item_at(0).has_colour).is_false()
	var coloured: SaveResult = _decode(SaveFixtures.to_text(SaveFixtures.base_dict()))
	assert_bool(SaveFixtures.model_of(coloured).get_item_at(0).has_colour).is_true()


# --- uids ----------------------------------------------------------------------------------


func test_bad_uid_is_damaged() -> void:
	var bad: Array = [
		"",
		"a1f3",
		"A1B2C3D4",
		"a1b2c3D4",
		"a1b2c3d45",
		"g1b2c3d4",
		" a1b2c3d",
		"a1b2c3d ",
		"a1b2c3d4\n",
		"a1b2-3d4",
		"é1b2c3d4",
	]
	var rows: Array = []
	for uid: String in bad:
		rows.append(_row("item uid '%s'" % uid.c_escape(), _path(ITEM, "uid"), uid))
		rows.append(_row("fish uid '%s'" % uid.c_escape(), _path(FISH, "uid"), uid))
	assert_array(_mismatches(rows, SaveResult.Kind.DAMAGED)).is_empty()


func test_good_uids_accepted() -> void:
	var rows: Array = [
		_row("digits", _path(ITEM, "uid"), "12345678"),
		_row("letters", _path(ITEM, "uid"), "abcdef01"),
		_row("zeros", _path(FISH, "uid"), "00000000"),
		_row("mixed", _path(FISH, "uid"), "0badf00d"),
	]
	assert_array(_mismatches(rows, SaveResult.Kind.OK)).is_empty()


func test_duplicate_uid_is_damaged() -> void:
	var two_items: Dictionary = SaveFixtures.base_dict()
	var items: Array = two_items["items"]
	var twin: Dictionary = (items[0] as Dictionary).duplicate(true)
	items.append(twin)
	var two_fish: Dictionary = SaveFixtures.base_dict()
	var fish: Array = two_fish["fish"]
	fish.append((fish[0] as Dictionary).duplicate(true))
	var item_then_fish: Dictionary = SaveFixtures.changed(_path(FISH, "uid"), "a0000001")
	var fish_then_item: Dictionary = SaveFixtures.changed(_path(ITEM, "uid"), "f0000001")
	var rows: Array = [
		["item and item", SaveFixtures.to_text(two_items)],
		["fish and fish", SaveFixtures.to_text(two_fish)],
		["item and fish", SaveFixtures.to_text(item_then_fish)],
		["fish and item", SaveFixtures.to_text(fish_then_item)],
	]
	assert_array(_mismatches(rows, SaveResult.Kind.DAMAGED)).is_empty()


# --- colours -------------------------------------------------------------------------------


func test_bad_colour_is_damaged() -> void:
	var bad: Array = [
		"#FFF",
		"#FFFF",
		"E8D9B0",
		"#GGGGGG",
		"#12345",
		"#1234567",
		"#123456789",
		"#",
		"",
		"red",
		"#E8D9B0 ",
		" #E8D9B0",
		"#E8D9B0\n",
		"0xE8D9B0",
		"#E8 D9B0",
		"rgb(1,2,3)",
	]
	var rows: Array = []
	for colour: String in bad:
		rows.append(_row("substrate '%s'" % colour.c_escape(), _path(SUBSTRATE, "colour"), colour))
		rows.append(_row("item '%s'" % colour.c_escape(), _path(ITEM, "colour"), colour))
	assert_array(_mismatches(rows, SaveResult.Kind.DAMAGED)).is_empty()


func test_hex_colour_accepted_in_either_case() -> void:
	var cases: Array = [
		["#E8D9B0", Color8(0xE8, 0xD9, 0xB0, 0xFF)],
		["#e8d9b0", Color8(0xE8, 0xD9, 0xB0, 0xFF)],
		["#E8d9B0", Color8(0xE8, 0xD9, 0xB0, 0xFF)],
		["#E8D9B0FF", Color8(0xE8, 0xD9, 0xB0, 0xFF)],
		["#e8d9b080", Color8(0xE8, 0xD9, 0xB0, 0x80)],
		["#00000000", Color8(0, 0, 0, 0)],
	]
	var failures: PackedStringArray = PackedStringArray()
	for case: Array in cases:
		var text: String = SaveFixtures.to_text(
			SaveFixtures.changed(_path(SUBSTRATE, "colour"), case[0])
		)
		var item_text: String = SaveFixtures.to_text(
			SaveFixtures.changed(_path(ITEM, "colour"), case[0])
		)
		var expected: Color = case[1]
		var result: SaveResult = _decode(text)
		var item_result: SaveResult = _decode(item_text)
		if result.kind != SaveResult.Kind.OK or item_result.kind != SaveResult.Kind.OK:
			failures.append("%s refused" % case[0])
			continue
		var got: Color = SaveFixtures.model_of(result).get_substrate_colour()
		var got_item: Color = SaveFixtures.model_of(item_result).get_item_at(0).colour
		if got.to_rgba32() != expected.to_rgba32():
			failures.append("substrate %s decoded as %s" % [case[0], got.to_html()])
		if got_item.to_rgba32() != expected.to_rgba32():
			failures.append("item %s decoded as %s" % [case[0], got_item.to_html()])
	assert_array(failures).is_empty()


# --- numbers -------------------------------------------------------------------------------


func test_non_finite_number_is_damaged() -> void:
	var paths: Array = [
		["item position x", _path(_path(ITEM, "position"), 0)],
		["item rotation_y", _path(ITEM, "rotation_y")],
		["item scale", _path(ITEM, "scale")],
		["fish variant", _path(FISH, "variant")],
		["heightmap size x", _path(_path(HEIGHTMAP, "size"), 0)],
	]
	var rows: Array = []
	for entry: Array in paths:
		for raw: String in ["1e999", "-1e999"]:
			rows.append(_raw_row("%s = %s" % [entry[0], raw], entry[1], raw))
	assert_array(_mismatches(rows, SaveResult.Kind.DAMAGED)).is_empty()


func test_bad_variant_is_damaged() -> void:
	var rows: Array = [
		_row("minus one", _path(FISH, "variant"), -1),
		_row("1.5", _path(FISH, "variant"), 1.5),
		_row("0.1", _path(FISH, "variant"), 0.1),
		_row("text", _path(FISH, "variant"), "1"),
		_row("256", _path(FISH, "variant"), 256),
		_row("1000000", _path(FISH, "variant"), 1000000),
		_row("1e10", _path(FISH, "variant"), 1e10),
		_row("true", _path(FISH, "variant"), true),
		_row("null", _path(FISH, "variant"), null),
		_raw_row("1e999", _path(FISH, "variant"), "1e999"),
	]
	assert_array(_mismatches(rows, SaveResult.Kind.DAMAGED)).is_empty()


func test_variant_limits_accepted() -> void:
	var failures: PackedStringArray = PackedStringArray()
	for value: Variant in [0, 1, 255, 2.0, 255.0]:
		var text: String = SaveFixtures.to_text(SaveFixtures.changed(_path(FISH, "variant"), value))
		var result: SaveResult = _decode(text)
		if result.kind != SaveResult.Kind.OK:
			failures.append("variant %s refused" % str(value))
		elif SaveFixtures.model_of(result).get_fish_at(0).variant != int(value):
			failures.append(
				(
					"variant %s decoded as %d"
					% [str(value), SaveFixtures.model_of(result).get_fish_at(0).variant]
				)
			)
	assert_array(failures).is_empty()


func test_bad_scale_is_damaged() -> void:
	var rows: Array = [
		_row("zero", _path(ITEM, "scale"), 0),
		_row("zero float", _path(ITEM, "scale"), 0.0),
		_row("minus one", _path(ITEM, "scale"), -1.0),
		_row("tiny negative", _path(ITEM, "scale"), -1e-30),
		_raw_row("infinity", _path(ITEM, "scale"), "1e999"),
		_raw_row("negative zero", _path(ITEM, "scale"), "-0.0"),
	]
	assert_array(_mismatches(rows, SaveResult.Kind.DAMAGED)).is_empty()
	var tiny: SaveResult = _decode(
		SaveFixtures.to_text(SaveFixtures.changed(_path(ITEM, "scale"), 1e-30))
	)
	assert_int(tiny.kind).is_equal(SaveResult.Kind.OK)


func test_bad_position_is_damaged() -> void:
	var rows: Array = [
		_row("empty", _path(ITEM, "position"), []),
		_row("one number", _path(ITEM, "position"), [1.0]),
		_row("two numbers", _path(ITEM, "position"), [1.0, 2.0]),
		_row("four numbers", _path(ITEM, "position"), [1.0, 2.0, 3.0, 4.0]),
		_row("float32 overflow", _path(ITEM, "position"), [1e300, 0.0, 0.0]),
		_row("float32 overflow negative", _path(ITEM, "position"), [0.0, -1e300, 0.0]),
		_row("float32 overflow in z", _path(ITEM, "position"), [0.0, 0.0, 3.5e38]),
		_raw_row("infinity", _path(_path(ITEM, "position"), 2), "1e999"),
	]
	assert_array(_mismatches(rows, SaveResult.Kind.DAMAGED)).is_empty()


func test_large_but_finite_numbers_accepted() -> void:
	var position: Array = [1e30, -1e30, 0.0]
	var rows: Array = [
		_row("big position", _path(ITEM, "position"), position),
		_row("negative rotation", _path(ITEM, "rotation_y"), -720.5),
		_row("rotation not normalised", _path(ITEM, "rotation_y"), 1e6),
		_row("big scale", _path(ITEM, "scale"), 1e20),
	]
	assert_array(_mismatches(rows, SaveResult.Kind.OK)).is_empty()


# --- stamps --------------------------------------------------------------------------------


func test_bad_stamp_is_damaged() -> void:
	var bad: Array = [
		"2026-13-45T00:00:00Z",
		"2026-13-01T00:00:00Z",
		"2026-00-10T00:00:00Z",
		"2026-01-00T00:00:00Z",
		"2026-01-32T00:00:00Z",
		"2025-02-29T00:00:00Z",
		"1900-02-29T00:00:00Z",
		"2026-04-31T00:00:00Z",
		"2026-01-01T24:00:00Z",
		"2026-01-01T00:60:00Z",
		"2026-01-01T00:00:60Z",
		"2026-01-01T00:00:00",
		"2026-01-01 00:00:00Z",
		"2026-01-01T00:00:00.123Z",
		"2026-01-01T00:00:00+00:00",
		"2026-01-01T00:00:00z",
		"2026-01-01t00:00:00Z",
		"2026-01-01T00:00:00Z\n",
		" 2026-01-01T00:00:00Z",
		"26-01-01T00:00:00Z",
		"2026-1-1T0:0:0Z",
		"",
		"yesterday",
		"2026-01-01",
	]
	var rows: Array = []
	for stamp: String in bad:
		rows.append(_row("created '%s'" % stamp.c_escape(), ["created"], stamp))
		rows.append(_row("modified '%s'" % stamp.c_escape(), ["modified"], stamp))
	assert_array(_mismatches(rows, SaveResult.Kind.DAMAGED)).is_empty()


func test_leap_day_accepted() -> void:
	var rows: Array = [
		_row("2024", ["created"], "2024-02-29T00:00:00Z"),
		_row("2000", ["modified"], "2000-02-29T23:59:59Z"),
		_row("end of year", ["created"], "2026-12-31T23:59:59Z"),
		_row("start of year", ["created"], "2026-01-01T00:00:00Z"),
	]
	assert_array(_mismatches(rows, SaveResult.Kind.OK)).is_empty()


func test_created_and_modified_taken_from_the_file() -> void:
	var result: SaveResult = _decode(SaveFixtures.to_text(SaveFixtures.base_dict()))
	assert_str(SaveFixtures.model_of(result).get_created()).is_equal(SaveFixtures.STAMP_CREATED)
	assert_str(SaveFixtures.model_of(result).get_modified()).is_equal(SaveFixtures.STAMP_MODIFIED)


func test_one_missing_stamp_loads_as_load_time() -> void:
	var no_created: SaveResult = _decode(SaveFixtures.to_text(SaveFixtures.removed(["created"])))
	assert_str(SaveFixtures.model_of(no_created).get_created()).is_equal(NOW)
	assert_str(SaveFixtures.model_of(no_created).get_modified()).is_equal(
		SaveFixtures.STAMP_MODIFIED
	)
	var no_modified: SaveResult = _decode(SaveFixtures.to_text(SaveFixtures.removed(["modified"])))
	assert_str(SaveFixtures.model_of(no_modified).get_created()).is_equal(
		SaveFixtures.STAMP_CREATED
	)
	assert_str(SaveFixtures.model_of(no_modified).get_modified()).is_equal(NOW)


# --- heightmap -----------------------------------------------------------------------------


func _flat(count: int, value: float = 0.0) -> Array[float]:
	var result: Array[float] = []
	for index: int in count:
		result.append(value)
	return result


func _heightmap_text(size: Variant, data: Variant) -> String:
	var heightmap: Dictionary = {"size": size, "data": data}
	return SaveFixtures.to_text(SaveFixtures.changed(HEIGHTMAP, heightmap))


func test_bad_heightmap_is_damaged() -> void:
	var inf_bytes: String = Marshalls.raw_to_base64(PackedByteArray([0x00, 0x00, 0x80, 0x7F]))
	var nan_bytes: String = Marshalls.raw_to_base64(PackedByteArray([0x00, 0x00, 0xC0, 0x7F]))
	var minus_inf: String = Marshalls.raw_to_base64(PackedByteArray([0x00, 0x00, 0x80, 0xFF]))
	var rows: Array = [
		["size 1.5", _heightmap_text([1.5, 2], SaveFixtures.b64(_flat(3)))],
		["size 2.5 by 1", _heightmap_text([2.5, 1], SaveFixtures.b64(_flat(2)))],
		["size negative x", _heightmap_text([-1, 2], "")],
		["size negative y", _heightmap_text([2, -1], "")],
		["size both negative", _heightmap_text([-1, -1], SaveFixtures.b64(_flat(1)))],
		["size 1025 by 1", _heightmap_text([1025, 1], SaveFixtures.b64(_flat(1025)))],
		["size 1 by 1025", _heightmap_text([1, 1025], SaveFixtures.b64(_flat(1025)))],
		["size 0 by 0 with data", _heightmap_text([0, 0], SaveFixtures.b64(_flat(1)))],
		["size 0 by 3 without data", _heightmap_text([0, 3], "")],
		["size 3 by 0 without data", _heightmap_text([3, 0], "")],
		["size 0 by 3 with data", _heightmap_text([0, 3], SaveFixtures.b64(_flat(3)))],
		["size 2 by 2 without data", _heightmap_text([2, 2], "")],
		["data one value short", _heightmap_text([2, 2], SaveFixtures.b64(_flat(3)))],
		["data one value long", _heightmap_text([2, 2], SaveFixtures.b64(_flat(5)))],
		["data far too long", _heightmap_text([1, 1], SaveFixtures.b64(_flat(100)))],
		[
			"data with a partial value",
			_heightmap_text([1, 1], Marshalls.raw_to_base64(PackedByteArray([0, 0, 0])))
		],
		["base64 bad characters", _heightmap_text([1, 1], "!!!!")],
		["base64 url alphabet", _heightmap_text([1, 1], "AA-_")],
		["base64 length not a multiple of 4", _heightmap_text([1, 1], "AAA")],
		["base64 padding in the middle", _heightmap_text([1, 1], "AA=A")],
		["base64 padding only", _heightmap_text([1, 1], "====")],
		["base64 three paddings", _heightmap_text([1, 1], "A===")],
		["base64 padding then more", _heightmap_text([2, 1], "AAAA====")],
		["base64 padding before the last group", _heightmap_text([2, 1], "AA==AAAA")],
		["base64 with newline", _heightmap_text([1, 1], "AAAAAA==\n")],
		["base64 with space", _heightmap_text([1, 1], "AAAA AAAA")],
		["data infinity", _heightmap_text([1, 1], inf_bytes)],
		["data negative infinity", _heightmap_text([1, 1], minus_inf)],
		["data nan", _heightmap_text([1, 1], nan_bytes)],
		["size is a string pair", _heightmap_text(["1", "1"], SaveFixtures.b64(_flat(1)))],
		["size is infinite", SaveFixtures.changed_raw(_path(_path(HEIGHTMAP, "size"), 0), "1e999")],
		[
			"missing size with data present",
			SaveFixtures.to_text(
				SaveFixtures.changed(HEIGHTMAP, {"data": SaveFixtures.b64(_flat(2))})
			)
		],
		[
			"missing data with size present",
			SaveFixtures.to_text(SaveFixtures.changed(HEIGHTMAP, {"size": [2, 1]}))
		],
	]
	assert_array(_mismatches(rows, SaveResult.Kind.DAMAGED)).is_empty()


func test_heightmap_side_1024_accepted() -> void:
	var wide: Array[float] = _flat(1024, 0.25)
	var result: SaveResult = _decode(_heightmap_text([1024, 1], SaveFixtures.b64(wide)))
	assert_int(result.kind).is_equal(SaveResult.Kind.OK)
	assert_bool(SaveFixtures.model_of(result).get_heightmap_size() == Vector2i(1024, 1)).is_true()
	assert_int(SaveFixtures.model_of(result).get_heightmap().size()).is_equal(1024)
	assert_float(SaveFixtures.model_of(result).get_heightmap()[1023]).is_equal(0.25)
	var tall: SaveResult = _decode(_heightmap_text([1, 1024], SaveFixtures.b64(wide)))
	assert_int(tall.kind).is_equal(SaveResult.Kind.OK)
	assert_bool(SaveFixtures.model_of(tall).get_heightmap_size() == Vector2i(1, 1024)).is_true()


func test_flat_and_whole_float_heightmaps_accepted() -> void:
	var flat: SaveResult = _decode(_heightmap_text([0, 0], ""))
	assert_int(flat.kind).is_equal(SaveResult.Kind.OK)
	assert_int(SaveFixtures.model_of(flat).get_heightmap().size()).is_equal(0)
	assert_bool(SaveFixtures.model_of(flat).get_heightmap_size() == Vector2i.ZERO).is_true()
	var floats: SaveResult = _decode(_heightmap_text([2.0, 1.0], SaveFixtures.b64([0.5, 0.25])))
	assert_int(floats.kind).is_equal(SaveResult.Kind.OK)
	assert_bool(SaveFixtures.model_of(floats).get_heightmap_size() == Vector2i(2, 1)).is_true()
	assert_array(SaveFixtures.model_of(floats).get_heightmap()).is_equal(
		PackedFloat32Array([0.5, 0.25])
	)


# --- size and depth ------------------------------------------------------------------------


func test_oversized_is_damaged() -> void:
	var bytes: PackedByteArray = SaveFixtures.padded_bytes(SaveFixtures.MAX_FILE_BYTES + 1)
	var result: SaveResult = SaveCodec.new().decode_bytes(bytes, NOW)
	assert_int(result.kind).is_equal(SaveResult.Kind.DAMAGED)
	assert_object(result.model).is_null()


func test_exactly_max_size_accepted() -> void:
	var bytes: PackedByteArray = SaveFixtures.padded_bytes(SaveFixtures.MAX_FILE_BYTES)
	assert_int(bytes.size()).is_equal(SaveFixtures.MAX_FILE_BYTES)
	var result: SaveResult = SaveCodec.new().decode_bytes(bytes, NOW)
	assert_int(result.kind).is_equal(SaveResult.Kind.OK)


func test_deep_nesting_is_damaged() -> void:
	var codec: SaveCodec = SaveCodec.new()
	for use_arrays: bool in [true, false]:
		var text: String = SaveFixtures.deep_text(2000, use_arrays)
		var from_text: SaveResult = codec.decode(text, NOW)
		assert_int(from_text.kind).is_equal(SaveResult.Kind.DAMAGED)
		var from_bytes: SaveResult = codec.decode_bytes(text.to_utf8_buffer(), NOW)
		assert_int(from_bytes.kind).is_equal(SaveResult.Kind.DAMAGED)


func test_moderate_nesting_under_unknown_key_accepted() -> void:
	var text: String = SaveFixtures.deep_text(20, true)
	assert_int(_decode(text).kind).is_equal(SaveResult.Kind.OK)


# --- defaults, identity keys and unknown keys ------------------------------------------------


func test_minimal_file_loads_defaults() -> void:
	var bytes: PackedByteArray = SaveFixtures.read_bytes(SaveFixtures.MINIMAL_PATH)
	assert_int(bytes.size()).is_greater(0)
	var result: SaveResult = SaveCodec.new().decode_bytes(bytes, NOW)
	assert_int(result.kind).is_equal(SaveResult.Kind.OK)
	var model: AquariumModel = SaveFixtures.model_of(result)
	assert_str(model.get_aquarium_name()).is_equal("")
	assert_str(String(model.get_tank_id())).is_equal("")
	assert_str(String(model.get_substrate_id())).is_equal("")
	assert_bool(model.get_substrate_colour() == Color.WHITE).is_true()
	assert_int(model.get_heightmap().size()).is_equal(0)
	assert_bool(model.get_heightmap_size() == Vector2i.ZERO).is_true()
	assert_int(model.get_item_count()).is_equal(0)
	assert_int(model.get_fish_count()).is_equal(0)
	assert_str(model.get_created()).is_equal(NOW)
	assert_str(model.get_modified()).is_equal(NOW)


func test_item_defaults() -> void:
	var data: Dictionary = {
		"format_version": 1,
		"items": [{"uid": "a0000001", "catalog_id": "rock_a"}],
	}
	var result: SaveResult = _decode(SaveFixtures.to_text(data))
	assert_int(result.kind).is_equal(SaveResult.Kind.OK)
	var item: PlacedItem = SaveFixtures.model_of(result).get_item_at(0)
	assert_bool(item.position == Vector3.ZERO).is_true()
	assert_float(item.rotation_y).is_equal(0.0)
	assert_float(item.scale).is_equal(1.0)
	assert_bool(item.has_colour).is_false()
	assert_str(item.uid).is_equal("a0000001")
	assert_str(String(item.catalog_id)).is_equal("rock_a")


func test_fish_defaults() -> void:
	var data: Dictionary = {
		"format_version": 1,
		"fish": [{"uid": "f0000001", "species_id": "guppy"}],
	}
	var result: SaveResult = _decode(SaveFixtures.to_text(data))
	assert_int(result.kind).is_equal(SaveResult.Kind.OK)
	var fish: FishInstance = SaveFixtures.model_of(result).get_fish_at(0)
	assert_int(fish.variant).is_equal(0)
	assert_str(fish.nickname).is_equal("")
	assert_str(String(fish.species_id)).is_equal("guppy")


func test_missing_identity_key_is_damaged() -> void:
	var rows: Array = [
		["item without uid", SaveFixtures.to_text(SaveFixtures.removed(_path(ITEM, "uid")))],
		[
			"item without catalog_id",
			SaveFixtures.to_text(SaveFixtures.removed(_path(ITEM, "catalog_id")))
		],
		["fish without uid", SaveFixtures.to_text(SaveFixtures.removed(_path(FISH, "uid")))],
		[
			"fish without species_id",
			SaveFixtures.to_text(SaveFixtures.removed(_path(FISH, "species_id")))
		],
		_row("item empty catalog_id", _path(ITEM, "catalog_id"), ""),
		_row("fish empty species_id", _path(FISH, "species_id"), ""),
		_row("item empty uid", _path(ITEM, "uid"), ""),
	]
	assert_array(_mismatches(rows, SaveResult.Kind.DAMAGED)).is_empty()


func test_empty_free_strings_accepted() -> void:
	var data: Dictionary = SaveFixtures.base_dict()
	data["name"] = ""
	data["tank_id"] = ""
	var substrate: Dictionary = data["substrate"]
	substrate["id"] = ""
	var fish: Array = data["fish"]
	(fish[0] as Dictionary)["nickname"] = ""
	var result: SaveResult = _decode(SaveFixtures.to_text(data))
	assert_int(result.kind).is_equal(SaveResult.Kind.OK)
	assert_str(SaveFixtures.model_of(result).get_aquarium_name()).is_equal("")
	assert_str(SaveFixtures.model_of(result).get_fish_at(0).nickname).is_equal("")


func test_unknown_keys_ignored() -> void:
	var data: Dictionary = SaveFixtures.base_dict()
	data["thumbnail"] = "AAAA"
	data["mode"] = "survival"
	data["simulation"] = {"a1b2c3d4": {"hunger": 0.5}}
	var substrate: Dictionary = data["substrate"]
	substrate["extra"] = [1, 2, 3]
	(substrate["heightmap"] as Dictionary)["extra"] = null
	(data["items"][0] as Dictionary)["extra"] = {"deep": [1, {"x": 2}]}
	(data["fish"][0] as Dictionary)["personality"] = 0.7
	var result: SaveResult = _decode(SaveFixtures.to_text(data))
	assert_int(result.kind).is_equal(SaveResult.Kind.OK)
	var plain: SaveResult = _decode(SaveFixtures.to_text(SaveFixtures.base_dict()))
	assert_dict(ModelState.snapshot_8bit(SaveFixtures.model_of(result))).is_equal(
		ModelState.snapshot_8bit(SaveFixtures.model_of(plain))
	)


func test_unknown_ids_kept() -> void:
	var data: Dictionary = SaveFixtures.base_dict()
	(data["items"][0] as Dictionary)["catalog_id"] = "no_such_item_anywhere"
	(data["fish"][0] as Dictionary)["species_id"] = "no_such_species_anywhere"
	data["tank_id"] = "no_such_tank"
	(data["substrate"] as Dictionary)["id"] = "no_such_substrate"
	var result: SaveResult = _decode(SaveFixtures.to_text(data))
	assert_int(result.kind).is_equal(SaveResult.Kind.OK)
	assert_str(String(SaveFixtures.model_of(result).get_item_at(0).catalog_id)).is_equal(
		"no_such_item_anywhere"
	)
	assert_str(String(SaveFixtures.model_of(result).get_fish_at(0).species_id)).is_equal(
		"no_such_species_anywhere"
	)
	assert_str(String(SaveFixtures.model_of(result).get_tank_id())).is_equal("no_such_tank")
	assert_str(String(SaveFixtures.model_of(result).get_substrate_id())).is_equal(
		"no_such_substrate"
	)


func test_valid_base_file_decodes() -> void:
	var result: SaveResult = _decode(SaveFixtures.to_text(SaveFixtures.base_dict()))
	assert_int(result.kind).is_equal(SaveResult.Kind.OK)
	assert_bool(result.is_ok()).is_true()
	assert_str(SaveFixtures.model_of(result).get_aquarium_name()).is_equal("Base")
	assert_int(SaveFixtures.model_of(result).get_item_count()).is_equal(1)
	assert_int(SaveFixtures.model_of(result).get_fish_count()).is_equal(1)


func test_partly_invalid_items_are_damaged_and_yield_no_model() -> void:
	var data: Dictionary = SaveFixtures.base_dict()
	var items: Array = []
	for index: int in 3:
		var item: Dictionary = (SaveFixtures.base_dict()["items"][0] as Dictionary).duplicate(true)
		item["uid"] = "b000000%d" % index
		items.append(item)
	var broken: Dictionary = (items[0] as Dictionary).duplicate(true)
	broken["uid"] = "b0000009"
	broken["scale"] = 0
	items.append(broken)
	data["items"] = items
	var result: SaveResult = _decode(SaveFixtures.to_text(data))
	assert_int(result.kind).is_equal(SaveResult.Kind.DAMAGED)
	assert_object(result.model).is_null()
