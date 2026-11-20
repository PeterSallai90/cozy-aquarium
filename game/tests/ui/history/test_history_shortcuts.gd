# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #32 AC 17, 19, 20 and 21 (shortcut part; owner: developer): Ctrl+Z (action history_undo) and
## Ctrl+Y or Ctrl+Shift+Z (history_redo) read by HistoryControls in _unhandled_input with exact
## match and no echo. One press is one step, whatever the key echo does; Ctrl+Alt+Z, a bare Z and
## Shift+Y do nothing. They do nothing during a drag, while a blocker (modal dialog, photo mode)
## is up, with a text field focused (it keeps its own Ctrl+Z) and while the history is busy (the
## busy history is not asked, so no engine error). During a rotate hold Ctrl+Z cancels the hold as
## #31 AC 41 (d) says (Ctrl cancels): the item returns to its angle from before the press, no
## command and no history_changed, nothing is undone, the still held key does not restart the
## hold; a second Ctrl+Z press, after the first Z was released, undoes the previous step. The
## cancelling Ctrl+Z is sent as one event (Z with the Ctrl flag) and as separate Ctrl and Z events
## (the tail of the cancel, ADR 0008 Amendment 2 rule 16). With a pick the undo changes only the
## model: pick and ghost stay, the ghost keeps following the pointer, the next click places.
## Test decisions: the history steps are test-only AddItemCommands (history_rig.gd); the rotate
## hold starts on FIRST at the free angle 10, so a pending angle of 25 is visible; the key echo
## is pushed by hand.

const Rig := preload("res://tests/helpers/placement_rig.gd")
const Session := preload("res://tests/helpers/placement_session.gd")
const Api := preload("res://tests/helpers/placement_api.gd")
const Edit := preload("res://tests/helpers/edit_api.gd")
const Hist := preload("res://tests/helpers/history_rig.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")

const FIRST := "a0000001"
const SECOND := "a0000002"
const STEP_ONE := "b0000001"
const STEP_TWO := "b0000002"
const START_DEG: float = 10.0
const CTRL := KEY_MASK_CTRL

var _s: Session = null
var _changes: Array = []


func after_test() -> void:
	if EventBus.history_changed.is_connected(_on_history_changed):
		EventBus.history_changed.disconnect(_on_history_changed)
	Hist.close(_s)


func _on_history_changed(can_undo: bool, can_redo: bool) -> void:
	_changes.append([can_undo, can_redo])


func _open(steps: int = 2) -> bool:
	_s = await Hist.open(self)
	var complete: bool = _s.placement != null and _s.view != null and _s.ghost != null
	(
		assert_bool(complete)
		. override_failure_message("RoomCorner needs a Placement child with PlacedItems and Ghost")
		. is_true()
	)
	var shown: bool = Hist.controls(_s) != null
	(
		assert_bool(shown)
		. override_failure_message("game/ui/history/history_controls.tscn is missing")
		. is_true()
	)
	if not (complete and shown):
		return false
	if steps >= 1:
		Hist.step(_s, STEP_ONE, -0.2)
	if steps >= 2:
		Hist.step(_s, STEP_TWO, 0.2)
	_changes.clear()
	EventBus.history_changed.connect(_on_history_changed)
	return true


func _chord(keycode: Key, mods: int) -> void:
	_s.key(keycode, true, mods)
	_s.key(keycode, false, mods)
	await _s.frame()


func _echo(keycode: Key, mods: int) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	event.echo = true
	event.ctrl_pressed = (mods & CTRL) != 0
	event.shift_pressed = (mods & KEY_MASK_SHIFT) != 0
	_s.viewport.push_input(event)
	_s.step(0.0)


func _select_first() -> void:
	_s.click(_s.screen_of_item(FIRST))
	assert_str(_s.selected_uid()).is_equal(FIRST)


func _counts() -> Array:
	return [_s.history.get_undo_count(), _s.history.get_redo_count()]


# --- AC 17 ---


func test_ac17_ctrl_z_undoes_exactly_one_step_per_press() -> void:
	if not await _open():
		return
	await _chord(KEY_Z, CTRL)
	assert_array(_counts()).is_equal([1, 1])
	assert_bool(_s.model.has_uid(STEP_TWO)).is_false()
	assert_bool(_s.model.has_uid(STEP_ONE)).is_true()


