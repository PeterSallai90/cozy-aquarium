# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #25 criteria 5, 6, 12 (modifier part), 14 and 16 (key repeat part) (owner: developer): Q/E and
## R/F on the build camera. Presses come from synthetic events pushed through the viewport; time
## comes from BuildCamera.step(delta) with fixed frame times. Convention (technical plan, ADR 0008):
## E turns clockwise seen from above and subtracts the step from the unwrapped target azimuth, Q
## adds it; R raises and F lowers the target elevation by 5 degrees. Repeat: the first step fires on
## key-down; then one step per interval (0.25 s) of frame time capped at 0.1 s per frame, never
## more than one step per frame; echo events are ignored.

const Room := preload("res://tests/helpers/room_rig.gd")
const Cam := preload("res://tests/helpers/camera_rig.gd")
const Table := preload("res://tests/helpers/tank_table.gd")
const OrbitApi := preload("res://tests/helpers/orbit_api.gd")

const STEP_AZ := 45.0
const STEP_EL := 5.0
const HUGE := 1000000.0

var _viewport: SubViewport = null
var _room: Node3D = null
var _camera: Camera3D = null


func _open(id: StringName = Table.MEDIUM) -> bool:
	(
		assert_bool(ResourceLoader.exists(Room.ROOM_SCENE))
		. override_failure_message("room scene missing: %s" % Room.ROOM_SCENE)
		. is_true()
	)
	var rig: Dictionary = await Cam.open(self, Room.model_with(id))
	_viewport = rig["viewport"]
	_room = rig["room"]
	_camera = Cam.camera_of(_room)
	(
		assert_bool(_camera != null)
		. override_failure_message("the room has no BuildCamera child (Camera3D)")
		. is_true()
	)
	return _camera != null


func _press(keycode: Key) -> void:
	Cam.key(_viewport, keycode, true)


func _release(keycode: Key) -> void:
	Cam.key(_viewport, keycode, false)


## The whole number of azimuth steps the target has taken from `start`.
func _az_steps(start: float) -> float:
	return (Cam.t_az(_camera) - start) / STEP_AZ


# --- AC 5: Q and E ---


func test_ac05_e_turns_the_target_45_degrees_clockwise_seen_from_above() -> void:
	if not await _open():
		return
	var start: float = Cam.t_az(_camera)
	_press(KEY_E)
	assert_float(Cam.t_az(_camera)).is_equal_approx(start - STEP_AZ, Cam.ANGLE_TOLERANCE_DEG)
	_release(KEY_E)
	Cam.settle(_camera)
	assert_float(Cam.az(_camera)).is_equal_approx(start - STEP_AZ, Cam.ANGLE_TOLERANCE_DEG)
	# Clockwise from the front, seen from above, the camera ends up on the left of the tank.
	assert_float(_camera.global_position.x).is_less(Cam.pivot(_camera).x - 0.1)


func test_ac05_q_turns_the_target_45_degrees_counter_clockwise_seen_from_above() -> void:
	if not await _open():
		return
	var start: float = Cam.t_az(_camera)
	_press(KEY_Q)
	assert_float(Cam.t_az(_camera)).is_equal_approx(start + STEP_AZ, Cam.ANGLE_TOLERANCE_DEG)
	_release(KEY_Q)
	Cam.settle(_camera)
	assert_float(_camera.global_position.x).is_greater(Cam.pivot(_camera).x + 0.1)


func test_ac05_the_view_eases_to_the_new_target_and_does_not_jump() -> void:
	if not await _open():
		return
	var start: float = Cam.az(_camera)
	Cam.tap(_viewport, KEY_E)
	assert_float(Cam.az(_camera)).is_equal_approx(start, Cam.ANGLE_TOLERANCE_DEG)
	Cam.step(_camera, Cam.FRAME_S)
	assert_float(Cam.az(_camera)).is_less(start)
	assert_float(Cam.az(_camera)).is_greater(start - STEP_AZ)
	Cam.settle(_camera)
	assert_float(Cam.az(_camera)).is_equal_approx(start - STEP_AZ, Cam.ANGLE_TOLERANCE_DEG)


