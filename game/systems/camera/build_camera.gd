class_name BuildCamera
extends Camera3D
## The build camera: orbits a pivot with right-drag and Q/E/R/F, eased by damping (ADR 0008).
## The room gives it the pivot and the default distance; it never touches the model.

const SETTINGS_PATH: String = "res://systems/camera/camera_settings.tres"
const ACTION_DRAG: StringName = &"camera_orbit_drag"
const ACTION_LEFT: StringName = &"camera_orbit_left"
const ACTION_RIGHT: StringName = &"camera_orbit_right"
const ACTION_UP: StringName = &"camera_elevation_up"
const ACTION_DOWN: StringName = &"camera_elevation_down"
const KEY_ACTIONS: Array[StringName] = [ACTION_LEFT, ACTION_RIGHT, ACTION_UP, ACTION_DOWN]

const PIN_TOLERANCE_DEG: float = 0.0001

@export var settings: CameraSettings = null

var _framed: bool = false
var _azimuth: float = 0.0
var _elevation: float = 0.0
var _distance: float = 1.0
var _pivot: Vector3 = Vector3.ZERO
var _target_azimuth: float = 0.0
var _target_elevation: float = 0.0
var _target_distance: float = 1.0
var _target_pivot: Vector3 = Vector3.ZERO
## Pivot height above the cabinet top minus the pivot height: constant for one framing.
var _above_offset: float = 0.0
var _target_above_offset: float = 0.0
var _dragging: bool = false
## Action name to the frame time collected toward the next repeat step.
var _held: Dictionary[StringName, float] = {}


func _ready() -> void:
	if settings == null:
		settings = load(SETTINGS_PATH) as CameraSettings
	set_process_input(false)
	_write_transform()


func _process(delta: float) -> void:
	step(delta)


## Called by the room. The first call snaps to the front at the start elevation; later calls keep
## the target azimuth, set the new pivot and distance and ease to them.
func set_framing(
	pivot: Vector3,
	default_distance_m: float,
	pivot_above_cabinet_m: float,
	start_elevation_deg: float
) -> void:
	# A camera held at the lowest elevation stays at the lowest elevation of the new tank.
	var at_lowest: bool = (
		_framed and _target_elevation <= get_min_elevation_deg() + PIN_TOLERANCE_DEG
	)
	_target_pivot = pivot
	_target_distance = default_distance_m
	_target_above_offset = pivot_above_cabinet_m - pivot.y
	if not _framed:
		_framed = true
		_azimuth = 0.0
		_target_azimuth = 0.0
		_target_elevation = start_elevation_deg
		_clamp_target_elevation()
		_snap_to_targets()
		return
	if at_lowest:
		_target_elevation = -INF
	_clamp_target_elevation()


## Sets the target pose; the elevation is clamped. Instant skips the easing.
func set_orbit(azimuth_deg: float, elevation_deg: float, instant: bool = false) -> void:
	_target_azimuth = azimuth_deg
	_target_elevation = elevation_deg
	_clamp_target_elevation()
	if instant:
		_snap_to_targets()


func get_azimuth_deg() -> float:
	return _azimuth


func get_elevation_deg() -> float:
	return _elevation


func get_distance_m() -> float:
	return _distance


func get_pivot() -> Vector3:
	return _pivot


func get_target_azimuth_deg() -> float:
	return _target_azimuth


func get_target_elevation_deg() -> float:
	return _target_elevation


func get_target_distance_m() -> float:
	return _target_distance


func get_target_pivot() -> Vector3:
	return _target_pivot


## The lowest allowed target elevation for the current target pivot and distance.
func get_min_elevation_deg() -> float:
	return _min_elevation(_target_pivot.y + _target_above_offset, _target_distance)


func is_dragging() -> bool:
	return _dragging


