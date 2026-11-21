extends GdUnitTestSuite
## #34 AC 26 (owner: developer), ADR 0013 rule 6: the resting pose is a pure function of (uid,
## zone, extents, tank interior, water line, substrate surface), never stored.
## FishRestPose.compute(uid, zone, extents, interior_size_m, water_line_m, surface_at,
## grain_allowance_m) gives position and yaw: x in [-X/2 + r + 0.01, X/2 - r - 0.01] with
## mix(lo, hi, unit) of the salt fish.rest.x (0 when the range is empty), z the same with
## fish.rest.z, y from FishZones (BOTTOM: the range minimum; others: min + unit * (max - min) with
## fish.rest.y), yaw = TAU * unit of fish.rest.yaw, where unit is the independent FNV-1a of
## FishApi. Three tanks x three species x 20 fixed uids.
## Test decision: the extents are synthetic numbers of the plan so this suite does not wait for the
## models; test_fish_view.gd repeats the pose check with the real extents.

const Api := preload("res://tests/helpers/fish_api.gd")

const EPS := 1e-6
const GLASS_MARGIN := 0.01
const UID_COUNT := 20
## tank id: [interior, water line]
const TANKS: Dictionary[StringName, Array] = {
	&"tank_small_1": [Vector3(0.40, 0.27, 0.25), 0.25],
	&"tank_medium_1": [Vector3(0.60, 0.35, 0.30), 0.33],
	&"tank_large_1": [Vector3(1.00, 0.52, 0.40), 0.50],
}
## species id: [zone, radius, below, above]
const SPECIES: Dictionary[StringName, Array] = {
	&"neon_tetra": [Api.ZONE_MIDDLE, 0.025, 0.005, 0.006],
	&"angelfish": [Api.ZONE_MIDDLE, 0.085, 0.095, 0.091],
	&"bronze_corydoras": [Api.ZONE_BOTTOM, 0.045, 0.0095, 0.0105],
}
const SAND_DEPTH := 0.03
const SAND_ALLOWANCE := 0.0015


func _have_pose() -> bool:
	var is_ready: bool = (
		Api.script_of(Api.POSE_PATH) != null and Api.script_of(Api.ZONES_PATH) != null
	)
	assert_bool(is_ready).override_failure_message("FishRestPose or FishZones is missing").is_true()
	return is_ready


func _uid(index: int) -> String:
	return "%08x" % (((index + 1) * 0x9E3779B1) & 0xFFFFFFFF)


func _flat(height: float) -> Callable:
	return func(_x: float, _z: float) -> float: return height


func _extents(id: StringName) -> Object:
	var row: Array = SPECIES[id]
	return Api.extents(row[1], row[2], row[3])


func _pose(
	uid: String, id: StringName, tank: StringName, surface: float = SAND_DEPTH
) -> Dictionary:
	var row: Array = SPECIES[id]
	var tank_row: Array = TANKS[tank]
	return Api.rest_pose(
		uid, row[0], _extents(id), tank_row[0], tank_row[1], _flat(surface), SAND_ALLOWANCE
	)


func _mix(low: float, high: float, unit: float) -> float:
	return low + (high - low) * unit


## The plan formula for x or z: the interior shrunk by the radius and 1 cm on every side.
func _axis(half_size: float, radius: float, unit: float) -> float:
	var low: float = -half_size + radius + GLASS_MARGIN
	var high: float = half_size - radius - GLASS_MARGIN
	if low > high:
		return 0.0
	return _mix(low, high, unit)


func test_the_glass_margin_constant_is_one_centimetre() -> void:
	var margin: float = Api.constant(Api.POSE_PATH, "GLASS_MARGIN_M", -1.0)
	assert_float(margin).is_equal_approx(0.01, EPS)


func test_ac26_every_pose_follows_the_plan_formula() -> void:
	if not _have_pose():
		return
	for tank: StringName in TANKS:
		var interior: Vector3 = (TANKS[tank] as Array)[0]
		var water: float = (TANKS[tank] as Array)[1]
		for id: StringName in SPECIES:
			var row: Array = SPECIES[id]
			for index: int in UID_COUNT:
				var uid: String = _uid(index)
				var pose: Dictionary = _pose(uid, id, tank)
				var label: String = "%s %s %s" % [tank, id, uid]
				(
					assert_bool(pose.is_empty())
					. override_failure_message(label + ": no pose")
					. is_false()
				)
				if pose.is_empty():
					return
				var position: Vector3 = pose["position"]
				var want_x: float = _axis(
					interior.x / 2.0, row[1], Api.expected_unit(uid, "fish.rest.x")
				)
				var want_z: float = _axis(
					interior.z / 2.0, row[1], Api.expected_unit(uid, "fish.rest.z")
				)
				assert_float(position.x).override_failure_message(label + " x").is_equal_approx(
					want_x, EPS
				)
				assert_float(position.z).override_failure_message(label + " z").is_equal_approx(
					want_z, EPS
				)
				var range_y: Dictionary = Api.origin_range(
					row[0], _flat(SAND_DEPTH), want_x, want_z, water, SAND_ALLOWANCE, _extents(id)
				)
				var want_y: float = range_y["min_y"]
				if row[0] != Api.ZONE_BOTTOM:
					want_y += (
						Api.expected_unit(uid, "fish.rest.y")
						* (float(range_y["max_y"]) - float(range_y["min_y"]))
					)
				assert_float(position.y).override_failure_message(label + " y").is_equal_approx(
					want_y, EPS
				)
				assert_float(pose["yaw"]).override_failure_message(label + " yaw").is_equal_approx(
					TAU * Api.expected_unit(uid, "fish.rest.yaw"), EPS
				)


