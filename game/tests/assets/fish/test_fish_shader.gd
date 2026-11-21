# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #34 AC 20, 21, 23 (automatic edges), 30, 33 (variant 0) and 37 (blend) (owner: technical-artist,
## stage 2): the fish shader game/shaders/fish.gdshader and its include fish_common.gdshaderinc
## (ADR 0013 rule 5, technical plan section 1). Headless Godot runs the dummy renderer and compiles
## no shaders, so the contract is tested three ways: the declared parameters (material uniforms
## through Shader.get_shader_uniform_list, instance uniforms by a source scan after the comments
## are removed), a scan that pins the eight constant lines of the include to the constants of the
## CPU twin (tests/helpers/fish_shader_twin.gd), and the twin itself, which holds the shader math
## in GDScript with GLSL semantics. The bend is sampled over the real species vertices with the
## real material values, so the species files and materials are needed for those tests.
## Test decisions: the shipped neon shimmer is evaluated on the stripe base colour region_r_colour
## (linear), the two view angles are N.V 1.0 and 0.3 and the threshold is 0.10; shader defaults of
## float parameters are read from the shader source when a material does not set them; the order of
## the fragment colour steps is checked as first-use positions in the source.

const Api := preload("res://tests/helpers/fish_api.gd")
const Checks := preload("res://tests/helpers/fish_species_checks.gd")
const Twin := preload("res://tests/helpers/fish_shader_twin.gd")

const SHADER := "res://shaders/fish.gdshader"
const INCLUDE := "res://shaders/fish_common.gdshaderinc"
const MATERIAL_UNIFORMS: PackedStringArray = [
	"palette_atlas",
	"fish_mask",
	"region_r_colour",
	"region_g_colour",
	"eye_colour",
	"eye_iris_colour",
	"eye_highlight_colour",
	"eye_highlight_strength",
	"eye_glint_strength",
	"transmission_strength",
	"transmission_color",
	"fin_opacity",
	"roughness",
	"specular_amount",
	"metallic",
	"swim_amplitude",
	"swim_frequency",
	"swim_speed_scale",
	"shimmer_strength",
	"shimmer_colour_a",
	"shimmer_colour_b",
	"shimmer_power",
	"variant_tint_keep",
]
const COLOUR_UNIFORMS: PackedStringArray = [
	"region_r_colour",
	"region_g_colour",
	"eye_colour",
	"eye_iris_colour",
	"eye_highlight_colour",
	"transmission_color",
	"shimmer_colour_a",
	"shimmer_colour_b",
]
const INSTANCE_UNIFORMS: Dictionary[String, String] = {
	"variant_tint_colour": "vec4",
	"variant_tint_strength": "float",
	"swim_phase": "float",
	"swim_speed": "float",
}
const BEND_DEFAULTS: Dictionary[String, float] = {
	"swim_amplitude": 0.10,
	"swim_frequency": 1.5,
	"swim_speed_scale": 1.0,
}
const TIME_SAMPLES := 24
const EPS := 1e-6


## The index of a // comment in a line, ignoring the // of a :// path; -1 when there is none.
func _comment_start(line: String) -> int:
	var from: int = 0
	while true:
		var index: int = line.find("//", from)
		if index < 0:
			return -1
		if index == 0 or line[index - 1] != ":":
			return index
		from = index + 2
	return -1


## The source of a shader file without // and /* */ comments.
func _code(path: String) -> String:
	var source: String = FileAccess.get_file_as_string(path)
	source = RegEx.create_from_string("(?s)/\\*.*?\\*/").sub(source, "", true)
	var kept: PackedStringArray = PackedStringArray()
	for line: String in source.split("\n"):
		var index: int = _comment_start(line)
		kept.append(line if index < 0 else line.substr(0, index))
	return "\n".join(kept)


func _all_code() -> String:
	return _code(SHADER) + "\n" + _code(INCLUDE)


func _have(path: String) -> bool:
	var found: bool = ResourceLoader.exists(path)
	assert_bool(found).override_failure_message("%s is missing" % path).is_true()
	return found


func _matches(source: String, pattern: String) -> bool:
	return RegEx.create_from_string(pattern).search(source) != null


## The body of `void <name>()` up to the closing brace at column 0 of the next function.
func _function_body(source: String, function_name: String) -> String:
	var start: int = source.find("void %s()" % function_name)
	if start < 0:
		return ""
	var rest: String = source.substr(start)
	var next: RegExMatch = RegEx.create_from_string("\\n\\}").search(rest)
	return rest if next == null else rest.substr(0, next.get_end())


