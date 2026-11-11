extends GdUnitTestSuite
## #25 criteria 1 to 4 (formula part), the damping, the drag conversion and the azimuth-0 link to
## CameraFraming (owner: developer). OrbitMath is pure and static; it is reached through OrbitApi
## because the class does not exist before the implementation.

const Api := preload("res://tests/helpers/late_api.gd")
const OrbitApi := preload("res://tests/helpers/orbit_api.gd")

const MEDIUM_ABOVE_M := 0.170
const SMALL_ABOVE_M := 0.129
const LARGE_ABOVE_M := 0.258
## The distance at which the large tank is limited by the cabinet floor and not by -10 degrees.
const LARGE_DEFAULT_DISTANCE_M := 1.489


func _math_exists() -> bool:
	(
		assert_bool(OrbitApi.math_exists())
		. override_failure_message("res://systems/camera/orbit_math.gd is missing")
		. is_true()
	)
	return OrbitApi.math_exists()


# --- AC 1 and 2: the lowest elevation ---


func test_ac01_the_limit_wins_when_the_cabinet_is_far_below() -> void:
	if not _math_exists():
		return
	assert_float(OrbitApi.min_elevation(-10.0, 0.17, 2.0)).is_equal_approx(-4.877, 0.01)
	assert_float(OrbitApi.min_elevation(-10.0, 0.17, 0.5)).is_equal_approx(-10.0, 0.01)


func test_ac01_the_small_and_medium_tank_stay_at_the_limit_at_the_default_distance() -> void:
	if not _math_exists():
		return
	for above: float in [SMALL_ABOVE_M, MEDIUM_ABOVE_M]:
		assert_float(OrbitApi.min_elevation(-10.0, above, 0.924)).is_equal_approx(-10.0, 0.01)


func test_ac01_the_large_tank_is_limited_by_the_cabinet_at_the_default_distance() -> void:
	if not _math_exists():
		return
	var expected: float = -rad_to_deg(asin(LARGE_ABOVE_M / LARGE_DEFAULT_DISTANCE_M))
	assert_float(expected).is_equal_approx(-9.979, 0.01)
	var result: float = OrbitApi.min_elevation(-10.0, LARGE_ABOVE_M, LARGE_DEFAULT_DISTANCE_M)
	assert_float(result).is_equal_approx(expected, 0.01)
	assert_float(result).is_greater(-10.0)


func test_ac01_the_camera_height_at_the_lowest_elevation_is_not_below_the_cabinet_top() -> void:
	if not _math_exists():
		return
	for distance: float in [0.4, 0.924, 1.489, 3.0, 6.0]:
		var elevation: float = OrbitApi.min_elevation(-10.0, LARGE_ABOVE_M, distance)
		var height_above_cabinet: float = LARGE_ABOVE_M + distance * sin(deg_to_rad(elevation))
		assert_float(height_above_cabinet).is_greater_equal(-0.0001)


func test_ac02_a_larger_distance_raises_the_lowest_elevation() -> void:
	if not _math_exists():
		return
	var near: float = OrbitApi.min_elevation(-10.0, MEDIUM_ABOVE_M, 0.924)
	var far: float = OrbitApi.min_elevation(-10.0, MEDIUM_ABOVE_M, 0.924 * 2.5)
	assert_float(far).is_greater(near)
	assert_float(far).is_equal_approx(-4.2, 0.3)


func test_ac02_the_large_tank_at_2_5_times_the_default_distance_is_minus_3_97() -> void:
	if not _math_exists():
		return
	var elevation: float = OrbitApi.min_elevation(
		-10.0, LARGE_ABOVE_M, LARGE_DEFAULT_DISTANCE_M * 2.5
	)
	assert_float(elevation).is_equal_approx(-3.97, 0.02)


func test_ac02_a_zero_distance_gives_the_limit_and_the_ratio_is_clamped() -> void:
	if not _math_exists():
		return
	assert_float(OrbitApi.min_elevation(-10.0, 0.17, 0.0)).is_equal_approx(-10.0, 0.0001)
	assert_float(OrbitApi.min_elevation(-10.0, 0.17, -1.0)).is_equal_approx(-10.0, 0.0001)
	var close: float = OrbitApi.min_elevation(-10.0, 0.5, 0.1)
	assert_bool(is_nan(close)).is_false()
	assert_float(close).is_equal_approx(-10.0, 0.0001)


# --- AC 3 and 4: the camera rotation and the azimuth wrap ---


func test_ac03_the_rotation_is_built_from_the_angles_and_matches_the_old_front_view() -> void:
	if not _math_exists():
		return
	var rotation: Vector3 = OrbitApi.camera_rotation(0.0, 5.0)
	assert_vector(rotation).is_equal_approx(
		Vector3(-deg_to_rad(5.0), 0.0, 0.0), Vector3.ONE * 0.0001
	)


