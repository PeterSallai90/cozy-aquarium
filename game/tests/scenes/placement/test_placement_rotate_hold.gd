# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #31 AC 27 and 41 (owner: developer): rotating the selected item with the rotate keys. One hold,
## from the press of Comma or Period until its release, is one undo step however many repeat ticks
## it made: mid-hold the model, the history and item_changed stay as they were and the drawn item
## (with its mark) shows the pending angle; the release runs one TransformItemCommand with the
## final angle (none when it ends at the start angle within SAME_ANGLE_DEG). Esc, a selection
## change, a model change of the held item, a dialog, a focus loss and Ctrl cancel the hold with no
## command; switching keys ends the first hold as a release and starts a new one; a release always
## ends the hold wherever the pointer is. A hold on a ghost or on a drag preview never touches the
## history.
## Test decisions: the item starts at the free angle 10 so that a wrong normalisation shows; "24
## steps of 15 degrees" of AC 27 is the press plus 23 repeat ticks; repeat times are computed from
## PlacementTuning and sit between two ticks; Shift is sent as its own key event before the rotate
## key.

const Rig := preload("res://tests/helpers/placement_rig.gd")
const Session := preload("res://tests/helpers/placement_session.gd")
const Api := preload("res://tests/helpers/placement_api.gd")
const Recorder := preload("res://tests/helpers/signal_recorder.gd")
const ModelState := preload("res://tests/helpers/model_state.gd")

const FIRST := "a0000001"
const SECOND := "a0000002"
const START_DEG: float = 10.0
const ANGLE_TOLERANCE := 0.05

var _s: Session = null
var _events: Recorder = null


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


## Two items; the first stands at the free angle 10 and is selected by a click.
func _select_first(start_deg: float = START_DEG) -> bool:
	var model: AquariumModel = Rig.model()
	Rig.add_item(model, FIRST, Rig.BRANCH, -0.1, 0.0, start_deg)
	Rig.add_item(model, SECOND, Rig.STONE, 0.15, 0.0, 0.0)
	if not await _open(model):
		return false
	_s.click(_s.screen_of_item(FIRST))
	assert_str(_s.selected_uid()).is_equal(FIRST)
	_events = Recorder.new()
	_events.watch(_s.model)
	return _s.selected_uid() == FIRST


func _time_for(ticks: int, fine: bool = false) -> float:
	var interval: float = Api.tuning("FINE_REPEAT_INTERVAL_S" if fine else "REPEAT_INTERVAL_S")
	return Api.tuning("REPEAT_DELAY_S") + (ticks - 1) * interval + interval * 0.5


func _gap(actual: float, expected: float) -> float:
	return absf(wrapf(actual - expected, -180.0, 180.0))


func _drawn_is(deg: float) -> void:
	(
		assert_float(_gap(_s.drawn_yaw(FIRST), deg))
		. override_failure_message("drawn angle %s, expected %s" % [_s.drawn_yaw(FIRST), deg])
		. is_less(ANGLE_TOLERANCE)
	)


func _changed_count() -> int:
	var count: int = 0
	for event_name: String in _events.names():
		if event_name == "item_changed":
			count += 1
	return count


func _marked() -> int:
	var count: int = 0
	for found: Node in _s.node_for(FIRST).find_children("*", "GeometryInstance3D", true, false):
		if (found as GeometryInstance3D).material_overlay != null:
			count += 1
	return count


## Nothing was committed: no command, no signal, the model angle, the drawn angle back at it.
func _assert_cancelled(model_deg: float = START_DEG) -> void:
	assert_bool(_s.holding()).is_false()
	assert_int(_s.history.get_undo_count()).is_equal(0)
	assert_int(_changed_count()).is_equal(0)
	assert_float(_s.model.get_item(FIRST).rotation_y).is_equal(model_deg)
	_drawn_is(model_deg)


func test_ac27_a_tap_shows_the_pending_angle_at_once_and_commits_one_step_on_release() -> void:
	if not await _select_first():
		return
	_s.key(KEY_COMMA, true)
	assert_bool(_s.holding()).is_true()
	_drawn_is(15.0)
	assert_float(_s.model.get_item(FIRST).rotation_y).is_equal(START_DEG)
	assert_int(_changed_count()).is_equal(0)
	assert_int(_s.history.get_undo_count()).is_equal(0)
	_s.key(KEY_COMMA, false)
	assert_bool(_s.holding()).is_false()
	assert_float(_s.model.get_item(FIRST).rotation_y).is_equal_approx(15.0, 0.001)
	assert_int(_changed_count()).is_equal(1)
	assert_int(_s.history.get_undo_count()).is_equal(1)
	_drawn_is(15.0)
	assert_bool(_s.history.undo()).is_true()
	assert_float(_s.model.get_item(FIRST).rotation_y).is_equal(START_DEG)
	assert_bool(_s.history.redo()).is_true()
	assert_float(_s.model.get_item(FIRST).rotation_y).is_equal_approx(15.0, 0.001)


