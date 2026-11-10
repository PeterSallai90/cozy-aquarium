# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #126 criteria 1, 3, 4, 5 and 6 at the tank level (owner: technical-artist for the shader, the
## material and the uniform names, developer for TankCaustics, TankWater and the tank scenes): the
## Caustics node under Tank/WaterVolume, its bounds, the values that reach it, the draw order, the
## off states and the failure cases. Node paths and API: technical plan of #126 and ADR 0007
## Amendment 1. The classes are reached through water_rig.gd, so a missing class fails one test
## with a readable message and never breaks the parse of the suite.

const Api := preload("res://tests/helpers/late_api.gd")
const Table := preload("res://tests/helpers/tank_table.gd")
const Water := preload("res://tests/helpers/water_rig.gd")
const SourceScan := preload("res://tests/helpers/source_scan.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")

const MM := 0.001
const SHADER_INSTANCE_NAMES: Array[String] = [
	"water_size_m",
	"lamp_position_m",
	"lamp_direction",
	"lamp_spot_angle_deg",
	"lamp_spot_range_m",
	"caustic_intensity",
	"caustic_speed",
	"caustic_scale",
]
const MATERIAL_UNIFORM_NAMES: Array[String] = [
	"caustic_color",
	"caustic_peak_gain",
	"caustic_side_weight",
	"caustic_depth_falloff_m",
]
const SIBLING_MATERIALS: Dictionary = {
	"depth tint": Water.DEPTH_TINT_MATERIAL,
	"surface": Water.SURFACE_MATERIAL,
	"glass": Water.GLASS_MATERIAL,
}


func _built(id: StringName, caustic: Resource = null) -> Node3D:
	var instance: Node3D = Water.built_tank_with_caustics(
		id, caustic if caustic != null else Water.caustic_settings()
	)
	auto_free(instance)
	return instance


## A built tank inside the tree with a test lamp set; returns the tank.
func _lit(id: StringName, caustic: Resource, angle: float = 50.0, range_m: float = 0.7) -> Node3D:
	var instance: Node3D = _built(id, caustic)
	add_child(instance)
	var light: SpotLight3D = Water.add_light(instance, Vector3(0.0, 0.5, 0.0), angle, range_m)
	Api.call_on(Water.water_of(instance), "set_key_light", [light], null)
	return instance


func _caustics(tank_node: Node3D) -> Node3D:
	var found: Array[Node] = Water.named(tank_node, "Caustics")
	(
		assert_int(found.size())
		. override_failure_message("Tank/WaterVolume/Caustics: expected exactly one")
		. is_equal(1)
	)
	return Water.caustics_of(tank_node)


func _apply(settings: Resource) -> void:
	Api.call_on(settings, "apply", [], null)


func _material(path: String) -> ShaderMaterial:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as ShaderMaterial


func _shader_text() -> String:
	return SourceScan.read(Water.CAUSTICS_SHADER)


func _effective(node: Node) -> float:
	return Api.call_on(node, "get_effective_intensity", [], Api.MISSING_NUMBER)


# --- AC 1: one Caustics per tank, inside the water bounds ---


func test_ac01_each_tank_scene_has_exactly_one_caustics_node() -> void:
	for id: StringName in Table.IDS:
		var instance: Node3D = Water.tank(id)
		auto_free(instance)
		(
			assert_int(Water.named(instance, "Caustics").size())
			. override_failure_message(str(id))
			. is_equal(1)
		)


func test_ac01_each_built_tank_has_exactly_one_caustics_under_the_water_volume() -> void:
	for id: StringName in Table.IDS:
		var instance: Node3D = _built(id)
		var found: Array[Node] = Water.named(instance, "Caustics")
		assert_int(found.size()).override_failure_message(str(id)).is_equal(1)
		if found.size() == 1:
			(
				assert_object(found[0].get_parent())
				. override_failure_message("%s: parent" % id)
				. is_same(Water.water_of(instance))
			)


func test_ac01_caustics_is_the_fourth_child_after_surface_fog_and_depth_tint() -> void:
	for id: StringName in Table.IDS:
		var water: Node3D = Water.water_of(_built(id))
		var names: Array[String] = []
		for child: Node in water.get_children():
			names.append(String(child.name))
		assert_array(names).override_failure_message(str(id)).is_equal(
			["Surface", "Fog", "DepthTint", "Caustics"]
		)


