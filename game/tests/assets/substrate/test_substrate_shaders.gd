# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #28 criteria 29, 39 and 41 (owner: technical-artist): the four bed shaders and the materials that
## use them (technical plan v3, sections 3.1 and 6; ADR 0011 rule 12). Headless Godot runs the dummy
## renderer and compiles no shaders, so the shaders are checked by source scans after the comments
## are removed (pattern of test_water_shaders.gd):
## - no texture sampler and no screen, depth or normal-roughness read in any of the four;
## - the core is opaque (ALPHA never written), matte, and its fragment function has no per-pixel
##   colour variation (no noise, no UV, no position, no instance data);
## - only substrate_sand_grain assigns VERTEX or DEPTH (the camera-facing quad of the ray-cast
##   grain);
##   the stone, sand top and core shaders write neither;
## - every look resource uses these shaders, and every material takes the tint through the uniform
##   substrate_tint (the bed copies the materials and sets the tint on the copies);
## - the colour constants of the sand shaders and of the black sand look have a chroma of at most
##   0.1 (AC 41; the measured screenshot colour is in the measure script).

const Api := preload("res://tests/helpers/substrate_bed_api.gd")
const Rig := preload("res://tests/helpers/substrate_scene_rig.gd")

const STONE := "substrate_stone"
const GRAIN := "substrate_sand_grain"
const TOP := "substrate_sand_top"
const CORE := "substrate_core"
const SHADERS: Array[String] = [STONE, GRAIN, TOP, CORE]
const SAMPLERS := "\\b(sampler2D|sampler3D|sampler2DArray|samplerCube|samplerCubeArray)\\b"
const TEXTURE_CALLS := "\\b(texture|textureLod|textureGrad|texelFetch|textureSize)\\s*\\("
const SCREEN_READS := "\\bhint_(screen_texture|depth_texture|normal_roughness_texture)\\b"
const ASSIGNS_VERTEX_OR_DEPTH := "\\b(VERTEX|DEPTH)\\s*(\\+|-|\\*|/)?=(?!=)"
const NOISE_CALLS := (
	"\\b(noise|hash|random|rand|fbm|snoise|perlin|simplex|voronoi|sin|cos|fract)" + "\\w*\\s*\\("
)
const PER_PIXEL_INPUTS := (
	"\\b(UV|UV2|VERTEX|NORMAL|FRAGCOORD|INSTANCE_CUSTOM|TIME|COLOR|VIEW|SCREEN_UV|"
	+ "NODE_POSITION_WORLD|MODEL_MATRIX|INV_VIEW_MATRIX)\\b"
)
const TINT_UNIFORM := "uniform\\s+vec[34]\\s+substrate_tint\\s*:\\s*source_color"
const COLOUR_CONSTANT := (
	"(?:const|uniform)\\s+vec[34]\\s+(\\w*(?:fill|glint|emission|emit|spark)\\w*)"
	+ "\\s*(?::\\s*source_color\\s*)?=\\s*vec[34]\\s*\\(([^)]*)\\)"
)
const CHROMA_LIMIT := 0.1


func _path(shader_name: String) -> String:
	return "%s/%s.gdshader" % [Api.SHADER_DIR, shader_name]


## The shader source without // and /* */ comments.
func _code(shader_name: String) -> String:
	var source: String = FileAccess.get_file_as_string(_path(shader_name))
	var block: RegEx = RegEx.create_from_string("(?s)/\\*.*?\\*/")
	source = block.sub(source, "", true)
	var kept: PackedStringArray = PackedStringArray()
	for line: String in source.split("\n"):
		var index: int = line.find("//")
		kept.append(line if index < 0 else line.substr(0, index))
	return "\n".join(kept)


func _have(shader_name: String) -> bool:
	var found: bool = FileAccess.file_exists(_path(shader_name))
	assert_bool(found).override_failure_message("%s is missing" % _path(shader_name)).is_true()
	return found


func _matches(shader_name: String, pattern: String) -> bool:
	return RegEx.create_from_string(pattern).search(_code(shader_name)) != null


## The body of `void fragment()` (from its opening brace to the matching one), "" when missing.
func _fragment_body(shader_name: String) -> String:
	var code: String = _code(shader_name)
	var start: int = code.find("void fragment()")
	if start < 0:
		return ""
	var open: int = code.find("{", start)
	if open < 0:
		return ""
	var depth: int = 0
	for i: int in range(open, code.length()):
		if code[i] == "{":
			depth += 1
		elif code[i] == "}":
			depth -= 1
			if depth == 0:
				return code.substr(open, i - open + 1)
	return ""


# --- all four ---


func test_ac39_the_four_shaders_are_spatial_shaders() -> void:
	for shader_name: String in SHADERS:
		if _have(shader_name):
			(
				assert_bool(_matches(shader_name, "shader_type\\s+spatial\\s*;"))
				. override_failure_message(shader_name)
				. is_true()
			)


