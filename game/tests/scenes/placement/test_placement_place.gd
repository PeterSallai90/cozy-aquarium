extends GdUnitTestSuite
## #31 AC 11, 13 to 16, 18 and 40 (click part) (owner: developer): placing with a click. With a
## pick and a ghost, a left click runs exactly one place command: one new PlacedItem with a fresh
## uid, the picked catalog_id, the ground-point position at y 0, the ghost rotation, scale 1.0 and
## no colour; one item_added, one history entry. Undo and redo restore state, uid and order. The
## pick and the ghost stay after a placement; Esc clears the pick through the EventBus request. A
## click without a valid ground point places nothing and logs nothing.
## Test decisions: a click is a left press followed by a left release at the same spot; the stub in
## the session plays the item browser; the engine log is checked with EngineOutput.capture_all.

const Rig := preload("res://tests/helpers/placement_rig.gd")
const Session := preload("res://tests/helpers/placement_session.gd")
const Recorder := preload("res://tests/helpers/signal_recorder.gd")
const ModelState := preload("res://tests/helpers/model_state.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")

const POSITION_TOLERANCE: float = 0.0001

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


func _uids() -> Array[String]:
	var uids: Array[String] = []
	for item: PlacedItem in _s.model.get_items():
		uids.append(item.uid)
	return uids


func test_ac13_one_click_places_one_item_at_the_ghost_with_the_picked_id() -> void:
	if not await _open():
		return
	var model_events: Recorder = Recorder.new()
	var history_events: Recorder = Recorder.new()
	_s.pick(Rig.STONE)
	var at: Vector2 = _s.screen_of(0.1234, -0.0567)
	_s.move(at)
	_s.tap(KEY_COMMA)
	_s.tap(KEY_COMMA)
	model_events.watch(_s.model)
	history_events.watch(_s.history)
	_s.click(at)
	await _s.frame()
	assert_int(_s.model.get_item_count()).is_equal(1)
	var item: PlacedItem = _s.model.get_item_at(0)
	assert_that(item.catalog_id).is_equal(Rig.STONE)
	assert_bool(item.uid.length() > 0 and _s.model.has_uid(item.uid)).is_true()
	var wanted: Vector3 = _s.ground_local(at)
	assert_float(item.position.x).is_equal_approx(wanted.x, POSITION_TOLERANCE)
	assert_float(item.position.z).is_equal_approx(wanted.z, POSITION_TOLERANCE)
	assert_float(item.position.y).is_equal(0.0)
	assert_float(item.rotation_y).is_equal_approx(30.0, 0.001)
	assert_float(item.scale).is_equal(1.0)
	assert_bool(item.has_colour).is_false()
	assert_array(model_events.names()).is_equal(["item_added"])
	assert_array(model_events.args_of(0)).is_equal([item.uid, 0])
	assert_int(_s.history.get_undo_count()).is_equal(1)
	var changes: int = 0
	for event_name: String in history_events.names():
		if event_name == "history_changed":
			changes += 1
	assert_int(changes).is_equal(1)
	assert_int(_s.drawn_count()).is_equal(1)


func test_ac11_two_items_may_stand_on_exactly_the_same_spot() -> void:
	if not await _open():
		return
	_s.pick(Rig.STONE)
	var at: Vector2 = _s.screen_of(0.05, 0.05)
	_s.move(at)
	_s.click(at)
	_s.click(at)
	assert_int(_s.model.get_item_count()).is_equal(2)
	assert_vector(_s.model.get_item_at(0).position).is_equal(_s.model.get_item_at(1).position)
	assert_bool(_s.model.get_item_at(0).uid != _s.model.get_item_at(1).uid).is_true()


func test_ac14_undo_returns_the_model_to_the_state_before_the_click_and_redo_restores_it() -> void:
	if not await _open():
		return
	_s.pick(Rig.STONE)
	var at: Vector2 = _s.screen_of(-0.1, 0.0)
	_s.move(at)
	var state_before: Dictionary = ModelState.snapshot(_s.model)
	_s.click(at)
	var state_after: Dictionary = ModelState.snapshot(_s.model)
	var uid: String = _s.model.get_item_at(0).uid
	assert_bool(_s.history.undo()).is_true()
	assert_dict(ModelState.snapshot(_s.model)).is_equal(state_before)
	await _s.frame()
	await _s.frame()
	assert_int(_s.drawn_count()).is_equal(0)
	assert_bool(_s.history.redo()).is_true()
	assert_dict(ModelState.snapshot(_s.model)).is_equal(state_after)
	assert_str(_s.model.get_item_at(0).uid).is_equal(uid)
	await _s.frame()
	assert_int(_s.drawn_count()).is_equal(1)


func test_ac14_several_placements_come_back_in_the_same_order() -> void:
	if not await _open():
		return
	_s.pick(Rig.STONE)
	for x: float in [-0.2, 0.0, 0.2]:
		var at: Vector2 = _s.screen_of(x, 0.0)
		_s.move(at)
		_s.click(at)
	var order: Array[String] = _uids()
	assert_int(order.size()).is_equal(3)
	assert_int(_s.history.get_undo_count()).is_equal(3)
	for step: int in 3:
		assert_bool(_s.history.undo()).is_true()
	assert_int(_s.model.get_item_count()).is_equal(0)
	for step: int in 3:
		assert_bool(_s.history.redo()).is_true()
	assert_array(_uids()).is_equal(order)
	assert_bool(_s.history.undo()).is_true()
	assert_bool(_s.history.redo()).is_true()
	assert_array(_uids()).is_equal(order)