func test_ac01_caustics_is_a_mesh_instance_with_the_tank_caustics_script() -> void:
	for id: StringName in Table.IDS:
		var node: Node3D = _caustics(_built(id))
		assert_object(node).override_failure_message(str(id)).is_instanceof(MeshInstance3D)
		var script: Script = node.get_script() as Script if node != null else null
		assert_str(script.resource_path if script != null else "<no script>").is_equal(
			Water.CAUSTICS_NODE_SCRIPT
		)


func test_ac01_the_transform_is_the_identity() -> void:
	for id: StringName in Table.IDS:
		var node: Node3D = _caustics(_built(id))
		if node == null:
			continue
		(
			assert_bool(node.transform.is_equal_approx(Transform3D.IDENTITY))
			. override_failure_message("%s: %s" % [id, node.transform])
			. is_true()
		)


func test_ac01_the_box_size_is_the_catalog_water_size() -> void:
	for id: StringName in Table.IDS:
		var node: MeshInstance3D = _caustics(_built(id)) as MeshInstance3D
		var expected: Vector3 = Water.definition(id).get_water_volume_size_m()
		var box: BoxMesh = node.mesh as BoxMesh if node != null else null
		assert_object(box).override_failure_message("%s: BoxMesh" % id).is_not_null()
		if box != null:
			assert_vector(box.size).override_failure_message(str(id)).is_equal_approx(
				expected, Vector3.ONE * MM
			)


func test_ac01_the_water_size_instance_parameter_is_the_water_size() -> void:
	for id: StringName in Table.IDS:
		var node: Node3D = _caustics(_built(id))
		var expected: Vector3 = Water.definition(id).get_water_volume_size_m()
		var value: Variant = Water.param(node, &"water_size_m")
		(
			assert_bool(Water.near_vector(value, expected, MM))
			. override_failure_message("%s: water_size_m %s, expected %s" % [id, value, expected])
			. is_true()
		)


func test_ac01_the_box_lies_inside_the_water_bounds_and_the_interior() -> void:
	for id: StringName in Table.IDS:
		var instance: Node3D = _built(id)
		var node: MeshInstance3D = _caustics(instance) as MeshInstance3D
		if node == null:
			continue
		var water: Node3D = Water.water_of(instance)
		var box: AABB = water.transform * node.transform * node.get_aabb()
		var inner: Vector3 = Table.interior(id)
		var interior: AABB = AABB(Vector3(-inner.x / 2.0, 0.0, -inner.z / 2.0), inner)
		var label: String = "%s: %s" % [id, box]
		(
			assert_bool(Water.bounds_of(water).grow(MM).encloses(box))
			. override_failure_message(label + " outside the water bounds")
			. is_true()
		)
		(
			assert_bool(interior.grow(MM).encloses(box))
			. override_failure_message(label + " outside the interior")
			. is_true()
		)
		assert_float(box.end.y).override_failure_message(label).is_less_equal(
			Table.water_line(id) + MM
		)


func test_ac01_caustics_casts_no_shadow() -> void:
	for id: StringName in Table.IDS:
		var node: MeshInstance3D = _caustics(_built(id)) as MeshInstance3D
		if node != null:
			assert_int(node.cast_shadow).override_failure_message(str(id)).is_equal(
				GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			)


# --- AC 2 at the node level: lamp values, lamp swap, draw order, no stale reference ---


func test_ac02_the_lamp_values_reach_the_instance_parameters() -> void:
	for id: StringName in Table.IDS:
		var instance: Node3D = _lit(id, Water.caustic_settings(), 50.0, 0.7)
		var node: Node3D = _caustics(instance)
		var water: Node3D = Water.water_of(instance)
		var light: SpotLight3D = instance.get_child(instance.get_child_count() - 1) as SpotLight3D
		var expected: Dictionary = Water.expected_lamp(water, light)
		(
			assert_bool(
				Water.near_vector(
					Water.param(node, &"lamp_position_m"), expected["lamp_position_m"]
				)
			)
			. override_failure_message("%s: lamp_position_m" % id)
			. is_true()
		)
		(
			assert_bool(
				Water.near_vector(Water.param(node, &"lamp_direction"), expected["lamp_direction"])
			)
			. override_failure_message("%s: lamp_direction" % id)
			. is_true()
		)
		assert_bool(Water.near(Water.param(node, &"lamp_spot_angle_deg"), 50.0)).is_true()
		assert_bool(Water.near(Water.param(node, &"lamp_spot_range_m"), 0.7)).is_true()


