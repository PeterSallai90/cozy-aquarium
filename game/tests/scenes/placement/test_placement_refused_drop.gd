# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #33 AC 13 (file group: developer, scene; owner decision 2026-11-21 "refused moves also cue"): a
## drag released over a spot the rules refuse is cancelled as before (no command, no history entry,
## the item where it was) and now plays the refusal cue once on the dragged item, also when it is
## not selected, and then it does not select it (the selection stays as before the press, #31 AC 25
## and 36). One refused release is one cue; a second one restarts it.
## No cue (plain cancellations, no ground point, clicks and valid moves): a release with no ground
## point (outside the tank, over a panel), Esc, a focus loss, a modal dialog (photo mode blocking),
## model_reset, a removed item, a drop at the same spot (a click: it selects, also for an item that
## is already invalid), a valid drop, and a click with a pick on an invalid spot (the ghost). There
## is no right-click test: placement does not handle the right button (the camera does).
## Fixtures (medium tank): stone FIRST at (-0.15, 0), stone SECOND at (0.05, 0); a drop of FIRST at
## (0.07, 0) overlaps SECOND, a drop at x 0.29 goes through the glass, a drop at (-0.2, 0.08) is
## valid. The cue state and the overlay of the dragged node are read from the view.

const Rig := preload("res://tests/helpers/placement_rig.gd")
const Session := preload("res://tests/helpers/placement_session.gd")
const Api := preload("res://tests/helpers/placement_api.gd")
const Recorder := preload("res://tests/helpers/signal_recorder.gd")
const ModelState := preload("res://tests/helpers/model_state.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")

const FIRST := "a0000001"
const SECOND := "a0000002"
const SELECTION_MATERIAL := "res://scenes/tank/items/item_selection_material.tres"
const BASE: float = 0.7
const TOLERANCE: float = 0.0001

var _s: Session = null
var _events: Recorder = null


func after_test() -> void:
	Rig.close(_s)


func _open(model: AquariumModel) -> bool:
	_s = await Rig.open(self, model)
	var complete: bool = _s.placement != null and _s.view != null and _s.ghost != null
	(
		assert_bool(complete)
		. override_failure_message(
			"RoomCorner needs a Placement child with the children PlacedItems and Ghost"
		)
		. is_true()
	)
	if complete:
		_events = Recorder.new()
		_events.watch(_s.model)
	return complete


func _pair() -> AquariumModel:
	var model: AquariumModel = Rig.model()
	Rig.add_item(model, FIRST, Rig.STONE, -0.15, 0.0)
	Rig.add_item(model, SECOND, Rig.STONE, 0.05, 0.0)
	return model


func _drag_first_to(target: Vector2) -> void:
	_s.press(_s.screen_of_item(FIRST))
	_s.move(target)


## Presses on FIRST, drags to `target` and releases there.
func _drop_first_at(target: Vector2) -> void:
	_drag_first_to(target)
	_s.release(target)


func _overlays(uid: String) -> Array[Material]:
	var found: Array[Material] = []
	var node: Node3D = _s.node_for(uid)
	if node == null:
		return found
	for child: Node in node.find_children("*", "GeometryInstance3D", true, false):
		var overlay: Material = (child as GeometryInstance3D).material_overlay
		if overlay != null:
			found.append(overlay)
	return found


func _assert_no_overlay(uid: String) -> void:
	assert_int(_overlays(uid).size()).is_equal(0)


func _assert_refused_and_unmoved(state_before: Dictionary) -> void:
	assert_dict(ModelState.snapshot(_s.model)).is_equal(state_before)
	assert_int(_s.history.get_undo_count()).is_equal(0)
	assert_bool(_s.dragging()).is_false()
	assert_bool(_s.ghost_shown()).is_false()


func _assert_no_cue() -> void:
	assert_int(_s.cue_count()).is_equal(0)
	assert_bool(_s.cue_active()).is_false()


# --- the refused drop plays one cue ---


func test_ac13_a_drop_on_an_overlap_cancels_and_plays_one_cue_on_the_dragged_item() -> void:
	if not await _open(_pair()):
		return
	var state_before: Dictionary = ModelState.snapshot(_s.model)
	var drawn_before: Vector3 = _s.local_position(_s.node_for(FIRST))
	_drop_first_at(_s.screen_of(0.07, 0.0))
	_assert_refused_and_unmoved(state_before)
	assert_vector(_s.local_position(_s.node_for(FIRST))).is_equal_approx(
		drawn_before, Vector3(0.0005, 0.0005, 0.0005)
	)
	assert_int(_s.cue_count()).is_equal(1)
	assert_bool(_s.cue_active()).is_true()
	assert_str(_s.cue_uid()).is_equal(FIRST)
	assert_int(_events.count()).is_equal(0)