func _material(id: StringName) -> ShaderMaterial:
	var path: String = "res://assets/fish/materials/%s.tres" % id
	if not ResourceLoader.exists(path):
		assert_bool(false).override_failure_message("%s is missing" % path).is_true()
		return null
	return load(path) as ShaderMaterial


## A float parameter: the material value, else the default written in the shader source.
func _float_of(material: ShaderMaterial, parameter: String) -> float:
	var value: Variant = material.get_shader_parameter(parameter)
	if value != null:
		return float(value)
	var found: RegExMatch = (
		RegEx
		. create_from_string("uniform\\s+float\\s+%s\\s*(:[^=;]*)?=\\s*(-?[0-9.]+)" % parameter)
		. search(_code(SHADER))
	)
	if found != null:
		return found.get_string(2).to_float()
	return BEND_DEFAULTS.get(parameter, Api.MISSING_NUMBER)


func _linear(material: ShaderMaterial, parameter: String) -> Color:
	var value: Variant = material.get_shader_parameter(parameter)
	if value is Color:
		return (value as Color).srgb_to_linear()
	return Color(Api.MISSING_NUMBER, 0.0, 0.0)


# --- the files and the declared parameters (AC 20) ---


func test_ac20_the_shader_is_a_spatial_shader_with_the_fish_render_modes() -> void:
	if not _have(SHADER) or not _have(INCLUDE):
		return
	var shader: Shader = load(SHADER) as Shader
	assert_object(shader).is_not_null()
	assert_int(shader.get_mode()).is_equal(Shader.MODE_SPATIAL)
	var modes: RegExMatch = RegEx.create_from_string("render_mode\\s+([^;]*);").search(
		_code(SHADER)
	)
	assert_object(modes).override_failure_message("no render_mode line").is_not_null()
	if modes != null:
		assert_str(modes.get_string(1)).contains("cull_disabled")
		assert_str(modes.get_string(1)).contains("depth_prepass_alpha")
	assert_bool(_matches(_code(SHADER), '#include\\s+"[^"]*fish_common\\.gdshaderinc"')).is_true()


func test_ac20_the_material_parameters_exist() -> void:
	if not _have(SHADER):
		return
	var names: Array[String] = []
	for entry: Dictionary in (load(SHADER) as Shader).get_shader_uniform_list():
		names.append(str(entry["name"]))
	for wanted: String in MATERIAL_UNIFORMS:
		(
			assert_bool(names.has(wanted))
			. override_failure_message("the shader has no uniform %s" % wanted)
			. is_true()
		)


func test_ac20_the_four_per_fish_values_are_instance_uniforms_of_the_right_type() -> void:
	if not _have(SHADER):
		return
	var source: String = _code(SHADER)
	for wanted: String in INSTANCE_UNIFORMS:
		var pattern: String = (
			"instance\\s+uniform\\s+%s\\s+%s\\b" % [INSTANCE_UNIFORMS[wanted], wanted]
		)
		(
			assert_bool(_matches(source, pattern))
			. override_failure_message(
				"no `instance uniform %s %s`" % [INSTANCE_UNIFORMS[wanted], wanted]
			)
			. is_true()
		)
	var names: Array[String] = []
	for entry: Dictionary in (load(SHADER) as Shader).get_shader_uniform_list():
		names.append(str(entry["name"]))
	for wanted: String in INSTANCE_UNIFORMS:
		(
			assert_bool(names.has(wanted))
			. override_failure_message(
				"%s is also a material uniform; it must be per fish only" % wanted
			)
			. is_false()
		)


func test_ac20_the_tint_strength_defaults_to_zero_so_an_unset_fish_is_untinted() -> void:
	if not _have(SHADER):
		return
	var pattern: String = (
		"instance\\s+uniform\\s+float\\s+variant_tint_strength"
		+ "\\s*(:[^=;]*)?=\\s*0(\\.0*)?\\s*;"
	)
	(
		assert_bool(_matches(_code(SHADER), pattern))
		. override_failure_message("variant_tint_strength needs the default 0.0")
		. is_true()
	)


