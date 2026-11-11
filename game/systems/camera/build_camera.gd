class_name BuildCamera
extends Camera3D
## The build camera: orbits a pivot with right-drag and Q/E/R/F, zooms with the wheel, pans with
## the middle button and goes home with Home, eased by damping (ADR 0008). It is kept out of the
## solids the room gives it (ADR 0009). The room gives it the pivot and the default distance; it
## never touches the model.

const SETTINGS_PATH: String = "res://systems/camera/camera_settings.tres"
const ACTION_DRAG: StringName = &"camera_orbit_drag"
const ACTION_LEFT: StringName = &"camera_orbit_left"
const ACTION_RIGHT: StringName = &"camera_orbit_right"
const ACTION_UP: StringName = &"camera_elevation_up"
const ACTION_DOWN: StringName = &"camera_elevation_down"
const ACTION_ZOOM_IN: StringName = &"camera_zoom_in"
const ACTION_ZOOM_OUT: StringName = &"camera_zoom_out"
const ACTION_PAN: StringName = &"camera_pan_drag"
const ACTION_HOME: StringName = &"camera_home"
const KEY_ACTIONS: Array[StringName] = [ACTION_LEFT, ACTION_RIGHT, ACTION_UP, ACTION_DOWN]

const PIN_TOLERANCE_DEG: float = 0.0001
const HELD_EPSILON_M: float = 0.000001
const PLANE_TOLERANCE_M: float = 0.000001

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
var _panning: bool = false
var _window_focused: bool = true
var _default_distance: float = 1.0
var _home_pivot: Vector3 = Vector3.ZERO
var _start_elevation: float = 0.0
var _has_bounds: bool = false
var _pan_box: AABB = AABB()
var _solids: Array[AABB] = []
## The distance the camera is placed at: the eased distance, pushed out of the solids.
var _shown_distance: float = 1.0
var _was_held: bool = false
## Action name to the frame time collected toward the next repeat step.
var _held: Dictionary[StringName, float] = {}


func _ready() -> void:
	if settings == null:
		settings = load(SETTINGS_PATH) as CameraSettings
	near = settings.camera_near_m
	set_process_input(false)
	_place()


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
	_default_distance = default_distance_m
	_home_pivot = _clamp_to_box(pivot)
	_start_elevation = start_elevation_deg
	_target_pivot = _home_pivot
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


## Called by the room before set_framing: the box the pivot may move in and the solids (room
## frame) the camera keeps out of. The target pivot is clamped into the new box.
func set_bounds(pan_box: AABB, solids: Array[AABB]) -> void:
	_pan_box = pan_box
	_has_bounds = true
	_solids = solids.duplicate()
	_target_pivot = _clamp_to_box(_target_pivot)
	_home_pivot = _clamp_to_box(_home_pivot)
	_clamp_target_elevation()


## Eases every part of the view back to the front view: nearest front azimuth, start elevation,
## default distance and the framing pivot.
func go_home() -> void:
	_target_azimuth = CameraMoves.home_azimuth_deg(_target_azimuth)
	_target_elevation = _start_elevation
	_target_distance = _default_distance
	_target_pivot = _home_pivot
	_clamp_target_elevation()


## Sets the target distance, kept inside the zoom limits. Instant skips the easing.
func set_target_distance_m(distance_m: float, instant: bool = false) -> void:
	_target_distance = _clamp_distance(distance_m)
	_clamp_target_elevation()
	if instant:
		_snap_to_targets()


## Sets the target pivot, kept inside the pan box. Instant skips the easing.
func set_target_pivot(pivot: Vector3, instant: bool = false) -> void:
	_target_pivot = _clamp_to_box(pivot)
	_clamp_target_elevation()
	if instant:
		_snap_to_targets()


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


func is_panning() -> bool:
	return _panning


## The distance the camera is placed at: the eased distance, pushed out of the solids.
func get_held_distance_m() -> float:
	return _shown_distance


func get_default_distance_m() -> float:
	return _default_distance


## Key repeat, damping and the transform write for one frame.
func step(delta_s: float) -> void:
	if (_dragging or _panning or not _held.is_empty()) and WorldInput.is_blocked(get_tree()):
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
	_place(factor)


