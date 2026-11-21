extends GdUnitTestSuite
## #31 AC 19, 20, 34 and 35 (owner: developer): selecting placed items. Without a pick, a press and
## a release on a placed item (no movement beyond the drag threshold) selects it: the mark is drawn
## and EventBus.item_selected(uid) fires once; the model and history stay. The nearest item to the
## camera wins. A click on empty world or Esc clears it with one item_selection_cleared; switching
## from one item to another emits only item_selected(other); selecting the selected item emits
## nothing. A pick clears the selection first. item_changed keeps it; item_removed of the selected
## uid, model_reset and tank_displayed clear it; undo of the placement of the selected item
## clears it.
## Test decisions: the selection signals are read from the EventBus through the session timeline
## ("selected:<uid>" and "cleared"); the nearest-item case uses the low camera (8 degrees) so two
## stones stand behind each other on one ray.

const Rig := preload("res://tests/helpers/placement_rig.gd")
const Session := preload("res://tests/helpers/placement_session.gd")
const Api := preload("res://tests/helpers/placement_api.gd")
const ModelState := preload("res://tests/helpers/model_state.gd")
const Factory := preload("res://tests/helpers/factory.gd")

const FIRST := "a0000001"
const SECOND := "a0000002"

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


func _marked(uid: String) -> int:
	var node: Node3D = _s.node_for(uid)
	if node == null:
		return -1
	var count: int = 0
	for found: Node in node.find_children("*", "GeometryInstance3D", true, false):
		if (found as GeometryInstance3D).material_overlay != null:
			count += 1
	return count


func _select(uid: String) -> void:
	_s.click(_s.screen_of_item(uid))


func test_ac19_a_click_on_an_item_selects_it_with_one_signal_and_a_mark() -> void:
	if not await _open(_pair()):
		return
	var state_before: Dictionary = ModelState.snapshot(_s.model)
	_select(FIRST)
	assert_str(_s.selected_uid()).is_equal(FIRST)
	assert_array(_s.selection_timeline).is_equal(["selected:%s" % FIRST])
	assert_int(_marked(FIRST)).is_greater(0)
	assert_int(_marked(SECOND)).is_equal(0)
	assert_dict(ModelState.snapshot(_s.model)).is_equal(state_before)
	assert_int(_s.history.get_undo_count()).is_equal(0)


func test_ac19_a_small_movement_inside_the_drag_threshold_still_selects() -> void:
	if not await _open(_pair()):
		return
	var at: Vector2 = _s.screen_of_item(FIRST)
	var near: Vector2 = at + Vector2(Api.tuning("DRAG_THRESHOLD_PX") * 0.5, 0.0)
	_s.press(at)
	_s.move(near)
	assert_bool(_s.dragging()).is_false()
	_s.release(near)
	assert_str(_s.selected_uid()).is_equal(FIRST)
	assert_int(_s.history.get_undo_count()).is_equal(0)


func test_ac19_of_several_items_under_the_pointer_the_nearest_to_the_camera_is_selected() -> void:
	var model: AquariumModel = Rig.model()
	Rig.add_item(model, FIRST, Rig.STONE, 0.0, -0.08)
	Rig.add_item(model, SECOND, Rig.STONE, 0.0, 0.08)
	if not await _open(model, Rig.LOW_ELEVATION_DEG):
		return
	# The pointer aims low on the far stone: the ray passes the near stone on its way.
	_s.click(_s.screen_of(0.0, -0.08, 0.01))
	assert_str(_s.selected_uid()).is_equal(SECOND)


func test_ac19_the_ghost_and_the_mark_are_never_hit() -> void:
	if not await _open(_pair()):
		return
	_select(FIRST)
	assert_int(_s.ghost.find_children("*", "CollisionObject3D", true, false).size()).is_equal(0)
	_select(SECOND)
	assert_str(_s.selected_uid()).is_equal(SECOND)