func test_ac17_ctrl_y_redoes_exactly_one_step() -> void:
	if not await _open():
		return
	_s.history.undo()
	_s.history.undo()
	await _chord(KEY_Y, CTRL)
	assert_array(_counts()).is_equal([1, 1])
	assert_bool(_s.model.has_uid(STEP_ONE)).is_true()
	assert_bool(_s.model.has_uid(STEP_TWO)).is_false()


func test_ac17_ctrl_shift_z_redoes_exactly_one_step() -> void:
	if not await _open():
		return
	_s.history.undo()
	_s.history.undo()
	await _chord(KEY_Z, CTRL | KEY_MASK_SHIFT)
	assert_array(_counts()).is_equal([1, 1])
	assert_bool(_s.model.has_uid(STEP_ONE)).is_true()


func test_ac17_the_shortcuts_call_the_history_exactly_once() -> void:
	if not await _open():
		return
	var undone: Array = []
	_s.history.undone.connect(func(_c: Command) -> void: undone.append(1))
	await _chord(KEY_Z, CTRL)
	assert_int(undone.size()).is_equal(1)


func test_ac17_ctrl_alt_z_a_bare_z_and_shift_y_do_nothing() -> void:
	if not await _open():
		return
	await _chord(KEY_Z, CTRL | KEY_MASK_ALT)
	await _chord(KEY_Z, 0)
	await _chord(KEY_Z, KEY_MASK_SHIFT)
	await _chord(KEY_Y, KEY_MASK_SHIFT)
	await _chord(KEY_Z, CTRL | KEY_MASK_META)
	assert_array(_counts()).is_equal([2, 0])
	_s.history.undo()
	await _chord(KEY_Y, CTRL | KEY_MASK_SHIFT)
	await _chord(KEY_Y, CTRL | KEY_MASK_ALT)
	assert_array(_counts()).is_equal([1, 1])


func test_ac17_undo_with_nothing_to_undo_and_redo_with_nothing_to_redo_do_nothing() -> void:
	if not await _open(0):
		return
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void:
			await _chord(KEY_Z, CTRL)
			await _chord(KEY_Y, CTRL)
	)
	assert_dict(seen["errors"]).is_empty()
	assert_array(_counts()).is_equal([0, 0])
	assert_array(_changes).is_empty()


func test_ac17_ctrl_keys_never_trigger_a_world_action() -> void:
	if not await _open():
		return
	_select_first()
	await _chord(KEY_Z, CTRL)
	await _chord(KEY_Y, CTRL)
	assert_str(_s.selected_uid()).is_equal(FIRST)
	assert_bool(_s.model.has_uid(FIRST)).is_true()
	assert_bool(_s.holding()).is_false()
	assert_bool(_s.dragging()).is_false()


# --- AC 19 ---


func test_ac19_a_key_echo_does_not_undo_again() -> void:
	if not await _open():
		return
	_s.key(KEY_Z, true, CTRL)
	assert_array(_counts()).is_equal([1, 1])
	_echo(KEY_Z, CTRL)
	_echo(KEY_Z, CTRL)
	await _s.frame()
	assert_array(_counts()).is_equal([1, 1])
	_s.key(KEY_Z, false, CTRL)
	_s.key(KEY_Z, true, CTRL)
	assert_array(_counts()).is_equal([0, 2])


func test_ac19_a_key_echo_does_not_redo_again() -> void:
	if not await _open():
		return
	_s.history.undo()
	_s.history.undo()
	_s.key(KEY_Y, true, CTRL)
	_echo(KEY_Y, CTRL)
	_echo(KEY_Y, CTRL)
	await _s.frame()
	assert_array(_counts()).is_equal([1, 1])


func test_ac19_an_echo_without_a_first_press_does_nothing() -> void:
	if not await _open():
		return
	_echo(KEY_Z, CTRL)
	await _s.frame()
	assert_array(_counts()).is_equal([2, 0])


# --- AC 20 ---


