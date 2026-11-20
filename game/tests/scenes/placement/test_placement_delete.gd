# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #32 AC 1 to 5 (owner: developer): deleting the selected item, from the Delete key (action
## item_delete, read by PlacementSystem) and from EventBus.item_delete_requested (the HUD button).
## One DeleteItemCommand: item_removed once, no other item touched, one history entry, the
## selection cleared once (#31 rules); undo brings the item back at its old index, drawn, with
## every field and not selected; redo deletes again. Nothing happens, with no command and no
## history entry, without a selection, with a pick, during a drag, during a rotate hold, while a
## modal dialog or photo mode blocks the world (a fake blocker), while a text field has the focus,
## with Shift, Ctrl, Alt or Meta held, on a key echo, and while the history is busy (no engine
## error). A focused Button does not block the key. A dropped item (after a drag) deletes the
## same way. The Items panel case and the hint line are in test_main_history.gd.
## Test decisions: the item is selected by a real click on it; the echo event is pushed by hand;
## the busy history is a fake command whose do() sends the Delete key from inside the command.

const Rig := preload("res://tests/helpers/placement_rig.gd")
const Session := preload("res://tests/helpers/placement_session.gd")
const Api := preload("res://tests/helpers/placement_api.gd")
const Edit := preload("res://tests/helpers/edit_api.gd")
const Recorder := preload("res://tests/helpers/signal_recorder.gd")
const ModelState := preload("res://tests/helpers/model_state.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")
const Factory := preload("res://tests/helpers/factory.gd")

const FIRST := "a0000001"
const SECOND := "a0000002"
const THIRD := "a0000003"

var _s: Session = null


func after_test() -> void:
	Rig.close(_s)


func _open(model: AquariumModel = null) -> bool:
	_s = await Rig.open(self, model)
	var complete: bool = _s.placement != null and _s.view != null and _s.ghost != null
	(
		assert_bool(complete)
		. override_failure_message(
			"RoomCorner needs a Placement child with the children PlacedItems and Ghost"
		)
		. is_true()
	)
	var wired: bool = EventBus.has_signal("item_delete_requested") and Edit.exists(Edit.DELETE)
	(
		assert_bool(wired)
		. override_failure_message("EventBus.item_delete_requested or DeleteItemCommand is missing")
		. is_true()
	)
	return complete and wired


func _trio() -> AquariumModel:
	var model: AquariumModel = Rig.model()
	Rig.add_item(model, FIRST, Rig.STONE, -0.15, 0.0)
	Rig.add_item(model, SECOND, Rig.BRANCH, 0.15, 0.0, 90.0)
	Rig.add_item(model, THIRD, Rig.AMPHORA, 0.0, 0.12, 37.5)
	return model


func _select(uid: String = FIRST) -> bool:
	_s.click(_s.screen_of_item(uid))
	assert_str(_s.selected_uid()).is_equal(uid)
	return _s.selected_uid() == uid


## The two ways to ask for a delete: the key, and the HUD button's request.
func _ask(via_key: bool) -> void:
	if via_key:
		_s.tap(KEY_DELETE)
	else:
		EventBus.emit_signal("item_delete_requested")
	await _s.frame()


func _key_event(keycode: Key, pressed: bool, echo: bool, mods: int) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	event.echo = echo
	event.ctrl_pressed = (mods & KEY_MASK_CTRL) != 0
	event.shift_pressed = (mods & KEY_MASK_SHIFT) != 0
	event.alt_pressed = (mods & KEY_MASK_ALT) != 0
	event.meta_pressed = (mods & KEY_MASK_META) != 0
	_s.viewport.push_input(event)
	_s.step(0.0)


func _assert_nothing_deleted(count: int = 3) -> void:
	assert_int(_s.model.get_item_count()).is_equal(count)
	assert_bool(_s.model.has_uid(FIRST)).is_true()
	assert_int(_s.drawn_count()).is_equal(count)


