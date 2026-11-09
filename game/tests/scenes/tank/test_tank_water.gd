# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #23 criteria 1, 5, 9, 10 and 12 (owner: developer for the script, technical-artist for the art
## nodes): the water volume of each tank scene, built from the catalog by TankWater.build() before
## the tank enters the tree. Node paths and API: technical plan of #23 and ADR 0007.

const Api := preload("res://tests/helpers/late_api.gd")
const Table := preload("res://tests/helpers/tank_table.gd")
const Water := preload("res://tests/helpers/water_rig.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")

const MM := 0.001


func _tank(id: StringName, fog_settings: Resource = null) -> Node3D:
	var instance: Node3D = Water.built_tank(id, fog_settings)
	auto_free(instance)
	(
		assert_bool(Water.is_built(Water.water_of(instance)))
		. override_failure_message("%s: WaterVolume is not built" % id)
		. is_true()
	)
	return instance


func _child(tank_node: Node3D, node_name: String) -> Node3D:
	var node: Node3D = tank_node.get_node_or_null("WaterVolume/" + node_name) as Node3D
	(
		assert_object(node)
		. override_failure_message("Tank/WaterVolume/%s missing" % node_name)
		. is_not_null()
	)
	return node


func _material_path(instance: MeshInstance3D) -> String:
	var material: Material = instance.get_active_material(0)
	return material.resource_path if material != null else "<no material>"


# --- AC 1: size, position, bounds ---


func test_ac01_each_tank_is_built_and_reports_the_catalog_water_size() -> void:
	for id: StringName in Table.IDS:
		var instance: Node3D = _tank(id)
		var water: Node3D = Water.water_of(instance)
		var expected: Vector3 = Water.definition(id).get_water_volume_size_m()
		assert_bool(Water.is_built(water)).override_failure_message(str(id)).is_true()
		assert_vector(Water.size_of(water)).override_failure_message(str(id)).is_equal_approx(
			expected, Vector3.ONE * MM
		)


func test_ac01_the_size_is_interior_width_water_line_and_interior_depth() -> void:
	for id: StringName in Table.IDS:
		var inner: Vector3 = Table.interior(id)
		var size: Vector3 = Water.size_of(Water.water_of(_tank(id)))
		assert_vector(size).override_failure_message(str(id)).is_equal_approx(
			Vector3(inner.x, Table.water_line(id), inner.z), Vector3.ONE * MM
		)


func test_ac01_bottom_is_at_tank_local_zero_and_top_at_the_water_line() -> void:
	for id: StringName in Table.IDS:
		var bounds: AABB = Water.bounds_of(Water.water_of(_tank(id)))
		assert_float(bounds.position.y).override_failure_message(str(id)).is_equal_approx(0.0, MM)
		assert_float(bounds.end.y).override_failure_message(str(id)).is_equal_approx(
			Table.water_line(id), MM
		)


func test_ac01_bounds_are_centred_on_the_interior_in_x_and_z() -> void:
	for id: StringName in Table.IDS:
		var inner: Vector3 = Table.interior(id)
		var bounds: AABB = Water.bounds_of(Water.water_of(_tank(id)))
		var label: String = str(id)
		assert_float(bounds.position.x).override_failure_message(label).is_equal_approx(
			-inner.x / 2.0, MM
		)
		assert_float(bounds.end.x).override_failure_message(label).is_equal_approx(
			inner.x / 2.0, MM
		)
		assert_float(bounds.position.z).override_failure_message(label).is_equal_approx(
			-inner.z / 2.0, MM
		)
		assert_float(bounds.end.z).override_failure_message(label).is_equal_approx(
			inner.z / 2.0, MM
		)


func test_ac01_the_top_is_below_the_rim() -> void:
	for id: StringName in Table.IDS:
		var bounds: AABB = Water.bounds_of(Water.water_of(_tank(id)))
		assert_float(bounds.end.y).override_failure_message(str(id)).is_less(Table.interior(id).y)


func test_ac01_water_volume_stays_at_half_the_water_line_with_scale_one() -> void:
	for id: StringName in Table.IDS:
		var water: Node3D = Water.water_of(_tank(id))
		assert_float(water.position.y).override_failure_message(str(id)).is_equal_approx(
			Table.water_line(id) / 2.0, MM
		)
		assert_float(water.position.x).is_equal_approx(0.0, MM)
		assert_float(water.position.z).is_equal_approx(0.0, MM)
		assert_vector(water.scale).override_failure_message(str(id)).is_equal_approx(
			Vector3.ONE, Vector3.ONE * 0.0001
		)


