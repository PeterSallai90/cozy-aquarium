extends GdUnitTestSuite

const Factory := preload("res://tests/helpers/factory.gd")
const ModelState := preload("res://tests/helpers/model_state.gd")
const SaveFixtures := preload("res://tests/helpers/save_fixtures.gd")

const STAMP := "2026-11-01T12:00:00Z"


func _encode(model: AquariumModel) -> SaveResult:
	var result: SaveResult = SaveCodec.new().encode(model, model.get_modified())
	assert_int(result.kind).is_equal(SaveResult.Kind.OK)
	return result


## Saves with the model's own `modified`, so a loaded copy is expected to be equal.
func _round_trip(model: AquariumModel) -> AquariumModel:
	var text: String = _encode(model).text
	var decoded: SaveResult = SaveCodec.new().decode(text, STAMP)
	assert_int(decoded.kind).is_equal(SaveResult.Kind.OK)
	assert_object(decoded.model).is_not_null()
	return SaveFixtures.model_of(decoded)


func test_populated_model_round_trips() -> void:
	var model: AquariumModel = SaveFixtures.populated_model()
	var loaded: AquariumModel = _round_trip(model)
	assert_dict(ModelState.snapshot_8bit(loaded)).is_equal(ModelState.snapshot_8bit(model))


func test_created_and_modified_round_trip() -> void:
	var model: AquariumModel = SaveFixtures.populated_model()
	model.set_save_times("2026-01-02T03:04:05Z", "2026-05-06T07:08:09Z")
	var loaded: AquariumModel = _round_trip(model)
	assert_str(loaded.get_created()).is_equal("2026-01-02T03:04:05Z")
	assert_str(loaded.get_modified()).is_equal("2026-05-06T07:08:09Z")
	assert_dict(ModelState.snapshot_8bit(loaded)).is_equal(ModelState.snapshot_8bit(model))


func test_alpha_survives_on_substrate_and_item() -> void:
	var model: AquariumModel = AquariumModel.new(STAMP)
	model.apply_set_substrate(&"glass_beads", Color8(0x10, 0x20, 0x30, 0x40))
	var item: PlacedItem = Factory.coloured_item("a0000001", Color8(0x50, 0x60, 0x70, 0x80))
	model.apply_insert_item(item, 0)
	var loaded: AquariumModel = _round_trip(model)
	assert_int(roundi(loaded.get_substrate_colour().a * 255.0)).is_equal(0x40)
	var loaded_item: PlacedItem = loaded.get_item("a0000001")
	assert_bool(loaded_item.has_colour).is_true()
	assert_int(roundi(loaded_item.colour.a * 255.0)).is_equal(0x80)
	assert_dict(ModelState.snapshot_8bit(loaded)).is_equal(ModelState.snapshot_8bit(model))


func test_item_without_colour_stays_without_colour() -> void:
	var loaded: AquariumModel = _round_trip(SaveFixtures.populated_model())
	assert_bool(loaded.get_item("a0000002").has_colour).is_false()
	assert_bool(loaded.get_item("a0000001").has_colour).is_true()


func test_decode_then_encode_same_bytes() -> void:
	var codec: SaveCodec = SaveCodec.new()
	var first: String = _encode(SaveFixtures.populated_model()).text
	var decoded: SaveResult = codec.decode(first, STAMP)
	assert_int(decoded.kind).is_equal(SaveResult.Kind.OK)
	var second: SaveResult = codec.encode(
		SaveFixtures.model_of(decoded), SaveFixtures.model_of(decoded).get_modified()
	)
	assert_int(second.kind).is_equal(SaveResult.Kind.OK)
	assert_bool(second.text.to_utf8_buffer() == first.to_utf8_buffer()).is_true()


func test_decode_then_encode_same_bytes_for_non_8bit_colours() -> void:
	# Colours that are not 8 bit exact are rounded on the first save; the second save is stable.
	var model: AquariumModel = SaveFixtures.populated_model()
	model.apply_set_substrate(&"sand", Color(0.123456, 0.654321, 0.999999, 0.333333))
	var codec: SaveCodec = SaveCodec.new()
	var first: String = _encode(model).text
	var decoded: SaveResult = codec.decode(first, STAMP)
	var second: SaveResult = codec.encode(
		SaveFixtures.model_of(decoded), SaveFixtures.model_of(decoded).get_modified()
	)
	assert_bool(second.text.to_utf8_buffer() == first.to_utf8_buffer()).is_true()


