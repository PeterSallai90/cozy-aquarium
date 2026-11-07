extends GdUnitTestSuite
## #21 criteria 6 and 17: unit body length, origin, front axis (+Z) and real size of the fins.

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


func test_criterion_06_body_is_one_unit_long_and_centred_on_the_origin() -> void:
	if _fish_loaded():
		_expect(Checks.body_failures(_source.mesh))


func test_criterion_06_head_points_to_positive_z_through_the_eye_faces() -> void:
	if not _fish_loaded():
		return
	assert_str(_source.atlas_problem).is_empty()
	if _source.atlas != null:
		_expect(Checks.eye_failures(_source.mesh, _source.atlas))


func test_criterion_17_total_length_is_a_tetra_with_a_forked_tail() -> void:
	if not _fish_loaded():
		return
	var failures: PackedStringArray = Checks.size_failures(_source.mesh)
	var total: String = "\n".join(failures)
	assert_str(total).is_empty()


func test_criterion_17_fin_sizes_and_pectoral_symmetry() -> void:
	if not _fish_loaded():
		return
	var all_failures: PackedStringArray = Checks.size_failures(_source.mesh)
	var fin_rules: PackedStringArray = PackedStringArray()
	for failure: String in all_failures:
		if not failure.begins_with("real size"):
			fin_rules.append(failure)
	_expect(fin_rules)
