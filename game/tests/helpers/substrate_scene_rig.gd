extends RefCounted
## Reads the substrate bed of a tank scene or a room for the #28 tests (technical plan v3). The bed
## is the node Tank/SubstrateAnchor/Substrate (class SubstrateBed, a Node3D) created by the room at
## run time; a built bed holds SubstrateBedView children with the nodes Core, CoreFloor, SandSurface
## (sand), Chunk_<ix>_<iz>_v<n> and SandTop_<a>_<b>, whose materials carry the shader parameter
## substrate_tint. SubstrateBed does not exist before the implementation, so the node is reached by
## path and by name.

const Api := preload("res://tests/helpers/substrate_bed_api.gd")
const Sub := preload("res://tests/helpers/substrate_api.gd")
const Table := preload("res://tests/helpers/tank_table.gd")

const ANCHOR := "SubstrateAnchor"
const BED := "Substrate"
const BED_IN_TANK := "SubstrateAnchor/Substrate"
const BED_IN_ROOM := "Tank/SubstrateAnchor/Substrate"
const BED_CLASS := "SubstrateBed"
const VIEW_CLASS := "SubstrateBedView"
const TINT_PARAMETER := "substrate_tint"
const TINT_TOLERANCE := 0.0001
## The files of the flat layer of the first approach; none may exist any more.
const FLAT_LAYER_FILES: Array[String] = [
	"res://scenes/tank/substrate_layer.gd",
	"res://shaders/substrate.gdshader",
	"res://assets/tank/materials/substrate.tres",
]


## The SubstrateBed of a room, null when the node is missing or is not a SubstrateBed (the flat
## layer of the first approach sits at the same path).
static func bed_of_room(room: Node) -> Node3D:
	return _as_bed(room.get_node_or_null(BED_IN_ROOM))


static func bed_of_tank(tank_node: Node) -> Node3D:
	return _as_bed(tank_node.get_node_or_null(BED_IN_TANK))


static func _as_bed(node: Node) -> Node3D:
	if node == null or Api.class_of(node) != BED_CLASS:
		return null
	return node as Node3D


## The tank scene of a catalog id (not in the tree), a bare Node3D when it is missing.
static func tank_scene(id: StringName) -> Node3D:
	var path: String = Table.scene_path(id)
	if not ResourceLoader.exists(path):
		return Node3D.new()
	var scene: PackedScene = load(path) as PackedScene
	var instance: Node3D = scene.instantiate() as Node3D if scene != null else null
	return instance if instance != null else Node3D.new()


## Every SubstrateBedView below the bed.
static func views_of(bed: Node) -> Array[Node3D]:
	var found: Array[Node3D] = []
	if bed == null:
		return found
	for child: Node in bed.get_children():
		if Api.class_of(child) == VIEW_CLASS:
			found.append(child as Node3D)
	return found


## Every GeometryInstance3D below a node (stone chunks, sand tops, core, skin).
static func geometry_below(node: Node) -> Array[GeometryInstance3D]:
	var found: Array[GeometryInstance3D] = []
	if node == null:
		return found
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is GeometryInstance3D:
			found.append(current as GeometryInstance3D)
		stack.append_array(current.get_children())
	return found


## The materials a geometry instance draws with: the override, else the surface materials of its
## mesh (a MultiMesh node uses the mesh of its MultiMesh).
static func materials_of(instance: GeometryInstance3D) -> Array[Material]:
	var found: Array[Material] = []
	if instance.material_override != null:
		found.append(instance.material_override)
		return found
	var mesh: Mesh = null
	if instance is MeshInstance3D:
		mesh = (instance as MeshInstance3D).mesh
	elif instance is MultiMeshInstance3D:
		var multimesh: MultiMesh = (instance as MultiMeshInstance3D).multimesh
		mesh = multimesh.mesh if multimesh != null else null
	if mesh != null:
		for surface: int in mesh.get_surface_count():
			var material: Material = mesh.surface_get_material(surface)
			if material != null:
				found.append(material)
	return found


## True when the shader of a ShaderMaterial declares the uniform.
static func has_uniform(material: Material, uniform_name: String) -> bool:
	var shader_material: ShaderMaterial = material as ShaderMaterial
	if shader_material == null or shader_material.shader == null:
		return false
	for uniform: Dictionary in shader_material.shader.get_shader_uniform_list():
		if uniform["name"] == uniform_name:
			return true
	return false


## The tint of a material: the parameter substrate_tint, or the stand-in colour when it has none.
static func tint_of_material(material: Material) -> Color:
	var shader_material: ShaderMaterial = material as ShaderMaterial
	if shader_material == null:
		return Sub.MISSING_COLOUR
	var value: Variant = shader_material.get_shader_parameter(TINT_PARAMETER)
	if value is Color:
		return value
	if value is Vector4:
		var vector: Vector4 = value
		return Color(vector.x, vector.y, vector.z, vector.w)
	return Sub.MISSING_COLOUR


static func same_tint(a: Color, b: Color) -> bool:
	return (
		absf(a.r - b.r) <= TINT_TOLERANCE
		and absf(a.g - b.g) <= TINT_TOLERANCE
		and absf(a.b - b.b) <= TINT_TOLERANCE
	)


## All materials of a view that take the tint (they declare substrate_tint), without duplicates.
static func tinted_materials(view: Node) -> Array[Material]:
	var found: Array[Material] = []
	for instance: GeometryInstance3D in geometry_below(view):
		for material: Material in materials_of(instance):
			if has_uniform(material, TINT_PARAMETER) and not found.has(material):
				found.append(material)
	return found


## "" when every tinted material of the view holds `colour` (and there is at least one for each
## part: Core, CoreFloor and a stone or grain node), else what differs.
static func tint_mismatch(view: Node, colour: Color) -> String:
	if view == null:
		return "no view"
	var problems: PackedStringArray = PackedStringArray()
	var materials: Array[Material] = tinted_materials(view)
	if materials.is_empty():
		return "no material takes substrate_tint"
	for material: Material in materials:
		var tint: Color = tint_of_material(material)
		if not same_tint(tint, colour):
			problems.append(
				"%s has tint %s, want %s" % [material.resource_name, Sub.hex(tint), Sub.hex(colour)]
			)
	for part: String in ["Core", "CoreFloor"]:
		var node: GeometryInstance3D = view.get_node_or_null(part) as GeometryInstance3D
		if node == null:
			problems.append("%s is missing" % part)
			continue
		var found: bool = false
		for material: Material in materials_of(node):
			found = found or has_uniform(material, TINT_PARAMETER)
		if not found:
			problems.append("%s has no material with substrate_tint" % part)
	return "; ".join(problems)


## True when any stone or grain node (a MultiMeshInstance3D) of the view is visible in the tree.
static func stones_visible(view: Node) -> bool:
	for instance: GeometryInstance3D in geometry_below(view):
		if instance is MultiMeshInstance3D and instance.is_visible_in_tree():
			return true
	return false


## The AABB of a mesh instance of the view in the space of the view.
static func aabb_in_view(node: MeshInstance3D, view: Node3D) -> AABB:
	if node == null or node.mesh == null:
		return AABB()
	var transform: Transform3D = Transform3D.IDENTITY
	var current: Node3D = node
	while current != null and current != view:
		transform = current.transform * transform
		current = current.get_parent() as Node3D
	return transform * node.mesh.get_aabb()
