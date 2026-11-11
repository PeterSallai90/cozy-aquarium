# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #24 criteria 8, 9, 13 (the camera eases to the default view; #25 AC 8 keeps the azimuth) and 19
## (automatic part) (owner: developer): the room reacts to the change-tank Command. The room
## listens to the model (tank_changed, model_reset), swaps tank, cabinet and lamp and frames the
## default view of the new tank. Swapping goes through the real Command and CommandHistory; the
## room never writes the model.

const Api := preload("res://tests/helpers/late_api.gd")
const Rig := preload("res://tests/helpers/room_rig.gd")
const Cam := preload("res://tests/helpers/camera_rig.gd")
const Table := preload("res://tests/helpers/tank_table.gd")
const Factory := preload("res://tests/helpers/factory.gd")
const ModelState := preload("res://tests/helpers/model_state.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")
const SaveFixtures := preload("res://tests/helpers/save_fixtures.gd")

var _model: AquariumModel = null
var _catalog: RefCounted = null
var _history: CommandHistory = null
var _room: Node3D = null


func before_test() -> void:
	_catalog = Rig.default_catalog()
	_history = CommandHistory.new()
	_model = Rig.model_with(Table.MEDIUM)


func _open_room(model: AquariumModel = null) -> Node3D:
	(
		assert_bool(ResourceLoader.exists(Rig.ROOM_SCENE))
		. override_failure_message("room scene missing: %s" % Rig.ROOM_SCENE)
		. is_true()
	)
	var room: Node3D = Rig.instantiate(model if model != null else _model, _catalog)
	add_child(room)
	auto_free(room)
	await get_tree().process_frame
	return room


func _change(id: StringName) -> bool:
	return _history.execute(Api.change_tank(_model, _catalog, id))


func _furnish() -> void:
	_model.apply_set_heightmap(PackedFloat32Array([0.0, 0.2, 0.1, 0.0]), Vector2i(2, 2))
	_model.apply_insert_item(Factory.item("a0000001"), 0)
	_model.apply_insert_item(Factory.item("a0000002", &"plant_fern"), 1)
	_model.apply_insert_fish(Factory.fish("f0000001"), 0)


## Children of the room whose name starts with the prefix (a leaked "Tank2" would count).
func _children_named(room: Node3D, prefix: String) -> Array[Node]:
	var found: Array[Node] = []
	for child: Node in room.get_children():
		if String(child.name).begins_with(prefix):
			found.append(child)
	return found


func _scene_path_of(id: StringName, field: String) -> String:
	var definition: Resource = Rig.definition_of(id)
	var scene: PackedScene = Api.prop(definition, field, null) as PackedScene
	return scene.resource_path if scene != null else "<no %s>" % field


func _assert_displays(room: Node3D, id: StringName) -> void:
	(
		assert_that(Rig.displayed_id(room))
		. override_failure_message("displayed tank is not %s" % id)
		. is_equal(id)
	)
	for pair: Array in [["Tank", "scene"], ["Cabinet", "cabinet_scene"], ["Lamp", "lamp_scene"]]:
		var nodes: Array[Node] = _children_named(room, pair[0])
		(
			assert_int(nodes.size())
			. override_failure_message("%s: %d nodes named %s*" % [id, nodes.size(), pair[0]])
			. is_equal(1)
		)
		if nodes.size() == 1:
			assert_str(String(nodes[0].name)).is_equal(pair[0])
			(
				assert_str(nodes[0].scene_file_path)
				. override_failure_message("%s of %s" % [pair[0], id])
				. is_equal(_scene_path_of(id, pair[1]))
			)


# --- AC 9 ---


func test_ac09_each_tank_in_turn_shows_exactly_one_tank_cabinet_and_lamp() -> void:
	var room: Node3D = await _open_room()
	_assert_displays(room, Table.MEDIUM)
	for id: StringName in [Table.SMALL, Table.LARGE, Table.MEDIUM, Table.SMALL]:
		assert_bool(_change(id)).override_failure_message("change to %s" % id).is_true()
		await get_tree().process_frame
		_assert_displays(room, id)


