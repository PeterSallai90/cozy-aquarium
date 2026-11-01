extends GdUnitTestSuite

const Factory := preload("res://tests/helpers/factory.gd")
const ModelState := preload("res://tests/helpers/model_state.gd")
const SaveFixtures := preload("res://tests/helpers/save_fixtures.gd")
const SignalRecorder := preload("res://tests/helpers/signal_recorder.gd")

const STAMP := "2026-11-01T12:00:00Z"

const TOP_KEYS := [
	"format_version", "name", "tank_id", "substrate", "items", "fish", "created", "modified"
]
const SUBSTRATE_KEYS := ["id", "colour", "heightmap"]
const HEIGHTMAP_KEYS := ["size", "data"]
const ITEM_KEYS := ["uid", "catalog_id", "position", "rotation_y", "scale", "colour"]
const FISH_KEYS := ["uid", "species_id", "variant", "nickname"]

const ITEM_DEFECTS := [
	"position inf",
	"position nan",
	"rotation inf",
	"rotation nan",
	"scale inf",
	"scale nan",
	"scale zero",
	"scale negative",
	"empty catalog id",
	"empty uid",
	"uid too short",
	"uid uppercase",
	"uid not hex",
	"uid too long",
	"uid duplicates fish",
	"colour nan",
	"colour inf alpha",
]
const FISH_DEFECTS := [
	"variant -1",
	"variant 256",
	"empty species id",
	"fish uid empty",
	"fish uid uppercase",
	"fish uid duplicates item",
]


func _encode(model: AquariumModel, stamp: String = STAMP) -> SaveResult:
	return SaveCodec.new().encode(model, stamp)


func _parsed(model: AquariumModel) -> Dictionary:
	var result: SaveResult = _encode(model)
	assert_int(result.kind).is_equal(SaveResult.Kind.OK)
	var json: JSON = JSON.new()
	assert_int(json.parse(result.text)).is_equal(OK)
	var data: Variant = json.data
	assert_bool(data is Dictionary).is_true()
	return data


func _model_with_substrate_colour(colour: Color) -> AquariumModel:
	var model: AquariumModel = AquariumModel.new(STAMP)
	model.apply_set_substrate(&"sand", colour)
	return model


# --- text format ---------------------------------------------------------------------------


func test_encoded_text_is_utf8_lf_indented_with_one_newline() -> void:
	var result: SaveResult = _encode(SaveFixtures.populated_model())
	assert_int(result.kind).is_equal(SaveResult.Kind.OK)
	var text: String = result.text
	var bytes: PackedByteArray = text.to_utf8_buffer()
	(
		assert_bool(bytes.size() >= 3 and bytes.slice(0, 3) == PackedByteArray([0xEF, 0xBB, 0xBF]))
		. is_false()
	)
	assert_bool(text.contains("\r")).is_false()
	assert_bool(text.contains("\t")).is_false()
	assert_bool(text.ends_with("\n")).is_true()
	assert_bool(text.ends_with("\n\n")).is_false()
	assert_bool(text.begins_with("{\n")).is_true()
	var lines: PackedStringArray = text.split("\n")
	assert_str(lines[1]).starts_with('  "format_version"')
	assert_bool(lines[1].begins_with("   ")).is_false()
	assert_bool(bytes.get_string_from_utf8().to_utf8_buffer() == bytes).is_true()
	var json: JSON = JSON.new()
	assert_int(json.parse(text)).is_equal(OK)
	assert_bool(json.data is Dictionary).is_true()


func test_format_version_is_integer_one() -> void:
	var result: SaveResult = _encode(SaveFixtures.populated_model())
	assert_str(result.text).contains('"format_version": 1,')
	assert_str(result.text).not_contains('"format_version": 1.0')
	assert_int(SaveCodec.FORMAT_VERSION).is_equal(1)
	assert_float(_parsed(SaveFixtures.populated_model())["format_version"]).is_equal(1.0)