func test_ac13_a_drop_through_the_glass_plays_one_cue() -> void:
	if not await _open(_pair()):
		return
	var state_before: Dictionary = ModelState.snapshot(_s.model)
	_drop_first_at(_s.screen_of(0.29, 0.0))
	_assert_refused_and_unmoved(state_before)
	assert_int(_s.cue_count()).is_equal(1)
	assert_str(_s.cue_uid()).is_equal(FIRST)


func test_ac13_the_previewed_rotation_is_judged_for_the_cue() -> void:
	if not await _open(_pair()):
		return
	# The unturned stone at x -0.24 reaches -0.295 and fits; turned by 45 degrees (3 taps) it reaches
	# -0.307 and goes through the glass.
	var target: Vector2 = _s.screen_of(-0.24, 0.0)
	_drag_first_to(target)
	assert_bool(_s.ghost_shown()).is_true()
	for tap_index: int in 3:
		_s.tap(KEY_COMMA)
	assert_bool(_s.ghost_shown()).is_false()
	_s.release(target)
	assert_int(_s.cue_count()).is_equal(1)
	assert_int(_s.history.get_undo_count()).is_equal(0)


func test_ac13_the_cue_runs_the_curve_and_ends_after_the_duration() -> void:
	if not await _open(_pair()):
		return
	var peak: float = Api.tuning("REFUSAL_CUE_PEAK_STRENGTH")
	_drop_first_at(_s.screen_of(0.07, 0.0))
	assert_float(_s.cue_strength()).is_equal_approx(BASE, TOLERANCE)
	_s.step(0.15)
	assert_float(_s.cue_strength()).is_equal_approx(peak, TOLERANCE)
	_s.step(0.4)
	assert_bool(_s.cue_active()).is_false()
	assert_float(_s.cue_strength()).is_equal_approx(BASE, TOLERANCE)
	assert_int(_s.cue_count()).is_equal(1)


# --- unselected and selected dragged items ---


func test_ac13_an_unselected_dragged_item_gets_the_cue_and_is_not_selected() -> void:
	if not await _open(_pair()):
		return
	_assert_no_overlay(FIRST)
	_drop_first_at(_s.screen_of(0.07, 0.0))
	assert_str(_s.selected_uid()).is_equal("")
	assert_array(_s.selection_timeline).is_empty()
	assert_int(_s.cue_count()).is_equal(1)
	# The runtime copy of the cue material is the overlay while the cue runs, and nothing after.
	var overlays: Array[Material] = _overlays(FIRST)
	assert_int(overlays.size()).is_greater(0)
	for overlay: Material in overlays:
		assert_str(overlay.resource_path).is_not_equal(SELECTION_MATERIAL)
	_s.step(0.5)
	assert_bool(_s.cue_active()).is_false()
	_assert_no_overlay(FIRST)
	assert_str(_s.selected_uid()).is_equal("")


func test_ac13_with_another_item_selected_the_selection_stays_and_the_cue_plays_on_the_dragged_one(
) -> void:
	if not await _open(_pair()):
		return
	_s.click(_s.screen_of_item(SECOND))
	assert_str(_s.selected_uid()).is_equal(SECOND)
	_drop_first_at(_s.screen_of(0.07, 0.0))
	assert_str(_s.selected_uid()).is_equal(SECOND)
	assert_array(_s.selection_timeline).is_equal(["selected:%s" % SECOND])
	assert_str(_s.cue_uid()).is_equal(FIRST)
	assert_int(_s.cue_count()).is_equal(1)
	assert_int(_overlays(SECOND).size()).is_greater(0)
	for overlay: Material in _overlays(SECOND):
		assert_str(overlay.resource_path).is_equal(SELECTION_MATERIAL)
	_s.step(0.5)
	assert_str(_s.selected_uid()).is_equal(SECOND)
	assert_int(_overlays(SECOND).size()).is_greater(0)


func test_ac13_a_selected_dragged_item_keeps_its_selection_and_gets_the_cue_on_the_mark() -> void:
	if not await _open(_pair()):
		return
	_s.click(_s.screen_of_item(FIRST))
	assert_str(_s.selected_uid()).is_equal(FIRST)
	_drop_first_at(_s.screen_of(0.07, 0.0))
	assert_str(_s.selected_uid()).is_equal(FIRST)
	assert_int(_s.cue_count()).is_equal(1)
	assert_str(_s.cue_uid()).is_equal(FIRST)
	assert_int(_s.history.get_undo_count()).is_equal(0)
	_s.step(0.5)
	assert_bool(_s.cue_active()).is_false()
	for overlay: Material in _overlays(FIRST):
		assert_str(overlay.resource_path).is_equal(SELECTION_MATERIAL)
	assert_str(_s.selected_uid()).is_equal(FIRST)


