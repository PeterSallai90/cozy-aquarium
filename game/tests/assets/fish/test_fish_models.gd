extends GdUnitTestSuite
## #34 AC 7, 9 and 10 (owner: technical-artist, stage 1): the three species models
## game/assets/fish/<id>.glb. AC 7 repeats the #21 rules (AC 1 to 8 and 19) for each file: one
## MeshInstance3D, identity transforms, 800 to 2,500 triangles, UV and UV2 with every UV2 triangle
## inside one atlas cell, body vertex alpha 0 and fin vertex alpha 1, a double-sided fin material
## and a single-sided body material, smooth body normals, a body 1 unit long and centred on the
## origin with the head towards +Z, and meshes/light_baking 0 in the .import file. AC 9 and 10 bind
## the real size and the silhouette numbers with the measurement methods of the technical plan.
## Test decisions: the surface roles and the double-sided flags come from the glTF JSON (the
## imported material is the external species material, ADR 0013 rule 2); the corydoras and
## angelfish thickness needs the mask (UV0 band 0); the tolerance of 1 percent applies to AC 10
## ranges and to the body length, not to the AC 9 total lengths (inclusive bounds). The proof fish
## files are pinned by their SHA-256 at the base commit a3b864d (nothing in #34 may change them).

const Api := preload("res://tests/helpers/fish_api.gd")
const Checks := preload("res://tests/helpers/fish_species_checks.gd")

const PROOF_HASHES: Dictionary[String, String] = {
	"res://assets/fish/proof_fish.glb":
	"e75c3be34607ee24744857ce975b5eec267c22aae48ed1b99c0b406625a2dd0d",
	"res://assets/fish/proof_palette_atlas.png":
	"f9fd8b8b11d7c14d018debda2d7dc3c74b8850c1a9705f931c0dce9cfc665f58",
	"res://assets/fish/proof_fish.glb.import":
	"63ec78d2bd1a094892e8ee61c1c991885bf5a62ee7fe4bb25cf354f2c299cd7e",
	"res://assets/fish/proof_palette_atlas.png.import":
	"6b9531b36259bf09251871584990c1e4c52a3241631d705d8edaa143c092495a",
}

var _models: Dictionary[StringName, Checks.FishModel] = {}


func before_test() -> void:
	for id: StringName in Api.IDS:
		_models[id] = Checks.open(id)


func after_test() -> void:
	for id: StringName in _models:
		_models[id].release()
	_models.clear()


## Runs `rule` on every species that loaded; a species that did not load fails with its cause.
func _each(rule: Callable) -> void:
	for id: StringName in Api.IDS:
		var model: Checks.FishModel = _models[id]
		(
			assert_str(model.problem)
			. override_failure_message("%s: %s" % [id, model.problem])
			. is_empty()
		)
		if not model.problem.is_empty():
			continue
		var failures: PackedStringArray = rule.call(model)
		(
			assert_str("\n".join(failures))
			. override_failure_message("%s: %s" % [id, "; ".join(failures)])
			. is_empty()
		)


func _measure(id: StringName) -> Dictionary:
	var model: Checks.FishModel = _models[id]
	if not model.problem.is_empty():
		return {}
	var mask: Image = Checks.load_mask(id)
	assert_object(mask).override_failure_message("%s: mask is missing" % id).is_not_null()
	return Checks.measure(model, mask)


# --- AC 7 ---


func test_ac07_layout_budget_uv_arrays_and_import_flags() -> void:
	_each(Checks.layout_failures)


func test_ac07_every_uv2_triangle_sits_inside_one_atlas_cell() -> void:
	_each(Checks.atlas_cell_failures)


func test_ac07_vertex_alpha_is_a_binary_fin_mask() -> void:
	_each(Checks.alpha_failures)


func test_ac07_fin_is_double_sided_and_body_is_not() -> void:
	_each(Checks.cull_failures)


func test_ac07_body_normals_are_smooth_across_split_vertices() -> void:
	_each(Checks.smooth_normal_failures)


func test_ac07_body_is_one_unit_long_centred_with_the_head_towards_plus_z() -> void:
	_each(Checks.body_failures)


# --- AC 9 ---


func test_ac09_body_length_equals_the_adult_length_within_one_percent() -> void:
	for id: StringName in Api.IDS:
		var model: Checks.FishModel = _models[id]
		(
			assert_str(model.problem)
			. override_failure_message("%s: %s" % [id, model.problem])
			. is_empty()
		)
		if not model.problem.is_empty():
			continue
		var scaled_cm: float = Checks.span(Checks.body_points(model), 2) * Checks.ADULT_CM[id]
		(
			assert_float(scaled_cm)
			. override_failure_message("%s: scaled body length %.3f cm" % [id, scaled_cm])
			. is_between(Checks.ADULT_CM[id] * 0.99, Checks.ADULT_CM[id] * 1.01)
		)


