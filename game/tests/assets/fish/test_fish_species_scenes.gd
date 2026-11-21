extends GdUnitTestSuite
## #34 AC 35 and the eye colours of AC 23 (owner: technical-artist, stage 2; the atlas is stage 1):
## FishSpecies.scene is a wrapper scene game/assets/fish/scenes/<id>.tscn (root Node3D, identity
## transform, no script) that instances game/assets/fish/<id>.glb. The .glb import maps both glTF
## materials `body` and `fin` to the one species material game/assets/fish/materials/<id>.tres
## (use_external, as the decor items); that ShaderMaterial uses game/shaders/fish.gdshader with the
## species mask, the shared palette atlas, eye_colour, eye_iris_colour and the region colours.
## The shared fish_palette_atlas.png is 64 x 64 px, a 4 x 4 grid of flat 16 px cells, imported
## lossless without mipmaps like the proof atlas. The wrapper scene is looked up by path (not
## through the catalog) so this suite belongs to the technical-artist alone.
## Test decisions: "dark" eye = HSV value at most 0.30; the angelfish iris is orange-red = hue 0 to
## 45 degrees with saturation at least 0.5; the painted dot and the glint of the shipped materials
## are on (strength above 0.3), the edge cases of the strengths are in test_fish_shader.gd.

const Api := preload("res://tests/helpers/fish_api.gd")
const Checks := preload("res://tests/helpers/fish_species_checks.gd")

const SHADER := "res://shaders/fish.gdshader"
const ATLAS := "res://assets/fish/fish_palette_atlas.png"
const COLOUR_PARAMETERS: PackedStringArray = [
	"eye_colour",
	"eye_iris_colour",
	"eye_highlight_colour",
	"region_r_colour",
	"region_g_colour",
]


func _scene_path(id: StringName) -> String:
	return "res://assets/fish/scenes/%s.tscn" % id


func _material_path(id: StringName) -> String:
	return "res://assets/fish/materials/%s.tres" % id


func _material(id: StringName) -> ShaderMaterial:
	if not ResourceLoader.exists(_material_path(id)):
		assert_bool(false).override_failure_message("%s is missing" % _material_path(id)).is_true()
		return null
	return load(_material_path(id)) as ShaderMaterial


func _parameter(material: ShaderMaterial, name_of: String) -> Variant:
	return material.get_shader_parameter(name_of)


# --- the wrapper scene ---


func test_ac35_the_wrapper_scene_is_a_plain_node3d_with_an_identity_transform() -> void:
	for id: StringName in Api.IDS:
		var path: String = _scene_path(id)
		var present: bool = ResourceLoader.exists(path)
		assert_bool(present).override_failure_message("%s is missing" % path).is_true()
		if not present:
			continue
		var root: Node3D = (load(path) as PackedScene).instantiate() as Node3D
		assert_object(root).override_failure_message("%s: root is not a Node3D" % id).is_not_null()
		if root == null:
			continue
		(
			assert_object(root.get_script())
			. override_failure_message("%s: root has a script" % id)
			. is_null()
		)
		(
			assert_bool(root.transform.is_equal_approx(Transform3D.IDENTITY))
			. override_failure_message("%s: root transform is not the identity" % id)
			. is_true()
		)
		root.free()


func test_ac35_the_wrapper_instances_the_species_glb() -> void:
	for id: StringName in Api.IDS:
		var path: String = _scene_path(id)
		var text: String = FileAccess.get_file_as_string(path)
		assert_str(text).override_failure_message("%s is missing or empty" % path).is_not_empty()
		assert_str(text).override_failure_message("%s does not instance the .glb" % path).contains(
			"res://assets/fish/%s.glb" % id
		)


