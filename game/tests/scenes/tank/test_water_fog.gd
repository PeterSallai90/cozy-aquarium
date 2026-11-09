# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #23 criteria 2 and 7 (owner: developer for WaterFogSettings and the room, technical-artist for
## the FogVolume nodes and the mirror values): the bounded in-tank FogVolume, the single place for
## every fog value (WaterFogSettings, ADR 0007) and the fog-off state. The froxel values have no
## renderer getter, so they are checked on the resource only.

const Api := preload("res://tests/helpers/late_api.gd")
const Rig := preload("res://tests/helpers/room_rig.gd")
const Table := preload("res://tests/helpers/tank_table.gd")
const Water := preload("res://tests/helpers/water_rig.gd")
const SourceScan := preload("res://tests/helpers/source_scan.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")

const MM := 0.001
const ENVIRONMENT_PATH := "res://scenes/room/room_environment.tres"
const SETTINGS_SCRIPT := "res://scenes/tank/water_fog_settings.gd"


func after_test() -> void:
	# apply_to_rendering_server() changes process-wide state: put the defaults back.
	Water.restore_rendering_server()


func _fog_of(tank_node: Node3D) -> FogVolume:
	var found: Array[Node] = Water.all_of(tank_node, "FogVolume")
	return found[0] as FogVolume if found.size() == 1 else null


func _preview() -> FogMaterial:
	if not ResourceLoader.exists(Water.FOG_MATERIAL):
		return null
	return load(Water.FOG_MATERIAL) as FogMaterial


func _number(settings: Resource, field: String) -> float:
	return Api.prop(settings, field, Api.MISSING_NUMBER)


func _open_room(fog_settings: Resource, id: StringName = Table.MEDIUM) -> Node3D:
	var room: Node3D = Water.room(Rig.model_with(id), Rig.default_catalog(), fog_settings)
	add_child(room)
	auto_free(room)
	await get_tree().process_frame
	return room


# --- AC 2: one bounded box FogVolume per tank ---


func test_ac02_each_tank_scene_has_exactly_one_fog_volume() -> void:
	for id: StringName in Table.IDS:
		var instance: Node3D = Water.tank(id)
		auto_free(instance)
		(
			assert_int(Water.all_of(instance, "FogVolume").size())
			. override_failure_message(str(id))
			. is_equal(1)
		)


func test_ac02_the_fog_volume_is_a_box() -> void:
	for id: StringName in Table.IDS:
		var instance: Node3D = Water.built_tank(id)
		auto_free(instance)
		var fog: FogVolume = _fog_of(instance)
		assert_object(fog).override_failure_message(str(id)).is_not_null()
		if fog != null:
			assert_int(fog.shape).override_failure_message(str(id)).is_equal(
				RenderingServer.FOG_VOLUME_SHAPE_BOX
			)


func test_ac02_the_fog_size_equals_the_water_volume_size() -> void:
	for id: StringName in Table.IDS:
		var instance: Node3D = Water.built_tank(id)
		auto_free(instance)
		var fog: FogVolume = _fog_of(instance)
		if fog == null:
			fail("%s: no FogVolume" % id)
			continue
		var expected: Vector3 = Water.definition(id).get_water_volume_size_m()
		assert_vector(fog.size).override_failure_message(str(id)).is_equal_approx(
			expected, Vector3.ONE * MM
		)


func test_ac02_the_fog_box_lies_inside_the_interior_box() -> void:
	for id: StringName in Table.IDS:
		var instance: Node3D = Water.built_tank(id)
		auto_free(instance)
		var fog: FogVolume = _fog_of(instance)
		if fog == null:
			fail("%s: no FogVolume" % id)
			continue
		var inner: Vector3 = Table.interior(id)
		var centre: Vector3 = Water.in_tank(instance, fog).origin
		var low: Vector3 = centre - fog.size / 2.0
		var high: Vector3 = centre + fog.size / 2.0
		var label: String = str(id)
		assert_float(low.x).override_failure_message(label).is_greater_equal(-inner.x / 2.0 - MM)
		assert_float(high.x).override_failure_message(label).is_less_equal(inner.x / 2.0 + MM)
		assert_float(low.y).override_failure_message(label).is_greater_equal(-MM)
		assert_float(high.y).override_failure_message(label).is_less_equal(inner.y + MM)
		assert_float(low.z).override_failure_message(label).is_greater_equal(-inner.z / 2.0 - MM)
		assert_float(high.z).override_failure_message(label).is_less_equal(inner.z / 2.0 + MM)