func test_ac26_every_pose_is_inside_the_glass_margin_and_the_zone_range() -> void:
	if not _have_pose():
		return
	for tank: StringName in TANKS:
		var interior: Vector3 = (TANKS[tank] as Array)[0]
		for id: StringName in SPECIES:
			var radius: float = (SPECIES[id] as Array)[1]
			for index: int in UID_COUNT:
				var pose: Dictionary = _pose(_uid(index), id, tank)
				if pose.is_empty():
					assert_bool(false).override_failure_message("no pose").is_true()
					return
				var position: Vector3 = pose["position"]
				var label: String = "%s %s %d" % [tank, id, index]
				var limit_x: float = maxf(0.0, interior.x / 2.0 - radius - GLASS_MARGIN)
				var limit_z: float = maxf(0.0, interior.z / 2.0 - radius - GLASS_MARGIN)
				(
					assert_bool(absf(position.x) <= limit_x + EPS)
					. override_failure_message(label + ": x reaches the glass")
					. is_true()
				)
				(
					assert_bool(absf(position.z) <= limit_z + EPS)
					. override_failure_message(label + ": z reaches the glass")
					. is_true()
				)
				(
					assert_bool(position.y > SAND_DEPTH)
					. override_failure_message(label + ": inside the bed")
					. is_true()
				)


func test_ac26_no_two_fish_of_a_species_share_a_point_in_any_tank() -> void:
	if not _have_pose():
		return
	for tank: StringName in TANKS:
		for id: StringName in SPECIES:
			var points: Array[Vector3] = []
			for index: int in UID_COUNT:
				var pose: Dictionary = _pose(_uid(index), id, tank)
				if pose.is_empty():
					assert_bool(false).override_failure_message("no pose").is_true()
					return
				points.append(pose["position"])
			for a: int in points.size():
				for b: int in range(a + 1, points.size()):
					(
						assert_bool(points[a].distance_to(points[b]) > 0.001)
						. override_failure_message(
							"%s %s: fish %d and %d are within 1 mm" % [tank, id, a, b]
						)
						. is_true()
					)


func test_ac26_the_same_input_gives_the_same_pose() -> void:
	if not _have_pose():
		return
	var first: Dictionary = _pose("f1000001", &"angelfish", &"tank_medium_1")
	var second: Dictionary = _pose("f1000001", &"angelfish", &"tank_medium_1")
	assert_bool(first.is_empty()).is_false()
	assert_dict(first).is_equal(second)


func test_ac26_removing_one_fish_does_not_change_the_pose_of_any_other() -> void:
	if not _have_pose():
		return
	var poses_before: Array[Dictionary] = []
	for index: int in UID_COUNT:
		poses_before.append(_pose(_uid(index), &"neon_tetra", &"tank_large_1"))
	# "Remove" fish 7: the pose of every other uid is computed again from its own input only.
	for index: int in UID_COUNT:
		if index == 7:
			continue
		assert_dict(_pose(_uid(index), &"neon_tetra", &"tank_large_1")).is_equal(
			poses_before[index]
		)


func test_ac26_the_pose_follows_the_substrate_surface_for_a_bottom_fish() -> void:
	if not _have_pose():
		return
	var sand: Dictionary = _pose("f1000006", &"bronze_corydoras", &"tank_small_1", 0.03)
	var pebbles: Dictionary = _pose("f1000006", &"bronze_corydoras", &"tank_small_1", 0.06)
	if sand.is_empty() or pebbles.is_empty():
		assert_bool(false).override_failure_message("no pose").is_true()
		return
	(
		assert_float((pebbles["position"] as Vector3).y - (sand["position"] as Vector3).y)
		. is_equal_approx(0.03, EPS)
	)
	assert_float((pebbles["position"] as Vector3).x).is_equal_approx(
		(sand["position"] as Vector3).x, EPS
	)


func test_ac26_edge_a_tank_too_small_for_the_margin_pins_x_and_z_to_the_middle() -> void:
	if not _have_pose():
		return
	var huge: Object = Api.extents(0.3, 0.01, 0.01)
	var pose: Dictionary = Api.rest_pose(
		"f1000001",
		Api.ZONE_MIDDLE,
		huge,
		Vector3(0.40, 0.27, 0.25),
		0.25,
		_flat(SAND_DEPTH),
		SAND_ALLOWANCE
	)
	assert_bool(pose.is_empty()).is_false()
	assert_float((pose.get("position", Vector3.ONE) as Vector3).x).is_equal_approx(0.0, EPS)
	assert_float((pose.get("position", Vector3.ONE) as Vector3).z).is_equal_approx(0.0, EPS)


func test_ac26_edge_a_column_too_small_for_the_fish_reports_pinned() -> void:
	if not _have_pose():
		return
	var tall: Object = Api.extents(0.02, 0.2, 0.2)
	var pose: Dictionary = Api.rest_pose(
		"f1000001",
		Api.ZONE_MIDDLE,
		tall,
		Vector3(0.40, 0.27, 0.25),
		0.25,
		_flat(SAND_DEPTH),
		SAND_ALLOWANCE
	)
	assert_bool(pose.get("pinned", false)).is_true()
	assert_float((pose.get("position", Vector3.ZERO) as Vector3).y).is_equal_approx(
		((SAND_DEPTH + 0.2) + (0.25 - 0.2)) / 2.0, EPS
	)
