# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #26 criteria 10 and 12 (owner: developer): the pure collision maths of CameraCollision
## (game/systems/camera/camera_collision.gd, ADR 0009): a solid plus margin is the box grown by
## the margin on every face, a point on the grown boundary is outside, and the held distance is
## the smallest distance at least the requested one that is outside every grown solid.

const Cz := preload("res://tests/helpers/camera_zoom_rig.gd")
const Table := preload("res://tests/helpers/tank_table.gd")
const OrbitApi := preload("res://tests/helpers/orbit_api.gd")

const MARGIN := 0.1
const TOLERANCE := 0.0001
const STEP := 0.001


func _box() -> AABB:
	return AABB(Vector3(-1.0, 0.0, -1.0), Vector3(2.0, 1.0, 2.0))


func _exists() -> bool:
	(
		assert_bool(ResourceLoader.exists(Cz.COLLISION_PATH))
		. override_failure_message("%s is missing" % Cz.COLLISION_PATH)
		. is_true()
	)
	return ResourceLoader.exists(Cz.COLLISION_PATH)


func _free(solids: Array[AABB], point: Vector3) -> bool:
	return Cz.is_clear(solids, MARGIN, point) == true


# --- is_clear ---


func test_ac10_a_point_inside_the_grown_box_is_not_clear() -> void:
	if not _exists():
		return
	var solids: Array[AABB] = [_box()]
	assert_that(Cz.is_clear(solids, MARGIN, Vector3(0.0, 0.5, 0.0))).is_equal(false)
	assert_that(Cz.is_clear(solids, MARGIN, Vector3(1.05, 0.5, 0.0))).is_equal(false)
	assert_that(Cz.is_clear(solids, MARGIN, Vector3(0.0, 1.05, 0.0))).is_equal(false)
	assert_that(Cz.is_clear(solids, MARGIN, Vector3(0.0, -0.05, 1.05))).is_equal(false)


func test_ac10_a_point_on_the_grown_boundary_is_clear() -> void:
	if not _exists():
		return
	var solids: Array[AABB] = [_box()]
	assert_that(Cz.is_clear(solids, MARGIN, Vector3(1.1, 0.5, 0.0))).is_equal(true)
	assert_that(Cz.is_clear(solids, MARGIN, Vector3(-1.1, 0.5, 0.0))).is_equal(true)
	assert_that(Cz.is_clear(solids, MARGIN, Vector3(0.0, 1.1, 0.0))).is_equal(true)
	assert_that(Cz.is_clear(solids, MARGIN, Vector3(0.0, 0.5, 1.1))).is_equal(true)


func test_ac10_a_point_outside_the_grown_box_is_clear() -> void:
	if not _exists():
		return
	var solids: Array[AABB] = [_box()]
	assert_that(Cz.is_clear(solids, MARGIN, Vector3(1.2, 0.5, 0.0))).is_equal(true)
	assert_that(Cz.is_clear(solids, MARGIN, Vector3(0.0, 2.0, 0.0))).is_equal(true)
	assert_that(Cz.is_clear(solids, MARGIN, Vector3(5.0, 5.0, 5.0))).is_equal(true)


func test_ac10_with_no_solids_every_point_is_clear() -> void:
	if not _exists():
		return
	var solids: Array[AABB] = []
	assert_that(Cz.is_clear(solids, MARGIN, Vector3.ZERO)).is_equal(true)


func test_ac10_every_solid_counts() -> void:
	if not _exists():
		return
	var far: AABB = AABB(Vector3(5.0, 0.0, 5.0), Vector3.ONE)
	var solids: Array[AABB] = [_box(), far]
	assert_that(Cz.is_clear(solids, MARGIN, Vector3(5.5, 0.5, 5.5))).is_equal(false)
	assert_that(Cz.is_clear(solids, MARGIN, Vector3(3.0, 0.5, 3.0))).is_equal(true)


# --- line_interval ---


