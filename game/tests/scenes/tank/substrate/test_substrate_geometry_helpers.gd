# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## Self-tests of the #28 measuring helpers (SubstrateGeometry and SubstrateViews). The suites of the
## bed measure the assembled data with these helpers; if the helper maths were wrong, a correct bed
## would fail or a wrong one pass. These tests run on small synthetic beds whose answer is known
## by construction and need no production class, so they pass before the implementation exists.
## Synthetic bed: a 6 cm x 4 cm tank (12 x 8 cells of 5 mm), one 4.9 mm cube (or sphere) in the
## middle of every cell on the floor, so the nominal depth is 4.9 mm.

const Geo := preload("res://tests/helpers/substrate_geometry.gd")
const Views := preload("res://tests/helpers/substrate_views.gd")
const Table := preload("res://tests/helpers/tank_table.gd")

const INTERIOR := Vector3(0.06, 0.1, 0.04)
const CELL := 0.005
const SIZE := 0.0049
const DEPTH := 0.0049
const CORE_CENTRE := Vector3(0.0, 0.0015, 0.0)
const CORE_SIZE := Vector3(0.04, 0.003, 0.02)


func _cube() -> PackedVector3Array:
	var corners: PackedVector3Array = PackedVector3Array()
	for x: float in [-0.5, 0.5]:
		for y: float in [-0.5, 0.5]:
			for z: float in [-0.5, 0.5]:
				corners.append(Vector3(x, y, z))
	return corners


## One instance of `scale_value` at `origin` as 16 floats (custom data 1, 0, 1, 0.5).
func _instance(origin: Vector3, scale_value: float) -> PackedFloat32Array:
	return PackedFloat32Array(
		[
			scale_value,
			0.0,
			0.0,
			origin.x,
			0.0,
			scale_value,
			0.0,
			origin.y,
			0.0,
			0.0,
			scale_value,
			origin.z,
			1.0,
			0.0,
			1.0,
			0.5,
		]
	)


## The buffers of the synthetic bed, leaving out the cells whose (column, row) is in `skip`.
func _bed(skip: Array[Vector2i] = [], radius_scale: float = SIZE) -> Array[Dictionary]:
	var buffer: PackedFloat32Array = PackedFloat32Array()
	for row: int in 8:
		for column: int in 12:
			if skip.has(Vector2i(column, row)):
				continue
			var origin: Vector3 = Vector3(
				-INTERIOR.x / 2.0 + (float(column) + 0.5) * CELL,
				SIZE / 2.0,
				-INTERIOR.z / 2.0 + (float(row) + 0.5) * CELL
			)
			buffer.append_array(_instance(origin, radius_scale))
	return [{"buffer": buffer, "variant": 0, "offset": Transform3D.IDENTITY}]


func _analysis(skip: Array[Vector2i] = [], sand: bool = false) -> Dictionary:
	var lod0: Array[PackedVector3Array] = [_cube()]
	var entries: Array[Dictionary] = _bed(skip, SIZE / 2.0 if sand else SIZE)
	return Geo.analyse(entries, lod0, INTERIOR, CORE_CENTRE, CORE_SIZE, sand)


# --- instances, placements, ellipsoids ---


func test_helper_the_instance_transform_reads_the_multimesh_layout() -> void:
	var buffer: PackedFloat32Array = PackedFloat32Array(
		[1, 2, 3, 10, 4, 5, 6, 20, 7, 8, 9, 30, 0, 0, 0, 0]
	)
	var transform: Transform3D = Geo.instance_transform(buffer, 0)
	assert_that(transform.basis.x).is_equal(Vector3(1, 4, 7))
	assert_that(transform.basis.y).is_equal(Vector3(2, 5, 8))
	assert_that(transform.basis.z).is_equal(Vector3(3, 6, 9))
	assert_that(transform.origin).is_equal(Vector3(10, 20, 30))


