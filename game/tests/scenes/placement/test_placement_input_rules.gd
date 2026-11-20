extends GdUnitTestSuite
## #31 AC 28 and 37 (owner: developer): the input rules of the rotate keys and of the world. A
## focused LineEdit keeps the characters (the rotate keys do nothing), as do Ctrl, Alt or Meta, also
## with Shift, and a modal dialog; Shift alone is the one allowed modifier (the fine step). A
## focused Button does not block the keys. A press in the world releases the focus of a text field
## and is then handled normally. While the world is blocked (a fake blocker standing in for the
## dialog and for photo mode, ADR 0008 Amendment 1 rule 10) the ghost, the mark and every gesture
## are off, the pick and the selection survive, and everything is back when the blocker is gone.
## Test decisions: the rotate keys carry their unicode (44 and 46) so a focused LineEdit would
## consume them; the fake blocker is a Control of the group world_input_blockers.

const Rig := preload("res://tests/helpers/placement_rig.gd")
const Session := preload("res://tests/helpers/placement_session.gd")
const Api := preload("res://tests/helpers/placement_api.gd")
const ModelState := preload("res://tests/helpers/model_state.gd")

const FIRST := "a0000001"

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
	return complete


func _one_item() -> AquariumModel:
	var model: AquariumModel = Rig.model()
	Rig.add_item(model, FIRST, Rig.BRANCH, -0.1, 0.0, 10.0)
	return model


func _marked() -> int:
	var count: int = 0
	for found: Node in _s.node_for(FIRST).find_children("*", "GeometryInstance3D", true, false):
		if (found as GeometryInstance3D).material_overlay != null:
			count += 1
	return count


# --- AC 28 ---


func test_ac28_a_focused_text_field_keeps_the_rotate_keys_from_the_ghost() -> void:
	if not await _open(Rig.model()):
		return
	_s.pick(Rig.STONE)
	_s.move(_s.screen_of(0.0, 0.0))
	var field: LineEdit = _s.make_text_field()
	field.grab_focus()
	await _s.frame()
	assert_bool(field.has_focus()).is_true()
	_s.tap(KEY_COMMA)
	_s.tap(KEY_PERIOD)
	_s.tap(KEY_COMMA, KEY_MASK_SHIFT)
	assert_float(_s.ghost_rotation()).is_equal_approx(0.0, 0.001)


func test_ac28_a_focused_text_field_keeps_the_rotate_keys_from_a_selected_item() -> void:
	if not await _open(_one_item()):
		return
	_s.click(_s.screen_of_item(FIRST))
	var field: LineEdit = _s.make_text_field()
	field.grab_focus()
	await _s.frame()
	_s.key(KEY_COMMA, true)
	assert_bool(_s.holding()).is_false()
	_s.key(KEY_COMMA, false)
	assert_int(_s.history.get_undo_count()).is_equal(0)


func test_ac28_ctrl_alt_or_meta_stop_the_rotate_keys_also_together_with_shift() -> void:
	if not await _open(Rig.model()):
		return
	_s.pick(Rig.STONE)
	_s.move(_s.screen_of(0.0, 0.0))
	for modifiers: int in [
		KEY_MASK_CTRL,
		KEY_MASK_ALT,
		KEY_MASK_META,
		KEY_MASK_CTRL | KEY_MASK_SHIFT,
		KEY_MASK_ALT | KEY_MASK_SHIFT,
		KEY_MASK_META | KEY_MASK_SHIFT,
	]:
		_s.tap(KEY_COMMA, modifiers)
		_s.tap(KEY_PERIOD, modifiers)
		(
			assert_float(_s.ghost_rotation())
			. override_failure_message("modifiers %d changed the ghost rotation" % modifiers)
			. is_equal_approx(0.0, 0.001)
		)


func test_ac28_shift_alone_selects_the_one_degree_step() -> void:
	if not await _open(Rig.model()):
		return
	_s.pick(Rig.STONE)
	_s.move(_s.screen_of(0.0, 0.0))
	_s.tap(KEY_COMMA, KEY_MASK_SHIFT)
	assert_float(_s.ghost_rotation()).is_equal_approx(1.0, 0.001)


func test_ac28_a_modal_dialog_stops_the_rotate_keys() -> void:
	if not await _open(Rig.model()):
		return
	_s.pick(Rig.STONE)
	_s.move(_s.screen_of(0.0, 0.0))
	var blocker: Control = _s.make_blocker()
	_s.set_blocked(blocker, true)
	_s.tap(KEY_COMMA)
	_s.tap(KEY_PERIOD, KEY_MASK_SHIFT)
	_s.set_blocked(blocker, false)
	assert_float(_s.ghost_rotation()).is_equal_approx(0.0, 0.001)