func test_ac01_the_built_signal_reports_the_size() -> void:
	var instance: Node3D = Water.tank(Table.MEDIUM)
	auto_free(instance)
	var water: Node3D = Water.water_of(instance)
	var seen: Array[Vector3] = []
	if water.has_signal("built"):
		water.connect("built", func(size: Vector3) -> void: seen.append(size))
	Water.build(water, Water.definition(Table.MEDIUM), Water.settings())
	assert_int(seen.size()).override_failure_message("built emitted once").is_equal(1)
	if seen.size() == 1:
		assert_vector(seen[0]).is_equal_approx(
			Water.definition(Table.MEDIUM).get_water_volume_size_m(), Vector3.ONE * MM
		)


func test_ac01_children_are_sized_from_the_catalog() -> void:
	for id: StringName in Table.IDS:
		var label: String = str(id)
		var instance: Node3D = _tank(id)
		var expected: Vector3 = Water.definition(id).get_water_volume_size_m()
		var surface: MeshInstance3D = _child(instance, "Surface") as MeshInstance3D
		var tint: MeshInstance3D = _child(instance, "DepthTint") as MeshInstance3D
		var fog: FogVolume = _child(instance, "Fog") as FogVolume
		if surface != null and surface.mesh is PlaneMesh:
			var plane: PlaneMesh = surface.mesh as PlaneMesh
			assert_float(plane.size.x).override_failure_message(label).is_equal_approx(
				expected.x, MM
			)
			assert_float(plane.size.y).override_failure_message(label).is_equal_approx(
				expected.z, MM
			)
		else:
			fail("%s: Surface has no PlaneMesh" % label)
		if tint != null and tint.mesh is BoxMesh:
			(
				assert_vector((tint.mesh as BoxMesh).size)
				. override_failure_message(label)
				. is_equal_approx(expected, Vector3.ONE * MM)
			)
		else:
			fail("%s: DepthTint has no BoxMesh" % label)
		if fog != null:
			assert_vector(fog.size).override_failure_message(label).is_equal_approx(
				expected, Vector3.ONE * MM
			)


func test_ac01_instance_parameter_water_size_equals_the_size() -> void:
	for id: StringName in Table.IDS:
		var instance: Node3D = _tank(id)
		var expected: Vector3 = Water.definition(id).get_water_volume_size_m()
		for node_name: String in ["Surface", "DepthTint"]:
			var label: String = "%s %s" % [id, node_name]
			var node: GeometryInstance3D = _child(instance, node_name) as GeometryInstance3D
			if node == null:
				continue
			var value: Variant = node.get_instance_shader_parameter("water_size_m")
			assert_that(value).override_failure_message(label).is_not_null()
			if value is Vector3:
				assert_vector(value as Vector3).override_failure_message(label).is_equal_approx(
					expected, Vector3.ONE * MM
				)


func test_ac01_a_second_build_does_not_stack_nodes_or_change_the_size() -> void:
	var instance: Node3D = _tank(Table.MEDIUM)
	var water: Node3D = Water.water_of(instance)
	var count: int = water.get_child_count()
	Water.build(water, Water.definition(Table.MEDIUM), Water.settings())
	assert_int(water.get_child_count()).is_equal(count)
	assert_vector(Water.size_of(water)).is_equal_approx(
		Water.definition(Table.MEDIUM).get_water_volume_size_m(), Vector3.ONE * MM
	)


# --- AC 5: materials and surface ---


func test_ac05_the_glass_uses_the_tank_glass_material() -> void:
	for id: StringName in Table.IDS:
		var glass: MeshInstance3D = _tank(id).get_node_or_null("Glass") as MeshInstance3D
		assert_object(glass).is_not_null()
		if glass == null:
			continue
		assert_int(glass.mesh.get_surface_count()).is_greater(0)
		for surface: int in glass.mesh.get_surface_count():
			var material: Material = glass.get_active_material(surface)
			assert_object(material).override_failure_message(str(id)).is_instanceof(ShaderMaterial)
			(
				assert_str(material.resource_path if material != null else "")
				. override_failure_message("%s surface %d" % [id, surface])
				. is_equal(Water.GLASS_MATERIAL)
			)