func test_helper_a_tile_offset_turns_about_y_mirrors_x_and_moves_to_the_cell() -> void:
	var turned: Transform3D = Geo.tile_offset(1.0, 2.0, 1, 0)
	assert_that(turned * Vector3(1, 0, 0)).is_equal_approx(
		Vector3(1.0, 0.0, 1.0), Vector3.ONE * 1e-5
	)
	var mirrored: Transform3D = Geo.tile_offset(0.0, 0.0, 0, 1)
	assert_that(mirrored * Vector3(1, 0, 0)).is_equal_approx(Vector3(-1, 0, 0), Vector3.ONE * 1e-5)
	assert_that(Geo.tile_offset(0.5, -0.5, 0, 0).origin).is_equal(Vector3(0.5, 0.0, -0.5))


func test_helper_an_ellipsoid_has_the_row_norms_as_half_extents_and_its_extreme_point() -> void:
	var basis: Basis = Basis.from_scale(Vector3(3.0, 1.0, 2.0))
	assert_that(Geo.ellipsoid_half_extents(basis)).is_equal_approx(
		Vector3(3, 1, 2), Vector3.ONE * 1e-6
	)
	var transform: Transform3D = Transform3D(basis, Vector3(1, 1, 1))
	assert_that(Geo.ellipsoid_extreme_point(transform, Vector3.RIGHT)).is_equal_approx(
		Vector3(4, 1, 1), Vector3.ONE * 1e-6
	)
	assert_that(Geo.ellipsoid_extreme_point(transform, Vector3.UP)).is_equal_approx(
		Vector3(1, 2, 1), Vector3.ONE * 1e-6
	)
	var tilted: Basis = Basis(Vector3.FORWARD, deg_to_rad(90.0)) * basis
	var half: Vector3 = Geo.ellipsoid_half_extents(tilted)
	assert_float(half.y).is_equal_approx(3.0, 1e-5)


# --- the analysis of a flat synthetic bed ---


func test_helper_a_flat_bed_has_the_mean_top_and_edges_of_its_stones() -> void:
	var analysis: Dictionary = _analysis()
	assert_int(int(analysis["count"])).is_equal(96)
	assert_float(Geo.mean_top(analysis)).is_equal_approx(DEPTH, 1e-6)
	for face: int in Geo.FACES:
		var edge: PackedFloat32Array = Geo.edge_heights(analysis, face)
		assert_int(edge.size()).is_equal(12 if face <= Geo.BACK else 8)
		assert_float(Geo.mean_of(edge)).is_equal_approx(DEPTH, 1e-6)
		assert_float(Geo.peak_to_peak(edge)).is_equal_approx(0.0, 1e-9)


func test_helper_the_cells_under_the_core_without_a_stone_take_the_core_top() -> void:
	var skipped: Array[Vector2i] = [Vector2i(6, 4)]
	var analysis: Dictionary = _analysis(skipped)
	var field: PackedFloat32Array = analysis["field"]
	var core_top: float = CORE_CENTRE.y + CORE_SIZE.y / 2.0
	assert_float(field[4 * 12 + 6]).is_equal_approx(core_top, 1e-9)
	assert_float(Geo.mean_top(analysis)).is_less(DEPTH)
	# A cell in the strip next to the glass, outside the core, without a stone stays at the floor.
	var strip: Dictionary = _analysis([Vector2i(0, 0)])
	assert_float((strip["field"] as PackedFloat32Array)[0]).is_equal(0.0)


func test_helper_the_shell_extreme_and_the_bounds_come_from_the_stones() -> void:
	var analysis: Dictionary = _analysis()
	var interior: Vector3 = INTERIOR
	for face: int in Geo.FACES:
		var gap: float = (
			(Geo.plane_of(interior, face) - Geo.shell_extreme(analysis, face)) * Geo.face_sign(face)
		)
		assert_float(gap).is_between(0.0, 0.0001)
	assert_float((analysis["min"] as Vector3).y).is_equal_approx(0.0, 1e-7)
	assert_float((analysis["max"] as Vector3).y).is_equal_approx(DEPTH, 1e-7)