func test_ac03_the_basis_is_orthonormal_with_up_up_at_every_elevation_and_azimuth() -> void:
	if not _math_exists():
		return
	for azimuth: float in [0.0, 45.0, 90.0, 180.0, 270.0, 359.0, -135.0, 725.0]:
		for elevation: float in [-10.0, 0.0, 5.0, 45.0, 84.99, 85.0]:
			var basis: Basis = Basis.from_euler(OrbitApi.camera_rotation(azimuth, elevation))
			assert_float(basis.x.length()).is_equal_approx(1.0, 0.0001)
			assert_float(basis.y.length()).is_equal_approx(1.0, 0.0001)
			assert_float(basis.z.length()).is_equal_approx(1.0, 0.0001)
			assert_float(basis.x.dot(basis.y)).is_equal_approx(0.0, 0.0001)
			assert_float(basis.y.dot(basis.z)).is_equal_approx(0.0, 0.0001)
			assert_float(basis.y.y).is_greater(0.0)
			var toward_pivot: Vector3 = -OrbitApi.offset(azimuth, elevation, 1.0)
			assert_float((-basis.z).dot(toward_pivot)).is_greater(0.9999)


func test_ac04_azimuth_plus_a_full_turn_gives_the_same_offset() -> void:
	if not _math_exists():
		return
	for azimuth: float in [0.0, 33.0, 180.0, 270.0]:
		for turns: int in [-3, -1, 1, 2, 5]:
			assert_vector(OrbitApi.offset(azimuth + 360.0 * turns, 20.0, 0.9)).is_equal_approx(
				OrbitApi.offset(azimuth, 20.0, 0.9), Vector3.ONE * 0.0001
			)


func test_ac04_azimuth_convention_front_right_back_left() -> void:
	if not _math_exists():
		return
	var tolerance: Vector3 = Vector3.ONE * 0.0001
	assert_vector(OrbitApi.offset(0.0, 0.0, 2.0)).is_equal_approx(Vector3(0, 0, 2), tolerance)
	assert_vector(OrbitApi.offset(90.0, 0.0, 2.0)).is_equal_approx(Vector3(2, 0, 0), tolerance)
	assert_vector(OrbitApi.offset(180.0, 0.0, 2.0)).is_equal_approx(Vector3(0, 0, -2), tolerance)
	assert_vector(OrbitApi.offset(270.0, 0.0, 2.0)).is_equal_approx(Vector3(-2, 0, 0), tolerance)
	assert_vector(OrbitApi.offset(0.0, 90.0, 2.0)).is_equal_approx(Vector3(0, 2, 0), tolerance)


func test_ac04_the_offset_keeps_its_length_at_every_angle() -> void:
	if not _math_exists():
		return
	for azimuth: float in [0.0, 77.0, 200.0, 311.0]:
		for elevation: float in [-10.0, 12.0, 85.0]:
			assert_float(OrbitApi.offset(azimuth, elevation, 1.3).length()).is_equal_approx(
				1.3, 0.0001
			)


func test_ac04_at_azimuth_0_the_offset_is_the_framing_of_adr_0005_and_0006() -> void:
	if not _math_exists():
		return
	var pivot: Vector3 = Vector3(0.0, 0.92, 0.005)
	for elevation: float in [5.0, 30.0, -10.0]:
		var framing: Vector3 = Api.camera_position(pivot, 0.924, elevation) - pivot
		assert_vector(OrbitApi.offset(0.0, elevation, 0.924)).is_equal_approx(
			framing, Vector3.ONE * 0.0001
		)


# --- damping (scope: about 0.15 s, 0 = instant) ---


func test_damping_time_zero_or_less_is_instant() -> void:
	if not _math_exists():
		return
	assert_float(OrbitApi.damp_factor(0.016, 0.0)).is_equal_approx(1.0, 0.0001)
	assert_float(OrbitApi.damp_factor(0.016, -1.0)).is_equal_approx(1.0, 0.0001)


func test_damping_closes_99_percent_of_the_gap_after_the_damping_time() -> void:
	if not _math_exists():
		return
	assert_float(OrbitApi.damp_factor(0.15, 0.15)).is_equal_approx(0.99, 0.005)
	assert_float(OrbitApi.damp_factor(0.0, 0.15)).is_equal_approx(0.0, 0.0001)


func test_damping_is_frame_rate_independent() -> void:
	if not _math_exists():
		return
	var half: float = OrbitApi.damp_factor(0.008, 0.15)
	var whole: float = OrbitApi.damp_factor(0.016, 0.15)
	assert_float((1.0 - half) * (1.0 - half)).is_equal_approx(1.0 - whole, 0.0001)
	assert_float(whole).is_between(0.0, 1.0)
	assert_float(OrbitApi.damp_factor(0.2, 0.15)).is_greater(OrbitApi.damp_factor(0.1, 0.15))


# --- drag conversion (AC 16: pixel based) ---


func test_ac16_a_full_viewport_height_of_pixels_is_the_settings_degrees() -> void:
	if not _math_exists():
		return
	assert_float(OrbitApi.drag_deg(720.0, 720.0, 180.0)).is_equal_approx(180.0, 0.0001)
	assert_float(OrbitApi.drag_deg(360.0, 720.0, 180.0)).is_equal_approx(90.0, 0.0001)
	assert_float(OrbitApi.drag_deg(-180.0, 720.0, 180.0)).is_equal_approx(-45.0, 0.0001)
	assert_float(OrbitApi.drag_deg(0.0, 720.0, 180.0)).is_equal_approx(0.0, 0.0001)


func test_ac16_the_same_pixels_turn_the_view_less_in_a_taller_window() -> void:
	if not _math_exists():
		return
	assert_float(OrbitApi.drag_deg(100.0, 1440.0, 180.0)).is_equal_approx(12.5, 0.0001)
	assert_float(OrbitApi.drag_deg(100.0, 720.0, 360.0)).is_equal_approx(50.0, 0.0001)
