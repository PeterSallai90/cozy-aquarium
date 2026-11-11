# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #26 criteria 1, 2, 4, 5 and 8 (owner: developer): the pure zoom, pan and Home maths of
## CameraMoves (game/systems/camera/camera_moves.gd), unit-tested without a scene. The signatures
## are the ones of the technical plan.

const Cz := preload("res://tests/helpers/camera_zoom_rig.gd")
const OrbitApi := preload("res://tests/helpers/orbit_api.gd")

const STEP := 0.9
const TOLERANCE := 0.0001
const WIDE := 16.0 / 9.0


func _exists() -> bool:
	(
		assert_bool(Cz.moves_exist())
		. override_failure_message("%s is missing" % Cz.MOVES_PATH)
		. is_true()
	)
	return Cz.moves_exist()


func _camera_axes(azimuth: float, elevation: float) -> Basis:
	return Basis.from_euler(OrbitApi.camera_rotation(azimuth, elevation), EULER_ORDER_YXZ)


# --- AC 1: the zoom multiplier ---


func test_ac01_one_notch_multiplies_by_the_step_factor() -> void:
	if not _exists():
		return
	assert_float(Cz.zoom_multiplier(STEP, 1.0)).is_equal_approx(STEP, TOLERANCE)


func test_ac01_zooming_out_multiplies_by_one_over_the_step_factor() -> void:
	if not _exists():
		return
	assert_float(Cz.zoom_multiplier(1.0 / STEP, 1.0)).is_equal_approx(1.0 / STEP, TOLERANCE)


func test_ac01_a_fractional_event_uses_the_step_factor_to_the_power_of_the_factor() -> void:
	if not _exists():
		return
	assert_float(Cz.zoom_multiplier(STEP, 0.5)).is_equal_approx(pow(STEP, 0.5), TOLERANCE)
	assert_float(Cz.zoom_multiplier(STEP, 2.0)).is_equal_approx(STEP * STEP, TOLERANCE)
	assert_float(Cz.zoom_multiplier(1.0 / STEP, 0.5)).is_equal_approx(
		pow(1.0 / STEP, 0.5), TOLERANCE
	)


func test_ac01_a_factor_of_zero_counts_as_one() -> void:
	if not _exists():
		return
	assert_float(Cz.zoom_multiplier(STEP, 0.0)).is_equal_approx(STEP, TOLERANCE)
	assert_float(Cz.zoom_multiplier(1.0 / STEP, 0.0)).is_equal_approx(1.0 / STEP, TOLERANCE)


func test_ac01_a_negative_factor_counts_as_one() -> void:
	if not _exists():
		return
	assert_float(Cz.zoom_multiplier(STEP, -3.0)).is_equal_approx(STEP, TOLERANCE)


func test_ac01_n_notches_multiply_to_the_step_factor_to_the_power_of_n() -> void:
	if not _exists():
		return
	var distance: float = 1.0
	for notch: int in 5:
		distance *= Cz.zoom_multiplier(STEP, 1.0)
	assert_float(distance).is_equal_approx(pow(STEP, 5.0), TOLERANCE)


# --- AC 2: the distance clamp ---


func test_ac02_the_distance_is_kept_inside_the_limits() -> void:
	if not _exists():
		return
	var low: float = Cz.setting("zoom_min_factor")
	var high: float = Cz.setting("zoom_max_factor")
	assert_float(Cz.clamp_distance(1.0, 1.0, low, high)).is_equal_approx(1.0, TOLERANCE)
	assert_float(Cz.clamp_distance(1.5, 1.0, low, high)).is_equal_approx(1.5, TOLERANCE)
	assert_float(Cz.clamp_distance(0.1, 1.0, low, high)).is_equal_approx(low, TOLERANCE)
	assert_float(Cz.clamp_distance(9.0, 1.0, low, high)).is_equal_approx(high, TOLERANCE)


func test_ac02_the_limits_scale_with_the_default_distance() -> void:
	if not _exists():
		return
	assert_float(Cz.clamp_distance(0.0, 0.924, 0.6, 2.5)).is_equal_approx(0.924 * 0.6, TOLERANCE)
	assert_float(Cz.clamp_distance(100.0, 0.924, 0.6, 2.5)).is_equal_approx(0.924 * 2.5, TOLERANCE)


func test_ac02_zero_and_huge_values_stop_at_the_limits() -> void:
	if not _exists():
		return
	assert_float(Cz.clamp_distance(0.0, 2.0, 0.6, 2.5)).is_equal_approx(1.2, TOLERANCE)
	assert_float(Cz.clamp_distance(INF, 2.0, 0.6, 2.5)).is_equal_approx(5.0, TOLERANCE)
	var huge: float = Cz.zoom_multiplier(STEP, Cz.HUGE)
	assert_float(Cz.clamp_distance(2.0 * huge, 2.0, 0.6, 2.5)).is_equal_approx(1.2, TOLERANCE)
	var out: float = Cz.zoom_multiplier(1.0 / STEP, Cz.HUGE)
	assert_float(Cz.clamp_distance(2.0 * out, 2.0, 0.6, 2.5)).is_equal_approx(5.0, TOLERANCE)