func test_ac20_during_a_drag_ctrl_z_does_nothing_and_the_drag_goes_on() -> void:
	if not await _open():
		return
	var start: Vector2 = _s.screen_of_item(FIRST)
	_s.press(start)
	_s.move(start + Vector2(Api.tuning("DRAG_THRESHOLD_PX") + 4.0, 0.0))
	assert_bool(_s.dragging()).is_true()
	await _chord(KEY_Z, CTRL)
	assert_bool(_s.dragging()).is_true()
	assert_array(_counts()).is_equal([2, 0])
	_s.key(KEY_CTRL, true, CTRL)
	_s.key(KEY_Z, true, CTRL)
	_s.key(KEY_Z, false, CTRL)
	_s.key(KEY_CTRL, false, 0)
	assert_bool(_s.dragging()).is_true()
	assert_array(_counts()).is_equal([2, 0])
	_s.release(start)
	assert_bool(_s.dragging()).is_false()


func test_ac20_after_the_drag_ends_ctrl_z_works_again() -> void:
	if not await _open():
		return
	var start: Vector2 = _s.screen_of_item(FIRST)
	_s.press(start)
	_s.move(start + Vector2(Api.tuning("DRAG_THRESHOLD_PX") + 4.0, 0.0))
	_s.esc()
	assert_bool(_s.dragging()).is_false()
	_s.release(start)
	await _chord(KEY_Z, CTRL)
	assert_array(_counts()).is_equal([1, 1])


func test_ac20_a_blocker_modal_dialog_or_photo_mode_stops_both_shortcuts() -> void:
	if not await _open():
		return
	var blocker: Control = _s.make_blocker()
	_s.set_blocked(blocker, true)
	await _chord(KEY_Z, CTRL)
	assert_array(_counts()).is_equal([2, 0])
	_s.history.undo()
	await _chord(KEY_Y, CTRL)
	assert_array(_counts()).is_equal([1, 1])
	_s.set_blocked(blocker, false)
	await _chord(KEY_Y, CTRL)
	assert_array(_counts()).is_equal([2, 0])


func test_ac20_a_text_field_with_the_focus_keeps_its_own_ctrl_z_and_ctrl_y() -> void:
	if not await _open():
		return
	var field: LineEdit = _s.make_text_field()
	field.text = "abc"
	field.grab_focus()
	assert_bool(field.has_focus()).is_true()
	await _chord(KEY_Z, CTRL)
	assert_array(_counts()).is_equal([2, 0])
	_s.history.undo()
	await _chord(KEY_Y, CTRL)
	await _chord(KEY_Z, CTRL | KEY_MASK_SHIFT)
	assert_array(_counts()).is_equal([1, 1])


func test_ac20_a_focused_button_does_not_block_the_shortcuts() -> void:
	if not await _open():
		return
	var button: Button = _s.make_button()
	button.grab_focus()
	assert_bool(button.has_focus()).is_true()
	await _chord(KEY_Z, CTRL)
	assert_array(_counts()).is_equal([1, 1])


func test_ac20_a_busy_history_is_not_asked_and_prints_no_error() -> void:
	if not await _open():
		return
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void:
			var fake: Command = BusyChordCommand.new(self)
			assert_bool(_s.history.execute(fake)).is_true()
			assert_bool(_s.history.undo()).is_true()
			assert_bool(_s.history.redo()).is_true()
	)
	assert_dict(seen["errors"]).is_empty()
	# do(), undo() and redo() each sent Ctrl+Z and Ctrl+Y into a busy history: nothing ran.
	assert_array(_counts()).is_equal([3, 0])


## A command that sends Ctrl+Z and Ctrl+Y from inside do() and undo(), while the history is busy.
class BusyChordCommand:
	extends Command

	var _suite: Node = null

	func _init(suite: Node) -> void:
		_suite = suite

	func do() -> bool:
		_suite.call("_chord", KEY_Z, KEY_MASK_CTRL)
		_suite.call("_chord", KEY_Y, KEY_MASK_CTRL)
		return true

	func undo() -> bool:
		_suite.call("_chord", KEY_Z, KEY_MASK_CTRL)
		_suite.call("_chord", KEY_Y, KEY_MASK_CTRL)
		return true


# --- AC 20: the rotate hold ---


