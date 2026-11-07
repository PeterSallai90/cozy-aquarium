extends GdUnitTestSuite
## #21 criteria 2, 3, 5, 7, 8: triangle budget, UV sets and atlas cells, vertex alpha mask, culling
## and smooth normals of the committed proof_fish.glb. Criterion 5 is the atlas cell test (3) with
## the import flag test (4): a regenerated lightmap UV2 straddles cells and fails here.

const Source := preload("res://tests/helpers/proof_fish_source.gd")
const Checks := preload("res://tests/helpers/proof_fish_checks.gd")

var _source: Source = null


func before_test() -> void:
	_source = Source.new()
	_source.open()


func after_test() -> void:
	_source.release()


func _expect(failures: PackedStringArray) -> void:
	assert_str("\n".join(failures)).is_empty()


func _fish_loaded() -> bool:
	assert_str(_source.problem).is_empty()
	return _source.problem.is_empty() and _source.mesh != null


func test_criterion_02_triangle_total_is_within_the_fish_budget() -> void:
	if _fish_loaded():
		_expect(Checks.budget_failures(_source.mesh))


func test_criterion_03_every_surface_has_uv_and_uv2() -> void:
	if _fish_loaded():
		_expect(Checks.uv_array_failures(_source.mesh))


func test_criterion_03_every_triangle_sits_inside_one_atlas_cell() -> void:
	if _fish_loaded():
		_expect(Checks.atlas_cell_failures(_source.mesh))


func test_criterion_05_uv2_is_not_a_regenerated_lightmap() -> void:
	if not _fish_loaded():
		return
	_expect(Checks.atlas_cell_failures(_source.mesh))
	_expect(Checks.import_failures(_source.import_config))


func test_criterion_07_vertex_alpha_is_a_binary_fin_mask() -> void:
	if _fish_loaded():
		_expect(Checks.alpha_failures(_source.mesh))


func test_criterion_08a_fin_is_double_sided_and_body_is_not() -> void:
	if _fish_loaded():
		_expect(Checks.cull_failures(_source.mesh))


func test_criterion_08b_body_normals_are_smooth_across_split_vertices() -> void:
	if _fish_loaded():
		_expect(Checks.smooth_normal_failures(_source.mesh))
