# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #25 criteria 1, 2 (scene part), 3, 4, 7, 9, 13, 15 and 16 (drag part) (owner: developer): the
## build camera in the real room, driven by synthetic mouse events pushed through the viewport and
## by fixed frame times (BuildCamera.step). The expected limits come from OrbitMath, never from a
## literal -10, except where the story states the numbers (-10 and -9.979 at the default distance).
## Room and camera access: tests/helpers/camera_rig.gd.

const Room := preload("res://tests/helpers/room_rig.gd")
const Cam := preload("res://tests/helpers/camera_rig.gd")
const Table := preload("res://tests/helpers/tank_table.gd")
const Glb := preload("res://tests/helpers/glb_mesh_checks.gd")
const OrbitApi := preload("res://tests/helpers/orbit_api.gd")

const HUGE_PX := 1000000.0
const STORY_LIMIT_DEG := {
	&"tank_small_1": -10.0,
	&"tank_medium_1": -10.0,
	&"tank_large_1": -9.979,
}

var _viewport: SubViewport = null
var _room: Node3D = null
var _camera: Camera3D = null


## Opens the room with the tank in its own viewport; false (after a failed assert) when the room
## has no BuildCamera yet.
func _open(id: StringName = Table.MEDIUM, size: Vector2i = Cam.SIZE_16_9) -> bool:
	(
		assert_bool(ResourceLoader.exists(Room.ROOM_SCENE))
		. override_failure_message("room scene missing: %s" % Room.ROOM_SCENE)
		. is_true()
	)
	if _viewport != null and is_instance_valid(_viewport):
		_viewport.free()
	var rig: Dictionary = await Cam.open(self, Room.model_with(id), size)
	_viewport = rig["viewport"]
	_room = rig["room"]
	_camera = Cam.camera_of(_room)
	(
		assert_bool(_camera != null)
		. override_failure_message("the room has no BuildCamera child (Camera3D)")
		. is_true()
	)
	return _camera != null


func _tank_pivot() -> Vector3:
	return (_room.get_node("Tank/WaterVolume") as Node3D).global_position


func _height_ok() -> bool:
	return _camera.global_position.y >= Cam.CABINET_TOP_M - Cam.LENGTH_TOLERANCE_M


# --- the start view ---


func test_default_view_is_the_front_at_5_degrees_with_the_framing_distance() -> void:
	if not await _open():
		return
	assert_float(Cam.az(_camera)).is_equal_approx(0.0, Cam.ANGLE_TOLERANCE_DEG)
	assert_float(Cam.el(_camera)).is_equal_approx(5.0, Cam.ANGLE_TOLERANCE_DEG)
	assert_float(Cam.t_az(_camera)).is_equal_approx(0.0, Cam.ANGLE_TOLERANCE_DEG)
	assert_float(Cam.t_el(_camera)).is_equal_approx(5.0, Cam.ANGLE_TOLERANCE_DEG)
	assert_vector(Cam.pivot(_camera)).is_equal_approx(_tank_pivot(), Vector3.ONE * 0.001)
	assert_vector(_camera.global_position - Cam.pivot(_camera)).is_equal_approx(
		OrbitApi.offset(0.0, 5.0, Cam.dist(_camera)), Vector3.ONE * 0.001
	)
	assert_vector(_camera.rotation).is_equal_approx(
		OrbitApi.camera_rotation(0.0, 5.0), Vector3.ONE * 0.001
	)


func test_the_camera_stays_a_direct_child_of_the_room_and_is_current() -> void:
	if not await _open():
		return
	assert_object(_camera.get_parent()).is_same(_room)
	assert_object(_viewport.get_camera_3d()).is_same(_camera)


func test_the_start_view_does_not_ease_from_the_origin() -> void:
	if not await _open():
		return
	var before: Vector3 = _camera.global_position
	Cam.step(_camera, 0.5)
	assert_vector(_camera.global_position).is_equal_approx(before, Vector3.ONE * 0.001)


# --- AC 1: the lowest elevation, per tank ---