func _assert_hold_cancelled(counts: Array) -> void:
	assert_bool(_s.holding()).is_false()
	assert_float(_s.model.get_item(FIRST).rotation_y).is_equal(START_DEG)
	assert_float(absf(wrapf(_s.drawn_yaw(FIRST) - START_DEG, -180.0, 180.0))).is_less(0.05)
	assert_array(_counts()).is_equal(counts)
	assert_array(_changes).override_failure_message("history_changed fired").is_empty()


func test_ac20_ctrl_z_during_a_rotate_hold_cancels_it_and_undoes_nothing_as_one_event() -> void:
	if not await _open():
		return
	_select_first()
	_s.key(KEY_COMMA, true)
	assert_bool(_s.holding()).is_true()
	_s.key(KEY_Z, true, CTRL)
	_assert_hold_cancelled([2, 0])
	assert_bool(_s.model.has_uid(STEP_TWO)).is_true()
	# The comma key is still held and repeats: the hold does not restart.
	_echo(KEY_COMMA, 0)
	_echo(KEY_COMMA, 0)
	_s.step(1.0)
	_assert_hold_cancelled([2, 0])
	assert_bool(_s.history.can_undo()).is_true()
	assert_bool(_s.history.can_redo()).is_false()
	_s.key(KEY_Z, false, CTRL)
	_s.key(KEY_COMMA, false)
	_assert_hold_cancelled([2, 0])


func test_ac20_a_second_ctrl_z_press_after_the_cancel_undoes_the_previous_step() -> void:
	if not await _open():
		return
	_select_first()
	_s.key(KEY_COMMA, true)
	_s.key(KEY_Z, true, CTRL)
	_s.key(KEY_Z, false, CTRL)
	_s.key(KEY_COMMA, false)
	_assert_hold_cancelled([2, 0])
	_s.key(KEY_Z, true, CTRL)
	_s.key(KEY_Z, false, CTRL)
	assert_array(_counts()).is_equal([1, 1])
	assert_bool(_s.model.has_uid(STEP_TWO)).is_false()
	assert_bool(_s.model.has_uid(STEP_ONE)).is_true()
	assert_array(_changes).is_equal([[true, true]])


func test_ac20_the_same_with_separate_ctrl_and_z_events() -> void:
	if not await _open():
		return
	_select_first()
	_s.key(KEY_COMMA, true)
	assert_bool(_s.holding()).is_true()
	_s.key(KEY_CTRL, true, CTRL)
	assert_bool(_s.holding()).is_false()
	_s.key(KEY_Z, true, CTRL)
	_assert_hold_cancelled([2, 0])
	_echo(KEY_COMMA, CTRL)
	_s.key(KEY_CTRL, false, 0)
	_s.key(KEY_Z, false, 0)
	_s.key(KEY_COMMA, false)
	_assert_hold_cancelled([2, 0])
	assert_bool(_s.model.has_uid(STEP_TWO)).is_true()
	# A new press undoes as usual.
	_s.key(KEY_CTRL, true, CTRL)
	_s.key(KEY_Z, true, CTRL)
	assert_array(_counts()).is_equal([1, 1])
	_s.key(KEY_Z, false, CTRL)
	_s.key(KEY_CTRL, false, 0)
	assert_array(_counts()).is_equal([1, 1])
	assert_float(_s.model.get_item(FIRST).rotation_y).is_equal(START_DEG)


func test_ac20_z_released_before_ctrl_ends_the_tail_with_separate_events() -> void:
	if not await _open():
		return
	_select_first()
	_s.key(KEY_COMMA, true)
	_s.key(KEY_CTRL, true, CTRL)
	_s.key(KEY_Z, true, CTRL)
	_assert_hold_cancelled([2, 0])
	_s.key(KEY_Z, false, CTRL)
	_s.key(KEY_COMMA, false, CTRL)
	# Ctrl is still down; a new Z press undoes once.
	_s.key(KEY_Z, true, CTRL)
	assert_array(_counts()).is_equal([1, 1])
	_s.key(KEY_Z, false, CTRL)
	_s.key(KEY_CTRL, false, 0)


