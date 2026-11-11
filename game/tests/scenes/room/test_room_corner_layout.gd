# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #22 criteria 7, 10, 11, 12 (key light position) and 15, and #24 criteria 10 and 12, on the
## composed room for each of the three tanks (spans technical-artist and developer files). Room
## space = Node3D local space. The numbers come from the issue table (tank_table.gd), not from the
## catalog; the stand position of cabinet, tank and lamp is not fixed here, only the rules it must
## obey (2.5 cm overhang, 2 to 5 cm back gap, no wall intersection, floor contact).

const Glb := preload("res://tests/helpers/glb_mesh_checks.gd")
const Checks := preload("res://tests/helpers/proof_fish_checks.gd")
const Api := preload("res://tests/helpers/late_api.gd")
const Rig := preload("res://tests/helpers/room_rig.gd")
const Table := preload("res://tests/helpers/tank_table.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")

const MM := 0.001


func _room(id: StringName = Table.MEDIUM) -> Node3D:
	(
		assert_bool(ResourceLoader.exists(Rig.ROOM_SCENE))
		. override_failure_message("room scene missing: %s" % Rig.ROOM_SCENE)
		. is_true()
	)
	var room: Node3D = Rig.instantiate(Rig.model_with(id), Rig.default_catalog())
	add_child(room)
	return auto_free(room)


func _mesh(root: Node, wanted: String) -> MeshInstance3D:
	var instance: MeshInstance3D = Glb.find_mesh(root, wanted)
	assert_object(instance).override_failure_message("mesh %s missing" % wanted).is_not_null()
	return instance


func _room_box(room: Node3D, root_name: String, wanted: String) -> AABB:
	var instance: MeshInstance3D = _mesh(room.get_node(root_name), wanted)
	if instance == null:
		return AABB()
	return Glb.bounds_in(instance, room)


func _tank_box(room: Node3D, root_path: String, wanted: String) -> AABB:
	var instance: MeshInstance3D = _mesh(room.get_node(root_path), wanted)
	if instance == null:
		return AABB()
	return Checks.bounds(Rig.vertices_in_tank(room, instance))


func _rim_y(id: StringName) -> float:
	return Table.interior(id).y + Table.TRIM_M


# --- #22 AC 7 / #24 AC 10: the stand ---


func test_ac10_cabinet_top_height_constant_is_075() -> void:
	assert_float(Api.room_constant("CABINET_TOP_HEIGHT_M")).is_equal_approx(0.75, 0.00001)


func test_ac10_tank_root_sits_at_cabinet_top_plus_glass_thickness_within_1_mm() -> void:
	for id: StringName in Table.IDS:
		var room: Node3D = _room(id)
		var tank: Node3D = room.get_node("Tank") as Node3D
		assert_float(tank.position.y).override_failure_message(id).is_equal_approx(
			Table.CABINET_TOP_M + Table.glass(id), MM
		)
		assert_float(tank.position.x).is_equal_approx(0.0, MM)


func test_ac10_tank_bottom_rests_on_the_cabinet_top() -> void:
	for id: StringName in Table.IDS:
		var room: Node3D = _room(id)
		var cabinet: AABB = Glb.scene_bounds_in(room.get_node("Cabinet") as Node3D, room)
		var glass: AABB = _room_box(room, "Tank", "Glass")
		assert_float(glass.position.y).override_failure_message(id).is_equal_approx(
			cabinet.end.y, MM
		)


func test_ac10_cabinet_top_is_at_the_constant() -> void:
	for id: StringName in Table.IDS:
		var room: Node3D = _room(id)
		var cabinet: AABB = Glb.scene_bounds_in(room.get_node("Cabinet") as Node3D, room)
		assert_float(cabinet.end.y).override_failure_message(id).is_equal_approx(
			Api.room_constant("CABINET_TOP_HEIGHT_M"), MM
		)