func test_decode_of_the_golden_file_then_encode_same_bytes() -> void:
	var codec: SaveCodec = SaveCodec.new()
	var decoded: SaveResult = codec.decode_bytes(
		SaveFixtures.read_bytes(SaveFixtures.GOLDEN_PATH), STAMP
	)
	assert_int(decoded.kind).is_equal(SaveResult.Kind.OK)
	var first: SaveResult = codec.encode(
		SaveFixtures.model_of(decoded), SaveFixtures.model_of(decoded).get_modified()
	)
	var again: SaveResult = codec.decode(first.text, STAMP)
	var second: SaveResult = codec.encode(
		SaveFixtures.model_of(again), SaveFixtures.model_of(again).get_modified()
	)
	assert_bool(second.text.to_utf8_buffer() == first.text.to_utf8_buffer()).is_true()


func test_empty_model_round_trips_flat() -> void:
	var model: AquariumModel = AquariumModel.new(STAMP)
	var loaded: AquariumModel = _round_trip(model)
	assert_dict(ModelState.snapshot_8bit(loaded)).is_equal(ModelState.snapshot_8bit(model))
	assert_int(loaded.get_heightmap().size()).is_equal(0)
	assert_bool(loaded.get_heightmap_size() == Vector2i.ZERO).is_true()
	assert_int(loaded.get_item_count()).is_equal(0)
	assert_int(loaded.get_fish_count()).is_equal(0)


func _strings() -> Array[String]:
	var thousand: String = "x".repeat(1000)
	var mixed: String = "aé" + "z".repeat(998)
	return [
		"",
		"Árvíztűrő tükörfúrógép",
		"熱帯魚",
		"열대어",
		"Привет, мир",
		"🐠🐟 emoji 🌊",
		thousand,
		mixed,
		"quote \" and ' marks",
		"back\\slash and \\n literal",
		"line one\nline two\r\nline three",
		"tab\there",
		"control \u0001 and \u000b and \u001f characters",
		"slash / less < greater > ampersand &",
	]


func test_strings_round_trip() -> void:
	var failures: PackedStringArray = PackedStringArray()
	for text: String in _strings():
		var model: AquariumModel = AquariumModel.new(STAMP)
		model.apply_set_name(text)
		model.apply_set_tank_id(StringName(text))
		model.apply_insert_fish(Factory.fish("f0000001", &"neon_tetra", 0, text), 0)
		var loaded: AquariumModel = _round_trip(model)
		if loaded.get_aquarium_name() != text:
			failures.append("name changed for '%s'" % text.left(20))
		if loaded.get_fish_at(0).nickname != text:
			failures.append("nickname changed for '%s'" % text.left(20))
		if loaded.get_tank_id() != StringName(text):
			failures.append("tank id changed for '%s'" % text.left(20))
	assert_array(failures).is_empty()


func test_encoded_bytes_are_valid_utf8_without_raw_control_characters() -> void:
	var failures: PackedStringArray = PackedStringArray()
	for text: String in _strings():
		var model: AquariumModel = AquariumModel.new(STAMP)
		model.apply_set_name(text)
		model.apply_insert_fish(Factory.fish("f0000001", &"neon_tetra", 0, text), 0)
		var bytes: PackedByteArray = _encode(model).text.to_utf8_buffer()
		if bytes.get_string_from_utf8().to_utf8_buffer() != bytes:
			failures.append("not valid UTF-8 for '%s'" % text.left(20))
		for value: int in bytes:
			if value < 0x20 and value != 0x0A:
				failures.append("raw control byte %d for '%s'" % [value, text.left(20)])
				break
	assert_array(failures).is_empty()


func test_floats_round_trip_exactly() -> void:
	var model: AquariumModel = AquariumModel.new(STAMP)
	var values: PackedFloat32Array = PackedFloat32Array(
		[0.1, 1.0 / 3.0, 1e-7, 0.123456789, 12345.678, 1e20, -0.1, 3.4e38]
	)
	model.apply_set_heightmap(values, Vector2i(8, 1))
	var first: PlacedItem = Factory.item(
		"a0000001", &"rock_a", Vector3(0.1, 1.0 / 3.0, 1e-7), 0.1, 1.0 / 3.0
	)
	var second: PlacedItem = Factory.item(
		"a0000002", &"rock_a", Vector3(-0.123456789, 1234.5678, -1e-7), 123456.78901234567, 1e-7
	)
	var third: PlacedItem = Factory.item(
		"a0000003", &"rock_a", Vector3.ZERO, 1.2345678901234567e-7, 1.2345678901234567e-7
	)
	var fourth: PlacedItem = Factory.item("a0000004", &"rock_a", Vector3.ONE, -1e20, 1e20)
	for item: PlacedItem in [first, second, third, fourth]:
		model.apply_insert_item(item, model.get_item_count())
	var loaded: AquariumModel = _round_trip(model)
	assert_dict(ModelState.snapshot_8bit(loaded)).is_equal(ModelState.snapshot_8bit(model))
	var failures: PackedStringArray = PackedStringArray()
	for item: PlacedItem in model.get_items():
		var other: PlacedItem = loaded.get_item(item.uid)
		if var_to_bytes(other.rotation_y) != var_to_bytes(item.rotation_y):
			failures.append(
				"rotation_y of %s: %.17g vs %.17g" % [item.uid, other.rotation_y, item.rotation_y]
			)
		if var_to_bytes(other.scale) != var_to_bytes(item.scale):
			failures.append("scale of %s: %.17g vs %.17g" % [item.uid, other.scale, item.scale])
		if other.position != item.position:
			failures.append("position of %s" % item.uid)
	var loaded_values: PackedFloat32Array = loaded.get_heightmap()
	for index: int in values.size():
		if loaded_values[index] != values[index]:
			failures.append("heightmap value %d" % index)
	assert_array(failures).is_empty()