func test_ac27_period_turns_the_item_clockwise_a_negative_step() -> void:
	if not await _select_first():
		return
	_s.tap(KEY_PERIOD)
	assert_float(_s.model.get_item(FIRST).rotation_y).is_equal_approx(0.0, 0.001)
	_s.tap(KEY_PERIOD)
	assert_float(_s.model.get_item(FIRST).rotation_y).is_equal_approx(345.0, 0.001)
	assert_int(_s.history.get_undo_count()).is_equal(2)


func test_ac27_a_hold_with_0_1_and_5_repeat_ticks_is_one_history_entry() -> void:
	for ticks: int in [0, 1, 5]:
		if not await _select_first():
			return
		_s.key(KEY_COMMA, true)
		if ticks > 0:
			_s.step(_time_for(ticks))
		var final_deg: float = fposmod(15.0 + 15.0 * ticks, 360.0)
		_drawn_is(final_deg)
		assert_int(_s.history.get_undo_count()).is_equal(0)
		assert_int(_changed_count()).is_equal(0)
		assert_float(_s.model.get_item(FIRST).rotation_y).is_equal(START_DEG)
		assert_int(_marked()).is_greater(0)
		_s.key(KEY_COMMA, false)
		(
			assert_int(_s.history.get_undo_count())
			. override_failure_message("%d ticks" % ticks)
			. is_equal(1)
		)
		assert_int(_changed_count()).is_equal(1)
		assert_float(_s.model.get_item(FIRST).rotation_y).is_equal_approx(final_deg, 0.001)
		assert_bool(_s.history.undo()).is_true()
		assert_float(_s.model.get_item(FIRST).rotation_y).is_equal(START_DEG)
		assert_bool(_s.history.redo()).is_true()
		assert_float(_s.model.get_item(FIRST).rotation_y).is_equal_approx(final_deg, 0.001)
		Rig.close(_s)
		_s.viewport.queue_free()
		await _s.frame()


func test_ac27_24_steps_of_15_degrees_end_at_the_start_and_run_no_command() -> void:
	if not await _select_first(30.0):
		return
	_s.key(KEY_COMMA, true)
	_s.step(_time_for(23))
	_drawn_is(30.0)
	_s.key(KEY_COMMA, false)
	_assert_cancelled(30.0)


func test_ac27_24_repeat_ticks_end_one_step_past_the_start_and_run_one_command() -> void:
	if not await _select_first(30.0):
		return
	_s.key(KEY_COMMA, true)
	_s.step(_time_for(24))
	_s.key(KEY_COMMA, false)
	assert_int(_s.history.get_undo_count()).is_equal(1)
	assert_float(_s.model.get_item(FIRST).rotation_y).is_equal_approx(45.0, 0.001)


func test_ac27_a_hold_with_shift_turns_in_one_degree_steps() -> void:
	if not await _select_first():
		return
	_s.shift(true)
	_s.key(KEY_COMMA, true, KEY_MASK_SHIFT)
	_drawn_is(START_DEG + 1.0)
	_s.step(_time_for(3, true))
	_drawn_is(START_DEG + 4.0)
	_s.key(KEY_COMMA, false, KEY_MASK_SHIFT)
	_s.shift(false)
	assert_int(_s.history.get_undo_count()).is_equal(1)
	assert_float(_s.model.get_item(FIRST).rotation_y).is_equal_approx(START_DEG + 4.0, 0.001)


func test_ac27_two_separate_holds_are_two_undo_steps_on_the_same_item() -> void:
	if not await _select_first():
		return
	_s.tap(KEY_COMMA)
	_s.tap(KEY_COMMA)
	assert_int(_s.history.get_undo_count()).is_equal(2)
	assert_str(_s.selected_uid()).is_equal(FIRST)
	assert_float(_s.model.get_item(FIRST).rotation_y).is_equal_approx(30.0, 0.001)
	assert_bool(_s.history.undo()).is_true()
	assert_float(_s.model.get_item(FIRST).rotation_y).is_equal_approx(15.0, 0.001)
	assert_bool(_s.history.undo()).is_true()
	assert_float(_s.model.get_item(FIRST).rotation_y).is_equal(START_DEG)


