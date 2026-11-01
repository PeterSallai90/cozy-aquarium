extends GdUnitTestSuite

const Factory := preload("res://tests/helpers/factory.gd")
const ModelState := preload("res://tests/helpers/model_state.gd")
const SignalRecorder := preload("res://tests/helpers/signal_recorder.gd")
const ErrorContains := preload("res://tests/helpers/error_contains.gd")
const EventBusScript := preload("res://systems/event_bus.gd")
const AddItemCommand := preload("res://tests/helpers/commands/add_item_command.gd")
const AddFishCommand := preload("res://tests/helpers/commands/add_fish_command.gd")
const RemoveItemCommand := preload("res://tests/helpers/commands/remove_item_command.gd")
const RemoveFishCommand := preload("res://tests/helpers/commands/remove_fish_command.gd")
const ChangeItemCommand := preload("res://tests/helpers/commands/change_item_command.gd")
const ChangeFishCommand := preload("res://tests/helpers/commands/change_fish_command.gd")
const SetTankCommand := preload("res://tests/helpers/commands/set_tank_command.gd")
const MultiChangeCommand := preload("res://tests/helpers/commands/multi_change_command.gd")
const FailingCommand := preload("res://tests/helpers/commands/failing_command.gd")
const BrokenUndoCommand := preload("res://tests/helpers/commands/broken_undo_command.gd")
const BrokenRedoCommand := preload("res://tests/helpers/commands/broken_redo_command.gd")

const FIXED_CLOCK := "2026-10-27T18:00:00Z"

var _model: AquariumModel
var _history: CommandHistory


func before_test() -> void:
	_model = AquariumModel.new(FIXED_CLOCK)
	_history = CommandHistory.new()
	_model.apply_set_name("Start")
	_model.apply_set_tank_id(&"tank_a")
	for uid: String in ["a0000001", "a0000002", "a0000003"]:
		_model.apply_insert_item(Factory.item(uid), _model.get_item_count())
	for uid: String in ["f0000001", "f0000002", "f0000003"]:
		_model.apply_insert_fish(
			Factory.fish(uid, &"guppy", 1, "Fish " + uid), _model.get_fish_count()
		)


## Builds the command named by kind against the current model.
func _make(kind: String) -> Command:
	var result: Command = null
	match kind:
		"set_tank":
			result = SetTankCommand.new(_model, &"tank_b")
		"add_item":
			result = AddItemCommand.new(_model, Factory.item("a0000009"))
		"remove_item":
			result = RemoveItemCommand.new(_model, "a0000002")
		"change_item":
			var changed: PlacedItem = _model.get_item("a0000002").copy()
			changed.position = Vector3(0.3, 0.0, 0.2)
			changed.has_colour = true
			changed.colour = Color(0.2, 0.4, 0.6)
			result = ChangeItemCommand.new(_model, changed)
		"add_fish":
			result = AddFishCommand.new(_model, Factory.fish("f0000009", &"betta", 2, "Neo"))
		"remove_fish":
			result = RemoveFishCommand.new(_model, "f0000002")
		"change_fish":
			var renamed: FishInstance = _model.get_fish("f0000002").copy()
			renamed.nickname = "熱帯魚"
			renamed.variant = 4
			result = ChangeFishCommand.new(_model, renamed)
		"multi_change":
			result = MultiChangeCommand.new(_model, "Renamed", &"tank_c", Factory.item("a0000008"))
	return result


func _kinds() -> Array[String]:
	return [
		"set_tank",
		"add_item",
		"remove_item",
		"change_item",
		"add_fish",
		"remove_fish",
		"change_fish",
		"multi_change",
	]


func _snap() -> Dictionary:
	return ModelState.snapshot(_model)


func _item_uids() -> Array[String]:
	var uids: Array[String] = []
	for item: PlacedItem in _model.get_items():
		uids.append(item.uid)
	return uids


func test_execute_runs_do_once_and_pushes() -> void:
	var command: SetTankCommand = SetTankCommand.new(_model, &"tank_b")
	var ok: bool = _history.execute(command)
	assert_bool(ok).is_true()
	assert_int(command.do_count).is_equal(1)
	assert_that(_model.get_tank_id()).is_equal(&"tank_b")
	assert_int(_history.get_undo_count()).is_equal(1)
	assert_bool(_history.can_undo()).is_true()
	assert_bool(_history.can_redo()).is_false()