func test_ac10_the_interval_of_a_line_through_the_box_is_entry_and_exit() -> void:
	if not _exists():
		return
	var span: Vector2 = Cz.line_interval(Vector3(-3.0, 0.5, 0.0), Vector3.RIGHT, _box())
	assert_float(span.x).is_equal_approx(2.0, TOLERANCE)
	assert_float(span.y).is_equal_approx(4.0, TOLERANCE)


func test_ac10_the_interval_of_a_line_that_starts_inside_begins_before_zero() -> void:
	if not _exists():
		return
	var span: Vector2 = Cz.line_interval(Vector3(0.0, 0.5, 0.0), Vector3.RIGHT, _box())
	assert_float(span.x).is_less(0.0)
	assert_float(span.y).is_equal_approx(1.0, TOLERANCE)


func test_ac10_a_line_that_misses_the_box_has_no_interval() -> void:
	if not _exists():
		return
	var span: Vector2 = Cz.line_interval(Vector3(-3.0, 5.0, 0.0), Vector3.RIGHT, _box())
	assert_bool(span.x >= span.y).is_true()
	var parallel: Vector2 = Cz.line_interval(Vector3(0.0, 2.0, 0.0), Vector3.FORWARD, _box())
	assert_bool(parallel.x >= parallel.y).is_true()


func test_ac10_a_slanted_line_gets_its_entry_and_exit_from_the_slabs() -> void:
	if not _exists():
		return
	var direction: Vector3 = Vector3(1.0, 1.0, 0.0).normalized()
	var span: Vector2 = Cz.line_interval(Vector3(-2.0, -1.0, 0.0), direction, _box())
	# The line y = x + 1 enters at x = -1 (y = 0) and leaves at y = 1 (x = 0).
	assert_float(span.x).is_equal_approx(sqrt(2.0), TOLERANCE)
	assert_float(span.y).is_equal_approx(2.0 * sqrt(2.0), TOLERANCE)


# --- held_distance ---


func test_ac12_a_free_requested_distance_is_returned_unchanged() -> void:
	if not _exists():
		return
	var solids: Array[AABB] = [_box()]
	var held: float = Cz.held_distance(solids, MARGIN, Vector3(0.0, 0.5, 0.0), Vector3.RIGHT, 2.0)
	assert_float(held).is_equal_approx(2.0, TOLERANCE)


func test_ac12_a_blocked_request_is_pushed_out_to_the_grown_boundary() -> void:
	if not _exists():
		return
	var solids: Array[AABB] = [_box()]
	var pivot: Vector3 = Vector3(0.0, 0.5, 0.0)
	var held: float = Cz.held_distance(solids, MARGIN, pivot, Vector3.RIGHT, 0.3)
	assert_float(held).is_equal_approx(1.1, TOLERANCE)


func test_ac12_the_held_distance_is_the_smallest_free_one() -> void:
	if not _exists():
		return
	var solids: Array[AABB] = [_box()]
	var pivot: Vector3 = Vector3(0.0, 0.5, 0.0)
	var direction: Vector3 = Vector3(0.8, 0.0, 0.6)
	var held: float = Cz.held_distance(solids, MARGIN, pivot, direction, 0.2)
	assert_bool(_free(solids, pivot + direction * (held + 0.0001))).is_true()
	assert_bool(_free(solids, pivot + direction * (held - STEP))).is_false()
	assert_float(held).is_greater_equal(0.2)


func test_ac12_a_request_exactly_on_the_boundary_is_free() -> void:
	if not _exists():
		return
	var solids: Array[AABB] = [_box()]
	var held: float = Cz.held_distance(solids, MARGIN, Vector3(0.0, 0.5, 0.0), Vector3.RIGHT, 1.1)
	assert_float(held).is_equal_approx(1.1, TOLERANCE)


func test_ac12_a_request_beyond_the_box_in_front_of_it_is_unchanged() -> void:
	if not _exists():
		return
	var solids: Array[AABB] = [_box()]
	var held: float = Cz.held_distance(solids, MARGIN, Vector3(-4.0, 0.5, 0.0), Vector3.LEFT, 1.0)
	assert_float(held).is_equal_approx(1.0, TOLERANCE)