func test_ac02_a_lamp_swap_changes_the_footprint_values() -> void:
	var instance: Node3D = _lit(Table.MEDIUM, Water.caustic_settings(), 50.0, 0.7)
	var node: Node3D = _caustics(instance)
	var light: SpotLight3D = instance.get_child(instance.get_child_count() - 1) as SpotLight3D
	light.spot_angle = 30.0
	light.spot_range = 0.4
	light.position = Vector3(0.1, 0.4, 0.0)
	Api.call_on(Water.water_of(instance), "set_key_light", [light], null)
	var expected: Dictionary = Water.expected_lamp(Water.water_of(instance), light)
	assert_bool(Water.near(Water.param(node, &"lamp_spot_angle_deg"), 30.0)).is_true()
	assert_bool(Water.near(Water.param(node, &"lamp_spot_range_m"), 0.4)).is_true()
	(
		assert_bool(
			Water.near_vector(Water.param(node, &"lamp_position_m"), expected["lamp_position_m"])
		)
		. is_true()
	)


func test_ac02_the_lamp_values_are_in_the_water_volume_frame_not_in_world_space() -> void:
	var instance: Node3D = _built(Table.LARGE, Water.caustic_settings())
	instance.position = Vector3(2.0, 1.0, -3.0)
	add_child(instance)
	var light: SpotLight3D = Water.add_light(instance, Vector3(0.25, 0.5, 0.0), 45.0, 0.6)
	var water: Node3D = Water.water_of(instance)
	Api.call_on(water, "set_key_light", [light], null)
	var expected: Vector3 = Water.expected_lamp(water, light)["lamp_position_m"]
	var value: Variant = Water.param(_caustics(instance), &"lamp_position_m")
	(
		assert_bool(Water.near_vector(value, expected))
		. override_failure_message("got %s, expected %s" % [value, expected])
		. is_true()
	)


func test_ac02_caustics_is_drawn_under_depth_tint_surface_and_glass() -> void:
	var caustics: ShaderMaterial = _material(Water.CAUSTICS_MATERIAL)
	assert_object(caustics).override_failure_message("caustics.tres missing").is_not_null()
	if caustics == null:
		return
	assert_int(caustics.render_priority).is_equal(-3)
	for label: String in SIBLING_MATERIALS:
		var other: ShaderMaterial = _material(SIBLING_MATERIALS[label])
		if other != null:
			assert_int(caustics.render_priority).override_failure_message(label).is_less(
				other.render_priority
			)


func test_ac02_the_existing_water_materials_keep_their_render_priority() -> void:
	assert_int(_material(Water.DEPTH_TINT_MATERIAL).render_priority).is_equal(-2)
	assert_int(_material(Water.SURFACE_MATERIAL).render_priority).is_equal(-1)
	assert_int(_material(Water.GLASS_MATERIAL).render_priority).is_equal(0)


func test_ac02_caustics_holds_no_node_reference() -> void:
	for id: StringName in Table.IDS:
		var node: Node3D = _caustics(_lit(id, Water.caustic_settings()))
		if node == null:
			continue
		for property: Dictionary in node.get_property_list():
			if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
				continue
			var value: Variant = node.get(String(property["name"]))
			(
				assert_bool(value is Node)
				. override_failure_message(
					"%s: script variable %s holds a Node" % [id, property["name"]]
				)
				. is_false()
			)


func test_ac02_the_caustics_node_does_no_per_frame_work() -> void:
	var node: Node3D = _caustics(_lit(Table.SMALL, Water.caustic_settings()))
	if node == null:
		return
	assert_bool(node.has_method("_process")).is_false()
	assert_bool(node.has_method("_physics_process")).is_false()
	assert_bool(node.is_processing()).is_false()


func test_ac02_the_settings_signal_has_one_connection_and_none_after_the_tank_is_freed() -> void:
	var settings: Resource = Water.caustic_settings()
	var instance: Node3D = _lit(Table.SMALL, settings)
	assert_int(settings.get_signal_connection_list("applied").size()).is_equal(1)
	remove_child(instance)
	instance.free()
	await get_tree().process_frame
	assert_int(settings.get_signal_connection_list("applied").size()).is_equal(0)