func test_ac20_colours_use_source_color_and_the_mask_is_linear_data() -> void:
	if not _have(SHADER):
		return
	var source: String = _code(SHADER)
	for wanted: String in COLOUR_UNIFORMS:
		var pattern: String = "uniform\\s+vec[34]\\s+%s\\s*:[^;=]*source_color" % wanted
		(
			assert_bool(_matches(source, pattern))
			. override_failure_message("%s must be a source_color vec3 or vec4" % wanted)
			. is_true()
		)
	var mask: RegExMatch = (
		RegEx.create_from_string("uniform\\s+sampler2D\\s+fish_mask([^;]*);").search(source)
	)
	assert_object(mask).override_failure_message("no sampler2D fish_mask").is_not_null()
	if mask != null:
		(
			assert_str(mask.get_string(1))
			. override_failure_message("fish_mask is linear data, no source_color")
			. not_contains("source_color")
		)
	var atlas: RegExMatch = (
		RegEx.create_from_string("uniform\\s+sampler2D\\s+palette_atlas([^;]*);").search(source)
	)
	assert_object(atlas).override_failure_message("no sampler2D palette_atlas").is_not_null()
	if atlas != null:
		assert_str(atlas.get_string(1)).contains("source_color")
		assert_str(atlas.get_string(1)).contains("filter_nearest")


func test_ac20_the_base_colour_is_not_a_parameter_and_the_vertex_alpha_is_the_fin_mask() -> void:
	if not _have(SHADER):
		return
	var source: String = _all_code()
	(
		assert_bool(_matches(source, "uniform\\s+[a-z0-9]+\\s+(base|body|albedo)[a-z_]*colou?r"))
		. is_false()
	)
	(
		assert_bool(_matches(source, "COLOR\\.a"))
		. override_failure_message("the shader must read COLOR.a as the fin mask")
		. is_true()
	)


# --- the include: constants, functions and the pinned reading of the B channel ---


func test_ac20_the_include_pins_the_eight_constants_to_the_twin() -> void:
	if not _have(INCLUDE):
		return
	var source: String = _code(INCLUDE)
	for constant_name: String in Twin.CONSTANTS:
		var found: RegExMatch = (
			RegEx
			. create_from_string(
				"(?m)^\\s*const\\s+float\\s+%s\\s*=\\s*(-?[0-9.]+)\\s*;\\s*$" % constant_name
			)
			. search(source)
		)
		(
			assert_object(found)
			. override_failure_message(
				"no line `const float %s = <value>;` in the include" % constant_name
			)
			. is_not_null()
		)
		if found != null:
			(
				assert_float(found.get_string(1).to_float())
				. override_failure_message(
					"%s in the include differs from the twin" % constant_name
				)
				. is_equal(Twin.CONSTANTS[constant_name])
			)


func test_ac20_the_include_defines_the_four_named_functions() -> void:
	if not _have(INCLUDE):
		return
	var source: String = _code(INCLUDE)
	for function_name: String in ["fish_bend_x", "fish_tint", "fish_shimmer", "fish_eye_band"]:
		(
			assert_bool(_matches(source, "\\b(float|int|vec3|vec4)\\s+%s\\s*\\(" % function_name))
			. override_failure_message("the include does not define %s" % function_name)
			. is_true()
		)


func test_ac31_the_eye_bands_are_read_unfiltered_with_texel_fetch_at_level_0() -> void:
	if not _have(SHADER) or not _have(INCLUDE):
		return
	var source: String = _all_code()
	var fetch: String = "texelFetch\\s*\\(\\s*fish_mask\\s*,[^;]*,\\s*0\\s*\\)\\s*\\.\\s*b\\b"
	(
		assert_bool(_matches(source, fetch))
		. override_failure_message("B must be read with texelFetch(fish_mask, ..., 0).b")
		. is_true()
	)
	(
		assert_bool(_matches(source, "round\\s*\\([^;]*3\\.0"))
		. override_failure_message("the band is decoded as int(round(b * 3.0))")
		. is_true()
	)
	var filtered: bool = _matches(
		source, "texture(Lod)?\\s*\\(\\s*fish_mask[^;]*\\)\\s*\\.\\s*[rgba]*b[rgba]*\\b"
	)
	(
		assert_bool(filtered)
		. override_failure_message("B must never be read through a filtered fetch")
		. is_false()
	)


# --- the fragment and vertex wiring ---


func test_ac37_the_fragment_applies_regions_then_tint_then_shimmer_then_the_eye() -> void:
	if not _have(SHADER):
		return
	var body: String = _function_body(_code(SHADER), "fragment")
	assert_str(body).override_failure_message("no fragment() function").is_not_empty()
	var region: int = body.find("region_r_colour")
	var tint: int = body.find("fish_tint(")
	var shimmer: int = body.find("fish_shimmer(")
	var eye: int = body.rfind("eye_colour")
	(
		assert_bool(region >= 0 and tint >= 0 and shimmer >= 0 and eye >= 0)
		. override_failure_message(
			"fragment() must use region_r_colour, fish_tint(, fish_shimmer( and eye_colour"
		)
		. is_true()
	)
	(
		assert_bool(region < tint and tint < shimmer and shimmer < eye)
		. override_failure_message(
			(
				"order must be regions, tint, shimmer, eye (first use positions %d %d %d %d)"
				% [region, tint, shimmer, eye]
			)
		)
		. is_true()
	)


