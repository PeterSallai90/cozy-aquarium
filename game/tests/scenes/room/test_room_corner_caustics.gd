# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #126 criteria 2, 4, 5 and 6 in the live room (owner: developer for room_corner.gd and
## TankCaustics, technical-artist for the shader that must load without errors): small, then
## large, then small again with tank, cabinet and lamp swapping each time; the caustic values
## come from the displayed lamp's KeyLight. ADR 0007 Amendment 1 and the technical plan of #126.

const Api := preload("res://tests/helpers/late_api.gd")
const Rig := preload("res://tests/helpers/room_rig.gd")
const Table := preload("res://tests/helpers/tank_table.gd")
const Water := preload("res://tests/helpers/water_rig.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")

const MM := 0.001

var _model: AquariumModel = null
var _catalog: RefCounted = null
var _history: CommandHistory = null
var _fog: Resource = null
var _caustic: Resource = null


func before_test() -> void:
	_catalog = Rig.default_catalog()
	_history = CommandHistory.new()
	_model = Rig.model_with(Table.SMALL)
	_fog = Water.settings()
	_caustic = Water.caustic_settings()


func after_test() -> void:
	Water.restore_rendering_server()


func _open_room(catalog: RefCounted = null) -> Node3D:
	var room: Node3D = Water.room_with_caustics(
		_model, catalog if catalog != null else _catalog, _fog, _caustic
	)
	add_child(room)
	auto_free(room)
	await get_tree().process_frame
	return room


func _change(id: StringName) -> void:
	(
		assert_bool(_history.execute(Api.change_tank(_model, _catalog, id)))
		. override_failure_message("change to %s" % id)
		. is_true()
	)
	await get_tree().process_frame
	await get_tree().process_frame


func _key_light(room: Node3D) -> SpotLight3D:
	return room.get_node_or_null("Lamp/KeyLight") as SpotLight3D


func _water(room: Node3D) -> Node3D:
	return Water.water_of(Water.displayed_tank(room))


func _caustics(room: Node3D) -> Node3D:
	var tank_node: Node3D = Water.displayed_tank(room)
	if tank_node == null:
		return null
	return Water.caustics_of(tank_node)


func _caustic_connections() -> int:
	return _caustic.get_signal_connection_list("applied").size()


func _fog_connections() -> int:
	return _fog.get_signal_connection_list("applied").size()


## Exactly one Caustics under Tank/WaterVolume, sized for the tank, fed by the displayed lamp.
func _assert_caustics(room: Node3D, id: StringName) -> void:
	var tank_node: Node3D = Water.displayed_tank(room)
	assert_object(tank_node).override_failure_message("no Tank for %s" % id).is_not_null()
	if tank_node == null:
		return
	var found: Array[Node] = Water.named(tank_node, "Caustics")
	assert_int(found.size()).override_failure_message("%s: Caustics count" % id).is_equal(1)
	var node: MeshInstance3D = Water.caustics_of(tank_node) as MeshInstance3D
	if node == null:
		return
	var water: Node3D = _water(room)
	assert_object(node.get_parent()).override_failure_message("%s: parent" % id).is_same(water)
	var expected_size: Vector3 = Water.definition(id).get_water_volume_size_m()
	var box: BoxMesh = node.mesh as BoxMesh
	assert_object(box).override_failure_message("%s: BoxMesh" % id).is_not_null()
	if box != null:
		assert_vector(box.size).override_failure_message("%s: box size" % id).is_equal_approx(
			expected_size, Vector3.ONE * MM
		)
	var light: SpotLight3D = _key_light(room)
	assert_object(light).override_failure_message("%s: Lamp/KeyLight" % id).is_not_null()
	if light != null:
		var expected: Dictionary = Water.expected_lamp(water, light)
		(
			assert_bool(
				Water.near_vector(
					Water.param(node, &"lamp_position_m"), expected["lamp_position_m"]
				)
			)
			. override_failure_message(
				(
					"%s: lamp_position_m %s, expected %s"
					% [id, Water.param(node, &"lamp_position_m"), expected["lamp_position_m"]]
				)
			)
			. is_true()
		)
		(
			assert_bool(
				Water.near_vector(Water.param(node, &"lamp_direction"), expected["lamp_direction"])
			)
			. override_failure_message(
				(
					"%s: lamp_direction %s, expected %s"
					% [id, Water.param(node, &"lamp_direction"), expected["lamp_direction"]]
				)
			)
			. is_true()
		)
		(
			assert_bool(Water.near(Water.param(node, &"lamp_spot_angle_deg"), light.spot_angle))
			. override_failure_message("%s: spot angle" % id)
			. is_true()
		)
		(
			assert_bool(Water.near(Water.param(node, &"lamp_spot_range_m"), light.spot_range))
			. override_failure_message("%s: spot range" % id)
			. is_true()
		)
	assert_bool(node.visible).override_failure_message("%s: hidden under a lamp" % id).is_true()
	var global_box: AABB = node.global_transform * node.get_aabb()
	var inner: Vector3 = Table.interior(id)
	var interior: AABB = (
		tank_node.global_transform * AABB(Vector3(-inner.x / 2.0, 0.0, -inner.z / 2.0), inner)
	)
	(
		assert_bool(interior.grow(MM).encloses(global_box))
		. override_failure_message(
			"%s: %s is outside the tank interior %s" % [id, global_box, interior]
		)
		. is_true()
	)