func test_ac05_eight_presses_before_damping_settles_make_a_full_turn() -> void:
	if not await _open():
		return
	var start: float = Cam.t_az(_camera)
	var start_position: Vector3 = _camera.global_position
	for index: int in 8:
		Cam.tap(_viewport, KEY_E)
	assert_float(Cam.t_az(_camera)).is_equal_approx(start - 360.0, Cam.ANGLE_TOLERANCE_DEG)
	Cam.settle(_camera)
	assert_float(Cam.az(_camera)).is_equal_approx(start - 360.0, Cam.ANGLE_TOLERANCE_DEG)
	assert_vector(_camera.global_position).is_equal_approx(start_position, Vector3.ONE * 0.001)
	assert_float(Cam.heading_gap(Cam.az(_camera), start)).is_less(Cam.ANGLE_TOLERANCE_DEG)


func test_ac05_two_presses_make_a_quarter_turn() -> void:
	if not await _open():
		return
	var start: float = Cam.t_az(_camera)
	Cam.tap(_viewport, KEY_E)
	Cam.tap(_viewport, KEY_E)
	assert_float(Cam.t_az(_camera)).is_equal_approx(start - 90.0, Cam.ANGLE_TOLERANCE_DEG)
	Cam.tap(_viewport, KEY_Q)
	Cam.tap(_viewport, KEY_Q)
	Cam.tap(_viewport, KEY_Q)
	assert_float(Cam.t_az(_camera)).is_equal_approx(start + 45.0, Cam.ANGLE_TOLERANCE_DEG)


func test_ac05_presses_while_the_view_is_still_easing_add_to_the_target() -> void:
	if not await _open():
		return
	var start: float = Cam.t_az(_camera)
	Cam.tap(_viewport, KEY_Q)
	Cam.step(_camera, Cam.FRAME_S)
	Cam.tap(_viewport, KEY_Q)
	Cam.step(_camera, Cam.FRAME_S)
	Cam.tap(_viewport, KEY_Q)
	assert_float(Cam.t_az(_camera)).is_equal_approx(start + 3.0 * STEP_AZ, Cam.ANGLE_TOLERANCE_DEG)
	Cam.settle(_camera)
	assert_float(Cam.az(_camera)).is_equal_approx(start + 3.0 * STEP_AZ, Cam.ANGLE_TOLERANCE_DEG)


func test_ac05_a_key_step_keeps_distance_elevation_and_pivot() -> void:
	if not await _open():
		return
	var dist: float = Cam.dist(_camera)
	var el: float = Cam.el(_camera)
	var pivot: Vector3 = Cam.pivot(_camera)
	Cam.tap(_viewport, KEY_E)
	Cam.settle(_camera)
	assert_float(Cam.dist(_camera)).is_equal_approx(dist, Cam.LENGTH_TOLERANCE_M)
	assert_float(Cam.el(_camera)).is_equal_approx(el, Cam.ANGLE_TOLERANCE_DEG)
	assert_vector(Cam.pivot(_camera)).is_equal_approx(pivot, Vector3.ONE * 0.001)
	assert_float(_camera.global_position.distance_to(pivot)).is_equal_approx(
		dist, Cam.LENGTH_TOLERANCE_M
	)


func test_ac05_holding_e_fires_on_key_down_then_repeats_at_the_settings_interval() -> void:
	if not await _open():
		return
	var interval: float = OrbitApi.setting("key_repeat_interval_s")
	var start: float = Cam.t_az(_camera)
	_press(KEY_E)
	assert_float(_az_steps(start)).is_equal_approx(-1.0, 0.0001)
	# 12 frames of 0.08 s are 0.96 s: three more steps at an interval of 0.25 s.
	var frame: float = 0.08
	for index: int in 12:
		Cam.step(_camera, frame)
	var expected: float = 1.0 + floorf(12.0 * frame / interval)
	assert_float(_az_steps(start)).is_equal_approx(-expected, 0.0001)
	assert_float(expected).is_equal(4.0)


