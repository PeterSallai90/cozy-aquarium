extends RefCounted
## Builds the room with the build camera for the #25 tests and drives it with fixed frame times
## (ADR 0008 rule 6): the helpers switch the camera's and the wall node's own processing off and
## call step(delta) themselves. The camera and the wall node are reached by node name and by method
## name (call), because BuildCamera and WallCutaway do not exist before the implementation.
##
## Fixed contract used by the #25 tests (technical plan on the issue):
## - The room has a direct child "BuildCamera" (Camera3D) with get_azimuth_deg, get_elevation_deg,
##   get_distance_m, get_pivot, the get_target_* getters, get_min_elevation_deg, is_dragging,
##   set_orbit(az, el, instant) and step(delta_s); azimuth is the unwrapped angle in degrees.
## - The room has a child "WallCutaway" with step(delta_s, camera_position), is_hidden_target(id),
##   get_alpha(id) and is_wall_rendered(id), ids &"back" and &"left".
## - Azimuth 0 is the front (+Z), 90 is right (+X), 270 is left (-X); E subtracts 45 degrees,
##   Q adds 45 degrees; elevation is positive above the pivot.

const Rig := preload("res://tests/helpers/room_rig.gd")
const Table := preload("res://tests/helpers/tank_table.gd")
const OrbitApi := preload("res://tests/helpers/orbit_api.gd")

const CAMERA := "BuildCamera"
const WALLS := "WallCutaway"
const FRAME_S: float = 1.0 / 60.0
const SETTLE_S: float = 3.0
const SIZE_16_9 := Vector2i(1280, 720)
const SIZE_4_3 := Vector2i(1024, 768)
const SIZE_21_9 := Vector2i(1680, 720)
const MAX_ELEVATION_DEG: float = 85.0
const ANGLE_TOLERANCE_DEG: float = 0.01
const LENGTH_TOLERANCE_M: float = 0.001
const CABINET_TOP_M: float = 0.75
const BACK_PLANE_Z_M: float = -0.215
const LEFT_PLANE_X_M: float = -0.85
const BAND_M: float = 0.05


## The room of `model` in its own SubViewport of the given size, added below `suite`. Returns
## {"viewport": SubViewport, "room": Node3D}; the helper auto_frees the viewport.
static func open(
	suite: GdUnitTestSuite, model: AquariumModel, size: Vector2i = SIZE_16_9
) -> Dictionary:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = size
	suite.add_child(viewport)
	suite.auto_free(viewport)
	var room: Node3D = Rig.instantiate(model, Rig.default_catalog())
	viewport.add_child(room)
	await suite.get_tree().process_frame
	freeze(room)
	return {"viewport": viewport, "room": room}


## Stops the own processing of the camera and the wall node, so the tests drive them.
static func freeze(room: Node) -> void:
	var camera: Node = camera_of(room)
	if camera != null:
		camera.set_process(false)
	var walls: Node = walls_of(room)
	if walls != null:
		walls.set_process(false)


static func camera_of(room: Node) -> Camera3D:
	return room.get_node_or_null(CAMERA) as Camera3D


static func walls_of(room: Node) -> Node:
	return room.get_node_or_null(WALLS)


# --- reading the camera ---


static func az(camera: Node) -> float:
	return camera.call("get_azimuth_deg")


static func el(camera: Node) -> float:
	return camera.call("get_elevation_deg")


static func dist(camera: Node) -> float:
	return camera.call("get_distance_m")


static func pivot(camera: Node) -> Vector3:
	return camera.call("get_pivot")


static func t_az(camera: Node) -> float:
	return camera.call("get_target_azimuth_deg")


static func t_el(camera: Node) -> float:
	return camera.call("get_target_elevation_deg")


static func t_dist(camera: Node) -> float:
	return camera.call("get_target_distance_m")


static func t_pivot(camera: Node) -> Vector3:
	return camera.call("get_target_pivot")


static func dragging(camera: Node) -> bool:
	return camera.call("is_dragging")


## The lowest allowed elevation for the tank at the camera's target distance, from the helper.
static func min_el(camera: Node, id: StringName) -> float:
	var above: float = Table.glass(id) + Table.water_line(id) / 2.0
	return OrbitApi.min_elevation(
		OrbitApi.setting("min_elevation_limit_deg"), above, t_dist(camera)
	)


# --- driving the camera ---


