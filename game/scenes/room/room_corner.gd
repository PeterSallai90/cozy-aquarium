class_name RoomCorner
extends Node3D
## The cozy room corner: room, cabinet, lamp, the displayed tank and the build camera.
## Reads the model, never writes it. When the model changes the tank (or is reset), the room swaps
## tank, cabinet and lamp for the ones of the new tank and frames the default view again.

const CABINET_TOP_HEIGHT_M: float = 0.75
## Cabinet margin around the tank exterior on every side; the same rule as the cabinet generator.
const CABINET_MARGIN_M: float = 0.025
## Room origin to the inner face of the back wall, and the gap between wall and cabinet back.
const BACK_WALL_Z_M: float = -0.215
const SIDE_WALL_X_M: float = -0.85
const WALL_GAP_M: float = 0.035
const CAMERA_HFOV_DEG: float = 50.0
const CAMERA_ELEVATION_DEG: float = 5.0
const CAMERA_WIDTH_SHARE: float = 0.85
const CAMERA_MAX_KEEP_WIDTH_ASPECT: float = 16.0 / 9.0
## ADR 0006: share of the half screen height kept free above and below the framed points.
const CAMERA_FIT_MARGIN: float = 0.02
const NO_TANK_PIVOT_HEIGHT_M: float = 0.2
const FOG_SETTINGS_PATH: String = "res://scenes/tank/water_fog_settings.tres"
const CAUSTIC_SETTINGS_PATH: String = "res://scenes/tank/water_caustic_settings.tres"
const NO_TANK_EXTERIOR_M: Vector3 = Vector3(0.66, 0.36, 0.36)

var _model: AquariumModel = null
var _catalog: TankCatalog = null
var _fog_settings: WaterFogSettings = null
var _caustic_settings: WaterCausticSettings = null
var _displayed_tank_id: StringName = &""
var _camera_distance: float = 0.0
## The tank instance made while resolving the definition; _show_tank adds it to the room.
var _resolved_tank: Node3D = null

@onready var _camera: BuildCamera = $BuildCamera
@onready var _walls: WallCutaway = $WallCutaway


## Optional, before the node enters the tree. Without it the room uses a new model, the catalog
## directory, the shared default fog settings and the shared default caustic settings
## (CAUSTIC_SETTINGS_PATH). fog_settings and caustic_settings are both optional; null selects
## the default.
func setup(
	model: AquariumModel,
	catalog: TankCatalog,
	fog_settings: WaterFogSettings = null,
	caustic_settings: WaterCausticSettings = null
) -> void:
	_model = model
	_catalog = catalog
	_fog_settings = fog_settings
	_caustic_settings = caustic_settings


func _ready() -> void:
	if _model == null:
		_model = AquariumModel.new()
	if _catalog == null:
		_catalog = TankCatalog.load_dir()
	if _fog_settings == null:
		_fog_settings = load(FOG_SETTINGS_PATH) as WaterFogSettings
	if _caustic_settings == null:
		_caustic_settings = load(CAUSTIC_SETTINGS_PATH) as WaterCausticSettings
	_setup_fog()
	_model.tank_changed.connect(_on_tank_changed)
	_model.model_reset.connect(_show_tank)
	_show_tank()
	_register_walls()
	get_viewport().size_changed.connect(_apply_projection)
	_apply_projection()


## Gives the room its own Environment copy (the shared resource is never changed) and applies the
## fog settings to it and to the froxel globals; later applications come through the signal.
func _setup_fog() -> void:
	if _fog_settings == null:
		return
	var holder: WorldEnvironment = get_node_or_null("WorldEnvironment") as WorldEnvironment
	if holder != null and holder.environment != null:
		holder.environment = holder.environment.duplicate() as Environment
	_fog_settings.applied.connect(_on_fog_applied)
	_on_fog_applied()


func _on_fog_applied() -> void:
	var holder: WorldEnvironment = get_node_or_null("WorldEnvironment") as WorldEnvironment
	if holder != null:
		_fog_settings.apply_to_environment(holder.environment)
	_fog_settings.apply_to_rendering_server()


## The id of the tank that is shown; empty when no tank is shown.
func get_displayed_tank_id() -> StringName:
	return _displayed_tank_id


