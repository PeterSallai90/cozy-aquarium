extends GdUnitTestSuite
## #33 AC 15 (d), file group: technical-artist (shader and material, architect addendum 2 section
## 1): the selection glow shader gets the linear-light uniform glow_lift (vec3, default zero, no
## source_color hint, so no sRGB conversion) that the refusal cue drives, and
## item_selection_material.tres carries the zero default. The blend is premultiplied alpha (the
## intended output is dst * (1 - a) + glow_colour * a + glow_lift * fresnel); when Godot cannot
## meet the identity proof, the fallback is a separate additive pass in
## item_refusal_lift.gdshader (blend_add, same
## fresnel term, uniforms glow_lift and fresnel_power). Either way the three existing uniforms keep
## their names, ranges and defaults, and the shader reads no screen, depth or normal texture
## (test_placement_materials.gd covers that and stays unchanged).
## The identity of the default look (renders, at most 1/255 per channel) is a preview check by the
## technical-artist, not a test here.

const GLOW_SHADER := "res://shaders/item_selection_glow.gdshader"
const LIFT_SHADER := "res://shaders/item_refusal_lift.gdshader"
const MATERIAL := "res://scenes/tank/items/item_selection_material.tres"


func _source(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _matches(text: String, pattern: String) -> bool:
	var regex: RegEx = RegEx.new()
	regex.compile(pattern)
	return regex.search(text) != null


func _uses_fallback_pass() -> bool:
	return ResourceLoader.exists(LIFT_SHADER)


func test_the_glow_shader_declares_glow_lift_as_a_linear_vec3_with_a_zero_default() -> void:
	var source: String = _source(GLOW_SHADER)
	if _uses_fallback_pass():
		source = _source(LIFT_SHADER)
	(
		assert_bool(_matches(source, "uniform\\s+vec3\\s+glow_lift\\s*="))
		. override_failure_message("no `uniform vec3 glow_lift = ...` in the glow shader")
		. is_true()
	)
	(
		assert_bool(
			_matches(
				source,
				"uniform\\s+vec3\\s+glow_lift\\s*=\\s*vec3\\(\\s*0(\\.0*)?\\s*(,\\s*0(\\.0*)?\\s*){2}\\)"
			)
		)
		. override_failure_message("glow_lift must default to vec3(0.0)")
		. is_true()
	)
	assert_bool(_matches(source, "uniform\\s+vec3\\s+glow_lift\\s*:")).is_false()


func _declares_range(
	source: String, uniform_name: String, low: String, high: String, default: String
) -> bool:
	var pattern: String = (
		"uniform\\s+float\\s+"
		+ uniform_name
		+ "\\s*:\\s*hint_range\\(\\s*"
		+ low
		+ "\\s*,\\s*"
		+ high
		+ "\\s*\\)\\s*=\\s*"
		+ default
	)
	return _matches(source, pattern)


func test_the_glow_shader_keeps_the_three_uniforms_ranges_and_defaults() -> void:
	var source: String = _source(GLOW_SHADER)
	assert_bool(_matches(source, "uniform\\s+vec4\\s+glow_colour\\s*:\\s*source_color")).is_true()
	assert_bool(_matches(source, "vec4\\(\\s*1\\.0\\s*,\\s*0\\.86\\s*,\\s*0\\.62\\s*,")).is_true()
	assert_bool(_declares_range(source, "fresnel_strength", "0\\.0", "1\\.0", "0\\.7")).is_true()
	assert_bool(_declares_range(source, "fresnel_power", "0\\.5", "8\\.0", "1\\.6")).is_true()


func test_the_glow_blends_premultiplied_or_adds_in_a_separate_pass() -> void:
	var source: String = _source(GLOW_SHADER)
	if _uses_fallback_pass():
		var lift_source: String = _source(LIFT_SHADER)
		assert_bool(_matches(lift_source, "blend_add")).is_true()
		assert_bool(_matches(lift_source, "uniform\\s+float\\s+fresnel_power")).is_true()
		assert_bool(_matches(lift_source, "\\bfresnel\\b")).is_true()
		assert_bool(_matches(source, "blend_mix")).is_true()
	else:
		assert_bool(_matches(source, "blend_premul_alpha")).is_true()
		assert_bool(_matches(source, "blend_mix")).is_false()
		# The lift is added scaled by the fresnel term, not by the alpha.
		assert_bool(_matches(source, "glow_lift\\s*\\*\\s*fresnel")).is_true()


func test_the_render_modes_of_the_overlay_are_kept() -> void:
	var source: String = _source(GLOW_SHADER)
	for mode: String in ["unshaded", "cull_back", "depth_draw_never", "shadows_disabled"]:
		assert_bool(_matches(source, "\\b%s\\b" % mode)).override_failure_message(mode).is_true()


func test_the_selection_material_carries_a_zero_glow_lift_default() -> void:
	var material: ShaderMaterial = load(MATERIAL) as ShaderMaterial
	assert_object(material).is_not_null()
	var lift: Variant = material.get_shader_parameter("glow_lift")
	(
		assert_bool(lift is Vector3)
		. override_failure_message("item_selection_material.tres has no shader_parameter/glow_lift")
		. is_true()
	)
	if lift is Vector3:
		assert_bool((lift as Vector3).is_equal_approx(Vector3.ZERO)).is_true()


func test_the_selection_material_keeps_its_other_values() -> void:
	var material: ShaderMaterial = load(MATERIAL) as ShaderMaterial
	assert_float(float(material.get_shader_parameter("fresnel_strength"))).is_equal(0.7)
	assert_float(float(material.get_shader_parameter("fresnel_power"))).is_equal(1.6)
	var colour: Color = material.get_shader_parameter("glow_colour")
	assert_bool(colour.is_equal_approx(Color(1.0, 0.86, 0.62, 1.0))).is_true()
	assert_int(material.render_priority).is_equal(-1)
	assert_str(material.shader.resource_path).is_equal(GLOW_SHADER)
	assert_object(material.next_pass).is_null()