func test_key_order_top_substrate_heightmap_items_fish() -> void:
	var data: Dictionary = _parsed(SaveFixtures.populated_model())
	assert_array(data.keys()).is_equal(TOP_KEYS)
	var substrate: Dictionary = data["substrate"]
	assert_array(substrate.keys()).is_equal(SUBSTRATE_KEYS)
	var heightmap: Dictionary = substrate["heightmap"]
	assert_array(heightmap.keys()).is_equal(HEIGHTMAP_KEYS)
	var items: Array = data["items"]
	for item: Dictionary in items:
		assert_array(item.keys()).is_equal(ITEM_KEYS)
	var fish: Array = data["fish"]
	for member: Dictionary in fish:
		assert_array(member.keys()).is_equal(FISH_KEYS)


func test_items_and_fish_in_list_order() -> void:
	var data: Dictionary = _parsed(SaveFixtures.populated_model())
	var items: Array = data["items"]
	var item_uids: Array = []
	for item: Dictionary in items:
		item_uids.append(item["uid"])
	assert_array(item_uids).is_equal(["a0000001", "a0000002", "a0000003"])
	var fish: Array = data["fish"]
	var fish_uids: Array = []
	for member: Dictionary in fish:
		fish_uids.append(member["uid"])
	assert_array(fish_uids).is_equal(["f0000001", "f0000002", "f0000003"])
	var first_fish: Dictionary = fish[2]
	assert_str(first_fish["nickname"]).is_equal("Kék 熱帯魚")
	assert_str(first_fish["species_id"]).is_equal("betta")
	assert_float(first_fish["variant"]).is_equal(1.0)


func test_item_without_colour_is_null() -> void:
	var data: Dictionary = _parsed(SaveFixtures.populated_model())
	var items: Array = data["items"]
	var plain: Dictionary = items[1]
	assert_bool(plain.has("colour")).is_true()
	assert_bool(plain["colour"] == null).is_true()
	var coloured: Dictionary = items[0]
	assert_str(coloured["colour"]).is_equal("#336699")


func test_key_set_is_exactly_v1() -> void:
	var data: Dictionary = _parsed(SaveFixtures.populated_model())
	var paths: PackedStringArray = PackedStringArray()
	_collect_paths(data, "", paths)
	var expected: PackedStringArray = PackedStringArray()
	for key: String in TOP_KEYS:
		expected.append(key)
	for key: String in SUBSTRATE_KEYS:
		expected.append("substrate." + key)
	for key: String in HEIGHTMAP_KEYS:
		expected.append("substrate.heightmap." + key)
	for key: String in ITEM_KEYS:
		expected.append("items[]." + key)
	for key: String in FISH_KEYS:
		expected.append("fish[]." + key)
	paths.sort()
	expected.sort()
	assert_array(paths).is_equal(expected)


func _collect_paths(node: Variant, prefix: String, paths: PackedStringArray) -> void:
	if node is Dictionary:
		var dict: Dictionary = node
		for key: String in dict.keys():
			var path: String = key if prefix.is_empty() else prefix + "." + key
			if not paths.has(path):
				paths.append(path)
			_collect_paths(dict[key], path, paths)
	elif node is Array:
		var list: Array = node
		for element: Variant in list:
			if element is Dictionary:
				_collect_paths(element, prefix + "[]", paths)


# --- determinism ---------------------------------------------------------------------------


func test_same_state_same_stamp_byte_identical() -> void:
	var first: SaveResult = _encode(SaveFixtures.populated_model())
	var second: SaveResult = _encode(SaveFixtures.populated_model())
	assert_bool(first.text.to_utf8_buffer() == second.text.to_utf8_buffer()).is_true()
	var model: AquariumModel = SaveFixtures.populated_model()
	assert_str(_encode(model).text).is_equal(_encode(model).text)


