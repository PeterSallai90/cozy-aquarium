extends GdUnitTestSuite
## #33 AC 16, the load part (owner: developer): a save with overlapping items, items outside the
## interior, an item above the substrate and an item of an unknown catalog id decodes unchanged:
## loading never moves, clips, repairs or removes an item (#31 Q19, #38). SaveCodec and the save
## format do not change in #33, so the round trip part is a guard that passes before the
## implementation; the check that these items are really invalid for the new rules fails until the
## rules exist.

const Api := preload("res://tests/helpers/placement_api.gd")
const Factory := preload("res://tests/helpers/factory.gd")
const ModelState := preload("res://tests/helpers/model_state.gd")
const SaveFixtures := preload("res://tests/helpers/save_fixtures.gd")
const Fx := preload("res://tests/helpers/validity_fixtures.gd")

const STAMP := "2026-11-01T12:00:00Z"
const INVALID_UIDS: Array[String] = ["a0000001", "a0000002", "a0000003", "a0000004", "a0000006"]


func _messy_model() -> AquariumModel:
	var model: AquariumModel = Fx.model(Fx.MEDIUM, Fx.PEBBLES)
	# An overlapping pair, an item through the glass, an item turned into the glass, an item of an
	# unknown id and an item above the surface.
	model.apply_insert_item(Factory.item("a0000001", &"river_stone", Vector3.ZERO, 0.0, 1.0), 0)
	model.apply_insert_item(
		Factory.item("a0000002", &"river_stone", Vector3(0.02, 0, 0.01), 33.0, 1.0), 1
	)
	model.apply_insert_item(
		Factory.item("a0000003", &"driftwood_branch", Vector3(0.28, 0, 0.0), 0.0, 1.0), 2
	)
	model.apply_insert_item(
		Factory.item("a0000004", &"driftwood_branch", Vector3(0.0, 0, 0.14), 90.0, 1.0), 3
	)
	model.apply_insert_item(
		Factory.item("a0000005", &"gone_item", Vector3(0.1, 0, 0.1), 0.0, 1.0), 4
	)
	model.apply_insert_item(
		Factory.item("a0000006", &"clay_amphora", Vector3(-0.2, 0.05, -0.1), 0.0, 1.0), 5
	)
	return model


func _round_trip(model: AquariumModel) -> AquariumModel:
	var encoded: SaveResult = SaveCodec.new().encode(model, model.get_modified())
	assert_int(encoded.kind).is_equal(SaveResult.Kind.OK)
	var decoded: SaveResult = SaveCodec.new().decode(encoded.text, STAMP)
	assert_int(decoded.kind).is_equal(SaveResult.Kind.OK)
	return SaveFixtures.model_of(decoded)


func test_ac16_a_save_with_overlapping_and_outside_items_loads_unchanged() -> void:
	var model: AquariumModel = _messy_model()
	var loaded: AquariumModel = _round_trip(model)
	assert_dict(ModelState.snapshot_8bit(loaded)).is_equal(ModelState.snapshot_8bit(model))
	assert_int(loaded.get_item_count()).is_equal(6)
	assert_vector(loaded.get_item("a0000003").position).is_equal(Vector3(0.28, 0.0, 0.0))
	assert_vector(loaded.get_item("a0000006").position).is_equal(Vector3(-0.2, 0.05, -0.1))
	assert_float(loaded.get_item("a0000004").rotation_y).is_equal(90.0)
	assert_bool(loaded.has_uid("a0000005")).is_true()


func test_ac16_the_messy_items_are_really_invalid_for_the_new_rules() -> void:
	if not Api.exists(Api.RULES):
		return
	var rules: RefCounted = Api.rules()
	var loaded: AquariumModel = _round_trip(_messy_model())
	for uid: String in INVALID_UIDS:
		# Judged as a fresh placement against the rest of the save.
		var rest: AquariumModel = Fx.model(Fx.MEDIUM, Fx.PEBBLES)
		for item: PlacedItem in loaded.get_items():
			if item.uid != uid:
				rest.apply_insert_item(item.copy(), rest.get_item_count())
		var item: PlacedItem = loaded.get_item(uid)
		var again: PlacedItem = Factory.item(
			"c0000001", item.catalog_id, item.position, item.rotation_y, item.scale
		)
		(
			assert_bool(Fx.refused(rules, rest, again))
			. override_failure_message("%s must be invalid for the new rules" % uid)
			. is_true()
		)


func test_ac16_judging_the_items_changes_nothing_in_the_loaded_model() -> void:
	if not Api.exists(Api.RULES):
		return
	var rules: RefCounted = Api.rules()
	var loaded: AquariumModel = _round_trip(_messy_model())
	var state_before: Dictionary = ModelState.snapshot_8bit(loaded)
	for item: PlacedItem in loaded.get_items():
		Fx.ok(rules, loaded, item.copy(), item)
	assert_dict(ModelState.snapshot_8bit(loaded)).is_equal(state_before)