func test_ac10_tank_footprint_lies_inside_the_cabinet_footprint() -> void:
	for id: StringName in Table.IDS:
		var room: Node3D = _room(id)
		var cabinet: AABB = Glb.scene_bounds_in(room.get_node("Cabinet") as Node3D, room)
		for wanted: String in ["Glass", "Frame"]:
			var part: AABB = _room_box(room, "Tank", wanted)
			assert_float(part.position.x).is_greater_equal(cabinet.position.x)
			assert_float(part.end.x).is_less_equal(cabinet.end.x)
			assert_float(part.position.z).is_greater_equal(cabinet.position.z)
			assert_float(part.end.z).is_less_equal(cabinet.end.z)


func test_ac10_cabinet_overhangs_the_tank_by_2_5_cm_on_every_side_within_1_mm() -> void:
	for id: StringName in Table.IDS:
		var room: Node3D = _room(id)
		var cabinet: AABB = Glb.scene_bounds_in(room.get_node("Cabinet") as Node3D, room)
		var glass: AABB = _room_box(room, "Tank", "Glass")
		var overhangs: Dictionary = {
			"left": glass.position.x - cabinet.position.x,
			"right": cabinet.end.x - glass.end.x,
			"back": glass.position.z - cabinet.position.z,
			"front": cabinet.end.z - glass.end.z,
		}
		for side: String in overhangs:
			(
				assert_float(overhangs[side])
				. override_failure_message("%s: %s overhang is %s" % [id, side, overhangs[side]])
				. is_equal_approx(Table.CABINET_MARGIN_M, MM)
			)


func test_ac10_cabinet_stands_on_the_floor_surface() -> void:
	for id: StringName in Table.IDS:
		var room: Node3D = _room(id)
		var cabinet: AABB = Glb.scene_bounds_in(room.get_node("Cabinet") as Node3D, room)
		var floor_box: AABB = _room_box(room, "Room", "Floor")
		assert_float(cabinet.position.y).override_failure_message(id).is_equal_approx(
			floor_box.end.y, MM
		)


func test_ac10_gap_between_cabinet_back_and_wall_is_2_to_5_cm() -> void:
	for id: StringName in Table.IDS:
		var room: Node3D = _room(id)
		var cabinet: AABB = Glb.scene_bounds_in(room.get_node("Cabinet") as Node3D, room)
		var wall: AABB = _room_box(room, "Room", "BackWall")
		assert_float(cabinet.position.z - wall.end.z).override_failure_message(id).is_between(
			0.02 - MM, 0.05 + MM
		)


func test_ac10_cabinet_does_not_intersect_the_back_or_the_side_wall() -> void:
	for id: StringName in Table.IDS:
		var room: Node3D = _room(id)
		var cabinet: AABB = Glb.scene_bounds_in(room.get_node("Cabinet") as Node3D, room)
		for wanted: String in ["BackWall", "SideWall"]:
			var part: AABB = _room_box(room, "Room", wanted)
			(
				assert_bool(cabinet.intersects(part))
				. override_failure_message("%s: the cabinet intersects the %s" % [id, wanted])
				. is_false()
			)


func test_ac10_the_side_wall_stays_clear_of_the_cabinet_side() -> void:
	for id: StringName in Table.IDS:
		var room: Node3D = _room(id)
		var cabinet: AABB = Glb.scene_bounds_in(room.get_node("Cabinet") as Node3D, room)
		var wall: AABB = _room_box(room, "Room", "SideWall")
		var gap: float = cabinet.position.x - wall.end.x
		assert_float(gap).override_failure_message("%s: side wall gap %s" % [id, gap]).is_greater(
			0.1
		)


func test_ac10_floor_extends_at_least_10_cm_around_the_cabinet_front_and_sides() -> void:
	for id: StringName in Table.IDS:
		var room: Node3D = _room(id)
		var cabinet: AABB = Glb.scene_bounds_in(room.get_node("Cabinet") as Node3D, room)
		var floor_box: AABB = _room_box(room, "Room", "Floor")
		assert_float(floor_box.position.x).override_failure_message(id).is_less_equal(
			cabinet.position.x - 0.1
		)
		assert_float(floor_box.end.x).override_failure_message(id).is_greater_equal(
			cabinet.end.x + 0.1
		)
		assert_float(floor_box.end.z).override_failure_message(id).is_greater_equal(
			cabinet.end.z + 0.1
		)


