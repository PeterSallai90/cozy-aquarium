# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #31 AC 5 to 10 and 40 (owner: developer, with the ghost material of the technical-artist): the
## ghost preview of RoomCorner/Placement/Ghost. A picked item (EventBus.item_picked) shows a
## see-through ghost of its own scene at the ground point under the pointer (the pointer ray
## against the plane of the nominal substrate surface), at the ghost rotation, with no model or
## history change; it follows camera moves and substrate changes; it is hidden over HUD panels,
## outside the interior, while the world is blocked and after item_pick_cleared. The rotate keys
## turn the ghost rotation (part of the pick); key repeat runs on fixed frame times.
## Test decisions: the camera looks from 60 degrees above (30 degrees for the tall item); the HUD
## panels are fake MOUSE_FILTER_STOP Controls in the viewport; the expected ground point is an
## independent plane intersection in the session helper; Shift is sent as its own key event
## before the rotate key (the plan reads Shift from the Shift key events at each repeat).

const Rig := preload("res://tests/helpers/placement_rig.gd")
const Session := preload("res://tests/helpers/placement_session.gd")
const Api := preload("res://tests/helpers/placement_api.gd")
const Cam := preload("res://tests/helpers/camera_rig.gd")
const ModelState := preload("res://tests/helpers/model_state.gd")

const GHOST_MATERIAL := "res://scenes/tank/items/item_ghost_material.tres"
const AC40_ELEVATION_DEG: float = 30.0
const TOLERANCE := Vector3(0.0005, 0.0005, 0.0005)
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


func _yaw_gap(actual: float, expected: float) -> float:
	return absf(wrapf(actual - expected, -180.0, 180.0))


func _child_ids() -> Array[int]:
	var ids: Array[int] = []
	for child: Node in _s.ghost.get_children():
		ids.append(child.get_instance_id())
	return ids


func _scene_of_ghost() -> String:
	for child: Node in _s.ghost.get_children():
		if child.scene_file_path != "":
			return child.scene_file_path
	return "<no scene instance>"


func test_ac05_without_a_pick_there_is_no_ghost() -> void:
	if not await _open():
		return
	_s.move(_s.screen_of(0.0, 0.0))
	assert_bool(_s.ghost_shown()).is_false()


func test_ac05_the_ghost_stands_at_the_ground_point_under_the_pointer() -> void:
	if not await _open():
		return
	_s.pick(Rig.STONE)
	var at: Vector2 = _s.screen_of(0.1234, -0.0567)
	_s.move(at)
	assert_bool(_s.ghost_shown()).is_true()
	assert_vector(_s.local_position(_s.ghost)).is_equal_approx(
		Vector3(0.1234, 0.0, -0.0567), TOLERANCE
	)
	assert_vector(_s.local_position(_s.ghost)).is_equal_approx(_s.ground_local(at), TOLERANCE)


func test_ac05_the_position_is_continuous_with_no_grid() -> void:
	if not await _open():
		return
	_s.pick(Rig.STONE)
	var first: Vector2 = Vector2(560.0, 330.0)
	_s.move(first)
	var one: Vector3 = _s.local_position(_s.ghost)
	_s.move(first + Vector2(1.0, 0.0))
	var two: Vector3 = _s.local_position(_s.ghost)
	assert_vector(one).is_equal_approx(_s.ground_local(first), TOLERANCE)
	assert_vector(two).is_equal_approx(_s.ground_local(first + Vector2(1.0, 0.0)), TOLERANCE)
	assert_float(two.x - one.x).is_greater(0.0)
	assert_float(two.x - one.x).is_less(0.005)


