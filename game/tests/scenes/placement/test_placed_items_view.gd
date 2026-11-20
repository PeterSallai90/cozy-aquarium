# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #31 AC 1 to 4, 12 (scene part), 33 (counts) and 39 (the mark) (owner: developer, with the
## selection material of the technical-artist): the drawn items of RoomCorner/Placement/PlacedItems.
## One node per uid from ItemDefinition.scene at the model transform (x and z tank-local, y on the
## nominal substrate surface, rotation_y degrees around +Y with 0 facing +Z, scale); exactly the
## affected node is created, freed or updated on item_added, item_removed and item_changed;
## substrate_changed moves every item with the new surface and leaves the model alone; model_reset
## rebuilds all in one pass; an unknown catalog_id or a definition without a scene draws nothing
## and logs nothing. The mark is the selection material as material_overlay on the meshes of the
## selected drawn node.
## Test decisions where the plan is silent: item_changed updates the existing node in place (same
## instance, no new creation); hit entries are Dictionaries {"transform", "aabb"} in tank-local
## space, one per drawn item in model order; the 100-item guard builds a 10 x 10 grid inside the
## medium tank.

const Rig := preload("res://tests/helpers/placement_rig.gd")
const Session := preload("res://tests/helpers/placement_session.gd")
const Api := preload("res://tests/helpers/placement_api.gd")
const Factory := preload("res://tests/helpers/factory.gd")
const LateApi := preload("res://tests/helpers/late_api.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")

const SELECTION_MATERIAL := "res://scenes/tank/items/item_selection_material.tres"
const ANGLE_TOLERANCE := 0.05

var _s: Session = null


func after_test() -> void:
	Rig.close(_s)


func _open(model: AquariumModel = null) -> bool:
	_s = await Rig.open(self, model)
	var complete: bool = _s.placement != null and _s.view != null and _s.ghost != null
	(
		assert_bool(complete)
		. override_failure_message(
			"RoomCorner needs a Placement child with the children PlacedItems and Ghost"
		)
		. is_true()
	)
	return complete


func _trio() -> AquariumModel:
	var model: AquariumModel = Rig.model()
	Rig.add_item(model, "a0000001", Rig.STONE, 0.1, 0.05, 0.0)
	Rig.add_item(model, "a0000002", Rig.BRANCH, -0.2, -0.05, 90.0)
	Rig.add_item(model, "a0000003", Rig.AMPHORA, 0.0, 0.1, 37.5)
	return model


func _geometry(node: Node) -> Array[GeometryInstance3D]:
	var found: Array[GeometryInstance3D] = []
	for child: Node in node.find_children("*", "GeometryInstance3D", true, false):
		found.append(child as GeometryInstance3D)
	return found


func _overlays(node: Node) -> int:
	var count: int = 0
	for instance: GeometryInstance3D in _geometry(node):
		if instance.material_overlay != null:
			count += 1
	return count


# --- structure ---


func test_ac01_placement_is_a_persistent_child_of_the_room_in_the_tank_frame() -> void:
	if not await _open(_trio()):
		return
	var placement: Node = _s.placement
	assert_object(placement.get_parent()).is_same(_s.room)
	var tank: Node3D = _s.room.get_node("Tank") as Node3D
	assert_vector(placement.global_position).is_equal_approx(
		tank.global_position, Vector3(0.0001, 0.0001, 0.0001)
	)
	var before_id: int = placement.get_instance_id()
	var catalog: TankCatalog = TankCatalog.load_dir()
	var swap: Command = LateApi.change_tank(_s.model, catalog, &"tank_large_1")
	assert_bool(_s.history.execute(swap)).is_true()
	await _s.frame()
	assert_int(_s.room.get_node("Placement").get_instance_id()).is_equal(before_id)
	var new_tank: Node3D = _s.room.get_node("Tank") as Node3D
	assert_vector(placement.global_position).is_equal_approx(
		new_tank.global_position, Vector3(0.0001, 0.0001, 0.0001)
	)


# --- AC 1 ---