func test_ac35_every_surface_of_the_instanced_fish_uses_the_species_material() -> void:
	for id: StringName in Api.IDS:
		var path: String = _scene_path(id)
		if not ResourceLoader.exists(path):
			assert_bool(false).override_failure_message("%s is missing" % path).is_true()
			continue
		var root: Node3D = (load(path) as PackedScene).instantiate() as Node3D
		var instances: Array[MeshInstance3D] = Checks.mesh_instances(root)
		(
			assert_int(instances.size())
			. override_failure_message("%s: MeshInstance3D count" % id)
			. is_equal(1)
		)
		for instance: MeshInstance3D in instances:
			assert_int(instance.mesh.get_surface_count()).is_equal(2)
			for surface: int in instance.mesh.get_surface_count():
				var material: Material = instance.get_active_material(surface)
				(
					assert_bool(material is ShaderMaterial)
					. override_failure_message(
						"%s surface %d is not a ShaderMaterial" % [id, surface]
					)
					. is_true()
				)
				if material != null:
					(
						assert_str(material.resource_path)
						. override_failure_message(
							"%s surface %d does not use the species material" % [id, surface]
						)
						. is_equal(_material_path(id))
					)
		root.free()


func test_ac35_the_glb_import_maps_body_and_fin_to_the_species_material() -> void:
	for id: StringName in Api.IDS:
		var config: ConfigFile = ConfigFile.new()
		var path: String = Checks.glb_path(id) + ".import"
		var loaded: bool = config.load(path) == OK
		assert_bool(loaded).override_failure_message("missing: %s" % path).is_true()
		if not loaded:
			continue
		var subresources: Dictionary = config.get_value("params", "_subresources", {})
		var materials: Dictionary = subresources.get("materials", {})
		for role: String in ["body", "fin"]:
			var entry: Dictionary = materials.get(role, {})
			(
				assert_bool(bool(entry.get("use_external/enabled", false)))
				. override_failure_message("%s: material %s is not external" % [id, role])
				. is_true()
			)
			(
				assert_str(str(entry.get("use_external/path", "")))
				. override_failure_message("%s: material %s maps to another file" % [id, role])
				. is_equal(_material_path(id))
			)


# --- the species material ---


func test_ac35_the_material_uses_the_fish_shader_with_the_species_mask_and_the_atlas() -> void:
	for id: StringName in Api.IDS:
		var material: ShaderMaterial = _material(id)
		if material == null:
			continue
		assert_object(material.shader).is_not_null()
		if material.shader != null:
			assert_str(material.shader.resource_path).is_equal(SHADER)
		var mask: Texture2D = _parameter(material, "fish_mask") as Texture2D
		assert_object(mask).override_failure_message("%s: fish_mask is not set" % id).is_not_null()
		if mask != null:
			assert_str(mask.resource_path).is_equal("res://assets/fish/%s_mask.png" % id)
		var atlas: Texture2D = _parameter(material, "palette_atlas") as Texture2D
		(
			assert_object(atlas)
			. override_failure_message("%s: palette_atlas is not set" % id)
			. is_not_null()
		)
		if atlas != null:
			assert_str(atlas.resource_path).is_equal(ATLAS)


func test_ac35_the_material_sets_the_eye_and_region_colours() -> void:
	for id: StringName in Api.IDS:
		var material: ShaderMaterial = _material(id)
		if material == null:
			continue
		for parameter: String in COLOUR_PARAMETERS:
			(
				assert_bool(_parameter(material, parameter) is Color)
				. override_failure_message("%s: %s is not a Color" % [id, parameter])
				. is_true()
			)


func test_ac23_neon_and_corydoras_have_a_dark_eye_without_an_iris_ring() -> void:
	for id: StringName in [Api.NEON, Api.CORY]:
		var material: ShaderMaterial = _material(id)
		if material == null:
			continue
		var pupil: Color = _parameter(material, "eye_colour") as Color
		var iris: Color = _parameter(material, "eye_iris_colour") as Color
		(
			assert_bool(iris == pupil)
			. override_failure_message("%s: eye_iris_colour must equal eye_colour" % id)
			. is_true()
		)
		(
			assert_float(pupil.v)
			. override_failure_message("%s: the eye is not dark" % id)
			. is_less_equal(0.30)
		)