func test_ac01_one_very_large_downward_drag_stops_at_the_lowest_elevation_of_every_tank() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		Cam.drag(_viewport, Vector2(0.0, HUGE_PX))
		var lowest: float = Cam.min_el(_camera, id)
		assert_float(lowest).is_equal_approx(STORY_LIMIT_DEG[id], Cam.ANGLE_TOLERANCE_DEG)
		assert_float(Cam.t_el(_camera)).is_equal_approx(lowest, Cam.ANGLE_TOLERANCE_DEG)
		Cam.settle(_camera)
		assert_float(Cam.el(_camera)).is_equal_approx(lowest, Cam.ANGLE_TOLERANCE_DEG)
		assert_float(_camera.global_position.y).is_greater_equal(
			Cam.CABINET_TOP_M - Cam.LENGTH_TOLERANCE_M
		)


func test_ac01_a_slow_drag_down_stops_at_the_same_elevation() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		Cam.right_press(_viewport)
		for index: int in 120:
			Cam.motion(_viewport, Vector2(0.0, 10.0))
			Cam.step(_camera, 0.016)
			assert_bool(_height_ok()).is_true()
		Cam.right_release(_viewport)
		assert_float(Cam.t_el(_camera)).is_equal_approx(
			Cam.min_el(_camera, id), Cam.ANGLE_TOLERANCE_DEG
		)


func test_ac01_the_camera_height_never_drops_below_the_cabinet_while_easing_down() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		Cam.drag(_viewport, Vector2(0.0, HUGE_PX))
		for index: int in 240:
			Cam.step(_camera, Cam.FRAME_S)
			assert_float(_camera.global_position.y).is_greater_equal(
				Cam.CABINET_TOP_M - Cam.LENGTH_TOLERANCE_M
			)


func test_ac01_a_downward_drag_lowers_and_an_upward_drag_raises_the_elevation() -> void:
	if not await _open():
		return
	# 20 px of a 720 px high viewport at 180 degrees per viewport height is 5 degrees.
	Cam.drag(_viewport, Vector2(0.0, 20.0))
	assert_float(Cam.t_el(_camera)).is_equal_approx(0.0, Cam.ANGLE_TOLERANCE_DEG)
	Cam.drag(_viewport, Vector2(0.0, -40.0))
	assert_float(Cam.t_el(_camera)).is_equal_approx(10.0, Cam.ANGLE_TOLERANCE_DEG)


func test_ac01_the_drag_changes_the_target_and_the_view_eases_after_it() -> void:
	if not await _open():
		return
	Cam.drag(_viewport, Vector2(0.0, 20.0))
	assert_float(Cam.el(_camera)).is_equal_approx(5.0, Cam.ANGLE_TOLERANCE_DEG)
	Cam.settle(_camera)
	assert_float(Cam.el(_camera)).is_equal_approx(0.0, Cam.ANGLE_TOLERANCE_DEG)


# --- AC 2: a larger distance raises the lowest elevation (scene part) ---


func test_ac02_at_2_5_times_the_default_distance_the_lowest_elevation_is_about_minus_4() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		var above: float = Table.glass(id) + Table.water_line(id) / 2.0
		var limit: float = OrbitApi.setting("min_elevation_limit_deg")
		var distance: float = Cam.t_dist(_camera) * 2.5
		var elevation: float = OrbitApi.min_elevation(limit, above, distance)
		assert_float(elevation).is_greater(Cam.min_el(_camera, id))
		assert_float(elevation).is_equal_approx(-4.0, 0.5)
		if id == Table.LARGE:
			assert_float(elevation).is_equal_approx(-3.97, 0.03)
		# The camera at that distance and elevation is at the cabinet top, not below.
		var height: float = _tank_pivot().y + distance * sin(deg_to_rad(elevation))
		assert_float(height).is_greater_equal(Cam.CABINET_TOP_M - Cam.LENGTH_TOLERANCE_M)


# --- AC 3: the top, no flip ---


func test_ac03_one_very_large_upward_drag_stops_at_85_degrees_with_a_sane_basis() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		Cam.drag(_viewport, Vector2(0.0, -HUGE_PX))
		assert_float(Cam.t_el(_camera)).is_equal_approx(Cam.MAX_ELEVATION_DEG, 0.01)
		Cam.settle(_camera)
		assert_float(Cam.el(_camera)).is_equal_approx(Cam.MAX_ELEVATION_DEG, 0.01)
		assert_array(Array(Cam.basis_failures(_camera, Cam.pivot(_camera)))).is_empty()


