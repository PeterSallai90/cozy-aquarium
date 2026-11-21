extends GdUnitTestSuite
## #31 AC 13, 14, 29 and 30 (owner: developer): PlaceItemCommand(model, item, rules). The command
## receives the complete item with its uid, appends it in do() and re-inserts it at the recorded
## index on redo; undo removes it. A used uid, a missing item, a point outside the interior or a
## non-finite value make do() return false with the model untouched and no signal. The command
## changes the model only through the apply_* methods (created and modified stay as they were).
## Test decision: the engine output of a rejected do() is not pinned (the plan does not say whether
## it logs); the rejected cases run under EngineOutput.capture so either way passes.
## #33 AC 14 (owner: developer): the command refuses every invalid spot of PlacementRules (overlap,
## through the glass, degenerate data) with the model unchanged, no signal and no history entry; the
## sequence place A, place B beside it, undo B, place C on the spot of B works. The fixture items
## of #31 are spread out (the stone is 11 x 8 cm, turned by 37 degrees it needs about 14 cm).

const Api := preload("res://tests/helpers/placement_api.gd")
const Factory := preload("res://tests/helpers/factory.gd")
const ModelState := preload("res://tests/helpers/model_state.gd")
const Recorder := preload("res://tests/helpers/signal_recorder.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")

var _rules: RefCounted = null
var _history: CommandHistory = null
var _undo_before: int = 0


func before_test() -> void:
	_rules = Api.rules()
	_history = CommandHistory.new()


func _have() -> bool:
	var found: bool = Api.exists(Api.PLACE) and Api.exists(Api.RULES)
	(
		assert_bool(found)
		. override_failure_message("place_item_command.gd or placement_rules.gd is missing")
		. is_true()
	)
	return found


func _model() -> AquariumModel:
	var model: AquariumModel = AquariumModel.new("2026-11-01T12:00:00Z")
	model.apply_set_tank_id(&"tank_medium_1")
	return model


func _item(uid: String, x: float = 0.1234, z: float = -0.0567) -> PlacedItem:
	return Factory.item(uid, &"river_stone", Vector3(x, 0.0, z), 37.0, 1.0)


func _place(model: AquariumModel, item: PlacedItem) -> bool:
	return _history.execute(Api.place_command(model, item, _rules))


func _uids(model: AquariumModel) -> Array[String]:
	var uids: Array[String] = []
	for item: PlacedItem in model.get_items():
		uids.append(item.uid)
	return uids


func test_ac29_the_command_is_a_command_subclass() -> void:
	if not _have():
		return
	var command: Command = Api.place_command(_model(), _item("a0000001"), _rules)
	assert_object(command).is_not_null()
	assert_bool(command is Command).is_true()


func test_ac13_do_appends_the_given_item_with_one_item_added() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	var recorder: Recorder = Recorder.new()
	recorder.watch(model)
	assert_bool(_place(model, _item("a0000001"))).is_true()
	assert_int(model.get_item_count()).is_equal(1)
	var stored: PlacedItem = model.get_item("a0000001")
	assert_object(stored).is_not_null()
	assert_that(stored.catalog_id).is_equal(&"river_stone")
	assert_vector(stored.position).is_equal(Vector3(0.1234, 0.0, -0.0567))
	assert_float(stored.rotation_y).is_equal(37.0)
	assert_float(stored.scale).is_equal(1.0)
	assert_bool(stored.has_colour).is_false()
	assert_array(recorder.names()).is_equal(["item_added"])
	assert_array(recorder.args_of(0)).is_equal(["a0000001", 0])
	assert_int(_history.get_undo_count()).is_equal(1)


func test_ac14_undo_restores_the_state_before_every_field() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	_place(model, _item("a0000001", 0.0, 0.0))
	var state_before: Dictionary = ModelState.snapshot(model)
	assert_bool(_place(model, _item("a0000002"))).is_true()
	assert_bool(_history.undo()).is_true()
	assert_dict(ModelState.snapshot(model)).is_equal(state_before)


