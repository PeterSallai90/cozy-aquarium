extends GdUnitTestSuite
## #28 criterion 14, shader and material contract (owner: technical-artist). Headless Godot runs the
## dummy renderer and compiles no shaders, so the shader is checked by source scans after the
## comments are removed (pattern of test_water_shaders.gd): the four instance uniforms of the
## interface, an opaque lit surface, no vertex displacement (relief is shading only, Q13), no
## texture fetch and no screen, depth or normal-roughness reads (technical plan, performance).
## The shared material points at the shader and carries no per-type value. The licence row of the
## material is part of the asset rules.

const Scene := preload("res://tests/helpers/substrate_scene_rig.gd")

const LICENSES := "res://../docs/asset-licenses.md"
const MATERIAL_ROW := "assets/tank/materials/substrate.tres"


## The shader source without // and /* */ comments.
func _code() -> String:
	var source: String = FileAccess.get_file_as_string(Scene.SHADER_PATH)
	var block: RegEx = RegEx.create_from_string("(?s)/\\*.*?\\*/")
	source = block.sub(source, "", true)
	var lines: PackedStringArray = source.split("\n")
	var kept: PackedStringArray = PackedStringArray()
	for line: String in lines:
		var index: int = line.find("//")
		kept.append(line if index < 0 else line.substr(0, index))
	return "\n".join(kept)


func _have_shader() -> bool:
	var found: bool = FileAccess.file_exists(Scene.SHADER_PATH)
	assert_bool(found).override_failure_message("%s is missing" % Scene.SHADER_PATH).is_true()
	return found


func _matches(pattern: String) -> bool:
	return RegEx.create_from_string(pattern).search(_code()) != null


# --- the interface ---


func test_ac14_the_shader_is_a_spatial_shader() -> void:
	if _have_shader():
		assert_bool(_matches("shader_type\\s+spatial\\s*;")).is_true()


func test_ac14_the_tint_is_a_source_colour_instance_uniform() -> void:
	if _have_shader():
		(
			assert_bool(
				_matches("instance\\s+uniform\\s+vec4\\s+substrate_tint\\s*:\\s*source_color")
			)
			. override_failure_message("instance uniform vec4 substrate_tint : source_color")
			. is_true()
		)


func test_ac14_the_three_look_parameters_are_instance_uniforms_of_the_agreed_types() -> void:
	if not _have_shader():
		return
	for declaration: String in [
		"instance\\s+uniform\\s+float\\s+grain_scale\\b",
		"instance\\s+uniform\\s+int\\s+grain_shape\\b",
		"instance\\s+uniform\\s+float\\s+grain_contrast\\b",
	]:
		assert_bool(_matches(declaration)).override_failure_message(declaration).is_true()


# --- an opaque lit surface ---


func test_ac14_the_shader_is_not_unshaded() -> void:
	if _have_shader():
		assert_str(_code()).not_contains("unshaded")


func test_ac14_the_shader_is_opaque_and_writes_depth() -> void:
	if not _have_shader():
		return
	assert_str(_code()).not_contains("blend_")
	assert_str(_code()).not_contains("depth_draw_never")
	assert_str(_code()).not_contains("depth_test_disabled")


func test_ac14_the_shader_does_not_draw_both_sides_or_the_back_faces() -> void:
	if _have_shader():
		assert_str(_code()).not_contains("cull_front")


# --- no displacement, no texture fetch ---


func test_ac14_the_shader_never_assigns_the_vertex() -> void:
	if not _have_shader():
		return
	var assignment: RegEx = RegEx.create_from_string("\\bVERTEX\\b\\s*(\\.\\w+)?\\s*[-+*/]?=(?!=)")
	var hit: RegExMatch = assignment.search(_code())
	(
		assert_bool(hit == null)
		. override_failure_message(
			"the shader assigns VERTEX: '%s'" % [hit.get_string() if hit else ""]
		)
		. is_true()
	)


func test_ac14_the_shader_declares_no_sampler() -> void:
	if _have_shader():
		assert_str(_code()).not_contains("sampler2D")
		assert_str(_code()).not_contains("sampler3D")


func test_ac14_the_shader_reads_no_screen_depth_or_normal_roughness_texture() -> void:
	if not _have_shader():
		return
	for hint: String in [
		"hint_screen_texture", "hint_depth_texture", "hint_normal_roughness_texture", "texture("
	]:
		assert_str(_code()).override_failure_message("the shader uses %s" % hint).not_contains(hint)


func test_ac14_the_shader_has_a_fragment_function_and_sets_albedo() -> void:
	if _have_shader():
		assert_bool(_matches("void\\s+fragment\\s*\\(")).is_true()
		assert_bool(_matches("\\bALBEDO\\b")).is_true()


# --- the material ---


func test_ac14_the_material_exists_and_uses_the_substrate_shader() -> void:
	var exists: bool = ResourceLoader.exists(Scene.MATERIAL_PATH)
	assert_bool(exists).override_failure_message("%s is missing" % Scene.MATERIAL_PATH).is_true()
	if not exists:
		return
	var material: ShaderMaterial = load(Scene.MATERIAL_PATH) as ShaderMaterial
	assert_object(material).is_not_null()
	if material != null and material.shader != null:
		assert_str(material.shader.resource_path).is_equal(Scene.SHADER_PATH)
	else:
		assert_bool(false).override_failure_message("the material has no shader").is_true()


func test_ac14_the_material_holds_no_per_type_value() -> void:
	if not ResourceLoader.exists(Scene.MATERIAL_PATH):
		assert_bool(false).override_failure_message("%s is missing" % Scene.MATERIAL_PATH).is_true()
		return
	var text: String = FileAccess.get_file_as_string(Scene.MATERIAL_PATH)
	assert_str(text).is_not_empty()
	for name: String in ["substrate_tint", "grain_scale", "grain_shape", "grain_contrast"]:
		(
			assert_str(text)
			. override_failure_message(
				(
					"the shared material must not store %s (per-type values are instance uniforms)"
					% name
				)
			)
			. not_contains("shader_parameter/%s" % name)
		)


# --- the asset rule ---


func test_ac14_the_material_has_a_licence_row() -> void:
	var path: String = ProjectSettings.globalize_path("res://").path_join(
		"../docs/asset-licenses.md"
	)
	var text: String = FileAccess.get_file_as_string(path.simplify_path())
	assert_str(text).is_not_empty()
	(
		assert_str(text)
		. override_failure_message("no row for %s in docs/asset-licenses.md" % MATERIAL_ROW)
		. contains("`%s`" % MATERIAL_ROW)
	)
