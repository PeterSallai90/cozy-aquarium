# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #31 AC 21 to 26, 36 and 40 (drop part) (owner: developer): moving a placed item by dragging.
## Without a pick, a press on an item and a move beyond the drag threshold start a drag: a
## ghost-like
## preview follows the ground point under the pointer at the item rotation, the model item and
## history stay for the whole drag, and the drawn item stays at its start. Rotate keys turn the
## preview (no hold starts). A release over a valid ground point commits one TransformItemCommand
## (one item_changed, one history entry, the dropped item becomes the selection); a drop at the same
## spot runs nothing and selects like a click. Esc, a release outside the tank or over a panel, a
## modal dialog, a focus loss, model_reset and the removal or replacement of the dragged item cancel
## the drag with no command and the selection as before. A drag started in the world keeps running
## over a panel; a press that starts on a panel starts nothing.
## Test decisions: the pointer leaves the press spot in one motion event to the target; the start
## spot of the same-spot case is the ground point of the item origin (the drag has no grab offset).

const Rig := preload("res://tests/helpers/placement_rig.gd")
const Session := preload("res://tests/helpers/placement_session.gd")
const Api := preload("res://tests/helpers/placement_api.gd")
const Recorder := preload("res://tests/helpers/signal_recorder.gd")
const ModelState := preload("res://tests/helpers/model_state.gd")

const FIRST := "a0000001"
const SECOND := "a0000002"
const TOLERANCE := 0.0002
const ANGLE_TOLERANCE := 0.05

var _s: Session = null


func after_test() -> void:
	Rig.close(_s)


func _open(model: AquariumModel = null, elevation: float = Rig.TOP_ELEVATION_DEG) -> bool:
	_s = await Rig.open(self, model, elevation)
	var complete: bool = _s.placement != null and _s.view != null and _s.ghost != null
	(
		assert_bool(complete)
		. override_failure_message(
			"RoomCorner needs a Placement child with the children PlacedItems and Ghost"
		)
		. is_true()
	)
	return complete


func _pair() -> AquariumModel:
	var model: AquariumModel = Rig.model()
	Rig.add_item(model, FIRST, Rig.STONE, -0.15, 0.0)
	Rig.add_item(model, SECOND, Rig.BRANCH, 0.15, 0.0, 90.0)
	return model


func _threshold() -> float:
	return Api.tuning("DRAG_THRESHOLD_PX")


## Presses on the first item and moves the pointer to `to` (one motion event).
func _start_drag(to: Vector2) -> void:
	_s.press(_s.screen_of_item(FIRST))
	_s.move(to)


func _yaw_gap(actual: float, expected: float) -> float:
	return absf(wrapf(actual - expected, -180.0, 180.0))


func _cancelled(state_before: Dictionary) -> void:
	assert_bool(_s.dragging()).is_false()
	assert_bool(_s.ghost_shown()).is_false()
	assert_int(_s.history.get_undo_count()).is_equal(0)
	assert_dict(ModelState.snapshot(_s.model)).is_equal(state_before)


func _marked(uid: String) -> int:
	var count: int = 0
	for found: Node in _s.node_for(uid).find_children("*", "GeometryInstance3D", true, false):
		if (found as GeometryInstance3D).material_overlay != null:
			count += 1
	return count


func test_ac21_a_move_inside_the_threshold_is_no_drag_and_beyond_it_is() -> void:
	if not await _open(_pair()):
		return
	var start: Vector2 = _s.screen_of_item(FIRST)
	_s.press(start)
	_s.move(start + Vector2(_threshold() * 0.5, 0.0))
	assert_bool(_s.dragging()).is_false()
	assert_bool(_s.ghost_shown()).is_false()
	_s.move(start + Vector2(_threshold() + 2.0, 0.0))
	assert_bool(_s.dragging()).is_true()
	assert_bool(_s.ghost_shown()).is_true()


func test_ac21_the_preview_follows_the_ground_point_and_the_model_stays() -> void:
	if not await _open(_pair()):
		return
	var state_before: Dictionary = ModelState.snapshot(_s.model)
	var start_node: Node3D = _s.node_for(FIRST)
	var start_transform: Transform3D = start_node.global_transform
	var model_events: Recorder = Recorder.new()
	model_events.watch(_s.model)
	var target: Vector2 = _s.screen_of(0.05, -0.08)
	_start_drag(target)
	assert_bool(_s.dragging()).is_true()
	assert_vector(_s.local_position(_s.ghost)).is_equal_approx(
		_s.ground_local(target), Vector3(TOLERANCE, TOLERANCE, TOLERANCE)
	)
	assert_float(_yaw_gap(_s.yaw_of(_s.ghost), 0.0)).is_less(ANGLE_TOLERANCE)
	assert_dict(ModelState.snapshot(_s.model)).is_equal(state_before)
	assert_int(_s.history.get_undo_count()).is_equal(0)
	assert_int(model_events.count()).is_equal(0)
	assert_object(_s.node_for(FIRST)).is_same(start_node)
	assert_bool(start_node.global_transform.is_equal_approx(start_transform)).is_true()
	assert_bool(start_node.is_visible_in_tree()).is_true()