func test_ac02_the_fog_top_is_not_above_the_water_line() -> void:
	for id: StringName in Table.IDS:
		var instance: Node3D = Water.built_tank(id)
		auto_free(instance)
		var fog: FogVolume = _fog_of(instance)
		if fog == null:
			fail("%s: no FogVolume" % id)
			continue
		var top: float = Water.in_tank(instance, fog).origin.y + fog.size.y / 2.0
		assert_float(top).override_failure_message(str(id)).is_less_equal(Table.water_line(id) + MM)


func test_ac02_the_fog_material_density_is_above_zero_and_at_most_a_tenth() -> void:
	for id: StringName in Table.IDS:
		var instance: Node3D = Water.built_tank(id)
		auto_free(instance)
		var fog: FogVolume = _fog_of(instance)
		var material: FogMaterial = fog.material as FogMaterial if fog != null else null
		assert_object(material).override_failure_message("%s: FogMaterial" % id).is_not_null()
		if material != null:
			assert_float(material.density).override_failure_message(str(id)).is_between(
				0.0000001, 0.1
			)


func test_ac02_the_fog_albedo_is_set_from_the_settings() -> void:
	for id: StringName in Table.IDS:
		var settings: Resource = Water.settings()
		var expected: Color = Api.prop(settings, "albedo", Color.BLACK)
		var instance: Node3D = Water.built_tank(id, settings)
		auto_free(instance)
		var fog: FogVolume = _fog_of(instance)
		var material: FogMaterial = fog.material as FogMaterial if fog != null else null
		assert_object(material).is_not_null()
		if material != null:
			(
				assert_bool(material.albedo.is_equal_approx(expected))
				. override_failure_message(
					"%s: albedo %s, settings %s" % [id, material.albedo, expected]
				)
				. is_true()
			)
			(
				assert_bool(material.albedo.is_equal_approx(Color.WHITE))
				. override_failure_message("albedo must be tinted, not the default white")
				. is_false()
			)


func test_ac02_the_build_does_not_mutate_the_preview_material_resource() -> void:
	var settings: Resource = Water.settings()
	settings.set("density", 0.05)
	var preview: FogMaterial = _preview()
	assert_object(preview).is_not_null()
	var before: float = preview.density if preview != null else -1.0
	var instance: Node3D = Water.built_tank(Table.MEDIUM, settings)
	auto_free(instance)
	if preview != null:
		assert_float(preview.density).is_equal(before)


# --- AC 7: the single fog place ---


func test_ac07_the_fog_settings_default_instance_holds_the_planned_values() -> void:
	var settings: Resource = Water.settings()
	assert_bool(settings.has_signal("applied")).override_failure_message("signal applied").is_true()
	assert_that(Api.prop(settings, "volumetric_fog_enabled", null)).is_equal(true)
	assert_float(_number(settings, "density")).is_equal_approx(0.02, 0.1)
	assert_float(_number(settings, "volumetric_fog_length")).is_between(3.0, 8.0)
	assert_float(_number(settings, "volumetric_fog_detail_spread")).is_between(0.5, 6.0)
	assert_int(Api.prop(settings, "volume_size", -1)).is_between(16, 512)
	assert_int(Api.prop(settings, "volume_depth", -1)).is_between(16, 512)
	assert_that(Api.prop(settings, "use_filter", null)).is_not_null()