func test_helper_the_core_wall_distance_is_the_gap_between_the_pane_and_the_box() -> void:
	var analysis: Dictionary = _analysis()
	assert_float(Geo.core_wall_distance(analysis, Geo.FRONT)).is_equal_approx(0.02 - 0.01, 1e-9)
	assert_float(Geo.core_wall_distance(analysis, Geo.BACK)).is_equal_approx(0.01, 1e-9)
	assert_float(Geo.core_wall_distance(analysis, Geo.LEFT)).is_equal_approx(0.03 - 0.02, 1e-9)
	assert_float(Geo.core_wall_distance(analysis, Geo.RIGHT)).is_equal_approx(0.01, 1e-9)


func test_helper_glass_contact_is_full_on_a_packed_face_and_zero_when_the_row_is_missing() -> void:
	var full: Dictionary = _analysis()
	for face: int in Geo.FACES:
		(
			assert_float(Geo.glass_contact_share(full, face, CELL, DEPTH))
			. override_failure_message(Geo.FACE_NAMES[face])
			. is_equal_approx(1.0, 1e-9)
		)
	var front_row_missing: Array[Vector2i] = []
	for column: int in 12:
		front_row_missing.append(Vector2i(column, 7))
	var gap: Dictionary = _analysis(front_row_missing)
	assert_float(Geo.glass_contact_share(gap, Geo.FRONT, CELL, DEPTH)).is_equal(0.0)
	assert_float(Geo.glass_contact_share(gap, Geo.BACK, CELL, DEPTH)).is_equal_approx(1.0, 1e-9)


func test_helper_rays_meet_stones_before_the_core_where_the_shell_is_and_miss_where_it_is_not(
) -> void:
	var full: Dictionary = _analysis()
	assert_float(Geo.ray_stone_share(full, Geo.FRONT, CELL, DEPTH)).is_equal_approx(1.0, 1e-9)
	var half_missing: Array[Vector2i] = []
	for column: int in 6:
		for row: int in [6, 7]:
			half_missing.append(Vector2i(column, row))
	var gap: Dictionary = _analysis(half_missing)
	assert_float(Geo.ray_stone_share(gap, Geo.FRONT, CELL, DEPTH)).is_equal_approx(0.5, 1e-9)


func test_helper_top_coverage_counts_footprints_and_finds_uncovered_windows() -> void:
	var full: Dictionary = Geo.top_coverage(_analysis(), DEPTH, 0.001, CELL, SIZE, false)
	assert_float(float(full["share"])).is_equal_approx(1.0, 1e-9)
	assert_int(int(full["k"])).is_equal(3)
	assert_int(int(full["empty_windows"])).is_equal(0)
	var hole: Array[Vector2i] = []
	for column: int in [4, 5, 6]:
		for row: int in [3, 4, 5]:
			hole.append(Vector2i(column, row))
	var holed: Dictionary = Geo.top_coverage(_analysis(hole), DEPTH, 0.001, CELL, SIZE, false)
	assert_float(float(holed["share"])).is_equal_approx(87.0 / 96.0, 1e-9)
	(
		assert_int(int(holed["empty_windows"]))
		. override_failure_message("one 3 x 3 hole, one window")
		. is_equal(1)
	)
	var one_missing: Dictionary = Geo.top_coverage(
		_analysis([Vector2i(2, 2)]), DEPTH, 0.001, CELL, SIZE, false
	)
	assert_int(int(one_missing["empty_windows"])).is_equal(0)


func test_helper_a_stone_below_the_top_is_not_a_top_footprint() -> void:
	var analysis: Dictionary = _analysis()
	var cover: Dictionary = Geo.top_coverage(analysis, DEPTH + 0.01, 0.001, CELL, SIZE, false)
	assert_float(float(cover["share"])).is_equal(0.0)


func test_helper_sand_grains_use_the_analytic_ellipsoid() -> void:
	var analysis: Dictionary = _analysis([], true)
	assert_float(Geo.mean_top(analysis)).is_equal_approx(SIZE / 2.0 + SIZE / 2.0, 1e-6)
	assert_float((analysis["max"] as Vector3).y).is_equal_approx(DEPTH, 1e-6)
	var cover: Dictionary = Geo.top_coverage(analysis, DEPTH, 0.001, CELL, SIZE, true)
	assert_float(float(cover["share"])).is_equal_approx(1.0, 1e-9)


