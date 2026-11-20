extends GdUnitTestSuite
## #32 AC 1 (model part), 2 and 6 (owner: developer): DeleteItemCommand(model, uid). One
## item_removed per do, one item_added per undo, nothing else; undo puts the same item back at its
## old list index with every field, so the model equals its state before the delete except
## `modified`; redo deletes again; a uid that is not in the model makes do() return false with the
## model untouched, no signal and no history entry.
## Test decision: the engine output of a refused do() is not pinned (like TransformItemCommand).

const Api := preload("res://tests/helpers/edit_api.gd")
const Factory := preload("res://tests/helpers/factory.gd")
const ModelState := preload("res://tests/helpers/model_state.gd")
const Recorder := preload("res://tests/helpers/signal_recorder.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")

const A := "a0000001"
const B := "a0000002"
const C := "a0000003"

var _history: CommandHistory = null


func before_test() -> void:
	_history = CommandHistory.new()


func _have() -> bool:
	var found: bool = Api.exists(Api.DELETE)
	(
		assert_bool(found)
		. override_failure_message("game/model/delete_item_command.gd is missing")
		. is_true()
	)
	return found


## Three items; B is coloured and scaled so that every field can be seen coming back.
func _model() -> AquariumModel:
	var model: AquariumModel = AquariumModel.new("2026-11-01T12:00:00Z")
	model.apply_set_tank_id(&"tank_medium_1")
	model.apply_insert_item(Factory.item(A, &"river_stone", Vector3(-0.1, 0, 0), 5.0, 1.0), 0)
	var middle: PlacedItem = Factory.coloured_item(B, Color8(0x2A, 0x7F, 0x9E))
	middle.catalog_id = &"clay_amphora"
	middle.position = Vector3(0.1, 0.0, 0.05)
	middle.rotation_y = 37.5
	middle.scale = 1.5
	model.apply_insert_item(middle, 1)
	model.apply_insert_item(Factory.item(C, &"driftwood_branch", Vector3(0, 0, 0.1), 0.0, 1.0), 2)
	return model


func _delete(model: AquariumModel, uid: String) -> bool:
	return _history.execute(Api.delete_command(model, uid))


## A snapshot without `modified` (the one field a delete may change).
func _state(model: AquariumModel) -> Dictionary:
	var state: Dictionary = ModelState.snapshot(model)
	state.erase("modified")
	return state


func test_ac01_the_command_is_a_command_subclass() -> void:
	if not _have():
		return
	var command: Command = Api.delete_command(_model(), B)
	assert_object(command).is_not_null()
	assert_bool(command is Command).is_true()


func test_ac01_do_removes_the_item_with_one_item_removed_and_one_history_entry() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	var recorder: Recorder = Recorder.new()
	recorder.watch(model)
	assert_bool(_delete(model, B)).is_true()
	assert_array(recorder.names()).is_equal(["item_removed"])
	assert_array(recorder.args_of(0)).is_equal([B, 1])
	assert_bool(model.has_uid(B)).is_false()
	assert_int(model.get_item_count()).is_equal(2)
	assert_int(_history.get_undo_count()).is_equal(1)
	assert_int(_history.get_redo_count()).is_equal(0)


func test_ac01_no_other_item_is_touched_and_their_order_stays() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	var first: PlacedItem = model.get_item(A)
	var last: PlacedItem = model.get_item(C)
	var before_first: Dictionary = {"p": first.position, "r": first.rotation_y, "s": first.scale}
	assert_bool(_delete(model, B)).is_true()
	assert_object(model.get_item_at(0)).is_same(first)
	assert_object(model.get_item_at(1)).is_same(last)
	assert_vector(first.position).is_equal(before_first["p"])
	assert_float(first.rotation_y).is_equal(before_first["r"])
	assert_float(first.scale).is_equal(before_first["s"])


func test_ac02_undo_puts_the_item_back_at_its_old_index_for_every_position() -> void:
	if not _have():
		return
	for uid: String in [A, B, C]:
		var model: AquariumModel = _model()
		var index: int = model.get_item_index(uid)
		var state_before: Dictionary = _state(model)
		assert_bool(_delete(model, uid)).is_true()
		var recorder: Recorder = Recorder.new()
		recorder.watch(model)
		assert_bool(_history.undo()).is_true()
		assert_array(recorder.names()).override_failure_message(uid).is_equal(["item_added"])
		assert_array(recorder.args_of(0)).is_equal([uid, index])
		assert_int(model.get_item_index(uid)).override_failure_message(uid).is_equal(index)
		assert_dict(_state(model)).override_failure_message(uid).is_equal(state_before)
		_history.clear()