func test_ac14_undo_emits_one_item_removed_and_redo_one_item_added_at_the_same_index() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	_place(model, _item("a0000001", 0.0, 0.0))
	assert_bool(_place(model, _item("a0000002"))).is_true()
	var recorder: Recorder = Recorder.new()
	recorder.watch(model)
	assert_bool(_history.undo()).is_true()
	assert_array(recorder.names()).is_equal(["item_removed"])
	assert_array(recorder.args_of(0)).is_equal(["a0000002", 1])
	recorder.clear()
	assert_bool(_history.redo()).is_true()
	assert_array(recorder.names()).is_equal(["item_added"])
	assert_array(recorder.args_of(0)).is_equal(["a0000002", 1])
	assert_int(model.get_item_index("a0000002")).is_equal(1)


func test_ac14_several_placements_come_back_in_the_same_order_after_undo_and_redo() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	for uid: String in ["a0000001", "a0000002", "a0000003", "a0000004"]:
		(
			assert_bool(_place(model, _item(uid, -0.225 + 0.15 * model.get_item_count(), 0.0)))
			. is_true()
		)
	var order: Array[String] = _uids(model)
	var full: Dictionary = ModelState.snapshot(model)
	assert_bool(_history.undo()).is_true()
	assert_bool(_history.undo()).is_true()
	assert_array(_uids(model)).is_equal(["a0000001", "a0000002"])
	assert_bool(_history.redo()).is_true()
	assert_array(_uids(model)).is_equal(["a0000001", "a0000002", "a0000003"])
	assert_bool(_history.redo()).is_true()
	assert_array(_uids(model)).is_equal(order)
	assert_dict(ModelState.snapshot(model)).is_equal(full)


func test_ac14_redo_keeps_the_uid_of_the_first_do() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	assert_bool(_place(model, _item("a0000001"))).is_true()
	assert_bool(_history.undo()).is_true()
	assert_bool(model.has_uid("a0000001")).is_false()
	assert_bool(_history.redo()).is_true()
	assert_bool(model.has_uid("a0000001")).is_true()
	assert_int(model.get_item_count()).is_equal(1)


func test_ac29_do_is_repeatable_after_undo_when_called_directly() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	var command: Command = Api.place_command(model, _item("a0000001"), _rules)
	assert_bool(command.do()).is_true()
	assert_bool(command.undo()).is_true()
	assert_int(model.get_item_count()).is_equal(0)
	assert_bool(command.do()).is_true()
	assert_int(model.get_item_count()).is_equal(1)


func test_ac29_the_command_never_touches_created_or_modified() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	model.set_save_times("2026-01-01T00:00:00Z", "2026-02-02T00:00:00Z")
	assert_bool(_place(model, _item("a0000001"))).is_true()
	assert_str(model.get_created()).is_equal("2026-01-01T00:00:00Z")
	assert_str(model.get_modified()).is_equal("2026-02-02T00:00:00Z")
	assert_bool(_history.undo()).is_true()
	assert_str(model.get_created()).is_equal("2026-01-01T00:00:00Z")
	assert_str(model.get_modified()).is_equal("2026-02-02T00:00:00Z")


func _rejected(model: AquariumModel, item: PlacedItem) -> void:
	var state_before: Dictionary = ModelState.snapshot(model)
	var recorder: Recorder = Recorder.new()
	recorder.watch(model)
	var outcome: Array = []
	await EngineOutput.capture(func() -> void: outcome.append(_place(model, item)))
	assert_bool(outcome[0]).is_false()
	assert_dict(ModelState.snapshot(model)).is_equal(state_before)
	assert_int(recorder.count()).is_equal(0)
	assert_int(_history.get_undo_count()).is_equal(_undo_before)


func test_ac30_a_used_uid_is_refused_without_a_change_or_a_signal() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	assert_bool(_place(model, _item("a0000001"))).is_true()
	_undo_before = _history.get_undo_count()
	await _rejected(model, _item("a0000001", 0.0, 0.0))