func _on_tank_changed(_tank_id: StringName) -> void:
	_show_tank()


## Replaces tank, cabinet and lamp by the ones of the tank the model asks for, frames the default
## view and announces the displayed tank.
func _show_tank() -> void:
	for node_name: StringName in [&"Tank", &"Cabinet", &"Lamp"]:
		var old: Node = get_node_or_null(NodePath(node_name))
		if old != null:
			remove_child(old)
			old.queue_free()
	_resolved_tank = null
	var definition: TankDefinition = _resolve_tank()
	var stand_z: float = 0.0
	if definition != null:
		stand_z = _stand_z(definition)
	_add_furniture(&"Cabinet", definition, stand_z)
	_displayed_tank_id = &""
	var tank: Node3D = _resolved_tank
	var water: TankWater = null
	_resolved_tank = null
	if tank != null:
		tank.name = &"Tank"
		tank.position = Vector3(0.0, CABINET_TOP_HEIGHT_M + definition.glass_thickness_m, stand_z)
		water = tank.get_node_or_null("WaterVolume") as TankWater
		if water != null:
			water.build(definition, _fog_settings, _caustic_settings)
		add_child(tank)
		_displayed_tank_id = definition.id
	var lamp: Node3D = _add_furniture(&"Lamp", definition, stand_z)
	var mount: Node3D = null
	if tank != null:
		mount = tank.get_node_or_null("lamp_mount") as Node3D
	if mount != null:
		lamp.global_transform = mount.global_transform
		if water != null:
			water.set_key_light(lamp.get_node_or_null("KeyLight") as SpotLight3D)
	elif tank == null:
		lamp.position = Vector3(0.0, 0.0, stand_z)
	_frame_camera(definition, stand_z)
	EventBus.tank_displayed.emit(_displayed_tank_id)


## The definition to show: the model's tank, else the default tank (one warning for an unknown id,
## one error for a tank without a loadable scene). Null when not even the default exists. When the
## default has no loadable scene either, its definition is still returned: the room then shows
## its furniture without a tank.
func _resolve_tank() -> TankDefinition:
	var default_id: StringName = AquariumModel.DEFAULT_TANK_ID
	var wanted: StringName = _model.get_tank_id()
	var definition: TankDefinition = _catalog.get_definition(wanted)
	if definition == null:
		push_warning(
			'RoomCorner: unknown tank id "%s"; showing the default tank "%s"' % [wanted, default_id]
		)
		definition = _catalog.get_definition(default_id)
	if _can_instantiate(definition):
		return definition
	if definition != null and definition.id != default_id:
		push_error(
			(
				'RoomCorner: tank "%s" has no loadable scene; showing the default tank "%s"'
				% [definition.id, default_id]
			)
		)
		definition = _catalog.get_definition(default_id)
		if _can_instantiate(definition):
			return definition
	push_error(
		(
			(
				'RoomCorner: default tank "%s" has no loadable scene; '
				+ "showing the room without a tank"
			)
			% default_id
		)
	)
	return definition


func _can_instantiate(definition: TankDefinition) -> bool:
	if definition == null:
		return false
	var instance: Node3D = _instantiate(definition.scene)
	if instance == null:
		return false
	_resolved_tank = instance
	return true


## The scene root, or null when there is no scene or its root is not a Node3D.
func _instantiate(scene: PackedScene) -> Node3D:
	if scene == null:
		return null
	var instance: Node = scene.instantiate()
	if instance == null:
		return null
	if not instance is Node3D:
		instance.free()
		return null
	return instance as Node3D


## Adds the cabinet or the lamp of the definition under the given name; an empty Node3D stands in
## when there is no scene, so the room always has both nodes.
func _add_furniture(node_name: StringName, definition: TankDefinition, stand_z: float) -> Node3D:
	var scene: PackedScene = null
	if definition != null:
		scene = definition.cabinet_scene if node_name == &"Cabinet" else definition.lamp_scene
	var node: Node3D = _instantiate(scene)
	if node == null:
		node = Node3D.new()
	node.name = node_name
	if node_name == &"Cabinet":
		node.position = Vector3(0.0, 0.0, stand_z)
	add_child(node)
	return node