func test_helper_the_empty_window_counter_on_a_plain_grid() -> void:
	var grid: PackedByteArray = PackedByteArray()
	grid.resize(25)
	for index: int in 25:
		grid[index] = 1
	assert_int(Geo.empty_windows(grid, 5, 5, 2)).is_equal(0)
	for row: int in [1, 2]:
		for column: int in [1, 2]:
			grid[row * 5 + column] = 0
	assert_int(Geo.empty_windows(grid, 5, 5, 2)).is_equal(1)
	assert_int(Geo.empty_windows(grid, 5, 5, 1)).is_equal(4)
	assert_int(Geo.empty_windows(grid, 5, 5, 6)).is_equal(0)


# --- sizes and tint ---


func test_helper_the_drawn_size_is_the_mesh_extent_or_twice_the_ellipsoid_column() -> void:
	var cubes: Array[Dictionary] = _bed()
	var mesh_sizes: PackedFloat32Array = Geo.drawn_sizes(cubes, PackedFloat32Array([1.0]), false)
	assert_int(mesh_sizes.size()).is_equal(96)
	assert_float(mesh_sizes[0]).is_equal_approx(SIZE, 1e-7)
	var spheres: Array[Dictionary] = _bed([], SIZE / 2.0)
	var sand_sizes: PackedFloat32Array = Geo.drawn_sizes(spheres, PackedFloat32Array(), true)
	assert_float(sand_sizes[0]).is_equal_approx(SIZE, 1e-7)
	assert_float(Geo.longest_extent(_cube())).is_equal_approx(1.0, 1e-9)
	assert_int(Geo.longest_axis(PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 3, 2)]))).is_equal(
		1
	)


func test_helper_custom_data_and_the_saturation_channel() -> void:
	var custom: PackedFloat32Array = Geo.custom_data(_bed())
	assert_int(custom.size()).is_equal(96 * 4)
	assert_float(custom[0]).is_equal(1.0)
	assert_float(custom[3]).is_equal(0.5)
	assert_float(Geo.saturation_of(1.1 + 4.0 * 3.0)).is_equal_approx(1.1, 1e-5)
	assert_float(Geo.saturation_of(0.9)).is_equal_approx(0.9, 1e-6)
	assert_float(Geo.saturation_of(1.4 + 4.0 * 15.0)).is_equal_approx(1.4, 1e-4)
	var values: PackedFloat32Array = PackedFloat32Array([4.0, 1.0, 3.0, 2.0, 5.0])
	assert_float(Geo.percentile(values, 0.5)).is_equal(3.0)
	assert_float(Geo.percentile(values, 0.0)).is_equal(1.0)
	assert_float(Geo.percentile(values, 1.0)).is_equal(5.0)


# --- tiles ---


func _placements(columns: int, rows: int, pitch: float) -> PackedFloat32Array:
	var placements: PackedFloat32Array = PackedFloat32Array()
	for row: int in rows:
		for column: int in columns:
			placements.append_array(
				PackedFloat32Array(
					[
						float(column) * pitch,
						float(row) * pitch,
						float(column % 4),
						float(row % 2),
						float((column + row) % 3)
					]
				)
			)
	return placements


func test_helper_the_tile_pitch_and_lattice_and_adjacent_repeats() -> void:
	var placements: PackedFloat32Array = _placements(4, 3, 0.05)
	var pitch: Vector2 = Geo.tile_pitch(placements)
	assert_float(pitch.x).is_equal_approx(0.05, 1e-6)
	assert_float(pitch.y).is_equal_approx(0.05, 1e-6)
	var cells: Dictionary = Geo.lattice(placements, pitch)
	assert_int(cells.size()).is_equal(12)
	assert_int(Geo.adjacent_equal_pairs(cells)).is_equal(0)
	cells[Vector2i(1, 0)] = cells[Vector2i(0, 0)]
	assert_int(Geo.adjacent_equal_pairs(cells)).is_equal(1)
	cells[Vector2i(0, 1)] = cells[Vector2i(0, 0)]
	assert_int(Geo.adjacent_equal_pairs(cells)).is_equal(2)


