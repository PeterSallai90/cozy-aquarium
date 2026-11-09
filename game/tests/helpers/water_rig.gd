extends RefCounted
## Builds tank scenes, rooms and fog settings for the #23 water tests. TankWater and
## WaterFogSettings do not exist before the implementation, so they are reached through plain
## Node3D and Resource calls (see late_api.gd for the reason): a missing class then fails one test
## with a readable message and never breaks the parse of the whole suite.

const Api := preload("res://tests/helpers/late_api.gd")
const Rig := preload("res://tests/helpers/room_rig.gd")
const Table := preload("res://tests/helpers/tank_table.gd")

const SETTINGS_PATH := "res://scenes/tank/water_fog_settings.tres"
const GLASS_MATERIAL := "res://assets/tank/materials/tank_glass.tres"
const SURFACE_MATERIAL := "res://assets/tank/materials/water_surface.tres"
const DEPTH_TINT_MATERIAL := "res://assets/tank/materials/water_depth_tint.tres"
const FOG_MATERIAL := "res://assets/tank/materials/water_fog.tres"
const MM := 0.001
const NO_METHOD: StringName = &"<no method>"


## A private copy of the default fog settings, so a test never mutates the shared resource. A bare
## Resource while the class is missing.
static func settings() -> Resource:
	if not ResourceLoader.exists(SETTINGS_PATH):
		return Resource.new()
	var shared: Resource = load(SETTINGS_PATH) as Resource
	if shared == null:
		return Resource.new()
	return shared.duplicate() as Resource


## The tank scene of a catalog id, not yet in the tree and not built. A bare Node3D when missing.
static func tank(id: StringName) -> Node3D:
	var path: String = Table.scene_path(id)
	if not ResourceLoader.exists(path):
		return Node3D.new()
	var scene: PackedScene = load(path) as PackedScene
	var instance: Node3D = scene.instantiate() as Node3D if scene != null else null
	return instance if instance != null else Node3D.new()


static func definition(id: StringName) -> TankDefinition:
	return Rig.definition_of(id) as TankDefinition


static func water_of(tank_node: Node) -> Node3D:
	return tank_node.get_node_or_null("WaterVolume") as Node3D


## TankWater.build(); the NO_METHOD marker while the class is missing.
static func build(water: Node, def: TankDefinition, fog_settings: Resource) -> Variant:
	return Api.call_on(water, "build", [def, fog_settings], NO_METHOD)


## A tank scene with its WaterVolume built from the catalog definition and a private settings copy.
## The caller frees the returned tank.
static func built_tank(id: StringName, fog_settings: Resource = null) -> Node3D:
	var instance: Node3D = tank(id)
	var water: Node3D = water_of(instance)
	if water != null:
		build(water, definition(id), fog_settings if fog_settings != null else settings())
	return instance


static func size_of(water: Node) -> Vector3:
	return Api.call_on(water, "get_size_m", [], Vector3.ONE * Api.MISSING_NUMBER)


## True only when TankWater.is_built() exists and returns true.
static func is_built(water: Node) -> bool:
	var result: Variant = Api.call_on(water, "is_built", [], NO_METHOD)
	return typeof(result) == TYPE_BOOL and result


## True only when the Variant is the bool true (a missing method gives a marker, never an error).
static func is_true(value: Variant) -> bool:
	return typeof(value) == TYPE_BOOL and value


static func bounds_of(water: Node) -> AABB:
	return Api.call_on(
		water, "get_bounds_in_tank", [], AABB(Vector3.ONE * Api.MISSING_NUMBER, Vector3.ZERO)
	)


## All descendants of a class below a node (any depth, owner not required).
static func all_of(root: Node, class_name_text: String) -> Array[Node]:
	return root.find_children("*", class_name_text, true, false)


## All descendants with this exact node name.
static func named(root: Node, node_name: String) -> Array[Node]:
	var found: Array[Node] = []
	for node: Node in root.find_children(node_name, "", true, false):
		if String(node.name) == node_name:
			found.append(node)
	return found


## Transform of a node relative to the tank root, through the WaterVolume chain only.
static func in_tank(tank_node: Node3D, node: Node3D) -> Transform3D:
	var result: Transform3D = Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != tank_node:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result


## Total warning count of a capture result.
static func count_of(entries: Dictionary) -> int:
	var total: int = 0
	for key: Variant in entries:
		total += int(entries[key])
	return total


## Puts the process-wide froxel values back to the defaults (RenderingServer has no getter).
static func restore_rendering_server() -> void:
	var defaults: Resource = settings()
	Api.call_on(defaults, "apply_to_rendering_server", [], null)


## The committed room scene with setup(model, catalog, fog_settings) called before it enters the
## tree. The caller adds it to the tree and owns it. A plain Node3D stand-in when the scene is
## missing.
static func room(model: AquariumModel, catalog: RefCounted, fog_settings: Resource) -> Node3D:
	if not ResourceLoader.exists(Rig.ROOM_SCENE):
		return Node3D.new()
	var instance: Node3D = (load(Rig.ROOM_SCENE) as PackedScene).instantiate() as Node3D
	if instance == null:
		return Node3D.new()
	if instance.has_method("setup"):
		var wanted: int = 2
		for entry: Dictionary in instance.get_method_list():
			if entry["name"] == "setup":
				wanted = (entry["args"] as Array).size()
		if wanted >= 3:
			instance.call("setup", model, catalog, fog_settings)
		else:
			instance.call("setup", model, catalog)
	return instance


static func environment_of(room_node: Node) -> Environment:
	var holder: WorldEnvironment = (
		room_node.get_node_or_null("WorldEnvironment") as WorldEnvironment
	)
	return holder.environment if holder != null else null


## The displayed tank of a room.
static func displayed_tank(room_node: Node) -> Node3D:
	return room_node.get_node_or_null("Tank") as Node3D
