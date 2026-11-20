extends GdUnitTestSuite
## #32 AC 9, 11 and 12 (owner: developer): the save format is unchanged. A coloured amphora saves
## its colour as "#RRGGBB" and loads with the same colour; Original colour saves as "colour": null;
## a colour on an item that is not colourable (and a colour that is in no swatch list) is kept
## unchanged by the catalog-free codec; load then re-save gives identical text; two items keep
## their own colours. The codec, SaveRules and the migrations are not changed by #32, so the
## encode/decode tests are guards that pass before the implementation; only the test that records
## the colour through RecolourItemCommand needs the new command.

const Api := preload("res://tests/helpers/edit_api.gd")
const Factory := preload("res://tests/helpers/factory.gd")
const ModelState := preload("res://tests/helpers/model_state.gd")
const SaveFixtures := preload("res://tests/helpers/save_fixtures.gd")

const STAMP := "2026-11-01T12:00:00Z"
const TEAL := Color8(0x2A, 0x7F, 0x9E)
const BRICK := Color8(0xB5, 0x4A, 0x33)


func _model() -> AquariumModel:
	var model: AquariumModel = AquariumModel.new(STAMP)
	model.apply_set_tank_id(&"tank_medium_1")
	var first: PlacedItem = Factory.coloured_item("a0000001", TEAL)
	first.catalog_id = &"clay_amphora"
	model.apply_insert_item(first, 0)
	var second: PlacedItem = Factory.coloured_item("a0000002", BRICK)
	second.catalog_id = &"clay_amphora"
	model.apply_insert_item(second, 1)
	var stone: PlacedItem = Factory.coloured_item("a0000003", Color8(0x12, 0x34, 0x56))
	stone.catalog_id = &"river_stone"
	model.apply_insert_item(stone, 2)
	var plain: PlacedItem = Factory.item("a0000004", &"clay_amphora")
	model.apply_insert_item(plain, 3)
	return model


func _encode(model: AquariumModel) -> String:
	var result: SaveResult = SaveCodec.new().encode(model, STAMP)
	assert_int(result.kind).is_equal(SaveResult.Kind.OK)
	return result.text


func _decode(text: String) -> AquariumModel:
	var result: SaveResult = SaveCodec.new().decode(text, STAMP)
	assert_int(result.kind).is_equal(SaveResult.Kind.OK)
	return SaveFixtures.model_of(result)


func _items_of(text: String) -> Array:
	var parsed: Variant = JSON.parse_string(text)
	assert_bool(parsed is Dictionary).is_true()
	var document: Dictionary = parsed if parsed is Dictionary else {}
	return document.get("items", [])


func test_ac11_each_amphora_keeps_its_own_colour_through_save_and_load() -> void:
	var model: AquariumModel = _model()
	var loaded: AquariumModel = _decode(_encode(model))
	assert_dict(ModelState.snapshot_8bit(loaded)).is_equal(ModelState.snapshot_8bit(model))
	assert_int(loaded.get_item("a0000001").colour.to_rgba32()).is_equal(TEAL.to_rgba32())
	assert_int(loaded.get_item("a0000002").colour.to_rgba32()).is_equal(BRICK.to_rgba32())
	assert_bool(loaded.get_item("a0000004").has_colour).is_false()


func test_ac11_the_saved_item_keeps_the_existing_keys_and_a_hex_colour() -> void:
	var items: Array = _items_of(_encode(_model()))
	var keys: Array = (items[0] as Dictionary).keys()
	keys.sort()
	var expected: Array = ["uid", "catalog_id", "position", "rotation_y", "scale", "colour"]
	expected.sort()
	assert_array(keys).is_equal(expected)
	assert_str(str((items[0] as Dictionary)["colour"]).to_upper()).is_equal("#2A7F9E")


func test_ac09_an_item_without_colour_saves_colour_null() -> void:
	var items: Array = _items_of(_encode(_model()))
	assert_that((items[3] as Dictionary)["colour"]).is_null()


func test_ac09_original_colour_through_the_command_saves_null_and_undo_saves_the_colour() -> void:
	if not Api.exists(Api.RECOLOUR):
		assert_bool(false).override_failure_message("recolour_item_command.gd is missing").is_true()
		return
	var model: AquariumModel = _model()
	var history: CommandHistory = CommandHistory.new()
	(
		assert_bool(history.execute(Api.recolour_command(model, "a0000001", false, Color.WHITE)))
		. is_true()
	)
	var saved: Array = _items_of(_encode(model))
	assert_that((saved[0] as Dictionary)["colour"]).is_null()
	assert_bool(_decode(_encode(model)).get_item("a0000001").has_colour).is_false()
	assert_bool(history.undo()).is_true()
	saved = _items_of(_encode(model))
	assert_str(str((saved[0] as Dictionary)["colour"]).to_upper()).is_equal("#2A7F9E")


func test_ac12_a_colour_on_an_item_that_is_not_colourable_is_kept_unchanged() -> void:
	var loaded: AquariumModel = _decode(_encode(_model()))
	var stone: PlacedItem = loaded.get_item("a0000003")
	assert_bool(stone.has_colour).is_true()
	assert_int(stone.colour.to_rgba32()).is_equal(Color8(0x12, 0x34, 0x56).to_rgba32())


func test_ac12_load_then_re_save_gives_identical_text() -> void:
	var first: String = _encode(_model())
	var second: String = _encode(_decode(first))
	assert_str(second).is_equal(first)


func test_ac12_an_item_with_an_unknown_catalog_id_and_a_colour_survives() -> void:
	var model: AquariumModel = _model()
	var ghost: PlacedItem = Factory.coloured_item("a0000005", BRICK)
	ghost.catalog_id = &"no_such_item"
	model.apply_insert_item(ghost, 4)
	var first: String = _encode(model)
	var loaded: AquariumModel = _decode(first)
	assert_int(loaded.get_item("a0000005").colour.to_rgba32()).is_equal(BRICK.to_rgba32())
	assert_str(_encode(loaded)).is_equal(first)
