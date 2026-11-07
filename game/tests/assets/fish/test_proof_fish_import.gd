extends GdUnitTestSuite
## #21 criteria 1, 4, 19, 23: the committed proof_fish.glb imports as one clean mesh scene.
## The import log gate (criterion 1, second half) is a CI script, not a unit test.

const Source := preload("res://tests/helpers/proof_fish_source.gd")
const Checks := preload("res://tests/helpers/proof_fish_checks.gd")
const LfsGuard := preload("res://tests/helpers/lfs_guard.gd")

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


func test_criterion_23_glb_is_not_an_lfs_pointer() -> void:
	assert_str(LfsGuard.problem(_source.glb_path, LfsGuard.GLB_MAGIC)).is_empty()


func test_criterion_01_loads_as_node3d_with_exactly_one_mesh_instance() -> void:
	if not _fish_loaded():
		return
	_expect(Checks.layout_failures(_source.root, _source.mesh))
	assert_int(Source.mesh_instances(_source.root).size()).is_equal(1)


func test_criterion_01_mesh_has_two_surfaces_named_body_and_fin() -> void:
	if not _fish_loaded():
		return
	assert_int(_source.mesh.get_surface_count()).is_equal(2)
	assert_str(Checks.surface_name(_source.mesh, 0)).is_equal("body")
	assert_str(Checks.surface_name(_source.mesh, 1)).is_equal("fin")


func test_criterion_04_light_baking_is_disabled_and_no_lightmap_uv() -> void:
	if not _fish_loaded():
		return
	if _source.import_config == null:
		assert_bool(_source.is_temporary()).is_true()
		return
	_expect(Checks.import_failures(_source.import_config))


func test_criterion_19_root_and_descendants_have_identity_transform() -> void:
	if not _fish_loaded():
		return
	_expect(Checks.transform_failures(_source.root))
