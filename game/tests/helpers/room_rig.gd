extends RefCounted
## Builds the room corner scene for tests (#22). Room space is the local space of the RoomCorner
## root, which the tests keep at the identity transform. The room, catalog and definition types
## are reached through LateApi because they do not exist before the implementation.

const Glb := preload("res://tests/helpers/glb_mesh_checks.gd")
const Api := preload("res://tests/helpers/late_api.gd")

const ROOM_SCENE := "res://scenes/room/room_corner.tscn"
const DEFAULT_ID := &"tank_medium_60l"


## The committed scene with setup() called before it enters the tree. The caller adds it to the
## tree (or a SubViewport) and owns it. A plain Node3D stand-in when the scene is missing.
static func instantiate(model: AquariumModel, catalog: RefCounted) -> Node3D:
	if not ResourceLoader.exists(ROOM_SCENE):
		return Node3D.new()
	var scene: PackedScene = load(ROOM_SCENE) as PackedScene
	var room: Node3D = scene.instantiate() as Node3D
	if room != null and room.has_method("setup"):
		room.call("setup", model, catalog)
	return room if room != null else Node3D.new()


static func default_catalog() -> RefCounted:
	return Api.catalog_load_dir()


static func model_with(tank_id: StringName) -> AquariumModel:
	var model: AquariumModel = AquariumModel.new("2026-11-01T12:00:00Z")
	model.apply_set_tank_id(tank_id)
	return model


static func default_definition() -> Resource:
	return Api.definition_of(default_catalog(), DEFAULT_ID)


static func displayed_id(room: Node) -> StringName:
	return Api.call_on(room, "get_displayed_tank_id", [], &"<no method>")


## A definition that copies the default tank's numbers but has the given id and scene.
static func variant(id: StringName, scene: PackedScene) -> Resource:
	var source: Resource = default_definition()
	var copy: Resource = Api.new_definition()
	copy.set("id", id)
	copy.set("scene", scene)
	for field: String in [
		"name_key",
		"description_key",
		"interior_size_m",
		"volume_litres",
		"glass_thickness_m",
		"water_line_height_m"
	]:
		copy.set(field, Api.prop(source, field, null))
	return copy


## A scene whose root is a plain Node (not a Node3D).
static func wrong_root_scene() -> PackedScene:
	var node: Node = Node.new()
	var scene: PackedScene = PackedScene.new()
	scene.pack(node)
	node.free()
	return scene


## Vertices of a mesh instance below the room, in room space.
static func vertices_in_room(room: Node3D, instance: MeshInstance3D) -> PackedVector3Array:
	return Glb.vertices_in(instance, room)


## The same vertices in tank-local space (the Tank node transform undone).
static func vertices_in_tank(room: Node3D, instance: MeshInstance3D) -> PackedVector3Array:
	var tank: Node3D = room.get_node("Tank") as Node3D
	var inverse: Transform3D = tank.transform.affine_inverse()
	var result: PackedVector3Array = PackedVector3Array()
	for point: Vector3 in vertices_in_room(room, instance):
		result.append(inverse * point)
	return result


static func glass_m() -> float:
	return Api.prop(default_definition(), "glass_thickness_m", Api.MISSING_NUMBER)


static func water_line_m() -> float:
	return Api.prop(default_definition(), "water_line_height_m", Api.MISSING_NUMBER)


static func interior_m() -> Vector3:
	return Api.prop(default_definition(), "interior_size_m", Vector3.ZERO)


static func exterior_m() -> Vector3:
	return Api.call_on(default_definition(), "get_exterior_size_m", [], Vector3.ZERO)
