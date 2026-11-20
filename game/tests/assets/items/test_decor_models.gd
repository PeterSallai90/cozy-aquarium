# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #157 criteria 5, 6, 7 and 8, model part (owner: technical-artist). The three starter decoration
## models in res://assets/items/models: real size, origin, budget, shading, UV layers, the shared
## decor atlas with one cell per model, vertex colours and the shared decor material.
##
## Group that makes this file pass: technical-artist (stage 1: the geometry, UV, import-flag and
## vertex colour tests; stage 2: the two material tests, which need decor_palette.tres, the shader
## uniform vertex_shade and the _subresources mapping in the three .glb.import files).
##
## The expected sizes are the footprint table of the issue, written here as constants (x width, y
## height, z depth, in cm) and not read from the catalog, so the art can go green before the
## developer adds the .tres files; test_decor_starter_set.gd checks the same numbers on the catalog.
##
## Test decisions where the plan is silent:
## - The atlas cells are fixed as in plan section 3 and never move: stone (0, 0), branch (1, 0),
##   amphora (2, 0), column and row from the top-left of decor_palette_atlas.png (8 x 8 cells).
## - The mesh checks sum all MeshInstance3D nodes of the imported scene (the LOD0 arrays).
## - "Smooth" is one normal per vertex position (spread at most 2 degrees); "not flat-faceted"
##   is: on more than half of the triangles a vertex normal differs from the face normal by more
##   than 2 degrees.

const Glb := preload("res://tests/helpers/glb_mesh_checks.gd")
const Checks := preload("res://tests/helpers/proof_fish_checks.gd")
const LfsGuard := preload("res://tests/helpers/lfs_guard.gd")
const FishSource := preload("res://tests/helpers/proof_fish_source.gd")

const MODEL_DIR := "res://assets/items/models/"
const ATLAS_PATH := "res://assets/items/decor_palette_atlas.png"
const MATERIAL_PATH := "res://assets/items/materials/decor_palette.tres"
const SHADER_PATH := "res://shaders/decor_item.gdshader"
const IDS: Array[String] = ["river_stone", "driftwood_branch", "clay_amphora"]
const SIZE_CM: Dictionary[String, Vector3] = {
	"river_stone": Vector3(11.0, 6.0, 8.0),
	"driftwood_branch": Vector3(28.0, 8.0, 7.0),
	"clay_amphora": Vector3(9.0, 14.0, 8.0),
}
## Atlas cell (column, row from the top) of each model.
const CELL: Dictionary[String, Vector2i] = {
	"river_stone": Vector2i(0, 0),
	"driftwood_branch": Vector2i(1, 0),
	"clay_amphora": Vector2i(2, 0),
}
const GRID := 8
const CELL_PX := 16
const CELL_HALF := 8
const TRIANGLES_MIN := 300
const TRIANGLES_MAX := 1500
const SIZE_TOLERANCE := 0.05
const SMOOTH_MAX_DEGREES := 2.0
const SPLIT_MIN_DEGREES := 30.0
const FLAT_MAX_DEGREES := 2.0
const SNAP := 0.0001
const STONE_SATURATION_MAX := 0.25
const WOOD_HUE_MIN_DEG := 15.0
const WOOD_HUE_MAX_DEG := 40.0
const WOOD_VALUE_MAX := 0.6


func _path(id: String) -> String:
	return MODEL_DIR + id + ".glb"


## The imported scene of one model; null (and a failed assert) while it is missing or broken.
func _open(id: String) -> Node3D:
	var opened: Dictionary = Glb.open_glb(_path(id))
	assert_str(String(opened["problem"])).override_failure_message(id).is_empty()
	var root: Node3D = opened["root"]
	if root != null:
		auto_free(root)
	return root


func _atlas() -> Image:
	var image: Image = Image.new()
	var error: int = image.load_png_from_buffer(FileAccess.get_file_as_bytes(ATLAS_PATH))
	assert_int(error).override_failure_message("cannot read %s" % ATLAS_PATH).is_equal(OK)
	return image


