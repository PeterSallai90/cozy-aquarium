extends GdUnitTestSuite
## #31 AC 23, 27, 29 and 30 (owner: developer): TransformItemCommand(model, uid, position,
## rotation_y, rules), used for the drop of a drag (position and rotation) and for the release of a
## rotate hold (rotation only). One item_changed per do, undo and redo; undo restores the exact
## start position and rotation; the uid, catalog_id, scale and colour stay; a missing uid or a point
## outside the interior makes do() return false with the model untouched and no signal. The Command
## base class stays as it is (AC 29: used unchanged), which is pinned here by its method list.
## Test decision: the engine output of a rejected do() is not pinned (see
## test_place_item_command.gd).

const Api := preload("res://tests/helpers/placement_api.gd")
const Factory := preload("res://tests/helpers/factory.gd")
const ModelState := preload("res://tests/helpers/model_state.gd")
const Recorder := preload("res://tests/helpers/signal_recorder.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")

const UID := "a0000002"

var _rules: RefCounted = null
var _history: CommandHistory = null


func before_test() -> void:
	_rules = Api.rules()
	_history = CommandHistory.new()


func _have() -> bool:
	var found: bool = Api.exists(Api.TRANSFORM) and Api.exists(Api.RULES)
	(
		assert_bool(found)
		. override_failure_message("transform_item_command.gd or placement_rules.gd is missing")
		. is_true()
	)
	return found


## Three items; the middle one has a colour and scale 1.5 so that unchanged fields are visible.
func _model() -> AquariumModel:
	var model: AquariumModel = AquariumModel.new("2026-11-01T12:00:00Z")
	model.apply_set_tank_id(&"tank_medium_1")
	model.apply_insert_item(
		Factory.item("a0000001", &"river_stone", Vector3(-0.1, 0, 0), 5.0, 1.0), 0
	)
	var middle: PlacedItem = Factory.coloured_item(UID, Color(0.2, 0.4, 0.6))
	middle.catalog_id = &"driftwood_branch"
	middle.position = Vector3(0.1, 0.0, 0.05)
	middle.rotation_y = 10.0
	middle.scale = 1.5
	model.apply_insert_item(middle, 1)
	model.apply_insert_item(
		Factory.item("a0000003", &"clay_amphora", Vector3(0, 0, 0.1), 0.0, 1.0), 2
	)
	return model


func _transform(model: AquariumModel, position: Vector3, rotation_y: float) -> bool:
	return _history.execute(Api.transform_command(model, UID, position, rotation_y, _rules))


func test_ac29_the_command_is_a_command_subclass_and_the_base_class_is_unchanged() -> void:
	if not _have():
		return
	var command: Command = Api.transform_command(_model(), UID, Vector3.ZERO, 0.0, _rules)
	assert_object(command).is_not_null()
	assert_bool(command is Command).is_true()
	var names: Array[String] = []
	for entry: Dictionary in (Command as Script).get_script_method_list():
		names.append(String(entry["name"]))
	names.sort()
	assert_array(names).is_equal(["_script_name", "do", "undo"])


func test_ac23_do_moves_and_turns_with_one_item_changed() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	var recorder: Recorder = Recorder.new()
	recorder.watch(model)
	assert_bool(_transform(model, Vector3(-0.2, 0.0, 0.12), 45.0)).is_true()
	var item: PlacedItem = model.get_item(UID)
	assert_vector(item.position).is_equal(Vector3(-0.2, 0.0, 0.12))
	assert_float(item.rotation_y).is_equal(45.0)
	assert_array(recorder.names()).is_equal(["item_changed"])
	assert_array(recorder.args_of(0)).is_equal([UID, 1])
	assert_int(_history.get_undo_count()).is_equal(1)


func test_ac23_uid_catalog_id_scale_colour_and_list_order_stay() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	assert_bool(_transform(model, Vector3(-0.2, 0.0, 0.12), 45.0)).is_true()
	var item: PlacedItem = model.get_item(UID)
	assert_that(item.catalog_id).is_equal(&"driftwood_branch")
	assert_float(item.scale).is_equal(1.5)
	assert_bool(item.has_colour).is_true()
	assert_bool(item.colour.is_equal_approx(Color(0.2, 0.4, 0.6))).is_true()
	assert_int(model.get_item_index(UID)).is_equal(1)
	assert_int(model.get_item_count()).is_equal(3)