func test_modified_is_the_argument_not_the_model_value() -> void:
	var model: AquariumModel = SaveFixtures.populated_model()
	var data: Dictionary = {}
	var result: SaveResult = _encode(model, "2027-02-03T04:05:06Z")
	var json: JSON = JSON.new()
	assert_int(json.parse(result.text)).is_equal(OK)
	data = json.data
	assert_str(data["modified"]).is_equal("2027-02-03T04:05:06Z")
	assert_str(data["created"]).is_equal(SaveFixtures.STAMP_CREATED)
	assert_str(model.get_modified()).is_equal(SaveFixtures.STAMP_CREATED)


func test_encode_does_not_change_the_model() -> void:
	var model: AquariumModel = SaveFixtures.populated_model()
	var before: Dictionary = ModelState.snapshot(model)
	var recorder: SignalRecorder = SignalRecorder.new()
	recorder.watch(model)
	_encode(model)
	assert_dict(ModelState.snapshot(model)).is_equal(before)
	assert_array(recorder.events).is_empty()


# --- colours -------------------------------------------------------------------------------


func test_colour_hex_cases() -> void:
	var cases: Array = [
		["opaque white", Color(1.0, 1.0, 1.0, 1.0), "#FFFFFF"],
		["8 bit exact", Color8(0xE8, 0xD9, 0xB0), "#E8D9B0"],
		["alpha 128", Color8(0x11, 0x22, 0x33, 0x80), "#11223380"],
		["alpha 0", Color8(0x11, 0x22, 0x33, 0x00), "#11223300"],
		["uppercase", Color8(0xAB, 0xCD, 0xEF), "#ABCDEF"],
		["clamped components", Color(-0.2, 1.7, 0.2, 1.0), "#00FF33"],
		["alpha above 1 clamps to opaque", Color(1.0, 1.0, 1.0, 2.0), "#FFFFFF"],
		["alpha below 0 clamps to 00", Color(1.0, 1.0, 1.0, -1.0), "#FFFFFF00"],
	]
	var failures: PackedStringArray = PackedStringArray()
	for case: Array in cases:
		var colour: Color = case[1]
		var data: Dictionary = _parsed(_model_with_substrate_colour(colour))
		var substrate: Dictionary = data["substrate"]
		if substrate["colour"] != case[2]:
			failures.append("%s: got %s want %s" % [case[0], substrate["colour"], case[2]])
	assert_array(failures).is_empty()


func test_item_colour_written_as_hex() -> void:
	var model: AquariumModel = AquariumModel.new(STAMP)
	var item: PlacedItem = Factory.coloured_item("a0000001", Color8(0x7A, 0x5C, 0x3E))
	var faint: PlacedItem = Factory.coloured_item("a0000002", Color8(0x7A, 0x5C, 0x3E, 0x01))
	model.apply_insert_item(item, 0)
	model.apply_insert_item(faint, 1)
	var items: Array = _parsed(model)["items"]
	var first: Dictionary = items[0]
	var second: Dictionary = items[1]
	assert_str(first["colour"]).is_equal("#7A5C3E")
	assert_str(second["colour"]).is_equal("#7A5C3E01")


# --- heightmap -----------------------------------------------------------------------------


func test_heightmap_known_bytes() -> void:
	var model: AquariumModel = AquariumModel.new(STAMP)
	var values: PackedFloat32Array = PackedFloat32Array([0.0, 0.5, 1.0, 0.25, 0.125, 0.0625])
	model.apply_set_heightmap(values, Vector2i(3, 2))
	var substrate: Dictionary = _parsed(model)["substrate"]
	var heightmap: Dictionary = substrate["heightmap"]
	assert_array(heightmap["size"]).is_equal([3.0, 2.0])
	assert_str(heightmap["data"]).is_equal("AAAAAAAAAD8AAIA/AACAPgAAAD4AAIA9")
	var raw: PackedByteArray = Marshalls.base64_to_raw(heightmap["data"])
	assert_int(raw.size()).is_equal(24)
	assert_array(raw.slice(4, 8)).is_equal([0x00, 0x00, 0x00, 0x3F])


