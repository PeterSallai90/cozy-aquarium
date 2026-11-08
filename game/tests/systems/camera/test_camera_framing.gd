extends GdUnitTestSuite
## #22 criterion 9 (formula part, owner: developer): CameraFraming.default_distance and
## camera_position, the pure functions B14 reuses (ADR 0005). The projection rule per aspect ratio
## is checked on the room camera in test_room_corner_camera.gd. CameraFraming is reached through
## LateApi because the class does not exist before the implementation.

const Api := preload("res://tests/helpers/late_api.gd")


func test_ac09_default_distance_of_the_medium_tank_is_0924_m() -> void:
	var distance: float = Api.default_distance(0.61, 0.31, 50.0, 5.0, 0.85)
	assert_float(distance).is_equal_approx(0.924, 0.001)


func test_ac09_default_distance_follows_the_formula() -> void:
	var width: float = 0.8
	var depth: float = 0.4
	var expected: float = (
		width / (2.0 * 0.85 * tan(deg_to_rad(60.0) / 2.0)) + depth / 2.0 * cos(deg_to_rad(10.0))
	)
	assert_float(Api.default_distance(width, depth, 60.0, 10.0, 0.85)).is_equal_approx(
		expected, 0.0001
	)


func test_ac09_a_wider_tank_needs_a_larger_distance() -> void:
	var narrow: float = Api.default_distance(0.61, 0.31, 50.0, 5.0, 0.85)
	var wide: float = Api.default_distance(0.91, 0.31, 50.0, 5.0, 0.85)
	assert_float(wide).is_greater(narrow)


func test_ac09_a_smaller_share_needs_a_larger_distance() -> void:
	var tight: float = Api.default_distance(0.61, 0.31, 50.0, 5.0, 0.85)
	var loose: float = Api.default_distance(0.61, 0.31, 50.0, 5.0, 0.5)
	assert_float(loose).is_greater(tight)


func test_ac09_camera_position_is_in_front_and_above_the_pivot_by_the_elevation() -> void:
	var pivot: Vector3 = Vector3(0.0, 1.0, 0.0)
	var position: Vector3 = Api.camera_position(pivot, 2.0, 5.0)
	assert_float(position.x).is_equal_approx(0.0, 0.0001)
	assert_float(position.y).is_equal_approx(1.0 + 2.0 * sin(deg_to_rad(5.0)), 0.0001)
	assert_float(position.z).is_equal_approx(2.0 * cos(deg_to_rad(5.0)), 0.0001)
	assert_float(position.distance_to(pivot)).is_equal_approx(2.0, 0.0001)


func test_ac09_camera_position_at_zero_elevation_is_level_with_the_pivot() -> void:
	var position: Vector3 = Api.camera_position(Vector3(0.0, 0.5, 0.0), 1.0, 0.0)
	assert_float(position.y).is_equal_approx(0.5, 0.0001)
	assert_float(position.z).is_equal_approx(1.0, 0.0001)