func test_ac03_dragging_further_up_and_around_at_85_degrees_never_flips_the_view() -> void:
	if not await _open():
		return
	Cam.right_press(_viewport)
	for index: int in 90:
		Cam.motion(_viewport, Vector2(15.0, -30.0))
		Cam.step(_camera, Cam.FRAME_S)
		assert_float(Cam.t_el(_camera)).is_less_equal(Cam.MAX_ELEVATION_DEG + 0.01)
		assert_float(Cam.el(_camera)).is_less_equal(Cam.MAX_ELEVATION_DEG + 0.01)
		assert_array(Array(Cam.basis_failures(_camera, Cam.pivot(_camera)))).is_empty()
	Cam.right_release(_viewport)
	assert_float(Cam.t_el(_camera)).is_equal_approx(Cam.MAX_ELEVATION_DEG, 0.01)


func test_ac03_the_basis_stays_sane_on_the_way_up_and_down() -> void:
	if not await _open():
		return
	Cam.drag(_viewport, Vector2(60.0, -HUGE_PX))
	for index: int in 60:
		Cam.step(_camera, Cam.FRAME_S)
		assert_array(Array(Cam.basis_failures(_camera, Cam.pivot(_camera)))).is_empty()
	Cam.drag(_viewport, Vector2(-60.0, HUGE_PX))
	for index: int in 60:
		Cam.step(_camera, Cam.FRAME_S)
		assert_array(Array(Cam.basis_failures(_camera, Cam.pivot(_camera)))).is_empty()


# --- AC 4: no limit horizontally ---


func test_ac04_a_horizontal_drag_of_more_than_two_turns_orbits_without_a_limit() -> void:
	if not await _open():
		return
	var start_az: float = Cam.t_az(_camera)
	var start_el: float = Cam.t_el(_camera)
	var start_dist: float = Cam.t_dist(_camera)
	var per_event: float = OrbitApi.drag_deg(120.0, 720.0, 180.0)
	Cam.right_press(_viewport)
	var turned: float = 0.0
	for index: int in 26:
		var before: float = Cam.t_az(_camera)
		Cam.motion(_viewport, Vector2(120.0, 0.0))
		var step: float = Cam.t_az(_camera) - before
		assert_float(absf(step)).is_equal_approx(per_event, Cam.ANGLE_TOLERANCE_DEG)
		turned += step
	Cam.right_release(_viewport)
	assert_float(absf(turned)).is_equal_approx(26.0 * per_event, 0.05)
	assert_float(absf(turned)).is_greater(720.0)
	assert_float(Cam.t_el(_camera)).is_equal_approx(start_el, Cam.ANGLE_TOLERANCE_DEG)
	assert_float(Cam.t_dist(_camera)).is_equal_approx(start_dist, Cam.LENGTH_TOLERANCE_M)
	assert_float(absf(Cam.t_az(_camera) - start_az)).is_greater(720.0)
	Cam.settle(_camera)
	assert_float(Cam.el(_camera)).is_equal_approx(start_el, Cam.ANGLE_TOLERANCE_DEG)
	assert_float(Cam.dist(_camera)).is_equal_approx(start_dist, Cam.LENGTH_TOLERANCE_M)


func test_ac04_the_other_way_round_brings_the_view_back_to_where_it_started() -> void:
	if not await _open():
		return
	var start_position: Vector3 = _camera.global_position
	var start_az: float = Cam.t_az(_camera)
	Cam.drag(_viewport, Vector2(3000.0, 0.0))
	Cam.drag(_viewport, Vector2(-3000.0, 0.0))
	assert_float(Cam.t_az(_camera)).is_equal_approx(start_az, Cam.ANGLE_TOLERANCE_DEG)
	Cam.settle(_camera)
	assert_vector(_camera.global_position).is_equal_approx(start_position, Vector3.ONE * 0.001)


func test_ac04_a_turn_of_more_than_one_circle_eases_the_whole_way_without_a_jump() -> void:
	if not await _open():
		return
	Cam.drag(_viewport, Vector2(1800.0, 0.0))
	var gap: float = absf(Cam.t_az(_camera) - Cam.az(_camera))
	assert_float(gap).is_equal_approx(450.0, 0.05)
	var last: float = Cam.az(_camera)
	for index: int in 30:
		Cam.step(_camera, Cam.FRAME_S)
		# The damped value moves monotonically toward the target and never overshoots it.
		assert_float(absf(Cam.t_az(_camera) - Cam.az(_camera))).is_less_equal(
			absf(Cam.t_az(_camera) - last) + 0.0001
		)
		last = Cam.az(_camera)
	Cam.settle(_camera)
	assert_float(Cam.az(_camera)).is_equal_approx(Cam.t_az(_camera), Cam.ANGLE_TOLERANCE_DEG)