func test_ac05_a_step_does_not_repeat_before_one_interval_has_passed() -> void:
	if not await _open():
		return
	var start: float = Cam.t_az(_camera)
	_press(KEY_Q)
	Cam.step(_camera, 0.08)
	Cam.step(_camera, 0.08)
	assert_float(_az_steps(start)).is_equal_approx(1.0, 0.0001)
	Cam.step(_camera, 0.08)
	Cam.step(_camera, 0.08)
	assert_float(_az_steps(start)).is_equal_approx(2.0, 0.0001)


func test_ac05_releasing_the_key_stops_the_repeat() -> void:
	if not await _open():
		return
	var start: float = Cam.t_az(_camera)
	_press(KEY_E)
	Cam.step(_camera, 0.08)
	_release(KEY_E)
	Cam.step(_camera, 3.0)
	assert_float(_az_steps(start)).is_equal_approx(-1.0, 0.0001)


func test_ac05_a_new_press_after_a_release_fires_at_once() -> void:
	if not await _open():
		return
	var start: float = Cam.t_az(_camera)
	_press(KEY_E)
	Cam.step(_camera, 0.2)
	_release(KEY_E)
	_press(KEY_E)
	assert_float(_az_steps(start)).is_equal_approx(-2.0, 0.0001)


func test_ac05_os_key_echo_events_are_ignored() -> void:
	if not await _open():
		return
	var start: float = Cam.t_az(_camera)
	_press(KEY_E)
	for index: int in 6:
		Cam.key(_viewport, KEY_E, true, true)
	assert_float(_az_steps(start)).is_equal_approx(-1.0, 0.0001)
	Cam.step(_camera, 0.01)
	assert_float(_az_steps(start)).is_equal_approx(-1.0, 0.0001)


func test_ac05_a_lone_echo_event_without_a_press_does_nothing() -> void:
	if not await _open():
		return
	var start: float = Cam.t_az(_camera)
	Cam.key(_viewport, KEY_E, true, true)
	Cam.key(_viewport, KEY_Q, true, true)
	Cam.step(_camera, 1.0)
	assert_float(_az_steps(start)).is_equal_approx(0.0, 0.0001)


func test_ac05_a_long_frame_fires_no_extra_step() -> void:
	if not await _open():
		return
	var start: float = Cam.t_az(_camera)
	_press(KEY_E)
	# One hitch of 10 s counts as 0.1 s (cap), which is less than the 0.25 s interval.
	Cam.step(_camera, 10.0, 10.0)
	assert_float(_az_steps(start)).is_equal_approx(-1.0, 0.0001)


func test_ac05_four_long_frames_fire_one_repeat_not_one_per_frame() -> void:
	if not await _open():
		return
	var start: float = Cam.t_az(_camera)
	_press(KEY_E)
	for index: int in 4:
		Cam.step(_camera, 0.5, 0.5)
	# The capped time is 4 x 0.1 s = 0.4 s: one repeat after the first step.
	assert_float(_az_steps(start)).is_equal_approx(-2.0, 0.0001)


func test_ac05_a_key_that_is_not_bound_does_nothing() -> void:
	if not await _open():
		return
	var start: float = Cam.t_az(_camera)
	var el: float = Cam.t_el(_camera)
	for keycode: Key in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_T, KEY_SPACE]:
		Cam.tap(_viewport, keycode)
	assert_float(Cam.t_az(_camera)).is_equal(start)
	assert_float(Cam.t_el(_camera)).is_equal(el)


# --- AC 6: R and F ---


