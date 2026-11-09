# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #23 criteria 5, 6 and 11 and the file rules (owner: technical-artist): the water and glass
## shaders and materials. Headless Godot cannot read shader defaults, so every named parameter must
## be stored explicitly in the .tres. The ranges are the issue's, so tuning inside them needs no
## test change.

const SourceScan := preload("res://tests/helpers/source_scan.gd")
const Water := preload("res://tests/helpers/water_rig.gd")
const Table := preload("res://tests/helpers/tank_table.gd")

const SHADER_DIR := "res://shaders/"
const DEPTH_TINT_SHADER := "res://shaders/water_depth_tint.gdshader"
const SURFACE_SHADER := "res://shaders/water_surface.gdshader"
const GLASS_SHADER := "res://shaders/tank_glass.gdshader"
const COMMON_INCLUDE := "res://shaders/water_common.gdshaderinc"
const PLACEHOLDER := "res://assets/tank/materials/glass_placeholder.tres"


func _shader(path: String) -> Shader:
	var exists: bool = ResourceLoader.exists(path)
	assert_bool(exists).override_failure_message("shader missing: %s" % path).is_true()
	if not exists:
		return null
	var shader: Shader = load(path) as Shader
	assert_object(shader).override_failure_message("not a Shader: %s" % path).is_not_null()
	return shader


func _material(path: String) -> ShaderMaterial:
	var exists: bool = ResourceLoader.exists(path)
	assert_bool(exists).override_failure_message("material missing: %s" % path).is_true()
	if not exists:
		return null
	var material: ShaderMaterial = load(path) as ShaderMaterial
	(
		assert_object(material)
		. override_failure_message("not a ShaderMaterial: %s" % path)
		. is_not_null()
	)
	return material


## The uniform entry with this exact name, or an empty dictionary.
func _uniform(shader: Shader, uniform_name: String) -> Dictionary:
	if shader == null:
		return {}
	for entry: Dictionary in shader.get_shader_uniform_list():
		if entry["name"] == uniform_name:
			return entry
	return {}


## [min, max] of a hint_range uniform; empty when the uniform has no range hint.
func _hint_range(entry: Dictionary) -> PackedFloat64Array:
	if entry.is_empty() or int(entry["hint"]) != PROPERTY_HINT_RANGE:
		return PackedFloat64Array()
	var parts: PackedStringArray = String(entry["hint_string"]).split(",")
	if parts.size() < 2:
		return PackedFloat64Array()
	return PackedFloat64Array([parts[0].to_float(), parts[1].to_float()])


func _assert_range_inside(
	shader_path: String, uniform_name: String, low: float, high: float
) -> void:
	var entry: Dictionary = _uniform(_shader(shader_path), uniform_name)
	(
		assert_bool(entry.is_empty())
		. override_failure_message("%s: uniform %s missing" % [shader_path, uniform_name])
		. is_false()
	)
	var range_hint: PackedFloat64Array = _hint_range(entry)
	(
		assert_bool(range_hint.is_empty())
		. override_failure_message("%s: %s has no hint_range" % [shader_path, uniform_name])
		. is_false()
	)
	if range_hint.size() == 2:
		(
			assert_float(range_hint[0])
			. override_failure_message("%s hint minimum" % uniform_name)
			. is_greater_equal(low)
		)
		(
			assert_float(range_hint[1])
			. override_failure_message("%s hint maximum" % uniform_name)
			. is_less_equal(high)
		)


func _assert_stored_in(
	material_path: String, uniform_name: String, low: float, high: float
) -> void:
	var material: ShaderMaterial = _material(material_path)
	if material == null:
		return
	var value: Variant = material.get_shader_parameter(uniform_name)
	(
		assert_that(value)
		. override_failure_message(
			"%s: %s is not stored explicitly" % [material_path, uniform_name]
		)
		. is_not_null()
	)
	if value is float or value is int:
		(
			assert_float(float(value))
			. override_failure_message("%s: %s = %s" % [material_path, uniform_name, value])
			. is_between(low, high)
		)


# --- AC 11: the files exist and parse ---


