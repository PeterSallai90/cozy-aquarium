# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #28 criteria 14, 24, 27, 28 and 39, geometry of the assembled bed (owner: technical-artist: the
## assembler, the baked data and the core). For each of the three tanks and each of the five types
## the bed is assembled once (SubstrateBedFixture) and measured on the exact data: the transformed
## LOD0 vertices of the stones and the analytic ellipsoids of the sand grains (SubstrateGeometry).
## The numbers are the plan's (technical plan v3, 1.3 and 1.9): S is the fill depth of the type,
## T_mean = max(1 mm, 0.25 x median drawn grain), u = max(1.5 mm, 0.5 x largest drawn grain), the
## glass cell = max(2 mm, median), the median and the largest come from the baked size classes.
## The floor skin and the node names are in test_substrate_bed_view.gd.

const Api := preload("res://tests/helpers/substrate_bed_api.gd")
const Fixture := preload("res://tests/helpers/substrate_bed_fixture.gd")
const Geo := preload("res://tests/helpers/substrate_geometry.gd")
const Sub := preload("res://tests/helpers/substrate_api.gd")
const Table := preload("res://tests/helpers/tank_table.gd")

const GLASS_REACH_M := 0.001
const MIN_CELL_M := 0.002
const SHELL_GRAINS := 2.0
const RAY_STEP_M := 0.005
const GLASS_SHARE := 0.90
const RAY_SHARE := 0.90
const STONE_TOP_SHARE := 0.95
const SAND_TOP_SHARE := 0.90


## Fails once, readably, while a piece of the pipeline is missing. True when the bed can be read.
func _ready_for(tank_id: StringName, id: StringName) -> bool:
	var why: String = Fixture.analysis_problem(tank_id, id)
	assert_str(why).override_failure_message("%s in %s: %s" % [id, tank_id, why]).is_empty()
	return why.is_empty() and not Fixture.analysis_of(tank_id, id).is_empty()


func _median(tank_id: StringName, id: StringName) -> float:
	return float(Fixture.bake_of(tank_id, id).call("median_size"))


func _largest(tank_id: StringName, id: StringName) -> float:
	return float(Fixture.bake_of(tank_id, id).call("largest_size"))


func _t_mean(median: float) -> float:
	return maxf(0.001, 0.25 * median)


func _u(largest: float) -> float:
	return maxf(0.0015, 0.5 * largest)


func _label(tank_id: StringName, id: StringName) -> String:
	return "%s in %s" % [id, tank_id]


func _each_pair(check: Callable) -> void:
	for tank_id: StringName in Table.IDS:
		for id: StringName in Sub.IDS:
			if not _ready_for(tank_id, id):
				return
			check.call(tank_id, id, Fixture.analysis_of(tank_id, id))


# --- AC 14 and 24: the surface ---


func test_ac14_the_mean_top_height_equals_the_fill_depth_within_t_mean() -> void:
	_each_pair(
		func(tank_id: StringName, id: StringName, analysis: Dictionary) -> void:
			var tolerance: float = _t_mean(_median(tank_id, id))
			var mean: float = Geo.mean_top(analysis)
			(
				assert_float(mean)
				. override_failure_message(
					(
						"%s: mean top %.5f, fill depth %.3f +- %.5f"
						% [_label(tank_id, id), mean, Api.fill_depth(id), tolerance]
					)
				)
				. is_equal_approx(Api.fill_depth(id), tolerance)
			)
	)


func test_ac14_no_stone_top_lies_above_the_fill_depth_plus_u() -> void:
	_each_pair(
		func(tank_id: StringName, id: StringName, analysis: Dictionary) -> void:
			var limit: float = Api.fill_depth(id) + _u(_largest(tank_id, id))
			var highest: float = (analysis["max"] as Vector3).y
			(
				assert_float(highest)
				. override_failure_message(
					"%s: highest point %.5f above %.5f" % [_label(tank_id, id), highest, limit]
				)
				. is_less_equal(limit)
			)
	)


func test_ac24_the_mean_top_edge_along_each_glass_face_equals_the_fill_depth() -> void:
	_each_pair(
		func(tank_id: StringName, id: StringName, analysis: Dictionary) -> void:
			var tolerance: float = _t_mean(_median(tank_id, id))
			for face: int in Geo.FACES:
				var mean: float = Geo.mean_of(Geo.edge_heights(analysis, face))
				(
					assert_float(mean)
					. override_failure_message(
						(
							"%s, %s face: mean top edge %.5f, fill depth %.3f +- %.5f"
							% [
								_label(tank_id, id),
								Geo.FACE_NAMES[face],
								mean,
								Api.fill_depth(id),
								tolerance
							]
						)
					)
					. is_equal_approx(Api.fill_depth(id), tolerance)
				)
	)