func test_ac20_selecting_the_selected_item_again_emits_nothing() -> void:
	if not await _open(_pair()):
		return
	_select(FIRST)
	_select(FIRST)
	assert_array(_s.selection_timeline).is_equal(["selected:%s" % FIRST])
	assert_str(_s.selected_uid()).is_equal(FIRST)


func test_ac20_switching_to_another_item_emits_only_the_new_selection() -> void:
	if not await _open(_pair()):
		return
	_select(FIRST)
	_select(SECOND)
	assert_array(_s.selection_timeline).is_equal(["selected:%s" % FIRST, "selected:%s" % SECOND])
	assert_int(_marked(FIRST)).is_equal(0)
	assert_int(_marked(SECOND)).is_greater(0)


func test_ac20_a_click_on_empty_world_clears_the_selection_once() -> void:
	if not await _open(_pair()):
		return
	_select(FIRST)
	_s.click(_s.screen_of(0.0, -0.1))
	assert_str(_s.selected_uid()).is_equal("")
	assert_array(_s.selection_timeline).is_equal(["selected:%s" % FIRST, "cleared"])
	assert_int(_marked(FIRST)).is_equal(0)
	_s.click(Session.OUTSIDE)
	assert_array(_s.selection_timeline).is_equal(["selected:%s" % FIRST, "cleared"])


func test_ac20_a_click_outside_the_tank_clears_the_selection() -> void:
	if not await _open(_pair()):
		return
	_select(FIRST)
	_s.click(Session.OUTSIDE)
	assert_str(_s.selected_uid()).is_equal("")
	assert_array(_s.selection_timeline).is_equal(["selected:%s" % FIRST, "cleared"])


func test_ac20_esc_clears_the_selection_once_and_sends_no_pick_request() -> void:
	if not await _open(_pair()):
		return
	_select(FIRST)
	_s.esc()
	assert_str(_s.selected_uid()).is_equal("")
	assert_array(_s.selection_timeline).is_equal(["selected:%s" % FIRST, "cleared"])
	assert_int(_s.clear_requests).is_equal(0)
	_s.esc()
	assert_array(_s.selection_timeline).is_equal(["selected:%s" % FIRST, "cleared"])


## #33 update: the click lands on the spot the stone occupies, so nothing is placed there (the
## footprint rule); the click still never selects.
func test_ac20_with_a_pick_a_click_on_an_item_never_selects() -> void:
	if not await _open(_pair()):
		return
	_s.pick(Rig.AMPHORA)
	_s.click(_s.screen_of_item(FIRST))
	assert_int(_s.model.get_item_count()).is_equal(2)
	assert_str(_s.selected_uid()).is_equal("")
	assert_array(_s.selection_timeline).is_empty()


func test_ac34_a_pick_clears_the_selection_first_and_it_never_comes_back() -> void:
	if not await _open(_pair()):
		return
	_select(FIRST)
	_s.move(_s.screen_of(0.0, -0.1))
	_s.pick(Rig.STONE)
	assert_array(_s.selection_timeline).is_equal(["selected:%s" % FIRST, "cleared"])
	assert_str(_s.selected_uid()).is_equal("")
	assert_bool(_s.ghost_shown()).is_true()
	assert_int(_marked(FIRST)).is_equal(0)
	_s.unpick()
	assert_str(_s.selected_uid()).is_equal("")
	assert_array(_s.selection_timeline).is_equal(["selected:%s" % FIRST, "cleared"])


func test_ac35_item_changed_keeps_the_selection_and_the_mark() -> void:
	var model: AquariumModel = _pair()
	if not await _open(model):
		return
	_select(FIRST)
	var turned: PlacedItem = model.get_item(FIRST).copy()
	turned.rotation_y = 75.0
	turned.position = Vector3(-0.1, 0.0, 0.05)
	model.apply_replace_item(turned)
	await _s.frame()
	assert_str(_s.selected_uid()).is_equal(FIRST)
	assert_array(_s.selection_timeline).is_equal(["selected:%s" % FIRST])
	assert_int(_marked(FIRST)).is_greater(0)