func test_ac12_the_held_distance_is_never_smaller_than_the_requested_one() -> void:
	if not _exists():
		return
	var solids: Array[AABB] = [_box()]
	for requested: float in [0.0, 0.5, 1.0, 1.5, 3.0]:
		var held: float = Cz.held_distance(
			solids, MARGIN, Vector3(0.2, 0.4, 0.1), Vector3(0.6, 0.0, 0.8), requested
		)
		assert_float(held).is_greater_equal(requested - TOLERANCE)


func test_ac12_chained_solids_are_left_one_after_the_other() -> void:
	if not _exists():
		return
	var second: AABB = AABB(Vector3(1.15, 0.0, -1.0), Vector3(1.0, 1.0, 2.0))
	var solids: Array[AABB] = [_box(), second]
	var pivot: Vector3 = Vector3(0.0, 0.5, 0.0)
	var held: float = Cz.held_distance(solids, MARGIN, pivot, Vector3.RIGHT, 0.3)
	# The first box lets go at 1.1, which is inside the grown second box (1.05 to 2.25).
	assert_float(held).is_equal_approx(2.25, TOLERANCE)
	assert_bool(_free(solids, pivot + Vector3.RIGHT * held)).is_true()


func test_ac12_the_order_of_the_solids_does_not_matter() -> void:
	if not _exists():
		return
	var second: AABB = AABB(Vector3(1.15, 0.0, -1.0), Vector3(1.0, 1.0, 2.0))
	var forward: Array[AABB] = [_box(), second]
	var backward: Array[AABB] = [second, _box()]
	var pivot: Vector3 = Vector3(0.0, 0.5, 0.0)
	assert_float(Cz.held_distance(forward, MARGIN, pivot, Vector3.RIGHT, 0.3)).is_equal_approx(
		Cz.held_distance(backward, MARGIN, pivot, Vector3.RIGHT, 0.3), TOLERANCE
	)


func test_ac12_a_rising_line_always_has_a_finite_free_distance() -> void:
	if not _exists():
		return
	var solids: Array[AABB] = [_box(), AABB(Vector3(-0.5, 1.0, -0.5), Vector3(1.0, 1.0, 1.0))]
	for elevation: float in [5.0, 30.0, 60.0, 85.0]:
		var direction: Vector3 = Vector3(
			cos(deg_to_rad(elevation)), sin(deg_to_rad(elevation)), 0.0
		)
		var pivot: Vector3 = Vector3(0.0, 0.5, 0.0)
		var held: float = Cz.held_distance(solids, MARGIN, pivot, direction, 0.1)
		assert_bool(is_finite(held)).is_true()
		assert_bool(_free(solids, pivot + direction * held)).is_true()


func test_ac12_a_pivot_at_the_inner_glass_is_pushed_out_along_its_line() -> void:
	if not _exists():
		return
	for id: StringName in Table.IDS:
		var box: AABB = Cz.tank_box(id, 0.0)
		var solids: Array[AABB] = [box]
		var pivot: Vector3 = Vector3(0.0, box.position.y + 0.1, box.end.z - Table.glass(id))
		var held: float = Cz.held_distance(solids, Cz.margin(), pivot, Vector3.BACK, 0.02)
		assert_float(held).is_equal_approx(Table.glass(id) + Cz.margin(), TOLERANCE * 10.0)


# --- lowest_held_elevation_deg ---


func test_ac12_the_lowest_held_elevation_is_the_angle_that_leaves_the_footprint() -> void:
	if not _exists():
		return
	var cabinet: AABB = AABB(Vector3(-1.0, 0.0, -1.0), Vector3(2.0, 0.75, 2.0))
	var solids: Array[AABB] = [cabinet]
	var pivot: Vector3 = Vector3(0.0, 0.8, 0.0)
	var lowest: float = Cz.lowest_held_elevation(solids, MARGIN, pivot, 90.0, 0.75)
	var expected: float = -rad_to_deg(atan((0.8 - 0.75) / (1.0 + MARGIN)))
	assert_float(lowest).is_equal_approx(expected, 0.001)