# --- AC 4: the vertical field of view ---


func test_ac04_tan_half_vertical_fov_at_16_9_with_keep_width_is_0_2623() -> void:
	if not _exists():
		return
	var value: float = Cz.tan_half_vfov(50.0, Camera3D.KEEP_WIDTH, WIDE)
	assert_float(value).is_equal_approx(tan(deg_to_rad(25.0)) * 9.0 / 16.0, TOLERANCE)
	assert_float(value).is_equal_approx(0.2623, 0.0001)


func test_ac04_tan_half_vertical_fov_with_keep_height_is_the_half_angle_itself() -> void:
	if not _exists():
		return
	var value: float = Cz.tan_half_vfov(40.0, Camera3D.KEEP_HEIGHT, 2.4)
	assert_float(value).is_equal_approx(tan(deg_to_rad(20.0)), TOLERANCE)


func test_ac04_keep_width_gets_smaller_with_a_wider_aspect() -> void:
	if not _exists():
		return
	var narrow: float = Cz.tan_half_vfov(50.0, Camera3D.KEEP_WIDTH, 4.0 / 3.0)
	var wide: float = Cz.tan_half_vfov(50.0, Camera3D.KEEP_WIDTH, WIDE)
	assert_float(narrow).is_greater(wide)
	assert_float(narrow).is_equal_approx(tan(deg_to_rad(25.0)) * 3.0 / 4.0, TOLERANCE)


# --- AC 4: the pan offset ---


func test_ac04_a_drag_to_the_right_moves_the_pivot_along_minus_camera_right() -> void:
	if not _exists():
		return
	var offset: Vector3 = Cz.pan_offset(Vector2(36.0, 0.0), 720.0, 1.0, 0.2623, 1.0, 0.0, 0.0)
	assert_float(offset.x).is_equal_approx(-0.05 * 2.0 * 0.2623, TOLERANCE)
	assert_float(offset.y).is_equal_approx(0.0, TOLERANCE)
	assert_float(offset.z).is_equal_approx(0.0, TOLERANCE)


func test_ac04_a_drag_down_moves_the_pivot_along_plus_camera_up() -> void:
	if not _exists():
		return
	var offset: Vector3 = Cz.pan_offset(Vector2(0.0, 36.0), 720.0, 1.0, 0.2623, 1.0, 0.0, 0.0)
	assert_float(offset.y).is_equal_approx(0.05 * 2.0 * 0.2623, TOLERANCE)
	assert_float(offset.x).is_equal_approx(0.0, TOLERANCE)


func test_ac04_the_offset_follows_the_camera_basis_at_any_azimuth_and_elevation() -> void:
	if not _exists():
		return
	var relative: Vector2 = Vector2(25.0, -14.0)
	for azimuth: float in [0.0, 90.0, 215.0, -60.0, 750.0]:
		for elevation: float in [-5.0, 5.0, 30.0, 85.0]:
			var axes: Basis = _camera_axes(azimuth, elevation)
			var scale_x: float = relative.x / 720.0 * 2.0 * 0.8 * 0.2623 * 1.5
			var scale_y: float = relative.y / 720.0 * 2.0 * 0.8 * 0.2623 * 1.5
			var expected: Vector3 = -axes.x * scale_x + axes.y * scale_y
			var offset: Vector3 = Cz.pan_offset(
				relative, 720.0, 0.8, 0.2623, 1.5, azimuth, elevation
			)
			assert_vector(offset).is_equal_approx(expected, Vector3.ONE * TOLERANCE)


func test_ac04_the_offset_is_proportional_to_the_distance() -> void:
	if not _exists():
		return
	var low: float = Cz.setting("zoom_min_factor")
	var high: float = Cz.setting("zoom_max_factor")
	var near: Vector3 = Cz.pan_offset(Vector2(30.0, 20.0), 720.0, low, 0.2623, 1.0, 40.0, 10.0)
	var far: Vector3 = Cz.pan_offset(Vector2(30.0, 20.0), 720.0, high, 0.2623, 1.0, 40.0, 10.0)
	assert_float(near.length() / far.length()).is_equal_approx(low / high, TOLERANCE)


func test_ac04_the_offset_is_proportional_to_the_pan_speed() -> void:
	if not _exists():
		return
	var base: Vector3 = Cz.pan_offset(Vector2(30.0, 20.0), 720.0, 1.0, 0.2623, 1.0, 40.0, 10.0)
	var fast: Vector3 = Cz.pan_offset(Vector2(30.0, 20.0), 720.0, 1.0, 0.2623, 2.0, 40.0, 10.0)
	assert_vector(fast).is_equal_approx(base * 2.0, Vector3.ONE * TOLERANCE)


