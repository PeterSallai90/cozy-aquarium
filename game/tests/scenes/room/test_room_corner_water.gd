# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #23 criteria 4, 10 and 11 (owner: developer for room_corner.gd, technical-artist for the art
## nodes): the water of the displayed tank in the live room, after tank swaps, with missing nodes,
## and the headless load of every tank without shader or material errors.

const Api := preload("res://tests/helpers/late_api.gd")
const Rig := preload("res://tests/helpers/room_rig.gd")
const Table := preload("res://tests/helpers/tank_table.gd")
const Water := preload("res://tests/helpers/water_rig.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")

const MM := 0.001

var _model: AquariumModel = null
var _catalog: RefCounted = null
var _history: CommandHistory = null
var _settings: Resource = null


func before_test() -> void:
	_catalog = Rig.default_catalog()
	_history = CommandHistory.new()
	_model = Rig.model_with(Table.SMALL)
	_settings = Water.settings()


func after_test() -> void:
	Water.restore_rendering_server()


func _open_room() -> Node3D:
	var room: Node3D = Water.room(_model, _catalog, _settings)
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


## One WaterVolume, Surface, Fog (FogVolume) and DepthTint under the displayed Tank, sized for it.
func _assert_one_water(room: Node3D, id: StringName) -> void:
	var tank_node: Node3D = Water.displayed_tank(room)
	assert_object(tank_node).override_failure_message("no Tank for %s" % id).is_not_null()
	if tank_node == null:
		return
	var expected: Vector3 = Water.definition(id).get_water_volume_size_m()
	(
		assert_int(Water.named(tank_node, "WaterVolume").size())
		. override_failure_message("%s: WaterVolume" % id)
		. is_equal(1)
	)
	(
		assert_int(Water.named(tank_node, "Surface").size())
		. override_failure_message("%s: Surface" % id)
		. is_equal(1)
	)
	(
		assert_int(Water.named(tank_node, "DepthTint").size())
		. override_failure_message("%s: DepthTint" % id)
		. is_equal(1)
	)
	(
		assert_int(Water.all_of(tank_node, "FogVolume").size())
		. override_failure_message("%s: FogVolume" % id)
		. is_equal(1)
	)
	var water: Node3D = Water.water_of(tank_node)
	(
		assert_vector(Water.size_of(water))
		. override_failure_message("%s: size for the new tank" % id)
		. is_equal_approx(expected, Vector3.ONE * MM)
	)
	var fogs: Array[Node] = Water.all_of(tank_node, "FogVolume")
	if fogs.size() == 1:
		(
			assert_vector((fogs[0] as FogVolume).size)
			. override_failure_message("%s: fog size" % id)
			. is_equal_approx(expected, Vector3.ONE * MM)
		)


func _connections() -> int:
	return _settings.get_signal_connection_list("applied").size()


# --- AC 4: swaps ---


func test_ac04_the_first_tank_has_one_water_volume_surface_fog_and_depth_tint() -> void:
	var room: Node3D = await _open_room()
	_assert_one_water(room, Table.SMALL)


func test_ac04_small_then_large_then_small_each_show_exactly_one_water() -> void:
	var room: Node3D = await _open_room()
	_assert_one_water(room, Table.SMALL)
	await _change(Table.LARGE)
	_assert_one_water(room, Table.LARGE)
	await _change(Table.SMALL)
	_assert_one_water(room, Table.SMALL)


func test_ac04_the_swaps_raise_no_error_and_no_warning() -> void:
	var rooms: Array[Node3D] = []
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void:
			rooms.append(await _open_room())
			await _change(Table.LARGE)
			await _change(Table.SMALL)
	)
	var room: Node3D = rooms[0]
	assert_int(Water.count_of(seen["errors"])).is_equal(0)
	assert_int(Water.count_of(seen["warnings"])).is_equal(0)
	assert_int(Water.count_of(seen["script_errors"])).is_equal(0)
	_assert_one_water(room, Table.SMALL)


func test_ac04_the_settings_signal_has_two_connections_after_every_swap() -> void:
	# The room and the live TankWater. A third connection would point to a freed tank.
	var room: Node3D = await _open_room()
	assert_int(_connections()).override_failure_message("after load").is_equal(2)
	for id: StringName in [Table.LARGE, Table.SMALL, Table.MEDIUM]:
		await _change(id)
		assert_int(_connections()).override_failure_message("after the swap to %s" % id).is_equal(2)
	assert_object(room).is_not_null()


func test_ac04_the_previous_water_is_freed_with_its_tank() -> void:
	var room: Node3D = await _open_room()
	var old_ids: Array[int] = []
	for node_name: String in ["WaterVolume", "Surface", "DepthTint"]:
		for node: Node in Water.named(Water.displayed_tank(room), node_name):
			old_ids.append(node.get_instance_id())
	for node: Node in Water.all_of(Water.displayed_tank(room), "FogVolume"):
		old_ids.append(node.get_instance_id())
	assert_int(old_ids.size()).is_equal(4)
	await _change(Table.LARGE)
	for old_id: int in old_ids:
		(
			assert_object(instance_from_id(old_id))
			. override_failure_message("a water node of the previous tank was not freed")
			. is_null()
		)


