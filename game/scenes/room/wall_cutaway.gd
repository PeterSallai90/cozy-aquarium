class_name WallCutaway
extends Node
## Hides a room wall while the active camera is behind its plane, with a short fade (ADR 0008
## rule 6: the work happens in step()). It follows the viewport camera and touches nothing else.

const BACK: StringName = &"back"
const LEFT: StringName = &"left"
const SETTINGS_PATH: String = "res://systems/camera/camera_settings.tres"
## Used when no camera is active yet: well in front of both walls.
const FALLBACK_CAMERA_POSITION: Vector3 = Vector3(0.0, 1.0, 10.0)

@export var settings: CameraSettings = null

## Wall id to {"nodes": Array[GeometryInstance3D], "plane": Plane, "hidden": bool, "alpha": float}.
var _walls: Dictionary[StringName, Dictionary] = {}


## True when a wall that was hidden (or shown) stays so: the state flips only beyond half the band
## on either side of the wall plane.
static func next_hidden(was_hidden: bool, signed_distance_m: float, band_m: float) -> bool:
	if signed_distance_m < -band_m / 2.0:
		return true
	if signed_distance_m > band_m / 2.0:
		return false
	return was_hidden


func _ready() -> void:
	_ensure_settings()
	# Runs after the camera moved in the same frame.
	process_priority = 100


func _process(delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null:
		step(delta, camera.global_position)


## Registers a wall: its meshes and its plane in global space, normal pointing into the room. The
## state follows the current camera position at once, without a fade.
func add_wall(id: StringName, nodes: Array[GeometryInstance3D], plane: Plane) -> void:
	_ensure_settings()
	var camera_position: Vector3 = _current_camera_position()
	var hidden: bool = next_hidden(
		false, plane.distance_to(camera_position), settings.wall_hysteresis_band_m
	)
	var wall: Dictionary = {
		"nodes": nodes, "plane": plane, "hidden": hidden, "alpha": 0.0 if hidden else 1.0
	}
	_walls[id] = wall
	_apply(wall)


## Updates every wall from the actual camera position and moves its alpha toward the target.
func step(delta_s: float, camera_position: Vector3) -> void:
	_ensure_settings()
	var fade_time: float = settings.wall_fade_time_s
	for id: StringName in _walls:
		var wall: Dictionary = _walls[id]
		var plane: Plane = wall["plane"]
		wall["hidden"] = next_hidden(
			wall["hidden"], plane.distance_to(camera_position), settings.wall_hysteresis_band_m
		)
		var goal: float = 0.0 if wall["hidden"] else 1.0
		if fade_time <= 0.0:
			wall["alpha"] = goal
		else:
			wall["alpha"] = move_toward(wall["alpha"], goal, delta_s / fade_time)
		_apply(wall)


func is_hidden_target(id: StringName) -> bool:
	return _walls.has(id) and _walls[id]["hidden"]


func get_alpha(id: StringName) -> float:
	return _walls[id]["alpha"] if _walls.has(id) else 1.0


func is_wall_rendered(id: StringName) -> bool:
	return _walls.has(id) and get_alpha(id) > 0.0


func _apply(wall: Dictionary) -> void:
	var alpha: float = wall["alpha"]
	var nodes: Array[GeometryInstance3D] = wall["nodes"]
	for node: GeometryInstance3D in nodes:
		node.visible = alpha > 0.0
		node.transparency = 0.0 if alpha >= 1.0 else 1.0 - alpha


func _current_camera_position() -> Vector3:
	if is_inside_tree():
		var camera: Camera3D = get_viewport().get_camera_3d()
		if camera != null:
			return camera.global_position
	return FALLBACK_CAMERA_POSITION


func _ensure_settings() -> void:
	if settings == null:
		settings = load(SETTINGS_PATH) as CameraSettings