func _assert_no_node_reference(room: Node3D) -> void:
	var node: Node3D = _caustics(room)
	assert_object(node).override_failure_message("no Caustics to inspect").is_not_null()
	if node == null:
		return
	for property: Dictionary in node.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var value: Variant = node.get(String(property["name"]))
		(
			assert_bool(value is Node)
			. override_failure_message("script variable %s holds a Node" % property["name"])
			. is_false()
		)


# --- AC 2: swaps ---


func test_ac02_the_first_tank_has_one_caustics_fed_by_its_lamp() -> void:
	var room: Node3D = await _open_room()
	_assert_caustics(room, Table.SMALL)


func test_ac02_small_then_large_then_small_each_show_one_caustics_for_the_new_tank() -> void:
	var room: Node3D = await _open_room()
	_assert_caustics(room, Table.SMALL)
	await _change(Table.LARGE)
	_assert_caustics(room, Table.LARGE)
	await _change(Table.SMALL)
	_assert_caustics(room, Table.SMALL)


func test_ac02_the_medium_tank_has_one_caustics_too() -> void:
	_model = Rig.model_with(Table.MEDIUM)
	var room: Node3D = await _open_room()
	_assert_caustics(room, Table.MEDIUM)


func test_ac02_the_swaps_raise_no_error_and_no_warning() -> void:
	var rooms: Array[Node3D] = []
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void:
			rooms.append(await _open_room())
			await _change(Table.LARGE)
			await _change(Table.SMALL)
	)
	assert_int(Water.count_of(seen["errors"])).override_failure_message(str(seen)).is_equal(0)
	assert_int(Water.count_of(seen["warnings"])).override_failure_message(str(seen)).is_equal(0)
	assert_int(Water.count_of(seen["script_errors"])).override_failure_message(str(seen)).is_equal(
		0
	)
	_assert_caustics(rooms[0], Table.SMALL)


func test_ac02_the_previous_caustics_is_freed_with_its_tank() -> void:
	var room: Node3D = await _open_room()
	var old_node: Node3D = _caustics(room)
	assert_object(old_node).is_not_null()
	if old_node == null:
		return
	var old_id: int = old_node.get_instance_id()
	await _change(Table.LARGE)
	(
		assert_object(instance_from_id(old_id))
		. override_failure_message("the Caustics of the previous tank was not freed")
		. is_null()
	)
	await _change(Table.SMALL)
	assert_object(_caustics(room)).is_not_null()


func test_ac02_the_caustic_settings_signal_has_one_connection_after_every_swap() -> void:
	var room: Node3D = await _open_room()
	assert_int(_caustic_connections()).override_failure_message("after load").is_equal(1)
	for id: StringName in [Table.LARGE, Table.SMALL, Table.MEDIUM]:
		await _change(id)
		(
			assert_int(_caustic_connections())
			. override_failure_message("after the swap to %s" % id)
			. is_equal(1)
		)
	assert_object(room).is_not_null()


func test_ac02_the_fog_settings_signal_still_has_two_connections_after_every_swap() -> void:
	var room: Node3D = await _open_room()
	assert_int(_fog_connections()).override_failure_message("after load").is_equal(2)
	for id: StringName in [Table.LARGE, Table.SMALL]:
		await _change(id)
		(
			assert_int(_fog_connections())
			. override_failure_message("after the swap to %s" % id)
			. is_equal(2)
		)
	assert_object(room).is_not_null()