func _cell_colour(image: Image, cell: Vector2i) -> Color:
	return image.get_pixel(cell.x * CELL_PX + CELL_HALF, cell.y * CELL_PX + CELL_HALF)


## Every distinct atlas cell that a UV2 point of the model falls into.
func _cells_of(root: Node3D) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for instance: MeshInstance3D in Glb.mesh_instances(root):
		for surface: int in instance.mesh.get_surface_count():
			var arrays: Array = instance.mesh.surface_get_arrays(surface)
			for uv: Vector2 in Checks.column_v2(arrays, Mesh.ARRAY_TEX_UV2):
				var cell: Vector2i = Vector2i(floori(uv.x * GRID), floori(uv.y * GRID))
				if not cells.has(cell):
					cells.append(cell)
	return cells


# --- AC 5: real size, origin, scale ---


func test_ac05_each_glb_is_a_real_glb_and_not_an_lfs_pointer() -> void:
	for id: String in IDS:
		(
			assert_str(LfsGuard.problem(_path(id), LfsGuard.GLB_MAGIC))
			. override_failure_message(id)
			. is_empty()
		)


func test_ac05_each_model_has_the_real_size_of_the_issue_within_5_percent() -> void:
	for id: String in IDS:
		var root: Node3D = _open(id)
		if root == null:
			continue
		var wanted: Vector3 = SIZE_CM[id] / 100.0
		var size: Vector3 = Glb.scene_bounds(root).size
		for axis: int in 3:
			(
				assert_float(size[axis])
				. override_failure_message(
					(
						"%s axis %d: %.4f m, need %.4f m +/- 5 percent"
						% [id, axis, size[axis], wanted[axis]]
					)
				)
				. is_equal_approx(wanted[axis], wanted[axis] * SIZE_TOLERANCE)
			)


func test_ac05_the_lowest_point_of_each_model_is_y_zero_within_1_mm() -> void:
	for id: String in IDS:
		var root: Node3D = _open(id)
		if root == null:
			continue
		var low: float = Glb.scene_bounds(root).position.y
		(
			assert_float(low)
			. override_failure_message("%s lowest y = %.5f m" % [id, low])
			. is_equal_approx(0.0, Glb.MM)
		)


func test_ac05_the_footprint_centre_of_each_model_is_the_origin_within_1_mm() -> void:
	for id: String in IDS:
		var root: Node3D = _open(id)
		if root == null:
			continue
		var centre: Vector3 = Glb.scene_bounds(root).get_center()
		(
			assert_float(centre.x)
			. override_failure_message("%s centre x = %.5f m" % [id, centre.x])
			. is_equal_approx(0.0, Glb.MM)
		)
		(
			assert_float(centre.z)
			. override_failure_message("%s centre z = %.5f m" % [id, centre.z])
			. is_equal_approx(0.0, Glb.MM)
		)


func test_ac05_no_model_has_a_baked_scale() -> void:
	for id: String in IDS:
		var root: Node3D = _open(id)
		if root == null:
			continue
		assert_str("\n".join(Glb.scale_failures(root))).override_failure_message(id).is_empty()


# --- AC 6: triangle budget and import flags ---


func test_ac06_each_model_has_300_to_1500_triangles_at_lod0() -> void:
	for id: String in IDS:
		var root: Node3D = _open(id)
		if root == null:
			continue
		var total: int = 0
		for instance: MeshInstance3D in Glb.mesh_instances(root):
			total += Checks.triangle_count(instance.mesh)
		assert_int(total).override_failure_message("%s: %d triangles" % [id, total]).is_between(
			TRIANGLES_MIN, TRIANGLES_MAX
		)


func test_ac06_each_import_has_lods_on_and_light_baking_off_and_no_lightmap_uv() -> void:
	for id: String in IDS:
		var config: ConfigFile = ConfigFile.new()
		var error: int = config.load(_path(id) + ".import")
		assert_int(error).override_failure_message("%s.glb.import is missing" % id).is_equal(OK)
		if error != OK:
			continue
		(
			assert_bool(bool(config.get_value("params", "meshes/generate_lods", false)))
			. override_failure_message("%s: meshes/generate_lods must be true" % id)
			. is_true()
		)
		(
			assert_str("\n".join(Glb.import_failures(_path(id))))
			. override_failure_message(id)
			. is_empty()
		)