func test_ac05_the_surface_uses_the_water_surface_material() -> void:
	for id: StringName in Table.IDS:
		var surface: MeshInstance3D = _child(_tank(id), "Surface") as MeshInstance3D
		if surface != null:
			assert_str(_material_path(surface)).override_failure_message(str(id)).is_equal(
				Water.SURFACE_MATERIAL
			)


func test_ac05_the_depth_tint_uses_the_water_depth_tint_material() -> void:
	for id: StringName in Table.IDS:
		var tint: MeshInstance3D = _child(_tank(id), "DepthTint") as MeshInstance3D
		if tint != null:
			assert_str(_material_path(tint)).override_failure_message(str(id)).is_equal(
				Water.DEPTH_TINT_MATERIAL
			)


func test_ac05_the_surface_sits_at_the_water_line_in_tank_local_space() -> void:
	for id: StringName in Table.IDS:
		var instance: Node3D = _tank(id)
		var surface: Node3D = _child(instance, "Surface")
		if surface == null:
			continue
		var origin: Vector3 = Water.in_tank(instance, surface).origin
		assert_float(origin.y).override_failure_message(str(id)).is_equal_approx(
			Table.water_line(id), MM
		)
		assert_float(origin.x).is_equal_approx(0.0, MM)
		assert_float(origin.z).is_equal_approx(0.0, MM)


func test_ac05_the_surface_spans_the_interior_width_and_depth() -> void:
	for id: StringName in Table.IDS:
		var surface: MeshInstance3D = _child(_tank(id), "Surface") as MeshInstance3D
		if surface == null or not surface.mesh is PlaneMesh:
			fail("%s: no Surface PlaneMesh" % id)
			continue
		var inner: Vector3 = Table.interior(id)
		var box: AABB = surface.get_aabb()
		assert_float(box.size.x).override_failure_message(str(id)).is_equal_approx(inner.x, MM)
		assert_float(box.size.z).override_failure_message(str(id)).is_equal_approx(inner.z, MM)


func test_ac05_the_surface_is_below_the_rim() -> void:
	for id: StringName in Table.IDS:
		var instance: Node3D = _tank(id)
		var surface: Node3D = _child(instance, "Surface")
		if surface != null:
			(
				assert_float(Water.in_tank(instance, surface).origin.y)
				. override_failure_message(str(id))
				. is_less(Table.interior(id).y)
			)


func test_ac05_the_water_nodes_do_not_cast_shadows() -> void:
	for id: StringName in Table.IDS:
		var instance: Node3D = _tank(id)
		for node_name: String in ["Surface", "Fog", "DepthTint"]:
			var node: GeometryInstance3D = _child(instance, node_name) as GeometryInstance3D
			if node != null:
				(
					assert_int(node.cast_shadow)
					. override_failure_message("%s %s" % [id, node_name])
					. is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
				)


func test_ac05_the_scene_has_exactly_one_surface_fog_and_depth_tint() -> void:
	for id: StringName in Table.IDS:
		var instance: Node3D = _tank(id)
		for node_name: String in ["Surface", "Fog", "DepthTint"]:
			(
				assert_int(Water.named(instance, node_name).size())
				. override_failure_message("%s %s" % [id, node_name])
				. is_equal(1)
			)


# --- AC 9: invalid water lines ---


func _invalid_definition(water_line: float) -> TankDefinition:
	var copy: TankDefinition = Water.definition(Table.MEDIUM).duplicate() as TankDefinition
	copy.water_line_height_m = water_line
	return copy


func _build_invalid(water_line: float) -> Dictionary:
	var instance: Node3D = Water.tank(Table.MEDIUM)
	auto_free(instance)
	var water: Node3D = Water.water_of(instance)
	var settings: Resource = Water.settings()
	var def: TankDefinition = _invalid_definition(water_line)
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void: Water.build(water, def, settings)
	)
	seen["water"] = water
	return seen


func _assert_not_built_with_one_warning(seen: Dictionary, label: String) -> void:
	var water: Node3D = seen["water"] as Node3D
	(
		assert_int(Water.count_of(seen["warnings"]))
		. override_failure_message("%s: exactly one warning" % label)
		. is_equal(1)
	)
	assert_int(Water.count_of(seen["errors"])).override_failure_message(label).is_equal(0)
	assert_int(Water.count_of(seen["script_errors"])).override_failure_message(label).is_equal(0)
	assert_bool(Water.is_built(water)).override_failure_message(label).is_false()
	assert_vector(Water.size_of(water)).override_failure_message(label).is_equal(Vector3.ZERO)