func test_ac04_the_fog_values_survive_a_swap() -> void:
	var room: Node3D = await _open_room()
	_settings.set("density", 0.05)
	Api.call_on(_settings, "apply", [], null)
	await _change(Table.LARGE)
	var fogs: Array[Node] = Water.all_of(Water.displayed_tank(room), "FogVolume")
	assert_int(fogs.size()).is_equal(1)
	if fogs.size() == 1:
		var material: FogMaterial = (fogs[0] as FogVolume).material as FogMaterial
		assert_object(material).is_not_null()
		if material != null:
			assert_float(material.density).is_equal_approx(0.05, 0.0001)


func test_ac04_an_applied_change_reaches_only_the_displayed_tank() -> void:
	var room: Node3D = await _open_room()
	await _change(Table.LARGE)
	_settings.set("density", 0.07)
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void: Api.call_on(_settings, "apply", [], null)
	)
	assert_int(Water.count_of(seen["errors"])).is_equal(0)
	assert_int(Water.count_of(seen["script_errors"])).is_equal(0)
	var fogs: Array[Node] = Water.all_of(Water.displayed_tank(room), "FogVolume")
	assert_int(fogs.size()).is_equal(1)
	if fogs.size() == 1:
		var material: FogMaterial = (fogs[0] as FogVolume).material as FogMaterial
		assert_float(material.density if material != null else -1.0).is_equal_approx(0.07, 0.0001)


# --- AC 10: robustness in the live room ---


func test_ac10_the_room_loads_with_cabinet_and_lamp_around_the_water() -> void:
	var room: Node3D = await _open_room()
	assert_object(Water.displayed_tank(room)).is_not_null()
	assert_object(room.get_node_or_null("Cabinet")).is_not_null()
	assert_object(room.get_node_or_null("Lamp")).is_not_null()


func test_ac10_a_removed_surface_does_not_break_a_swap_or_an_apply() -> void:
	var room: Node3D = await _open_room()
	for node: Node in Water.named(Water.displayed_tank(room), "Surface"):
		node.get_parent().remove_child(node)
		node.free()
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void:
			Api.call_on(_settings, "apply", [], null)
			await _change(Table.LARGE)
	)
	assert_int(Water.count_of(seen["errors"])).is_equal(0)
	assert_int(Water.count_of(seen["script_errors"])).is_equal(0)
	assert_int(Water.count_of(seen["warnings"])).is_less_equal(1)
	_assert_one_water(room, Table.LARGE)


func test_ac10_a_removed_fog_does_not_break_an_apply_or_a_swap() -> void:
	var room: Node3D = await _open_room()
	for node: Node in Water.all_of(Water.displayed_tank(room), "FogVolume"):
		node.get_parent().remove_child(node)
		node.free()
	_settings.set("density", 0.04)
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void:
			Api.call_on(_settings, "apply", [], null)
			await _change(Table.LARGE)
	)
	assert_int(Water.count_of(seen["errors"])).is_equal(0)
	assert_int(Water.count_of(seen["script_errors"])).is_equal(0)
	assert_int(Water.count_of(seen["warnings"])).is_less_equal(1)
	_assert_one_water(room, Table.LARGE)


func test_ac10_glass_and_contents_still_render_without_the_water_nodes() -> void:
	var room: Node3D = await _open_room()
	var tank_node: Node3D = Water.displayed_tank(room)
	var removed: int = 0
	for node_name: String in ["Surface", "DepthTint"]:
		for node: Node in Water.named(tank_node, node_name):
			node.get_parent().remove_child(node)
			node.free()
			removed += 1
	assert_int(removed).override_failure_message("Surface and DepthTint missing").is_equal(2)
	await get_tree().process_frame
	var glass: MeshInstance3D = tank_node.get_node_or_null("Glass") as MeshInstance3D
	assert_object(glass).is_not_null()
	if glass != null:
		assert_bool(glass.is_visible_in_tree()).is_true()
	assert_object(tank_node.get_node_or_null("SubstrateAnchor")).is_not_null()
	assert_object(room.get_node_or_null("Cabinet")).is_not_null()


# --- AC 11: no shader or material errors in the headless load ---


func test_ac11_the_room_loads_each_tank_without_any_engine_output() -> void:
	for id: StringName in Table.IDS:
		_model = Rig.model_with(id)
		_settings = Water.settings()
		var rooms: Array[Node3D] = []
		var seen: Dictionary = await EngineOutput.capture_all(
			func() -> void:
				rooms.append(await _open_room())
				await get_tree().process_frame
		)
		var room: Node3D = rooms[0]
		(
			assert_int(Water.count_of(seen["errors"]))
			. override_failure_message("%s: errors %s" % [id, seen["errors"]])
			. is_equal(0)
		)
		(
			assert_int(Water.count_of(seen["warnings"]))
			. override_failure_message("%s: warnings %s" % [id, seen["warnings"]])
			. is_equal(0)
		)
		(
			assert_int(Water.count_of(seen["script_errors"]))
			. override_failure_message("%s: script errors %s" % [id, seen["script_errors"]])
			. is_equal(0)
		)
		_assert_one_water(room, id)
		room.queue_free()
		await get_tree().process_frame


func test_ac11_every_water_material_has_a_shader_and_no_missing_resource() -> void:
	for path: String in [Water.GLASS_MATERIAL, Water.SURFACE_MATERIAL, Water.DEPTH_TINT_MATERIAL]:
		var material: ShaderMaterial = null
		if ResourceLoader.exists(path):
			material = load(path) as ShaderMaterial
		assert_object(material).override_failure_message("%s missing" % path).is_not_null()
		if material != null:
			(
				assert_object(material.shader)
				. override_failure_message("%s has no shader" % path)
				. is_not_null()
			)