func test_ac35_changes_to_other_items_change_nothing() -> void:
	var model: AquariumModel = _pair()
	if not await _open(model):
		return
	_select(FIRST)
	var other: PlacedItem = model.get_item(SECOND).copy()
	other.rotation_y = 10.0
	model.apply_replace_item(other)
	Rig.add_item(model, "a0000003", Rig.AMPHORA, 0.0, 0.1)
	await _s.frame()
	assert_str(_s.selected_uid()).is_equal(FIRST)
	assert_array(_s.selection_timeline).is_equal(["selected:%s" % FIRST])


func test_ac35_removing_the_selected_item_clears_the_selection_once() -> void:
	var model: AquariumModel = _pair()
	if not await _open(model):
		return
	_select(FIRST)
	model.apply_remove_item(FIRST)
	await _s.frame()
	assert_str(_s.selected_uid()).is_equal("")
	assert_array(_s.selection_timeline).is_equal(["selected:%s" % FIRST, "cleared"])


func test_ac35_a_model_reset_clears_the_selection_once() -> void:
	var model: AquariumModel = _pair()
	if not await _open(model):
		return
	_select(FIRST)
	var other: AquariumModel = Rig.model()
	Rig.add_item(other, "b0000001", Rig.AMPHORA, 0.0, 0.0)
	model.reset_from(other)
	await _s.frame()
	assert_str(_s.selected_uid()).is_equal("")
	assert_array(_s.selection_timeline).is_equal(["selected:%s" % FIRST, "cleared"])


func test_ac35_a_displayed_tank_clears_the_selection_once() -> void:
	if not await _open(_pair()):
		return
	_select(FIRST)
	EventBus.tank_displayed.emit(&"tank_medium_1")
	assert_str(_s.selected_uid()).is_equal("")
	assert_array(_s.selection_timeline).is_equal(["selected:%s" % FIRST, "cleared"])


func test_ac35_undo_of_the_placement_of_the_selected_item_clears_and_redo_brings_it_back_unselected(
) -> void:
	if not await _open(Rig.model()):
		return
	var item: PlacedItem = Factory.item("c0000001", Rig.STONE, Vector3(0.0, 0.0, 0.0), 0.0, 1.0)
	assert_bool(_s.history.execute(Api.place_command(_s.model, item, Api.rules()))).is_true()
	await _s.frame()
	_select("c0000001")
	assert_str(_s.selected_uid()).is_equal("c0000001")
	assert_bool(_s.history.undo()).is_true()
	await _s.frame()
	assert_str(_s.selected_uid()).is_equal("")
	assert_array(_s.selection_timeline).is_equal(["selected:c0000001", "cleared"])
	assert_bool(_s.history.redo()).is_true()
	await _s.frame()
	assert_str(_s.selected_uid()).is_equal("")
	assert_int(_s.drawn_count()).is_equal(1)
	assert_int(_marked("c0000001")).is_equal(0)


func test_ac35_a_move_or_rotate_undone_and_redone_keeps_the_selection() -> void:
	var model: AquariumModel = _pair()
	if not await _open(model):
		return
	_select(FIRST)
	var command: Command = Api.transform_command(
		model, FIRST, model.get_item(FIRST).position, 30.0, Api.rules()
	)
	assert_bool(_s.history.execute(command)).is_true()
	await _s.frame()
	assert_str(_s.selected_uid()).is_equal(FIRST)
	assert_bool(_s.history.undo()).is_true()
	await _s.frame()
	assert_str(_s.selected_uid()).is_equal(FIRST)
	assert_bool(_s.history.redo()).is_true()
	await _s.frame()
	assert_str(_s.selected_uid()).is_equal(FIRST)
	assert_array(_s.selection_timeline).is_equal(["selected:%s" % FIRST])
	assert_int(_marked(FIRST)).is_greater(0)
