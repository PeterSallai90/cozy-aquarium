# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #21 criteria 4, 5, 15, 17, 23: the rule checks must fail, and name the broken rule, on bad data.
## Synthetic meshes only: no committed fixtures.

const Checks := preload("res://tests/helpers/proof_fish_checks.gd")
const LfsGuard := preload("res://tests/helpers/lfs_guard.gd")

const POINTER_TEXT := (
	"version https://git-lfs.github.com/spec/v1\n"
	+ "oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393\n"
	+ "size 12345\n"
)
const POINTER_PATH := "user://proof_fish_lfs_pointer_test.glb"


func after_test() -> void:
	if FileAccess.file_exists(POINTER_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(POINTER_PATH))


func _material(label: String, cull: BaseMaterial3D.CullMode) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.resource_name = label
	material.cull_mode = cull
	return material


func _cell_uv(cell: Vector2i) -> PackedVector2Array:
	var centre: Vector2 = (Vector2(cell) + Vector2(0.5, 0.5)) / 4.0
	return PackedVector2Array(
		[centre + Vector2(-0.02, -0.02), centre + Vector2(0.02, -0.02), centre + Vector2(0.0, 0.02)]
	)


## One surface per entry: {"name", "vertices", "uv2" (optional), "alpha" (optional)}.
func _mesh(surfaces: Array[Dictionary]) -> ArrayMesh:
	var mesh: ArrayMesh = ArrayMesh.new()
	for spec: Dictionary in surfaces:
		var vertices: PackedVector3Array = spec["vertices"]
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		var uv: PackedVector2Array = PackedVector2Array()
		var colors: PackedColorArray = PackedColorArray()
		for i: int in vertices.size():
			uv.append(Vector2.ZERO)
			colors.append(Color(1.0, 1.0, 1.0, float(spec.get("alpha", 0.0))))
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_COLOR] = colors
		if spec.has("uv2"):
			arrays[Mesh.ARRAY_TEX_UV2] = spec["uv2"]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var cull: BaseMaterial3D.CullMode = BaseMaterial3D.CULL_BACK
		if spec["name"] == "fin":
			cull = BaseMaterial3D.CULL_DISABLED
		mesh.surface_set_material(mesh.get_surface_count() - 1, _material(spec["name"], cull))
	return mesh


## count triangles, all in one atlas cell.
func _triangles(label: String, count: int, cell: Vector2i, alpha: float) -> Dictionary:
	var vertices: PackedVector3Array = PackedVector3Array()
	var uv2: PackedVector2Array = PackedVector2Array()
	for t: int in count:
		vertices.append_array(
			PackedVector3Array([Vector3(t, 0, 0), Vector3(t, 1, 0), Vector3(t, 0, 1)])
		)
		uv2.append_array(_cell_uv(cell))
	return {"name": label, "vertices": vertices, "uv2": uv2, "alpha": alpha}


func _fish(body_count: int, fin_count: int) -> ArrayMesh:
	var body: Dictionary = _triangles("body", body_count, Vector2i(1, 1), 0.0)
	var fin: Dictionary = _triangles("fin", fin_count, Vector2i(2, 1), 1.0)
	return _mesh([body, fin])


## A hand-built tetra: body box 1.0 long, caudal behind it, dorsal, pectoral pair.
## extra_fins: more fin vertices (three per triangle) appended after the pectorals.
func _tetra(
	caudal_z: float, right_pectoral_x: float, extra_fins: PackedVector3Array = PackedVector3Array()
) -> ArrayMesh:
	var body: PackedVector3Array = PackedVector3Array()
	for x: float in [-0.07, 0.07]:
		for y: float in [-0.125, 0.125]:
			for z: float in [-0.5, 0.5]:
				body.append(Vector3(x, y, z))
	body.append(Vector3(0.07, 0.125, 0.5))
	var fins: PackedVector3Array = PackedVector3Array(
		[
			Vector3(0, 0.05, caudal_z),
			Vector3(0, -0.05, caudal_z),
			Vector3(0, 0, -0.5),
			Vector3(0, 0.30, 0.1),
			Vector3(0, 0.125, 0.0),
			Vector3(0, 0.125, 0.2),
			Vector3(right_pectoral_x, 0, 0.0),
			Vector3(right_pectoral_x, 0, 0.13),
			Vector3(right_pectoral_x, -0.05, 0.1),
			Vector3(-0.07, 0, 0.0),
			Vector3(-0.07, 0, 0.13),
			Vector3(-0.07, -0.05, 0.1),
		]
	)
	fins.append_array(extra_fins)
	return _mesh([{"name": "body", "vertices": body}, {"name": "fin", "vertices": fins}])


func _joined(failures: PackedStringArray) -> String:
	return "\n".join(failures)