func test_undo_restores_exact_state() -> void:
	for kind: String in _kinds():
		before_test()
		var before: Dictionary = _snap()
		var command: Command = _make(kind)
		assert_bool(_history.execute(command)).override_failure_message(kind).is_true()
		assert_dict(_snap()).override_failure_message(kind).is_not_equal(before)
		assert_bool(_history.undo()).override_failure_message(kind).is_true()
		assert_dict(_snap()).override_failure_message(kind).is_equal(before)
		assert_bool(_history.can_undo()).is_false()
		assert_bool(_history.can_redo()).is_true()


func test_redo_restores_exact_after_state() -> void:
	for kind: String in _kinds():
		before_test()
		var command: Command = _make(kind)
		assert_bool(_history.execute(command)).is_true()
		var after: Dictionary = _snap()
		assert_bool(_history.undo()).is_true()
		assert_bool(_history.redo()).override_failure_message(kind).is_true()
		assert_dict(_snap()).override_failure_message(kind).is_equal(after)
		assert_bool(_history.can_undo()).is_true()
		assert_bool(_history.can_redo()).is_false()


func test_remove_middle_item_undo_restores_index() -> void:
	var before: Dictionary = _snap()
	var middle: PlacedItem = _model.get_item("a0000002")
	assert_bool(_history.execute(RemoveItemCommand.new(_model, "a0000002"))).is_true()
	assert_array(_item_uids()).is_equal(["a0000001", "a0000003"])
	var after_remove: Dictionary = _snap()
	assert_bool(_history.undo()).is_true()
	assert_array(_item_uids()).is_equal(["a0000001", "a0000002", "a0000003"])
	assert_int(_model.get_item_index("a0000002")).is_equal(1)
	assert_bool(is_same(_model.get_item("a0000002"), middle)).is_true()
	assert_dict(_snap()).is_equal(before)
	assert_bool(_history.redo()).is_true()
	assert_dict(_snap()).is_equal(after_remove)
	assert_array(_item_uids()).is_equal(["a0000001", "a0000003"])


func test_remove_middle_fish_undo_restores_index() -> void:
	var before: Dictionary = _snap()
	var middle: FishInstance = _model.get_fish("f0000002")
	assert_bool(_history.execute(RemoveFishCommand.new(_model, "f0000002"))).is_true()
	assert_int(_model.get_fish_count()).is_equal(2)
	assert_bool(_history.undo()).is_true()
	assert_int(_model.get_fish_index("f0000002")).is_equal(1)
	assert_bool(is_same(_model.get_fish("f0000002"), middle)).is_true()
	assert_str(_model.get_fish("f0000002").nickname).is_equal("Fish f0000002")
	assert_dict(_snap()).is_equal(before)
	assert_bool(_history.redo()).is_true()
	assert_str(_model.get_fish_at(0).uid).is_equal("f0000001")
	assert_str(_model.get_fish_at(1).uid).is_equal("f0000003")


func test_add_undo_redo_keeps_same_instance_and_uid() -> void:
	var item: PlacedItem = Factory.item("a0000009")
	assert_bool(_history.execute(AddItemCommand.new(_model, item))).is_true()
	assert_bool(_history.undo()).is_true()
	assert_object(_model.get_item("a0000009")).is_null()
	assert_bool(_history.redo()).is_true()
	assert_bool(is_same(_model.get_item("a0000009"), item)).is_true()
	assert_str(item.uid).is_equal("a0000009")
	var fish: FishInstance = Factory.fish("f0000009", &"betta", 2, "Neo")
	assert_bool(_history.execute(AddFishCommand.new(_model, fish))).is_true()
	assert_bool(_history.undo()).is_true()
	assert_bool(_history.redo()).is_true()
	assert_bool(is_same(_model.get_fish("f0000009"), fish)).is_true()
	assert_str(fish.uid).is_equal("f0000009")


func test_add_with_existing_uid_fails() -> void:
	var before: Dictionary = _snap()
	var recorder: SignalRecorder = SignalRecorder.new()
	recorder.watch(_model)
	recorder.watch(_history)
	var clash_with_fish: PlacedItem = Factory.item("f0000001")
	assert_bool(_history.execute(AddItemCommand.new(_model, clash_with_fish))).is_false()
	var clash_with_item: FishInstance = Factory.fish("a0000001")
	assert_bool(_history.execute(AddFishCommand.new(_model, clash_with_item))).is_false()
	assert_dict(_snap()).is_equal(before)
	assert_array(recorder.events).is_empty()
	assert_int(_history.get_undo_count()).is_equal(0)