func test_ac04_a_horizontal_drag_converts_pixels_with_the_viewport_height() -> void:
	if not await _open():
		return
	var before: float = Cam.t_az(_camera)
	Cam.drag(_viewport, Vector2(80.0, 0.0))
	# 80 px of 720 px at 180 degrees per viewport height is 20 degrees (direction is feel).
	assert_float(absf(Cam.t_az(_camera) - before)).is_equal_approx(20.0, Cam.ANGLE_TOLERANCE_DEG)


func test_ac04_the_same_drag_in_a_taller_viewport_turns_less() -> void:
	if not await _open(Table.MEDIUM, Cam.SIZE_4_3):
		return
	var before: float = Cam.t_az(_camera)
	Cam.drag(_viewport, Vector2(80.0, 0.0))
	# 80 px of 768 px at 180 degrees per viewport height.
	assert_float(absf(Cam.t_az(_camera) - before)).is_equal_approx(
		80.0 / 768.0 * 180.0, Cam.ANGLE_TOLERANCE_DEG
	)


# --- damping ---


func test_the_view_eases_to_the_target_in_about_0_15_seconds() -> void:
	if not await _open():
		return
	Cam.drag(_viewport, Vector2(360.0, 0.0))
	var gap: float = absf(Cam.t_az(_camera) - Cam.az(_camera))
	assert_float(gap).is_equal_approx(90.0, 0.05)
	Cam.step(_camera, Cam.FRAME_S)
	var remaining: float = absf(Cam.t_az(_camera) - Cam.az(_camera))
	assert_float(remaining).is_between(gap * 0.4, gap * 0.8)
	Cam.step(_camera, 0.15 - Cam.FRAME_S)
	assert_float(absf(Cam.t_az(_camera) - Cam.az(_camera))).is_less_equal(gap * 0.02)


func test_a_damping_time_of_zero_is_instant() -> void:
	if not await _open():
		return
	var settings: Resource = OrbitApi.settings().duplicate() as Resource
	settings.set("damping_time_s", 0.0)
	_camera.set("settings", settings)
	Cam.drag(_viewport, Vector2(360.0, -100.0))
	Cam.step(_camera, Cam.FRAME_S)
	assert_float(Cam.az(_camera)).is_equal_approx(Cam.t_az(_camera), Cam.ANGLE_TOLERANCE_DEG)
	assert_float(Cam.el(_camera)).is_equal_approx(Cam.t_el(_camera), Cam.ANGLE_TOLERANCE_DEG)


# --- AC 7: the tank stays in view ---


func test_ac07_the_pivot_and_the_tank_stay_in_view_at_every_pose_and_aspect() -> void:
	var sizes: Array[Vector2i] = [Cam.SIZE_16_9, Cam.SIZE_4_3, Cam.SIZE_21_9]
	for id: StringName in Table.IDS:
		for size: Vector2i in sizes:
			if not await _open(id, size):
				return
			var tank: AABB = Glb.scene_bounds_in(_room.get_node("Tank") as Node3D, _room)
			for azimuth: float in [0.0, 90.0, 180.0, 270.0, 315.0]:
				for elevation: float in [-10.0, 5.0, 45.0, 85.0]:
					Cam.set_orbit(_camera, azimuth, elevation, true)
					var where: String = "%s %s az %s el %s" % [id, size, azimuth, elevation]
					var pivot: Vector3 = Cam.pivot(_camera)
					(
						assert_bool(_camera.is_position_behind(pivot))
						. override_failure_message("pivot behind the camera at %s" % where)
						. is_false()
					)
					var screen: Vector2 = _camera.unproject_position(pivot)
					var inside: bool = (
						screen.x >= 0.0
						and screen.x <= size.x
						and screen.y >= 0.0
						and screen.y <= size.y
					)
					(
						assert_bool(inside)
						. override_failure_message(
							"pivot at %s is outside the viewport at %s" % [screen, where]
						)
						. is_true()
					)
					(
						assert_bool(_camera.is_position_in_frustum(tank.get_center()))
						. override_failure_message("tank centre outside the frustum at %s" % where)
						. is_true()
					)


# --- AC 9: the left mouse button does nothing ---