func test_ac10_nothing_is_below_the_floor_slab_and_only_the_slab_below_the_floor_surface() -> void:
	for id: StringName in Table.IDS:
		var room: Node3D = _room(id)
		var floor_box: AABB = _room_box(room, "Room", "Floor")
		assert_float(floor_box.size.y).is_greater_equal(0.01)
		for instance: MeshInstance3D in Glb.mesh_instances(room):
			var box: AABB = Glb.bounds_in(instance, room)
			assert_float(box.position.y).is_greater_equal(floor_box.position.y - MM)
			if instance.name != &"Floor":
				(
					assert_float(box.position.y)
					. override_failure_message(
						"%s: %s reaches below the floor surface" % [id, instance.name]
					)
					. is_greater_equal(floor_box.end.y - MM)
				)


func test_main_scene_instances_the_room_corner() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	var main: Node = scene.instantiate()
	var corner: Node = main.get_node_or_null("RoomCorner")
	assert_object(corner).is_not_null()
	if corner != null:
		assert_str(corner.scene_file_path).is_equal("res://scenes/room/room_corner.tscn")
	main.free()


# --- the lamp in tank space (#22 AC 10, #24 AC 12) ---


func test_ac12_lamp_nodes_exist_under_the_lamp_root() -> void:
	for id: StringName in Table.IDS:
		var room: Node3D = _room(id)
		assert_object(room.get_node_or_null("Lamp/lamp")).is_instanceof(MeshInstance3D)
		assert_object(room.get_node_or_null("Lamp/lamp_brackets")).is_instanceof(MeshInstance3D)
		assert_object(room.get_node_or_null("Tank/lamp_mount")).is_instanceof(Marker3D)


func test_ac12_lamp_is_placed_at_the_lamp_mount() -> void:
	for id: StringName in Table.IDS:
		var room: Node3D = _room(id)
		var mount: Node3D = room.get_node("Tank/lamp_mount") as Node3D
		var lamp: Node3D = room.get_node("Lamp") as Node3D
		assert_vector(lamp.global_position).override_failure_message(id).is_equal_approx(
			mount.global_position, Vector3.ONE * MM
		)


func test_ac12_bar_is_the_exterior_length_minus_3_cm_by_6_cm_at_or_above_the_trim_top() -> void:
	for id: StringName in Table.IDS:
		var room: Node3D = _room(id)
		var bar: AABB = _tank_box(room, "Lamp", "lamp")
		assert_float(bar.size.x).override_failure_message("%s bar length" % id).is_equal_approx(
			Table.lamp_bar_length(id), MM
		)
		assert_float(bar.size.z).is_equal_approx(Table.LAMP_DEPTH_M, MM)
		assert_float(bar.position.y).override_failure_message(id).is_greater_equal(_rim_y(id) - MM)


func test_ac12_bar_has_no_front_skirt_it_stays_within_the_tank_depth() -> void:
	for id: StringName in Table.IDS:
		var room: Node3D = _room(id)
		var whole: AABB = Glb.scene_bounds_in(room.get_node("Lamp") as Node3D, room)
		assert_float(whole.size.z).is_less_equal(Table.LAMP_DEPTH_M + MM)


func test_ac12_brackets_rest_on_the_trim_top() -> void:
	for id: StringName in Table.IDS:
		var room: Node3D = _room(id)
		var brackets: AABB = _tank_box(room, "Lamp", "lamp_brackets")
		var outer_x: float = Table.exterior(id).x / 2.0
		assert_float(brackets.position.y).override_failure_message(id).is_equal_approx(
			_rim_y(id), MM
		)
		assert_float(brackets.end.x).is_less_equal(outer_x + MM)
		assert_float(brackets.position.x).is_greater_equal(-outer_x - MM)