func test_ac27_with_nothing_selected_a_rotate_key_does_nothing() -> void:
	var model: AquariumModel = Rig.model()
	Rig.add_item(model, FIRST, Rig.BRANCH, -0.1, 0.0, START_DEG)
	if not await _open(model):
		return
	var state_before: Dictionary = ModelState.snapshot(model)
	_s.key(KEY_COMMA, true)
	assert_bool(_s.holding()).is_false()
	_s.step(2.0)
	_s.key(KEY_COMMA, false)
	assert_dict(ModelState.snapshot(model)).is_equal(state_before)
	assert_int(_s.history.get_undo_count()).is_equal(0)


func test_ac41_a_esc_during_the_hold_cancels_it_and_keeps_the_selection() -> void:
	if not await _select_first():
		return
	_s.key(KEY_COMMA, true)
	_s.step(_time_for(2))
	_s.esc()
	_assert_cancelled()
	assert_str(_s.selected_uid()).is_equal(FIRST)
	assert_int(_s.clear_requests).is_equal(0)
	# The key is still held: it does nothing more until it is released and pressed again.
	_s.step(2.0)
	_assert_cancelled()
	_s.key(KEY_COMMA, false)
	_assert_cancelled()
	_s.key(KEY_COMMA, true)
	assert_bool(_s.holding()).is_true()
	_drawn_is(15.0)
	_s.key(KEY_COMMA, false)
	assert_int(_s.history.get_undo_count()).is_equal(1)


func test_ac41_a_second_esc_after_the_cancelled_hold_clears_the_selection() -> void:
	if not await _select_first():
		return
	_s.key(KEY_COMMA, true)
	_s.esc()
	_s.esc()
	assert_str(_s.selected_uid()).is_equal("")
	assert_array(_s.selection_timeline).is_equal(["selected:%s" % FIRST, "cleared"])


func test_ac41_switching_keys_ends_the_first_hold_and_starts_a_new_one() -> void:
	if not await _select_first():
		return
	_s.key(KEY_COMMA, true)
	_s.key(KEY_PERIOD, true)
	assert_int(_s.history.get_undo_count()).is_equal(1)
	assert_float(_s.model.get_item(FIRST).rotation_y).is_equal_approx(15.0, 0.001)
	assert_bool(_s.holding()).is_true()
	_drawn_is(0.0)
	_s.step(Api.tuning("REPEAT_DELAY_S") * 1.1)
	_drawn_is(345.0)
	_s.key(KEY_COMMA, false)
	assert_bool(_s.holding()).is_true()
	_drawn_is(345.0)
	_s.key(KEY_PERIOD, false)
	assert_bool(_s.holding()).is_false()
	assert_int(_s.history.get_undo_count()).is_equal(2)
	assert_float(_s.model.get_item(FIRST).rotation_y).is_equal_approx(345.0, 0.001)
	assert_bool(_s.history.undo()).is_true()
	assert_float(_s.model.get_item(FIRST).rotation_y).is_equal_approx(15.0, 0.001)
	assert_bool(_s.history.undo()).is_true()
	assert_float(_s.model.get_item(FIRST).rotation_y).is_equal(START_DEG)


func test_ac41_a_click_on_empty_world_cancels_the_hold_before_the_click_is_handled() -> void:
	if not await _select_first():
		return
	_s.key(KEY_COMMA, true)
	_s.click(_s.screen_of(0.0, 0.1))
	_assert_cancelled()
	assert_str(_s.selected_uid()).is_equal("")
	assert_array(_s.selection_timeline).is_equal(["selected:%s" % FIRST, "cleared"])


func test_ac41_a_click_on_another_item_cancels_the_hold_and_selects_it() -> void:
	if not await _select_first():
		return
	_s.key(KEY_COMMA, true)
	_s.click(_s.screen_of_item(SECOND))
	_assert_cancelled()
	assert_str(_s.selected_uid()).is_equal(SECOND)


func test_ac41_a_pick_cancels_the_hold() -> void:
	if not await _select_first():
		return
	_s.key(KEY_COMMA, true)
	_s.pick(Rig.STONE)
	_assert_cancelled()
	assert_str(_s.selected_uid()).is_equal("")


func test_ac41_removing_the_held_item_cancels_the_hold() -> void:
	if not await _select_first():
		return
	_s.key(KEY_COMMA, true)
	_s.model.apply_remove_item(FIRST)
	_s.step(0.0)
	assert_bool(_s.holding()).is_false()
	assert_int(_s.history.get_undo_count()).is_equal(0)
	_s.key(KEY_COMMA, false)
	assert_int(_s.history.get_undo_count()).is_equal(0)
	assert_object(_s.model.get_item(FIRST)).is_null()


func test_ac41_a_model_reset_cancels_the_hold() -> void:
	if not await _select_first():
		return
	_s.key(KEY_COMMA, true)
	var other: AquariumModel = Rig.model()
	Rig.add_item(other, "b0000001", Rig.AMPHORA, 0.0, 0.0)
	_s.model.reset_from(other)
	_s.step(0.0)
	assert_bool(_s.holding()).is_false()
	_s.key(KEY_COMMA, false)
	assert_int(_s.history.get_undo_count()).is_equal(0)