func test_ac27_the_top_edge_stays_within_u_and_has_the_minimum_peak_to_peak() -> void:
	_each_pair(
		func(tank_id: StringName, id: StringName, analysis: Dictionary) -> void:
			var u: float = _u(_largest(tank_id, id))
			var minimum: float = maxf(0.001, 0.5 * _median(tank_id, id))
			var depth: float = Api.fill_depth(id)
			for face: int in Geo.FACES:
				var edge: PackedFloat32Array = Geo.edge_heights(analysis, face)
				var label: String = "%s, %s face" % [_label(tank_id, id), Geo.FACE_NAMES[face]]
				for value: float in edge:
					(
						assert_float(value)
						. override_failure_message(
							"%s: edge %.5f outside %.3f +- %.5f" % [label, value, depth, u]
						)
						. is_between(depth - u, depth + u)
					)
				(
					assert_float(Geo.peak_to_peak(edge))
					. override_failure_message(
						(
							"%s: peak to peak %.5f below %.5f"
							% [label, Geo.peak_to_peak(edge), minimum]
						)
					)
					. is_greater_equal(minimum)
				)
	)


# --- AC 14: the glass, the footprint, the floor ---


func test_ac14_the_outermost_shell_point_is_within_1_mm_of_each_inner_glass_plane() -> void:
	_each_pair(
		func(tank_id: StringName, id: StringName, analysis: Dictionary) -> void:
			var interior: Vector3 = Table.interior(tank_id)
			for face: int in Geo.FACES:
				var gap: float = (
					(Geo.plane_of(interior, face) - Geo.shell_extreme(analysis, face))
					* Geo.face_sign(face)
				)
				(
					assert_float(gap)
					. override_failure_message(
						(
							"%s, %s face: the shell is %.5f m from the glass"
							% [_label(tank_id, id), Geo.FACE_NAMES[face], gap]
						)
					)
					. is_between(-Geo.EPS, GLASS_REACH_M)
				)
	)


func test_ac14_no_stone_core_or_skin_lies_outside_the_footprint_or_below_the_floor() -> void:
	_each_pair(
		func(tank_id: StringName, id: StringName, analysis: Dictionary) -> void:
			var interior: Vector3 = Table.interior(tank_id)
			var low: Vector3 = analysis["min"]
			var high: Vector3 = analysis["max"]
			var label: String = _label(tank_id, id)
			assert_float(low.x).override_failure_message(label).is_greater_equal(
				-interior.x / 2.0 - Geo.EPS
			)
			assert_float(high.x).override_failure_message(label).is_less_equal(
				interior.x / 2.0 + Geo.EPS
			)
			assert_float(low.z).override_failure_message(label).is_greater_equal(
				-interior.z / 2.0 - Geo.EPS
			)
			assert_float(high.z).override_failure_message(label).is_less_equal(
				interior.z / 2.0 + Geo.EPS
			)
			assert_float(low.y).override_failure_message(label).is_greater_equal(-Geo.EPS)
			var centre: Vector3 = analysis["core_centre"]
			var size: Vector3 = analysis["core_size"]
			(
				assert_float(centre.y - size.y / 2.0)
				. override_failure_message("%s: the core goes below the floor" % label)
				. is_greater_equal(-Geo.EPS)
			)
			assert_float(absf(centre.x) + size.x / 2.0).is_less_equal(interior.x / 2.0 + Geo.EPS)
			assert_float(absf(centre.z) + size.z / 2.0).is_less_equal(interior.z / 2.0 + Geo.EPS)
	)


func test_ac27_at_least_90_percent_of_the_glass_cells_hold_a_stone_touching_the_pane() -> void:
	_each_pair(
		func(tank_id: StringName, id: StringName, analysis: Dictionary) -> void:
			var cell: float = maxf(MIN_CELL_M, _median(tank_id, id))
			for face: int in Geo.FACES:
				var share: float = Geo.glass_contact_share(analysis, face, cell, Api.fill_depth(id))
				(
					assert_float(share)
					. override_failure_message(
						(
							"%s, %s face: glass contact %.3f of the cells (cell %.4f m)"
							% [_label(tank_id, id), Geo.FACE_NAMES[face], share, cell]
						)
					)
					. is_greater_equal(GLASS_SHARE)
				)
	)


func test_ac27_the_stones_and_grains_at_the_glass_are_real_instances() -> void:
	for id: StringName in Sub.IDS:
		if not _ready_for(Table.LARGE, id):
			return
		var data: RefCounted = Fixture.bed_of(Table.LARGE, id)
		(
			assert_int(Api.chunk_instance_count(data))
			. override_failure_message("%s: no instances in the chunks" % id)
			. is_greater(0)
		)
		var look: Resource = Api.look_of(id)
		if Api.is_sand(id):
			assert_object(look.get("grain_glb")).is_null()
		else:
			(
				assert_object(look.get("grain_glb"))
				. override_failure_message("%s: stones are real meshes, grain_glb is null" % id)
				. is_not_null()
			)