func test_ac12_rays_from_the_camera_to_the_water_line_grid_miss_the_lamp() -> void:
	for id: StringName in Table.IDS:
		var room: Node3D = _room(id)
		var tank: Node3D = room.get_node("Tank") as Node3D
		var camera: Camera3D = room.get_node("BuildCamera") as Camera3D
		var boxes: Array[AABB] = [
			_room_box(room, "Lamp", "lamp"),
			_room_box(room, "Lamp", "lamp_brackets"),
		]
		var half_x: float = Table.interior(id).x / 2.0
		var half_z: float = Table.interior(id).z / 2.0
		var hits: int = 0
		for column: int in 3:
			for row: int in 3:
				var local: Vector3 = Vector3(
					(column - 1) * half_x, Table.water_line(id), (row - 1) * half_z
				)
				var target: Vector3 = tank.transform * local
				for box: AABB in boxes:
					if box.intersects_segment(camera.global_position, target):
						hits += 1
		assert_int(hits).override_failure_message("%s: %d rays hit the lamp" % [id, hits]).is_equal(
			0
		)


func test_ac12_key_light_is_inside_the_tank_footprint_and_above_the_trim() -> void:
	for id: StringName in Table.IDS:
		var room: Node3D = _room(id)
		var tank: Node3D = room.get_node("Tank") as Node3D
		var light: SpotLight3D = room.get_node("Lamp/KeyLight") as SpotLight3D
		var local: Vector3 = tank.transform.affine_inverse() * light.global_position
		assert_float(absf(local.x)).is_less_equal(Table.exterior(id).x / 2.0)
		assert_float(absf(local.z)).is_less_equal(Table.interior(id).z / 2.0 + 0.06)
		assert_float(local.y).override_failure_message(id).is_greater_equal(_rim_y(id) - MM)


# --- #22 AC 15 (medium; the hide roots are the same for every tank) ---


func _hide_and_check(root_name: String) -> void:
	var room: Node3D = _room()
	var tank: Node3D = room.get_node("Tank") as Node3D
	var before: Transform3D = tank.transform
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void: (room.get_node(root_name) as Node3D).visible = false
	)
	assert_dict(seen["errors"]).is_empty()
	assert_dict(seen["warnings"]).is_empty()
	assert_bool(tank.transform.is_equal_approx(before)).is_true()
	assert_bool(tank.is_visible_in_tree()).is_true()
	assert_bool((room.get_node(root_name) as Node3D).is_visible_in_tree()).is_false()
	var light: SpotLight3D = room.get_node("Lamp/KeyLight") as SpotLight3D
	assert_bool(light.is_visible_in_tree()).is_equal(root_name != "Lamp")


func test_ac15_hiding_room_keeps_the_tank_and_the_key_light() -> void:
	await _hide_and_check("Room")


func test_ac15_hiding_cabinet_keeps_the_tank_and_the_key_light() -> void:
	await _hide_and_check("Cabinet")


func test_ac15_hiding_lamp_hides_the_lamp_and_its_light_but_not_the_tank() -> void:
	await _hide_and_check("Lamp")


func test_ac15_hiding_lamp_hides_the_bar_and_brackets() -> void:
	var room: Node3D = _room()
	(room.get_node("Lamp") as Node3D).visible = false
	assert_bool((room.get_node("Lamp/lamp") as Node3D).is_visible_in_tree()).is_false()
	assert_bool((room.get_node("Lamp/lamp_brackets") as Node3D).is_visible_in_tree()).is_false()


func test_ac15_the_camera_is_not_under_a_hideable_root() -> void:
	var room: Node3D = _room()
	var camera: Node = room.get_node("BuildCamera")
	assert_object(camera.get_parent()).is_same(room)
	for root_name: String in ["Room", "Cabinet", "Lamp"]:
		assert_bool(room.get_node(root_name).is_ancestor_of(camera)).is_false()


func test_ac15_hiding_all_three_roots_leaves_the_tank_visible() -> void:
	var room: Node3D = _room()
	for root_name: String in ["Room", "Cabinet", "Lamp"]:
		(room.get_node(root_name) as Node3D).visible = false
	assert_bool((room.get_node("Tank") as Node3D).is_visible_in_tree()).is_true()