func test_ac01_every_item_is_drawn_at_its_model_transform() -> void:
	var model: AquariumModel = _trio()
	var scaled: PlacedItem = Factory.item("a0000004", Rig.STONE, Vector3(0.2, 0.0, 0.0), 0.0, 1.5)
	model.apply_insert_item(scaled, model.get_item_count())
	if not await _open(model):
		return
	assert_int(_s.drawn_count()).is_equal(4)
	for item: PlacedItem in model.get_items():
		var node: Node3D = _s.node_for(item.uid)
		assert_object(node).override_failure_message("no node for %s" % item.uid).is_not_null()
		if node == null:
			continue
		var local: Vector3 = _s.local_position(node)
		assert_vector(local).is_equal_approx(
			Vector3(item.position.x, 0.0, item.position.z), Vector3(0.0005, 0.0005, 0.0005)
		)
		var gap: float = absf(wrapf(_s.yaw_of(node) - item.rotation_y, -180.0, 180.0))
		assert_float(gap).is_less(ANGLE_TOLERANCE)
		var node_scale: Vector3 = node.global_transform.basis.get_scale()
		assert_float(node_scale.x).is_equal_approx(item.scale, 0.001)
		assert_float(node_scale.y).is_equal_approx(item.scale, 0.001)


func test_ac01_the_drawn_node_is_the_scene_of_the_catalog_definition() -> void:
	if not await _open(_trio()):
		return
	var node: Node3D = _s.node_for("a0000001")
	var definition: ItemDefinition = _s.items.get_definition(Rig.STONE)
	assert_str(node.scene_file_path).is_equal(definition.scene.resource_path)


func test_ac01_the_item_stands_on_the_substrate_surface() -> void:
	if not await _open(_trio()):
		return
	var node: Node3D = _s.node_for("a0000001")
	var local_bottom: float = _s.placement.to_local(node.global_position).y
	assert_float(local_bottom).is_equal_approx(_s.depth(), 0.0005)


func test_ac12_zero_degrees_faces_front_and_90_turns_the_front_toward_plus_x() -> void:
	var model: AquariumModel = Rig.model()
	Rig.add_item(model, "a0000001", Rig.BRANCH, 0.0, 0.0, 0.0)
	Rig.add_item(model, "a0000002", Rig.BRANCH, 0.1, 0.0, 90.0)
	if not await _open(model):
		return
	var basis: Basis = _s.placement.global_transform.basis.inverse()
	var front: Vector3 = basis * _s.node_for("a0000001").global_transform.basis.z
	var turned: Vector3 = basis * _s.node_for("a0000002").global_transform.basis.z
	assert_float(front.dot(Vector3.BACK)).is_greater(0.999)
	assert_float(turned.dot(Vector3.RIGHT)).is_greater(0.999)


func test_ac01_adding_one_item_creates_exactly_one_node_and_touches_no_other() -> void:
	var model: AquariumModel = Rig.model()
	Rig.add_item(model, "a0000001", Rig.STONE, 0.1, 0.05)
	Rig.add_item(model, "a0000002", Rig.BRANCH, -0.2, -0.05, 90.0)
	if not await _open(model):
		return
	var first: Node3D = _s.node_for("a0000001")
	var second: Node3D = _s.node_for("a0000002")
	var first_transform: Transform3D = first.global_transform
	var created: int = _s.created_count()
	Rig.add_item(model, "a0000003", Rig.AMPHORA, 0.0, 0.1)
	await _s.frame()
	assert_int(_s.created_count()).is_equal(created + 1)
	assert_int(_s.drawn_count()).is_equal(3)
	assert_object(_s.node_for("a0000001")).is_same(first)
	assert_object(_s.node_for("a0000002")).is_same(second)
	assert_object(_s.node_for("a0000003")).is_not_null()
	assert_bool(first.global_transform.is_equal_approx(first_transform)).is_true()


func test_ac01_removing_one_item_frees_exactly_that_node() -> void:
	var model: AquariumModel = _trio()
	if not await _open(model):
		return
	var removed: Node3D = _s.node_for("a0000002")
	var kept: Node3D = _s.node_for("a0000001")
	var created: int = _s.created_count()
	model.apply_remove_item("a0000002")
	await _s.frame()
	await _s.frame()
	assert_bool(is_instance_valid(removed) and removed.is_inside_tree()).is_false()
	assert_int(_s.drawn_count()).is_equal(2)
	assert_object(_s.node_for("a0000002")).is_null()
	assert_object(_s.node_for("a0000001")).is_same(kept)
	assert_int(_s.created_count()).is_equal(created)


