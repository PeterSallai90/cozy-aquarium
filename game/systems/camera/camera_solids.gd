class_name CameraSolids
extends RefCounted
## Builds the solids the build camera keeps out of, and the box the pivot may move in (ADR 0009).
## Boxes are in the room frame. Reads only sizes of the tank definition, never Mode 2 fields.


## The tank exterior from the cabinet top to the rim top; a zero box without volume.
static func tank_box(definition: TankDefinition, cabinet_top_y: float, stand_z: float) -> AABB:
	if definition == null or not _has_volume(definition.interior_size_m):
		return AABB()
	var outer: Vector3 = definition.get_exterior_size_m()
	var height: float = (
		definition.glass_thickness_m + definition.interior_size_m.y + definition.trim_size_m
	)
	return _centred(outer.x, outer.z, stand_z, cabinet_top_y, height)


## The cabinet: exterior footprint plus the margin, from the floor to the cabinet top.
static func cabinet_box(
	definition: TankDefinition, cabinet_top_y: float, cabinet_margin_m: float, stand_z: float
) -> AABB:
	if definition == null:
		return AABB()
	var outer: Vector3 = definition.get_exterior_size_m()
	return _centred(
		outer.x + 2.0 * cabinet_margin_m,
		outer.z + 2.0 * cabinet_margin_m,
		stand_z,
		0.0,
		cabinet_top_y
	)


## The interior footprint from the tank floor to the water line; the pivot point without a tank.
static func pan_box(
	definition: TankDefinition, cabinet_top_y: float, stand_z: float, pivot: Vector3
) -> AABB:
	if definition == null:
		return AABB(pivot, Vector3.ZERO)
	var inner: Vector3 = definition.interior_size_m
	if not _has_volume(inner):
		return AABB(pivot, Vector3.ZERO)
	return _centred(
		inner.x,
		inner.z,
		stand_z,
		cabinet_top_y + definition.glass_thickness_m,
		definition.water_line_height_m
	)


## One box per visible mesh under the lamp, in the room frame; none for a missing or hidden lamp.
static func lamp_boxes(lamp: Node3D, room_frame: Transform3D) -> Array[AABB]:
	var boxes: Array[AABB] = []
	if lamp == null or not lamp.is_inside_tree() or not lamp.is_visible_in_tree():
		return boxes
	var to_room: Transform3D = room_frame.affine_inverse()
	_collect(lamp, to_room, boxes)
	return boxes


static func _collect(node: Node, to_room: Transform3D, boxes: Array[AABB]) -> void:
	var instance: MeshInstance3D = node as MeshInstance3D
	if instance != null and instance.mesh != null and instance.is_visible_in_tree():
		var box: AABB = (to_room * instance.global_transform) * instance.mesh.get_aabb()
		if box.get_volume() > 0.0:
			boxes.append(box)
	for child: Node in node.get_children():
		_collect(child, to_room, boxes)


static func _has_volume(size: Vector3) -> bool:
	return size.x > 0.0 and size.y > 0.0 and size.z > 0.0


static func _centred(
	width: float, depth: float, centre_z: float, base_y: float, height: float
) -> AABB:
	if width <= 0.0 or depth <= 0.0 or height <= 0.0:
		return AABB()
	return AABB(
		Vector3(-width / 2.0, base_y, centre_z - depth / 2.0), Vector3(width, height, depth)
	)