func test_ac06_r_raises_and_f_lowers_the_target_elevation_by_5_degrees() -> void:
	if not await _open():
		return
	var start: float = Cam.t_el(_camera)
	_press(KEY_R)
	assert_float(Cam.t_el(_camera)).is_equal_approx(start + STEP_EL, Cam.ANGLE_TOLERANCE_DEG)
	_release(KEY_R)
	Cam.tap(_viewport, KEY_F)
	Cam.tap(_viewport, KEY_F)
	assert_float(Cam.t_el(_camera)).is_equal_approx(start - STEP_EL, Cam.ANGLE_TOLERANCE_DEG)
	Cam.settle(_camera)
	assert_float(Cam.el(_camera)).is_equal_approx(start - STEP_EL, Cam.ANGLE_TOLERANCE_DEG)


func test_ac06_presses_accumulate_on_the_target_while_the_view_eases() -> void:
	if not await _open():
		return
	var start: float = Cam.t_el(_camera)
	Cam.tap(_viewport, KEY_R)
	Cam.step(_camera, Cam.FRAME_S)
	Cam.tap(_viewport, KEY_R)
	Cam.tap(_viewport, KEY_R)
	assert_float(Cam.t_el(_camera)).is_equal_approx(start + 15.0, Cam.ANGLE_TOLERANCE_DEG)
	assert_float(Cam.el(_camera)).is_less(start + 15.0)


func test_ac06_holding_r_repeats_at_the_settings_interval() -> void:
	if not await _open():
		return
	var start: float = Cam.t_el(_camera)
	_press(KEY_R)
	for index: int in 12:
		Cam.step(_camera, 0.08)
	assert_float(Cam.t_el(_camera)).is_equal_approx(start + 4.0 * STEP_EL, Cam.ANGLE_TOLERANCE_DEG)


func test_ac06_os_key_echo_events_are_ignored_for_r_and_f() -> void:
	if not await _open():
		return
	var start: float = Cam.t_el(_camera)
	_press(KEY_R)
	for index: int in 5:
		Cam.key(_viewport, KEY_R, true, true)
	Cam.key(_viewport, KEY_F, true, true)
	assert_float(Cam.t_el(_camera)).is_equal_approx(start + STEP_EL, Cam.ANGLE_TOLERANCE_DEG)


func test_ac06_holding_r_stops_at_85_degrees() -> void:
	if not await _open():
		return
	Cam.set_orbit(_camera, 0.0, 70.0, true)
	_press(KEY_R)
	for index: int in 60:
		Cam.step(_camera, 0.05)
		assert_float(Cam.t_el(_camera)).is_less_equal(Cam.MAX_ELEVATION_DEG + 0.01)
	assert_float(Cam.t_el(_camera)).is_equal_approx(Cam.MAX_ELEVATION_DEG, 0.01)
	Cam.settle(_camera)
	assert_float(Cam.el(_camera)).is_equal_approx(Cam.MAX_ELEVATION_DEG, 0.01)


func test_ac06_a_press_at_85_degrees_stays_at_85_degrees() -> void:
	if not await _open():
		return
	Cam.set_orbit(_camera, 0.0, 85.0, true)
	Cam.tap(_viewport, KEY_R)
	assert_float(Cam.t_el(_camera)).is_equal_approx(Cam.MAX_ELEVATION_DEG, 0.01)


func test_ac06_holding_r_after_long_frames_does_not_pass_85_degrees() -> void:
	if not await _open():
		return
	Cam.set_orbit(_camera, 0.0, 80.0, true)
	_press(KEY_R)
	for index: int in 10:
		Cam.step(_camera, 5.0, 5.0)
		assert_float(Cam.t_el(_camera)).is_less_equal(Cam.MAX_ELEVATION_DEG + 0.01)


