extends GdUnitTestSuite
## #31 AC 31 (owner: developer): placed, moved and rotated items survive a SaveCodec round trip
## with the same uid, catalog_id, position, rotation_y and scale; free angles (37, one just below
## 360) and free positions come back equal. SaveCodec and the save format do not change in #31,
## so this suite is a guard that passes before the implementation too (no missing behaviour to
## fail on); it pins the rule for the later changes. The drawn items after a load match the drawn
## items before (a scene check) is in test_placed_items_view.gd.

const Factory := preload("res://tests/helpers/factory.gd")
const ModelState := preload("res://tests/helpers/model_state.gd")
const SaveFixtures := preload("res://tests/helpers/save_fixtures.gd")

const STAMP := "2026-11-01T12:00:00Z"


func _round_trip(model: AquariumModel) -> AquariumModel:
	var encoded: SaveResult = SaveCodec.new().encode(model, model.get_modified())
	assert_int(encoded.kind).is_equal(SaveResult.Kind.OK)
	var decoded: SaveResult = SaveCodec.new().decode(encoded.text, STAMP)
	assert_int(decoded.kind).is_equal(SaveResult.Kind.OK)
	return SaveFixtures.model_of(decoded)


func _model() -> AquariumModel:
	var model: AquariumModel = AquariumModel.new(STAMP)
	model.apply_set_tank_id(&"tank_medium_1")
	model.apply_insert_item(
		Factory.item("a0000001", &"river_stone", Vector3(0.12345, 0, -0.0567), 37.0, 1.0), 0
	)
	model.apply_insert_item(
		Factory.item("a0000002", &"driftwood_branch", Vector3(-0.3, 0, 0.15), 359.99, 1.0), 1
	)
	model.apply_insert_item(
		Factory.item("a0000003", &"clay_amphora", Vector3(0.0, 0, 0.0), 0.0, 1.0), 2
	)
	return model


func test_ac31_free_angles_free_positions_uid_catalog_id_and_scale_round_trip() -> void:
	var model: AquariumModel = _model()
	var loaded: AquariumModel = _round_trip(model)
	assert_dict(ModelState.snapshot_8bit(loaded)).is_equal(ModelState.snapshot_8bit(model))
	var first: PlacedItem = loaded.get_item("a0000001")
	assert_float(first.rotation_y).is_equal(37.0)
	assert_vector(first.position).is_equal(Vector3(0.12345, 0.0, -0.0567))
	assert_float(loaded.get_item("a0000002").rotation_y).is_equal(359.99)


func test_ac31_a_moved_and_rotated_item_round_trips_in_the_same_list_order() -> void:
	var model: AquariumModel = _model()
	var moved: PlacedItem = model.get_item("a0000002").copy()
	moved.position = Vector3(0.2718, 0.0, -0.1414)
	moved.rotation_y = 123.5
	model.apply_replace_item(moved)
	var loaded: AquariumModel = _round_trip(model)
	assert_dict(ModelState.snapshot_8bit(loaded)).is_equal(ModelState.snapshot_8bit(model))
	assert_int(loaded.get_item_index("a0000002")).is_equal(1)


func test_ac31_the_loader_accepts_any_finite_angle_such_as_the_sample_minus_90() -> void:
	var model: AquariumModel = _model()
	var odd: PlacedItem = model.get_item("a0000003").copy()
	odd.rotation_y = -90.0
	model.apply_replace_item(odd)
	var loaded: AquariumModel = _round_trip(model)
	assert_float(loaded.get_item("a0000003").rotation_y).is_equal(-90.0)