func test_ac21_the_preview_carries_no_mark_and_the_start_keeps_its_mark_when_selected() -> void:
	if not await _open(_pair()):
		return
	_s.click(_s.screen_of_item(FIRST))
	assert_str(_s.selected_uid()).is_equal(FIRST)
	_start_drag(_s.screen_of(0.0, -0.08))
	assert_bool(_s.dragging()).is_true()
	assert_int(_marked(FIRST)).is_greater(0)
	for found: Node in _s.ghost.find_children("*", "GeometryInstance3D", true, false):
		assert_object((found as GeometryInstance3D).material_overlay).is_null()


func test_ac22_rotate_keys_turn_the_preview_and_start_no_hold() -> void:
	if not await _open(_pair()):
		return
	var state_before: Dictionary = ModelState.snapshot(_s.model)
	_start_drag(_s.screen_of(0.0, -0.08))
	_s.tap(KEY_COMMA)
	assert_float(_yaw_gap(_s.yaw_of(_s.ghost), 15.0)).is_less(ANGLE_TOLERANCE)
	_s.tap(KEY_COMMA)
	assert_float(_yaw_gap(_s.yaw_of(_s.ghost), 30.0)).is_less(ANGLE_TOLERANCE)
	_s.tap(KEY_PERIOD)
	assert_float(_yaw_gap(_s.yaw_of(_s.ghost), 15.0)).is_less(ANGLE_TOLERANCE)
	assert_bool(_s.holding()).is_false()
	assert_dict(ModelState.snapshot(_s.model)).is_equal(state_before)
	assert_int(_s.history.get_undo_count()).is_equal(0)


func test_ac23_a_drop_commits_one_move_with_the_previewed_rotation() -> void:
	if not await _open(_pair()):
		return
	var start: PlacedItem = _s.model.get_item(FIRST).copy()
	var target: Vector2 = _s.screen_of(0.05, -0.08)
	_start_drag(target)
	_s.tap(KEY_COMMA)
	_s.tap(KEY_COMMA)
	var model_events: Recorder = Recorder.new()
	model_events.watch(_s.model)
	_s.release(target)
	await _s.frame()
	var item: PlacedItem = _s.model.get_item(FIRST)
	var wanted: Vector3 = _s.ground_local(target)
	assert_float(item.position.x).is_equal_approx(wanted.x, TOLERANCE)
	assert_float(item.position.z).is_equal_approx(wanted.z, TOLERANCE)
	assert_float(item.position.y).is_equal(0.0)
	assert_float(item.rotation_y).is_equal_approx(30.0, 0.001)
	assert_that(item.catalog_id).is_equal(Rig.STONE)
	assert_array(model_events.names()).is_equal(["item_changed"])
	assert_int(_s.history.get_undo_count()).is_equal(1)
	assert_bool(_s.dragging()).is_false()
	assert_bool(_s.ghost_shown()).is_false()
	assert_bool(_s.history.undo()).is_true()
	var undone: PlacedItem = _s.model.get_item(FIRST)
	assert_vector(undone.position).is_equal(start.position)
	assert_float(undone.rotation_y).is_equal(start.rotation_y)
	assert_bool(_s.history.redo()).is_true()
	assert_float(_s.model.get_item(FIRST).rotation_y).is_equal_approx(30.0, 0.001)


func test_ac23_the_dropped_item_is_drawn_at_its_new_place_and_selected() -> void:
	if not await _open(_pair()):
		return
	var target: Vector2 = _s.screen_of(0.05, -0.08)
	_start_drag(target)
	_s.release(target)
	await _s.frame()
	assert_str(_s.selected_uid()).is_equal(FIRST)
	assert_array(_s.selection_timeline).is_equal(["selected:%s" % FIRST])
	var wanted: Vector3 = _s.ground_local(target)
	assert_vector(_s.local_position(_s.node_for(FIRST))).is_equal_approx(
		wanted, Vector3(TOLERANCE, TOLERANCE, TOLERANCE)
	)