func test_ac37_the_tint_never_touches_roughness_specular_or_metallic() -> void:
	if not _have(SHADER):
		return
	for line: String in _all_code().split("\n"):
		if _matches(line, "\\b(ROUGHNESS|SPECULAR|METALLIC)\\b"):
			(
				assert_str(line)
				. override_failure_message(
					"a material line mentions the tint: %s" % line.strip_edges()
				)
				. not_contains("tint")
			)


func test_ac30_the_shimmer_uses_the_normal_view_angle_and_the_fin_rules_read_the_vertex_alpha(
) -> void:
	if not _have(SHADER):
		return
	var source: String = _all_code()
	assert_bool(_matches(source, "dot\\s*\\(\\s*NORMAL\\s*,\\s*VIEW\\s*\\)")).is_true()
	(
		assert_bool(
			_matches(
				source,
				"ALPHA\\s*=[^;]*fin_opacity[^;]*COLOR\\.a|ALPHA\\s*=[^;]*COLOR\\.a[^;]*fin_opacity"
			)
		)
		. override_failure_message("ALPHA = mix(1.0, fin_opacity, COLOR.a)")
		. is_true()
	)
	(
		assert_bool(
			_matches(
				source,
				"BACKLIGHT\\s*=[^;]*transmission_color[^;]*transmission_strength[^;]*COLOR\\.a"
			)
		)
		. override_failure_message(
			"BACKLIGHT = transmission_color * transmission_strength * COLOR.a"
		)
		. is_true()
	)


func test_ac21_the_bend_is_a_lateral_vertex_function_with_the_swim_instance_values() -> void:
	if not _have(SHADER):
		return
	var body: String = _function_body(_code(SHADER), "vertex")
	assert_str(body).override_failure_message("no vertex() function").is_not_empty()
	assert_bool(_matches(body, "VERTEX\\.x\\s*\\+=")).is_true()
	assert_bool(body.contains("fish_bend_x(")).is_true()
	assert_bool(body.contains("swim_phase") and body.contains("swim_speed")).is_true()
	(
		assert_bool(_matches(body, "\\bNORMAL\\s*="))
		. override_failure_message("the bend leaves the normals unchanged")
		. is_false()
	)
	(
		assert_bool(_matches(body, "VERTEX\\.(y|z)\\s*[+\\-]?="))
		. override_failure_message("the bend is lateral only")
		. is_false()
	)


# --- AC 21: the bend sampled over the real vertices with the real material values ---


## {"largest": float, "front": float, "argmax_s": float} at one speed over the species vertices.
func _bend_scan(id: StringName, speed: float) -> Dictionary:
	var model: Checks.FishModel = Checks.open(id)
	var material: ShaderMaterial = _material(id)
	var result: Dictionary = {}
	assert_str(model.problem).override_failure_message("%s: %s" % [id, model.problem]).is_empty()
	if model.problem.is_empty() and material != null:
		var amp: float = _float_of(material, "swim_amplitude")
		var freq: float = _float_of(material, "swim_frequency")
		var scale: float = _float_of(material, "swim_speed_scale")
		var largest: float = 0.0
		var front: float = 0.0
		var argmax_s: float = 0.0
		var smallest_s: float = INF
		for point: Vector3 in Checks.all_points(model):
			var best: float = 0.0
			for step: int in TIME_SAMPLES:
				var time: float = (
					float(step) / TIME_SAMPLES / maxf(0.001, Twin.frequency(freq, speed, scale))
				)
				best = maxf(best, absf(Twin.bend_x(point.z, time, 0.0, speed, amp, freq, scale)))
			(
				assert_bool(best <= Twin.peak(point.z, speed, amp, scale) + EPS)
				. override_failure_message("a vertex moves more than a * w(s)")
				. is_true()
			)
			var s: float = Twin.s_of(point.z)
			smallest_s = minf(smallest_s, s)
			if s <= 0.2:
				front = maxf(front, best)
			if best > largest:
				largest = best
				argmax_s = s
		result = {"largest": largest, "front": front, "argmax_s": argmax_s}
	model.release()
	return result


func test_ac21_the_swim_amplitude_frequency_and_speed_scale_are_in_their_allowed_ranges() -> void:
	for id: StringName in Api.IDS:
		var material: ShaderMaterial = _material(id)
		if material == null:
			continue
		assert_float(_float_of(material, "swim_amplitude")).is_between(0.06, 0.12)
		assert_float(_float_of(material, "swim_frequency")).is_between(0.5, 2.5)
		assert_float(_float_of(material, "swim_speed_scale")).is_equal_approx(1.0, EPS)