func test_ac09_a_zero_water_line_is_not_built_and_warns_once() -> void:
	_assert_not_built_with_one_warning(await _build_invalid(0.0), "water line 0")


func test_ac09_a_negative_water_line_is_not_built_and_warns_once() -> void:
	_assert_not_built_with_one_warning(await _build_invalid(-0.1), "water line -0.1")


func test_ac09_a_water_line_equal_to_the_interior_height_is_not_built_and_warns_once() -> void:
	var height: float = Table.interior(Table.MEDIUM).y
	_assert_not_built_with_one_warning(await _build_invalid(height), "water line = interior")


func test_ac09_a_water_line_above_the_interior_height_is_not_built_and_warns_once() -> void:
	var height: float = Table.interior(Table.MEDIUM).y + 0.1
	_assert_not_built_with_one_warning(await _build_invalid(height), "water line above interior")


func test_ac09_a_null_definition_is_not_built_and_warns_once() -> void:
	var instance: Node3D = Water.tank(Table.MEDIUM)
	auto_free(instance)
	var water: Node3D = Water.water_of(instance)
	var settings: Resource = Water.settings()
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void: Api.call_on(water, "build", [null, settings], null)
	)
	seen["water"] = water
	_assert_not_built_with_one_warning(seen, "null definition")


func test_ac09_build_returns_false_for_an_invalid_water_line() -> void:
	var instance: Node3D = Water.tank(Table.MEDIUM)
	auto_free(instance)
	var water: Node3D = Water.water_of(instance)
	var settings: Resource = Water.settings()
	var def: TankDefinition = _invalid_definition(0.0)
	var results: Array = []
	await EngineOutput.capture_all(
		func() -> void: results.append(Water.build(water, def, settings))
	)
	(
		assert_bool(results.size() == 1 and typeof(results[0]) == TYPE_BOOL and not results[0])
		. override_failure_message("build() must return false, got %s" % [results])
		. is_true()
	)


func test_ac09_an_invalid_build_hides_the_children() -> void:
	var seen: Dictionary = await _build_invalid(-0.5)
	var water: Node3D = seen["water"] as Node3D
	for node_name: String in ["Surface", "Fog", "DepthTint"]:
		var node: Node3D = water.get_node_or_null(node_name) as Node3D
		assert_object(node).override_failure_message("%s missing" % node_name).is_not_null()
		if node != null:
			assert_bool(node.visible).override_failure_message(node_name).is_false()


func test_ac09_a_valid_build_after_an_invalid_one_recovers() -> void:
	var seen: Dictionary = await _build_invalid(0.0)
	var water: Node3D = seen["water"] as Node3D
	var result: Variant = Water.build(water, Water.definition(Table.MEDIUM), Water.settings())
	assert_bool(Water.is_true(result)).is_true()
	assert_vector(Water.size_of(water)).is_equal_approx(
		Water.definition(Table.MEDIUM).get_water_volume_size_m(), Vector3.ONE * MM
	)


# --- AC 10: missing nodes or shaders ---


func _build_without(node_name: String) -> Dictionary:
	var instance: Node3D = Water.tank(Table.MEDIUM)
	auto_free(instance)
	var water: Node3D = Water.water_of(instance)
	var removed: Node = water.get_node_or_null(node_name)
	(
		assert_object(removed)
		. override_failure_message("%s missing from the scene" % node_name)
		. is_not_null()
	)
	if removed != null:
		water.remove_child(removed)
		removed.free()
	var settings: Resource = Water.settings()
	var def: TankDefinition = Water.definition(Table.MEDIUM)
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void: Water.build(water, def, settings)
	)
	seen["water"] = water
	return seen


func _assert_quiet(seen: Dictionary, label: String) -> void:
	assert_int(Water.count_of(seen["warnings"])).override_failure_message(label).is_less_equal(1)
	assert_int(Water.count_of(seen["errors"])).override_failure_message(label).is_equal(0)
	assert_int(Water.count_of(seen["script_errors"])).override_failure_message(label).is_equal(0)


func test_ac10_a_missing_surface_does_not_break_the_build() -> void:
	var seen: Dictionary = await _build_without("Surface")
	_assert_quiet(seen, "no Surface")
	var water: Node3D = seen["water"] as Node3D
	assert_bool(Water.is_built(water)).is_true()
	var fog: FogVolume = water.get_node_or_null("Fog") as FogVolume
	assert_object(fog).is_not_null()
	if fog != null:
		assert_vector(fog.size).is_equal_approx(
			Water.definition(Table.MEDIUM).get_water_volume_size_m(), Vector3.ONE * MM
		)