func test_ac09_the_previous_tank_cabinet_and_lamp_are_freed() -> void:
	var room: Node3D = await _open_room()
	var old_ids: Array[int] = []
	for node_name: String in ["Tank", "Cabinet", "Lamp"]:
		old_ids.append(room.get_node(node_name).get_instance_id())
	assert_bool(_change(Table.LARGE)).is_true()
	await get_tree().process_frame
	await get_tree().process_frame
	for old_id: int in old_ids:
		(
			assert_object(instance_from_id(old_id))
			. override_failure_message("a previous tank, cabinet or lamp node was not freed")
			. is_null()
		)


func test_ac09_repeated_swaps_leave_no_orphan_nodes() -> void:
	var room: Node3D = await _open_room()
	await get_tree().process_frame
	var baseline: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for id: StringName in [Table.SMALL, Table.LARGE, Table.MEDIUM, Table.SMALL, Table.LARGE]:
		_change(id)
		await get_tree().process_frame
	await get_tree().process_frame
	assert_int(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))).is_equal(
		baseline
	)
	assert_that(Rig.displayed_id(room)).is_equal(Table.LARGE)


func test_ac09_a_swap_logs_no_error_and_no_warning_for_every_tank() -> void:
	var room: Node3D = await _open_room()
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void:
			for id: StringName in [Table.SMALL, Table.LARGE, Table.MEDIUM, Table.LARGE]:
				_change(id)
				await get_tree().process_frame
	)
	assert_dict(seen["errors"]).is_empty()
	assert_dict(seen["warnings"]).is_empty()
	assert_that(Rig.displayed_id(room)).is_equal(Table.LARGE)


func test_ac09_the_swap_places_the_new_tank_on_the_cabinet_top_at_once() -> void:
	var room: Node3D = await _open_room()
	_change(Table.LARGE)
	await get_tree().process_frame
	var tank: Node3D = room.get_node("Tank") as Node3D
	assert_float(tank.position.y).is_equal_approx(
		Table.CABINET_TOP_M + Table.glass(Table.LARGE), 0.001
	)
	var mount: Node3D = room.get_node("Tank/lamp_mount") as Node3D
	assert_vector((room.get_node("Lamp") as Node3D).global_position).is_equal_approx(
		mount.global_position, Vector3.ONE * 0.001
	)


func test_ac09_the_room_never_writes_the_model_while_swapping() -> void:
	var room: Node3D = await _open_room()
	var emitted: Array[StringName] = []
	_model.tank_changed.connect(func(id: StringName) -> void: emitted.append(id))
	_change(Table.LARGE)
	await get_tree().process_frame
	# Exactly the one signal of the Command itself, none from the room.
	assert_array(emitted).is_equal([Table.LARGE])
	assert_that(_model.get_tank_id()).is_equal(Table.LARGE)
	assert_that(Rig.displayed_id(room)).is_equal(Table.LARGE)


# --- AC 13: the camera eases to the default view of the new tank ---


func test_ac13_a_tank_change_eases_to_the_default_view_of_the_new_tank() -> void:
	# #25 AC 8 supersedes the reset: the azimuth is kept, so a camera that is still at the front
	# view (azimuth 0, elevation 5) ends at the default view of the new tank once it has settled.
	var fresh: Node3D = await _open_room(Rig.model_with(Table.LARGE))
	var fresh_camera: Camera3D = fresh.get_node("BuildCamera") as Camera3D
	var fresh_pivot: Vector3 = (fresh.get_node("Tank/WaterVolume") as Node3D).global_position
	var room: Node3D = await _open_room()
	var camera: Camera3D = room.get_node("BuildCamera") as Camera3D
	camera.set_process(false)
	assert_bool(_change(Table.LARGE)).is_true()
	await get_tree().process_frame
	Cam.settle(camera)
	var pivot: Vector3 = (room.get_node("Tank/WaterVolume") as Node3D).global_position
	assert_vector(camera.global_position - pivot).is_equal_approx(
		fresh_camera.global_position - fresh_pivot, Vector3.ONE * 0.002
	)
	assert_vector(camera.rotation).is_equal_approx(fresh_camera.rotation, Vector3.ONE * 0.002)