func _cleared_count() -> int:
	return _s.selection_timeline.count("cleared")


# --- AC 1 ---


func test_ac01_delete_removes_the_selected_item_with_one_command_and_one_signal() -> void:
	for via_key: bool in [true, false]:
		if not await _open(_trio()):
			return
		_select()
		var events: Recorder = Recorder.new()
		events.watch(_s.model)
		await _ask(via_key)
		assert_array(events.names()).override_failure_message("key %s" % via_key).is_equal(
			["item_removed"]
		)
		assert_array(events.args_of(0)).is_equal([FIRST, 0])
		assert_bool(_s.model.has_uid(FIRST)).is_false()
		assert_int(_s.model.get_item_count()).is_equal(2)
		assert_int(_s.history.get_undo_count()).is_equal(1)
		assert_int(_s.drawn_count()).is_equal(2)
		assert_object(_s.node_for(FIRST)).is_null()
		Rig.close(_s)


func test_ac01_no_other_item_is_touched() -> void:
	if not await _open(_trio()):
		return
	_select()
	var second: PlacedItem = _s.model.get_item(SECOND)
	var third: PlacedItem = _s.model.get_item(THIRD)
	var second_before: Vector3 = second.position
	await _ask(true)
	assert_object(_s.model.get_item(SECOND)).is_same(second)
	assert_object(_s.model.get_item(THIRD)).is_same(third)
	assert_vector(second.position).is_equal(second_before)
	assert_float(third.rotation_y).is_equal(37.5)
	assert_object(_s.node_for(SECOND)).is_not_null()
	assert_object(_s.node_for(THIRD)).is_not_null()


func test_ac01_the_command_is_a_delete_command_in_the_history() -> void:
	if not await _open(_trio()):
		return
	_select()
	await _ask(true)
	assert_bool(_s.history.can_undo()).is_true()
	assert_bool(_s.history.can_redo()).is_false()
	assert_bool(_s.history.undo()).is_true()
	assert_int(_s.model.get_item_index(FIRST)).is_equal(0)


# --- AC 2 ---


func test_ac02_undo_restores_the_item_at_its_index_drawn_and_not_selected() -> void:
	for via_key: bool in [true, false]:
		if not await _open(_trio()):
			return
		var state_before: Dictionary = ModelState.snapshot(_s.model)
		state_before.erase("modified")
		_select(SECOND)
		await _ask(via_key)
		_s.selection_timeline.clear()
		assert_bool(_s.history.undo()).is_true()
		await _s.frame()
		var state_after: Dictionary = ModelState.snapshot(_s.model)
		state_after.erase("modified")
		assert_dict(state_after).is_equal(state_before)
		assert_int(_s.model.get_item_index(SECOND)).is_equal(1)
		assert_int(_s.drawn_count()).is_equal(3)
		assert_object(_s.node_for(SECOND)).is_not_null()
		assert_str(_s.selected_uid()).is_equal("")
		assert_array(_s.selection_timeline).is_empty()
		assert_bool(_s.history.redo()).is_true()
		await _s.frame()
		assert_bool(_s.model.has_uid(SECOND)).is_false()
		assert_int(_s.drawn_count()).is_equal(2)
		Rig.close(_s)


func test_ac02_the_undone_item_can_be_selected_again_by_a_click() -> void:
	if not await _open(_trio()):
		return
	_select()
	await _ask(true)
	assert_bool(_s.history.undo()).is_true()
	await _s.frame()
	_s.click(_s.screen_of_item(FIRST))
	assert_str(_s.selected_uid()).is_equal(FIRST)


# --- AC 3 ---