func test_ac11_each_shader_loads_with_a_non_empty_uniform_list() -> void:
	for path: String in [DEPTH_TINT_SHADER, SURFACE_SHADER, GLASS_SHADER]:
		var shader: Shader = _shader(path)
		if shader != null:
			(
				assert_int(shader.get_shader_uniform_list().size())
				. override_failure_message("%s: no uniforms" % path)
				. is_greater(0)
			)
			assert_int(shader.get_mode()).override_failure_message(path).is_equal(
				Shader.MODE_SPATIAL
			)


func test_ac11_the_shared_include_exists_and_is_used_by_the_depth_tint() -> void:
	(
		assert_bool(FileAccess.file_exists(COMMON_INCLUDE))
		. override_failure_message("%s missing" % COMMON_INCLUDE)
		. is_true()
	)
	var source: String = SourceScan.read(DEPTH_TINT_SHADER)
	assert_str(source).override_failure_message("depth tint must include the common file").contains(
		"water_common.gdshaderinc"
	)


func test_ac11_each_material_uses_its_shader() -> void:
	var pairs: Dictionary = {
		Water.GLASS_MATERIAL: GLASS_SHADER,
		Water.SURFACE_MATERIAL: SURFACE_SHADER,
		Water.DEPTH_TINT_MATERIAL: DEPTH_TINT_SHADER,
	}
	for material_path: String in pairs:
		var material: ShaderMaterial = _material(material_path)
		if material != null and material.shader != null:
			(
				assert_str(material.shader.resource_path)
				. override_failure_message(material_path)
				. is_equal(pairs[material_path])
			)
		elif material != null:
			fail("%s has no shader" % material_path)


func test_ac11_the_materials_use_the_fixed_render_priorities() -> void:
	var expected: Dictionary = {
		Water.DEPTH_TINT_MATERIAL: -2, Water.SURFACE_MATERIAL: -1, Water.GLASS_MATERIAL: 0
	}
	for material_path: String in expected:
		var material: ShaderMaterial = _material(material_path)
		if material != null:
			assert_int(material.render_priority).override_failure_message(material_path).is_equal(
				expected[material_path]
			)


func test_ac11_no_water_shader_reads_the_screen_texture() -> void:
	for path: String in [DEPTH_TINT_SHADER, SURFACE_SHADER, GLASS_SHADER, COMMON_INCLUDE]:
		(
			assert_bool(FileAccess.file_exists(path))
			. override_failure_message("%s missing" % path)
			. is_true()
		)
		var source: String = SourceScan.strip_comments(SourceScan.read(path))
		(
			assert_str(source)
			. override_failure_message("%s reads the screen texture" % path)
			. not_contains("hint_screen_texture")
		)


func test_ac11_the_depth_tint_reads_the_depth_texture_and_draws_back_faces() -> void:
	var source: String = SourceScan.strip_comments(SourceScan.read(DEPTH_TINT_SHADER))
	assert_str(source).contains("hint_depth_texture")
	assert_str(source).contains("cull_front")


func test_ac11_the_surface_is_drawn_from_both_sides() -> void:
	var source: String = SourceScan.strip_comments(SourceScan.read(SURFACE_SHADER))
	assert_str(source).contains("cull_disabled")


# --- AC 6: parameters by exact name, hint range inside the issue range ---


func test_ac06_depth_tint_strength_exists_with_a_range_inside_0_to_1() -> void:
	_assert_range_inside(DEPTH_TINT_SHADER, "depth_tint_strength", 0.0, 1.0)


func test_ac06_depth_tint_color_exists_as_a_colour() -> void:
	var entry: Dictionary = _uniform(_shader(DEPTH_TINT_SHADER), "depth_tint_color")
	assert_bool(entry.is_empty()).override_failure_message("depth_tint_color missing").is_false()
	if not entry.is_empty():
		assert_int(int(entry["type"])).is_equal(TYPE_COLOR)


func test_ac06_meniscus_strength_exists_with_a_range_inside_0_to_1() -> void:
	_assert_range_inside(SURFACE_SHADER, "meniscus_strength", 0.0, 1.0)


func test_ac06_meniscus_width_exists_with_a_range_inside_0_to_6_mm() -> void:
	_assert_range_inside(SURFACE_SHADER, "meniscus_width_m", 0.0, 0.006)


func test_ac06_the_depth_tint_strength_default_lies_in_the_range() -> void:
	_assert_stored_in(Water.DEPTH_TINT_MATERIAL, "depth_tint_strength", 0.0, 1.0)


