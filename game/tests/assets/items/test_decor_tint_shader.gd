extends GdUnitTestSuite
## #32 AC 11, shader contract (owner: technical-artist): game/shaders/decor_item.gdshader is the
## decor shader with one more thing, `instance uniform vec4 item_tint` (alpha 0: the original look,
## unchanged; alpha 1: tinted with rgb). assets/items/materials/decor_palette.tres switches to it
## with the old parameter values, and the three decor models still share that one material, so a
## colour never needs its own material. palette_atlas.gdshader and the room material do not change
## (their file hashes are pinned below; room, cabinet, lamp and tank keep their look).
## Headless Godot runs the dummy renderer and compiles no shaders, so the shader is checked by a
## source scan after the comments are removed (pattern of test_placement_materials.gd). The look of
## the tint is the technical artist's call and the owner's judgement (AC 14), not tested here.
## Test decisions: the pinned hashes are the SHA-256 of the files at the base commit d89a0fc (LF
## line endings, .gitattributes); a deliberate change of those two files needs its own issue.

const SHADER := "res://shaders/decor_item.gdshader"
const OLD_SHADER := "res://shaders/palette_atlas.gdshader"
const DECOR_MATERIAL := "res://assets/items/materials/decor_palette.tres"
const ROOM_MATERIAL := "res://assets/room/materials/room_palette.tres"
const OLD_SHADER_SHA256 := "1dbf37885ab13525b53f3a64ad40478c3784228a46015009a0cf1d69b191f7a8"
const ROOM_MATERIAL_SHA256 := "1093d9ec2194e9b25f1437ca1380bfa216ae597a4d9d687ffd747b73f1004a45"
const ATLAS := "res://assets/items/decor_palette_atlas.png"
const PARAMETERS: Dictionary[String, float] = {
	"roughness": 0.75,
	"specular_amount": 0.5,
	"emission_from_v": 1.0,
	"emission_energy": 0.0,
	"vertex_shade": 1.0,
}


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


func test_ac11_the_decor_shader_is_a_spatial_shader() -> void:
	if not _have(SHADER):
		return
	var shader: Shader = load(SHADER) as Shader
	assert_object(shader).is_not_null()
	assert_int(shader.get_mode()).is_equal(Shader.MODE_SPATIAL)


func test_ac11_the_decor_shader_declares_the_instance_uniform_item_tint_as_vec4() -> void:
	if not _have(SHADER):
		return
	(
		assert_bool(_matches(SHADER, "instance\\s+uniform\\s+vec4\\s+item_tint\\b"))
		. override_failure_message("no `instance uniform vec4 item_tint`")
		. is_true()
	)


func test_ac11_the_tint_is_applied_by_the_alpha_so_alpha_0_is_the_original_look() -> void:
	if not _have(SHADER):
		return
	(
		assert_bool(_matches(SHADER, "item_tint\\.a\\b|item_tint\\.w\\b|item_tint\\s*\\)?\\.a"))
		. override_failure_message("the shader never reads item_tint.a")
		. is_true()
	)


func test_ac11_the_decor_shader_keeps_every_uniform_of_the_atlas_shader() -> void:
	if not _have(SHADER) or not _have(OLD_SHADER):
		return
	for param: String in ["palette_atlas", "roughness", "specular_amount", "emission_from_v"]:
		(
			assert_bool(_matches(SHADER, "uniform\\s+\\w+\\s+%s\\b" % param))
			. override_failure_message("decor_item.gdshader has no uniform %s" % param)
			. is_true()
		)
	for param: String in ["emission_energy", "vertex_shade"]:
		(
			assert_bool(_matches(SHADER, "uniform\\s+\\w+\\s+%s\\b" % param))
			. override_failure_message("decor_item.gdshader has no uniform %s" % param)
			. is_true()
		)


func test_ac11_the_decor_shader_still_reads_the_atlas_through_uv2_and_culls_back_faces() -> void:
	if not _have(SHADER):
		return
	assert_bool(_matches(SHADER, "texture\\s*\\(\\s*palette_atlas\\s*,\\s*UV2\\s*\\)")).is_true()
	assert_bool(_matches(SHADER, "render_mode[^;]*cull_back")).is_true()


func test_ac11_the_decor_material_uses_the_new_shader_with_the_old_parameters() -> void:
	if not _have(DECOR_MATERIAL) or not _have(SHADER):
		return
	var material: ShaderMaterial = load(DECOR_MATERIAL) as ShaderMaterial
	assert_object(material).is_not_null()
	if material == null or material.shader == null:
		assert_bool(false).override_failure_message("decor_palette.tres has no shader").is_true()
		return
	assert_str(material.shader.resource_path).is_equal(SHADER)
	for param: String in PARAMETERS:
		var value: Variant = material.get_shader_parameter(param)
		(
			assert_bool(value != null)
			. override_failure_message("parameter %s is not set" % param)
			. is_true()
		)
		if value != null:
			assert_float(float(value)).override_failure_message(param).is_equal_approx(
				PARAMETERS[param], 0.0001
			)
	var atlas: Texture2D = material.get_shader_parameter("palette_atlas") as Texture2D
	assert_object(atlas).is_not_null()
	if atlas != null:
		assert_str(atlas.resource_path).is_equal(ATLAS)


func test_ac11_the_material_does_not_set_item_tint_so_an_untinted_item_keeps_the_old_look() -> void:
	if not _have(DECOR_MATERIAL):
		return
	var material: ShaderMaterial = load(DECOR_MATERIAL) as ShaderMaterial
	assert_object(material).is_not_null()
	if material == null:
		return
	assert_str(FileAccess.get_file_as_string(DECOR_MATERIAL)).not_contains("item_tint")


func test_ac11_the_atlas_shader_and_the_room_material_do_not_change() -> void:
	(
		assert_str(FileAccess.get_sha256(OLD_SHADER))
		. override_failure_message(
			"palette_atlas.gdshader changed (room, cabinet, lamp and tank use it)"
		)
		. is_equal(OLD_SHADER_SHA256)
	)
	(
		assert_str(FileAccess.get_sha256(ROOM_MATERIAL))
		. override_failure_message("room_palette.tres changed")
		. is_equal(ROOM_MATERIAL_SHA256)
	)
	assert_str(_code(OLD_SHADER)).not_contains("item_tint")


func test_ac11_the_three_decor_models_share_one_material_resource_path_with_the_shader() -> void:
	var seen: Dictionary = {}
	for id: String in ["river_stone", "driftwood_branch", "clay_amphora"]:
		var scene: PackedScene = load("res://assets/items/scenes/%s.tscn" % id) as PackedScene
		assert_object(scene).override_failure_message(id).is_not_null()
		if scene == null:
			continue
		var root: Node = scene.instantiate()
		for found: Node in root.find_children("*", "MeshInstance3D", true, false):
			var instance: MeshInstance3D = found as MeshInstance3D
			for surface: int in instance.mesh.get_surface_count():
				var material: Material = instance.get_active_material(surface)
				assert_object(material).is_not_null()
				if material != null:
					seen[material.resource_path] = true
		root.free()
	assert_array(seen.keys()).is_equal([DECOR_MATERIAL])