func test_heightmap_size_is_written_as_integers() -> void:
	var model: AquariumModel = AquariumModel.new(STAMP)
	model.apply_set_heightmap(PackedFloat32Array([0.0, 0.5]), Vector2i(2, 1))
	var result: SaveResult = _encode(model)
	var collapsed: String = result.text.replace("\n", "").replace(" ", "")
	assert_str(collapsed).contains('"size":[2,1]')


func test_flat_heightmap_written_as_zero_size_empty_data() -> void:
	var model: AquariumModel = AquariumModel.new(STAMP)
	var substrate: Dictionary = _parsed(model)["substrate"]
	var heightmap: Dictionary = substrate["heightmap"]
	assert_array(heightmap["size"]).is_equal([0.0, 0.0])
	assert_str(heightmap["data"]).is_equal("")


# --- the writer never writes what the reader refuses -----------------------------------------


func _break_item(defect: String, item: PlacedItem) -> void:
	match defect:
		"position inf":
			item.position = Vector3(INF, 0.0, 0.0)
		"position nan":
			item.position = Vector3(0.0, NAN, 0.0)
		"rotation inf":
			item.rotation_y = INF
		"rotation nan":
			item.rotation_y = NAN
		"scale inf":
			item.scale = INF
		"scale nan":
			item.scale = NAN
		"scale zero":
			item.scale = 0.0
		"scale negative":
			item.scale = -1.0
		"empty catalog id":
			item.catalog_id = &""
		"empty uid":
			item.uid = ""
		"uid too short":
			item.uid = "a1f3"
		"uid uppercase":
			item.uid = "A1B2C3D4"
		"uid not hex":
			item.uid = "g1b2c3d4"
		"uid too long":
			item.uid = "a1b2c3d45"
		"uid duplicates fish":
			item.uid = "f0000001"
		"colour nan":
			item.has_colour = true
			item.colour = Color(NAN, 0.0, 0.0)
		"colour inf alpha":
			item.has_colour = true
			item.colour = Color(0.0, 0.0, 0.0, INF)
		_:
			fail("unknown item defect %s" % defect)


func _break_fish(defect: String, fish: FishInstance) -> void:
	match defect:
		"variant -1":
			fish.variant = -1
		"variant 256":
			fish.variant = 256
		"empty species id":
			fish.species_id = &""
		"fish uid empty":
			fish.uid = ""
		"fish uid uppercase":
			fish.uid = "F0000001"
		"fish uid duplicates item":
			fish.uid = "a0000001"
		_:
			fail("unknown fish defect %s" % defect)