func test_ac21_the_front_20_percent_does_not_move() -> void:
	for id: StringName in Api.IDS:
		for speed: float in [0.0, 1.0]:
			var scan: Dictionary = _bend_scan(id, speed)
			if scan.is_empty():
				continue
			(
				assert_float(float(scan["front"]))
				. override_failure_message("%s speed %.0f: the front moves" % [id, speed])
				. is_less_equal(0.25 * float(scan["largest"]))
			)
			assert_float(float(scan["front"])).is_equal_approx(0.0, EPS)


func test_ac21_the_largest_displacement_is_in_the_rear_40_percent() -> void:
	for id: StringName in Api.IDS:
		var scan: Dictionary = _bend_scan(id, 1.0)
		if scan.is_empty():
			continue
		(
			assert_float(float(scan["argmax_s"]))
			. override_failure_message("%s: the largest bend is at s %.2f" % [id, scan["argmax_s"]])
			. is_greater_equal(0.6)
		)


func test_ac21_a_resting_fish_still_breathes_and_a_fast_one_stays_calm() -> void:
	for id: StringName in Api.IDS:
		var rest: Dictionary = _bend_scan(id, 0.0)
		var fast: Dictionary = _bend_scan(id, 1.0)
		if rest.is_empty() or fast.is_empty():
			continue
		(
			assert_float(float(rest["largest"]))
			. override_failure_message("%s speed 0: %.4f" % [id, rest["largest"]])
			. is_between(0.005, 0.03)
		)
		(
			assert_float(float(fast["largest"]))
			. override_failure_message("%s speed 1: %.4f" % [id, fast["largest"]])
			. is_between(0.06, 0.15)
		)
		assert_float(float(fast["largest"])).is_less_equal(0.12 + 0.005)


func test_ac21_no_vertex_moves_more_than_0_15_body_lengths_at_any_speed() -> void:
	for id: StringName in Api.IDS:
		for speed: float in [0.0, 0.25, 0.5, 0.75, 1.0, 1.5]:
			var scan: Dictionary = _bend_scan(id, speed)
			if scan.is_empty():
				continue
			(
				assert_float(float(scan["largest"]))
				. override_failure_message("%s speed %.2f: %.4f" % [id, speed, scan["largest"]])
				. is_less_equal(0.15)
			)


func test_ac21_the_twin_bend_matches_the_plan_at_hand_computed_points() -> void:
	# s = 0.5 - z: the snout (s 0) does not move, the tail base (s 1) has w = smoothstep(0.2, 1.2, 1).
	assert_float(Twin.bend_x(0.5, 0.3, 1.0, 1.0, 0.1, 1.5, 1.0)).is_equal_approx(0.0, EPS)
	var w: float = Twin.smoothstep_glsl(0.2, 1.2, 1.0)
	assert_float(w).is_equal_approx(0.896, 0.001)
	assert_float(Twin.peak(-0.5, 1.0, 0.1, 1.0)).is_equal_approx(0.1 * w, EPS)
	assert_float(Twin.peak(-0.5, 0.0, 0.1, 1.0)).is_equal_approx(0.1 * 0.15 * w, EPS)
	assert_float(Twin.frequency(1.5, 0.0, 1.0)).is_equal_approx(0.6, EPS)
	assert_float(Twin.frequency(1.5, 1.0, 1.0)).is_equal_approx(1.5, EPS)


# --- AC 30: the shimmer ---


func test_ac30_the_neon_stripe_changes_colour_with_the_view_angle() -> void:
	var material: ShaderMaterial = _material(Api.NEON)
	if material == null:
		return
	var base: Color = _linear(material, "region_r_colour")
	var a: Color = _linear(material, "shimmer_colour_a")
	var b: Color = _linear(material, "shimmer_colour_b")
	var power: float = _float_of(material, "shimmer_power")
	var strength: float = _float_of(material, "shimmer_strength")
	var head_on: Color = Twin.shimmer(base, 1.0, power, a, b, strength, 1.0, 0.0)
	var glancing: Color = Twin.shimmer(base, 0.3, power, a, b, strength, 1.0, 0.0)
	(
		assert_float(Twin.distance(head_on, glancing))
		. override_failure_message(
			"stripe colour differs by only %.3f" % Twin.distance(head_on, glancing)
		)
		. is_greater_equal(0.10)
	)


