# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #32 AC 15, 16, 17 (button part) and 23 (owner: developer): the Undo and Redo text buttons of
## HistoryControls (game/ui/history/history_controls.tscn; children UndoButton and RedoButton).
## Both are disabled at the start and after a clear (a load, a reset). Their enabled state is the
## last EventBus.history_changed(can_undo, can_redo) and nothing else: direct emits drive them even
## when the real history says otherwise, so the buttons never query the history. A new command
## after an undo disables Redo. A click on an enabled button calls CommandHistory.undo() or redo()
## exactly once; a disabled button does nothing; a blocker (dialog, photo mode), a running gesture
## and a busy history stop a click too. A failed undo or redo (a fake failing command, the engine
## error declared) clears the history, both buttons disable through the signal, and no dialog opens.
## Test decisions: the node lives in its own SubViewport with the EventBus bound to the history
## (as main.gd does); clicks are real mouse events at the centre of the button.

const Edit := preload("res://tests/helpers/edit_api.gd")
const Factory := preload("res://tests/helpers/factory.gd")
const AddItemCommand := preload("res://tests/helpers/commands/add_item_command.gd")
const BrokenUndo := preload("res://tests/helpers/commands/broken_undo_command.gd")
const BrokenRedo := preload("res://tests/helpers/commands/broken_redo_command.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")
const SourceScan := preload("res://tests/helpers/source_scan.gd")

const WINDOW := Vector2i(1152, 648)

var _history: CommandHistory = null
var _model: AquariumModel = null
var _viewport: SubViewport = null
var _controls: Control = null
var _undo: Button = null
var _redo: Button = null


## A stand-in for a world system with a running gesture.
class Source:
	extends Node

	func has_running_gesture() -> bool:
		return true


func after_test() -> void:
	EventBus.unbind_history()


func _open() -> bool:
	_model = AquariumModel.new("2026-11-01T12:00:00Z")
	_history = CommandHistory.new()
	EventBus.bind_history(_history)
	_viewport = SubViewport.new()
	_viewport.size = WINDOW
	add_child(_viewport)
	auto_free(_viewport)
	_controls = Edit.instance(Edit.HISTORY_SCENE)
	(
		assert_bool(_controls != null)
		. override_failure_message("game/ui/history/history_controls.tscn is missing")
		. is_true()
	)
	if _controls == null:
		return false
	_controls.call("setup", _history)
	_viewport.add_child(_controls)
	await get_tree().process_frame
	await get_tree().process_frame
	_undo = _controls.find_child("UndoButton", true, false) as Button
	_redo = _controls.find_child("RedoButton", true, false) as Button
	var found: bool = _undo != null and _redo != null
	(
		assert_bool(found)
		. override_failure_message("HistoryControls needs the buttons UndoButton and RedoButton")
		. is_true()
	)
	return found


func _step(uid: String) -> void:
	var item: PlacedItem = Factory.item(uid, &"river_stone", Vector3(0.1, 0.0, 0.0), 0.0, 1.0)
	assert_bool(_history.execute(AddItemCommand.new(_model, item))).is_true()


func _click(button: Button) -> void:
	var at: Vector2 = button.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		_viewport.push_input(event)
	await get_tree().process_frame


func _states() -> Array:
	return [not _undo.disabled, not _redo.disabled]


# --- AC 15 ---


func test_ac15_both_buttons_are_disabled_at_the_start() -> void:
	if not await _open():
		return
	assert_array(_states()).is_equal([false, false])


