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
const CAUSTIC_SETTINGS_PATH := "res://scenes/tank/water_caustic_settings.tres"
const CAUSTIC_SETTINGS_SCRIPT := "res://scenes/tank/water_caustic_settings.gd"
const CAUSTICS_MATERIAL := "res://assets/tank/materials/caustics.tres"
const CAUSTICS_SHADER := "res://shaders/caustics.gdshader"
const CAUSTICS_NODE_SCRIPT := "res://scenes/tank/tank_caustics.gd"
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


# --- #126 caustics: the classes do not exist before the implementation, same late binding ---


## A private copy of the default caustic settings. A bare Resource while the class is missing.
static func caustic_settings() -> Resource:
	if not ResourceLoader.exists(CAUSTIC_SETTINGS_PATH):
		return Resource.new()
	var shared: Resource = load(CAUSTIC_SETTINGS_PATH) as Resource
	if shared == null:
		return Resource.new()
	return shared.duplicate() as Resource


## TankWater.build(definition, fog, caustics) with the optional third parameter.
static func build_with_caustics(
	water: Node, def: TankDefinition, fog_settings: Resource, caustic: Resource
) -> Variant:
	return Api.call_on(water, "build", [def, fog_settings, caustic], NO_METHOD)


## A tank scene built with private fog settings and the given caustic settings. Not in the tree;
## the caller frees it.
static func built_tank_with_caustics(id: StringName, caustic: Resource) -> Node3D:
	var instance: Node3D = tank(id)
	var water: Node3D = water_of(instance)
	if water != null:
		build_with_caustics(water, definition(id), settings(), caustic)
	return instance


## The single node named Caustics below a root, or null (also when there are several).
static func caustics_of(root: Node) -> Node3D:
	var found: Array[Node] = named(root, "Caustics")
	return found[0] as Node3D if found.size() == 1 else null


## A spot light under the tank, pointing down (-Z of its basis is -Y). Needs the tank in the tree.
static func add_light(
	tank_node: Node3D, local_position: Vector3, angle_deg: float, range_m: float
) -> SpotLight3D:
	var light: SpotLight3D = SpotLight3D.new()
	light.spot_angle = angle_deg
	light.spot_range = range_m
	light.position = local_position
	light.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	tank_node.add_child(light)
	return light


## Lamp values in the WaterVolume frame, by the formulas of the technical plan of #126.
static func expected_lamp(water: Node3D, light: SpotLight3D) -> Dictionary:
	var inverse: Transform3D = water.global_transform.affine_inverse()
	return {
		"lamp_position_m": inverse * light.global_position,
		"lamp_direction":
		(water.global_basis.inverse() * light.global_basis * Vector3.FORWARD).normalized(),
		"lamp_spot_angle_deg": light.spot_angle,
		"lamp_spot_range_m": light.spot_range,
	}


## The committed room scene with setup(model, catalog, fog, caustic). Falls back to the shorter
## setup() while the fourth parameter does not exist, so the room still loads and a test fails
## on its own assertion.
static func room_with_caustics(
	model: AquariumModel, catalog: RefCounted, fog_settings: Resource, caustic: Resource
) -> Node3D:
	if not ResourceLoader.exists(Rig.ROOM_SCENE):
		return Node3D.new()
	var instance: Node3D = (load(Rig.ROOM_SCENE) as PackedScene).instantiate() as Node3D
	if instance == null:
		return Node3D.new()
	var wanted: int = 2
	for entry: Dictionary in instance.get_method_list():
		if entry["name"] == "setup":
			wanted = (entry["args"] as Array).size()
	if wanted >= 4:
		instance.call("setup", model, catalog, fog_settings, caustic)
	elif wanted == 3:
		instance.call("setup", model, catalog, fog_settings)
	else:
		instance.call("setup", model, catalog)
	return instance


## An instance shader parameter of a node, or null.
static func param(node: Node, parameter: StringName) -> Variant:
	var geometry: GeometryInstance3D = node as GeometryInstance3D
	if geometry == null:
		return null
	return geometry.get_instance_shader_parameter(parameter)


## True when the Variant is a float or int equal to `expected` within `tolerance`.
static func near(value: Variant, expected: float, tolerance: float = 0.0001) -> bool:
	return (
		(typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT)
		and (absf(float(value) - expected) <= tolerance)
	)


## True when the Variant is a Vector3 within `tolerance` of `expected` per component.
static func near_vector(value: Variant, expected: Vector3, tolerance: float = 0.001) -> bool:
	if typeof(value) != TYPE_VECTOR3:
		return false
	var vector: Vector3 = value
	return (
		absf(vector.x - expected.x) <= tolerance
		and absf(vector.y - expected.y) <= tolerance
		and absf(vector.z - expected.z) <= tolerance
	)