## The cabinet stands with its back WALL_GAP_M from the back wall; the tank, the lamp and the
## camera pivot follow it.
func _stand_z(definition: TankDefinition) -> float:
	var depth: float = definition.get_exterior_size_m().z + 2.0 * CABINET_MARGIN_M
	return BACK_WALL_Z_M + WALL_GAP_M + depth / 2.0


func _frame_camera(definition: TankDefinition, stand_z: float) -> void:
	var pivot: Vector3 = Vector3(0.0, CABINET_TOP_HEIGHT_M + NO_TANK_PIVOT_HEIGHT_M, stand_z)
	var exterior: Vector3 = NO_TANK_EXTERIOR_M
	var fit: float = 0.0
	if definition != null:
		exterior = definition.get_exterior_size_m()
		pivot.y = (
			CABINET_TOP_HEIGHT_M
			+ definition.glass_thickness_m
			+ definition.water_line_height_m / 2.0
		)
		fit = CameraFraming.fit_distance(
			_fit_points(definition, pivot.y),
			CAMERA_HFOV_DEG,
			CAMERA_ELEVATION_DEG,
			CAMERA_FIT_MARGIN
		)
	_camera_distance = maxf(
		CameraFraming.default_distance(
			exterior.x, exterior.z, CAMERA_HFOV_DEG, CAMERA_ELEVATION_DEG, CAMERA_WIDTH_SHARE
		),
		fit
	)
	_camera.set_framing(
		pivot, _camera_distance, pivot.y - CABINET_TOP_HEIGHT_M, CAMERA_ELEVATION_DEG
	)


## Gives the wall cutaway the two walls and their planes (normals into the room).
func _register_walls() -> void:
	var room: Node = get_node_or_null("Room")
	if room == null:
		return
	var back: Node = room.find_child("BackWall", true, false)
	var side: Node = room.find_child("SideWall", true, false)
	if back is GeometryInstance3D:
		var nodes: Array[GeometryInstance3D] = [back as GeometryInstance3D]
		var plane: Plane = Plane(Vector3(0.0, 0.0, 1.0), BACK_WALL_Z_M)
		_walls.add_wall(WallCutaway.BACK, nodes, global_transform * plane)
	if side is GeometryInstance3D:
		var nodes: Array[GeometryInstance3D] = [side as GeometryInstance3D]
		var plane: Plane = Plane(Vector3(1.0, 0.0, 0.0), SIDE_WALL_X_M)
		_walls.add_wall(WallCutaway.LEFT, nodes, global_transform * plane)


## The points that must stay on screen, relative to the pivot: the corners of the tank exterior
## with its rim trim, and the two front corners of the cabinet top (ADR 0006).
func _fit_points(definition: TankDefinition, pivot_y: float) -> PackedVector3Array:
	var exterior: Vector3 = definition.get_exterior_size_m()
	var low: float = CABINET_TOP_HEIGHT_M - pivot_y
	var high: float = (
		CABINET_TOP_HEIGHT_M
		+ definition.glass_thickness_m
		+ definition.interior_size_m.y
		+ definition.trim_size_m
		- pivot_y
	)
	var points: PackedVector3Array = PackedVector3Array()
	for side_x: float in [-1.0, 1.0]:
		for side_z: float in [-1.0, 1.0]:
			for y: float in [low, high]:
				points.append(Vector3(side_x * exterior.x / 2.0, y, side_z * exterior.z / 2.0))
		points.append(
			Vector3(
				side_x * (exterior.x / 2.0 + CABINET_MARGIN_M),
				low,
				exterior.z / 2.0 + CABINET_MARGIN_M
			)
		)
	return points


func _apply_projection() -> void:
	var size: Vector2 = get_viewport().get_visible_rect().size
	if size.y <= 0.0:
		return
	var aspect: float = size.x / size.y
	_camera.keep_aspect = CameraFraming.keep_aspect_for(aspect, CAMERA_MAX_KEEP_WIDTH_ASPECT)
	_camera.fov = CameraFraming.fov_for(aspect, CAMERA_HFOV_DEG, CAMERA_MAX_KEEP_WIDTH_ASPECT)
