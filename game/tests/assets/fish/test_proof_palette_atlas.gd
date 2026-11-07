extends GdUnitTestSuite
## #21 criteria 9 and 23: proof_palette_atlas.png is 64 x 64 px with 16 flat 16 x 16 px cells.

const Source := preload("res://tests/helpers/proof_fish_source.gd")
const Checks := preload("res://tests/helpers/proof_fish_checks.gd")
const LfsGuard := preload("res://tests/helpers/lfs_guard.gd")

var _source: Source = null


func before_test() -> void:
	_source = Source.new()
	_source.open()


func after_test() -> void:
	_source.release()


func test_criterion_23_atlas_is_not_an_lfs_pointer() -> void:
	assert_str(LfsGuard.problem(_source.atlas_path, LfsGuard.PNG_MAGIC)).is_empty()


func test_criterion_09_atlas_is_64x64_with_16_flat_cells() -> void:
	assert_str(LfsGuard.problem(_source.atlas_path, LfsGuard.PNG_MAGIC)).is_empty()
	assert_str(_source.atlas_problem).is_empty()
	if _source.atlas == null:
		return
	assert_str("\n".join(Checks.atlas_failures(_source.atlas))).is_empty()