func test_ac29_no_shader_of_the_bed_uses_a_texture_sampler() -> void:
	for shader_name: String in SHADERS:
		if not _have(shader_name):
			continue
		for pattern: String in [SAMPLERS, TEXTURE_CALLS, SCREEN_READS]:
			(
				assert_bool(_matches(shader_name, pattern))
				. override_failure_message(
					"%s samples a texture or reads the screen (%s)" % [shader_name, pattern]
				)
				. is_false()
			)


func test_ac39_every_shader_takes_the_tint_as_a_source_colour_uniform() -> void:
	for shader_name: String in SHADERS:
		if _have(shader_name):
			(
				assert_bool(_matches(shader_name, TINT_UNIFORM))
				. override_failure_message(
					"%s: uniform vec4 substrate_tint : source_color" % shader_name
				)
				. is_true()
			)


func test_ac39_no_shader_is_unshaded_or_blended_except_through_the_plan() -> void:
	for shader_name: String in [STONE, TOP, CORE]:
		if _have(shader_name):
			(
				assert_bool(_matches(shader_name, "\\bunshaded\\b"))
				. override_failure_message("%s is unshaded" % shader_name)
				. is_false()
			)
			assert_bool(_matches(shader_name, "\\bblend_(add|sub|mul|premul_alpha)\\b")).is_false()


# --- VERTEX and depth writes ---


func test_ac39_only_the_sand_grain_shader_assigns_vertex_or_depth() -> void:
	for shader_name: String in [STONE, TOP, CORE]:
		if _have(shader_name):
			(
				assert_bool(_matches(shader_name, ASSIGNS_VERTEX_OR_DEPTH))
				. override_failure_message(
					"%s assigns VERTEX or DEPTH; only %s may" % [shader_name, GRAIN]
				)
				. is_false()
			)


func test_ac39_the_sand_grain_shader_turns_a_quad_to_the_camera_through_vertex() -> void:
	if not _have(GRAIN):
		return
	assert_bool(_matches(GRAIN, "\\bskip_vertex_transform\\b")).is_true()
	(
		assert_bool(_matches(GRAIN, "\\bVERTEX\\s*=(?!=)"))
		. override_failure_message("%s never assigns VERTEX" % GRAIN)
		. is_true()
	)
	(
		assert_bool(_matches(GRAIN, "\\bdiscard\\s*;"))
		. override_failure_message("the ray-cast grain must discard on a miss")
		. is_true()
	)


func test_ac39_the_stone_shader_reads_the_instance_custom_data() -> void:
	if _have(STONE):
		assert_bool(_matches(STONE, "\\bINSTANCE_CUSTOM\\b")).is_true()


# --- the core ---


func test_ac39_the_core_is_opaque_and_never_writes_alpha() -> void:
	if not _have(CORE):
		return
	(
		assert_bool(_matches(CORE, "\\bALPHA(_SCISSOR_THRESHOLD|_HASH_SCALE)?\\b"))
		. override_failure_message("the core shader mentions ALPHA")
		. is_false()
	)
	assert_bool(_matches(CORE, "\\bblend_\\w+\\b")).is_false()
	assert_bool(_matches(CORE, "\\bdiscard\\b")).is_false()


func test_ac39_the_core_is_matte() -> void:
	if not _have(CORE):
		return
	(
		assert_bool(_matches(CORE, "\\bMETALLIC\\s*=\\s*(?!0(\\.0*)?\\s*;)"))
		. override_failure_message("the core writes a non-zero METALLIC")
		. is_false()
	)
	var rough: RegExMatch = RegEx.create_from_string("\\bROUGHNESS\\s*=\\s*([0-9.]+)\\s*;").search(
		_code(CORE)
	)
	(
		assert_object(rough)
		. override_failure_message("the core must write ROUGHNESS as a literal of at least 0.9")
		. is_not_null()
	)
	if rough != null:
		assert_float(float(rough.get_string(1))).is_greater_equal(0.9)
	(
		assert_bool(_matches(CORE, "\\bEMISSION\\b"))
		. override_failure_message("the core must not emit light")
		. is_false()
	)


func test_ac39_the_core_has_no_per_pixel_colour_variation() -> void:
	if not _have(CORE):
		return
	var body: String = _fragment_body(CORE)
	assert_str(body).override_failure_message("%s has no fragment()" % CORE).is_not_empty()
	var noise: RegExMatch = RegEx.create_from_string(NOISE_CALLS).search(_code(CORE))
	assert_object(noise).override_failure_message("the core calls a noise-like function").is_null()
	var input: RegExMatch = RegEx.create_from_string(PER_PIXEL_INPUTS).search(body)
	(
		assert_object(input)
		. override_failure_message(
			(
				"the core fragment reads a per-pixel input: %s"
				% (input.get_string() if input != null else "")
			)
		)
		. is_null()
	)
	(
		assert_bool(_matches(CORE, "\\bvarying\\b"))
		. override_failure_message("the core has a varying")
		. is_false()
	)