func test_ac28_a_focused_button_does_not_block_the_rotate_keys() -> void:
	if not await _open(Rig.model()):
		return
	_s.pick(Rig.STONE)
	_s.move(_s.screen_of(0.0, 0.0))
	var button: Button = _s.make_button()
	button.grab_focus()
	await _s.frame()
	assert_bool(button.has_focus()).is_true()
	_s.tap(KEY_PERIOD)
	assert_float(_s.ghost_rotation()).is_equal_approx(345.0, 0.001)
	assert_bool(_s.ghost_shown()).is_true()


func test_ac28_a_press_in_the_world_releases_the_text_focus_and_is_then_handled() -> void:
	if not await _open(Rig.model()):
		return
	_s.pick(Rig.STONE)
	var at: Vector2 = _s.screen_of(0.0, 0.0)
	_s.move(at)
	var field: LineEdit = _s.make_text_field()
	field.grab_focus()
	await _s.frame()
	assert_bool(field.has_focus()).is_true()
	_s.click(at)
	assert_bool(field.has_focus()).is_false()
	assert_int(_s.model.get_item_count()).is_equal(1)
	_s.tap(KEY_COMMA)
	assert_float(_s.ghost_rotation()).is_equal_approx(15.0, 0.001)


# --- AC 37 ---


func test_ac37_a_blocker_hides_the_ghost_and_the_pick_survives_with_its_rotation() -> void:
	if not await _open(Rig.model()):
		return
	_s.pick(Rig.STONE)
	_s.tap(KEY_COMMA)
	_s.tap(KEY_COMMA)
	var at: Vector2 = _s.screen_of(0.0, 0.0)
	_s.move(at)
	assert_bool(_s.ghost_shown()).is_true()
	var blocker: Control = _s.make_blocker()
	_s.set_blocked(blocker, true)
	assert_bool(_s.ghost_shown()).is_false()
	assert_str(_s.picked_id()).is_equal(String(Rig.STONE))
	_s.set_blocked(blocker, false)
	_s.move(at + Vector2(1.0, 0.0))
	assert_bool(_s.ghost_shown()).is_true()
	assert_float(_s.ghost_rotation()).is_equal_approx(30.0, 0.001)
	assert_float(absf(wrapf(_s.yaw_of(_s.ghost) - 30.0, -180.0, 180.0))).is_less(0.05)


func test_ac37_a_blocker_hides_the_mark_and_the_selection_survives() -> void:
	if not await _open(_one_item()):
		return
	_s.click(_s.screen_of_item(FIRST))
	assert_int(_marked()).is_greater(0)
	var blocker: Control = _s.make_blocker()
	_s.set_blocked(blocker, true)
	assert_int(_marked()).is_equal(0)
	assert_str(_s.selected_uid()).is_equal(FIRST)
	_s.set_blocked(blocker, false)
	assert_int(_marked()).is_greater(0)
	assert_str(_s.selected_uid()).is_equal(FIRST)


func test_ac37_while_blocked_no_placement_selection_or_rotate_key_is_handled() -> void:
	var model: AquariumModel = _one_item()
	if not await _open(model):
		return
	var blocker: Control = _s.make_blocker()
	_s.set_blocked(blocker, true)
	_s.click(_s.screen_of_item(FIRST))
	assert_str(_s.selected_uid()).is_equal("")
	_s.pick(Rig.STONE)
	_s.click(_s.screen_of(0.1, 0.05))
	assert_int(model.get_item_count()).is_equal(1)
	_s.tap(KEY_COMMA)
	_s.tap(KEY_COMMA, KEY_MASK_SHIFT)
	assert_float(_s.ghost_rotation()).is_equal_approx(0.0, 0.001)
	assert_int(_s.history.get_undo_count()).is_equal(0)


func test_ac37_starting_a_blocker_cancels_a_drag_and_a_hold_with_no_command() -> void:
	var model: AquariumModel = _one_item()
	if not await _open(model):
		return
	_s.press(_s.screen_of_item(FIRST))
	_s.move(_s.screen_of(0.1, -0.1))
	assert_bool(_s.dragging()).is_true()
	var blocker: Control = _s.make_blocker()
	_s.set_blocked(blocker, true)
	assert_bool(_s.dragging()).is_false()
	_s.release(_s.screen_of(0.1, -0.1))
	_s.set_blocked(blocker, false)
	assert_int(_s.history.get_undo_count()).is_equal(0)
	_s.click(_s.screen_of_item(FIRST))
	assert_str(_s.selected_uid()).is_equal(FIRST)
	_s.key(KEY_COMMA, true)
	assert_bool(_s.holding()).is_true()
	_s.set_blocked(blocker, true)
	assert_bool(_s.holding()).is_false()
	_s.set_blocked(blocker, false)
	_s.key(KEY_COMMA, false)
	assert_int(_s.history.get_undo_count()).is_equal(0)
	assert_float(model.get_item(FIRST).rotation_y).is_equal(10.0)