func test_ac09_a_left_button_drag_does_not_move_the_camera() -> void:
	if not await _open():
		return
	var az: float = Cam.t_az(_camera)
	var el: float = Cam.t_el(_camera)
	var before: Vector3 = _camera.global_position
	Cam.button(_viewport, MOUSE_BUTTON_LEFT, true)
	assert_bool(Cam.dragging(_camera)).is_false()
	Cam.motion(_viewport, Vector2(300.0, 200.0), Vector2(400.0, 300.0), MOUSE_BUTTON_MASK_LEFT)
	Cam.motion(_viewport, Vector2(-900.0, -500.0), Vector2(0.0, 0.0), MOUSE_BUTTON_MASK_LEFT)
	Cam.button(_viewport, MOUSE_BUTTON_LEFT, false)
	Cam.step(_camera, 1.0)
	assert_float(Cam.t_az(_camera)).is_equal(az)
	assert_float(Cam.t_el(_camera)).is_equal(el)
	assert_vector(_camera.global_position).is_equal_approx(before, Vector3.ONE * 0.0001)


func test_ac09_a_middle_button_drag_does_not_move_the_camera() -> void:
	if not await _open():
		return
	var az: float = Cam.t_az(_camera)
	Cam.button(_viewport, MOUSE_BUTTON_MIDDLE, true)
	Cam.motion(_viewport, Vector2(300.0, 200.0), Vector2(400.0, 300.0), MOUSE_BUTTON_MASK_MIDDLE)
	Cam.button(_viewport, MOUSE_BUTTON_MIDDLE, false)
	assert_float(Cam.t_az(_camera)).is_equal(az)


func test_ac09_moving_the_mouse_without_a_button_does_not_move_the_camera() -> void:
	if not await _open():
		return
	var az: float = Cam.t_az(_camera)
	var el: float = Cam.t_el(_camera)
	Cam.motion(_viewport, Vector2(300.0, 200.0), Vector2(400.0, 300.0), 0)
	assert_float(Cam.t_az(_camera)).is_equal(az)
	assert_float(Cam.t_el(_camera)).is_equal(el)


# --- AC 13: a drag ends when the button is released anywhere or the window loses focus ---


func test_ac13_the_drag_state_follows_the_right_button() -> void:
	if not await _open():
		return
	assert_bool(Cam.dragging(_camera)).is_false()
	Cam.right_press(_viewport)
	assert_bool(Cam.dragging(_camera)).is_true()
	Cam.right_release(_viewport)
	assert_bool(Cam.dragging(_camera)).is_false()


func test_ac13_a_release_outside_the_viewport_ends_the_drag() -> void:
	if not await _open():
		return
	Cam.right_press(_viewport, Vector2(600.0, 300.0))
	Cam.motion(_viewport, Vector2(20.0, 0.0), Vector2(620.0, 300.0))
	assert_bool(Cam.dragging(_camera)).is_true()
	var outside: Vector2 = Vector2(-300.0, -200.0)
	Cam.right_release(_viewport, outside)
	assert_bool(Cam.dragging(_camera)).is_false()
	var az: float = Cam.t_az(_camera)
	var el: float = Cam.t_el(_camera)
	Cam.motion(_viewport, Vector2(200.0, 100.0), Vector2(500.0, 400.0))
	assert_float(Cam.t_az(_camera)).is_equal(az)
	assert_float(Cam.t_el(_camera)).is_equal(el)


func test_ac13_a_drag_that_leaves_the_viewport_keeps_orbiting_until_the_release() -> void:
	if not await _open():
		return
	Cam.right_press(_viewport, Vector2(600.0, 300.0))
	var before: float = Cam.t_az(_camera)
	Cam.motion(_viewport, Vector2(40.0, 0.0), Vector2(2000.0, 300.0))
	assert_float(absf(Cam.t_az(_camera) - before)).is_equal_approx(10.0, Cam.ANGLE_TOLERANCE_DEG)
	Cam.right_release(_viewport, Vector2(2000.0, 300.0))


func test_ac13_losing_the_application_focus_ends_the_drag() -> void:
	if not await _open():
		return
	Cam.right_press(_viewport)
	Cam.motion(_viewport, Vector2(40.0, 0.0))
	assert_bool(Cam.dragging(_camera)).is_true()
	_camera.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_bool(Cam.dragging(_camera)).is_false()
	var az: float = Cam.t_az(_camera)
	Cam.motion(_viewport, Vector2(200.0, 100.0))
	assert_float(Cam.t_az(_camera)).is_equal(az)


