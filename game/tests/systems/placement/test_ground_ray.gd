extends GdUnitTestSuite
## #31 AC 5, 6, 7, 11 and 40 (owner: developer): GroundRay.intersect(origin, direction, plane_y)
## is the pure ray against the horizontal plane at the nominal substrate surface, in tank-local
## space; it returns {ok, point}. A ray that is parallel to the plane, comes from below, points
## behind the origin or is not finite returns ok = false (no ghost, no placement) and raises no
## engine error. Front, top and low rays are covered; the plane height is a parameter.

const Api := preload("res://tests/helpers/placement_api.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")

const PLANE_Y: float = 0.03
const TOLERANCE: float = 0.00001


func _have() -> bool:
	(
		assert_bool(Api.exists(Api.GROUND))
		. override_failure_message("res://systems/placement/ground_ray.gd is missing")
		. is_true()
	)
	return Api.exists(Api.GROUND)


func _hits(origin: Vector3, target: Vector3, plane_y: float = PLANE_Y) -> Dictionary:
	return Api.intersect(origin, (target - origin).normalized(), plane_y)


func _assert_hit(result: Dictionary, expected: Vector3) -> void:
	(
		assert_bool(result.get("ok", false) == true)
		. override_failure_message("expected a hit at %s, got %s" % [expected, result])
		. is_true()
	)
	if result.get("ok", false) != true:
		return
	var point: Vector3 = result["point"]
	assert_vector(point).is_equal_approx(expected, Vector3(TOLERANCE, TOLERANCE, TOLERANCE))


func _assert_miss(result: Dictionary) -> void:
	(
		assert_bool(result.has("ok") and result["ok"] == false)
		. override_failure_message("expected ok = false, got %s" % [result])
		. is_true()
	)


func test_ac05_a_front_ray_meets_the_plane_at_the_aimed_point() -> void:
	if not _have():
		return
	var target: Vector3 = Vector3(0.1, PLANE_Y, -0.05)
	_assert_hit(_hits(Vector3(0.0, 0.4, 0.9), target), target)


func test_ac05_a_top_ray_meets_the_plane_straight_below() -> void:
	if not _have():
		return
	_assert_hit(
		Api.intersect(Vector3(0.1, 1.0, 0.05), Vector3.DOWN, PLANE_Y), Vector3(0.1, PLANE_Y, 0.05)
	)


func test_ac40_a_low_ray_meets_the_plane_far_behind_where_it_enters() -> void:
	if not _have():
		return
	var target: Vector3 = Vector3(0.0, PLANE_Y, -0.1)
	_assert_hit(_hits(Vector3(0.0, 0.06, 1.0), target), target)


func test_ac05_the_point_height_is_the_plane_height() -> void:
	if not _have():
		return
	for plane_y: float in [0.03, 0.04, 0.06]:
		var result: Dictionary = _hits(Vector3(0.0, 0.5, 0.8), Vector3(0.0, plane_y, 0.0), plane_y)
		assert_bool(result.get("ok", false) == true).is_true()
		if result.get("ok", false) == true:
			var point: Vector3 = result["point"]
			assert_float(point.y).is_equal_approx(plane_y, TOLERANCE)


func test_ac07_a_ray_parallel_to_the_plane_misses() -> void:
	if not _have():
		return
	_assert_miss(Api.intersect(Vector3(0.0, 0.5, 1.0), Vector3(0.0, 0.0, -1.0), PLANE_Y))
	_assert_miss(Api.intersect(Vector3(0.0, PLANE_Y, 1.0), Vector3(0.0, 0.0, -1.0), PLANE_Y))


func test_ac07_a_ray_from_below_the_plane_misses() -> void:
	if not _have():
		return
	_assert_miss(Api.intersect(Vector3(0.0, 0.0, 0.5), Vector3.UP, PLANE_Y))
	_assert_miss(Api.intersect(Vector3(0.0, 0.0, 0.5), Vector3(0.0, -1.0, 0.0), PLANE_Y))


func test_ac07_a_ray_pointing_away_from_the_plane_misses() -> void:
	if not _have():
		return
	_assert_miss(Api.intersect(Vector3(0.0, 0.5, 0.5), Vector3.UP, PLANE_Y))
	_assert_miss(
		Api.intersect(Vector3(0.0, 0.5, 0.5), Vector3(0.0, 1.0, -1.0).normalized(), PLANE_Y)
	)


func test_ac07_non_finite_input_misses_and_raises_no_error() -> void:
	if not _have():
		return
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void:
			_assert_miss(Api.intersect(Vector3(NAN, 0.5, 0.0), Vector3.DOWN, PLANE_Y))
			_assert_miss(Api.intersect(Vector3(0.0, INF, 0.0), Vector3.DOWN, PLANE_Y))
			_assert_miss(Api.intersect(Vector3(0.0, 0.5, 0.0), Vector3(NAN, -1.0, 0.0), PLANE_Y))
			_assert_miss(Api.intersect(Vector3(0.0, 0.5, 0.0), Vector3(0.0, -INF, 0.0), PLANE_Y))
			_assert_miss(Api.intersect(Vector3(0.0, 0.5, 0.0), Vector3.DOWN, NAN))
			_assert_miss(Api.intersect(Vector3(0.0, 0.5, 0.0), Vector3.ZERO, PLANE_Y))
	)
	assert_dict(seen["errors"]).is_empty()
	assert_dict(seen["warnings"]).is_empty()
	assert_dict(seen["script_errors"]).is_empty()