func test_ac02_every_field_of_the_item_comes_back_including_the_colour() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	assert_bool(_delete(model, B)).is_true()
	assert_bool(_history.undo()).is_true()
	var item: PlacedItem = model.get_item(B)
	assert_str(item.uid).is_equal(B)
	assert_that(item.catalog_id).is_equal(&"clay_amphora")
	assert_vector(item.position).is_equal(Vector3(0.1, 0.0, 0.05))
	assert_float(item.rotation_y).is_equal(37.5)
	assert_float(item.scale).is_equal(1.5)
	assert_bool(item.has_colour).is_true()
	assert_bool(item.colour.is_equal_approx(Color8(0x2A, 0x7F, 0x9E))).is_true()


func test_ac02_redo_deletes_again_with_one_item_removed() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	assert_bool(_delete(model, B)).is_true()
	var after_state: Dictionary = _state(model)
	assert_bool(_history.undo()).is_true()
	var recorder: Recorder = Recorder.new()
	recorder.watch(model)
	assert_bool(_history.redo()).is_true()
	assert_array(recorder.names()).is_equal(["item_removed"])
	assert_array(recorder.args_of(0)).is_equal([B, 1])
	assert_dict(_state(model)).is_equal(after_state)
	assert_bool(_history.undo()).is_true()
	assert_int(model.get_item_index(B)).is_equal(1)


func test_ac02_undo_and_redo_never_touch_created() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	model.set_save_times("2026-01-01T00:00:00Z", "2026-02-02T00:00:00Z")
	assert_bool(_delete(model, B)).is_true()
	assert_bool(_history.undo()).is_true()
	assert_bool(_history.redo()).is_true()
	assert_str(model.get_created()).is_equal("2026-01-01T00:00:00Z")


func test_ac02_do_is_repeatable_after_undo_when_called_directly() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	var command: Command = Api.delete_command(model, B)
	var before_state: Dictionary = _state(model)
	assert_bool(command.do()).is_true()
	assert_bool(command.undo()).is_true()
	assert_dict(_state(model)).is_equal(before_state)
	assert_bool(command.do()).is_true()
	assert_bool(model.has_uid(B)).is_false()


func test_ac02_deleting_the_only_item_and_undoing_works() -> void:
	if not _have():
		return
	var model: AquariumModel = AquariumModel.new("2026-11-01T12:00:00Z")
	model.apply_insert_item(Factory.item(A), 0)
	assert_bool(_delete(model, A)).is_true()
	assert_int(model.get_item_count()).is_equal(0)
	assert_bool(_history.undo()).is_true()
	assert_int(model.get_item_index(A)).is_equal(0)


func test_ac06_a_uid_that_is_not_in_the_model_is_refused_without_a_change_or_a_signal() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	var before_state: Dictionary = ModelState.snapshot(model)
	var recorder: Recorder = Recorder.new()
	recorder.watch(model)
	var outcome: Array = []
	var command: Command = Api.delete_command(model, "ffffffff")
	await EngineOutput.capture(func() -> void: outcome.append(_history.execute(command)))
	assert_bool(outcome[0]).is_false()
	assert_dict(ModelState.snapshot(model)).is_equal(before_state)
	assert_int(recorder.count()).is_equal(0)
	assert_int(_history.get_undo_count()).is_equal(0)


func test_ac06_a_uid_deleted_meanwhile_is_refused_on_do() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	var command: Command = Api.delete_command(model, B)
	model.apply_remove_item(B)
	var before_state: Dictionary = ModelState.snapshot(model)
	var recorder: Recorder = Recorder.new()
	recorder.watch(model)
	var outcome: Array = []
	await EngineOutput.capture(func() -> void: outcome.append(command.do()))
	assert_bool(outcome[0]).is_false()
	assert_dict(ModelState.snapshot(model)).is_equal(before_state)
	assert_int(recorder.count()).is_equal(0)