func test_ac20_the_cancelled_hold_leaves_the_model_and_history_untouched_after_release() -> void:
	if not await _open():
		return
	_select_first()
	var state_before: Dictionary = {
		"items": _s.model.get_item_count(), "angle": _s.model.get_item(FIRST).rotation_y
	}
	_s.key(KEY_COMMA, true)
	_s.step(0.5)
	_s.key(KEY_Z, true, CTRL)
	_s.key(KEY_Z, false, CTRL)
	_s.key(KEY_COMMA, false)
	await _s.frame()
	assert_int(_s.model.get_item_count()).is_equal(state_before["items"])
	assert_float(_s.model.get_item(FIRST).rotation_y).is_equal(state_before["angle"])
	assert_array(_counts()).is_equal([2, 0])
	assert_array(_changes).is_empty()


func test_ac20_the_tail_does_not_block_a_later_ctrl_z_when_no_hold_was_cancelled() -> void:
	if not await _open():
		return
	_select_first()
	await _chord(KEY_Z, CTRL)
	await _chord(KEY_Z, CTRL)
	assert_array(_counts()).is_equal([0, 2])


func test_rule16_placement_joins_the_gesture_group_and_reports_drag_hold_and_idle() -> void:
	if not await _open():
		return
	assert_bool(_s.placement.is_in_group(Edit.GESTURE_GROUP)).is_true()
	assert_bool(Edit.is_gesture_running(get_tree()) == true).is_false()
	_select_first()
	_s.key(KEY_COMMA, true)
	assert_bool(_s.placement.call("has_running_gesture")).is_true()
	assert_bool(Edit.is_gesture_running(get_tree()) == true).is_true()
	_s.key(KEY_COMMA, false)
	assert_bool(Edit.is_gesture_running(get_tree()) == true).is_false()
	var start: Vector2 = _s.screen_of_item(SECOND)
	_s.press(start)
	_s.move(start + Vector2(Api.tuning("DRAG_THRESHOLD_PX") + 4.0, 0.0))
	assert_bool(Edit.is_gesture_running(get_tree()) == true).is_true()
	_s.release(start)
	assert_bool(Edit.is_gesture_running(get_tree()) == true).is_false()


# --- AC 21 ---


func test_ac21_with_a_pick_ctrl_z_changes_only_the_model_and_the_ghost_stays() -> void:
	if not await _open():
		return
	_s.pick(Rig.STONE)
	var at: Vector2 = _s.screen_of(0.0, 0.1)
	_s.move(at)
	assert_bool(_s.ghost_shown()).is_true()
	var ghost_at: Vector3 = _s.local_position(_s.ghost)
	await _chord(KEY_Z, CTRL)
	_s.step(0.0)
	assert_array(_counts()).is_equal([1, 1])
	assert_str(_s.picked_id()).is_equal(String(Rig.STONE))
	assert_bool(_s.ghost_shown()).is_true()
	assert_vector(_s.local_position(_s.ghost)).is_equal_approx(
		ghost_at, Vector3(0.0002, 0.0002, 0.0002)
	)
	var moved: Vector2 = _s.screen_of(0.1, 0.05)
	_s.move(moved)
	assert_vector(_s.local_position(_s.ghost)).is_equal_approx(
		_s.ground_local(moved), Vector3(0.0002, 0.0002, 0.0002)
	)


func test_ac21_the_next_click_after_an_undo_places_normally() -> void:
	if not await _open():
		return
	_s.pick(Rig.STONE)
	var at: Vector2 = _s.screen_of(0.0, 0.1)
	_s.move(at)
	await _chord(KEY_Z, CTRL)
	var count: int = _s.model.get_item_count()
	_s.move(at)
	_s.click(at)
	assert_int(_s.model.get_item_count()).is_equal(count + 1)
	assert_int(_s.history.get_undo_count()).is_equal(2)
	assert_int(_s.history.get_redo_count()).is_equal(0)


func test_ac21_redo_with_a_pick_keeps_the_pick_and_the_ghost_too() -> void:
	if not await _open():
		return
	_s.history.undo()
	_s.pick(Rig.STONE)
	var at: Vector2 = _s.screen_of(0.0, 0.1)
	_s.move(at)
	await _chord(KEY_Y, CTRL)
	_s.step(0.0)
	assert_array(_counts()).is_equal([2, 0])
	assert_str(_s.picked_id()).is_equal(String(Rig.STONE))
	assert_bool(_s.ghost_shown()).is_true()