func test_ac07_apply_emits_applied_once() -> void:
	var settings: Resource = Water.settings()
	var count: Array[int] = [0]
	if settings.has_signal("applied"):
		settings.connect("applied", func() -> void: count[0] += 1)
	Api.call_on(settings, "apply", [], null)
	assert_int(count[0]).is_equal(1)


func test_ac07_apply_clamps_out_of_range_values_with_one_warning() -> void:
	var settings: Resource = Water.settings()
	settings.set("density", 5.0)
	settings.set("volumetric_fog_length", 1000.0)
	settings.set("volumetric_fog_detail_spread", 100.0)
	settings.set("volume_size", 100000)
	settings.set("volume_depth", 1)
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void: Api.call_on(settings, "apply", [], null)
	)
	assert_int(Water.count_of(seen["warnings"])).is_equal(1)
	assert_int(Water.count_of(seen["errors"])).is_equal(0)
	assert_int(Water.count_of(seen["script_errors"])).is_equal(0)
	assert_float(_number(settings, "density")).is_equal_approx(0.1, 0.0001)
	assert_float(_number(settings, "volumetric_fog_length")).is_equal_approx(64.0, 0.0001)
	assert_float(_number(settings, "volumetric_fog_detail_spread")).is_equal_approx(6.0, 0.0001)
	assert_int(Api.prop(settings, "volume_size", -1)).is_equal(512)
	assert_int(Api.prop(settings, "volume_depth", -1)).is_equal(16)


func test_ac07_apply_clamps_negative_density_and_short_length() -> void:
	var settings: Resource = Water.settings()
	settings.set("density", -1.0)
	settings.set("volumetric_fog_length", 0.0)
	settings.set("volumetric_fog_detail_spread", 0.0)
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void: Api.call_on(settings, "apply", [], null)
	)
	assert_int(Water.count_of(seen["warnings"])).is_equal(1)
	assert_float(_number(settings, "density")).is_equal_approx(0.0, 0.0001)
	assert_float(_number(settings, "volumetric_fog_length")).is_equal_approx(1.0, 0.0001)
	assert_float(_number(settings, "volumetric_fog_detail_spread")).is_equal_approx(0.5, 0.0001)


func test_ac07_values_in_range_apply_without_a_warning() -> void:
	var settings: Resource = Water.settings()
	assert_bool(settings.has_method("apply")).override_failure_message("apply() missing").is_true()
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void: Api.call_on(settings, "apply", [], null)
	)
	assert_int(Water.count_of(seen["warnings"])).is_equal(0)
	assert_int(Water.count_of(seen["errors"])).is_equal(0)


func test_ac07_changing_the_settings_updates_environment_and_fog_without_a_rebuild() -> void:
	var settings: Resource = Water.settings()
	var room: Node3D = await _open_room(settings)
	var tank_before: Node3D = Water.displayed_tank(room)
	assert_object(tank_before).is_not_null()
	settings.set("density", 0.05)
	settings.set("volumetric_fog_length", 5.0)
	settings.set("volumetric_fog_detail_spread", 3.0)
	settings.set("volume_size", 32)
	settings.set("volume_depth", 48)
	settings.set("use_filter", false)
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void: Api.call_on(settings, "apply", [], null)
	)
	assert_int(Water.count_of(seen["warnings"])).is_equal(0)
	assert_int(Water.count_of(seen["script_errors"])).is_equal(0)
	var environment: Environment = Water.environment_of(room)
	assert_object(environment).is_not_null()
	if environment != null:
		assert_bool(environment.volumetric_fog_enabled).is_true()
		assert_float(environment.volumetric_fog_length).is_equal_approx(5.0, 0.0001)
		assert_float(environment.volumetric_fog_detail_spread).is_equal_approx(3.0, 0.0001)
		assert_float(environment.volumetric_fog_density).is_equal(0.0)
	(
		assert_object(Water.displayed_tank(room))
		. override_failure_message("the tank must not be rebuilt")
		. is_same(tank_before)
	)
	var fog: FogVolume = _fog_of(tank_before)
	var material: FogMaterial = fog.material as FogMaterial if fog != null else null
	assert_object(material).is_not_null()
	if material != null:
		assert_float(material.density).is_equal_approx(0.05, 0.0001)
	assert_int(Api.prop(settings, "volume_size", -1)).is_equal(32)
	assert_int(Api.prop(settings, "volume_depth", -1)).is_equal(48)
	assert_that(Api.prop(settings, "use_filter", null)).is_equal(false)