func test_ac02_the_caustics_holds_no_node_after_the_swaps() -> void:
	var room: Node3D = await _open_room()
	await _change(Table.LARGE)
	await _change(Table.SMALL)
	_assert_no_node_reference(room)


func test_ac02_a_lamp_swap_gives_each_lamp_its_own_footprint() -> void:
	var room: Node3D = await _open_room()
	var light: SpotLight3D = _key_light(room)
	assert_object(light).is_not_null()
	if light == null:
		return
	light.spot_angle = 33.0
	light.spot_range = 0.45
	Api.call_on(_water(room), "set_key_light", [light], null)
	var node: Node3D = _caustics(room)
	assert_bool(Water.near(Water.param(node, &"lamp_spot_angle_deg"), 33.0)).is_true()
	assert_bool(Water.near(Water.param(node, &"lamp_spot_range_m"), 0.45)).is_true()
	var expected: Dictionary = Water.expected_lamp(_water(room), light)
	(
		assert_bool(
			Water.near_vector(Water.param(node, &"lamp_direction"), expected["lamp_direction"])
		)
		. is_true()
	)


func test_ac02_an_applied_change_reaches_only_the_displayed_tank() -> void:
	var room: Node3D = await _open_room()
	await _change(Table.LARGE)
	_caustic.set("caustic_intensity", 1.5)
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void: Api.call_on(_caustic, "apply", [], null)
	)
	assert_int(Water.count_of(seen["errors"])).is_equal(0)
	assert_int(Water.count_of(seen["script_errors"])).is_equal(0)
	assert_int(Water.count_of(seen["warnings"])).is_equal(0)
	assert_bool(Water.near(Water.param(_caustics(room), &"caustic_intensity"), 1.5)).is_true()


func test_ac02_the_caustic_values_survive_a_swap() -> void:
	var room: Node3D = await _open_room()
	_caustic.set("caustic_scale", 40.0)
	_caustic.set("caustic_speed", 0.5)
	Api.call_on(_caustic, "apply", [], null)
	await _change(Table.LARGE)
	var node: Node3D = _caustics(room)
	assert_bool(Water.near(Water.param(node, &"caustic_scale"), 40.0)).is_true()
	assert_bool(Water.near(Water.param(node, &"caustic_speed"), 0.5)).is_true()


# --- AC 4: no shader or material errors in the headless load ---


func test_ac04_the_room_loads_each_tank_without_any_engine_output() -> void:
	for id: StringName in Table.IDS:
		_model = Rig.model_with(id)
		_fog = Water.settings()
		_caustic = Water.caustic_settings()
		var rooms: Array[Node3D] = []
		var seen: Dictionary = await EngineOutput.capture_all(
			func() -> void:
				rooms.append(await _open_room())
				await get_tree().process_frame
		)
		for kind: String in ["errors", "warnings", "script_errors"]:
			(
				assert_int(Water.count_of(seen[kind]))
				. override_failure_message("%s: %s %s" % [id, kind, seen[kind]])
				. is_equal(0)
			)
		_assert_caustics(rooms[0], id)
		rooms[0].queue_free()
		await get_tree().process_frame


# --- AC 5: failure cases in the live room ---


func test_ac05_a_removed_caustics_does_not_break_a_swap_or_an_apply() -> void:
	var room: Node3D = await _open_room()
	for node: Node in Water.named(Water.displayed_tank(room), "Caustics"):
		node.get_parent().remove_child(node)
		node.free()
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void:
			Api.call_on(_caustic, "apply", [], null)
			Api.call_on(_water(room), "set_key_light", [_key_light(room)], null)
			await _change(Table.LARGE)
	)
	assert_int(Water.count_of(seen["errors"])).override_failure_message(str(seen)).is_equal(0)
	assert_int(Water.count_of(seen["script_errors"])).override_failure_message(str(seen)).is_equal(
		0
	)
	assert_int(Water.count_of(seen["warnings"])).override_failure_message(str(seen)).is_less_equal(
		1
	)
	_assert_caustics(room, Table.LARGE)