func test_ac39_the_core_is_the_tint_times_a_dark_fraction() -> void:
	if _have(CORE):
		(
			assert_bool(_matches(CORE, "\\buniform\\s+float\\s+core_darkness\\b"))
			. override_failure_message("uniform float core_darkness")
			. is_true()
		)


# --- the looks use these shaders ---


func _shader_name_of(material: Material) -> String:
	var shader_material: ShaderMaterial = material as ShaderMaterial
	if shader_material == null or shader_material.shader == null:
		return ""
	return shader_material.shader.resource_path.get_file().get_basename()


func test_ac39_every_look_uses_the_bed_shaders_and_its_materials_hold_the_tint() -> void:
	var expected: Dictionary = {
		"sand_fine": {"grain_material": GRAIN, "top_material": TOP, "core_material": CORE},
		"sand_black": {"grain_material": GRAIN, "top_material": TOP, "core_material": CORE},
		"gravel_natural": {"stone_material": STONE, "core_material": CORE},
		"gravel_coloured": {"stone_material": STONE, "core_material": CORE},
		"pebbles_river": {"stone_material": STONE, "core_material": CORE},
	}
	for id: String in expected:
		var look: Resource = Api.look_of(StringName(id))
		assert_object(look).override_failure_message("no look for %s" % id).is_not_null()
		if look == null:
			continue
		var wanted: Dictionary = expected[id]
		for property: String in wanted:
			var material: Material = look.get(property) as Material
			(
				assert_object(material)
				. override_failure_message("%s: %s is null" % [id, property])
				. is_not_null()
			)
			if material == null:
				continue
			(
				assert_str(_shader_name_of(material))
				. override_failure_message("%s: %s uses the wrong shader" % [id, property])
				. is_equal(String(wanted[property]))
			)
			(
				assert_bool(Rig.has_uniform(material, Rig.TINT_PARAMETER))
				. override_failure_message("%s: %s has no substrate_tint" % [id, property])
				. is_true()
			)


# --- AC 41: the colour constants of the sand shaders and the black sand look ---


func _chroma(rgb: Vector3) -> float:
	var high: float = maxf(rgb.x, maxf(rgb.y, rgb.z))
	if high <= 0.0:
		return 0.0
	return (high - minf(rgb.x, minf(rgb.y, rgb.z))) / high


func test_ac41_the_light_colour_constants_of_the_sand_bed_have_a_chroma_of_at_most_0_1() -> void:
	var checked: int = 0
	var pattern: RegEx = RegEx.create_from_string(COLOUR_CONSTANT)
	for shader_name: String in [GRAIN, TOP, CORE]:
		if not _have(shader_name):
			continue
		for found: RegExMatch in pattern.search_all(_code(shader_name)):
			var parts: PackedStringArray = found.get_string(2).split(",")
			if parts.size() < 3:
				continue
			var rgb: Vector3 = Vector3(
				float(parts[0].strip_edges()),
				float(parts[1].strip_edges()),
				float(parts[2].strip_edges())
			)
			checked += 1
			(
				assert_float(_chroma(rgb))
				. override_failure_message(
					"%s: %s has chroma %.3f" % [shader_name, found.get_string(1), _chroma(rgb)]
				)
				. is_less_equal(CHROMA_LIMIT)
			)
	var look: Resource = Api.look_of(&"sand_black")
	assert_object(look).override_failure_message("no look for sand_black").is_not_null()
	if look != null:
		checked += _check_look_colours(look)
	(
		assert_int(checked)
		. override_failure_message(
			"no fill, glint or emission colour constant found in the sand shaders or the black sand look"
		)
		. is_greater(0)
	)


## Checks the fill, glint and emission colour parameters set on the materials of a look; returns how
## many it checked.
func _check_look_colours(look: Resource) -> int:
	var checked: int = 0
	var names: RegEx = RegEx.create_from_string("fill|glint|emission|emit|spark")
	for property: String in ["grain_material", "top_material", "core_material"]:
		var shader_material: ShaderMaterial = look.get(property) as ShaderMaterial
		if shader_material == null or shader_material.shader == null:
			continue
		for uniform: Dictionary in shader_material.shader.get_shader_uniform_list():
			var uniform_name: String = String(uniform["name"])
			if names.search(uniform_name) == null:
				continue
			var value: Variant = shader_material.get_shader_parameter(uniform_name)
			var rgb: Vector3 = Vector3.ZERO
			if value is Color:
				var colour: Color = value
				rgb = Vector3(colour.r, colour.g, colour.b)
			elif value is Vector3:
				rgb = value
			else:
				continue
			checked += 1
			(
				assert_float(_chroma(rgb))
				. override_failure_message(
					"sand_black %s.%s has chroma %.3f" % [property, uniform_name, _chroma(rgb)]
				)
				. is_less_equal(CHROMA_LIMIT)
			)
	return checked