func test_ac30_a_point_outside_the_interior_is_refused() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	_undo_before = 0
	await _rejected(model, _item("a0000001", 0.5, 0.0))


func test_ac30_a_non_finite_position_is_refused() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	_undo_before = 0
	await _rejected(model, _item("a0000001", NAN, 0.0))
	await _rejected(model, _item("a0000002", 0.0, INF))


func test_ac30_a_null_item_is_refused() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	_undo_before = 0
	await _rejected(model, null)


# --- #33 AC 14: the rules of validity ---


func test_ac14_an_overlapping_item_is_refused_without_a_change_a_signal_or_a_history_entry(
) -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	assert_bool(_place(model, _item("a0000001", 0.0, 0.0))).is_true()
	_undo_before = _history.get_undo_count()
	await _rejected(model, _item("a0000002", 0.05, 0.0))
	await _rejected(model, _item("a0000003", 0.0, 0.0))


func test_ac14_an_item_through_the_glass_is_refused() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	_undo_before = 0
	# The stone turned by 37 degrees reaches 6.8 cm in x: 0.2315 is flush, 0.27 is not.
	await _rejected(model, _item("a0000001", 0.27, 0.0))
	await _rejected(model, _item("a0000002", 0.0, 0.14))
	assert_bool(_place(model, _item("a0000003", 0.2315, 0.0))).is_true()


func test_ac14_a_degenerate_item_is_refused() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	_undo_before = 0
	await _rejected(model, Factory.item("a0000001", &"no_such_item", Vector3.ZERO, 0.0, 1.0))
	await _rejected(model, Factory.item("a0000002", &"river_stone", Vector3.ZERO, 0.0, 0.0))
	await _rejected(model, Factory.item("a0000003", &"river_stone", Vector3.ZERO, 0.0, -1.0))
	await _rejected(model, Factory.item("a0000004", &"river_stone", Vector3(0, 0.02, 0), 0.0, 1.0))
	await _rejected(model, Factory.item("a0000005", &"river_stone", Vector3(0, -0.02, 0), 0.0, 1.0))


func test_ac14_touching_items_are_both_placed() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	var first: PlacedItem = Factory.item("a0000001", &"river_stone", Vector3.ZERO, 0.0, 1.0)
	assert_bool(_place(model, first)).is_true()
	var beside: PlacedItem = Factory.item("a0000002", &"river_stone", Vector3(0.11, 0, 0), 0.0, 1.0)
	assert_bool(_place(model, beside)).is_true()
	assert_int(model.get_item_count()).is_equal(2)


func test_ac14_place_a_place_b_beside_undo_b_place_c_on_the_spot_of_b() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	var a: PlacedItem = Factory.item("a0000001", &"river_stone", Vector3(-0.1, 0, 0), 0.0, 1.0)
	var b: PlacedItem = Factory.item("a0000002", &"river_stone", Vector3(0.1, 0, 0), 0.0, 1.0)
	var c: PlacedItem = Factory.item("a0000003", &"river_stone", Vector3(0.1, 0, 0), 0.0, 1.0)
	assert_bool(_place(model, a)).is_true()
	assert_bool(_place(model, b)).is_true()
	# While B stands, another item on its spot is refused.
	var blocked: PlacedItem = Factory.item("a0000004", &"river_stone", Vector3(0.1, 0, 0), 0.0, 1.0)
	_undo_before = _history.get_undo_count()
	await _rejected(model, blocked)
	assert_bool(_history.undo()).is_true()
	assert_bool(model.has_uid("a0000002")).is_false()
	assert_bool(_place(model, c)).is_true()
	assert_array(_uids(model)).is_equal(["a0000001", "a0000003"])
	# Undo C and redo C: the uid stays.
	assert_bool(_history.undo()).is_true()
	assert_bool(_history.redo()).is_true()
	assert_array(_uids(model)).is_equal(["a0000001", "a0000003"])
