class_name RoomCorner
extends Node3D
## The cozy room corner: room, cabinet, lamp, the displayed tank and the placeholder camera.
## Reads the model, never writes it. When the model changes the tank (or is reset), the room swaps
## tank, cabinet and lamp for the ones of the new tank and frames the default view again.

const CABINET_TOP_HEIGHT_M: float = 0.75
## Cabinet margin around the tank exterior on every side; the same rule as the cabinet generator.
const CABINET_MARGIN_M: float = 0.025
## Room origin to the inner face of the back wall, and the gap between wall and cabinet back.
const BACK_WALL_Z_M: float = -0.215
const WALL_GAP_M: float = 0.035
const CAMERA_HFOV_DEG: float = 50.0
const CAMERA_ELEVATION_DEG: float = 5.0
const CAMERA_WIDTH_SHARE: float = 0.85
const CAMERA_MAX_KEEP_WIDTH_ASPECT: float = 16.0 / 9.0
## ADR 0006: share of the half screen height kept free above and below the framed points.
const CAMERA_FIT_MARGIN: float = 0.02
const NO_TANK_PIVOT_HEIGHT_M: float = 0.2
const NO_TANK_EXTERIOR_M: Vector3 = Vector3(0.66, 0.36, 0.36)

var _model: AquariumModel = null
var _catalog: TankCatalog = null
var _displayed_tank_id: StringName = &""
var _camera_distance: float = 0.0

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
	_model.tank_changed.connect(_on_tank_changed)
	_model.model_reset.connect(_show_tank)
	_show_tank()
	get_viewport().size_changed.connect(_apply_projection)
	_apply_projection()


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
	var definition: TankDefinition = _resolve_tank()
	var stand_z: float = 0.0
	if definition != null:
		stand_z = _stand_z(definition)
	_add_furniture(&"Cabinet", definition, stand_z)
	_displayed_tank_id = &""
	var tank: Node3D = null
	if definition != null:
		tank = _instantiate(definition.scene)
	if tank != null:
		tank.name = &"Tank"
		tank.position = Vector3(0.0, CABINET_TOP_HEIGHT_M + definition.glass_thickness_m, stand_z)
		add_child(tank)
		_displayed_tank_id = definition.id
	var lamp: Node3D = _add_furniture(&"Lamp", definition, stand_z)
	var mount: Node3D = null
	if tank != null:
		mount = tank.get_node_or_null("lamp_mount") as Node3D
	if mount != null:
		lamp.global_transform = mount.global_transform
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
	var probe: Node3D = _instantiate(definition.scene)
	if probe == null:
		return false
	probe.free()
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
	_camera.position = CameraFraming.camera_position(pivot, _camera_distance, CAMERA_ELEVATION_DEG)
	_camera.rotation = Vector3(-deg_to_rad(CAMERA_ELEVATION_DEG), 0.0, 0.0)


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