func test_ac03_after_the_delete_nothing_is_selected_and_the_signal_fired_once() -> void:
	for via_key: bool in [true, false]:
		if not await _open(_trio()):
			return
		_select()
		await _ask(via_key)
		assert_str(_s.selected_uid()).is_equal("")
		assert_int(_cleared_count()).override_failure_message("key %s" % via_key).is_equal(1)
		assert_array(_s.selection_timeline).is_equal(["selected:%s" % FIRST, "cleared"])
		Rig.close(_s)


# --- AC 4: nothing happens ---


func test_ac04_nothing_selected_does_nothing() -> void:
	for via_key: bool in [true, false]:
		if not await _open(_trio()):
			return
		await _ask(via_key)
		_assert_nothing_deleted()
		assert_int(_s.history.get_undo_count()).is_equal(0)
		Rig.close(_s)


func test_ac04_a_pick_does_nothing() -> void:
	for via_key: bool in [true, false]:
		if not await _open(_trio()):
			return
		_select()
		_s.pick(Rig.STONE)
		assert_str(_s.picked_id()).is_equal(String(Rig.STONE))
		await _ask(via_key)
		_assert_nothing_deleted()
		assert_int(_s.history.get_undo_count()).is_equal(0)
		Rig.close(_s)


func test_ac04_a_running_drag_does_nothing_and_the_drag_goes_on() -> void:
	for via_key: bool in [true, false]:
		if not await _open(_trio()):
			return
		_select()
		var start: Vector2 = _s.screen_of_item(FIRST)
		_s.press(start)
		_s.move(start + Vector2(Api.tuning("DRAG_THRESHOLD_PX") + 4.0, 0.0))
		assert_bool(_s.dragging()).is_true()
		await _ask(via_key)
		assert_bool(_s.dragging()).is_true()
		_assert_nothing_deleted()
		assert_int(_s.history.get_undo_count()).is_equal(0)
		_s.release(start)
		Rig.close(_s)


func test_ac04_a_running_rotate_hold_does_nothing_and_the_hold_goes_on() -> void:
	for via_key: bool in [true, false]:
		if not await _open(_trio()):
			return
		_select()
		_s.key(KEY_COMMA, true)
		assert_bool(_s.holding()).is_true()
		await _ask(via_key)
		assert_bool(_s.holding()).is_true()
		_assert_nothing_deleted()
		assert_int(_s.history.get_undo_count()).is_equal(0)
		_s.key(KEY_COMMA, false)
		Rig.close(_s)


func test_ac04_a_blocker_modal_dialog_or_photo_mode_does_nothing() -> void:
	for via_key: bool in [true, false]:
		if not await _open(_trio()):
			return
		_select()
		var blocker: Control = _s.make_blocker()
		_s.set_blocked(blocker, true)
		await _ask(via_key)
		_s.set_blocked(blocker, false)
		_assert_nothing_deleted()
		assert_int(_s.history.get_undo_count()).is_equal(0)
		Rig.close(_s)


func test_ac04_a_text_field_with_the_focus_does_nothing() -> void:
	if not await _open(_trio()):
		return
	_select()
	var field: LineEdit = _s.make_text_field()
	field.grab_focus()
	assert_bool(field.has_focus()).is_true()
	await _ask(true)
	_assert_nothing_deleted()
	assert_int(_s.history.get_undo_count()).is_equal(0)


func test_ac04_shift_ctrl_alt_or_meta_with_delete_does_nothing() -> void:
	for mask: int in [KEY_MASK_SHIFT, KEY_MASK_CTRL, KEY_MASK_ALT, KEY_MASK_META]:
		if not await _open(_trio()):
			return
		_select()
		_s.key(KEY_DELETE, true, mask)
		_s.key(KEY_DELETE, false, mask)
		await _s.frame()
		(
			assert_int(_s.model.get_item_count())
			. override_failure_message("modifier mask %d deleted the item" % mask)
			. is_equal(3)
		)
		assert_int(_s.history.get_undo_count()).is_equal(0)
		assert_str(_s.selected_uid()).is_equal(FIRST)
		Rig.close(_s)