func test_ac06_holding_f_stops_at_the_lowest_elevation_of_every_tank() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		Cam.set_orbit(_camera, 0.0, 0.0, true)
		var lowest: float = Cam.min_el(_camera, id)
		_press(KEY_F)
		for index: int in 60:
			Cam.step(_camera, 0.05)
			assert_float(Cam.t_el(_camera)).is_greater_equal(lowest - Cam.ANGLE_TOLERANCE_DEG)
			assert_float(_camera.global_position.y).is_greater_equal(
				Cam.CABINET_TOP_M - Cam.LENGTH_TOLERANCE_M
			)
		assert_float(Cam.t_el(_camera)).is_equal_approx(lowest, Cam.ANGLE_TOLERANCE_DEG)
		_release(KEY_F)


func test_ac06_holding_f_after_long_frames_does_not_pass_the_lowest_elevation() -> void:
	if not await _open(Table.LARGE):
		return
	var lowest: float = Cam.min_el(_camera, Table.LARGE)
	_press(KEY_F)
	for index: int in 10:
		Cam.step(_camera, 5.0, 5.0)
		assert_float(Cam.t_el(_camera)).is_greater_equal(lowest - Cam.ANGLE_TOLERANCE_DEG)
	assert_float(Cam.t_el(_camera)).is_equal_approx(lowest, Cam.ANGLE_TOLERANCE_DEG)


func test_ac06_a_single_step_down_near_the_lowest_elevation_clamps_to_it() -> void:
	if not await _open(Table.LARGE):
		return
	var lowest: float = Cam.min_el(_camera, Table.LARGE)
	Cam.set_orbit(_camera, 0.0, lowest + 2.0, true)
	Cam.tap(_viewport, KEY_F)
	assert_float(Cam.t_el(_camera)).is_equal_approx(lowest, Cam.ANGLE_TOLERANCE_DEG)


# --- AC 12: keys with a modifier never orbit ---


func test_ac12_keys_with_ctrl_shift_alt_or_meta_do_not_move_the_camera() -> void:
	if not await _open():
		return
	var az: float = Cam.t_az(_camera)
	var el: float = Cam.t_el(_camera)
	var cases: Array[Array] = [
		[KEY_Q, KEY_MASK_CTRL],
		[KEY_E, KEY_MASK_SHIFT],
		[KEY_R, KEY_MASK_ALT],
		[KEY_F, KEY_MASK_META],
		[KEY_E, KEY_MASK_CTRL | KEY_MASK_SHIFT],
		[KEY_Q, KEY_MASK_ALT | KEY_MASK_SHIFT],
	]
	for pair: Array in cases:
		Cam.tap(_viewport, pair[0], pair[1])
		Cam.key(_viewport, pair[0], true, false, pair[1])
		Cam.step(_camera, 1.0)
		Cam.key(_viewport, pair[0], false, false, pair[1])
	assert_float(Cam.t_az(_camera)).is_equal(az)
	assert_float(Cam.t_el(_camera)).is_equal(el)


func test_ac12_a_plain_press_still_works_after_the_modified_ones() -> void:
	if not await _open():
		return
	var az: float = Cam.t_az(_camera)
	Cam.tap(_viewport, KEY_E, KEY_MASK_CTRL)
	Cam.tap(_viewport, KEY_E)
	assert_float(Cam.t_az(_camera)).is_equal_approx(az - STEP_AZ, Cam.ANGLE_TOLERANCE_DEG)


func test_ac12_a_modifier_pressed_while_the_key_is_held_does_not_add_steps() -> void:
	if not await _open():
		return
	var az: float = Cam.t_az(_camera)
	_press(KEY_E)
	Cam.key(_viewport, KEY_E, true, false, KEY_MASK_CTRL)
	assert_float(Cam.t_az(_camera)).is_equal_approx(az - STEP_AZ, Cam.ANGLE_TOLERANCE_DEG)


# --- AC 13 (keys): losing the focus releases held keys ---