# --- AC 7: shading ---


## Normals of one surface grouped by vertex position: Dictionary[Vector3i, Array[Vector3]].
func _normals_by_position(arrays: Array) -> Dictionary:
	var vertices: PackedVector3Array = Checks.column_v3(arrays, Mesh.ARRAY_VERTEX)
	var normals: PackedVector3Array = Checks.column_v3(arrays, Mesh.ARRAY_NORMAL)
	var groups: Dictionary = {}
	if normals.size() != vertices.size():
		return groups
	for i: int in vertices.size():
		var key: Vector3i = Vector3i((vertices[i] / SNAP).round())
		var members: Array = groups.get(key, [])
		members.append(normals[i].normalized())
		groups[key] = members
	return groups


func _spread_degrees(members: Array) -> float:
	var worst: float = 0.0
	for a: int in members.size():
		for b: int in range(a + 1, members.size()):
			worst = maxf(worst, rad_to_deg((members[a] as Vector3).angle_to(members[b] as Vector3)))
	return worst


func test_ac07_the_branch_and_the_amphora_have_one_normal_per_vertex_position() -> void:
	for id: String in ["driftwood_branch", "clay_amphora"]:
		var root: Node3D = _open(id)
		if root == null:
			continue
		var worst: float = 0.0
		var seen: int = 0
		for instance: MeshInstance3D in Glb.mesh_instances(root):
			for surface: int in instance.mesh.get_surface_count():
				var groups: Dictionary = _normals_by_position(
					instance.mesh.surface_get_arrays(surface)
				)
				seen += groups.size()
				for key: Vector3i in groups:
					worst = maxf(worst, _spread_degrees(groups[key] as Array))
		assert_int(seen).override_failure_message("%s has no normals" % id).is_greater(0)
		(
			assert_float(worst)
			. override_failure_message(
				"%s: normals at one position differ by %.1f degrees" % [id, worst]
			)
			. is_less_equal(SMOOTH_MAX_DEGREES)
		)


func test_ac07_the_stone_has_a_hard_edge_split_by_angle() -> void:
	var root: Node3D = _open("river_stone")
	if root == null:
		return
	var split: bool = false
	for instance: MeshInstance3D in Glb.mesh_instances(root):
		for surface: int in instance.mesh.get_surface_count():
			var groups: Dictionary = _normals_by_position(instance.mesh.surface_get_arrays(surface))
			for key: Vector3i in groups:
				if _spread_degrees(groups[key] as Array) >= SPLIT_MIN_DEGREES:
					split = true
	(
		assert_bool(split)
		. override_failure_message("the stone has no vertex position with a split of 30 degrees")
		. is_true()
	)


