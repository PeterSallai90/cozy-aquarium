extends GdUnitTestSuite

const Factory := preload("res://tests/helpers/factory.gd")
const ModelState := preload("res://tests/helpers/model_state.gd")
const SignalRecorder := preload("res://tests/helpers/signal_recorder.gd")
const ErrorContains := preload("res://tests/helpers/error_contains.gd")
const AddItemCommand := preload("res://tests/helpers/commands/add_item_command.gd")
const SetTankCommand := preload("res://tests/helpers/commands/set_tank_command.gd")
const MultiChangeCommand := preload("res://tests/helpers/commands/multi_change_command.gd")

const FIXED_CLOCK := "2026-10-27T18:00:00Z"

var _model: AquariumModel
var _history: CommandHistory
var _recorder: SignalRecorder
var _inner_results: Array[bool] = []
var _seen_undo_counts: Array[int] = []
var _seen_item_counts: Array[int] = []
var _inner_runs: int = 0


func before_test() -> void:
	_model = AquariumModel.new(FIXED_CLOCK)
	_history = CommandHistory.new()
	_recorder = SignalRecorder.new()
	_recorder.watch(_model)
	_recorder.watch(_history)
	_inner_results.clear()
	_seen_undo_counts.clear()
	_seen_item_counts.clear()
	_inner_runs = 0


func _multi() -> MultiChangeCommand:
	return MultiChangeCommand.new(_model, "Renamed", &"tank_c", Factory.item("a0000008"))


# --- signal order ----------------------------------------------------------------------------


func test_execute_signal_order() -> void:
	assert_bool(_history.execute(_multi())).is_true()
	assert_array(_recorder.names()).is_equal(
		["name_changed", "tank_changed", "item_added", "executed", "history_changed"]
	)
	assert_array(_recorder.args_of(4)).is_equal([true, false])


func test_undo_signal_order() -> void:
	assert_bool(_history.execute(_multi())).is_true()
	_recorder.clear()
	assert_bool(_history.undo()).is_true()
	assert_array(_recorder.names()).is_equal(
		["item_removed", "tank_changed", "name_changed", "undone", "history_changed"]
	)
	assert_array(_recorder.args_of(4)).is_equal([false, true])


func test_redo_signal_order() -> void:
	assert_bool(_history.execute(_multi())).is_true()
	assert_bool(_history.undo()).is_true()
	_recorder.clear()
	assert_bool(_history.redo()).is_true()
	assert_array(_recorder.names()).is_equal(
		["name_changed", "tank_changed", "item_added", "redone", "history_changed"]
	)
	assert_array(_recorder.args_of(4)).is_equal([true, false])


func test_undo_emits_model_signals_in_reverse_order() -> void:
	assert_bool(_history.execute(_multi())).is_true()
	var do_names: PackedStringArray = _recorder.names().slice(0, 3)
	assert_array(do_names).is_equal(["name_changed", "tank_changed", "item_added"])
	_recorder.clear()
	assert_bool(_history.undo()).is_true()
	var undo_names: PackedStringArray = _recorder.names().slice(0, 3)
	assert_array(undo_names).is_equal(["item_removed", "tank_changed", "name_changed"])


func test_executed_carries_the_command() -> void:
	var command: MultiChangeCommand = _multi()
	assert_bool(_history.execute(command)).is_true()
	assert_bool(is_same(_recorder.args_of(3)[0], command)).is_true()
	assert_bool(_history.undo()).is_true()
	assert_bool(is_same(_recorder.args_of(_recorder.count() - 2)[0], command)).is_true()


func test_model_listener_sees_old_stack() -> void:
	_model.item_added.connect(_on_item_added_record_stack)
	assert_bool(_history.execute(_multi())).is_true()
	assert_array(_seen_undo_counts).is_equal([0])
	assert_int(_history.get_undo_count()).is_equal(1)


func test_history_listener_sees_new_model() -> void:
	_history.executed.connect(_on_history_record_items)
	_history.undone.connect(_on_history_record_items)
	_history.redone.connect(_on_history_record_items)
	_history.history_changed.connect(_on_history_changed_record_items)
	assert_bool(_history.execute(_multi())).is_true()
	assert_bool(_history.undo()).is_true()
	assert_bool(_history.redo()).is_true()
	# executed, history_changed, undone, history_changed, redone, history_changed
	assert_array(_seen_item_counts).is_equal([1, 1, 0, 0, 1, 1])


func test_clear_emits_only_history_changed_false_false() -> void:
	assert_bool(_history.execute(_multi())).is_true()
	_recorder.clear()
	assert_bool(_history.clear()).is_true()
	assert_array(_recorder.events).is_equal([["history_changed", [false, false]]])


# --- re-entrancy -----------------------------------------------------------------------------


func test_reentrant_execute_from_executed_handler_rejected() -> void:
	_history.executed.connect(_on_try_execute)
	var outer: Array[bool] = []
	await (
		assert_error(
			func() -> void: outer.append(_history.execute(SetTankCommand.new(_model, &"tank_b")))
		)
		. is_push_error(ErrorContains.new("re-entrant"))
	)
	assert_array(outer).is_equal([true])
	assert_array(_inner_results).is_equal([false])
	assert_int(_history.get_undo_count()).is_equal(1)
	assert_that(_model.get_tank_id()).is_equal(&"tank_b")


func test_reentrant_execute_from_history_changed_handler_rejected() -> void:
	_history.history_changed.connect(_on_try_execute_from_history_changed)
	var outer: Array[bool] = []
	await (
		assert_error(
			func() -> void: outer.append(_history.execute(SetTankCommand.new(_model, &"tank_b")))
		)
		. is_push_error(ErrorContains.new("re-entrant"))
	)
	assert_array(outer).is_equal([true])
	assert_array(_inner_results).is_equal([false])
	assert_int(_history.get_undo_count()).is_equal(1)
	assert_that(_model.get_tank_id()).is_equal(&"tank_b")