func test_ac09_total_length_including_fins_is_in_the_species_range() -> void:
	for id: StringName in Api.IDS:
		var model: Checks.FishModel = _models[id]
		(
			assert_str(model.problem)
			. override_failure_message("%s: %s" % [id, model.problem])
			. is_empty()
		)
		if not model.problem.is_empty():
			continue
		var total: float = Checks.span(Checks.all_points(model), 2)
		var range_units: Vector2 = Checks.TOTAL_UNITS[id]
		(
			assert_float(total)
			. override_failure_message(
				(
					"%s: total length %.3f units, need %.2f to %.2f"
					% [id, total, range_units.x, range_units.y]
				)
			)
			. is_between(range_units.x, range_units.y)
		)


func test_ac09_true_relative_sizes_hold() -> void:
	var lengths: Dictionary[StringName, float] = {}
	for id: StringName in Api.IDS:
		var model: Checks.FishModel = _models[id]
		(
			assert_str(model.problem)
			. override_failure_message("%s: %s" % [id, model.problem])
			. is_empty()
		)
		if not model.problem.is_empty():
			return
		lengths[id] = Checks.span(Checks.body_points(model), 2) * Checks.ADULT_CM[id]
	assert_float(lengths[&"angelfish"] / lengths[&"neon_tetra"]).is_greater_equal(3.0)
	assert_float(lengths[&"bronze_corydoras"] / lengths[&"neon_tetra"]).is_greater_equal(1.5)


# --- AC 10 ---


func test_ac10_neon_tetra_silhouette() -> void:
	var numbers: Dictionary = _measure(&"neon_tetra")
	assert_bool(numbers.is_empty()).override_failure_message("neon tetra did not load").is_false()
	if numbers.is_empty():
		return
	var failures: PackedStringArray = Checks.silhouette_failures(&"neon_tetra", numbers)
	assert_str("; ".join(failures)).is_empty()


func test_ac10_angelfish_silhouette() -> void:
	var numbers: Dictionary = _measure(&"angelfish")
	assert_bool(numbers.is_empty()).override_failure_message("angelfish did not load").is_false()
	if numbers.is_empty():
		return
	var failures: PackedStringArray = Checks.silhouette_failures(&"angelfish", numbers)
	assert_str("; ".join(failures)).is_empty()


func test_ac10_bronze_corydoras_silhouette() -> void:
	var numbers: Dictionary = _measure(&"bronze_corydoras")
	assert_bool(numbers.is_empty()).override_failure_message("corydoras did not load").is_false()
	if numbers.is_empty():
		return
	var failures: PackedStringArray = Checks.silhouette_failures(&"bronze_corydoras", numbers)
	assert_str("; ".join(failures)).is_empty()


func test_ac10_neon_stripe_and_red_region_extents_follow_the_mask() -> void:
	var model: Checks.FishModel = _models[&"neon_tetra"]
	assert_str(model.problem).is_empty()
	var mask: Image = Checks.load_mask(&"neon_tetra")
	assert_object(mask).override_failure_message("neon tetra mask is missing").is_not_null()
	if not model.problem.is_empty() or mask == null:
		return
	assert_str("; ".join(Checks.neon_extent_failures(model, mask))).is_empty()


func test_ac10_edge_the_silhouette_check_rejects_numbers_outside_the_ranges() -> void:
	var good: Dictionary = {
		"body_depth": 0.24,
		"total_height": 1.0,
		"thickness": 0.1,
		"belly_variation": 0.02,
		"barbel_lengths": [],
		"barbel_vertices_beyond": 0,
	}
	assert_int(Checks.silhouette_failures(&"neon_tetra", good).size()).is_equal(0)
	var deep: Dictionary = good.duplicate()
	deep["body_depth"] = 0.40
	assert_int(Checks.silhouette_failures(&"neon_tetra", deep).size()).is_greater(0)
	var flat_angel: Dictionary = {
		"body_depth": 0.75,
		"total_height": 1.1,
		"thickness": 0.22,
		"belly_variation": 0.0,
		"barbel_lengths": [],
		"barbel_vertices_beyond": 0,
	}
	assert_int(Checks.silhouette_failures(&"angelfish", flat_angel).size()).is_greater(0)
	var wobbly_cory: Dictionary = {
		"body_depth": 0.30,
		"total_height": 0.5,
		"thickness": 0.2,
		"belly_variation": 0.09,
		"dorsal_reach": 0.27,
		"barbel_lengths": [0.08, 0.08, 0.08],
		"barbel_vertices_beyond": 0,
	}
	assert_int(Checks.silhouette_failures(&"bronze_corydoras", wobbly_cory).size()).is_greater(1)


# --- the proof fish stays as it is ---


func test_the_proof_fish_files_are_byte_identical_to_the_base_commit() -> void:
	for path: String in PROOF_HASHES:
		(
			assert_str(FileAccess.get_sha256(path))
			. override_failure_message("%s changed (the #21 tests bind it)" % path)
			. is_equal(PROOF_HASHES[path])
		)