func test_ac07_the_room_does_not_write_the_shared_environment_resource() -> void:
	var settings: Resource = Water.settings()
	var shared: Environment = load(ENVIRONMENT_PATH) as Environment
	var length_before: float = shared.volumetric_fog_length
	var room: Node3D = await _open_room(settings)
	settings.set("volumetric_fog_length", 5.0)
	Api.call_on(settings, "apply", [], null)
	(
		assert_object(Water.environment_of(room))
		. override_failure_message("the room must use its own copy of the environment")
		. is_not_same(shared)
	)
	assert_float(shared.volumetric_fog_length).is_equal(length_before)


func test_ac07_without_a_settings_argument_the_room_still_loads_with_the_default_resource() -> void:
	var room: Node3D = Rig.instantiate(Rig.model_with(Table.MEDIUM), Rig.default_catalog())
	add_child(room)
	auto_free(room)
	await get_tree().process_frame
	var environment: Environment = Water.environment_of(room)
	assert_object(environment).is_not_null()
	if environment != null:
		assert_bool(environment.volumetric_fog_enabled).is_true()
	assert_object(Water.displayed_tank(room)).is_not_null()


# --- AC 7: fog off ---


func _assert_fog_off_state(room: Node3D, label: String) -> void:
	var tank_node: Node3D = Water.displayed_tank(room)
	assert_object(tank_node).override_failure_message(label).is_not_null()
	if tank_node == null:
		return
	var environment: Environment = Water.environment_of(room)
	if environment != null:
		assert_bool(environment.volumetric_fog_enabled).override_failure_message(label).is_false()
	var fog: FogVolume = _fog_of(tank_node)
	if fog != null:
		assert_bool(fog.visible).override_failure_message("%s: fog hidden" % label).is_false()
	for node_name: String in ["Surface", "DepthTint"]:
		var node: MeshInstance3D = tank_node.get_node_or_null("WaterVolume/" + node_name)
		assert_object(node).override_failure_message("%s: %s" % [label, node_name]).is_not_null()
		if node != null:
			(
				assert_bool(node.is_visible_in_tree())
				. override_failure_message("%s: %s visible" % [label, node_name])
				. is_true()
			)
			assert_object(node.get_active_material(0)).is_not_null()
	var glass: MeshInstance3D = tank_node.get_node_or_null("Glass") as MeshInstance3D
	assert_object(glass).is_not_null()
	if glass != null:
		assert_bool(glass.is_visible_in_tree()).is_true()
		assert_object(glass.get_active_material(0)).is_not_null()


func test_ac07_fog_off_before_loading_the_room_keeps_everything_else_rendering() -> void:
	var settings: Resource = Water.settings()
	settings.set("volumetric_fog_enabled", false)
	var rooms: Array[Node3D] = []
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void: rooms.append(await _open_room(settings))
	)
	var room: Node3D = rooms[0]
	assert_int(Water.count_of(seen["warnings"])).is_equal(0)
	assert_int(Water.count_of(seen["errors"])).is_equal(0)
	assert_int(Water.count_of(seen["script_errors"])).is_equal(0)
	_assert_fog_off_state(room, "fog off at load")