func test_ac13_losing_the_focus_while_a_key_is_held_stops_the_repeat() -> void:
	if not await _open():
		return
	var start: float = Cam.t_az(_camera)
	_press(KEY_E)
	Cam.step(_camera, 0.08)
	_camera.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	Cam.step(_camera, 3.0)
	assert_float(_az_steps(start)).is_equal_approx(-1.0, 0.0001)


func test_ac13_a_key_released_outside_the_window_is_not_stuck() -> void:
	if not await _open():
		return
	var start: float = Cam.t_az(_camera)
	_press(KEY_E)
	_camera.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	# The release arrives while the window is not focused and is lost; a later press starts clean.
	Cam.step(_camera, 3.0)
	Cam.tap(_viewport, KEY_E)
	assert_float(_az_steps(start)).is_equal_approx(-2.0, 0.0001)


# --- AC 14: a drag and Q/E at the same time ---


func test_ac14_a_drag_and_a_key_step_both_apply_to_the_target() -> void:
	if not await _open():
		return
	var start: float = Cam.t_az(_camera)
	Cam.right_press(_viewport)
	Cam.motion(_viewport, Vector2(80.0, 0.0), Vector2(180.0, 100.0))
	var dragged: float = Cam.t_az(_camera) - start
	assert_float(absf(dragged)).is_equal_approx(20.0, Cam.ANGLE_TOLERANCE_DEG)
	_press(KEY_E)
	assert_float(Cam.t_az(_camera)).is_equal_approx(
		start + dragged - STEP_AZ, Cam.ANGLE_TOLERANCE_DEG
	)
	Cam.motion(_viewport, Vector2(80.0, 0.0), Vector2(260.0, 100.0))
	assert_float(Cam.t_az(_camera)).is_equal_approx(
		start + 2.0 * dragged - STEP_AZ, Cam.ANGLE_TOLERANCE_DEG
	)
	Cam.right_release(_viewport, Vector2(260.0, 100.0))
	_release(KEY_E)


func test_ac14_a_drag_up_and_r_together_are_clamped_at_85_degrees() -> void:
	if not await _open():
		return
	Cam.right_press(_viewport)
	Cam.motion(_viewport, Vector2(0.0, -HUGE), Vector2(100.0, -HUGE))
	assert_float(Cam.t_el(_camera)).is_equal_approx(Cam.MAX_ELEVATION_DEG, 0.01)
	Cam.tap(_viewport, KEY_R)
	assert_float(Cam.t_el(_camera)).is_equal_approx(Cam.MAX_ELEVATION_DEG, 0.01)
	Cam.tap(_viewport, KEY_E)
	Cam.motion(_viewport, Vector2(0.0, -HUGE), Vector2(100.0, -HUGE))
	assert_float(Cam.t_el(_camera)).is_equal_approx(Cam.MAX_ELEVATION_DEG, 0.01)
	Cam.right_release(_viewport)
	Cam.settle(_camera)
	assert_array(Array(Cam.basis_failures(_camera, Cam.pivot(_camera)))).is_empty()


func test_ac14_a_drag_down_and_f_together_are_clamped_at_the_lowest_elevation() -> void:
	if not await _open(Table.LARGE):
		return
	var lowest: float = Cam.min_el(_camera, Table.LARGE)
	Cam.right_press(_viewport)
	Cam.motion(_viewport, Vector2(0.0, HUGE), Vector2(100.0, HUGE))
	Cam.tap(_viewport, KEY_F)
	Cam.tap(_viewport, KEY_F)
	assert_float(Cam.t_el(_camera)).is_equal_approx(lowest, Cam.ANGLE_TOLERANCE_DEG)
	Cam.right_release(_viewport)
	Cam.settle(_camera)
	assert_float(_camera.global_position.y).is_greater_equal(
		Cam.CABINET_TOP_M - Cam.LENGTH_TOLERANCE_M
	)