func test_ac13_every_change_re_frames_the_view_of_the_new_tank() -> void:
	var room: Node3D = await _open_room()
	var camera: Camera3D = room.get_node("BuildCamera") as Camera3D
	camera.set_process(false)
	var distances: Dictionary = {}
	for id: StringName in [Table.SMALL, Table.LARGE, Table.MEDIUM]:
		_change(id)
		await get_tree().process_frame
		Cam.settle(camera)
		var pivot: Vector3 = (room.get_node("Tank/WaterVolume") as Node3D).global_position
		distances[id] = camera.global_position.distance_to(pivot)
	# A larger tank is framed from further away.
	assert_float(distances[Table.LARGE]).is_greater(distances[Table.MEDIUM])
	assert_float(distances[Table.MEDIUM]).is_greater(distances[Table.SMALL])


# --- AC 8: save and load ---


func test_ac08_a_saved_and_loaded_model_has_the_chosen_tank_and_the_room_shows_it() -> void:
	var dir: String = SaveFixtures.make_dir("tank_swap_load")
	var path: String = dir.path_join("tank.json")
	var store: SaveStore = SaveStore.new()
	_furnish()
	assert_bool(_change(Table.LARGE)).is_true()
	assert_bool(store.save(_model, path).is_ok()).is_true()
	var loaded: AquariumModel = AquariumModel.new()
	var load_history: CommandHistory = CommandHistory.new()
	assert_bool(store.load_into(path, loaded, load_history).is_ok()).is_true()
	assert_that(loaded.get_tank_id()).is_equal(Table.LARGE)
	var room: Node3D = await _open_room(loaded)
	_assert_displays(room, Table.LARGE)
	assert_bool(load_history.can_undo()).is_false()
	SaveFixtures.remove_dir(dir)
	SaveFixtures.remove_root_if_empty()


func test_ac08_loading_into_a_live_model_swaps_the_room_and_clears_the_undo_history() -> void:
	var dir: String = SaveFixtures.make_dir("tank_swap_load_live")
	var path: String = dir.path_join("tank.json")
	var store: SaveStore = SaveStore.new()
	var room: Node3D = await _open_room()
	assert_bool(_change(Table.LARGE)).is_true()
	assert_bool(store.save(_model, path).is_ok()).is_true()
	assert_bool(_change(Table.SMALL)).is_true()
	await get_tree().process_frame
	_assert_displays(room, Table.SMALL)
	assert_int(_history.get_undo_count()).is_equal(2)
	assert_bool(store.load_into(path, _model, _history).is_ok()).is_true()
	await get_tree().process_frame
	assert_that(_model.get_tank_id()).is_equal(Table.LARGE)
	_assert_displays(room, Table.LARGE)
	# The load clears the session-only history: Undo cannot reapply a tank from another session.
	assert_bool(_history.can_undo()).is_false()
	assert_bool(_history.can_redo()).is_false()
	SaveFixtures.remove_dir(dir)
	SaveFixtures.remove_root_if_empty()


# --- AC 19 (automatic part): furnished tank, change, undo ---


func test_ac19_undo_brings_back_the_previous_tank_items_fish_heightmap_and_the_room_view() -> void:
	var room: Node3D = await _open_room()
	_furnish()
	var before: Dictionary = ModelState.snapshot(_model)
	assert_bool(_change(Table.SMALL)).is_true()
	await get_tree().process_frame
	_assert_displays(room, Table.SMALL)
	assert_int(_model.get_item_count()).is_equal(0)
	assert_bool(_history.undo()).is_true()
	await get_tree().process_frame
	assert_dict(ModelState.snapshot(_model)).is_equal(before)
	_assert_displays(room, Table.MEDIUM)


func test_ac19_redo_shows_the_changed_tank_again() -> void:
	var room: Node3D = await _open_room()
	_furnish()
	_change(Table.LARGE)
	_history.undo()
	await get_tree().process_frame
	assert_bool(_history.redo()).is_true()
	await get_tree().process_frame
	_assert_displays(room, Table.LARGE)
	assert_int(_model.get_item_count()).is_equal(0)


func test_ac19_undo_of_a_change_to_the_same_size_class_sequence_shows_each_earlier_tank() -> void:
	var room: Node3D = await _open_room()
	_change(Table.SMALL)
	_change(Table.LARGE)
	await get_tree().process_frame
	_history.undo()
	await get_tree().process_frame
	_assert_displays(room, Table.SMALL)
	_history.undo()
	await get_tree().process_frame
	_assert_displays(room, Table.MEDIUM)