func test_ac30_with_shimmer_strength_zero_the_colour_does_not_change_with_the_angle() -> void:
	var material: ShaderMaterial = _material(Api.NEON)
	if material == null:
		return
	var base: Color = _linear(material, "region_r_colour")
	var a: Color = _linear(material, "shimmer_colour_a")
	var b: Color = _linear(material, "shimmer_colour_b")
	var power: float = _float_of(material, "shimmer_power")
	var head_on: Color = Twin.shimmer(base, 1.0, power, a, b, 0.0, 1.0, 0.0)
	var glancing: Color = Twin.shimmer(base, 0.3, power, a, b, 0.0, 1.0, 0.0)
	assert_float(Twin.distance(head_on, glancing)).is_less_equal(EPS)
	assert_float(Twin.distance(head_on, base)).is_less_equal(EPS)


func test_ac30_the_default_strength_is_0_for_angelfish_and_corydoras_and_high_for_the_neon(
) -> void:
	for id: StringName in [Api.ANGEL, Api.CORY]:
		var material: ShaderMaterial = _material(id)
		if material != null:
			assert_float(_float_of(material, "shimmer_strength")).is_equal(0.0)
	var neon: ShaderMaterial = _material(Api.NEON)
	if neon != null:
		assert_float(_float_of(neon, "shimmer_strength")).is_between(0.6, 1.0)
		assert_float(_float_of(neon, "shimmer_power")).is_between(0.5, 8.0)


func test_ac30_both_shimmer_colours_stay_blue_green() -> void:
	var material: ShaderMaterial = _material(Api.NEON)
	if material == null:
		return
	for parameter: String in ["shimmer_colour_a", "shimmer_colour_b"]:
		var colour: Color = material.get_shader_parameter(parameter) as Color
		(
			assert_object(material.get_shader_parameter(parameter))
			. override_failure_message("%s is not set" % parameter)
			. is_not_null()
		)
		assert_float(colour.h * 360.0).override_failure_message("%s hue" % parameter).is_between(
			150.0, 235.0
		)
		(
			assert_float(colour.s)
			. override_failure_message("%s saturation" % parameter)
			. is_greater_equal(0.35)
		)


func test_ac30_the_shimmer_goes_from_colour_a_head_on_to_colour_b_at_a_glancing_angle() -> void:
	var a: Color = Color(0.1, 0.8, 0.6)
	var b: Color = Color(0.0, 0.3, 0.9)
	var base: Color = Color(0.5, 0.5, 0.5)
	var head_on: Color = Twin.shimmer(base, 1.0, 2.0, a, b, 1.0, 1.0, 0.0)
	var edge_on: Color = Twin.shimmer(base, 0.0, 2.0, a, b, 1.0, 1.0, 0.0)
	assert_float(Twin.distance(head_on, a)).is_less_equal(EPS)
	assert_float(Twin.distance(edge_on, b)).is_less_equal(EPS)
	var middle: Color = Twin.shimmer(base, 0.5, 2.0, a, b, 1.0, 1.0, 0.0)
	assert_float(Twin.distance(middle, Twin.mix_c(a, b, 0.25))).is_less_equal(EPS)


func test_ac30_the_shimmer_leaves_the_eye_and_everything_outside_region_r_alone() -> void:
	var a: Color = Color(0.1, 0.8, 0.6)
	var b: Color = Color(0.0, 0.3, 0.9)
	var base: Color = Color(0.5, 0.4, 0.3)
	(
		assert_float(Twin.distance(Twin.shimmer(base, 0.2, 2.0, a, b, 1.0, 0.0, 0.0), base))
		. is_less_equal(EPS)
	)
	(
		assert_float(Twin.distance(Twin.shimmer(base, 0.2, 2.0, a, b, 1.0, 1.0, 1.0), base))
		. is_less_equal(EPS)
	)
	(
		assert_float(
			Twin.distance(Twin.shimmer(base, 0.2, 2.0, a, b, 5.0, 1.0, 0.0), b.lerp(b, 0.0))
		)
		. is_less_equal(Twin.distance(b, Twin.shimmer(base, 0.2, 2.0, a, b, 1.0, 1.0, 0.0)) + EPS)
	)


# --- AC 37 and 33: the tint blend ---


func test_ac37_the_tint_replaces_the_base_colour_inside_the_body_keeping_the_luminance_share(
) -> void:
	var base: Color = Color(0.2, 0.3, 0.4)
	var tint_colour: Color = Color(0.8, 0.7, 0.1)
	var result: Color = Twin.tint(base, 1.0, 0.0, 0.0, tint_colour, 1.0, 0.3)
	# luma(base) = 0.28596, k = mix(1, 0.28596 / 0.35, 0.3) = 0.94511 (hand computed).
	assert_float(result.r).is_equal_approx(0.75609, 1e-4)
	assert_float(result.g).is_equal_approx(0.66158, 1e-4)
	assert_float(result.b).is_equal_approx(0.09451, 1e-4)