func test_ac01_replacing_one_item_updates_that_node_and_touches_no_other() -> void:
	var model: AquariumModel = _trio()
	if not await _open(model):
		return
	var changed: Node3D = _s.node_for("a0000002")
	var other: Node3D = _s.node_for("a0000001")
	var other_transform: Transform3D = other.global_transform
	var created: int = _s.created_count()
	var moved: PlacedItem = model.get_item("a0000002").copy()
	moved.position = Vector3(0.15, 0.0, 0.1)
	moved.rotation_y = 45.0
	model.apply_replace_item(moved)
	await _s.frame()
	assert_object(_s.node_for("a0000002")).is_same(changed)
	assert_int(_s.created_count()).is_equal(created)
	assert_vector(_s.local_position(changed)).is_equal_approx(
		Vector3(0.15, 0.0, 0.1), Vector3(0.0005, 0.0005, 0.0005)
	)
	assert_float(absf(wrapf(_s.yaw_of(changed) - 45.0, -180.0, 180.0))).is_less(ANGLE_TOLERANCE)
	assert_bool(other.global_transform.is_equal_approx(other_transform)).is_true()


# --- AC 2 ---


func test_ac02_a_deeper_substrate_lifts_every_item_and_the_model_stays() -> void:
	var model: AquariumModel = _trio()
	if not await _open(model):
		return
	var sand_depth: float = _s.depth()
	model.apply_set_substrate(Rig.PEBBLES, Rig.CREAM)
	await _s.frame()
	var pebble_depth: float = _s.depth()
	assert_float(pebble_depth).is_greater(sand_depth)
	for item: PlacedItem in model.get_items():
		var node: Node3D = _s.node_for(item.uid)
		var height: float = _s.placement.to_local(node.global_position).y
		assert_float(height).is_equal_approx(pebble_depth, 0.0005)
		assert_float(item.position.y).is_equal(0.0)


# --- AC 3 ---


func test_ac03_model_reset_rebuilds_the_drawn_items_from_the_new_model() -> void:
	var model: AquariumModel = _trio()
	if not await _open(model):
		return
	var old_node: Node3D = _s.node_for("a0000001")
	var other: AquariumModel = Rig.model()
	Rig.add_item(other, "b0000001", Rig.AMPHORA, -0.1, 0.0, 15.0)
	Rig.add_item(other, "b0000002", Rig.STONE, 0.2, 0.1, 200.0)
	model.reset_from(other)
	await _s.frame()
	await _s.frame()
	assert_int(_s.drawn_count()).is_equal(2)
	assert_object(_s.node_for("a0000001")).is_null()
	assert_bool(is_instance_valid(old_node) and old_node.is_inside_tree()).is_false()
	var node: Node3D = _s.node_for("b0000002")
	assert_object(node).is_not_null()
	if node != null:
		assert_float(absf(wrapf(_s.yaw_of(node) - 200.0, -180.0, 180.0))).is_less(ANGLE_TOLERANCE)


func test_ac03_a_tank_swap_removes_the_drawn_items_and_its_undo_brings_them_back() -> void:
	var model: AquariumModel = _trio()
	if not await _open(model):
		return
	var expected: Dictionary = {}
	for item: PlacedItem in model.get_items():
		var node: Node3D = _s.node_for(item.uid)
		expected[item.uid] = [_s.local_position(node), _s.yaw_of(node)]
	var catalog: TankCatalog = TankCatalog.load_dir()
	var swap: Command = LateApi.change_tank(model, catalog, &"tank_large_1")
	assert_bool(_s.history.execute(swap)).is_true()
	await _s.frame()
	await _s.frame()
	assert_int(model.get_item_count()).is_equal(0)
	assert_int(_s.drawn_count()).is_equal(0)
	assert_bool(_s.history.undo()).is_true()
	await _s.frame()
	await _s.frame()
	assert_int(_s.drawn_count()).is_equal(3)
	for uid: String in expected:
		var node: Node3D = _s.node_for(uid)
		assert_object(node).override_failure_message("no node for %s" % uid).is_not_null()
		if node == null:
			continue
		var pair: Array = expected[uid]
		assert_vector(_s.local_position(node)).is_equal_approx(
			pair[0] as Vector3, Vector3(0.0005, 0.0005, 0.0005)
		)
		assert_float(absf(wrapf(_s.yaw_of(node) - float(pair[1]), -180.0, 180.0))).is_less(
			ANGLE_TOLERANCE
		)


# --- AC 4 ---


