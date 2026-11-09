class_name TankWater
extends Node3D
## The water of a tank: sizes Surface, Fog and DepthTint from the catalog (ADR 0007). The size
## comes only from TankDefinition.get_water_volume_size_m(); scene values are editor previews.

## Emitted after a successful build, for children such as the later caustics.
signal built(size_m: Vector3)

const CHILD_NAMES: Array[StringName] = [&"Surface", &"Fog", &"DepthTint"]

var _size_m: Vector3 = Vector3.ZERO
var _is_built: bool = false
var _fog_settings: WaterFogSettings = null


## Sizes the children and keeps this node at (0, size.y / 2, 0). Returns false, with one warning
## and the children hidden, when the definition or its water size is unusable.
func build(definition: TankDefinition, fog_settings: WaterFogSettings) -> bool:
	_disconnect_settings()
	_is_built = false
	_size_m = Vector3.ZERO
	var problem: String = _problem_of(definition)
	if problem != "":
		push_warning("TankWater: water not built, %s" % problem)
		_set_children_visible(false)
		return false
	var size: Vector3 = definition.get_water_volume_size_m()
	_size_m = size
	_is_built = true
	position = Vector3(0.0, size.y / 2.0, 0.0)
	scale = Vector3.ONE
	_set_children_visible(true)
	var missing: PackedStringArray = PackedStringArray()
	_build_surface(size, missing)
	_build_fog(size, missing)
	_build_depth_tint(size, missing)
	_set_glass_size(definition.interior_size_m)
	if not missing.is_empty():
		push_warning("TankWater: missing water nodes: %s" % ", ".join(missing))
	_fog_settings = fog_settings
	if _fog_settings != null:
		_fog_settings.applied.connect(_on_fog_settings_applied)
		_on_fog_settings_applied()
	built.emit(size)
	return true


func is_built() -> bool:
	return _is_built


## The water size; zero when not built.
func get_size_m() -> Vector3:
	return _size_m


## The water box in tank-local space: x and z centred, y from the inner floor to the water line.
func get_bounds_in_tank() -> AABB:
	return AABB(Vector3(-_size_m.x / 2.0, 0.0, -_size_m.z / 2.0), _size_m)


func _problem_of(definition: TankDefinition) -> String:
	if definition == null:
		return "no tank definition"
	var size: Vector3 = definition.get_water_volume_size_m()
	for value: float in [size.x, size.y, size.z]:
		if not is_finite(value) or value <= 0.0:
			return "the water size %s is not positive and finite" % size
	if definition.water_line_height_m >= definition.interior_size_m.y:
		return "the water line is not below the interior height"
	return ""


func _set_children_visible(shown: bool) -> void:
	for child_name: StringName in CHILD_NAMES:
		var child: Node3D = get_node_or_null(NodePath(child_name)) as Node3D
		if child != null:
			child.visible = shown


func _build_surface(size: Vector3, missing: PackedStringArray) -> void:
	var surface: MeshInstance3D = get_node_or_null("Surface") as MeshInstance3D
	if surface == null:
		missing.append("Surface")
		return
	var mesh: PlaneMesh = PlaneMesh.new()
	mesh.size = Vector2(size.x, size.z)
	surface.mesh = mesh
	surface.position = Vector3(0.0, size.y / 2.0, 0.0)
	surface.set_instance_shader_parameter(&"water_size_m", size)


func _build_depth_tint(size: Vector3, missing: PackedStringArray) -> void:
	var tint: MeshInstance3D = get_node_or_null("DepthTint") as MeshInstance3D
	if tint == null:
		missing.append("DepthTint")
		return
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	tint.mesh = mesh
	tint.set_instance_shader_parameter(&"water_size_m", size)


func _build_fog(size: Vector3, missing: PackedStringArray) -> void:
	var fog: FogVolume = get_node_or_null("Fog") as FogVolume
	if fog == null:
		missing.append("Fog")
		return
	fog.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	fog.size = size
	var preview: FogMaterial = fog.material as FogMaterial
	fog.material = preview.duplicate() as FogMaterial if preview != null else FogMaterial.new()


## The glass is a sibling of the water volume in the tank scene; it needs the interior size.
func _set_glass_size(interior_m: Vector3) -> void:
	var parent: Node = get_parent()
	if parent == null:
		return
	var glass: GeometryInstance3D = parent.get_node_or_null("Glass") as GeometryInstance3D
	if glass != null:
		glass.set_instance_shader_parameter(&"glass_interior_size_m", interior_m)


func _disconnect_settings() -> void:
	if _fog_settings != null and _fog_settings.applied.is_connected(_on_fog_settings_applied):
		_fog_settings.applied.disconnect(_on_fog_settings_applied)
	_fog_settings = null


func _on_fog_settings_applied() -> void:
	if _fog_settings == null:
		return
	_fog_settings.apply_to_fog(get_node_or_null("Fog") as FogVolume)