func _grid_points(
	origin: Vector2, pitch: float, columns: int, rows: int, step: float, angle: float
) -> PackedFloat32Array:
	var points: PackedFloat32Array = PackedFloat32Array()
	var x: float = origin.x - pitch / 2.0 + step / 2.0
	while x < origin.x + (float(columns) - 0.5) * pitch:
		var z: float = origin.y - pitch / 2.0 + step / 2.0
		while z < origin.y + (float(rows) - 0.5) * pitch:
			points.append_array(PackedFloat32Array([x, z, angle]))
			z += step
		x += step
	return points


func test_helper_a_uniform_scatter_has_a_seam_density_ratio_of_one() -> void:
	# The inner 2 x 2 tiles of a 4 x 4 lattice, a point every 0.4 mm.
	var points: PackedFloat32Array = _grid_points(Vector2(0.05, 0.05), 0.05, 2, 2, 0.0004, 0.3)
	var ratio: float = Geo.seam_density_ratio(points, Vector2.ZERO, Vector2(0.05, 0.05), 4, 4)
	assert_float(ratio).override_failure_message("uniform scatter ratio %.3f" % ratio).is_between(
		0.9, 1.1
	)


func test_helper_grains_crowded_on_the_borders_have_a_ratio_far_above_one() -> void:
	var points: PackedFloat32Array = PackedFloat32Array()
	for index: int in 400:
		points.append_array(
			PackedFloat32Array(
				[0.075 + 0.0001 * float(index % 5), 0.1 + 0.0001 * float(index % 7), 0.0]
			)
		)
	var ratio: float = Geo.seam_density_ratio(points, Vector2.ZERO, Vector2(0.05, 0.05), 6, 6)
	assert_float(ratio).is_greater(2.0)


func test_helper_orientation_histograms_of_two_tiles_and_their_distance() -> void:
	var points: PackedFloat32Array = PackedFloat32Array()
	for index: int in 40:
		points.append_array(
			PackedFloat32Array(
				[0.05 + 0.001 * float(index % 10), 0.05 + 0.001 * floorf(float(index) / 10.0), 0.1]
			)
		)
		points.append_array(
			PackedFloat32Array(
				[0.10 + 0.001 * float(index % 10), 0.05 + 0.001 * floorf(float(index) / 10.0), 1.6]
			)
		)
	var histograms: Dictionary = Geo.orientation_histograms(
		points, Vector2.ZERO, Vector2(0.05, 0.05), 4, 4, 30
	)
	assert_int(histograms.size()).is_equal(2)
	var first: PackedFloat32Array = histograms[Vector2i(1, 1)]
	var second: PackedFloat32Array = histograms[Vector2i(2, 1)]
	assert_float(Geo.histogram_distance(first, first)).is_equal(0.0)
	assert_float(Geo.histogram_distance(first, second)).is_equal_approx(1.0, 1e-6)
	var sparse: Dictionary = Geo.orientation_histograms(
		points, Vector2.ZERO, Vector2(0.05, 0.05), 4, 4, 500
	)
	assert_int(sparse.size()).is_equal(0)


# --- views ---