static func step(camera: Node, seconds: float, frame_s: float = FRAME_S) -> void:
	var left: float = seconds
	while left > 0.0:
		var dt: float = minf(frame_s, left)
		camera.call("step", dt)
		left -= dt


static func settle(camera: Node) -> void:
	step(camera, SETTLE_S)


static func set_orbit(camera: Node, azimuth: float, elevation: float, instant: bool) -> void:
	camera.call("set_orbit", azimuth, elevation, instant)
	if instant:
		camera.call("step", 0.0)


## Instant pose, then the walls follow the camera until the fade has settled.
static func pose(room: Node, azimuth: float, elevation: float) -> void:
	var camera: Camera3D = camera_of(room)
	set_orbit(camera, azimuth, elevation, true)
	step_walls(room, SETTLE_S)


static func step_walls(room: Node, seconds: float, frame_s: float = FRAME_S) -> void:
	var camera: Camera3D = camera_of(room)
	var walls: Node = walls_of(room)
	var left: float = seconds
	while left > 0.0:
		var dt: float = minf(frame_s, left)
		walls.call("step", dt, camera.global_position)
		left -= dt


# --- synthetic input, pushed through the viewport like the engine would ---


static func button(
	viewport: Viewport, index: MouseButton, pressed: bool, at: Vector2 = Vector2(100.0, 100.0)
) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	event.position = at
	event.global_position = at
	if pressed:
		event.button_mask = 1 << (index - 1)
	viewport.push_input(event)


static func motion(
	viewport: Viewport,
	relative: Vector2,
	at: Vector2 = Vector2(100.0, 100.0),
	mask: int = MOUSE_BUTTON_MASK_RIGHT
) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.relative = relative
	event.screen_relative = relative
	event.button_mask = mask
	viewport.push_input(event)


static func right_press(viewport: Viewport, at: Vector2 = Vector2(100.0, 100.0)) -> void:
	button(viewport, MOUSE_BUTTON_RIGHT, true, at)


static func right_release(viewport: Viewport, at: Vector2 = Vector2(100.0, 100.0)) -> void:
	button(viewport, MOUSE_BUTTON_RIGHT, false, at)


## A complete right-drag by `relative` pixels in one motion event.
static func drag(
	viewport: Viewport, relative: Vector2, at: Vector2 = Vector2(100.0, 100.0)
) -> void:
	right_press(viewport, at)
	motion(viewport, relative, at + relative)
	right_release(viewport, at + relative)


static func key(
	viewport: Viewport,
	keycode: Key,
	pressed: bool,
	echo: bool = false,
	modifiers: int = 0,
	unicode: int = 0
) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.unicode = unicode
	event.pressed = pressed
	event.echo = echo
	event.ctrl_pressed = (modifiers & KEY_MASK_CTRL) != 0
	event.shift_pressed = (modifiers & KEY_MASK_SHIFT) != 0
	event.alt_pressed = (modifiers & KEY_MASK_ALT) != 0
	event.meta_pressed = (modifiers & KEY_MASK_META) != 0
	viewport.push_input(event)


static func tap(viewport: Viewport, keycode: Key, modifiers: int = 0) -> void:
	key(viewport, keycode, true, false, modifiers)
	key(viewport, keycode, false, false, modifiers)


# --- geometry ---


## Absolute difference of two headings in degrees, wrapped to 0..180.
static func heading_gap(first: float, second: float) -> float:
	return absf(wrapf(first - second, -180.0, 180.0))


## Why the camera basis is not a proper look-at basis: orthonormal axes, up vector up, forward
## (-Z) toward `target`. Empty when it is fine.
static func basis_failures(camera: Camera3D, target: Vector3) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	var basis: Basis = camera.global_transform.basis
	for axis: Vector3 in [basis.x, basis.y, basis.z]:
		if absf(axis.length() - 1.0) > 0.001:
			failures.append("an axis is not unit length: %s" % basis)
			break
	if (
		absf(basis.x.dot(basis.y)) > 0.001
		or absf(basis.y.dot(basis.z)) > 0.001
		or absf(basis.x.dot(basis.z)) > 0.001
	):
		failures.append("the axes are not orthogonal: %s" % basis)
	if basis.y.y <= 0.0:
		failures.append("the up vector points down: %s" % basis.y)
	var wanted: Vector3 = (target - camera.global_position).normalized()
	if (-basis.z).dot(wanted) < 0.9999:
		failures.append("the camera does not look at %s: forward %s" % [target, -basis.z])
	return failures