func test_ac15_the_pick_and_the_ghost_stay_after_a_placement_and_the_rotation_stays() -> void:
	if not await _open():
		return
	_s.pick(Rig.BRANCH)
	var at: Vector2 = _s.screen_of(0.1, 0.0)
	_s.move(at)
	_s.tap(KEY_COMMA)
	_s.tap(KEY_COMMA)
	_s.click(at)
	assert_str(_s.picked_id()).is_equal(String(Rig.BRANCH))
	assert_bool(_s.ghost_shown()).is_true()
	assert_float(_s.ghost_rotation()).is_equal_approx(30.0, 0.001)
	assert_int(_s.clear_requests).is_equal(0)
	var next: Vector2 = _s.screen_of(-0.1, 0.0)
	_s.move(next)
	_s.click(next)
	assert_int(_s.model.get_item_count()).is_equal(2)
	assert_float(_s.model.get_item_at(1).rotation_y).is_equal_approx(30.0, 0.001)
	assert_bool(_s.model.get_item_at(0).uid != _s.model.get_item_at(1).uid).is_true()


func test_ac15_esc_clears_the_pick_through_the_request_and_removes_the_ghost() -> void:
	if not await _open():
		return
	_s.pick(Rig.STONE)
	_s.move(_s.screen_of(0.0, 0.0))
	assert_bool(_s.ghost_shown()).is_true()
	_s.esc()
	assert_int(_s.clear_requests).is_equal(1)
	assert_bool(_s.ghost_shown()).is_false()
	assert_str(_s.picked_id()).is_equal("")
	assert_int(_s.history.get_undo_count()).is_equal(0)
	assert_int(_s.model.get_item_count()).is_equal(0)


func test_ac15_after_the_pick_is_cleared_a_click_places_nothing() -> void:
	if not await _open():
		return
	_s.pick(Rig.STONE)
	var at: Vector2 = _s.screen_of(0.0, 0.0)
	_s.move(at)
	_s.esc()
	_s.click(at)
	assert_int(_s.model.get_item_count()).is_equal(0)
	assert_str(_s.selected_uid()).is_equal("")


func test_ac16_a_click_without_a_valid_ground_point_places_nothing_and_logs_nothing() -> void:
	if not await _open():
		return
	_s.pick(Rig.STONE)
	var centre: Vector2 = _s.screen_of(0.0, 0.0)
	_s.make_panel(Rect2(centre - Vector2(40.0, 40.0), Vector2(80.0, 80.0)))
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void:
			_s.click(Session.OUTSIDE)
			_s.click(_s.screen_of(0.35, 0.0))
			_s.click(centre)
			await _s.frame()
	)
	assert_dict(seen["errors"]).is_empty()
	assert_dict(seen["warnings"]).is_empty()
	assert_dict(seen["script_errors"]).is_empty()
	assert_int(_s.model.get_item_count()).is_equal(0)
	assert_int(_s.history.get_undo_count()).is_equal(0)
	assert_str(_s.picked_id()).is_equal(String(Rig.STONE))


func test_ac18_a_model_reset_removes_the_ghost_and_runs_no_command() -> void:
	if not await _open():
		return
	_s.pick(Rig.STONE)
	_s.move(_s.screen_of(0.0, 0.0))
	assert_bool(_s.ghost_shown()).is_true()
	var other: AquariumModel = Rig.model()
	Rig.add_item(other, "b0000001", Rig.AMPHORA, 0.1, 0.0)
	_s.model.reset_from(other)
	_s.step(0.0)
	assert_bool(_s.ghost_shown()).is_false()
	assert_int(_s.history.get_undo_count()).is_equal(0)
	assert_int(_s.model.get_item_count()).is_equal(1)


func test_ac18_losing_the_window_focus_removes_the_ghost_and_runs_no_command() -> void:
	if not await _open():
		return
	_s.pick(Rig.STONE)
	_s.move(_s.screen_of(0.0, 0.0))
	assert_bool(_s.ghost_shown()).is_true()
	_s.focus_out()
	assert_bool(_s.ghost_shown()).is_false()
	assert_int(_s.history.get_undo_count()).is_equal(0)
	assert_int(_s.model.get_item_count()).is_equal(0)


func test_ac40_a_click_over_a_tall_item_places_at_the_ghost_on_the_bed_and_selects_nothing(
) -> void:
	var model: AquariumModel = Rig.model()
	Rig.add_item(model, "a0000001", Rig.TALL, 0.0, 0.10)
	if not await _open(model, 30.0):
		return
	_s.pick(Rig.STONE)
	var at: Vector2 = _s.screen_of(0.0, 0.10, 0.10)
	_s.move(at)
	var ghost_at: Vector3 = _s.local_position(_s.ghost)
	_s.click(at)
	assert_int(_s.model.get_item_count()).is_equal(2)
	var placed: PlacedItem = _s.model.get_item_at(1)
	assert_float(placed.position.x).is_equal_approx(ghost_at.x, POSITION_TOLERANCE * 5.0)
	assert_float(placed.position.z).is_equal_approx(ghost_at.z, POSITION_TOLERANCE * 5.0)
	assert_float(placed.position.z).is_less(0.05)
	assert_float(placed.position.y).is_equal(0.0)
	assert_str(_s.selected_uid()).is_equal("")
	assert_array(_s.selection_timeline).is_empty()