func test_ac07_switching_fog_off_while_the_room_is_shown_keeps_the_depth_tint() -> void:
	var settings: Resource = Water.settings()
	var room: Node3D = await _open_room(settings)
	var tint: MeshInstance3D = (
		Water.displayed_tank(room).get_node_or_null("WaterVolume/DepthTint") as MeshInstance3D
	)
	assert_object(tint).is_not_null()
	if tint == null:
		return
	var material: ShaderMaterial = tint.get_active_material(0) as ShaderMaterial
	assert_object(material).is_not_null()
	if material == null:
		return
	var strength_before: Variant = material.get_shader_parameter("depth_tint_strength")
	var color_before: Variant = material.get_shader_parameter("depth_tint_color")
	settings.set("volumetric_fog_enabled", false)
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void: Api.call_on(settings, "apply", [], null)
	)
	assert_int(Water.count_of(seen["warnings"])).is_equal(0)
	assert_int(Water.count_of(seen["script_errors"])).is_equal(0)
	_assert_fog_off_state(room, "fog switched off")
	assert_object(tint.get_active_material(0)).is_same(material)
	assert_that(material.get_shader_parameter("depth_tint_strength")).is_equal(strength_before)
	assert_that(material.get_shader_parameter("depth_tint_color")).is_equal(color_before)


func test_ac07_fog_can_be_switched_on_again() -> void:
	var settings: Resource = Water.settings()
	settings.set("volumetric_fog_enabled", false)
	var room: Node3D = await _open_room(settings)
	settings.set("volumetric_fog_enabled", true)
	Api.call_on(settings, "apply", [], null)
	var environment: Environment = Water.environment_of(room)
	if environment != null:
		assert_bool(environment.volumetric_fog_enabled).is_true()
	var fog: FogVolume = _fog_of(Water.displayed_tank(room))
	assert_object(fog).is_not_null()
	if fog != null:
		assert_bool(fog.visible).is_true()


# --- AC 7: values come from one place ---


func test_ac07_the_art_mirrors_equal_the_fog_settings_defaults() -> void:
	var settings: Resource = Water.settings()
	var preview: FogMaterial = _preview()
	assert_object(preview).override_failure_message("water_fog.tres missing").is_not_null()
	if preview != null:
		assert_float(preview.density).is_equal_approx(_number(settings, "density"), 0.00001)
		var albedo: Color = Api.prop(settings, "albedo", Color.BLACK)
		(
			assert_bool(preview.albedo.is_equal_approx(albedo))
			. override_failure_message("preview albedo %s, settings %s" % [preview.albedo, albedo])
			. is_true()
		)
	var environment: Environment = load(ENVIRONMENT_PATH) as Environment
	assert_float(environment.volumetric_fog_length).is_equal_approx(
		_number(settings, "volumetric_fog_length"), 0.00001
	)
	assert_float(environment.volumetric_fog_detail_spread).is_equal_approx(
		_number(settings, "volumetric_fog_detail_spread"), 0.00001
	)
	assert_that(environment.volumetric_fog_enabled).is_equal(
		Api.prop(settings, "volumetric_fog_enabled", null)
	)


func test_ac07_no_fog_value_is_written_outside_the_fog_settings_script() -> void:
	var excluded: PackedStringArray = ["res://tests/", "res://addons/", SETTINGS_SCRIPT]
	var patterns: Array[RegEx] = (
		SourceScan
		. compile(
			[
				"volumetric_fog_\\w+\\s*[-+*/]?=[^=]",
				"environment_set_volumetric_fog",
				"\\.(density|albedo)\\s*[-+*/]?=[^=]",
				'set\\(\\s*"(density|albedo|volumetric_fog_\\w+)"',
			]
		)
	)
	var offenders: PackedStringArray = PackedStringArray()
	for path: String in SourceScan.list_scripts("res://", excluded):
		var source: String = SourceScan.strip_comments(SourceScan.read(path))
		for hit: String in SourceScan.find_matches(source, patterns):
			offenders.append("%s: %s" % [path, hit])
	(
		assert_str("\n".join(offenders))
		. override_failure_message(
			"fog values must be written only in water_fog_settings.gd:\n%s" % "\n".join(offenders)
		)
		. is_empty()
	)


func test_ac07_the_fog_settings_script_exists() -> void:
	(
		assert_bool(ResourceLoader.exists(SETTINGS_SCRIPT))
		. override_failure_message("%s missing" % SETTINGS_SCRIPT)
		. is_true()
	)