func test_ac13_two_refused_drops_in_a_row_count_two_and_restart_the_cue() -> void:
	if not await _open(_pair()):
		return
	var peak: float = Api.tuning("REFUSAL_CUE_PEAK_STRENGTH")
	_drop_first_at(_s.screen_of(0.07, 0.0))
	_s.step(0.15)
	assert_float(_s.cue_strength()).is_equal_approx(peak, TOLERANCE)
	_drop_first_at(_s.screen_of(0.07, 0.0))
	assert_int(_s.cue_count()).is_equal(2)
	assert_float(_s.cue_strength()).is_equal_approx(BASE, TOLERANCE)
	assert_bool(_s.cue_active()).is_true()
	_s.step(0.5)
	assert_bool(_s.cue_active()).is_false()
	assert_int(_s.cue_count()).is_equal(2)


func test_ac13_an_already_invalid_item_dropped_on_a_refused_spot_cues_too() -> void:
	var model: AquariumModel = Rig.model()
	# 28 cm long from x 0.13 to 0.41: through the glass already; SECOND is a free stone.
	Rig.add_item(model, FIRST, Rig.BRANCH, 0.27, 0.0)
	Rig.add_item(model, SECOND, Rig.STONE, -0.2, 0.0)
	if not await _open(model):
		return
	var state_before: Dictionary = ModelState.snapshot(_s.model)
	var target: Vector2 = _s.screen_of(0.2, 0.0)
	_drag_first_to(target)
	_s.release(target)
	assert_dict(ModelState.snapshot(_s.model)).is_equal(state_before)
	assert_int(_s.cue_count()).is_equal(1)
	assert_int(_s.history.get_undo_count()).is_equal(0)


# --- no cue ---


func test_ac13_a_release_outside_the_tank_is_a_plain_cancellation() -> void:
	if not await _open(_pair()):
		return
	var state_before: Dictionary = ModelState.snapshot(_s.model)
	_drag_first_to(_s.screen_of(0.0, 0.0))
	_s.move(Session.OUTSIDE)
	_s.release(Session.OUTSIDE)
	_assert_refused_and_unmoved(state_before)
	_assert_no_cue()


func test_ac13_a_release_over_a_panel_is_a_plain_cancellation() -> void:
	if not await _open(_pair()):
		return
	var state_before: Dictionary = ModelState.snapshot(_s.model)
	var target: Vector2 = _s.screen_of(0.07, 0.0)
	_drag_first_to(target)
	_s.make_panel(Rect2(target - Vector2(50.0, 50.0), Vector2(100.0, 100.0)))
	_s.move(target + Vector2(1.0, 0.0))
	_s.release(target + Vector2(1.0, 0.0))
	_assert_refused_and_unmoved(state_before)
	_assert_no_cue()


func test_ac13_esc_during_the_drag_is_a_plain_cancellation() -> void:
	if not await _open(_pair()):
		return
	var state_before: Dictionary = ModelState.snapshot(_s.model)
	var target: Vector2 = _s.screen_of(0.07, 0.0)
	_drag_first_to(target)
	_s.esc()
	_s.release(target)
	_assert_refused_and_unmoved(state_before)
	_assert_no_cue()


func test_ac13_losing_the_window_focus_is_a_plain_cancellation() -> void:
	if not await _open(_pair()):
		return
	var state_before: Dictionary = ModelState.snapshot(_s.model)
	var target: Vector2 = _s.screen_of(0.07, 0.0)
	_drag_first_to(target)
	_s.focus_out()
	_s.release(target)
	_assert_refused_and_unmoved(state_before)
	_assert_no_cue()


func test_ac13_a_modal_dialog_or_photo_mode_is_a_plain_cancellation() -> void:
	if not await _open(_pair()):
		return
	var state_before: Dictionary = ModelState.snapshot(_s.model)
	var target: Vector2 = _s.screen_of(0.07, 0.0)
	_drag_first_to(target)
	var blocker: Control = _s.make_blocker()
	_s.set_blocked(blocker, true)
	_s.set_blocked(blocker, false)
	_s.release(target)
	_assert_refused_and_unmoved(state_before)
	_assert_no_cue()