func test_ac37_with_keep_zero_the_tint_colour_replaces_the_base_exactly() -> void:
	var tint_colour: Color = Color(0.8, 0.7, 0.1)
	for base: Color in [Color(0.2, 0.3, 0.4), Color(0.9, 0.9, 0.9), Color(0.0, 0.0, 0.0)]:
		var result: Color = Twin.tint(base, 1.0, 0.0, 0.0, tint_colour, 1.0, 0.0)
		assert_float(Twin.distance(result, tint_colour)).is_less_equal(EPS)


func test_ac37_a_share_of_the_base_luminance_variation_is_kept() -> void:
	var tint_colour: Color = Color(0.6, 0.5, 0.2)
	var dark: Color = Twin.tint(Color(0.1, 0.1, 0.1), 1.0, 0.0, 0.0, tint_colour, 1.0, 0.3)
	var light: Color = Twin.tint(Color(0.5, 0.5, 0.5), 1.0, 0.0, 0.0, tint_colour, 1.0, 0.3)
	assert_float(Twin.luma(light)).override_failure_message("shading is lost").is_greater(
		Twin.luma(dark) * 1.1
	)


func test_ac37_the_albino_tint_can_be_lighter_than_the_wild_base() -> void:
	var wild: Color = Color(0.15, 0.12, 0.05)
	var albino: Color = Color(0.9, 0.8, 0.7)
	var result: Color = Twin.tint(wild, 1.0, 0.0, 0.0, albino, 1.0, 0.3)
	assert_float(Twin.luma(result)).is_greater(Twin.luma(wild) * 3.0)


func test_ac37_nothing_outside_the_body_region_changes() -> void:
	var base: Color = Color(0.3, 0.2, 0.5)
	var tint_colour: Color = Color(0.9, 0.1, 0.1)
	# not body (mask alpha 0), eye, fin (vertex alpha 1)
	(
		assert_float(Twin.distance(Twin.tint(base, 0.0, 0.0, 0.0, tint_colour, 1.0, 0.3), base))
		. is_equal(0.0)
	)
	(
		assert_float(Twin.distance(Twin.tint(base, 1.0, 1.0, 0.0, tint_colour, 1.0, 0.3), base))
		. is_equal(0.0)
	)
	(
		assert_float(Twin.distance(Twin.tint(base, 1.0, 0.0, 1.0, tint_colour, 1.0, 0.3), base))
		. is_equal(0.0)
	)


func test_ac33_variant_0_is_the_untinted_colour_bit_for_bit_whatever_the_stored_colour() -> void:
	var stored: Array[Color] = [
		Color(1, 0, 0), Color(0.2, 0.9, 0.4), Color(0, 0, 0), Color(1, 1, 1)
	]
	var bases: Array[Color] = [Color(0.3, 0.2, 0.5), Color(0.0, 0.0, 0.0), Color(1.0, 0.9, 0.2)]
	for base: Color in bases:
		for colour: Color in stored:
			var result: Color = Twin.tint(base, 1.0, 0.0, 0.0, colour, 0.0, 0.3)
			(
				assert_bool(result.r == base.r and result.g == base.g and result.b == base.b)
				. override_failure_message("variant 0 changed %s into %s" % [base, result])
				. is_true()
			)


func test_ac37_the_strength_is_clamped_to_zero_to_one() -> void:
	var base: Color = Color(0.3, 0.2, 0.5)
	var tint_colour: Color = Color(0.9, 0.1, 0.1)
	var full: Color = Twin.tint(base, 1.0, 0.0, 0.0, tint_colour, 1.0, 0.3)
	(
		assert_float(Twin.distance(Twin.tint(base, 1.0, 0.0, 0.0, tint_colour, 3.0, 0.3), full))
		. is_less_equal(EPS)
	)
	(
		assert_float(Twin.distance(Twin.tint(base, 1.0, 0.0, 0.0, tint_colour, -1.0, 0.3), base))
		. is_less_equal(EPS)
	)


func test_ac37_every_species_material_keeps_a_share_of_the_luminance_between_0_2_and_0_4() -> void:
	for id: StringName in Api.IDS:
		var material: ShaderMaterial = _material(id)
		if material != null:
			assert_float(_float_of(material, "variant_tint_keep")).is_between(0.2, 0.4)


# --- AC 23: the eye bands and the two highlights ---