func test_ac02_a_second_build_keeps_a_single_settings_connection() -> void:
	var settings: Resource = Water.caustic_settings()
	var instance: Node3D = _built(Table.SMALL, settings)
	var water: Node3D = Water.water_of(instance)
	Water.build_with_caustics(water, Water.definition(Table.SMALL), Water.settings(), settings)
	Water.build_with_caustics(water, Water.definition(Table.SMALL), Water.settings(), settings)
	assert_int(settings.get_signal_connection_list("applied").size()).is_equal(1)


# --- AC 3: one place for the values, clamped, shown on the displayed caustic ---


func test_ac03_the_caustic_material_is_caustics_tres() -> void:
	for id: StringName in Table.IDS:
		var node: MeshInstance3D = _caustics(_built(id)) as MeshInstance3D
		var material: Material = node.material_override if node != null else null
		assert_str(material.resource_path if material != null else "<no material>").is_equal(
			Water.CAUSTICS_MATERIAL
		)


func test_ac03_no_tank_scene_or_the_material_holds_a_copy_of_the_values() -> void:
	var pattern: RegEx = RegEx.create_from_string("caustic_(intensity|speed|scale)")
	var files: PackedStringArray = SourceScan.list_files(
		"res://", PackedStringArray(["res://addons/", "res://tests/", "res://.godot/"]), [".tscn"]
	)
	assert_int(files.size()).override_failure_message("no .tscn found").is_greater(0)
	for path: String in files:
		(
			assert_bool(pattern.search(SourceScan.read(path)) != null)
			. override_failure_message("%s holds its own copy of a caustic value" % path)
			. is_false()
		)
	var material_text: String = SourceScan.read(Water.CAUSTICS_MATERIAL)
	assert_str(material_text).override_failure_message("caustics.tres missing").is_not_empty()
	assert_bool(pattern.search(material_text) != null).is_false()


func test_ac03_a_write_in_the_one_place_changes_all_three_displayed_caustics() -> void:
	var settings: Resource = Water.caustic_settings()
	var tanks: Array[Node3D] = []
	for id: StringName in Table.IDS:
		tanks.append(_lit(id, settings))
	settings.set("caustic_intensity", 1.25)
	settings.set("caustic_speed", 0.5)
	settings.set("caustic_scale", 40.0)
	_apply(settings)
	for index: int in tanks.size():
		var node: Node3D = _caustics(tanks[index])
		var label: String = str(Table.IDS[index])
		(
			assert_bool(Water.near(Water.param(node, &"caustic_intensity"), 1.25))
			. override_failure_message(label + " intensity")
			. is_true()
		)
		(
			assert_bool(Water.near(Water.param(node, &"caustic_speed"), 0.5))
			. override_failure_message(label + " speed")
			. is_true()
		)
		(
			assert_bool(Water.near(Water.param(node, &"caustic_scale"), 40.0))
			. override_failure_message(label + " scale")
			. is_true()
		)


func test_ac03_the_default_values_reach_the_instance_parameters() -> void:
	var instance: Node3D = _lit(Table.MEDIUM, Water.caustic_settings())
	var node: Node3D = _caustics(instance)
	assert_bool(Water.near(Water.param(node, &"caustic_intensity"), 0.4)).is_true()
	assert_bool(Water.near(Water.param(node, &"caustic_speed"), 0.25)).is_true()
	assert_bool(Water.near(Water.param(node, &"caustic_scale"), 25.0)).is_true()


func test_ac03_out_of_range_writes_are_clamped_on_the_resource_and_the_displayed_caustic() -> void:
	# [property, written, expected]: lower and upper ends of all three ranges.
	var cases: Array = [
		["caustic_intensity", 5.0, 2.0],
		["caustic_intensity", 9.0, 2.0],
		["caustic_speed", 0.01, 0.05],
		["caustic_speed", 1.0, 0.5],
		["caustic_scale", 5.0, 10.0],
		["caustic_scale", 100.0, 60.0],
		["caustic_intensity", -1.0, 0.0],
	]
	for entry: Array in cases:
		var field: String = entry[0]
		var settings: Resource = Water.caustic_settings()
		var instance: Node3D = _lit(Table.SMALL, settings)
		settings.set(field, entry[1])
		var seen: Dictionary = await EngineOutput.capture_all(func() -> void: _apply(settings))
		var label: String = "%s = %s" % [field, entry[1]]
		(
			assert_bool(Water.near(settings.get(field), float(entry[2])))
			. override_failure_message(
				"%s: resource holds %s, expected %s" % [label, settings.get(field), entry[2]]
			)
			. is_true()
		)
		var shown: Variant = Water.param(_caustics(instance), StringName(field))
		(
			assert_bool(Water.near(shown, float(entry[2])))
			. override_failure_message(
				"%s: caustic material shows %s, expected %s" % [label, shown, entry[2]]
			)
			. is_true()
		)
		assert_int(Water.count_of(seen["warnings"])).override_failure_message(label).is_equal(1)
		assert_int(Water.count_of(seen["errors"])).override_failure_message(label).is_equal(0)
		assert_int(Water.count_of(seen["script_errors"])).override_failure_message(label).is_equal(
			0
		)
		remove_child(instance)


