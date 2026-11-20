extends GdUnitTestSuite
## #31 AC 39 and the plan section 4 (owner: technical-artist): the two look resources of the
## placement system. game/shaders/item_ghost.gdshader and game/shaders/item_selection_glow.gdshader
## with the materials game/scenes/tank/items/item_ghost_material.tres and
## item_selection_material.tres. Headless Godot runs the dummy renderer and compiles no shaders, so
## the shaders are checked by source scans after the comments are removed (pattern of
## test_substrate_shaders.gd). The contract with the developer is the two resource paths and the
## uniform names ghost_alpha, ghost_tint (ghost) and fresnel_strength, fresnel_power, glow_colour
## (glow); the developer sets material_override, material_overlay and cast_shadow in code.
## Checked: the ghost is transparent (writes ALPHA, default ghost_alpha between 0 and 1), avoids
## self-overlap artefacts (depth_prepass_alpha or depth_draw_always) and samples a palette atlas
## sampler; the glow is a soft fresnel edge overlay whose strongest default output stays below the
## glow_hdr_threshold of the room environment (so it adds no bloom), reads no screen, depth or
## normal texture, and the room environment keeps its glow settings.
## Test decisions: "the glow output" is max(glow_colour rgb) times fresnel_strength; defaults come
## from the material parameter when it is set, else from the shader source.

const GHOST_SHADER := "res://shaders/item_ghost.gdshader"
const GLOW_SHADER := "res://shaders/item_selection_glow.gdshader"
const GHOST_MATERIAL := "res://scenes/tank/items/item_ghost_material.tres"
const SELECTION_MATERIAL := "res://scenes/tank/items/item_selection_material.tres"
const ENVIRONMENT := "res://scenes/room/room_environment.tres"
const SCREEN_READS := "\\bhint_(screen_texture|depth_texture|normal_roughness_texture)\\b"


## The shader source without // and /* */ comments.
func _code(path: String) -> String:
	var source: String = FileAccess.get_file_as_string(path)
	source = RegEx.create_from_string("(?s)/\\*.*?\\*/").sub(source, "", true)
	var kept: PackedStringArray = PackedStringArray()
	for line: String in source.split("\n"):
		var index: int = line.find("//")
		kept.append(line if index < 0 else line.substr(0, index))
	return "\n".join(kept)


func _have(path: String) -> bool:
	var found: bool = ResourceLoader.exists(path)
	assert_bool(found).override_failure_message("%s is missing" % path).is_true()
	return found


func _matches(path: String, pattern: String) -> bool:
	return RegEx.create_from_string(pattern).search(_code(path)) != null


func _uniform_names(path: String) -> Array[String]:
	var names: Array[String] = []
	var shader: Shader = load(path) as Shader
	for entry: Dictionary in shader.get_shader_uniform_list():
		names.append(String(entry["name"]))
	return names


func _material(path: String) -> ShaderMaterial:
	return load(path) as ShaderMaterial


## A float uniform: the material parameter when set, else the default in the shader source.
func _float_default(material_path: String, shader_path: String, uniform: String) -> float:
	var material: ShaderMaterial = _material(material_path)
	var set_value: Variant = material.get_shader_parameter(uniform)
	if set_value != null:
		return float(set_value)
	var pattern: String = "uniform\\s+float\\s+%s\\b[^=;]*=\\s*(-?[0-9.]+)" % uniform
	var found: RegExMatch = RegEx.create_from_string(pattern).search(_code(shader_path))
	return float(found.get_string(1)) if found != null else -999.0


## The rgb of a colour uniform: the material parameter when set, else the source default.
func _colour_default(material_path: String, shader_path: String, uniform: String) -> Vector3:
	var material: ShaderMaterial = _material(material_path)
	var set_value: Variant = material.get_shader_parameter(uniform)
	if set_value is Color:
		var colour: Color = set_value
		return Vector3(colour.r, colour.g, colour.b)
	var pattern: String = "uniform\\s+vec[34]\\s+%s\\b[^=;]*=\\s*vec[34]\\(([^)]*)\\)" % uniform
	var found: RegExMatch = RegEx.create_from_string(pattern).search(_code(shader_path))
	if found == null:
		return Vector3(-999.0, -999.0, -999.0)
	var parts: PackedStringArray = found.get_string(1).split(",")
	if parts.size() < 3:
		return Vector3(-999.0, -999.0, -999.0)
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))


# --- both shaders and materials exist and are wired ---


func test_both_shaders_exist_and_are_spatial_shaders_with_a_fragment_function() -> void:
	for path: String in [GHOST_SHADER, GLOW_SHADER]:
		if not _have(path):
			continue
		assert_object(load(path) as Shader).override_failure_message(path).is_not_null()
		assert_bool(_matches(path, "shader_type\\s+spatial\\s*;")).is_true()
		assert_bool(_matches(path, "void\\s+fragment\\s*\\(\\s*\\)")).is_true()