func test_ac13_a_model_reset_during_the_drag_is_a_plain_cancellation() -> void:
	if not await _open(_pair()):
		return
	var target: Vector2 = _s.screen_of(0.07, 0.0)
	_drag_first_to(target)
	var other: AquariumModel = Rig.model()
	Rig.add_item(other, FIRST, Rig.STONE, -0.15, 0.0)
	Rig.add_item(other, SECOND, Rig.STONE, 0.05, 0.0)
	_s.model.reset_from(other)
	_s.step(0.0)
	_s.release(target)
	assert_int(_s.history.get_undo_count()).is_equal(0)
	_assert_no_cue()


func test_ac13_a_removed_dragged_item_is_a_plain_cancellation() -> void:
	if not await _open(_pair()):
		return
	var target: Vector2 = _s.screen_of(0.07, 0.0)
	_drag_first_to(target)
	_s.model.apply_remove_item(FIRST)
	_s.step(0.0)
	_s.release(target)
	assert_int(_s.history.get_undo_count()).is_equal(0)
	_assert_no_cue()


func test_ac13_a_drop_at_the_same_spot_is_a_click_that_selects_with_no_cue() -> void:
	if not await _open(_pair()):
		return
	var home: Vector2 = _s.screen_of(-0.15, 0.0)
	_drag_first_to(home + Vector2(120.0, 40.0))
	assert_bool(_s.dragging()).is_true()
	_s.move(home)
	_s.release(home)
	assert_int(_s.history.get_undo_count()).is_equal(0)
	assert_str(_s.selected_uid()).is_equal(FIRST)
	_assert_no_cue()


func test_ac13_a_same_spot_drop_of_an_already_invalid_item_selects_it_with_no_cue() -> void:
	var model: AquariumModel = Rig.model()
	Rig.add_item(model, FIRST, Rig.BRANCH, 0.27, 0.0)
	if not await _open(model):
		return
	var home: Vector2 = _s.screen_of(0.27, 0.0)
	_s.press(_s.screen_of_item(FIRST))
	_s.move(home + Vector2(-120.0, 40.0))
	assert_bool(_s.dragging()).is_true()
	_s.move(home)
	_s.release(home)
	assert_int(_s.history.get_undo_count()).is_equal(0)
	assert_str(_s.selected_uid()).is_equal(FIRST)
	_assert_no_cue()


func test_ac13_a_valid_drop_commits_and_plays_no_cue() -> void:
	if not await _open(_pair()):
		return
	_drop_first_at(_s.screen_of(-0.2, 0.08))
	assert_int(_s.history.get_undo_count()).is_equal(1)
	assert_str(_s.selected_uid()).is_equal(FIRST)
	_assert_no_cue()
	_s.step(0.5)
	_assert_no_cue()


func test_ac13_a_click_with_a_pick_on_an_invalid_spot_plays_no_cue() -> void:
	if not await _open(_pair()):
		return
	_s.pick(Rig.STONE)
	var at: Vector2 = _s.screen_of(0.05, 0.0)
	_s.move(at)
	assert_bool(_s.ghost_shown()).is_false()
	_s.click(at)
	assert_int(_s.model.get_item_count()).is_equal(2)
	assert_int(_s.history.get_undo_count()).is_equal(0)
	_assert_no_cue()
	_s.click(_s.screen_of(0.29, 0.0))
	_assert_no_cue()


func test_ac13_the_cue_does_not_move_the_dragged_item_and_leaves_no_overlay_behind() -> void:
	if not await _open(_pair()):
		return
	var position_before: Vector3 = _s.local_position(_s.node_for(FIRST))
	_drop_first_at(_s.screen_of(0.07, 0.0))
	_s.step(0.1)
	assert_vector(_s.local_position(_s.node_for(FIRST))).is_equal_approx(
		position_before, Vector3(0.0005, 0.0005, 0.0005)
	)
	_s.step(1.0)
	_assert_no_overlay(FIRST)
	_assert_no_overlay(SECOND)


func test_ac13_a_refused_drop_logs_no_error_and_no_warning() -> void:
	if not await _open(_pair()):
		return
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void:
			_drop_first_at(_s.screen_of(0.07, 0.0))
			_s.step(0.2)
			_drop_first_at(_s.screen_of(0.29, 0.0))
			_s.step(0.5)
			await _s.frame()
	)
	assert_dict(seen["errors"]).is_empty()
	assert_dict(seen["warnings"]).is_empty()
	assert_dict(seen["script_errors"]).is_empty()