func test_ac03_valid_values_apply_without_a_warning() -> void:
	var settings: Resource = Water.caustic_settings()
	var instance: Node3D = _lit(Table.SMALL, settings)
	settings.set("caustic_intensity", 2.0)
	settings.set("caustic_speed", 0.05)
	settings.set("caustic_scale", 60.0)
	var seen: Dictionary = await EngineOutput.capture_all(func() -> void: _apply(settings))
	assert_int(Water.count_of(seen["warnings"])).is_equal(0)
	assert_int(Water.count_of(seen["errors"])).is_equal(0)
	assert_object(instance).is_not_null()


# --- AC 4: shader and material load ---


func test_ac04_the_material_has_a_shader_with_the_contract_uniforms() -> void:
	var material: ShaderMaterial = _material(Water.CAUSTICS_MATERIAL)
	assert_object(material).override_failure_message("caustics.tres missing").is_not_null()
	if material == null:
		return
	assert_object(material.shader).is_not_null()
	if material.shader == null:
		return
	var names: Array[String] = []
	for entry: Dictionary in material.shader.get_shader_uniform_list():
		names.append(String(entry["name"]))
	for wanted: String in MATERIAL_UNIFORM_NAMES:
		(
			assert_bool(wanted in names)
			. override_failure_message("uniform %s missing, got %s" % [wanted, names])
			. is_true()
		)


func test_ac04_the_shader_declares_the_instance_uniforms_of_the_contract() -> void:
	var text: String = SourceScan.strip_comments(_shader_text())
	assert_str(text).override_failure_message("caustics.gdshader missing").is_not_empty()
	for wanted: String in SHADER_INSTANCE_NAMES:
		var pattern: RegEx = RegEx.create_from_string(
			"instance\\s+uniform\\s+\\w+\\s+%s\\b" % wanted
		)
		(
			assert_bool(pattern.search(text) != null)
			. override_failure_message("instance uniform %s not declared" % wanted)
			. is_true()
		)


func test_ac04_the_shader_reads_the_depth_texture_and_never_the_screen_texture() -> void:
	var text: String = SourceScan.strip_comments(_shader_text())
	assert_str(text).override_failure_message("caustics.gdshader missing").is_not_empty()
	assert_bool(text.contains("hint_depth_texture")).is_true()
	assert_bool(text.contains("hint_screen_texture")).is_false()
	assert_bool(text.contains("hint_normal_roughness_texture")).is_false()


func test_ac04_the_shader_is_unshaded_depth_test_off_back_faces_and_never_writes_depth() -> void:
	var text: String = SourceScan.strip_comments(_shader_text())
	assert_str(text).override_failure_message("caustics.gdshader missing").is_not_empty()
	for mode: String in ["unshaded", "depth_test_disabled", "depth_draw_never", "cull_front"]:
		assert_bool(text.contains(mode)).override_failure_message("render_mode " + mode).is_true()


func test_ac04_loading_the_material_and_building_each_tank_prints_nothing() -> void:
	var holder: Array[Node3D] = []
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void:
			var material: Material = load(Water.CAUSTICS_MATERIAL) as Material
			assert_object(material).is_not_null()
			for id: StringName in Table.IDS:
				holder.append(_lit(id, Water.caustic_settings()))
			await get_tree().process_frame
			await get_tree().process_frame
	)
	assert_int(Water.count_of(seen["errors"])).override_failure_message(str(seen)).is_equal(0)
	assert_int(Water.count_of(seen["warnings"])).override_failure_message(str(seen)).is_equal(0)
	assert_int(Water.count_of(seen["script_errors"])).override_failure_message(str(seen)).is_equal(
		0
	)