func test_ac24_a_drag_that_ends_where_it_started_runs_no_command_and_selects() -> void:
	if not await _open(_pair()):
		return
	var home: Vector2 = _s.screen_of(-0.15, 0.0)
	_start_drag(home + Vector2(120.0, 40.0))
	assert_bool(_s.dragging()).is_true()
	_s.move(home)
	_s.release(home)
	await _s.frame()
	assert_int(_s.history.get_undo_count()).is_equal(0)
	assert_bool(_s.dragging()).is_false()
	assert_str(_s.selected_uid()).is_equal(FIRST)
	assert_array(_s.selection_timeline).is_equal(["selected:%s" % FIRST])


func test_ac25_esc_cancels_the_drag_and_keeps_an_earlier_selection() -> void:
	if not await _open(_pair()):
		return
	_s.click(_s.screen_of_item(FIRST))
	var state_before: Dictionary = ModelState.snapshot(_s.model)
	_start_drag(_s.screen_of(0.0, -0.08))
	assert_bool(_s.dragging()).is_true()
	_s.esc()
	_cancelled(state_before)
	assert_str(_s.selected_uid()).is_equal(FIRST)
	assert_array(_s.selection_timeline).is_equal(["selected:%s" % FIRST])
	assert_bool(_s.node_for(FIRST).is_visible_in_tree()).is_true()


func test_ac25_esc_cancels_the_drag_and_leaves_nothing_selected_when_nothing_was() -> void:
	if not await _open(_pair()):
		return
	var state_before: Dictionary = ModelState.snapshot(_s.model)
	_start_drag(_s.screen_of(0.0, -0.08))
	_s.esc()
	_cancelled(state_before)
	assert_str(_s.selected_uid()).is_equal("")
	assert_array(_s.selection_timeline).is_empty()
	_s.release(_s.screen_of(0.0, -0.08))
	assert_int(_s.history.get_undo_count()).is_equal(0)


func test_ac25_a_release_outside_the_tank_cancels() -> void:
	if not await _open(_pair()):
		return
	var state_before: Dictionary = ModelState.snapshot(_s.model)
	_start_drag(_s.screen_of(0.0, -0.08))
	_s.move(Session.OUTSIDE)
	_s.release(Session.OUTSIDE)
	_cancelled(state_before)
	assert_array(_s.selection_timeline).is_empty()


func test_ac25_a_release_over_a_panel_counts_as_outside_and_cancels() -> void:
	if not await _open(_pair()):
		return
	var state_before: Dictionary = ModelState.snapshot(_s.model)
	var inside: Vector2 = _s.screen_of(0.0, -0.08)
	_start_drag(inside)
	_s.make_panel(Rect2(inside - Vector2(50.0, 50.0), Vector2(100.0, 100.0)))
	_s.move(inside + Vector2(1.0, 0.0))
	_s.release(inside + Vector2(1.0, 0.0))
	_cancelled(state_before)


func test_ac26_a_drag_keeps_running_over_a_panel_and_a_later_valid_release_commits() -> void:
	if not await _open(_pair()):
		return
	var over: Vector2 = _s.screen_of(0.0, 0.0)
	_start_drag(_s.screen_of(0.0, -0.08))
	var panel: Control = _s.make_panel(Rect2(over - Vector2(40.0, 40.0), Vector2(80.0, 80.0)))
	_s.move(over)
	assert_bool(_s.dragging()).is_true()
	panel.queue_free()
	await _s.frame()
	var target: Vector2 = _s.screen_of(0.1, -0.1)
	_s.move(target)
	_s.release(target)
	assert_int(_s.history.get_undo_count()).is_equal(1)
	assert_float(_s.model.get_item(FIRST).position.x).is_equal_approx(0.1, 0.001)


func test_ac26_a_press_that_starts_on_a_panel_starts_no_selection_and_no_drag() -> void:
	if not await _open(_pair()):
		return
	var at: Vector2 = _s.screen_of_item(FIRST)
	_s.make_panel(Rect2(at - Vector2(40.0, 40.0), Vector2(80.0, 80.0)))
	_s.press(at)
	_s.move(at + Vector2(100.0, 0.0))
	assert_bool(_s.dragging()).is_false()
	_s.release(at + Vector2(100.0, 0.0))
	assert_str(_s.selected_uid()).is_equal("")
	assert_int(_s.history.get_undo_count()).is_equal(0)
	assert_array(_s.selection_timeline).is_empty()


func test_ac26_a_press_on_a_panel_with_a_pick_places_nothing() -> void:
	if not await _open(_pair()):
		return
	_s.pick(Rig.AMPHORA)
	var at: Vector2 = _s.screen_of(0.0, 0.0)
	_s.make_panel(Rect2(at - Vector2(40.0, 40.0), Vector2(80.0, 80.0)))
	_s.click(at)
	assert_int(_s.model.get_item_count()).is_equal(2)