func test_ac15_the_buttons_have_a_text_and_stop_the_mouse_while_the_root_ignores_it() -> void:
	if not await _open():
		return
	assert_str(_undo.text).is_not_empty()
	assert_str(_redo.text).is_not_empty()
	assert_int(_undo.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	assert_int(_redo.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	assert_int(_controls.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


func test_ac15_a_clear_after_a_load_or_a_reset_disables_both_buttons() -> void:
	if not await _open():
		return
	_step("c0000001")
	_step("c0000002")
	_history.undo()
	assert_array(_states()).is_equal([true, true])
	_history.clear()
	assert_array(_states()).is_equal([false, false])


# --- AC 16 ---


func test_ac16_the_buttons_follow_the_real_commands() -> void:
	if not await _open():
		return
	_step("c0000001")
	assert_array(_states()).is_equal([true, false])
	_step("c0000002")
	assert_array(_states()).is_equal([true, false])
	_history.undo()
	assert_array(_states()).is_equal([true, true])
	_history.undo()
	assert_array(_states()).is_equal([false, true])
	_history.redo()
	assert_array(_states()).is_equal([true, true])
	_history.redo()
	assert_array(_states()).is_equal([true, false])


func test_ac16_a_new_command_after_an_undo_disables_redo() -> void:
	if not await _open():
		return
	_step("c0000001")
	_history.undo()
	assert_array(_states()).is_equal([false, true])
	_step("c0000002")
	assert_array(_states()).is_equal([true, false])


func test_ac16_the_state_is_the_last_signal_not_the_history() -> void:
	if not await _open():
		return
	assert_bool(_history.can_undo()).is_false()
	EventBus.history_changed.emit(true, false)
	assert_array(_states()).is_equal([true, false])
	EventBus.history_changed.emit(false, true)
	assert_array(_states()).is_equal([false, true])
	EventBus.history_changed.emit(true, true)
	assert_array(_states()).is_equal([true, true])
	EventBus.history_changed.emit(false, false)
	assert_array(_states()).is_equal([false, false])
	assert_bool(_history.can_undo()).is_false()
	assert_bool(_history.can_redo()).is_false()


func test_ac16_the_buttons_never_ask_the_history_for_their_state() -> void:
	if not await _open():
		return
	_step("c0000001")
	# The history can undo, but the last signal said no: the button follows the signal.
	EventBus.history_changed.emit(false, false)
	assert_bool(_history.can_undo()).is_true()
	assert_array(_states()).is_equal([false, false])
	var source: String = SourceScan.strip_comments(
		FileAccess.get_file_as_string("res://ui/history/history_controls.gd")
	)
	for forbidden: String in ["can_undo()", "can_redo()", "get_undo_count", "get_redo_count"]:
		(
			assert_bool(source.contains(forbidden))
			. override_failure_message("history_controls.gd must not call %s" % forbidden)
			. is_false()
		)


# --- AC 17 ---


func test_ac17_a_click_on_enabled_undo_calls_undo_exactly_once() -> void:
	if not await _open():
		return
	_step("c0000001")
	_step("c0000002")
	var undone: Array = []
	_history.undone.connect(func(_c: Command) -> void: undone.append(1))
	await _click(_undo)
	assert_int(undone.size()).is_equal(1)
	assert_int(_history.get_undo_count()).is_equal(1)
	assert_int(_history.get_redo_count()).is_equal(1)
	assert_bool(_model.has_uid("c0000002")).is_false()


func test_ac17_a_click_on_enabled_redo_calls_redo_exactly_once() -> void:
	if not await _open():
		return
	_step("c0000001")
	_step("c0000002")
	_history.undo()
	_history.undo()
	var redone: Array = []
	_history.redone.connect(func(_c: Command) -> void: redone.append(1))
	await _click(_redo)
	assert_int(redone.size()).is_equal(1)
	assert_int(_history.get_undo_count()).is_equal(1)
	assert_int(_history.get_redo_count()).is_equal(1)


func test_ac17_a_disabled_button_does_nothing() -> void:
	if not await _open():
		return
	_step("c0000001")
	EventBus.history_changed.emit(false, false)
	await _click(_undo)
	await _click(_redo)
	assert_int(_history.get_undo_count()).is_equal(1)
	assert_int(_history.get_redo_count()).is_equal(0)
	_history.undo()
	EventBus.history_changed.emit(false, false)
	await _click(_redo)
	assert_int(_history.get_redo_count()).is_equal(1)


func test_ac17_a_click_with_nothing_to_undo_does_nothing_and_prints_no_error() -> void:
	if not await _open():
		return
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void:
			await _click(_undo)
			await _click(_redo)
	)
	assert_dict(seen["errors"]).is_empty()


func test_ac17_a_blocker_stops_a_click() -> void:
	if not await _open():
		return
	_step("c0000001")
	var blocker: Control = Control.new()
	blocker.add_to_group(&"world_input_blockers")
	blocker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport.add_child(blocker)
	await _click(_undo)
	assert_int(_history.get_undo_count()).is_equal(1)
	assert_int(_history.get_redo_count()).is_equal(0)
	blocker.visible = false
	await _click(_undo)
	assert_int(_history.get_undo_count()).is_equal(0)
	assert_int(_history.get_redo_count()).is_equal(1)
	blocker.free()


func test_ac17_a_running_gesture_stops_a_click_and_the_end_of_it_frees_the_button() -> void:
	if not await _open():
		return
	_step("c0000001")
	var source: Source = Source.new()
	source.add_to_group(&"world_gesture_sources")
	add_child(source)
	await _click(_undo)
	assert_int(_history.get_undo_count()).is_equal(1)
	source.free()
	await _click(_undo)
	assert_int(_history.get_undo_count()).is_equal(0)


func test_ac17_a_click_while_the_history_is_busy_does_nothing_and_prints_no_error() -> void:
	if not await _open():
		return
	_step("c0000001")
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void:
			var fake: Command = ClickCommand.new(self)
			assert_bool(_history.execute(fake)).is_true()
	)
	assert_dict(seen["errors"]).is_empty()
	assert_int(_history.get_undo_count()).is_equal(2)


## A command that clicks Undo from inside do(), while the history is busy.
class ClickCommand:
	extends Command

	var _suite: Node = null

	func _init(suite: Node) -> void:
		_suite = suite

	func do() -> bool:
		var button: Button = _suite.get("_undo") as Button
		button.pressed.emit()
		return true

	func undo() -> bool:
		return true


# --- AC 23 ---


func _assert_one_history_error(seen: Dictionary) -> void:
	var errors: Dictionary = seen["errors"]
	assert_int(errors.size()).override_failure_message("errors: %s" % errors).is_equal(1)
	for text: String in errors:
		assert_str(text).contains("failed; history cleared")
		assert_int(errors[text]).is_equal(1)


func _no_dialog() -> bool:
	for found: Node in _viewport.find_children("*", "Window", true, false):
		if (found as Window).visible:
			return false
	return true


func test_ac23_a_failed_undo_disables_both_buttons_without_a_dialog() -> void:
	if not await _open():
		return
	assert_bool(_history.execute(BrokenUndo.new(_model, &"tank_small_1"))).is_true()
	assert_array(_states()).is_equal([true, false])
	var seen: Dictionary = await EngineOutput.capture(func() -> void: await _click(_undo))
	_assert_one_history_error(seen)
	assert_array(_states()).is_equal([false, false])
	assert_int(_history.get_undo_count()).is_equal(0)
	assert_int(_history.get_redo_count()).is_equal(0)
	assert_bool(_no_dialog()).is_true()
	assert_bool(is_instance_valid(_controls)).is_true()


func test_ac23_a_failed_redo_disables_both_buttons_without_a_dialog() -> void:
	if not await _open():
		return
	assert_bool(_history.execute(BrokenRedo.new(_model, &"tank_small_1"))).is_true()
	assert_bool(_history.undo()).is_true()
	assert_array(_states()).is_equal([false, true])
	var seen: Dictionary = await EngineOutput.capture(func() -> void: await _click(_redo))
	_assert_one_history_error(seen)
	assert_array(_states()).is_equal([false, false])
	assert_bool(_no_dialog()).is_true()


func test_ac23_the_buttons_work_again_after_a_failure() -> void:
	if not await _open():
		return
	assert_bool(_history.execute(BrokenUndo.new(_model, &"tank_small_1"))).is_true()
	await EngineOutput.capture(func() -> void: await _click(_undo))
	_step("c0000001")
	assert_array(_states()).is_equal([true, false])
	await _click(_undo)
	assert_array(_states()).is_equal([false, true])