# --- AC 5: failure cases ---


func test_ac05_a_removed_caustics_does_not_break_build_set_key_light_or_apply() -> void:
	for id: StringName in Table.IDS:
		var settings: Resource = Water.caustic_settings()
		var instance: Node3D = Water.tank(id)
		auto_free(instance)
		add_child(instance)
		var water: Node3D = Water.water_of(instance)
		for node: Node in Water.named(instance, "Caustics"):
			node.get_parent().remove_child(node)
			node.free()
		var built: Array = []
		var seen: Dictionary = await EngineOutput.capture_all(
			func() -> void:
				built.append(
					Water.build_with_caustics(
						water, Water.definition(id), Water.settings(), settings
					)
				)
				var light: SpotLight3D = Water.add_light(instance, Vector3(0, 0.5, 0), 50.0, 0.7)
				Api.call_on(water, "set_key_light", [light], null)
				_apply(settings)
		)
		var label: String = str(id)
		assert_bool(Water.is_true(built[0])).override_failure_message(label + " build").is_true()
		assert_int(Water.count_of(seen["errors"])).override_failure_message(label).is_equal(0)
		assert_int(Water.count_of(seen["script_errors"])).override_failure_message(label).is_equal(
			0
		)
		assert_int(Water.count_of(seen["warnings"])).override_failure_message(label).is_less_equal(
			1
		)
		assert_int(Water.named(instance, "Caustics").size()).is_equal(0)
		for node_name: String in ["Surface", "DepthTint", "Fog"]:
			var child: Node3D = water.get_node_or_null(node_name) as Node3D
			assert_object(child).override_failure_message("%s: %s" % [id, node_name]).is_not_null()
			if child != null:
				(
					assert_bool(child.visible)
					. override_failure_message("%s: %s hidden" % [id, node_name])
					. is_true()
				)
		var glass: Node3D = instance.get_node_or_null("Glass") as Node3D
		assert_object(glass).is_not_null()
		if glass != null:
			assert_bool(glass.visible).is_true()
		remove_child(instance)


func test_ac05_a_caustics_material_without_a_shader_raises_no_script_error() -> void:
	var settings: Resource = Water.caustic_settings()
	var instance: Node3D = _lit(Table.MEDIUM, settings)
	var node: MeshInstance3D = _caustics(instance) as MeshInstance3D
	if node == null:
		return
	node.material_override = ShaderMaterial.new()
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void:
			_apply(settings)
			var light: SpotLight3D = Water.add_light(instance, Vector3(0, 0.5, 0), 40.0, 0.6)
			Api.call_on(Water.water_of(instance), "set_key_light", [light], null)
			await get_tree().process_frame
	)
	assert_int(Water.count_of(seen["errors"])).override_failure_message(str(seen)).is_equal(0)
	assert_int(Water.count_of(seen["script_errors"])).override_failure_message(str(seen)).is_equal(
		0
	)
	assert_int(Water.count_of(seen["warnings"])).override_failure_message(str(seen)).is_less_equal(
		1
	)


# --- AC 6: intensity 0, no lamp, not built ---


func test_ac06_the_authored_caustics_is_hidden_until_a_lamp_is_set() -> void:
	for id: StringName in Table.IDS:
		var instance: Node3D = Water.tank(id)
		auto_free(instance)
		var node: Node3D = _caustics(instance)
		if node == null:
			continue
		assert_bool(node.visible).override_failure_message("%s authored" % id).is_false()


func test_ac06_a_built_tank_without_a_set_key_light_call_is_hidden() -> void:
	for id: StringName in Table.IDS:
		var node: Node3D = _caustics(_built(id))
		if node == null:
			continue
		assert_bool(node.visible).override_failure_message(str(id)).is_false()
		assert_float(_effective(node)).override_failure_message(str(id)).is_equal(0.0)
		assert_bool(Api.call_on(node, "has_lamp", [], true)).is_false()


func test_ac06_a_lit_tank_shows_the_caustics_at_the_default_intensity() -> void:
	for id: StringName in Table.IDS:
		var node: Node3D = _caustics(_lit(id, Water.caustic_settings()))
		if node == null:
			continue
		assert_bool(node.visible).override_failure_message(str(id)).is_true()
		assert_bool(Api.call_on(node, "has_lamp", [], false)).is_true()
		assert_float(_effective(node)).override_failure_message(str(id)).is_equal_approx(
			0.4, 0.0001
		)


