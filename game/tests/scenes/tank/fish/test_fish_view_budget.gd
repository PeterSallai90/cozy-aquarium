extends GdUnitTestSuite
## #34 AC 24 (spans the technical-artist's materials and the developer's FishView; the developer
## runs second and owns the fix): given 60 fish of the three species (20 each), there is one
## ShaderMaterial per species (three in total, sharing one Shader) and every per-fish difference
## is an instance parameter. The plan budgets at most 4 draw calls per fish and 240 for 60 fish:
## 2 surfaces, each drawn in the depth prepass and the transparent colour pass, no shadow pass.
## The test checks the setup that gives that number: per fish exactly one MeshInstance3D whose mesh
## has exactly 2 surfaces, cast_shadow off, no material_override and no material_overlay, the
## species ShaderMaterial on both surfaces (the same instance for every fish of a species),
## next_pass null, and depth_prepass_alpha in the shader source. #49 measures the real draw calls.

const Api := preload("res://tests/helpers/fish_api.gd")
const FishRig := preload("res://tests/helpers/fish_view_rig.gd")

const PER_SPECIES := 20
const MAX_CALLS_PER_FISH := 4
const MAX_CALLS_TOTAL := 240
const PASSES := 2


func _sixty() -> AquariumModel:
	var fish: Array = []
	var index: int = 0
	for species: StringName in Api.IDS:
		for count: int in PER_SPECIES:
			index += 1
			fish.append(FishRig.fish("%08x" % (0x1000 + index), species, count % 2))
	return FishRig.model(FishRig.LARGE, FishRig.SAND, fish)


func test_ac24_sixty_fish_use_three_species_materials_that_share_one_shader() -> void:
	var rig: FishRig.Rig = FishRig.open(self, _sixty())
	assert_object(rig.view).override_failure_message("FishView is missing").is_not_null()
	if rig.view == null:
		return
	assert_int(rig.view.get_child_count()).is_equal(60)
	var by_species: Dictionary = {}
	var shaders: Dictionary = {}
	var total_calls: int = 0
	for entry: FishInstance in rig.model.get_fish_list():
		var node: Node3D = FishRig.node_of(rig, entry.uid)
		if node == null:
			assert_bool(false).override_failure_message("no node for %s" % entry.uid).is_true()
			continue
		var instances: Array[GeometryInstance3D] = FishRig.geometry(node)
		(
			assert_int(instances.size())
			. override_failure_message("%s: geometry count" % entry.uid)
			. is_equal(1)
		)
		var instance: MeshInstance3D = instances[0] as MeshInstance3D
		assert_object(instance).is_not_null()
		assert_int(instance.mesh.get_surface_count()).is_equal(2)
		assert_int(instance.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		assert_object(instance.material_override).is_null()
		assert_object(instance.material_overlay).is_null()
		for surface: int in 2:
			var material: ShaderMaterial = instance.get_active_material(surface) as ShaderMaterial
			(
				assert_object(material)
				. override_failure_message(
					"%s surface %d is not a ShaderMaterial" % [entry.uid, surface]
				)
				. is_not_null()
			)
			if material == null:
				continue
			assert_object(material.next_pass).is_null()
			var known: Variant = by_species.get(entry.species_id)
			if known == null:
				by_species[entry.species_id] = material
			(
				assert_bool(by_species[entry.species_id] == material)
				. override_failure_message(
					(
						"%s: fish of %s do not share one material instance"
						% [entry.uid, entry.species_id]
					)
				)
				. is_true()
			)
			shaders[material.shader] = true
		total_calls += instance.mesh.get_surface_count() * PASSES
	assert_int(by_species.size()).override_failure_message("one material per species").is_equal(3)
	var materials: Dictionary = {}
	for species: Variant in by_species:
		materials[by_species[species]] = true
	assert_int(materials.size()).is_equal(3)
	(
		assert_int(shaders.size())
		. override_failure_message("the three materials must share one Shader")
		. is_equal(1)
	)
	assert_int(total_calls).is_less_equal(MAX_CALLS_TOTAL)
	assert_int(total_calls).is_less_equal(MAX_CALLS_PER_FISH * 60)


func test_ac24_the_shader_draws_a_depth_prepass_for_the_transparent_body() -> void:
	var source: String = FileAccess.get_file_as_string("res://shaders/fish.gdshader")
	assert_str(source).override_failure_message("fish.gdshader is missing").is_not_empty()
	assert_str(source).contains("depth_prepass_alpha")


func test_ac24_every_per_fish_difference_is_an_instance_parameter() -> void:
	var rig: FishRig.Rig = FishRig.open(self, _sixty())
	if rig.view == null:
		assert_bool(false).override_failure_message("FishView is missing").is_true()
		return
	var tints: Dictionary = {}
	var phases: Dictionary = {}
	for entry: FishInstance in rig.model.get_fish_list():
		var node: Node3D = FishRig.node_of(rig, entry.uid)
		if node == null:
			continue
		var instance: GeometryInstance3D = FishRig.geometry(node)[0]
		tints[instance.get_instance_shader_parameter("variant_tint_strength")] = true
		phases[snappedf(float(instance.get_instance_shader_parameter("swim_phase")), 1e-6)] = true
	assert_int(tints.size()).override_failure_message("variants 0 and 1 both appear").is_equal(2)
	assert_int(phases.size()).override_failure_message("every fish has its own phase").is_equal(60)
