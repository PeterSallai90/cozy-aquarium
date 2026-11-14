extends RefCounted
## Reads the substrate layer of a tank scene or a room for the #28 tests. The layer is the node
## Tank/SubstrateAnchor/Substrate (class SubstrateLayer, a MeshInstance3D) with the instance shader
## parameters substrate_tint, grain_scale, grain_shape and grain_contrast (technical plan, visual
## layer). SubstrateLayer does not exist before the implementation, so the node is reached by path
## and by name.

const Sub := preload("res://tests/helpers/substrate_api.gd")
const Table := preload("res://tests/helpers/tank_table.gd")

const ANCHOR := "SubstrateAnchor"
const LAYER := "Substrate"
const LAYER_IN_TANK := "SubstrateAnchor/Substrate"
const LAYER_IN_ROOM := "Tank/SubstrateAnchor/Substrate"
const LAYER_SCRIPT := "res://scenes/tank/substrate_layer.gd"
const MATERIAL_PATH := "res://assets/tank/materials/substrate.tres"
const SHADER_PATH := "res://shaders/substrate.gdshader"
const TINT_TOLERANCE := 0.0001
## The top face of the layer lies in this tank-local band (technical plan 1.1): 0.5 mm below to
## 0.1 mm above the inner floor.
const TOP_MIN_M := -0.0005
const TOP_MAX_M := 0.0001
const PLACEMENT_M := -0.0002
const ONE_CM := 0.01


static func layer_of_room(room: Node) -> MeshInstance3D:
	return room.get_node_or_null(LAYER_IN_ROOM) as MeshInstance3D


static func layer_of_tank(tank_node: Node) -> MeshInstance3D:
	return tank_node.get_node_or_null(LAYER_IN_TANK) as MeshInstance3D


## The tank scene of a catalog id (not in the tree), a bare Node3D when it is missing.
static func tank_scene(id: StringName) -> Node3D:
	var path: String = Table.scene_path(id)
	if not ResourceLoader.exists(path):
		return Node3D.new()
	var scene: PackedScene = load(path) as PackedScene
	var instance: Node3D = scene.instantiate() as Node3D if scene != null else null
	return instance if instance != null else Node3D.new()


static func _as_color(value: Variant) -> Color:
	if value is Color:
		return value
	if value is Vector4:
		var vector: Vector4 = value
		return Color(vector.x, vector.y, vector.z, vector.w)
	return Sub.MISSING_COLOUR


static func tint_of(layer: Node) -> Color:
	var node: GeometryInstance3D = layer as GeometryInstance3D
	if node == null:
		return Sub.MISSING_COLOUR
	return _as_color(node.get_instance_shader_parameter("substrate_tint"))


static func parameter(layer: Node, wanted: String) -> Variant:
	var node: GeometryInstance3D = layer as GeometryInstance3D
	if node == null:
		return null
	return node.get_instance_shader_parameter(wanted)


## "" when the layer shows `colour` and the catalog look of `id`, else what differs.
static func mismatch(layer: Node, cat: RefCounted, id: StringName, colour: Color) -> String:
	if layer == null:
		return "no layer node"
	var problems: PackedStringArray = PackedStringArray()
	var tint: Color = tint_of(layer)
	if (
		absf(tint.r - colour.r) > TINT_TOLERANCE
		or absf(tint.g - colour.g) > TINT_TOLERANCE
		or absf(tint.b - colour.b) > TINT_TOLERANCE
	):
		problems.append("tint %s, want %s" % [Sub.hex(tint), Sub.hex(colour)])
	var look: Dictionary = Sub.look(cat, id)
	var scale_value: Variant = parameter(layer, "grain_scale")
	if scale_value == null or absf(float(scale_value) - float(look["grain_scale"])) > 1e-7:
		problems.append("grain_scale %s, want %s" % [scale_value, look["grain_scale"]])
	var shape_value: Variant = parameter(layer, "grain_shape")
	if shape_value == null or int(shape_value) != int(look["grain_shape"]):
		problems.append("grain_shape %s, want %s" % [shape_value, look["grain_shape"]])
	var contrast_value: Variant = parameter(layer, "grain_contrast")
	if contrast_value == null or absf(float(contrast_value) - float(look["grain_contrast"])) > 1e-6:
		problems.append("grain_contrast %s, want %s" % [contrast_value, look["grain_contrast"]])
	return "; ".join(problems)


## All vertices of the mesh of a MeshInstance3D in the local space of `reference` (the tank root).
static func vertices_in(instance: MeshInstance3D, reference: Node3D) -> PackedVector3Array:
	var result: PackedVector3Array = PackedVector3Array()
	if instance == null or instance.mesh == null:
		return result
	var to_reference: Transform3D = _transform_to(instance, reference)
	for surface: int in instance.mesh.get_surface_count():
		var arrays: Array = instance.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vertex: Vector3 in vertices:
			result.append(to_reference * vertex)
	return result


## The transform of `node` relative to `reference`, composed from the local transforms (works for
## a scene that is not in the tree).
static func _transform_to(node: Node3D, reference: Node3D) -> Transform3D:
	var result: Transform3D = Transform3D.IDENTITY
	var current: Node3D = node
	while current != null and current != reference:
		result = current.transform * result
		current = current.get_parent() as Node3D
	return result