func test_ac04_the_offset_is_pixels_over_the_viewport_height() -> void:
	if not _exists():
		return
	var small: Vector3 = Cz.pan_offset(Vector2(30.0, 0.0), 720.0, 1.0, 0.2623, 1.0, 0.0, 0.0)
	var tall: Vector3 = Cz.pan_offset(Vector2(30.0, 0.0), 1440.0, 1.0, 0.2623, 1.0, 0.0, 0.0)
	assert_vector(small).is_equal_approx(tall * 2.0, Vector3.ONE * TOLERANCE)


func test_ac04_a_viewport_height_of_zero_gives_no_movement() -> void:
	if not _exists():
		return
	var offset: Vector3 = Cz.pan_offset(Vector2(30.0, 20.0), 0.0, 1.0, 0.2623, 1.0, 0.0, 0.0)
	assert_vector(offset).is_equal_approx(Vector3.ZERO, Vector3.ONE * TOLERANCE)


# --- AC 5: the per-axis clamp ---


func test_ac05_a_pivot_inside_the_box_is_kept() -> void:
	if not _exists():
		return
	var box: AABB = AABB(Vector3(-1.0, 2.0, -3.0), Vector3(2.0, 1.0, 4.0))
	var inside: Vector3 = Vector3(0.5, 2.5, 0.0)
	assert_vector(Cz.clamp_pivot(inside, box)).is_equal_approx(inside, Vector3.ONE * TOLERANCE)


func test_ac05_each_axis_is_clamped_on_its_own_so_the_pivot_slides_along_an_edge() -> void:
	if not _exists():
		return
	var box: AABB = AABB(Vector3(-1.0, 2.0, -3.0), Vector3(2.0, 1.0, 4.0))
	var slid: Vector3 = Cz.clamp_pivot(Vector3(5.0, 2.5, 0.25), box)
	assert_vector(slid).is_equal_approx(Vector3(1.0, 2.5, 0.25), Vector3.ONE * TOLERANCE)
	var other: Vector3 = Cz.clamp_pivot(Vector3(0.0, 9.0, 0.25), box)
	assert_vector(other).is_equal_approx(Vector3(0.0, 3.0, 0.25), Vector3.ONE * TOLERANCE)


func test_ac05_a_pivot_far_outside_stops_at_the_corner() -> void:
	if not _exists():
		return
	var box: AABB = AABB(Vector3(-1.0, 2.0, -3.0), Vector3(2.0, 1.0, 4.0))
	var corner: Vector3 = Cz.clamp_pivot(Vector3(-Cz.HUGE, Cz.HUGE, Cz.HUGE), box)
	assert_vector(corner).is_equal_approx(Vector3(-1.0, 3.0, 1.0), Vector3.ONE * TOLERANCE)
	var back: Vector3 = Cz.clamp_pivot(Vector3(Cz.HUGE, -Cz.HUGE, -Cz.HUGE), box)
	assert_vector(back).is_equal_approx(Vector3(1.0, 2.0, -3.0), Vector3.ONE * TOLERANCE)


func test_ac05_a_collapsed_box_pins_the_pivot_to_its_point() -> void:
	if not _exists():
		return
	var point: Vector3 = Vector3(0.0, 0.95, 0.0)
	var box: AABB = AABB(point, Vector3.ZERO)
	assert_vector(Cz.clamp_pivot(Vector3(3.0, -2.0, 1.0), box)).is_equal_approx(
		point, Vector3.ONE * TOLERANCE
	)


# --- AC 8: the Home azimuth ---


func test_ac08_home_azimuth_750_goes_to_720() -> void:
	if not _exists():
		return
	assert_float(Cz.home_azimuth(750.0)).is_equal_approx(720.0, TOLERANCE)


func test_ac08_home_azimuth_at_an_exact_tie_goes_to_the_higher_multiple() -> void:
	if not _exists():
		return
	assert_float(Cz.home_azimuth(540.0)).is_equal_approx(720.0, TOLERANCE)
	assert_float(Cz.home_azimuth(180.0)).is_equal_approx(360.0, TOLERANCE)
	assert_float(Cz.home_azimuth(-180.0)).is_equal_approx(0.0, TOLERANCE)


func test_ac08_home_azimuth_keeps_multiples_of_360_and_is_not_wrapped() -> void:
	if not _exists():
		return
	assert_float(Cz.home_azimuth(0.0)).is_equal_approx(0.0, TOLERANCE)
	assert_float(Cz.home_azimuth(360.0)).is_equal_approx(360.0, TOLERANCE)
	assert_float(Cz.home_azimuth(-360.0)).is_equal_approx(-360.0, TOLERANCE)
	assert_float(Cz.home_azimuth(1085.0)).is_equal_approx(1080.0, TOLERANCE)
	assert_float(Cz.home_azimuth(-725.0)).is_equal_approx(-720.0, TOLERANCE)


func test_ac08_home_azimuth_just_below_the_tie_goes_down() -> void:
	if not _exists():
		return
	assert_float(Cz.home_azimuth(179.9)).is_equal_approx(0.0, TOLERANCE)
	assert_float(Cz.home_azimuth(180.1)).is_equal_approx(360.0, TOLERANCE)