func test_ac05_the_ghost_is_the_item_scene_with_the_ghost_material_and_no_shadow() -> void:
	if not await _open():
		return
	_s.pick(Rig.STONE)
	_s.move(_s.screen_of(0.0, 0.0))
	var definition: ItemDefinition = _s.items.get_definition(Rig.STONE)
	assert_str(_scene_of_ghost()).is_equal(definition.scene.resource_path)
	var meshes: Array[Node] = _s.ghost.find_children("*", "GeometryInstance3D", true, false)
	assert_int(meshes.size()).is_greater(0)
	for node: Node in meshes:
		var instance: GeometryInstance3D = node as GeometryInstance3D
		assert_object(instance.material_override).is_not_null()
		assert_str(instance.material_override.resource_path).is_equal(GHOST_MATERIAL)
		assert_int(instance.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		assert_object(instance.material_overlay).is_null()


func test_ac39_the_ghost_has_no_collision_and_no_pick_shape() -> void:
	if not await _open():
		return
	_s.pick(Rig.STONE)
	_s.move(_s.screen_of(0.0, 0.0))
	assert_int(_s.ghost.find_children("*", "CollisionObject3D", true, false).size()).is_equal(0)
	assert_int(_s.ghost.find_children("*", "CollisionShape3D", true, false).size()).is_equal(0)


func test_ac05_moving_the_ghost_changes_neither_the_model_nor_the_history() -> void:
	if not await _open():
		return
	var state_before: Dictionary = ModelState.snapshot(_s.model)
	_s.pick(Rig.STONE)
	for index: int in 10:
		_s.move(_s.screen_of(-0.2 + 0.04 * index, 0.0))
	assert_dict(ModelState.snapshot(_s.model)).is_equal(state_before)
	assert_int(_s.history.get_undo_count()).is_equal(0)


func test_ac06_a_camera_move_with_a_still_pointer_moves_the_ghost() -> void:
	if not await _open():
		return
	_s.pick(Rig.STONE)
	var at: Vector2 = Vector2(Rig.WINDOW) / 2.0
	_s.move(at)
	assert_bool(_s.ghost_shown()).is_true()
	var state_before: Vector3 = _s.local_position(_s.ghost)
	Cam.set_orbit(_s.camera, 35.0, 55.0, true)
	_s.step(0.0)
	var state_after: Vector3 = _s.local_position(_s.ghost)
	assert_bool(_s.ghost_shown()).is_true()
	assert_vector(state_after).is_equal_approx(_s.ground_local(at), TOLERANCE)
	assert_float(state_before.distance_to(state_after)).is_greater(0.005)
	assert_float(state_after.y).is_equal_approx(0.0, 0.0005)


func test_ac07_outside_the_tank_interior_there_is_no_ghost() -> void:
	if not await _open():
		return
	_s.pick(Rig.STONE)
	_s.move(_s.screen_of(0.0, 0.0))
	assert_bool(_s.ghost_shown()).is_true()
	_s.move(Session.OUTSIDE)
	assert_bool(_s.ghost_shown()).is_false()
	_s.move(_s.screen_of(0.29, 0.0))
	assert_bool(_s.ghost_shown()).is_true()
	_s.move(_s.screen_of(0.31, 0.0))
	assert_bool(_s.ghost_shown()).is_false()


func test_ac07_a_click_outside_the_interior_places_nothing() -> void:
	if not await _open():
		return
	_s.pick(Rig.STONE)
	_s.click(Session.OUTSIDE)
	_s.click(_s.screen_of(0.31, 0.0))
	assert_int(_s.model.get_item_count()).is_equal(0)
	assert_int(_s.history.get_undo_count()).is_equal(0)


func test_ac07_over_a_hud_panel_there_is_no_ghost_and_no_placement() -> void:
	if not await _open():
		return
	_s.pick(Rig.STONE)
	var centre: Vector2 = _s.screen_of(0.0, 0.0)
	var panel: Control = _s.make_panel(Rect2(centre - Vector2(60.0, 60.0), Vector2(120.0, 120.0)))
	_s.move(centre)
	assert_bool(_s.ghost_shown()).is_false()
	_s.click(centre)
	assert_int(_s.model.get_item_count()).is_equal(0)
	panel.queue_free()
	await _s.frame()
	_s.move(centre + Vector2(1.0, 0.0))
	assert_bool(_s.ghost_shown()).is_true()


func test_ac07_a_modal_dialog_hides_the_ghost_and_no_press_is_handled() -> void:
	if not await _open():
		return
	_s.pick(Rig.STONE)
	var at: Vector2 = _s.screen_of(0.0, 0.0)
	_s.move(at)
	assert_bool(_s.ghost_shown()).is_true()
	var blocker: Control = _s.make_blocker()
	_s.set_blocked(blocker, true)
	assert_bool(_s.ghost_shown()).is_false()
	_s.click(at)
	assert_int(_s.model.get_item_count()).is_equal(0)
	_s.set_blocked(blocker, false)
	_s.move(at + Vector2(1.0, 0.0))
	assert_bool(_s.ghost_shown()).is_true()


func test_ac08_a_non_modal_panel_leaves_the_ghost_over_the_visible_tank() -> void:
	if not await _open():
		return
	_s.pick(Rig.STONE)
	_s.make_panel(Rect2(0.0, 0.0, 120.0, 648.0))
	_s.move(_s.screen_of(0.0, 0.0))
	assert_bool(_s.ghost_shown()).is_true()
	_s.move(Vector2(60.0, 300.0))
	assert_bool(_s.ghost_shown()).is_false()


func test_ac09_another_pick_replaces_the_ghost_at_once_and_a_clear_removes_it() -> void:
	if not await _open():
		return
	_s.pick(Rig.STONE)
	var at: Vector2 = _s.screen_of(0.0, 0.0)
	_s.move(at)
	var definition: ItemDefinition = _s.items.get_definition(Rig.STONE)
	assert_str(_scene_of_ghost()).is_equal(definition.scene.resource_path)
	_s.pick(Rig.BRANCH)
	assert_bool(_s.ghost_shown()).is_true()
	var other: ItemDefinition = _s.items.get_definition(Rig.BRANCH)
	assert_str(_scene_of_ghost()).is_equal(other.scene.resource_path)
	_s.unpick()
	assert_bool(_s.ghost_shown()).is_false()


func test_ac33_the_ghost_is_one_instance_reused_while_the_pick_stays() -> void:
	if not await _open():
		return
	_s.pick(Rig.STONE)
	_s.move(_s.screen_of(0.0, 0.0))
	var ids: Array[int] = _child_ids()
	assert_int(ids.size()).is_greater(0)
	for index: int in 10:
		_s.move(_s.screen_of(-0.2 + 0.04 * index, 0.05))
	assert_array(_child_ids()).is_equal(ids)
	_s.pick(Rig.BRANCH)
	assert_array(_child_ids()).is_not_equal(ids)


func test_ac10_a_rotate_key_turns_the_ghost_in_15_degree_steps() -> void:
	if not await _open():
		return
	_s.pick(Rig.STONE)
	_s.move(_s.screen_of(0.0, 0.0))
	_s.tap(KEY_COMMA)
	assert_float(_s.ghost_rotation()).is_equal_approx(15.0, 0.001)
	assert_float(_yaw_gap(_s.yaw_of(_s.ghost), 15.0)).is_less(ANGLE_TOLERANCE)
	_s.tap(KEY_COMMA)
	assert_float(_s.ghost_rotation()).is_equal_approx(30.0, 0.001)
	_s.tap(KEY_PERIOD)
	assert_float(_s.ghost_rotation()).is_equal_approx(15.0, 0.001)
	_s.tap(KEY_PERIOD)
	_s.tap(KEY_PERIOD)
	assert_float(_s.ghost_rotation()).is_equal_approx(345.0, 0.001)
	assert_float(_yaw_gap(_s.yaw_of(_s.ghost), 345.0)).is_less(ANGLE_TOLERANCE)


func test_ac10_shift_turns_the_ghost_by_one_degree() -> void:
	if not await _open():
		return
	_s.pick(Rig.STONE)
	_s.move(_s.screen_of(0.0, 0.0))
	_s.tap(KEY_COMMA, KEY_MASK_SHIFT)
	assert_float(_s.ghost_rotation()).is_equal_approx(1.0, 0.001)
	_s.tap(KEY_COMMA, KEY_MASK_SHIFT)
	assert_float(_s.ghost_rotation()).is_equal_approx(2.0, 0.001)
	_s.tap(KEY_PERIOD, KEY_MASK_SHIFT)
	_s.tap(KEY_PERIOD, KEY_MASK_SHIFT)
	_s.tap(KEY_PERIOD, KEY_MASK_SHIFT)
	assert_float(_s.ghost_rotation()).is_equal_approx(359.0, 0.001)
	_s.tap(KEY_COMMA)
	assert_float(_s.ghost_rotation()).is_equal_approx(0.0, 0.001)


func test_ac10_the_ghost_rotation_resets_when_the_pick_changes_or_is_cleared() -> void:
	if not await _open():
		return
	_s.pick(Rig.STONE)
	_s.tap(KEY_COMMA)
	_s.tap(KEY_COMMA)
	assert_float(_s.ghost_rotation()).is_equal_approx(30.0, 0.001)
	_s.pick(Rig.BRANCH)
	assert_float(_s.ghost_rotation()).is_equal_approx(0.0, 0.001)
	_s.tap(KEY_COMMA)
	_s.unpick()
	_s.pick(Rig.STONE)
	assert_float(_s.ghost_rotation()).is_equal_approx(0.0, 0.001)


func test_ac10_the_rotate_keys_work_with_no_ghost_and_the_next_ghost_has_that_rotation() -> void:
	if not await _open():
		return
	_s.pick(Rig.BRANCH)
	_s.move(Session.OUTSIDE)
	assert_bool(_s.ghost_shown()).is_false()
	_s.tap(KEY_COMMA)
	_s.tap(KEY_COMMA)
	_s.tap(KEY_COMMA)
	assert_float(_s.ghost_rotation()).is_equal_approx(45.0, 0.001)
	_s.move(_s.screen_of(0.0, 0.0))
	assert_bool(_s.ghost_shown()).is_true()
	assert_float(_yaw_gap(_s.yaw_of(_s.ghost), 45.0)).is_less(ANGLE_TOLERANCE)


func test_ac10_a_held_rotate_key_repeats_after_the_delay_then_at_the_interval() -> void:
	if not await _open():
		return
	_s.pick(Rig.STONE)
	var delay: float = Api.tuning("REPEAT_DELAY_S")
	var interval: float = Api.tuning("REPEAT_INTERVAL_S")
	_s.key(KEY_COMMA, true)
	assert_float(_s.ghost_rotation()).is_equal_approx(15.0, 0.001)
	_s.step(delay * 0.9)
	assert_float(_s.ghost_rotation()).is_equal_approx(15.0, 0.001)
	_s.step(delay * 0.2)
	assert_float(_s.ghost_rotation()).is_equal_approx(30.0, 0.001)
	_s.step(interval)
	assert_float(_s.ghost_rotation()).is_equal_approx(45.0, 0.001)
	_s.step(interval)
	assert_float(_s.ghost_rotation()).is_equal_approx(60.0, 0.001)
	_s.key(KEY_COMMA, false)
	_s.step(delay + interval * 3.0)
	assert_float(_s.ghost_rotation()).is_equal_approx(60.0, 0.001)
	assert_int(_s.history.get_undo_count()).is_equal(0)


func test_ac10_a_held_rotate_key_with_shift_repeats_the_one_degree_step_faster() -> void:
	if not await _open():
		return
	_s.pick(Rig.STONE)
	var delay: float = Api.tuning("REPEAT_DELAY_S")
	var fine: float = Api.tuning("FINE_REPEAT_INTERVAL_S")
	_s.shift(true)
	_s.key(KEY_COMMA, true, KEY_MASK_SHIFT)
	assert_float(_s.ghost_rotation()).is_equal_approx(1.0, 0.001)
	_s.step(delay + fine * 0.5)
	assert_float(_s.ghost_rotation()).is_equal_approx(2.0, 0.001)
	_s.step(fine)
	assert_float(_s.ghost_rotation()).is_equal_approx(3.0, 0.001)
	_s.step(fine)
	assert_float(_s.ghost_rotation()).is_equal_approx(4.0, 0.001)


func test_ac10_releasing_shift_mid_hold_returns_the_repeat_to_15_degree_steps() -> void:
	if not await _open():
		return
	_s.pick(Rig.STONE)
	var delay: float = Api.tuning("REPEAT_DELAY_S")
	_s.shift(true)
	_s.key(KEY_COMMA, true, KEY_MASK_SHIFT)
	assert_float(_s.ghost_rotation()).is_equal_approx(1.0, 0.001)
	_s.shift(false)
	_s.step(delay * 1.1)
	assert_float(_s.ghost_rotation()).is_equal_approx(15.0, 0.001)


func test_ac07_a_substrate_change_moves_the_ghost_with_the_new_surface() -> void:
	if not await _open():
		return
	_s.pick(Rig.STONE)
	var at: Vector2 = _s.screen_of(0.1, 0.05)
	_s.move(at)
	_s.model.apply_set_substrate(Rig.PEBBLES, Rig.CREAM)
	await _s.frame()
	_s.step(0.0)
	assert_bool(_s.ghost_shown()).is_true()
	assert_vector(_s.local_position(_s.ghost)).is_equal_approx(_s.ground_local(at), TOLERANCE)
	assert_float(_s.placement.to_local(_s.ghost.global_position).y).is_equal_approx(
		_s.depth(), 0.0005
	)
	assert_int(_s.history.get_undo_count()).is_equal(0)


func test_ac40_over_a_tall_item_the_ghost_stands_on_the_bed_behind_it() -> void:
	var model: AquariumModel = Rig.model()
	Rig.add_item(model, "a0000001", Rig.TALL, 0.0, 0.10)
	if not await _open(model, AC40_ELEVATION_DEG):
		return
	_s.pick(Rig.STONE)
	var at: Vector2 = _s.screen_of(0.0, 0.10, 0.10)
	_s.move(at)
	var ground: Vector3 = _s.ground_local(at)
	assert_bool(_s.ghost_shown()).is_true()
	assert_vector(_s.local_position(_s.ghost)).is_equal_approx(ground, TOLERANCE)
	assert_float(ground.z).is_less(0.10 - 0.05)
	assert_float(_s.local_position(_s.ghost).y).is_equal_approx(0.0, 0.0005)