func _eye_material() -> Dictionary:
	return {
		"eye_colour": Color(0.02, 0.02, 0.03),
		"eye_iris_colour": Color(0.8, 0.3, 0.05),
		"eye_highlight_colour": Color(1.0, 1.0, 1.0),
		"eye_highlight_strength": 0.9,
		"eye_glint_strength": 0.8,
		"roughness": 0.45,
		"specular_amount": 0.5,
	}


func test_ac31_every_blue_level_within_the_tolerance_decodes_to_its_own_band() -> void:
	for band: int in 4:
		for level: int in range(maxi(0, band * 85 - 20), mini(255, band * 85 + 20) + 1):
			(
				assert_int(Twin.eye_band(float(level) / 255.0))
				. override_failure_message(
					(
						"level %d decodes to band %d, not %d"
						% [level, Twin.eye_band(float(level) / 255.0), band]
					)
				)
				. is_equal(band)
			)


func test_ac31_a_filtered_edge_would_turn_pupil_and_dot_into_an_iris_which_is_why_b_is_fetched(
) -> void:
	var filtered: float = (85.0 + 255.0) / 2.0 / 255.0
	assert_int(Twin.eye_band(filtered)).is_equal(2)


func test_ac23_each_band_shows_its_colour_and_band_0_leaves_the_fish_alone() -> void:
	var material: Dictionary = _eye_material()
	var base: Color = Color(0.4, 0.5, 0.6)
	assert_float(Twin.distance(Twin.eye_look(0, base, material)["colour"], base)).is_equal(0.0)
	(
		assert_float(
			Twin.distance(Twin.eye_look(1, base, material)["colour"], material["eye_colour"])
		)
		. is_less_equal(EPS)
	)
	(
		assert_float(
			Twin.distance(Twin.eye_look(2, base, material)["colour"], material["eye_iris_colour"])
		)
		. is_less_equal(EPS)
	)
	var dot: Color = Twin.eye_look(3, base, material)["colour"]
	(
		assert_float(
			Twin.distance(
				dot, Twin.mix_c(material["eye_colour"], material["eye_highlight_colour"], 0.9)
			)
		)
		. is_less_equal(EPS)
	)


func test_ac23_edge_with_both_highlights_off_the_eye_shows_pupil_and_iris_only() -> void:
	var material: Dictionary = _eye_material()
	material["eye_highlight_strength"] = 0.0
	material["eye_glint_strength"] = 0.0
	var base: Color = Color(0.4, 0.5, 0.6)
	var dot: Dictionary = Twin.eye_look(3, base, material)
	assert_float(Twin.distance(dot["colour"], material["eye_colour"])).is_less_equal(EPS)
	assert_float(Twin.distance(dot["emission"], Color(0, 0, 0))).is_less_equal(EPS)
	for band: int in [1, 2, 3]:
		var result: Dictionary = Twin.eye_look(band, base, material)
		assert_float(float(result["roughness"])).is_equal_approx(0.45, EPS)
		assert_float(float(result["specular"])).is_equal_approx(0.5, EPS)


func test_ac23_edge_the_painted_dot_works_alone() -> void:
	var material: Dictionary = _eye_material()
	material["eye_glint_strength"] = 0.0
	var result: Dictionary = Twin.eye_look(3, Color(0.4, 0.5, 0.6), material)
	assert_float(Twin.distance(result["colour"], material["eye_colour"])).is_greater(0.5)
	assert_float(Twin.luma(result["emission"])).is_greater(0.0)
	assert_float(float(result["roughness"])).is_equal_approx(0.45, EPS)
	assert_float(float(result["specular"])).is_equal_approx(0.5, EPS)


func test_ac23_edge_the_glint_works_alone() -> void:
	var material: Dictionary = _eye_material()
	material["eye_highlight_strength"] = 0.0
	var pupil: Dictionary = Twin.eye_look(1, Color(0.4, 0.5, 0.6), material)
	assert_float(Twin.distance(pupil["colour"], material["eye_colour"])).is_less_equal(EPS)
	assert_float(float(pupil["roughness"])).is_less(0.45)
	assert_float(float(pupil["specular"])).is_greater(0.5)
	material["eye_glint_strength"] = 1.0
	var full: Dictionary = Twin.eye_look(1, Color(0.4, 0.5, 0.6), material)
	assert_float(float(full["roughness"])).is_equal_approx(0.1, EPS)
	assert_float(float(full["specular"])).is_equal_approx(1.0, EPS)


func test_ac23_the_dot_adds_a_small_emission_of_the_highlight_colour() -> void:
	var material: Dictionary = _eye_material()
	var result: Dictionary = Twin.eye_look(3, Color(0.4, 0.5, 0.6), material)
	assert_float((result["emission"] as Color).r).is_equal_approx(1.0 * 0.9 * 0.3, EPS)