func test_timestamps_unchanged_by_execute_undo_redo() -> void:
	for kind: String in _kinds():
		before_test()
		assert_bool(_history.execute(_make(kind))).is_true()
		assert_str(_model.get_created()).is_equal(FIXED_CLOCK)
		assert_str(_model.get_modified()).is_equal(FIXED_CLOCK)
		assert_bool(_history.undo()).is_true()
		assert_str(_model.get_created()).is_equal(FIXED_CLOCK)
		assert_str(_model.get_modified()).is_equal(FIXED_CLOCK)
		assert_bool(_history.redo()).is_true()
		assert_str(_model.get_created()).is_equal(FIXED_CLOCK)
		assert_str(_model.get_modified()).is_equal(FIXED_CLOCK)


func test_hundred_commands_undo_all_redo_all() -> void:
	var initial: Dictionary = _snap()
	var count: int = 150
	var added_items: Array[String] = []
	for i: int in range(count):
		var command: Command = null
		var uid: String = "%08x" % (0x1000 + i)
		match i % 5:
			0:
				command = AddItemCommand.new(_model, Factory.item(uid))
				added_items.append(uid)
			1:
				command = AddFishCommand.new(_model, Factory.fish(uid, &"guppy", i, "n%d" % i))
			2:
				command = SetTankCommand.new(_model, StringName("tank_%d" % i))
			3:
				var changed: PlacedItem = _model.get_item("a0000001").copy()
				changed.rotation_y = float(i)
				command = ChangeItemCommand.new(_model, changed)
			4:
				command = RemoveItemCommand.new(_model, added_items.pop_back())
		assert_bool(_history.execute(command)).override_failure_message("step %d" % i).is_true()
	var final_state: Dictionary = _snap()
	assert_int(_history.get_undo_count()).is_equal(count)
	for i: int in range(count):
		assert_bool(_history.undo()).override_failure_message("undo %d" % i).is_true()
	assert_dict(_snap()).is_equal(initial)
	assert_bool(_history.can_undo()).is_false()
	for i: int in range(count):
		assert_bool(_history.redo()).override_failure_message("redo %d" % i).is_true()
	assert_dict(_snap()).is_equal(final_state)
	assert_int(_history.get_undo_count()).is_equal(count)
	assert_bool(_history.can_redo()).is_false()


func test_undo_on_empty_returns_false_silently() -> void:
	var before: Dictionary = _snap()
	var recorder: SignalRecorder = SignalRecorder.new()
	recorder.watch(_model)
	recorder.watch(_history)
	var result: Array[bool] = []
	await assert_error(func() -> void: result.append(_history.undo())).is_success()
	assert_array(result).is_equal([false])
	assert_dict(_snap()).is_equal(before)
	assert_array(recorder.events).is_empty()


func test_redo_on_empty_returns_false_silently() -> void:
	var before: Dictionary = _snap()
	var recorder: SignalRecorder = SignalRecorder.new()
	recorder.watch(_model)
	recorder.watch(_history)
	var result: Array[bool] = []
	await assert_error(func() -> void: result.append(_history.redo())).is_success()
	assert_array(result).is_equal([false])
	assert_dict(_snap()).is_equal(before)
	assert_array(recorder.events).is_empty()


func test_execute_after_undo_clears_redo() -> void:
	assert_bool(_history.execute(SetTankCommand.new(_model, &"tank_b"))).is_true()
	assert_bool(_history.execute(SetTankCommand.new(_model, &"tank_c"))).is_true()
	assert_bool(_history.undo()).is_true()
	assert_bool(_history.can_redo()).is_true()
	assert_bool(_history.execute(SetTankCommand.new(_model, &"tank_d"))).is_true()
	assert_bool(_history.can_redo()).is_false()
	assert_int(_history.get_redo_count()).is_equal(0)
	assert_int(_history.get_undo_count()).is_equal(2)
	assert_bool(_history.redo()).is_false()