func test_random_doubles_round_trip_exactly() -> void:
	# Godot's JSON parser reads long decimals with an error of a few units in the last place,
	# which a few fixed sample values do not show. Random 64-bit values do.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 2026
	var model: AquariumModel = AquariumModel.new(STAMP)
	var uids: UidGenerator = UidGenerator.new(5)
	for index: int in 300:
		var item: PlacedItem = Factory.item(uids.generate(model))
		item.rotation_y = rng.randf_range(-720.0, 720.0) + rng.randf() * 1e-9
		item.scale = rng.randf_range(0.1, 5.0) + rng.randf() * 1e-9
		model.apply_insert_item(item, model.get_item_count())
	var loaded: AquariumModel = _round_trip(model)
	var wrong: int = 0
	for index: int in 300:
		var before: PlacedItem = model.get_item_at(index)
		var after: PlacedItem = loaded.get_item_at(index)
		if after == null or after.rotation_y != before.rotation_y or after.scale != before.scale:
			wrong += 1
	assert_int(wrong).is_equal(0)


func test_d18_tank_round_trips() -> void:
	var model: AquariumModel = SaveFixtures.d18_model()
	assert_int(model.get_fish_count()).is_equal(60)
	assert_int(model.get_item_count()).is_equal(100)
	var loaded: AquariumModel = _round_trip(model)
	assert_dict(ModelState.snapshot_8bit(loaded)).is_equal(ModelState.snapshot_8bit(model))


func test_fish_identity_round_trips() -> void:
	var model: AquariumModel = SaveFixtures.populated_model()
	var loaded: AquariumModel = _round_trip(model)
	var failures: PackedStringArray = PackedStringArray()
	for index: int in model.get_fish_count():
		var before: FishInstance = model.get_fish_at(index)
		var after: FishInstance = loaded.get_fish_at(index)
		if after == null:
			failures.append("fish %d missing" % index)
			continue
		if after.uid != before.uid or after.species_id != before.species_id:
			failures.append("identity of fish %d" % index)
		if after.variant != before.variant or after.nickname != before.nickname:
			failures.append("variant or nickname of fish %d" % index)
	assert_array(failures).is_empty()
	assert_int(loaded.get_fish_count()).is_equal(3)


func test_unknown_keys_dropped_on_save() -> void:
	var data: Dictionary = SaveFixtures.base_dict()
	data["extra_top"] = {"a": 1}
	var substrate: Dictionary = data["substrate"]
	substrate["extra_substrate"] = true
	var items: Array = data["items"]
	var item: Dictionary = items[0]
	item["extra_item"] = "x"
	var fish: Array = data["fish"]
	var member: Dictionary = fish[0]
	member["personality"] = 0.5
	var codec: SaveCodec = SaveCodec.new()
	var decoded: SaveResult = codec.decode(SaveFixtures.to_text(data), STAMP)
	assert_int(decoded.kind).is_equal(SaveResult.Kind.OK)
	var written: SaveResult = codec.encode(
		SaveFixtures.model_of(decoded), SaveFixtures.model_of(decoded).get_modified()
	)
	assert_str(written.text).not_contains("extra_")
	assert_str(written.text).not_contains("personality")
	var clean: SaveResult = codec.encode(
		SaveFixtures.model_of(codec.decode(SaveFixtures.to_text(SaveFixtures.base_dict()), STAMP)),
		STAMP
	)
	var again: SaveResult = codec.encode(SaveFixtures.model_of(decoded), STAMP)
	assert_str(again.text).is_equal(clean.text)