func _bad_models() -> Array:
	var cases: Array = []
	for defect: String in ITEM_DEFECTS:
		var model: AquariumModel = SaveFixtures.populated_model()
		_break_item(defect, model.get_item_at(0))
		cases.append([defect, model, STAMP])
	var other_item: AquariumModel = SaveFixtures.populated_model()
	other_item.get_item_at(1).uid = "a0000001"
	cases.append(["uid duplicates another item", other_item, STAMP])
	for defect: String in FISH_DEFECTS:
		var model: AquariumModel = SaveFixtures.populated_model()
		_break_fish(defect, model.get_fish_at(0))
		cases.append([defect, model, STAMP])
	var twin: AquariumModel = SaveFixtures.populated_model()
	twin.get_fish_at(1).uid = "f0000001"
	cases.append(["uid duplicates another fish", twin, STAMP])
	var substrate_nan: AquariumModel = SaveFixtures.populated_model()
	substrate_nan.apply_set_substrate(&"sand", Color(NAN, 0.0, 0.0))
	cases.append(["substrate colour nan", substrate_nan, STAMP])
	var heightmap_cases: Array = [
		["heightmap side 1025", PackedFloat32Array(), Vector2i(1025, 1)],
		["heightmap too short", PackedFloat32Array([0.0, 0.0, 0.0]), Vector2i(2, 2)],
		["heightmap too long", PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0]), Vector2i(2, 2)],
		["heightmap inf", PackedFloat32Array([0.0, INF]), Vector2i(2, 1)],
		["heightmap nan", PackedFloat32Array([NAN, 0.0]), Vector2i(2, 1)],
		["heightmap negative size", PackedFloat32Array(), Vector2i(-1, 2)],
		["heightmap zero by zero with data", PackedFloat32Array([0.0]), Vector2i(0, 0)],
		["heightmap one dimension zero", PackedFloat32Array(), Vector2i(0, 3)],
		["heightmap other dimension zero", PackedFloat32Array(), Vector2i(3, 0)],
	]
	for entry: Array in heightmap_cases:
		var model: AquariumModel = SaveFixtures.populated_model()
		var values: PackedFloat32Array = entry[1]
		var size: Vector2i = entry[2]
		if entry[0] == "heightmap side 1025":
			values.resize(1025)
		model.apply_set_heightmap(values, size)
		cases.append([entry[0], model, STAMP])
	var bad_created: AquariumModel = SaveFixtures.populated_model()
	bad_created.set_save_times("2026-13-45T00:00:00Z", SaveFixtures.STAMP_MODIFIED)
	cases.append(["malformed created", bad_created, STAMP])
	var text_created: AquariumModel = SaveFixtures.populated_model()
	text_created.set_save_times("yesterday", SaveFixtures.STAMP_MODIFIED)
	cases.append(["created is not a stamp", text_created, STAMP])
	for bad_stamp: String in ["", "now", "2026-11-01 12:00:00Z", "2026-02-30T12:00:00Z"]:
		cases.append(["clock stamp '%s'" % bad_stamp, SaveFixtures.populated_model(), bad_stamp])
	return cases


func test_writer_refuses_every_reader_rule() -> void:
	var reference: SaveResult = _encode(SaveFixtures.populated_model())
	assert_int(reference.kind).is_equal(SaveResult.Kind.OK)
	var failures: PackedStringArray = PackedStringArray()
	for case: Array in _bad_models():
		var model: AquariumModel = case[1]
		var result: SaveResult = _encode(model, case[2])
		if result.kind != SaveResult.Kind.INTERNAL:
			failures.append("%s: kind %d, expected INTERNAL" % [case[0], result.kind])
		elif not result.text.is_empty():
			failures.append("%s: INTERNAL result still carries text" % case[0])
	assert_array(failures).is_empty()


func test_writer_refuses_a_model_over_the_reader_file_limit() -> void:
	var model: AquariumModel = SaveFixtures.populated_model()
	model.apply_set_name("a".repeat(SaveFixtures.MAX_FILE_BYTES))
	var result: SaveResult = _encode(model)
	assert_int(result.kind).is_equal(SaveResult.Kind.INTERNAL)
	assert_str(result.text).is_empty()


func test_writer_refusal_has_a_developer_detail() -> void:
	var model: AquariumModel = SaveFixtures.populated_model()
	model.get_item_at(0).scale = INF
	var result: SaveResult = _encode(model)
	assert_int(result.kind).is_equal(SaveResult.Kind.INTERNAL)
	assert_bool(result.is_ok()).is_false()
	assert_str(result.detail).is_not_empty()
	assert_object(result.model).is_null()


func test_writer_accepts_the_format_limits() -> void:
	var model: AquariumModel = SaveFixtures.populated_model()
	var values: PackedFloat32Array = PackedFloat32Array()
	values.resize(1024)
	model.apply_set_heightmap(values, Vector2i(1024, 1))
	model.get_fish_at(0).variant = 255
	assert_int(_encode(model).kind).is_equal(SaveResult.Kind.OK)