func test_both_materials_are_shader_materials_using_their_shader() -> void:
	for pair: Array in [[GHOST_MATERIAL, GHOST_SHADER], [SELECTION_MATERIAL, GLOW_SHADER]]:
		var material_path: String = pair[0]
		var shader_path: String = pair[1]
		if not _have(material_path):
			continue
		var material: ShaderMaterial = _material(material_path)
		assert_object(material).override_failure_message("%s" % material_path).is_not_null()
		if material == null or material.shader == null:
			(
				assert_bool(false)
				. override_failure_message("%s has no shader" % material_path)
				. is_true()
			)
			continue
		assert_str(material.shader.resource_path).is_equal(shader_path)


func test_the_uniform_names_of_the_contract_exist() -> void:
	if _have(GHOST_SHADER):
		var ghost: Array[String] = _uniform_names(GHOST_SHADER)
		assert_bool("ghost_alpha" in ghost).override_failure_message("ghost_alpha").is_true()
		assert_bool("ghost_tint" in ghost).override_failure_message("ghost_tint").is_true()
	if _have(GLOW_SHADER):
		var glow: Array[String] = _uniform_names(GLOW_SHADER)
		for wanted: String in ["fresnel_strength", "fresnel_power", "glow_colour"]:
			assert_bool(wanted in glow).override_failure_message(wanted).is_true()


# --- the ghost ---


func test_the_ghost_is_transparent_and_its_default_alpha_is_between_0_and_1() -> void:
	if not _have(GHOST_SHADER) or not _have(GHOST_MATERIAL):
		return
	(
		assert_bool(_matches(GHOST_SHADER, "\\bALPHA\\s*=(?!=)"))
		. override_failure_message("the ghost shader never writes ALPHA")
		. is_true()
	)
	var alpha: float = _float_default(GHOST_MATERIAL, GHOST_SHADER, "ghost_alpha")
	assert_float(alpha).is_greater(0.0)
	assert_float(alpha).is_less(1.0)


func test_the_ghost_avoids_self_overlap_artefacts() -> void:
	if not _have(GHOST_SHADER):
		return
	var ok: bool = _matches(GHOST_SHADER, "\\b(depth_prepass_alpha|depth_draw_always)\\b")
	(
		assert_bool(ok)
		. override_failure_message(
			"the ghost needs render_mode depth_prepass_alpha or depth_draw_always"
		)
		. is_true()
	)


func test_the_ghost_keeps_the_item_colours_through_the_palette_atlas() -> void:
	if not _have(GHOST_SHADER):
		return
	(
		assert_bool(_matches(GHOST_SHADER, "uniform\\s+sampler2D\\s+\\w+"))
		. override_failure_message("the ghost shader has no atlas sampler uniform")
		. is_true()
	)
	assert_bool(_matches(GHOST_SHADER, "\\btexture\\s*\\(")).is_true()


func test_the_ghost_reads_no_screen_depth_or_normal_texture() -> void:
	if not _have(GHOST_SHADER):
		return
	assert_bool(_matches(GHOST_SHADER, SCREEN_READS)).is_false()


# --- the selection glow ---


func test_the_glow_is_a_fresnel_edge_overlay_that_reads_no_screen_texture() -> void:
	if not _have(GLOW_SHADER):
		return
	assert_bool(_matches(GLOW_SHADER, "(?i)fresnel")).is_true()
	(
		assert_bool(_matches(GLOW_SHADER, "\\bALPHA\\s*=(?!=)"))
		. override_failure_message("the glow overlay must write ALPHA so it blends over the item")
		. is_true()
	)
	assert_bool(_matches(GLOW_SHADER, SCREEN_READS)).is_false()


func test_the_glow_defaults_stay_below_the_environment_glow_threshold() -> void:
	if not _have(GLOW_SHADER) or not _have(SELECTION_MATERIAL):
		return
	var environment: Environment = load(ENVIRONMENT) as Environment
	var threshold: float = environment.glow_hdr_threshold
	var strength: float = _float_default(SELECTION_MATERIAL, GLOW_SHADER, "fresnel_strength")
	var colour: Vector3 = _colour_default(SELECTION_MATERIAL, GLOW_SHADER, "glow_colour")
	assert_float(strength).is_greater(0.0)
	var brightest: float = maxf(colour.x, maxf(colour.y, colour.z))
	assert_float(brightest).is_greater(0.0)
	(
		assert_float(brightest * strength)
		. override_failure_message(
			"glow output %s reaches the glow threshold %s" % [brightest * strength, threshold]
		)
		. is_less(threshold)
	)


func test_the_room_environment_keeps_its_glow_settings() -> void:
	var environment: Environment = load(ENVIRONMENT) as Environment
	var fresh: Environment = Environment.new()
	assert_bool(environment.glow_enabled).is_true()
	assert_float(environment.glow_hdr_threshold).is_equal(fresh.glow_hdr_threshold)
	assert_float(environment.glow_intensity).is_equal(fresh.glow_intensity)
	assert_float(environment.glow_bloom).is_equal(fresh.glow_bloom)
	assert_float(environment.glow_strength).is_equal(fresh.glow_strength)
	assert_float(environment.ambient_light_energy).is_equal_approx(0.28, 0.0001)
	assert_int(environment.tonemap_mode).is_equal(4)
