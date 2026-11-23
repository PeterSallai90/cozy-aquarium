extends GdUnitTestSuite
## #36 Remove command (owner: developer): RemoveFishCommand(model, uid). do() removes the fish with
## one fish_removed; undo() puts the same instance back at its old index with every field (the
## nickname is any Unicode, stored unchanged); redo removes again. An unknown uid makes do() return
## false with the model untouched, no signal and no history entry. A uid that belongs to an item is
## not a fish and is refused too.

const Edit := preload("res://tests/helpers/fish_edit_api.gd")
const Factory := preload("res://tests/helpers/factory.gd")
const ModelState := preload("res://tests/helpers/model_state.gd")
const Recorder := preload("res://tests/helpers/signal_recorder.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")

const A := "f0000001"
const B := "f0000002"
const C := "f0000003"
const NICK := "Hal Árpád 魚 \U0001F41F\n tail"

var _history: CommandHistory = null


func before_test() -> void:
	_history = CommandHistory.new()


func _have() -> bool:
	var found: bool = Edit.exists(Edit.REMOVE)
	(
		assert_bool(found)
		. override_failure_message("game/model/remove_fish_command.gd is missing")
		. is_true()
	)
	return found


func _model() -> AquariumModel:
	var model: AquariumModel = AquariumModel.new("2026-11-01T12:00:00Z")
	model.apply_set_tank_id(&"tank_medium_1")
	model.apply_insert_fish(Factory.fish(A, &"neon_tetra", 1, ""), 0)
	model.apply_insert_fish(Factory.fish(B, &"angelfish", 2, NICK), 1)
	model.apply_insert_fish(Factory.fish(C, &"bronze_corydoras", 0, "Cory"), 2)
	return model


func _remove(model: AquariumModel, uid: String) -> bool:
	return _history.execute(Edit.remove_command(model, uid))


func _state(model: AquariumModel) -> Dictionary:
	var state: Dictionary = ModelState.snapshot(model)
	state.erase("modified")
	return state


func test_36_the_command_is_a_command_subclass() -> void:
	if not _have():
		return
	var command: Command = Edit.remove_command(_model(), B)
	assert_object(command).is_not_null()
	assert_bool(command is Command).is_true()


func test_36_do_removes_the_fish_with_one_fish_removed_and_one_history_entry() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	var recorder: Recorder = Recorder.new()
	recorder.watch(model)
	assert_bool(_remove(model, B)).is_true()
	assert_array(recorder.names()).is_equal(["fish_removed"])
	assert_array(recorder.args_of(0)).is_equal([B, 1])
	assert_bool(model.has_uid(B)).is_false()
	assert_int(model.get_fish_count()).is_equal(2)
	assert_int(_history.get_undo_count()).is_equal(1)


func test_36_undo_puts_the_same_fish_back_at_the_old_index() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	var state_before: Dictionary = _state(model)
	assert_bool(_remove(model, B)).is_true()
	var recorder: Recorder = Recorder.new()
	recorder.watch(model)
	assert_bool(_history.undo()).is_true()
	assert_array(recorder.names()).is_equal(["fish_added"])
	assert_array(recorder.args_of(0)).is_equal([B, 1])
	assert_dict(_state(model)).is_equal(state_before)
	var fish: FishInstance = model.get_fish_at(1)
	assert_str(fish.uid).is_equal(B)
	assert_str(String(fish.species_id)).is_equal("angelfish")
	assert_int(fish.variant).is_equal(2)
	assert_str(fish.nickname).is_equal(NICK)


func test_36_undo_of_the_first_and_the_last_fish_keeps_the_order() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	assert_bool(_remove(model, A)).is_true()
	assert_bool(_remove(model, C)).is_true()
	assert_bool(_history.undo()).is_true()
	assert_bool(_history.undo()).is_true()
	(
		assert_array(model.get_fish_list().map(func(f: FishInstance) -> String: return f.uid))
		. is_equal([A, B, C])
	)


func test_36_redo_removes_again() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	assert_bool(_remove(model, B)).is_true()
	assert_bool(_history.undo()).is_true()
	assert_bool(_history.redo()).is_true()
	assert_bool(model.has_uid(B)).is_false()
	assert_int(model.get_fish_count()).is_equal(2)


func test_36_an_unknown_uid_makes_do_fail_without_a_trace() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	var state_before: Dictionary = _state(model)
	var recorder: Recorder = Recorder.new()
	recorder.watch(model)
	var result: Array = [true]
	await EngineOutput.capture(func() -> void: result[0] = _remove(model, "f00000ff"))
	assert_bool(result[0]).is_false()
	assert_int(recorder.count()).is_equal(0)
	assert_dict(_state(model)).is_equal(state_before)
	assert_bool(_history.can_undo()).is_false()


func test_36_an_item_uid_is_not_a_fish_and_is_refused() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	model.apply_insert_item(Factory.item("a0000001"), 0)
	var state_before: Dictionary = _state(model)
	var result: Array = [true]
	await EngineOutput.capture(func() -> void: result[0] = _remove(model, "a0000001"))
	assert_bool(result[0]).is_false()
	assert_dict(_state(model)).is_equal(state_before)
	assert_bool(model.has_uid("a0000001")).is_true()


func test_36_an_empty_uid_is_refused() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	var state_before: Dictionary = _state(model)
	var result: Array = [true]
	await EngineOutput.capture(func() -> void: result[0] = _remove(model, ""))
	assert_bool(result[0]).is_false()
	assert_dict(_state(model)).is_equal(state_before)