func test_ac04_an_unknown_id_and_a_definition_without_a_scene_draw_nothing_and_log_nothing(
) -> void:
	var model: AquariumModel = Rig.model()
	if not await _open(model):
		return
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void:
			Rig.add_item(model, "a0000001", Rig.UNKNOWN, 0.0, 0.0)
			Rig.add_item(model, "a0000002", Rig.SCENELESS, 0.1, 0.0)
			await _s.frame()
			await _s.frame()
			model.apply_remove_item("a0000002")
			await _s.frame()
	)
	assert_dict(seen["errors"]).is_empty()
	assert_dict(seen["warnings"]).is_empty()
	assert_dict(seen["script_errors"]).is_empty()
	assert_int(_s.drawn_count()).is_equal(0)
	assert_object(_s.node_for("a0000001")).is_null()
	assert_int(model.get_item_count()).is_equal(1)
	assert_that(model.get_item("a0000001").catalog_id).is_equal(Rig.UNKNOWN)


func test_ac04_unknown_items_at_the_start_and_after_a_reset_draw_nothing_and_log_nothing() -> void:
	var model: AquariumModel = Rig.model()
	Rig.add_item(model, "a0000001", Rig.UNKNOWN, 0.0, 0.0)
	Rig.add_item(model, "a0000002", Rig.STONE, 0.1, 0.0)
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void:
			_s = await Rig.open(self, model)
			await _s.frame()
	)
	assert_dict(seen["errors"]).is_empty()
	assert_dict(seen["warnings"]).is_empty()
	assert_dict(seen["script_errors"]).is_empty()
	if _s.placement == null:
		assert_bool(false).override_failure_message("RoomCorner has no Placement child").is_true()
		return
	assert_int(_s.drawn_count()).is_equal(1)
	assert_object(_s.node_for("a0000002")).is_not_null()


# --- AC 33: counts ---


func _grid(count: int) -> AquariumModel:
	var model: AquariumModel = Rig.model()
	var ids: Array[StringName] = [Rig.STONE, Rig.BRANCH, Rig.AMPHORA]
	for index: int in count:
		var column: int = index % 10
		var row: int = floori(index / 10.0)
		Rig.add_item(
			model,
			"c%07d" % index,
			ids[index % 3],
			-0.27 + 0.06 * column,
			-0.135 + 0.03 * row,
			float(index * 7 % 360)
		)
	return model


func test_ac33_a_reset_with_100_items_builds_100_nodes_once() -> void:
	if not await _open(Rig.model()):
		return
	assert_int(_s.created_count()).is_equal(0)
	_s.model.reset_from(_grid(100))
	await _s.frame()
	await _s.frame()
	assert_int(_s.drawn_count()).is_equal(100)
	assert_int(_s.created_count()).is_equal(100)


func test_ac33_one_placement_creates_one_node_and_rebuilds_none_of_the_others() -> void:
	if not await _open(Rig.model()):
		return
	_s.model.reset_from(_grid(100))
	await _s.frame()
	var ids: Dictionary = {}
	for item: PlacedItem in _s.model.get_items():
		ids[item.uid] = _s.node_for(item.uid).get_instance_id()
	Rig.add_item(_s.model, "d0000001", Rig.STONE, 0.0, 0.0)
	await _s.frame()
	assert_int(_s.created_count()).is_equal(101)
	assert_int(_s.drawn_count()).is_equal(101)
	for uid: String in ids:
		assert_int(_s.node_for(uid).get_instance_id()).is_equal(int(ids[uid]))


func test_ac33_a_substrate_change_moves_nodes_and_creates_none() -> void:
	if not await _open(Rig.model()):
		return
	_s.model.reset_from(_grid(100))
	await _s.frame()
	_s.model.apply_set_substrate(Rig.PEBBLES, Rig.CREAM)
	await _s.frame()
	assert_int(_s.created_count()).is_equal(100)


func test_ac33_pointer_moves_with_a_ghost_create_free_or_move_no_placed_item() -> void:
	if not await _open(Rig.model()):
		return
	_s.model.reset_from(_grid(100))
	await _s.frame()
	var ids: Dictionary = {}
	var transforms: Dictionary = {}
	for item: PlacedItem in _s.model.get_items():
		var node: Node3D = _s.node_for(item.uid)
		ids[item.uid] = node.get_instance_id()
		transforms[item.uid] = node.global_transform
	_s.pick(Rig.STONE)
	for index: int in 20:
		_s.move(_s.screen_of(-0.25 + 0.025 * index, 0.01 * index - 0.1))
	assert_int(_s.created_count()).is_equal(100)
	assert_int(_s.drawn_count()).is_equal(100)
	for uid: String in ids:
		var node: Node3D = _s.node_for(uid)
		assert_int(node.get_instance_id()).is_equal(int(ids[uid]))
		assert_bool(node.global_transform.is_equal_approx(transforms[uid])).is_true()


# --- hit entries and AC 39 ---