func test_ac23_undo_restores_the_exact_start_and_redo_drops_again() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	var state_before: Dictionary = ModelState.snapshot(model)
	assert_bool(_transform(model, Vector3(-0.2, 0.0, 0.12), 45.0)).is_true()
	var state_after: Dictionary = ModelState.snapshot(model)
	var recorder: Recorder = Recorder.new()
	recorder.watch(model)
	assert_bool(_history.undo()).is_true()
	assert_dict(ModelState.snapshot(model)).is_equal(state_before)
	assert_array(recorder.names()).is_equal(["item_changed"])
	assert_bool(_history.redo()).is_true()
	assert_dict(ModelState.snapshot(model)).is_equal(state_after)
	assert_array(recorder.names()).is_equal(["item_changed", "item_changed"])


func test_ac27_a_rotation_only_command_keeps_the_position() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	assert_bool(_transform(model, Vector3(0.1, 0.0, 0.05), 25.0)).is_true()
	var item: PlacedItem = model.get_item(UID)
	assert_vector(item.position).is_equal(Vector3(0.1, 0.0, 0.05))
	assert_float(item.rotation_y).is_equal(25.0)
	assert_bool(_history.undo()).is_true()
	assert_float(model.get_item(UID).rotation_y).is_equal(10.0)


func test_ac27_an_item_outside_the_interior_can_still_be_turned() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	var old: PlacedItem = Factory.item("a0000009", &"river_stone", Vector3(0.5, 0, 0), 0.0, 1.0)
	model.apply_insert_item(old, 3)
	var command: Command = Api.transform_command(
		model, "a0000009", Vector3(0.5, 0, 0), 15.0, _rules
	)
	assert_bool(_history.execute(command)).is_true()
	assert_float(model.get_item("a0000009").rotation_y).is_equal(15.0)


func test_ac29_do_is_repeatable_after_undo_when_called_directly() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	var command: Command = Api.transform_command(model, UID, Vector3(0.0, 0.0, 0.0), 90.0, _rules)
	var state_before: Dictionary = ModelState.snapshot(model)
	assert_bool(command.do()).is_true()
	assert_bool(command.undo()).is_true()
	assert_dict(ModelState.snapshot(model)).is_equal(state_before)
	assert_bool(command.do()).is_true()
	assert_float(model.get_item(UID).rotation_y).is_equal(90.0)


func test_ac29_the_command_never_touches_created_or_modified() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	model.set_save_times("2026-01-01T00:00:00Z", "2026-02-02T00:00:00Z")
	assert_bool(_transform(model, Vector3(0.0, 0.0, 0.0), 90.0)).is_true()
	assert_bool(_history.undo()).is_true()
	assert_str(model.get_created()).is_equal("2026-01-01T00:00:00Z")
	assert_str(model.get_modified()).is_equal("2026-02-02T00:00:00Z")


func _rejected(uid: String, position: Vector3, rotation_y: float) -> void:
	var model: AquariumModel = _model()
	var state_before: Dictionary = ModelState.snapshot(model)
	var recorder: Recorder = Recorder.new()
	recorder.watch(model)
	var outcome: Array = []
	var command: Command = Api.transform_command(model, uid, position, rotation_y, _rules)
	await EngineOutput.capture(func() -> void: outcome.append(_history.execute(command)))
	assert_bool(outcome[0]).is_false()
	assert_dict(ModelState.snapshot(model)).is_equal(state_before)
	assert_int(recorder.count()).is_equal(0)
	assert_int(_history.get_undo_count()).is_equal(0)


func test_ac30_a_missing_uid_is_refused_without_a_change_or_a_signal() -> void:
	if not _have():
		return
	await _rejected("ffffffff", Vector3(0.0, 0.0, 0.0), 15.0)


func test_ac30_a_position_outside_the_interior_is_refused() -> void:
	if not _have():
		return
	await _rejected(UID, Vector3(0.5, 0.0, 0.0), 15.0)
	await _rejected(UID, Vector3(0.0, 0.0, -0.2), 15.0)


func test_ac30_non_finite_values_are_refused() -> void:
	if not _have():
		return
	await _rejected(UID, Vector3(NAN, 0.0, 0.0), 15.0)
	await _rejected(UID, Vector3(0.0, 0.0, INF), 15.0)
	await _rejected(UID, Vector3(0.1, 0.0, 0.05), NAN)
	await _rejected(UID, Vector3(0.1, 0.0, 0.05), -INF)