## While the window is unfocused the wheel, the pan start and Home are ignored; the #25 orbit
## drag and keys keep working (their tests pin that).
func _unhandled_input(event: InputEvent) -> void:
	if WorldInput.is_blocked(get_tree()):
		return
	var key: InputEventKey = event as InputEventKey
	if key != null:
		_handle_key_press(key)
		return
	if not event is InputEventMouseButton:
		return
	if event.is_action_pressed(ACTION_DRAG):
		_dragging = true
		set_process_input(true)
	elif not _window_focused or WorldInput.is_text_focused(get_viewport()):
		return
	elif event.is_action_pressed(ACTION_PAN):
		_panning = true
		set_process_input(true)
	elif event.is_action_pressed(ACTION_ZOOM_IN):
		_zoom(event as InputEventMouseButton, settings.zoom_step_factor)
	elif event.is_action_pressed(ACTION_ZOOM_OUT):
		_zoom(event as InputEventMouseButton, 1.0 / settings.zoom_step_factor)


## Reads the running gestures before the GUI; events stay unhandled.
func _input(event: InputEvent) -> void:
	if WorldInput.is_blocked(get_tree()):
		_end_gestures()
		return
	if _dragging or _panning:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		if motion != null:
			if _dragging:
				_drag_by(motion.relative)
			if _panning:
				_pan_by(motion.relative)
		elif event is InputEventMouseButton:
			if event.is_action_released(ACTION_DRAG):
				_dragging = false
			if event.is_action_released(ACTION_PAN):
				_panning = false
	if event is InputEventKey and not event.is_pressed():
		for action: StringName in _held.keys():
			if event.is_action_released(action):
				_held.erase(action)
	if not _dragging and not _panning and _held.is_empty():
		set_process_input(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_window_focused = false
		_end_gestures()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_window_focused = true


func _end_gestures() -> void:
	_dragging = false
	_panning = false
	_held.clear()
	set_process_input(false)


func _handle_key_press(key: InputEventKey) -> void:
	if not key.pressed or key.echo:
		return
	if key.shift_pressed or key.ctrl_pressed or key.alt_pressed or key.meta_pressed:
		return
	if key.is_action_pressed(ACTION_HOME, false, true):
		if _window_focused:
			go_home()
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


func _zoom(event: InputEventMouseButton, step_factor: float) -> void:
	if event.ctrl_pressed or event.alt_pressed or event.shift_pressed or event.meta_pressed:
		return
	if WorldInput.is_over_stop_control(get_viewport(), event.position):
		return
	var multiplier: float = CameraMoves.zoom_multiplier(step_factor, event.factor)
	_target_distance = _clamp_distance(_target_distance * multiplier)
	_clamp_target_elevation()


func _pan_by(relative: Vector2) -> void:
	var size: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = size.x / size.y if size.y > 0.0 else 1.0
	var offset: Vector3 = CameraMoves.pan_offset(
		relative,
		size.y,
		_target_distance,
		CameraMoves.tan_half_vertical_fov(fov, keep_aspect, aspect),
		settings.pan_speed,
		_target_azimuth,
		_target_elevation
	)
	_target_pivot = _clamp_to_box(_target_pivot + offset)
	_clamp_target_elevation()


func _clamp_distance(distance_m: float) -> float:
	return CameraMoves.clamp_distance(
		distance_m, _default_distance, settings.zoom_min_factor, settings.zoom_max_factor
	)


func _clamp_to_box(pivot: Vector3) -> Vector3:
	if not _has_bounds:
		return pivot
	return CameraMoves.clamp_pivot(pivot, _pan_box)


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
	_place()


## Places the camera at the eased pose, pushed out of the solids at every frame, so it is never
## inside one. A push-out is immediate; a release from a held frame eases (ADR 0009 rule 5).
## Below the cabinet top plane only the shown elevation is raised.
func _place(factor: float = 1.0) -> void:
	if not is_inside_tree():
		return
	var margin: float = settings.collision_margin_m
	var shown_elevation: float = _elevation
	var direction: Vector3 = OrbitMath.offset(_azimuth, shown_elevation, 1.0)
	var held: float = CameraCollision.held_distance(_solids, margin, _pivot, direction, _distance)
	var plane_y: float = -_above_offset
	if _pivot.y + direction.y * held < plane_y - PLANE_TOLERANCE_M:
		shown_elevation = maxf(
			_elevation,
			CameraCollision.lowest_held_elevation_deg(_solids, margin, _pivot, _azimuth, plane_y)
		)
		direction = OrbitMath.offset(_azimuth, shown_elevation, 1.0)
		held = CameraCollision.held_distance(_solids, margin, _pivot, direction, _distance)
	if _was_held and factor < 1.0 and held < _shown_distance:
		# The obstruction ended: ease out of the hold, never into a solid.
		var eased: float = lerpf(_shown_distance, held, factor)
		held = CameraCollision.held_distance(_solids, margin, _pivot, direction, eased)
	_was_held = held > _distance + HELD_EPSILON_M
	_shown_distance = held
	global_position = _pivot + direction * _shown_distance
	global_rotation = OrbitMath.camera_rotation(_azimuth, shown_elevation)