func test_ac39_the_hit_entries_are_the_items_in_tank_local_space_and_nothing_else() -> void:
	if not await _open(_trio()):
		return
	_s.pick(Rig.STONE)
	_s.move(_s.screen_of(0.0, 0.0))
	_s.step(0.0)
	var entries: Array = Api.call_on(_s.view, "get_hit_entries", [], [])
	assert_int(entries.size()).is_equal(3)
	if entries.size() != 3:
		return
	for index: int in 3:
		var item: PlacedItem = _s.model.get_item_at(index)
		var entry: Dictionary = entries[index]
		var transform: Transform3D = entry["transform"]
		var box: AABB = entry["aabb"]
		assert_vector(transform.origin).is_equal_approx(
			Vector3(item.position.x, _s.depth(), item.position.z), Vector3(0.0005, 0.0005, 0.0005)
		)
		assert_float(box.size.x).is_greater(0.01)
		assert_float(box.position.y).is_equal_approx(0.0, 0.001)


func test_ac39_the_mark_is_the_selection_material_on_the_meshes_of_the_selected_node_only() -> void:
	if not await _open(_trio()):
		return
	var count: int = _s.drawn_count()
	var hits: int = (Api.call_on(_s.view, "get_hit_entries", [], []) as Array).size()
	_s.view.call("set_selected", "a0000002")
	var marked: Node3D = _s.node_for("a0000002")
	var meshes: Array[GeometryInstance3D] = _geometry(marked)
	assert_int(meshes.size()).is_greater(0)
	for instance: GeometryInstance3D in meshes:
		assert_object(instance.material_overlay).is_not_null()
		assert_str(instance.material_overlay.resource_path).is_equal(SELECTION_MATERIAL)
	assert_int(_overlays(_s.node_for("a0000001"))).is_equal(0)
	assert_int(_overlays(_s.node_for("a0000003"))).is_equal(0)
	assert_int(_s.drawn_count()).is_equal(count)
	assert_int((Api.call_on(_s.view, "get_hit_entries", [], []) as Array).size()).is_equal(hits)
	_s.view.call("set_selected", "")
	assert_int(_overlays(marked)).is_equal(0)


func test_ac39_the_mark_moves_with_the_item_on_a_model_change_and_a_substrate_change() -> void:
	var model: AquariumModel = _trio()
	if not await _open(model):
		return
	_s.view.call("set_selected", "a0000001")
	var node: Node3D = _s.node_for("a0000001")
	var turned: PlacedItem = model.get_item("a0000001").copy()
	turned.rotation_y = 60.0
	model.apply_replace_item(turned)
	await _s.frame()
	assert_object(_s.node_for("a0000001")).is_same(node)
	assert_int(_overlays(node)).is_greater(0)
	assert_float(absf(wrapf(_s.yaw_of(node) - 60.0, -180.0, 180.0))).is_less(ANGLE_TOLERANCE)
	model.apply_set_substrate(Rig.PEBBLES, Rig.CREAM)
	await _s.frame()
	assert_int(_overlays(node)).is_greater(0)
	assert_float(_s.placement.to_local(node.global_position).y).is_equal_approx(_s.depth(), 0.0005)


func test_ac39_a_pending_rotation_turns_the_node_and_its_mark_without_the_model() -> void:
	var model: AquariumModel = _trio()
	if not await _open(model):
		return
	_s.view.call("set_selected", "a0000001")
	var node: Node3D = _s.node_for("a0000001")
	_s.view.call("show_pending_rotation", "a0000001", 90.0)
	assert_float(absf(wrapf(_s.yaw_of(node) - 90.0, -180.0, 180.0))).is_less(ANGLE_TOLERANCE)
	assert_int(_overlays(node)).is_greater(0)
	assert_float(model.get_item("a0000001").rotation_y).is_equal(0.0)
	_s.view.call("clear_pending", "a0000001")
	assert_float(absf(wrapf(_s.yaw_of(node) - 0.0, -180.0, 180.0))).is_less(ANGLE_TOLERANCE)
	assert_int(_overlays(node)).is_greater(0)


func test_ac39_hiding_the_feedback_hides_the_mark_and_showing_it_brings_it_back() -> void:
	if not await _open(_trio()):
		return
	_s.view.call("set_selected", "a0000001")
	var node: Node3D = _s.node_for("a0000001")
	_s.view.call("set_feedback_visible", false)
	assert_int(_overlays(node)).is_equal(0)
	_s.view.call("set_feedback_visible", true)
	assert_int(_overlays(node)).is_greater(0)