func test_ac13_losing_the_window_focus_ends_the_drag() -> void:
	if not await _open():
		return
	Cam.right_press(_viewport)
	Cam.motion(_viewport, Vector2(40.0, 0.0))
	_camera.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	assert_bool(Cam.dragging(_camera)).is_false()
	var el: float = Cam.t_el(_camera)
	Cam.motion(_viewport, Vector2(0.0, 100.0))
	assert_float(Cam.t_el(_camera)).is_equal(el)


func test_ac13_a_new_drag_works_after_a_focus_loss() -> void:
	if not await _open():
		return
	Cam.right_press(_viewport)
	_camera.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	Cam.drag(_viewport, Vector2(0.0, 20.0))
	assert_float(Cam.t_el(_camera)).is_equal_approx(0.0, Cam.ANGLE_TOLERANCE_DEG)


# --- AC 15: a resize changes nothing of the orbit ---


func test_ac15_resizing_the_window_keeps_azimuth_elevation_distance_and_pivot() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		Cam.set_orbit(_camera, 130.0, 20.0, true)
		var az: float = Cam.az(_camera)
		var el: float = Cam.el(_camera)
		var dist: float = Cam.dist(_camera)
		var pivot: Vector3 = Cam.pivot(_camera)
		for size: Vector2i in [Cam.SIZE_4_3, Cam.SIZE_21_9, Vector2i(800, 1200), Cam.SIZE_16_9]:
			_viewport.size = size
			await get_tree().process_frame
			await get_tree().process_frame
			Cam.step(_camera, 0.5)
			assert_float(Cam.az(_camera)).is_equal_approx(az, Cam.ANGLE_TOLERANCE_DEG)
			assert_float(Cam.el(_camera)).is_equal_approx(el, Cam.ANGLE_TOLERANCE_DEG)
			assert_float(Cam.dist(_camera)).is_equal_approx(dist, Cam.LENGTH_TOLERANCE_M)
			assert_vector(Cam.pivot(_camera)).is_equal_approx(pivot, Vector3.ONE * 0.001)
			assert_float(Cam.t_az(_camera)).is_equal_approx(az, Cam.ANGLE_TOLERANCE_DEG)
			assert_float(Cam.t_el(_camera)).is_equal_approx(el, Cam.ANGLE_TOLERANCE_DEG)
			var screen: Vector2 = _camera.unproject_position(Cam.pivot(_camera))
			assert_bool(Rect2(Vector2.ZERO, Vector2(size)).has_point(screen)).is_true()


# --- AC 16: a hitch changes nothing for a drag ---


func test_ac16_a_drag_gives_the_same_result_with_a_long_frame_in_between() -> void:
	if not await _open():
		return
	Cam.drag(_viewport, Vector2(160.0, 40.0))
	var short_az: float = Cam.t_az(_camera)
	var short_el: float = Cam.t_el(_camera)
	if not await _open():
		return
	Cam.right_press(_viewport)
	Cam.step(_camera, 0.5)
	Cam.motion(_viewport, Vector2(160.0, 40.0), Vector2(260.0, 140.0))
	Cam.step(_camera, 0.5)
	Cam.right_release(_viewport, Vector2(260.0, 140.0))
	assert_float(Cam.t_az(_camera)).is_equal_approx(short_az, Cam.ANGLE_TOLERANCE_DEG)
	assert_float(Cam.t_el(_camera)).is_equal_approx(short_el, Cam.ANGLE_TOLERANCE_DEG)


func test_ac16_one_big_motion_equals_the_same_pixels_in_many_small_ones() -> void:
	if not await _open():
		return
	Cam.drag(_viewport, Vector2(200.0, -30.0))
	var big_az: float = Cam.t_az(_camera)
	var big_el: float = Cam.t_el(_camera)
	if not await _open():
		return
	Cam.right_press(_viewport)
	for index: int in 20:
		Cam.motion(_viewport, Vector2(10.0, -1.5))
		Cam.step(_camera, 0.1)
	Cam.right_release(_viewport)
	assert_float(Cam.t_az(_camera)).is_equal_approx(big_az, Cam.ANGLE_TOLERANCE_DEG)
	assert_float(Cam.t_el(_camera)).is_equal_approx(big_el, Cam.ANGLE_TOLERANCE_DEG)