func test_failing_do_changes_nothing() -> void:
	# One undone command first, so the redo stack has content that must survive.
	assert_bool(_history.execute(SetTankCommand.new(_model, &"tank_b"))).is_true()
	assert_bool(_history.execute(SetTankCommand.new(_model, &"tank_c"))).is_true()
	assert_bool(_history.undo()).is_true()
	var bus: Node = auto_free(EventBusScript.new())
	bus.bind_history(_history)
	var before: Dictionary = _snap()
	var undo_count: int = _history.get_undo_count()
	var recorder: SignalRecorder = SignalRecorder.new()
	recorder.watch(_model)
	recorder.watch(_history)
	recorder.watch(bus)
	var command: FailingCommand = FailingCommand.new(_model)
	var result: Array[bool] = []
	await assert_error(func() -> void: result.append(_history.execute(command))).is_success()
	assert_array(result).is_equal([false])
	assert_int(command.do_count).is_equal(1)
	assert_dict(_snap()).is_equal(before)
	assert_int(_history.get_undo_count()).is_equal(undo_count)
	assert_bool(_history.can_redo()).is_true()
	assert_int(_history.get_redo_count()).is_equal(1)
	assert_array(recorder.events).is_empty()


func test_clear_empties_both_stacks() -> void:
	assert_bool(_history.execute(SetTankCommand.new(_model, &"tank_b"))).is_true()
	assert_bool(_history.execute(SetTankCommand.new(_model, &"tank_c"))).is_true()
	assert_bool(_history.undo()).is_true()
	var recorder: SignalRecorder = SignalRecorder.new()
	recorder.watch(_history)
	assert_bool(_history.clear()).is_true()
	assert_bool(_history.can_undo()).is_false()
	assert_bool(_history.can_redo()).is_false()
	assert_int(_history.get_undo_count()).is_equal(0)
	assert_int(_history.get_redo_count()).is_equal(0)
	assert_array(recorder.events).is_equal([["history_changed", [false, false]]])


func test_clear_on_empty_still_emits() -> void:
	var recorder: SignalRecorder = SignalRecorder.new()
	recorder.watch(_history)
	assert_bool(_history.clear()).is_true()
	assert_array(recorder.events).is_equal([["history_changed", [false, false]]])


func test_clear_does_not_change_the_model() -> void:
	assert_bool(_history.execute(SetTankCommand.new(_model, &"tank_b"))).is_true()
	var before: Dictionary = _snap()
	assert_bool(_history.clear()).is_true()
	assert_dict(_snap()).is_equal(before)


func test_failing_undo_clears_history() -> void:
	assert_bool(_history.execute(SetTankCommand.new(_model, &"tank_x"))).is_true()
	assert_bool(_history.execute(BrokenUndoCommand.new(_model, &"tank_b"))).is_true()
	var before: Dictionary = _snap()
	var recorder: SignalRecorder = SignalRecorder.new()
	recorder.watch(_history)
	var result: Array[bool] = []
	await (
		assert_error(func() -> void: result.append(_history.undo()))
		. is_push_error(ErrorContains.new("failed; history cleared"))
	)
	assert_array(result).is_equal([false])
	assert_bool(_history.can_undo()).is_false()
	assert_bool(_history.can_redo()).is_false()
	assert_int(_history.get_undo_count()).is_equal(0)
	assert_int(_history.get_redo_count()).is_equal(0)
	assert_array(recorder.events).is_equal([["history_changed", [false, false]]])
	assert_dict(_snap()).is_equal(before)


func test_failing_redo_clears_history() -> void:
	assert_bool(_history.execute(SetTankCommand.new(_model, &"tank_x"))).is_true()
	assert_bool(_history.execute(BrokenRedoCommand.new(_model, &"tank_b"))).is_true()
	assert_bool(_history.undo()).is_true()
	assert_bool(_history.undo()).is_true()
	assert_bool(_history.redo()).is_true()
	var before_redo: Dictionary = _snap()
	var recorder: SignalRecorder = SignalRecorder.new()
	recorder.watch(_history)
	var result: Array[bool] = []
	await (
		assert_error(func() -> void: result.append(_history.redo()))
		. is_push_error(ErrorContains.new("failed; history cleared"))
	)
	assert_array(result).is_equal([false])
	assert_bool(_history.can_undo()).is_false()
	assert_bool(_history.can_redo()).is_false()
	assert_array(recorder.events).is_equal([["history_changed", [false, false]]])
	assert_dict(_snap()).is_equal(before_redo)