func test_ac25_a_modal_dialog_mid_drag_cancels_it() -> void:
	if not await _open(_pair()):
		return
	var state_before: Dictionary = ModelState.snapshot(_s.model)
	var target: Vector2 = _s.screen_of(0.0, -0.08)
	_start_drag(target)
	var blocker: Control = _s.make_blocker()
	_s.set_blocked(blocker, true)
	_s.set_blocked(blocker, false)
	_s.release(target)
	_cancelled(state_before)


func test_ac25_losing_the_window_focus_mid_drag_cancels_it() -> void:
	if not await _open(_pair()):
		return
	var state_before: Dictionary = ModelState.snapshot(_s.model)
	var target: Vector2 = _s.screen_of(0.0, -0.08)
	_start_drag(target)
	_s.focus_out()
	_s.release(target)
	_cancelled(state_before)


func test_ac25_a_model_reset_mid_drag_cancels_it() -> void:
	if not await _open(_pair()):
		return
	var target: Vector2 = _s.screen_of(0.0, -0.08)
	_start_drag(target)
	var other: AquariumModel = Rig.model()
	Rig.add_item(other, "b0000001", Rig.AMPHORA, 0.0, 0.0)
	_s.model.reset_from(other)
	_s.step(0.0)
	assert_bool(_s.dragging()).is_false()
	assert_bool(_s.ghost_shown()).is_false()
	_s.release(target)
	assert_int(_s.history.get_undo_count()).is_equal(0)


func test_ac25_removing_the_dragged_item_mid_drag_cancels_it() -> void:
	if not await _open(_pair()):
		return
	var target: Vector2 = _s.screen_of(0.0, -0.08)
	_start_drag(target)
	_s.model.apply_remove_item(FIRST)
	_s.step(0.0)
	assert_bool(_s.dragging()).is_false()
	assert_bool(_s.ghost_shown()).is_false()
	_s.release(target)
	assert_int(_s.history.get_undo_count()).is_equal(0)
	assert_object(_s.model.get_item(FIRST)).is_null()


func test_ac25_replacing_the_dragged_item_mid_drag_cancels_it() -> void:
	if not await _open(_pair()):
		return
	var target: Vector2 = _s.screen_of(0.0, -0.08)
	_start_drag(target)
	var changed: PlacedItem = _s.model.get_item(FIRST).copy()
	changed.rotation_y = 120.0
	_s.model.apply_replace_item(changed)
	_s.step(0.0)
	assert_bool(_s.dragging()).is_false()
	assert_bool(_s.ghost_shown()).is_false()
	_s.release(target)
	assert_int(_s.history.get_undo_count()).is_equal(0)
	assert_float(_s.model.get_item(FIRST).rotation_y).is_equal(120.0)


func test_ac36_a_committed_drop_replaces_a_different_selection() -> void:
	if not await _open(_pair()):
		return
	_s.click(_s.screen_of_item(SECOND))
	assert_str(_s.selected_uid()).is_equal(SECOND)
	var target: Vector2 = _s.screen_of(0.0, -0.1)
	_start_drag(target)
	_s.release(target)
	assert_str(_s.selected_uid()).is_equal(FIRST)
	assert_array(_s.selection_timeline).is_equal(["selected:%s" % SECOND, "selected:%s" % FIRST])


func test_ac36_a_cancelled_drag_leaves_a_different_selection_as_it_was() -> void:
	if not await _open(_pair()):
		return
	_s.click(_s.screen_of_item(SECOND))
	_start_drag(_s.screen_of(0.0, -0.1))
	_s.esc()
	assert_str(_s.selected_uid()).is_equal(SECOND)
	assert_array(_s.selection_timeline).is_equal(["selected:%s" % SECOND])


func test_ac40_a_drop_over_a_tall_item_lands_on_the_bed_where_the_ghost_stood() -> void:
	var model: AquariumModel = Rig.model()
	Rig.add_item(model, FIRST, Rig.STONE, -0.2, 0.0)
	Rig.add_item(model, SECOND, Rig.TALL, 0.0, 0.10)
	if not await _open(model, 30.0):
		return
	var over_post: Vector2 = _s.screen_of(0.0, 0.10, 0.10)
	_start_drag(over_post)
	var ghost_at: Vector3 = _s.local_position(_s.ghost)
	_s.release(over_post)
	var item: PlacedItem = _s.model.get_item(FIRST)
	assert_float(item.position.x).is_equal_approx(ghost_at.x, 0.001)
	assert_float(item.position.z).is_equal_approx(ghost_at.z, 0.001)
	assert_float(item.position.z).is_less(0.05)
	assert_float(item.position.y).is_equal(0.0)