## Key repeat, damping and the transform write for one frame.
func step(delta_s: float) -> void:
	if (_dragging or not _held.is_empty()) and WorldInput.is_blocked(get_tree()):
		_end_gestures()
	_repeat_keys(delta_s)
	var factor: float = OrbitMath.damp_factor(delta_s, settings.damping_time_s)
	_azimuth = lerpf(_azimuth, _target_azimuth, factor)
	_elevation = lerpf(_elevation, _target_elevation, factor)
	_distance = lerpf(_distance, _target_distance, factor)
	_pivot = _pivot.lerp(_target_pivot, factor)
	_above_offset = lerpf(_above_offset, _target_above_offset, factor)
	_elevation = clampf(
		_elevation, _min_elevation(_pivot.y + _above_offset, _distance), settings.max_elevation_deg
	)
	_write_transform()


func _unhandled_input(event: InputEvent) -> void:
	if WorldInput.is_blocked(get_tree()):
		return
	var key: InputEventKey = event as InputEventKey
	if key != null:
		_handle_key_press(key)
	elif event.is_action_pressed(ACTION_DRAG) and event is InputEventMouseButton:
		_dragging = true
		set_process_input(true)


## Reads the running gestures before the GUI; events stay unhandled.
func _input(event: InputEvent) -> void:
	if WorldInput.is_blocked(get_tree()):
		_end_gestures()
		return
	if _dragging:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		if motion != null:
			_drag_by(motion.relative)
		elif event is InputEventMouseButton and event.is_action_released(ACTION_DRAG):
			_dragging = false
	if event is InputEventKey and not event.is_pressed():
		for action: StringName in _held.keys():
			if event.is_action_released(action):
				_held.erase(action)
	if not _dragging and _held.is_empty():
		set_process_input(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_end_gestures()


func _end_gestures() -> void:
	_dragging = false
	_held.clear()
	set_process_input(false)


func _handle_key_press(key: InputEventKey) -> void:
	if not key.pressed or key.echo:
		return
	if key.shift_pressed or key.ctrl_pressed or key.alt_pressed or key.meta_pressed:
		return
	for action: StringName in KEY_ACTIONS:
		if key.is_action_pressed(action, false, true):
			_apply_key_action(action)
			_held[action] = 0.0
			set_process_input(true)
			return


func _apply_key_action(action: StringName) -> void:
	match action:
		ACTION_LEFT:
			_target_azimuth += settings.azimuth_step_deg
		ACTION_RIGHT:
			_target_azimuth -= settings.azimuth_step_deg
		ACTION_UP:
			_target_elevation += settings.elevation_step_deg
		ACTION_DOWN:
			_target_elevation -= settings.elevation_step_deg
	_clamp_target_elevation()


func _repeat_keys(delta_s: float) -> void:
	var capped: float = minf(delta_s, settings.max_frame_time_s)
	for action: StringName in _held.keys():
		var collected: float = _held[action] + capped
		if collected >= settings.key_repeat_interval_s:
			_apply_key_action(action)
			collected -= settings.key_repeat_interval_s
		_held[action] = collected


func _drag_by(relative: Vector2) -> void:
	var height: float = get_viewport().get_visible_rect().size.y
	var per_height: float = settings.drag_deg_per_viewport_height
	_target_azimuth += OrbitMath.drag_deg(relative.x, height, per_height)
	_target_elevation -= OrbitMath.drag_deg(relative.y, height, per_height)
	_clamp_target_elevation()


func _min_elevation(pivot_above_cabinet_m: float, distance_m: float) -> float:
	return OrbitMath.min_elevation_deg(
		settings.min_elevation_limit_deg, pivot_above_cabinet_m, distance_m
	)


func _clamp_target_elevation() -> void:
	_target_elevation = clampf(
		_target_elevation, get_min_elevation_deg(), settings.max_elevation_deg
	)


func _snap_to_targets() -> void:
	_azimuth = _target_azimuth
	_elevation = _target_elevation
	_distance = _target_distance
	_pivot = _target_pivot
	_above_offset = _target_above_offset
	_write_transform()


func _write_transform() -> void:
	if not is_inside_tree():
		return
	global_position = _pivot + OrbitMath.offset(_azimuth, _elevation, _distance)
	global_rotation = OrbitMath.camera_rotation(_azimuth, _elevation)
