class_name RoomCorner
extends Node3D
## The cozy room corner: room, cabinet, lamp, the displayed tank and the placeholder camera.
## Reads the model, never writes it. Swapping the tank later is the job of the change-tank command.

const CABINET_TOP_HEIGHT_M: float = 0.75
const CAMERA_HFOV_DEG: float = 50.0
const CAMERA_ELEVATION_DEG: float = 5.0
const CAMERA_WIDTH_SHARE: float = 0.85
const CAMERA_MAX_KEEP_WIDTH_ASPECT: float = 16.0 / 9.0
const NO_TANK_PIVOT_HEIGHT_M: float = 0.2
const NO_TANK_EXTERIOR_M: Vector3 = Vector3(0.66, 0.36, 0.36)

var _model: AquariumModel = null
var _catalog: TankCatalog = null
var _displayed_tank_id: StringName = &""
var _camera_distance: float = 0.0

@onready var _lamp: Node3D = $Lamp
@onready var _camera: Camera3D = $PlaceholderCamera


## Optional, before the node enters the tree. Without it the room uses a new model and the
## catalog directory.
func setup(model: AquariumModel, catalog: TankCatalog) -> void:
	_model = model
	_catalog = catalog


func _ready() -> void:
	if _model == null:
		_model = AquariumModel.new()
	if _catalog == null:
		_catalog = TankCatalog.load_dir()
	var tank_definition: TankDefinition = _build_tank()
	_frame_camera(tank_definition)
	get_viewport().size_changed.connect(_apply_projection)
	_apply_projection()


## The id of the tank that is shown; empty when no tank is shown.
func get_displayed_tank_id() -> StringName:
	return _displayed_tank_id


func _build_tank() -> TankDefinition:
	var default_id: StringName = AquariumModel.DEFAULT_TANK_ID
	var wanted: StringName = _model.get_tank_id()
	var definition: TankDefinition = _catalog.get_definition(wanted)
	if definition == null:
		push_warning(
			'RoomCorner: unknown tank id "%s"; showing the default tank "%s"' % [wanted, default_id]
		)
		definition = _catalog.get_definition(default_id)
	var tank: Node3D = _instantiate(definition)
	if tank == null and definition != null and definition.id != default_id:
		push_error(
			(
				'RoomCorner: tank "%s" has no loadable scene; showing the default tank "%s"'
				% [definition.id, default_id]
			)
		)
		definition = _catalog.get_definition(default_id)
		tank = _instantiate(definition)
	if tank == null:
		push_error(
			(
				(
					'RoomCorner: default tank "%s" has no loadable scene; '
					+ "showing the room without a tank"
				)
				% default_id
			)
		)
		return _catalog.get_definition(default_id)
	tank.name = &"Tank"
	tank.position = Vector3(0.0, CABINET_TOP_HEIGHT_M + definition.glass_thickness_m, 0.0)
	add_child(tank)
	_displayed_tank_id = definition.id
	var mount: Node3D = tank.get_node_or_null("lamp_mount") as Node3D
	if mount != null:
		_lamp.global_transform = mount.global_transform
	return definition


## The tank scene root, or null when the definition has no loadable Node3D scene.
func _instantiate(definition: TankDefinition) -> Node3D:
	if definition == null or definition.scene == null:
		return null
	var instance: Node = definition.scene.instantiate()
	if instance == null:
		return null
	if not instance is Node3D:
		instance.free()
		return null
	return instance as Node3D


func _frame_camera(definition: TankDefinition) -> void:
	var pivot: Vector3 = Vector3(0.0, CABINET_TOP_HEIGHT_M + NO_TANK_PIVOT_HEIGHT_M, 0.0)
	var exterior: Vector3 = NO_TANK_EXTERIOR_M
	if definition != null:
		exterior = definition.get_exterior_size_m()
		pivot = Vector3(
			0.0,
			(
				CABINET_TOP_HEIGHT_M
				+ definition.glass_thickness_m
				+ definition.water_line_height_m / 2.0
			),
			0.0
		)
	_camera_distance = CameraFraming.default_distance(
		exterior.x, exterior.z, CAMERA_HFOV_DEG, CAMERA_ELEVATION_DEG, CAMERA_WIDTH_SHARE
	)
	_camera.position = CameraFraming.camera_position(pivot, _camera_distance, CAMERA_ELEVATION_DEG)
	_camera.rotation = Vector3(-deg_to_rad(CAMERA_ELEVATION_DEG), 0.0, 0.0)


func _apply_projection() -> void:
	var size: Vector2 = get_viewport().get_visible_rect().size
	if size.y <= 0.0:
		return
	var aspect: float = size.x / size.y
	_camera.keep_aspect = CameraFraming.keep_aspect_for(aspect, CAMERA_MAX_KEEP_WIDTH_ASPECT)
	_camera.fov = CameraFraming.fov_for(aspect, CAMERA_HFOV_DEG, CAMERA_MAX_KEEP_WIDTH_ASPECT)