func test_ac10_a_missing_fog_does_not_break_the_build() -> void:
	var seen: Dictionary = await _build_without("Fog")
	_assert_quiet(seen, "no Fog")
	var water: Node3D = seen["water"] as Node3D
	assert_bool(Water.is_built(water)).is_true()
	assert_object(water.get_node_or_null("Surface")).is_not_null()


func test_ac10_a_missing_depth_tint_does_not_break_the_build() -> void:
	var seen: Dictionary = await _build_without("DepthTint")
	_assert_quiet(seen, "no DepthTint")
	assert_bool(Water.is_built(seen["water"])).is_true()


func test_ac10_a_surface_material_without_a_shader_does_not_break_the_build() -> void:
	var instance: Node3D = Water.tank(Table.MEDIUM)
	auto_free(instance)
	var water: Node3D = Water.water_of(instance)
	var surface: MeshInstance3D = water.get_node_or_null("Surface") as MeshInstance3D
	assert_object(surface).is_not_null()
	if surface == null:
		return
	var material: ShaderMaterial = surface.get_active_material(0) as ShaderMaterial
	assert_object(material).is_not_null()
	if material == null:
		return
	var copy: ShaderMaterial = material.duplicate() as ShaderMaterial
	copy.shader = null
	surface.material_override = copy
	var settings: Resource = Water.settings()
	var def: TankDefinition = Water.definition(Table.MEDIUM)
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void: Water.build(water, def, settings)
	)
	_assert_quiet(seen, "surface shader cleared")
	assert_bool(Water.is_built(water)).is_true()


func test_ac10_the_glass_still_renders_when_the_surface_is_missing() -> void:
	var seen: Dictionary = await _build_without("Surface")
	var water: Node3D = seen["water"] as Node3D
	var glass: MeshInstance3D = water.get_parent().get_node_or_null("Glass") as MeshInstance3D
	assert_object(glass).is_not_null()
	if glass != null:
		assert_bool(glass.visible).is_true()
		assert_object(glass.get_active_material(0)).is_not_null()


# --- AC 12: meniscus parameters ---


func _build_with_meniscus(strength: float, width: float) -> Dictionary:
	var instance: Node3D = Water.tank(Table.MEDIUM)
	auto_free(instance)
	var surface: MeshInstance3D = instance.get_node_or_null("WaterVolume/Surface") as MeshInstance3D
	var material: ShaderMaterial = null
	if surface != null:
		material = surface.get_active_material(0) as ShaderMaterial
	assert_object(material).override_failure_message("Surface ShaderMaterial").is_not_null()
	if material != null:
		var copy: ShaderMaterial = material.duplicate() as ShaderMaterial
		copy.set_shader_parameter("meniscus_strength", strength)
		copy.set_shader_parameter("meniscus_width_m", width)
		surface.material_override = copy
	var water: Node3D = Water.water_of(instance)
	var settings: Resource = Water.settings()
	var def: TankDefinition = Water.definition(Table.MEDIUM)
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void: Water.build(water, def, settings)
	)
	seen["water"] = water
	return seen


func test_ac12_meniscus_strength_zero_builds_without_output() -> void:
	var seen: Dictionary = await _build_with_meniscus(0.0, 0.003)
	assert_int(Water.count_of(seen["warnings"])).is_equal(0)
	_assert_quiet(seen, "strength 0")
	assert_bool(Water.is_built(seen["water"])).is_true()


func test_ac12_meniscus_width_zero_builds_without_output() -> void:
	var seen: Dictionary = await _build_with_meniscus(0.3, 0.0)
	assert_int(Water.count_of(seen["warnings"])).is_equal(0)
	_assert_quiet(seen, "width 0")
	assert_bool(Water.is_built(seen["water"])).is_true()


func test_ac12_out_of_range_meniscus_values_cause_at_most_one_warning() -> void:
	for pair: Array in [[-1.0, 0.003], [5.0, 0.003], [0.3, -0.01], [0.3, 0.5]]:
		var seen: Dictionary = await _build_with_meniscus(pair[0], pair[1])
		_assert_quiet(seen, "meniscus %s" % [pair])
		assert_bool(Water.is_built(seen["water"])).is_true()