func test_ac05_the_room_still_shows_tank_glass_water_and_contents_without_caustics() -> void:
	var room: Node3D = await _open_room()
	var tank_node: Node3D = Water.displayed_tank(room)
	var present: Array[Node] = Water.named(tank_node, "Caustics")
	assert_int(present.size()).override_failure_message("no Caustics to remove").is_equal(1)
	for node: Node in present:
		node.get_parent().remove_child(node)
		node.free()
	await get_tree().process_frame
	var glass: MeshInstance3D = tank_node.get_node_or_null("Glass") as MeshInstance3D
	assert_object(glass).is_not_null()
	if glass != null:
		assert_bool(glass.is_visible_in_tree()).is_true()
	for node_name: String in ["Surface", "DepthTint"]:
		var child: Node3D = Water.named(tank_node, node_name)[0] as Node3D
		assert_bool(child.is_visible_in_tree()).override_failure_message(node_name).is_true()
	assert_object(tank_node.get_node_or_null("SubstrateAnchor")).is_not_null()
	assert_object(room.get_node_or_null("Cabinet")).is_not_null()


func test_ac05_a_caustics_material_without_a_shader_does_not_break_the_room() -> void:
	var room: Node3D = await _open_room()
	var node: MeshInstance3D = _caustics(room) as MeshInstance3D
	if node != null:
		node.material_override = ShaderMaterial.new()
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void:
			Api.call_on(_caustic, "apply", [], null)
			await _change(Table.LARGE)
	)
	assert_int(Water.count_of(seen["errors"])).override_failure_message(str(seen)).is_equal(0)
	assert_int(Water.count_of(seen["script_errors"])).override_failure_message(str(seen)).is_equal(
		0
	)
	assert_int(Water.count_of(seen["warnings"])).override_failure_message(str(seen)).is_less_equal(
		1
	)
	_assert_caustics(room, Table.LARGE)


# --- AC 6: no displayed lamp ---


func _catalog_with_lamp(lamp: PackedScene) -> RefCounted:
	var source: Resource = Rig.definition_of(Table.MEDIUM)
	var copy: Resource = source.duplicate() as Resource
	copy.set("lamp_scene", lamp)
	return Api.catalog_from([copy])


func test_ac06_a_definition_without_a_lamp_scene_hides_the_caustics() -> void:
	_model = Rig.model_with(Table.MEDIUM)
	var catalog: RefCounted = _catalog_with_lamp(null)
	var rooms: Array[Node3D] = []
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void: rooms.append(await _open_room(catalog))
	)
	assert_int(Water.count_of(seen["errors"])).override_failure_message(str(seen)).is_equal(0)
	assert_int(Water.count_of(seen["script_errors"])).is_equal(0)
	assert_int(Water.count_of(seen["warnings"])).is_less_equal(1)
	var node: Node3D = _caustics(rooms[0])
	assert_object(node).override_failure_message("Caustics missing").is_not_null()
	if node != null:
		assert_bool(node.visible).is_false()
		assert_float(Api.call_on(node, "get_effective_intensity", [], Api.MISSING_NUMBER)).is_equal(
			0.0
		)


func test_ac06_a_lamp_scene_without_a_key_light_hides_the_caustics() -> void:
	_model = Rig.model_with(Table.MEDIUM)
	var root: Node3D = Node3D.new()
	root.name = "Lamp"
	var scene: PackedScene = PackedScene.new()
	scene.pack(root)
	root.free()
	var catalog: RefCounted = _catalog_with_lamp(scene)
	var rooms: Array[Node3D] = []
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void: rooms.append(await _open_room(catalog))
	)
	assert_int(Water.count_of(seen["errors"])).override_failure_message(str(seen)).is_equal(0)
	assert_int(Water.count_of(seen["script_errors"])).is_equal(0)
	assert_int(Water.count_of(seen["warnings"])).is_less_equal(1)
	var node: Node3D = _caustics(rooms[0])
	assert_object(node).override_failure_message("Caustics missing").is_not_null()
	if node != null:
		assert_bool(node.visible).is_false()


func test_ac06_intensity_zero_hides_the_caustics_in_the_room_and_back_shows_them() -> void:
	var room: Node3D = await _open_room()
	_caustic.set("caustic_intensity", 0.0)
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void: Api.call_on(_caustic, "apply", [], null)
	)
	assert_int(Water.count_of(seen["errors"])).is_equal(0)
	assert_int(Water.count_of(seen["warnings"])).is_equal(0)
	var node: Node3D = _caustics(room)
	assert_object(node).is_not_null()
	if node == null:
		return
	assert_bool(node.visible).is_false()
	await _change(Table.LARGE)
	(
		assert_bool(_caustics(room).visible)
		. override_failure_message("intensity 0 must survive a swap")
		. is_false()
	)
	_caustic.set("caustic_intensity", 0.4)
	Api.call_on(_caustic, "apply", [], null)
	assert_bool(_caustics(room).visible).is_true()