func test_ac07_the_stone_is_not_flat_shaded() -> void:
	var root: Node3D = _open("river_stone")
	if root == null:
		return
	var triangles: int = 0
	var smooth: int = 0
	for instance: MeshInstance3D in Glb.mesh_instances(root):
		for surface: int in instance.mesh.get_surface_count():
			var arrays: Array = instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = Checks.column_v3(arrays, Mesh.ARRAY_VERTEX)
			var normals: PackedVector3Array = Checks.column_v3(arrays, Mesh.ARRAY_NORMAL)
			var indices: PackedInt32Array = Checks.surface_triangles(arrays)
			if normals.size() != vertices.size():
				continue
			# indices.size() / 3: three indices per triangle, a whole number of triangles.
			@warning_ignore("integer_division")
			for t: int in indices.size() / 3:
				var a: int = indices[t * 3]
				var b: int = indices[t * 3 + 1]
				var c: int = indices[t * 3 + 2]
				var face: Vector3 = (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
				if face.length() < 1e-12:
					continue
				face = face.normalized()
				triangles += 1
				for index: int in [a, b, c]:
					var vertex_normal: Vector3 = normals[index].normalized()
					var angle: float = minf(
						vertex_normal.angle_to(face), vertex_normal.angle_to(-face)
					)
					if rad_to_deg(angle) > FLAT_MAX_DEGREES:
						smooth += 1
						break
	assert_int(triangles).override_failure_message("the stone has no triangles").is_greater(0)
	(
		assert_float(float(smooth) / maxf(float(triangles), 1.0))
		. override_failure_message(
			"the stone looks flat-faceted: %d of %d triangles are smooth" % [smooth, triangles]
		)
		. is_greater(0.5)
	)


# --- AC 8: UV sets, atlas, colours ---


func test_ac08_each_model_has_exactly_two_uv_sets_and_uv_arrays() -> void:
	for id: String in IDS:
		var failures: PackedStringArray = Glb.texcoord_failures(_path(id))
		var root: Node3D = _open(id)
		if root != null:
			failures.append_array(Glb.uv_failures(root))
		(
			assert_str("\n".join(failures))
			. override_failure_message("%s: %s" % [id, "\n".join(failures)])
			. is_empty()
		)


func test_ac08_every_uv2_triangle_collapses_onto_the_centre_of_one_atlas_cell() -> void:
	for id: String in IDS:
		var root: Node3D = _open(id)
		if root == null:
			continue
		var failures: PackedStringArray = Glb.atlas_collapse_failures(root)
		(
			assert_str("\n".join(failures))
			. override_failure_message("%s: %s" % [id, "\n".join(failures)])
			. is_empty()
		)


func test_ac08_the_decor_atlas_is_a_128_px_png() -> void:
	assert_str(LfsGuard.problem(ATLAS_PATH, LfsGuard.PNG_MAGIC)).is_empty()
	var image: Image = _atlas()
	assert_int(image.get_width()).is_equal(GRID * CELL_PX)
	assert_int(image.get_height()).is_equal(GRID * CELL_PX)


func test_ac08_each_model_uses_exactly_one_atlas_cell_and_it_is_its_own_fixed_cell() -> void:
	for id: String in IDS:
		var root: Node3D = _open(id)
		if root == null:
			continue
		var cells: Array[Vector2i] = _cells_of(root)
		(
			assert_array(cells)
			. override_failure_message("%s uses the cells %s, need only %s" % [id, cells, CELL[id]])
			. is_equal([CELL[id]])
		)


func test_ac08_the_three_cells_have_three_different_colours() -> void:
	var image: Image = _atlas()
	if image.is_empty():
		return
	var seen: Dictionary = {}
	for id: String in IDS:
		seen[_cell_colour(image, CELL[id]).to_html()] = true
	assert_int(seen.size()).is_equal(3)


func test_ac08_the_stone_cell_is_grey_saturation_at_most_0_25() -> void:
	var image: Image = _atlas()
	if image.is_empty():
		return
	assert_float(_cell_colour(image, CELL["river_stone"]).s).is_less_equal(STONE_SATURATION_MAX)


func test_ac08_the_branch_cell_is_warm_brown_hue_15_to_40_degrees_value_at_most_0_6() -> void:
	var image: Image = _atlas()
	if image.is_empty():
		return
	var colour: Color = _cell_colour(image, CELL["driftwood_branch"])
	assert_float(colour.h * 360.0).is_between(WOOD_HUE_MIN_DEG, WOOD_HUE_MAX_DEG)
	assert_float(colour.v).is_less_equal(WOOD_VALUE_MAX)


## The highest saturation of the texels that the body surface of the proof fish samples.
func _fish_body_saturation_max() -> float:
	var source: FishSource = FishSource.new()
	source.open()
	var best: float = -1.0
	if source.problem.is_empty() and source.mesh != null and source.atlas != null:
		var surface: int = Checks.surface_by_name(source.mesh, Checks.BODY)
		if surface >= 0:
			var arrays: Array = source.mesh.surface_get_arrays(surface)
			# Width / cell size: the proof atlas is a whole number of cells wide.
			@warning_ignore("integer_division")
			var grid: int = source.atlas.get_width() / Checks.CELL_PIXELS
			for uv: Vector2 in Checks.column_v2(arrays, Mesh.ARRAY_TEX_UV2):
				var pixel: Vector2i = Vector2i(
					floori(uv.x * grid) * Checks.CELL_PIXELS + CELL_HALF,
					floori(uv.y * grid) * Checks.CELL_PIXELS + CELL_HALF
				)
				best = maxf(best, source.atlas.get_pixelv(pixel).s)
	source.release()
	return best


func test_ac08_the_amphora_is_more_saturated_than_stone_and_branch_and_less_than_the_fish() -> void:
	var image: Image = _atlas()
	if image.is_empty():
		return
	var amphora: float = _cell_colour(image, CELL["clay_amphora"]).s
	assert_float(amphora).is_greater(_cell_colour(image, CELL["river_stone"]).s)
	assert_float(amphora).is_greater(_cell_colour(image, CELL["driftwood_branch"]).s)
	var fish: float = _fish_body_saturation_max()
	(
		assert_float(fish)
		. override_failure_message("the proof fish body colours are unreadable")
		. is_greater(0.0)
	)
	assert_float(amphora).is_less(fish)


func test_ac08_the_stone_and_the_branch_carry_vertex_colours_with_a_value_below_1() -> void:
	for id: String in ["river_stone", "driftwood_branch"]:
		var root: Node3D = _open(id)
		if root == null:
			continue
		var found: bool = false
		var lowest: float = 1.0
		for instance: MeshInstance3D in Glb.mesh_instances(root):
			for surface: int in instance.mesh.get_surface_count():
				var arrays: Array = instance.mesh.surface_get_arrays(surface)
				for colour: Color in Checks.column_color(arrays, Mesh.ARRAY_COLOR):
					found = true
					lowest = minf(lowest, minf(colour.r, minf(colour.g, colour.b)))
		assert_bool(found).override_failure_message("%s has no vertex colours" % id).is_true()
		(
			assert_float(lowest)
			. override_failure_message("%s: no vertex colour below 1 (%.3f)" % [id, lowest])
			. is_less(0.999)
		)


# --- AC 8: the shared material (technical-artist stage 2) ---


func test_ac08_every_surface_uses_the_shared_decor_material_with_the_decor_atlas() -> void:
	for id: String in IDS:
		var root: Node3D = _open(id)
		if root == null:
			continue
		var surfaces: int = 0
		for instance: MeshInstance3D in Glb.mesh_instances(root):
			for surface: int in instance.mesh.get_surface_count():
				surfaces += 1
				var material: ShaderMaterial = (
					instance.get_active_material(surface) as ShaderMaterial
				)
				(
					assert_object(material)
					. override_failure_message("%s: not a ShaderMaterial" % id)
					. is_not_null()
				)
				if material == null:
					continue
				assert_str(material.resource_path).is_equal(MATERIAL_PATH)
				assert_object(material.shader).is_not_null()
				if material.shader != null:
					assert_str(material.shader.resource_path).is_equal(SHADER_PATH)
				var atlas: Texture2D = material.get_shader_parameter("palette_atlas") as Texture2D
				(
					assert_object(atlas)
					. override_failure_message("%s: no palette_atlas" % id)
					. is_not_null()
				)
				if atlas != null:
					assert_str(atlas.resource_path).is_equal(ATLAS_PATH)
				var shade: Variant = material.get_shader_parameter("vertex_shade")
				(
					assert_float(float(shade) if shade != null else 0.0)
					. override_failure_message("%s: vertex_shade must be above 0" % id)
					. is_greater(0.0)
				)
		assert_int(surfaces).override_failure_message("%s has no surface" % id).is_greater(0)


func test_ac08_the_three_models_share_one_material_resource() -> void:
	var paths: Dictionary = {}
	for id: String in IDS:
		var root: Node3D = _open(id)
		if root == null:
			continue
		for instance: MeshInstance3D in Glb.mesh_instances(root):
			for surface: int in instance.mesh.get_surface_count():
				var material: Material = instance.get_active_material(surface)
				paths[material.resource_path if material != null else "<none>"] = true
	assert_that(paths.keys()).is_equal([MATERIAL_PATH])