func test_ac41_a_displayed_tank_cancels_the_hold() -> void:
	if not await _select_first():
		return
	_s.key(KEY_COMMA, true)
	EventBus.tank_displayed.emit(&"tank_medium_1")
	assert_bool(_s.holding()).is_false()
	_s.key(KEY_COMMA, false)
	assert_int(_s.history.get_undo_count()).is_equal(0)


func test_ac41_a_change_of_the_held_item_by_someone_else_cancels_the_hold() -> void:
	if not await _select_first():
		return
	_s.key(KEY_COMMA, true)
	var changed: PlacedItem = _s.model.get_item(FIRST).copy()
	changed.rotation_y = 100.0
	_s.model.apply_replace_item(changed)
	_s.step(0.0)
	assert_bool(_s.holding()).is_false()
	_drawn_is(100.0)
	_s.key(KEY_COMMA, false)
	assert_int(_s.history.get_undo_count()).is_equal(0)
	assert_float(_s.model.get_item(FIRST).rotation_y).is_equal(100.0)
	assert_str(_s.selected_uid()).is_equal(FIRST)


func test_ac41_a_modal_dialog_cancels_the_hold() -> void:
	if not await _select_first():
		return
	_s.key(KEY_COMMA, true)
	var blocker: Control = _s.make_blocker()
	_s.set_blocked(blocker, true)
	assert_bool(_s.holding()).is_false()
	_s.set_blocked(blocker, false)
	_s.key(KEY_COMMA, false)
	_assert_cancelled()


func test_ac41_losing_the_window_focus_cancels_the_hold() -> void:
	if not await _select_first():
		return
	_s.key(KEY_COMMA, true)
	_s.focus_out()
	assert_bool(_s.holding()).is_false()
	_s.key(KEY_COMMA, false)
	_assert_cancelled()


func test_ac41_pressing_ctrl_cancels_the_hold() -> void:
	if not await _select_first():
		return
	_s.key(KEY_COMMA, true)
	_s.key(KEY_CTRL, true, KEY_MASK_CTRL)
	assert_bool(_s.holding()).is_false()
	_s.key(KEY_CTRL, false)
	_s.key(KEY_COMMA, false)
	_assert_cancelled()


func test_ac41_pressing_or_releasing_shift_does_not_interrupt_the_hold() -> void:
	if not await _select_first():
		return
	_s.key(KEY_COMMA, true)
	_s.shift(true)
	assert_bool(_s.holding()).is_true()
	_s.shift(false)
	assert_bool(_s.holding()).is_true()
	_s.key(KEY_COMMA, false)
	assert_int(_s.history.get_undo_count()).is_equal(1)


func test_ac41_a_key_release_ends_the_hold_wherever_the_pointer_is() -> void:
	if not await _select_first():
		return
	_s.key(KEY_COMMA, true)
	_s.move(Session.OUTSIDE)
	_s.key(KEY_COMMA, false)
	assert_bool(_s.holding()).is_false()
	assert_int(_s.history.get_undo_count()).is_equal(1)
	assert_float(_s.model.get_item(FIRST).rotation_y).is_equal_approx(15.0, 0.001)
	var item: PlacedItem = _s.model.get_item(FIRST)
	assert_vector(item.position).is_equal(Vector3(-0.1, 0.0, 0.0))


func test_ac41_a_hold_on_the_ghost_never_touches_the_history() -> void:
	if not await _open(Rig.model()):
		return
	_s.pick(Rig.STONE)
	_s.move(_s.screen_of(0.0, 0.0))
	_s.key(KEY_COMMA, true)
	_s.step(_time_for(5))
	_s.key(KEY_COMMA, false)
	assert_int(_s.history.get_undo_count()).is_equal(0)
	assert_float(_s.ghost_rotation()).is_equal_approx(90.0, 0.001)


func test_ac41_a_hold_during_a_drag_never_touches_the_history() -> void:
	var model: AquariumModel = Rig.model()
	Rig.add_item(model, FIRST, Rig.BRANCH, -0.1, 0.0, START_DEG)
	if not await _open(model):
		return
	_s.press(_s.screen_of_item(FIRST))
	_s.move(_s.screen_of(0.1, -0.1))
	assert_bool(_s.dragging()).is_true()
	_s.key(KEY_COMMA, true)
	_s.step(_time_for(3))
	_s.key(KEY_COMMA, false)
	assert_int(_s.history.get_undo_count()).is_equal(0)
	assert_float(_s.model.get_item(FIRST).rotation_y).is_equal(START_DEG)
	assert_bool(_s.holding()).is_false()