func test_helper_the_view_poses_follow_the_plan_for_the_large_tank() -> void:
	var front: Dictionary = Views.close_up("glass_close_front", Table.LARGE, 0.04)
	var o: float = 0.2 + 0.008
	assert_that(front["position"]).is_equal_approx(
		Vector3(0.1, 0.032, o + 0.12), Vector3.ONE * 1e-6
	)
	assert_that(front["target"]).is_equal_approx(Vector3(0.1, 0.0168, 0.2), Vector3.ONE * 1e-6)
	var left: Dictionary = Views.close_up("glass_close_left", Table.LARGE, 0.04)
	assert_that(left["position"]).is_equal_approx(
		Vector3(-0.5 - 0.008 - 0.12, 0.032, 0.0), Vector3.ONE * 1e-6
	)
	var corner: Dictionary = Views.close_up("corner", Table.LARGE, 0.04)
	assert_that(corner["position"]).is_equal_approx(
		Vector3(-0.72, 0.14, o + 0.22), Vector3.ONE * 1e-6
	)
	assert_that(corner["target"]).is_equal_approx(Vector3(-0.44, 0.02, 0.14), Vector3.ONE * 1e-6)
	assert_bool(Views.close_up("nowhere", Table.LARGE, 0.04).is_empty()).is_true()
	assert_int(Views.all_names().size()).is_equal(9)
	assert_str(Views.all_names()[0]).is_equal(Views.DEFAULT_VIEW)


func test_helper_every_view_looks_at_a_point_inside_its_own_frustum() -> void:
	for tank_id: StringName in Table.IDS:
		for view_name: String in Views.all_names():
			var pose: Dictionary = Views.pose_of(view_name, tank_id, 0.04)
			assert_bool(pose.is_empty()).override_failure_message(view_name).is_false()
			var planes: Array[Plane] = Views.frustum(pose)
			assert_int(planes.size()).is_equal(6)
			(
				assert_bool(Views.inside(planes, pose["target"]))
				. override_failure_message(
					"%s in %s: the target is outside the frustum" % [view_name, tank_id]
				)
				. is_true()
			)
			(
				assert_bool(Views.inside(planes, pose["position"]))
				. override_failure_message(
					"the camera position is inside its own frustum (before the near plane)"
				)
				. is_false()
			)


func test_helper_the_frustum_has_outward_planes_with_the_build_camera_angles() -> void:
	var pose: Dictionary = {"position": Vector3(0, 0, 1), "target": Vector3(0, 0, 0)}
	var planes: Array[Plane] = Views.frustum(pose)
	assert_bool(Views.inside(planes, Vector3(0, 0, 0))).is_true()
	(
		assert_bool(Views.inside(planes, Vector3(0, 0, 2)))
		. override_failure_message("behind")
		. is_false()
	)
	(
		assert_bool(Views.inside(planes, Vector3(0, 0, -200)))
		. override_failure_message("beyond far")
		. is_false()
	)
	var half_width: float = tan(deg_to_rad(Views.FOV_DEG) / 2.0)
	assert_bool(Views.inside(planes, Vector3(half_width * 0.99, 0, 0))).is_true()
	assert_bool(Views.inside(planes, Vector3(half_width * 1.01, 0, 0))).is_false()
	assert_bool(Views.inside(planes, Vector3(-half_width * 1.01, 0, 0))).is_false()
	var half_height: float = half_width / Views.ASPECT
	assert_bool(Views.inside(planes, Vector3(0, half_height * 0.99, 0))).is_true()
	assert_bool(Views.inside(planes, Vector3(0, -half_height * 1.01, 0))).is_false()
	(
		assert_bool(Views.inside(planes, Vector3(0, 0, 1.0 - Views.NEAR_M * 0.5)))
		. override_failure_message("before near")
		. is_false()
	)


func test_helper_the_default_view_looks_at_the_pivot_from_the_front_and_above() -> void:
	for tank_id: StringName in Table.IDS:
		var pose: Dictionary = Views.default_view(tank_id)
		var position: Vector3 = pose["position"]
		var target: Vector3 = pose["target"]
		assert_that(target).is_equal(Vector3(0.0, Table.water_line(tank_id) / 2.0, 0.0))
		assert_float(position.z).is_greater(Table.exterior(tank_id).z / 2.0)
		assert_float(position.y).is_greater(target.y)
		var transform: Transform3D = Views.transform_of(pose)
		var forward: Vector3 = -transform.basis.z
		assert_float(forward.dot((target - position).normalized())).is_equal_approx(1.0, 1e-5)
