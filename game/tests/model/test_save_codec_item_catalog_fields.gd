extends GdUnitTestSuite
## #152 criterion 11 (owner: developer): the Mode 2 data of an item definition never reaches a
## save. The codec writes only the catalog_id of a placed item. The test fails the day a Mode 2
## value is added to the save: (a) the key set of a saved item is the one the codec writes today,
## (b) no Mode 2 property name of ItemDefinition (read by reflection, so a new field is covered
## without editing this test) appears as a key or a string value anywhere in the document. The
## Mode 1 names are left out: `id` is also the save key `substrate.id`.

const Items := preload("res://tests/helpers/item_api.gd")
const Factory := preload("res://tests/helpers/factory.gd")
const STAMP := "2026-11-01T12:00:00Z"
const ITEM_KEYS: Array[String] = ["uid", "catalog_id", "position", "rotation_y", "scale", "colour"]


func _saved_document() -> Dictionary:
	var model: AquariumModel = AquariumModel.new(STAMP)
	model.apply_set_tank_id(&"tank_medium_1")
	model.apply_insert_item(Factory.item("a0000001", &"round_item"), 0)
	var result: SaveResult = SaveCodec.new().encode(model, STAMP)
	(
		assert_bool(result.is_ok())
		. override_failure_message("encode failed: %s" % result.detail)
		. is_true()
	)
	var parsed: Variant = JSON.parse_string(result.text)
	assert_bool(parsed is Dictionary).is_true()
	return parsed if parsed is Dictionary else {}


func _mode_2_names() -> Array[String]:
	var names: Array[String] = []
	for field: String in Items.property_names():
		if not Items.MODE_1.has(field):
			names.append(field)
	return names


## Every key and every string value at any depth.
func _all_strings(node: Variant, into: Array[String]) -> void:
	if node is Dictionary:
		var dictionary: Dictionary = node
		for key: Variant in dictionary:
			into.append(String(key))
			_all_strings(dictionary[key], into)
	elif node is Array:
		var list: Array = node
		for entry: Variant in list:
			_all_strings(entry, into)
	elif node is String:
		into.append(node)


func test_ac11_the_fixture_has_non_default_mode_2_values() -> void:
	var cat: RefCounted = Items.fixture("round_trip")
	assert_bool(Items.has_api(cat)).override_failure_message("ItemCatalog is missing").is_true()
	var definition: Resource = Items.definition(cat, &"round_item")
	assert_object(definition).is_not_null()
	if definition == null:
		return
	assert_float(definition.get("weight_kg")).is_not_equal(0.0)
	assert_int(definition.get("growth_form")).is_not_equal(0)


func test_ac11_the_mode_2_names_are_read_from_the_class() -> void:
	var names: Array[String] = _mode_2_names()
	(
		assert_bool(Items.script_exists(Items.DEFINITION_PATH))
		. override_failure_message("ItemDefinition is missing")
		. is_true()
	)
	assert_int(names.size()).is_equal(Items.COMMON.size() + Items.PLANT.size())
	assert_bool(names.has("weight_kg")).is_true()
	assert_bool(names.has("provides_cover")).is_true()
	assert_bool(names.has("id")).is_false()


func test_ac11_a_saved_item_has_exactly_the_keys_the_codec_writes_today() -> void:
	var document: Dictionary = _saved_document()
	var items: Array = document.get("items", [])
	assert_int(items.size()).is_equal(1)
	if items.is_empty():
		return
	var item: Dictionary = items[0]
	var keys: Array[String] = []
	for key: Variant in item.keys():
		keys.append(String(key))
	keys.sort()
	var expected: Array[String] = ITEM_KEYS.duplicate()
	expected.sort()
	assert_array(keys).is_equal(expected)
	assert_str(String(item["catalog_id"])).is_equal("round_item")


func test_ac11_no_mode_2_property_name_appears_anywhere_in_the_save() -> void:
	var names: Array[String] = _mode_2_names()
	assert_int(names.size()).override_failure_message("no Mode 2 names found").is_greater(0)
	var strings: Array[String] = []
	_all_strings(_saved_document(), strings)
	assert_int(strings.size()).is_greater(0)
	for field: String in names:
		(
			assert_bool(strings.has(field))
			. override_failure_message("the save contains the Mode 2 name %s" % field)
			. is_false()
		)


func test_ac11_the_save_text_holds_no_mode_2_value_of_the_fixture() -> void:
	var model: AquariumModel = AquariumModel.new(STAMP)
	model.apply_set_tank_id(&"tank_medium_1")
	model.apply_insert_item(Factory.item("a0000001", &"round_item"), 0)
	var result: SaveResult = SaveCodec.new().encode(model, STAMP)
	for needle: String in ["0.37", "12.37", "tannin", "growth", "footprint"]:
		assert_str(result.text).override_failure_message(needle).not_contains(needle)