func test_ac04_a_key_echo_does_nothing() -> void:
	if not await _open(_trio()):
		return
	_select()
	_key_event(KEY_DELETE, true, true, 0)
	await _s.frame()
	_assert_nothing_deleted()
	assert_int(_s.history.get_undo_count()).is_equal(0)


func test_ac04_a_focused_button_does_not_block_the_delete_key() -> void:
	if not await _open(_trio()):
		return
	_select()
	var button: Button = _s.make_button()
	button.grab_focus()
	assert_bool(button.has_focus()).is_true()
	await _ask(true)
	assert_bool(_s.model.has_uid(FIRST)).is_false()
	assert_int(_s.history.get_undo_count()).is_equal(1)


func test_ac04_a_busy_history_is_not_asked_and_prints_no_error() -> void:
	if not await _open(_trio()):
		return
	_select()
	var fake: Command = BusyKeyCommand.new(self)
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void: assert_bool(_s.history.execute(fake)).is_true()
	)
	assert_dict(seen["errors"]).is_empty()
	_assert_nothing_deleted()
	assert_int(_s.history.get_undo_count()).is_equal(1)


## Sends the Delete key from inside do(), when the history is busy.
class BusyKeyCommand:
	extends Command

	var _suite: Node = null

	func _init(suite: Node) -> void:
		_suite = suite

	func do() -> bool:
		_suite.call("_ask", true)
		return true

	func undo() -> bool:
		return true


func test_ac04_requests_without_a_selection_or_after_a_clear_do_nothing() -> void:
	if not await _open(_trio()):
		return
	_select()
	_s.esc()
	assert_str(_s.selected_uid()).is_equal("")
	await _ask(false)
	await _ask(true)
	_assert_nothing_deleted()


# --- AC 5 ---


func test_ac05_a_just_dropped_item_is_deleted_the_same_way_without_a_dialog() -> void:
	for via_key: bool in [true, false]:
		if not await _open(_trio()):
			return
		var start: Vector2 = _s.screen_of_item(FIRST)
		_s.press(start)
		_s.move(_s.screen_of(-0.05, -0.08))
		assert_bool(_s.dragging()).is_true()
		_s.release(_s.screen_of(-0.05, -0.08))
		assert_str(_s.selected_uid()).is_equal(FIRST)
		var undo_before: int = _s.history.get_undo_count()
		await _ask(via_key)
		assert_bool(_s.model.has_uid(FIRST)).is_false()
		assert_int(_s.history.get_undo_count()).is_equal(undo_before + 1)
		assert_bool(_s.history.undo()).is_true()
		assert_bool(_s.history.undo()).is_true()
		Rig.close(_s)


func test_ac05_a_freshly_placed_item_after_selecting_it_is_deleted() -> void:
	if not await _open(_trio()):
		return
	_s.pick(Rig.STONE)
	var at: Vector2 = _s.screen_of(0.2, -0.1)
	_s.move(at)
	_s.click(at)
	assert_int(_s.model.get_item_count()).is_equal(4)
	_s.unpick()
	var uid: String = _s.model.get_item_at(3).uid
	_s.click(_s.screen_of_item(uid))
	assert_str(_s.selected_uid()).is_equal(uid)
	await _ask(true)
	assert_bool(_s.model.has_uid(uid)).is_false()
	assert_int(_s.model.get_item_count()).is_equal(3)


func test_ac05_a_deleted_item_does_not_disturb_the_next_selection() -> void:
	if not await _open(_trio()):
		return
	_select()
	await _ask(true)
	_s.click(_s.screen_of_item(SECOND))
	assert_str(_s.selected_uid()).is_equal(SECOND)
	await _ask(false)
	assert_bool(_s.model.has_uid(SECOND)).is_false()
	assert_int(_s.model.get_item_count()).is_equal(1)
	assert_int(_s.history.get_undo_count()).is_equal(2)