func _write(bytes: PackedByteArray) -> void:
	var file: FileAccess = FileAccess.open(POINTER_PATH, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


# --- criterion 15: broken rules fail with the rule named ---


func test_criterion_15_light_baking_one_names_the_rule() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("params", "meshes/light_baking", 1)
	assert_str(_joined(Checks.import_failures(config))).contains("meshes/light_baking")


func test_criterion_15_light_baking_missing_counts_as_the_engine_default_one() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("params", "_subresources", {})
	assert_str(_joined(Checks.import_failures(config))).contains("meshes/light_baking")


func test_criterion_04_light_baking_zero_passes() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("params", "meshes/light_baking", 0)
	config.set_value("params", "_subresources", {})
	assert_array(Checks.import_failures(config)).is_empty()


func test_criterion_04_lightmap_uv_in_nested_subresources_fails() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("params", "meshes/light_baking", 0)
	var nested: Dictionary = {"nodes": {"PATH:proof_fish": {"generate/lightmap_uv": 1}}}
	config.set_value("params", "_subresources", nested)
	assert_str(_joined(Checks.import_failures(config))).contains("generate/lightmap_uv")


func test_criterion_15_more_than_2500_triangles_names_the_budget() -> void:
	assert_str(_joined(Checks.budget_failures(_fish(2000, 501)))).contains("triangle budget: 2501")


func test_criterion_02_exactly_2500_and_800_triangles_pass() -> void:
	assert_array(Checks.budget_failures(_fish(2000, 500))).is_empty()
	assert_array(Checks.budget_failures(_fish(700, 100))).is_empty()


func test_criterion_02_799_triangles_fail_the_faceted_look_floor() -> void:
	assert_str(_joined(Checks.budget_failures(_fish(700, 99)))).contains("triangle budget: 799")


func test_criterion_15_missing_uv2_names_the_uv2_array() -> void:
	var body: Dictionary = _triangles("body", 3, Vector2i(1, 1), 0.0)
	body.erase("uv2")
	var mesh: ArrayMesh = _mesh([body, _triangles("fin", 3, Vector2i(2, 1), 1.0)])
	assert_str(_joined(Checks.uv_array_failures(mesh))).contains("UV2 missing on surface body")


func test_criterion_05_lightmap_like_uv2_straddling_cells_fails() -> void:
	var body: Dictionary = _triangles("body", 1, Vector2i(1, 1), 0.0)
	body["uv2"] = PackedVector2Array(
		[Vector2(0.75, 0.08), Vector2(0.92, 0.08), Vector2(0.75, 0.92)]
	)
	var mesh: ArrayMesh = _mesh([body, _triangles("fin", 1, Vector2i(2, 1), 1.0)])
	assert_str(_joined(Checks.atlas_cell_failures(mesh))).contains("atlas cell")


func test_criterion_03_vertex_on_the_cell_edge_fails_the_half_texel_inset() -> void:
	var body: Dictionary = _triangles("body", 1, Vector2i(1, 1), 0.0)
	body["uv2"] = PackedVector2Array(
		[Vector2(0.255, 0.30), Vector2(0.30, 0.30), Vector2(0.28, 0.40)]
	)
	var mesh: ArrayMesh = _mesh([body, _triangles("fin", 1, Vector2i(2, 1), 1.0)])
	assert_str(_joined(Checks.atlas_cell_failures(mesh))).contains("atlas cell")


func test_criterion_03_vertex_inside_the_inset_within_tolerance_passes() -> void:
	var body: Dictionary = _triangles("body", 1, Vector2i(1, 1), 0.0)
	var edge: float = 0.25 + 1.0 / 128.0 - 0.00005
	body["uv2"] = PackedVector2Array([Vector2(edge, 0.3), Vector2(0.4, 0.3), Vector2(0.3, 0.4)])
	var mesh: ArrayMesh = _mesh([body, _triangles("fin", 1, Vector2i(2, 1), 1.0)])
	assert_array(Checks.atlas_cell_failures(mesh)).is_empty()


func test_criterion_03_body_and_fin_in_the_same_cell_fail() -> void:
	var body: Dictionary = _triangles("body", 2, Vector2i(1, 1), 0.0)
	var fin: Dictionary = _triangles("fin", 2, Vector2i(1, 1), 1.0)
	assert_str(_joined(Checks.atlas_cell_failures(_mesh([body, fin])))).contains("share cell")


func test_criterion_03_a_single_cell_for_everything_fails() -> void:
	var mesh: ArrayMesh = _mesh([_triangles("body", 2, Vector2i(3, 3), 0.0)])
	assert_str(_joined(Checks.atlas_cell_failures(mesh))).contains("at least 2")


func test_criterion_03_two_surfaces_in_two_cells_pass() -> void:
	assert_array(Checks.atlas_cell_failures(_fish(3, 3))).is_empty()


func test_criterion_07_translucent_body_or_opaque_fin_fails() -> void:
	var body: Dictionary = _triangles("body", 1, Vector2i(1, 1), 0.5)
	var fin: Dictionary = _triangles("fin", 1, Vector2i(2, 1), 0.5)
	var text: String = _joined(Checks.alpha_failures(_mesh([body, fin])))
	assert_str(text).contains("vertex alpha")
	assert_array(Checks.alpha_failures(_fish(1, 1))).is_empty()


func test_criterion_08_single_sided_fin_fails() -> void:
	var mesh: ArrayMesh = _fish(1, 1)
	(mesh.surface_get_material(1) as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_BACK
	assert_str(_joined(Checks.cull_failures(mesh))).contains("double-sided")


# --- criteria 6 and 17: real size on synthetic fish ---


func test_criterion_17_a_well_formed_tetra_passes_every_size_rule() -> void:
	var mesh: ArrayMesh = _tetra(-0.72, 0.07)
	assert_array(Checks.size_failures(mesh)).is_empty()
	assert_array(Checks.body_failures(mesh)).is_empty()


func test_criterion_17_stub_caudal_fails() -> void:
	var text: String = _joined(Checks.size_failures(_tetra(-0.51, 0.07)))
	assert_str(text).contains("real size")
	assert_str(text).contains("caudal")


func test_criterion_17_betta_style_trailing_tail_fails_the_ceiling() -> void:
	var text: String = _joined(Checks.size_failures(_tetra(-2.0, 0.07)))
	assert_str(text).contains("8 cm ceiling")


func test_criterion_17_unmirrored_pectoral_pair_fails() -> void:
	var text: String = _joined(Checks.size_failures(_tetra(-0.72, 0.09)))
	assert_str(text).contains("mirrored")


# --- #115 criteria 5 and 6: only the caudal may lie behind the tail end ---


func test_criterion_05_dorsal_behind_the_tail_fails_as_non_caudal() -> void:
	# Second dorsal triangle shares two positions with the dorsal, its tip is behind the tail.
	var extra: PackedVector3Array = PackedVector3Array(
		[Vector3(0, 0.30, 0.1), Vector3(0, 0.125, 0.0), Vector3(0, 0.20, -0.6)]
	)
	var text: String = _joined(Checks.size_failures(_tetra(-0.72, 0.07, extra)))
	assert_str(text).contains("fins extend Z: ")
	assert_str(text).contains("non-caudal centre-plane fin lies behind the tail")


func test_criterion_05_dorsal_tail_piece_is_caught_through_its_connection() -> void:
	# The last triangle alone starts within 0.10 of the tail end, but it is chained to the dorsal
	# (front at z 0.2), so the component is not a caudal. The rule works per component.
	var extra: PackedVector3Array = PackedVector3Array(
		[
			Vector3(0, 0.125, 0.0),
			Vector3(0, 0.30, 0.1),
			Vector3(0, 0.15, -0.45),
			Vector3(0, 0.15, -0.45),
			Vector3(0, 0.13, -0.42),
			Vector3(0, 0.20, -0.6),
		]
	)
	var text: String = _joined(Checks.size_failures(_tetra(-0.72, 0.07, extra)))
	assert_str(text).contains("fins extend Z: ")
	assert_str(text).contains("non-caudal centre-plane fin lies behind the tail")


## Guard against a too strict rule: green before and after the fix.
func test_criterion_06_caudal_behind_the_tail_with_dorsal_inside_the_body_passes() -> void:
	for caudal_z: float in [-0.72, -0.66]:
		var text: String = _joined(Checks.size_failures(_tetra(caudal_z, 0.07)))
		assert_str(text).not_contains("fins extend Z")


# --- criterion 23: LFS pointer ---


func test_criterion_23_pointer_file_says_run_git_lfs_pull() -> void:
	_write(POINTER_TEXT.to_ascii_buffer())
	var text: String = LfsGuard.problem(POINTER_PATH, LfsGuard.GLB_MAGIC)
	assert_str(text).contains("LFS pointer, run git lfs pull")


func test_criterion_23_missing_and_wrong_files_are_named() -> void:
	var missing: String = LfsGuard.problem("user://proof_fish_no_such.glb", LfsGuard.GLB_MAGIC)
	assert_str(missing).contains("missing")
	_write(PackedByteArray([0x50, 0x4B, 0x03, 0x04, 0x00]))
	assert_str(LfsGuard.problem(POINTER_PATH, LfsGuard.GLB_MAGIC)).contains("not a glb file")


func test_criterion_23_real_glb_and_png_headers_pass() -> void:
	_write(LfsGuard.GLB_MAGIC + PackedByteArray([2, 0, 0, 0]))
	assert_str(LfsGuard.problem(POINTER_PATH, LfsGuard.GLB_MAGIC)).is_empty()
	_write(LfsGuard.PNG_MAGIC + PackedByteArray([0x0D, 0x0A, 0x1A, 0x0A]))
	assert_str(LfsGuard.problem(POINTER_PATH, LfsGuard.PNG_MAGIC)).is_empty()
