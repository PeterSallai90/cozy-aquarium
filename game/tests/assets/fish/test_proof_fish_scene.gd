extends GdUnitTestSuite
## #21 support for criterion 12: the proof scene keeps working, so it cannot rot unnoticed.
## It binds the shader and the atlas to the two surfaces of the fish. Rendering is a manual check.

const Source := preload("res://tests/helpers/proof_fish_source.gd")
const Checks := preload("res://tests/helpers/proof_fish_checks.gd")

const SCENE_PATH := "res://scenes/dev/proof_fish/proof_fish.tscn"
const SHADER_FILE := "proof_fish.gdshader"
const ATLAS_FILE := "proof_palette_atlas.png"

var _root: Node = null


func after_test() -> void:
	if _root != null:
		_root.free()
	_root = null


func _open() -> MeshInstance3D:
	var exists: bool = ResourceLoader.exists(SCENE_PATH)
	assert_bool(exists).override_failure_message("proof scene missing: %s" % SCENE_PATH).is_true()
	if not exists:
		return null
	var scene: PackedScene = load(SCENE_PATH) as PackedScene
	assert_object(scene).is_not_null()
	if scene == null:
		return null
	_root = scene.instantiate()
	var instances: Array[MeshInstance3D] = Source.mesh_instances(_root)
	assert_int(instances.size()).is_equal(1)
	if instances.size() != 1:
		return null
	return instances[0]


func _override(instance: MeshInstance3D, wanted: String) -> ShaderMaterial:
	var surface: int = Checks.surface_by_name(instance.mesh, wanted)
	assert_int(surface).is_greater_equal(0)
	if surface < 0:
		return null
	var material: Material = instance.get_surface_override_material(surface)
	assert_object(material).is_instanceof(ShaderMaterial)
	return material as ShaderMaterial


func test_proof_scene_loads_with_one_fish_mesh() -> void:
	assert_object(_open()).is_not_null()


func test_proof_scene_both_surfaces_use_the_proof_shader_and_the_atlas() -> void:
	var instance: MeshInstance3D = _open()
	if instance == null:
		return
	for wanted: String in ["body", "fin"]:
		var material: ShaderMaterial = _override(instance, wanted)
		if material == null:
			continue
		assert_str(material.shader.resource_path).ends_with(SHADER_FILE)
		var atlas: Texture2D = material.get_shader_parameter("palette_atlas") as Texture2D
		assert_object(atlas).is_not_null()
		if atlas != null:
			assert_str(atlas.resource_path).ends_with(ATLAS_FILE)


func test_proof_scene_fin_is_drawn_after_the_body() -> void:
	var instance: MeshInstance3D = _open()
	if instance == null:
		return
	var body: ShaderMaterial = _override(instance, "body")
	var fin: ShaderMaterial = _override(instance, "fin")
	if body != null and fin != null:
		assert_int(fin.render_priority).is_greater(body.render_priority)


func test_proof_scene_fish_is_scaled_to_3_5_cm_in_the_scene_only() -> void:
	var instance: MeshInstance3D = _open()
	if instance == null:
		return
	var scale_factor: float = 1.0
	var node: Node = instance
	while node != null:
		if node is Node3D:
			scale_factor *= (node as Node3D).scale.x
		node = node.get_parent()
	assert_float(scale_factor).is_equal_approx(0.035, 0.0001)