func test_ac06_intensity_zero_hides_the_node_and_reports_zero_and_back_shows_it() -> void:
	var settings: Resource = Water.caustic_settings()
	var node: Node3D = _caustics(_lit(Table.LARGE, settings))
	if node == null:
		return
	settings.set("caustic_intensity", 0.0)
	var seen: Dictionary = await EngineOutput.capture_all(func() -> void: _apply(settings))
	assert_int(Water.count_of(seen["errors"])).is_equal(0)
	assert_int(Water.count_of(seen["warnings"])).is_equal(0)
	assert_bool(node.visible).override_failure_message("visible at intensity 0").is_false()
	assert_float(_effective(node)).is_equal(0.0)
	assert_bool(Water.near(Water.param(node, &"caustic_intensity"), 0.0)).is_true()
	settings.set("caustic_intensity", 0.4)
	_apply(settings)
	assert_bool(node.visible).override_failure_message("visible again at 0.4").is_true()
	assert_float(_effective(node)).is_equal_approx(0.4, 0.0001)


func test_ac06_clearing_the_lamp_hides_the_node() -> void:
	var instance: Node3D = _lit(Table.MEDIUM, Water.caustic_settings())
	var node: Node3D = _caustics(instance)
	if node == null:
		return
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void: Api.call_on(Water.water_of(instance), "set_key_light", [null], null)
	)
	assert_int(Water.count_of(seen["errors"])).is_equal(0)
	assert_int(Water.count_of(seen["warnings"])).is_equal(0)
	assert_bool(node.visible).is_false()
	assert_float(_effective(node)).is_equal(0.0)
	assert_bool(Api.call_on(node, "has_lamp", [], true)).is_false()


func test_ac06_a_rebuild_clears_the_lamp_and_hides_the_node() -> void:
	var settings: Resource = Water.caustic_settings()
	var instance: Node3D = _lit(Table.MEDIUM, settings)
	var node: Node3D = _caustics(instance)
	if node == null:
		return
	Water.build_with_caustics(
		Water.water_of(instance), Water.definition(Table.MEDIUM), Water.settings(), settings
	)
	assert_bool(node.visible).is_false()
	assert_bool(Api.call_on(node, "has_lamp", [], true)).is_false()


func test_ac06_a_light_outside_the_tree_gives_hidden_one_warning_and_no_error() -> void:
	var instance: Node3D = _built(Table.SMALL, Water.caustic_settings())
	add_child(instance)
	var light: SpotLight3D = SpotLight3D.new()
	auto_free(light)
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void: Api.call_on(Water.water_of(instance), "set_key_light", [light], null)
	)
	assert_int(Water.count_of(seen["warnings"])).override_failure_message(str(seen)).is_equal(1)
	assert_int(Water.count_of(seen["errors"])).is_equal(0)
	assert_int(Water.count_of(seen["script_errors"])).is_equal(0)
	var node: Node3D = _caustics(instance)
	if node != null:
		assert_bool(node.visible).is_false()
		assert_float(_effective(node)).is_equal(0.0)


func test_ac06_an_invalid_water_build_hides_the_caustics() -> void:
	var settings: Resource = Water.caustic_settings()
	var instance: Node3D = _lit(Table.MEDIUM, settings)
	var node: Node3D = _caustics(instance)
	if node == null:
		return
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void:
			Api.call_on(Water.water_of(instance), "build", [null, Water.settings(), settings], null)
	)
	assert_int(Water.count_of(seen["warnings"])).is_less_equal(1)
	assert_int(Water.count_of(seen["errors"])).is_equal(0)
	assert_int(Water.count_of(seen["script_errors"])).is_equal(0)
	assert_bool(node.visible).is_false()
	assert_float(_effective(node)).is_equal(0.0)
	(
		assert_int(settings.get_signal_connection_list("applied").size())
		. override_failure_message("an invalid build must disconnect the settings")
		. is_equal(0)
	)


func test_ac06_a_two_argument_build_still_works_and_hides_the_caustics() -> void:
	var instance: Node3D = Water.built_tank(Table.SMALL)
	auto_free(instance)
	var node: Node3D = _caustics(instance)
	if node != null:
		assert_bool(node.visible).is_false()