func test_ac12_the_lowest_held_elevation_looks_along_the_azimuth() -> void:
	if not _exists():
		return
	var cabinet: AABB = AABB(Vector3(-1.0, 0.0, -0.5), Vector3(2.0, 0.75, 1.0))
	var solids: Array[AABB] = [cabinet]
	var pivot: Vector3 = Vector3(0.25, 0.8, 0.0)
	var sideways: float = Cz.lowest_held_elevation(solids, MARGIN, pivot, 90.0, 0.75)
	var front: float = Cz.lowest_held_elevation(solids, MARGIN, pivot, 0.0, 0.75)
	var left: float = Cz.lowest_held_elevation(solids, MARGIN, pivot, 270.0, 0.75)
	assert_float(sideways).is_equal_approx(-rad_to_deg(atan(0.05 / (1.1 - 0.25))), 0.001)
	assert_float(front).is_equal_approx(-rad_to_deg(atan(0.05 / (0.5 + MARGIN))), 0.001)
	assert_float(left).is_equal_approx(-rad_to_deg(atan(0.05 / (1.1 + 0.25))), 0.001)


func test_ac12_the_lowest_held_elevation_on_the_three_floor_corner_cases() -> void:
	if not _exists():
		return
	for id: StringName in Table.IDS:
		var z: float = 0.0
		var cabinet: AABB = Cz.cabinet_box(id, z)
		var solids: Array[AABB] = [Cz.tank_box(id, z), cabinet]
		var pan: AABB = Cz.pan_box(id, z)
		var margin: float = Cz.margin()
		# Pivot at the back floor corner at the right edge; the camera on the right (+X).
		var corner: Vector3 = Vector3(pan.end.x, pan.position.y, pan.position.z)
		var right: float = Cz.lowest_held_elevation(solids, margin, corner, 90.0, Cz.CABINET_TOP_M)
		var reach_right: float = cabinet.end.x + margin - corner.x
		assert_float(right).is_equal_approx(
			-rad_to_deg(atan((corner.y - Cz.CABINET_TOP_M) / reach_right)), 0.001
		)
		# The same corner seen from the left (-X) has to cross the whole footprint.
		var left: float = Cz.lowest_held_elevation(solids, margin, corner, 270.0, Cz.CABINET_TOP_M)
		var reach_left: float = corner.x - (cabinet.position.x - margin)
		assert_float(left).is_equal_approx(
			-rad_to_deg(atan((corner.y - Cz.CABINET_TOP_M) / reach_left)), 0.001
		)
		assert_float(left).is_greater(right)


func test_ac12_the_raise_in_the_held_corner_cases_is_at_most_a_tenth_of_a_degree() -> void:
	if not _exists():
		return
	# Only the held cases: the corner seen across the whole footprint. The near-side corners,
	# 0.08 m from the cabinet edge, are never held at 0.6x. The target is the lowest allowed
	# elevation at 0.6x of the default distance of the tank (small, medium, large).
	var defaults: Array[float] = [0.699, 0.924, 1.489]
	for index: int in Table.IDS.size():
		var id: StringName = Table.IDS[index]
		var solids: Array[AABB] = [Cz.tank_box(id, 0.0), Cz.cabinet_box(id, 0.0)]
		var pan: AABB = Cz.pan_box(id, 0.0)
		for corner_x: bool in [false, true]:
			var corner: Vector3 = Cz.box_corner(pan, corner_x, false, false)
			var across: float = 270.0 if corner_x else 90.0
			var lowest: float = Cz.lowest_held_elevation(
				solids, Cz.margin(), corner, across, Cz.CABINET_TOP_M
			)
			var target: float = OrbitApi.min_elevation(
				OrbitApi.setting("min_elevation_limit_deg"),
				corner.y - Cz.CABINET_TOP_M,
				defaults[index] * Cz.setting("zoom_min_factor")
			)
			var raise_deg: float = maxf(target, lowest) - target
			assert_float(raise_deg).is_less_equal(0.1 + Cz.ANGLE_DEG)