# --- AC 39: shell and core ---


func test_ac39_the_core_wall_is_never_within_two_median_grains_of_a_pane() -> void:
	_each_pair(
		func(tank_id: StringName, id: StringName, analysis: Dictionary) -> void:
			var minimum: float = SHELL_GRAINS * _median(tank_id, id)
			for face: int in Geo.FACES:
				var distance: float = Geo.core_wall_distance(analysis, face)
				(
					assert_float(distance)
					. override_failure_message(
						(
							"%s, %s face: the core wall is %.5f m from the glass, need %.5f"
							% [_label(tank_id, id), Geo.FACE_NAMES[face], distance, minimum]
						)
					)
					. is_greater_equal(minimum - Geo.EPS)
				)
	)


func test_ac39_the_core_top_is_never_above_the_fill_depth_minus_the_median_grain() -> void:
	_each_pair(
		func(tank_id: StringName, id: StringName, analysis: Dictionary) -> void:
			var top: float = (
				(analysis["core_centre"] as Vector3).y + (analysis["core_size"] as Vector3).y / 2.0
			)
			var limit: float = Api.fill_depth(id) - _median(tank_id, id)
			(
				assert_float(top)
				. override_failure_message(
					"%s: core top %.5f above %.5f" % [_label(tank_id, id), top, limit]
				)
				. is_less_equal(limit + Geo.EPS)
			)
	)


func test_ac39_a_ray_from_each_glass_face_meets_a_stone_before_the_core_in_90_percent_of_the_steps(
) -> void:
	_each_pair(
		func(tank_id: StringName, id: StringName, analysis: Dictionary) -> void:
			for face: int in Geo.FACES:
				var share: float = Geo.ray_stone_share(
					analysis, face, RAY_STEP_M, Api.fill_depth(id)
				)
				(
					assert_float(share)
					. override_failure_message(
						(
							"%s, %s face: %.3f of the rays meet a stone before the core"
							% [_label(tank_id, id), Geo.FACE_NAMES[face], share]
						)
					)
					. is_greater_equal(RAY_SHARE)
				)
	)


func test_ac39_pebbles_have_stones_down_to_the_floor_at_every_glass_face() -> void:
	for tank_id: StringName in Table.IDS:
		if not _ready_for(tank_id, Api.PEBBLES):
			return
		var analysis: Dictionary = Fixture.analysis_of(tank_id, Api.PEBBLES)
		var bbox: PackedFloat32Array = analysis["bbox"]
		var lowest: float = INF
		for index: int in int(analysis["count"]):
			lowest = minf(lowest, bbox[index * Geo.BBOX_FLOATS + 1])
		(
			assert_float(lowest)
			. override_failure_message(
				"pebbles in %s: the lowest stone is %.5f above the floor" % [tank_id, lowest]
			)
			. is_less_equal(0.002)
		)


# --- AC 28: the top ---


func test_ac28_stones_cover_95_percent_of_the_top_cells_with_no_uncovered_window() -> void:
	_each_pair(
		func(tank_id: StringName, id: StringName, analysis: Dictionary) -> void:
			if Api.is_sand(id):
				return
			var median: float = _median(tank_id, id)
			var cover: Dictionary = Geo.top_coverage(
				analysis,
				Api.fill_depth(id),
				_t_mean(median),
				maxf(MIN_CELL_M, median),
				_largest(tank_id, id),
				false
			)
			(
				assert_float(float(cover["share"]))
				. override_failure_message(
					(
						"%s: stone footprints cover %.3f of the top cells"
						% [_label(tank_id, id), cover["share"]]
					)
				)
				. is_greater_equal(STONE_TOP_SHARE)
			)
			(
				assert_int(int(cover["empty_windows"]))
				. override_failure_message(
					(
						"%s: %d uncovered %d x %d cell windows"
						% [_label(tank_id, id), cover["empty_windows"], cover["k"], cover["k"]]
					)
				)
				. is_equal(0)
			)
	)


func test_ac28_grains_cover_90_percent_of_the_sand_top_cells() -> void:
	for tank_id: StringName in Table.IDS:
		for id: StringName in Api.SAND_IDS:
			if not _ready_for(tank_id, id):
				return
			var analysis: Dictionary = Fixture.analysis_of(tank_id, id)
			var median: float = _median(tank_id, id)
			var cover: Dictionary = Geo.top_coverage(
				analysis,
				Api.fill_depth(id),
				_t_mean(median),
				maxf(MIN_CELL_M, median),
				_largest(tank_id, id),
				true
			)
			(
				assert_float(float(cover["share"]))
				. override_failure_message(
					"%s: grains cover %.3f of the top cells" % [_label(tank_id, id), cover["share"]]
				)
				. is_greater_equal(SAND_TOP_SHARE)
			)
