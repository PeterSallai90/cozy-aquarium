extends GdUnitTestSuite
## #34 plan section 2 (owner: developer): the room hosts FishView as a persistent `Fish` child next
## to `Placement`, in the tank frame (moved to the tank's global transform, hidden with no tank),
## set up with the session model and catalogs. It survives a tank change as the same node, draws
## the fish of the model, and an empty model draws nothing and logs nothing.

const Api := preload("res://tests/helpers/fish_api.gd")
const FishRig := preload("res://tests/helpers/fish_view_rig.gd")
const RoomRig := preload("res://tests/helpers/room_rig.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")


func _room(model: AquariumModel) -> Node3D:
	var room: Node3D = RoomRig.instantiate(model, RoomRig.default_catalog())
	add_child(room)
	auto_free(room)
	await get_tree().process_frame
	await get_tree().process_frame
	return room


func _fish_view(room: Node3D) -> Node3D:
	var view: Node3D = room.get_node_or_null("Fish") as Node3D
	(
		assert_object(view)
		. override_failure_message("RoomCorner needs a persistent child named Fish (FishView)")
		. is_not_null()
	)
	return view


func test_the_room_has_a_fish_child_with_the_fish_view_script_next_to_placement() -> void:
	var room: Node3D = await _room(FishRig.trio())
	var view: Node3D = _fish_view(room)
	if view == null:
		return
	var script: Script = view.get_script() as Script
	assert_object(script).is_not_null()
	if script != null:
		assert_str(script.resource_path).is_equal(Api.VIEW_PATH)
	assert_object(view.get_parent()).is_same(room)
	assert_object(room.get_node_or_null("Placement")).is_not_null()


func test_the_fish_child_draws_the_fish_of_the_model_in_the_tank_frame() -> void:
	var room: Node3D = await _room(FishRig.trio())
	var view: Node3D = _fish_view(room)
	if view == null:
		return
	var tank: Node3D = room.get_node("Tank") as Node3D
	assert_vector(view.global_position).is_equal_approx(tank.global_position, Vector3.ONE * 0.0001)
	assert_int(view.get_child_count()).is_equal(3)
	assert_bool(view.visible).is_true()


func test_the_fish_child_is_the_same_node_after_a_tank_change_and_follows_the_tank() -> void:
	var model: AquariumModel = FishRig.trio()
	var room: Node3D = await _room(model)
	var view: Node3D = _fish_view(room)
	if view == null:
		return
	var id_before: int = view.get_instance_id()
	model.apply_set_tank_id(FishRig.LARGE)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(room.get_node("Fish").get_instance_id()).is_equal(id_before)
	var tank: Node3D = room.get_node("Tank") as Node3D
	assert_vector(view.global_position).is_equal_approx(tank.global_position, Vector3.ONE * 0.0001)
	assert_int(view.get_child_count()).is_equal(3)


func test_an_empty_model_draws_no_fish_and_logs_nothing() -> void:
	var holder: Array = []
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void: holder.append(await _room(FishRig.model()))
	)
	var view: Node3D = _fish_view(holder[0])
	if view == null:
		return
	assert_int(view.get_child_count()).is_equal(0)
	assert_dict(seen["warnings"]).is_empty()
	assert_dict(seen["errors"]).is_empty()