func test_ac06_the_depth_tint_colour_is_stored_and_opaque() -> void:
	var material: ShaderMaterial = _material(Water.DEPTH_TINT_MATERIAL)
	if material == null:
		return
	var value: Variant = material.get_shader_parameter("depth_tint_color")
	assert_that(value).override_failure_message("depth_tint_color not stored").is_not_null()
	if value is Color:
		assert_float((value as Color).a).is_equal_approx(1.0, 0.0001)


func test_ac06_the_meniscus_defaults_lie_in_the_range() -> void:
	_assert_stored_in(Water.SURFACE_MATERIAL, "meniscus_strength", 0.0, 1.0)
	_assert_stored_in(Water.SURFACE_MATERIAL, "meniscus_width_m", 0.0, 0.006)


func test_ac06_the_fog_preview_density_lies_in_the_range() -> void:
	var exists: bool = ResourceLoader.exists(Water.FOG_MATERIAL)
	assert_bool(exists).override_failure_message("water_fog.tres missing").is_true()
	if not exists:
		return
	var material: FogMaterial = load(Water.FOG_MATERIAL) as FogMaterial
	assert_object(material).is_not_null()
	if material != null:
		assert_float(material.density).is_between(0.0000001, 0.1)


func test_ac06_the_glass_has_one_fixed_edge_tint_and_a_reflection_parameter() -> void:
	var shader: Shader = _shader(GLASS_SHADER)
	if shader == null:
		return
	(
		assert_bool(_uniform(shader, "glass_edge_tint").is_empty())
		. override_failure_message("glass_edge_tint missing")
		. is_false()
	)
	var reflection: PackedStringArray = PackedStringArray()
	for entry: Dictionary in shader.get_shader_uniform_list():
		if String(entry["name"]).begins_with("glass_reflection_"):
			reflection.append(entry["name"])
	(
		assert_int(reflection.size())
		. override_failure_message("no glass_reflection_* parameter")
		. is_greater(0)
	)
	var material: ShaderMaterial = _material(Water.GLASS_MATERIAL)
	if material == null:
		return
	(
		assert_that(material.get_shader_parameter("glass_edge_tint"))
		. override_failure_message("glass_edge_tint not stored in the material")
		. is_not_null()
	)
	for uniform_name: String in reflection:
		(
			assert_that(material.get_shader_parameter(uniform_name))
			. override_failure_message("%s not stored in the material" % uniform_name)
			. is_not_null()
		)


func test_ac06_the_glass_edge_tint_is_not_scaled_by_the_thickness() -> void:
	assert_bool(FileAccess.file_exists(GLASS_SHADER)).is_true()
	var source: String = SourceScan.strip_comments(SourceScan.read(GLASS_SHADER))
	assert_str(source).not_contains("glass_thickness")


# --- Placeholder removal and licence rows ---


func test_the_glass_placeholder_material_is_deleted() -> void:
	(
		assert_bool(FileAccess.file_exists(PLACEHOLDER))
		. override_failure_message("glass_placeholder.tres must be deleted")
		. is_false()
	)


func test_no_glb_import_file_references_the_placeholder() -> void:
	for id: StringName in Table.IDS:
		var text: String = SourceScan.read(Table.glb_path(id) + ".import")
		assert_str(text).override_failure_message("%s.import" % id).is_not_empty()
		(
			assert_str(text)
			. override_failure_message("%s.import still names the placeholder" % id)
			. not_contains("glass_placeholder")
		)
		(
			assert_str(text)
			. override_failure_message("%s.import must name tank_glass.tres" % id)
			. contains("res://assets/tank/materials/tank_glass.tres")
		)


func test_every_new_material_has_a_licence_row_and_the_placeholder_row_is_gone() -> void:
	var text: String = FileAccess.get_file_as_string(
		ProjectSettings.globalize_path("res://").path_join("../docs/asset-licenses.md")
	)
	assert_str(text).is_not_empty()
	for file_name: String in [
		"tank_glass.tres", "water_surface.tres", "water_depth_tint.tres", "water_fog.tres"
	]:
		assert_str(text).override_failure_message("no licence row for %s" % file_name).contains(
			"assets/tank/materials/%s" % file_name
		)
	assert_str(text).not_contains("glass_placeholder.tres")