func test_ac23_the_angelfish_has_an_orange_red_iris_around_a_dark_pupil() -> void:
	var material: ShaderMaterial = _material(Api.ANGEL)
	if material == null:
		return
	var pupil: Color = _parameter(material, "eye_colour") as Color
	var iris: Color = _parameter(material, "eye_iris_colour") as Color
	assert_float(pupil.v).is_less_equal(0.30)
	(
		assert_bool(iris == pupil)
		. override_failure_message("the iris colour equals the pupil")
		. is_false()
	)
	assert_float(iris.h * 360.0).override_failure_message("iris hue is not orange-red").is_between(
		0.0, 45.0
	)
	assert_float(iris.s).is_greater_equal(0.5)


func test_ac23_the_painted_dot_and_the_glint_are_on_for_every_species() -> void:
	for id: StringName in Api.IDS:
		var material: ShaderMaterial = _material(id)
		if material == null:
			continue
		assert_float(float(_parameter(material, "eye_highlight_strength"))).is_greater(0.3)
		assert_float(float(_parameter(material, "eye_glint_strength"))).is_greater(0.3)
		var highlight: Color = _parameter(material, "eye_highlight_colour") as Color
		var pupil: Color = _parameter(material, "eye_colour") as Color
		(
			assert_float(highlight.v)
			. override_failure_message("%s: the dot is not bright" % id)
			. is_greater(pupil.v + 0.4)
		)


func test_ac23_the_eye_values_are_material_parameters_and_never_catalog_fields() -> void:
	var species: Resource = Api.new_species()
	assert_object(species).override_failure_message("FishSpecies is missing").is_not_null()
	if species == null:
		return
	for entry: Dictionary in species.get_property_list():
		var field: String = str(entry["name"])
		for prefix: String in ["eye_", "shimmer_", "variant_tint", "swim_amplitude", "swim_phase"]:
			(
				assert_bool(field.begins_with(prefix))
				. override_failure_message("FishSpecies has the look field %s" % field)
				. is_false()
			)


# --- the shared palette atlas ---


func test_ac35_the_atlas_is_64_by_64_with_a_4_by_4_grid_of_flat_cells() -> void:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(ATLAS)
	assert_int(bytes.size()).override_failure_message("%s is missing" % ATLAS).is_greater(0)
	var image: Image = Image.new()
	if bytes.is_empty() or image.load_png_from_buffer(bytes) != OK:
		return
	image.convert(Image.FORMAT_RGBA8)
	assert_int(image.get_width()).is_equal(64)
	assert_int(image.get_height()).is_equal(64)
	for row: int in 4:
		for col: int in 4:
			var corner: Color = image.get_pixel(col * 16, row * 16)
			for y: int in 16:
				for x: int in 16:
					if image.get_pixel(col * 16 + x, row * 16 + y) != corner:
						(
							assert_bool(false)
							. override_failure_message(
								"cell (%d, %d) is not one flat colour" % [col, row]
							)
							. is_true()
						)
						return


func test_ac35_the_atlas_import_is_lossless_without_mipmaps_like_the_proof_atlas() -> void:
	var config: ConfigFile = ConfigFile.new()
	var loaded: bool = config.load(ATLAS + ".import") == OK
	assert_bool(loaded).override_failure_message("missing: %s.import" % ATLAS).is_true()
	if not loaded:
		return
	assert_int(config.get_value("params", "compress/mode", -1)).is_equal(0)
	assert_bool(config.get_value("params", "mipmaps/generate", true)).is_false()
	assert_int(config.get_value("params", "detect_3d/compress_to", -1)).is_equal(0)
	assert_bool(config.get_value("params", "process/premult_alpha", true)).is_false()


func test_ac35_the_proof_atlas_is_not_the_fish_atlas() -> void:
	assert_bool(ATLAS == "res://assets/fish/proof_palette_atlas.png").is_false()
	(
		assert_bool(FileAccess.file_exists(ATLAS))
		. override_failure_message("%s is missing" % ATLAS)
		. is_true()
	)