func test_reentrant_execute_from_model_signal_handler_during_do_rejected() -> void:
	_model.tank_changed.connect(_on_try_execute_from_model_signal)
	var outer: Array[bool] = []
	await (
		assert_error(
			func() -> void: outer.append(_history.execute(SetTankCommand.new(_model, &"tank_b")))
		)
		. is_push_error(ErrorContains.new("re-entrant"))
	)
	assert_array(outer).is_equal([true])
	assert_array(_inner_results).is_equal([false])
	assert_int(_history.get_undo_count()).is_equal(1)
	assert_that(_model.get_tank_id()).is_equal(&"tank_b")


func test_reentrant_execute_from_model_signal_handler_during_undo_rejected() -> void:
	assert_bool(_history.execute(SetTankCommand.new(_model, &"tank_b"))).is_true()
	_model.tank_changed.connect(_on_try_execute_from_model_signal)
	var outer: Array[bool] = []
	await (
		assert_error(func() -> void: outer.append(_history.undo()))
		. is_push_error(ErrorContains.new("re-entrant"))
	)
	assert_array(outer).is_equal([true])
	assert_array(_inner_results).is_equal([false])
	assert_int(_history.get_undo_count()).is_equal(0)
	assert_int(_history.get_redo_count()).is_equal(1)
	assert_that(_model.get_tank_id()).is_equal(&"")


func test_reentrant_undo_during_undo_rejected() -> void:
	assert_bool(_history.execute(SetTankCommand.new(_model, &"tank_b"))).is_true()
	assert_bool(_history.execute(SetTankCommand.new(_model, &"tank_c"))).is_true()
	_history.undone.connect(_on_try_undo)
	var outer: Array[bool] = []
	await (
		assert_error(func() -> void: outer.append(_history.undo()))
		. is_push_error(ErrorContains.new("re-entrant"))
	)
	assert_array(outer).is_equal([true])
	assert_array(_inner_results).is_equal([false])
	assert_int(_history.get_undo_count()).is_equal(1)
	assert_int(_history.get_redo_count()).is_equal(1)
	assert_that(_model.get_tank_id()).is_equal(&"tank_b")


func test_reentrant_redo_rejected() -> void:
	assert_bool(_history.execute(SetTankCommand.new(_model, &"tank_b"))).is_true()
	assert_bool(_history.execute(SetTankCommand.new(_model, &"tank_c"))).is_true()
	assert_bool(_history.undo()).is_true()
	assert_bool(_history.undo()).is_true()
	_history.redone.connect(_on_try_redo)
	var outer: Array[bool] = []
	await (
		assert_error(func() -> void: outer.append(_history.redo()))
		. is_push_error(ErrorContains.new("re-entrant"))
	)
	assert_array(outer).is_equal([true])
	assert_array(_inner_results).is_equal([false])
	assert_int(_history.get_undo_count()).is_equal(1)
	assert_int(_history.get_redo_count()).is_equal(1)
	assert_that(_model.get_tank_id()).is_equal(&"tank_b")


func test_reentrant_clear_rejected() -> void:
	_history.executed.connect(_on_try_clear)
	var outer: Array[bool] = []
	await (
		assert_error(
			func() -> void: outer.append(_history.execute(SetTankCommand.new(_model, &"tank_b")))
		)
		. is_push_error(ErrorContains.new("re-entrant"))
	)
	assert_array(outer).is_equal([true])
	assert_array(_inner_results).is_equal([false])
	assert_int(_history.get_undo_count()).is_equal(1)


func test_history_usable_after_a_rejected_reentrant_call() -> void:
	_history.executed.connect(_on_try_execute)
	await (
		assert_error(func() -> void: _history.execute(SetTankCommand.new(_model, &"tank_b")))
		. is_push_error(ErrorContains.new("re-entrant"))
	)
	_history.executed.disconnect(_on_try_execute)
	assert_bool(_history.execute(SetTankCommand.new(_model, &"tank_c"))).is_true()
	assert_bool(_history.undo()).is_true()
	assert_that(_model.get_tank_id()).is_equal(&"tank_b")


# --- listeners -------------------------------------------------------------------------------


func _on_item_added_record_stack(_uid: String, _index: int) -> void:
	_seen_undo_counts.append(_history.get_undo_count())


func _on_history_record_items(_command: Command) -> void:
	_seen_item_counts.append(_model.get_item_count())


func _on_history_changed_record_items(_can_undo: bool, _can_redo: bool) -> void:
	_seen_item_counts.append(_model.get_item_count())


func _on_try_execute(_command: Command) -> void:
	_inner_runs += 1
	if _inner_runs > 1:
		return
	_inner_results.append(_history.execute(SetTankCommand.new(_model, &"tank_inner")))


func _on_try_execute_from_history_changed(_can_undo: bool, _can_redo: bool) -> void:
	_inner_runs += 1
	if _inner_runs > 1:
		return
	_inner_results.append(_history.execute(SetTankCommand.new(_model, &"tank_inner")))


func _on_try_execute_from_model_signal(_tank_id: StringName) -> void:
	_inner_runs += 1
	if _inner_runs == 1:
		_inner_results.append(_history.execute(SetTankCommand.new(_model, &"tank_inner")))


func _on_try_undo(_command: Command) -> void:
	_inner_results.append(_history.undo())


func _on_try_redo(_command: Command) -> void:
	_inner_results.append(_history.redo())


func _on_try_clear(_command: Command) -> void:
	_inner_results.append(_history.clear())
