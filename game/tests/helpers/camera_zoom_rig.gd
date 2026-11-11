extends RefCounted
## Shared code of the #26 tests (zoom, pan, Home, collision). The new helper classes (CameraMoves,
## CameraCollision, CameraSolids) do not exist before the implementation, and a direct reference
## to a missing class is a parse error that aborts the whole run, so they are reached through
## load(); every function returns a stand-in that no assertion accepts while the script is
## missing. The new BuildCamera methods are called by name behind a has_method guard.
##
## The collision oracle is built here from the catalog numbers and from the lamp scene, not from
## CameraSolids: the tank box (exterior footprint, cabinet top to rim top), the cabinet box
## (exterior footprint plus the cabinet margin, floor to cabinet top) and one box per visible lamp
## mesh. "Solid plus margin" is the box grown by the margin on every face (ADR 0009 rule 2); a
## point on the grown boundary is outside.

const Cam := preload("res://tests/helpers/camera_rig.gd")
const Api := preload("res://tests/helpers/late_api.gd")
const Rig := preload("res://tests/helpers/room_rig.gd")
const Table := preload("res://tests/helpers/tank_table.gd")
const Glb := preload("res://tests/helpers/glb_mesh_checks.gd")
const OrbitApi := preload("res://tests/helpers/orbit_api.gd")

const MOVES_PATH := "res://systems/camera/camera_moves.gd"
const COLLISION_PATH := "res://systems/camera/camera_collision.gd"
const SOLIDS_PATH := "res://systems/camera/camera_solids.gd"
const MISSING_NUMBER: float = Api.MISSING_NUMBER
const NEW_METHODS: Array[String] = [
	"set_bounds",
	"go_home",
	"set_target_distance_m",
	"set_target_pivot",
	"get_held_distance_m",
	"get_default_distance_m",
	"is_panning",
]
const HUGE: float = 1000000.0
const FRAME_S: float = Cam.FRAME_S
const LENGTH_M: float = Cam.LENGTH_TOLERANCE_M
const ANGLE_DEG: float = Cam.ANGLE_TOLERANCE_DEG
const CABINET_TOP_M: float = Table.CABINET_TOP_M
const HORIZONTAL_FOV_DEG: float = 50.0
const HELD_EPSILON_M: float = 0.0005
const STEADY := "steady"
const RELEASE := "release"
const NEITHER := "neither"
const FRAME_CLASS_TOLERANCE_M: float = 0.001
const RELEASE_RAISE_LIMIT_DEG: float = 1.0
const RELEASE_RUN_LIMIT_FRAMES: int = 30
const MASK_ALL: Array[int] = [KEY_MASK_CTRL, KEY_MASK_ALT, KEY_MASK_SHIFT, KEY_MASK_META]

# --- late-bound helper classes ---


static func _script(path: String) -> GDScript:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as GDScript


static func moves_exist() -> bool:
	return _script(MOVES_PATH) != null


static func _call_number(path: String, method: String, args: Array) -> float:
	var script: GDScript = _script(path)
	if script == null:
		return MISSING_NUMBER
	return script.callv(method, args)


static func _call_variant(path: String, method: String, args: Array, fallback: Variant) -> Variant:
	var script: GDScript = _script(path)
	if script == null:
		return fallback
	return script.callv(method, args)


static func zoom_multiplier(step_factor: float, event_factor: float) -> float:
	return _call_number(MOVES_PATH, "zoom_multiplier", [step_factor, event_factor])


static func clamp_distance(
	distance_m: float, default_m: float, min_factor: float, max_factor: float
) -> float:
	return _call_number(
		MOVES_PATH, "clamp_distance", [distance_m, default_m, min_factor, max_factor]
	)


static func tan_half_vfov(fov_deg: float, keep: Camera3D.KeepAspect, aspect: float) -> float:
	return _call_number(MOVES_PATH, "tan_half_vertical_fov", [fov_deg, keep, aspect])


static func pan_offset(
	relative_px: Vector2,
	height_px: float,
	distance_m: float,
	tan_half: float,
	speed: float,
	azimuth_deg: float,
	elevation_deg: float
) -> Vector3:
	return _call_variant(
		MOVES_PATH,
		"pan_offset",
		[relative_px, height_px, distance_m, tan_half, speed, azimuth_deg, elevation_deg],
		Vector3.ONE * MISSING_NUMBER
	)


static func clamp_pivot(pivot: Vector3, box: AABB) -> Vector3:
	return _call_variant(MOVES_PATH, "clamp_pivot", [pivot, box], Vector3.ONE * MISSING_NUMBER)


static func home_azimuth(azimuth_deg: float) -> float:
	return _call_number(MOVES_PATH, "home_azimuth_deg", [azimuth_deg])


static func is_clear(boxes: Array[AABB], margin_m: float, point: Vector3) -> Variant:
	return _call_variant(COLLISION_PATH, "is_clear", [boxes, margin_m, point], null)


static func line_interval(origin: Vector3, direction: Vector3, box: AABB) -> Vector2:
	return _call_variant(
		COLLISION_PATH, "line_interval", [origin, direction, box], Vector2.ONE * MISSING_NUMBER
	)


static func held_distance(
	boxes: Array[AABB], margin_m: float, pivot: Vector3, direction: Vector3, requested_m: float
) -> float:
	return _call_number(
		COLLISION_PATH, "held_distance", [boxes, margin_m, pivot, direction, requested_m]
	)


static func lowest_held_elevation(
	boxes: Array[AABB], margin_m: float, pivot: Vector3, azimuth_deg: float, plane_y: float
) -> float:
	return _call_number(
		COLLISION_PATH, "lowest_held_elevation_deg", [boxes, margin_m, pivot, azimuth_deg, plane_y]
	)


static func solids_tank_box(definition: Resource, cabinet_top_y: float, stand: float) -> Variant:
	return _call_variant(SOLIDS_PATH, "tank_box", [definition, cabinet_top_y, stand], null)


static func solids_cabinet_box(
	definition: Resource, cabinet_top_y: float, margin_m: float, stand: float
) -> Variant:
	return _call_variant(
		SOLIDS_PATH, "cabinet_box", [definition, cabinet_top_y, margin_m, stand], null
	)


static func solids_pan_box(
	definition: Resource, cabinet_top_y: float, stand: float, pivot: Vector3
) -> Variant:
	return _call_variant(SOLIDS_PATH, "pan_box", [definition, cabinet_top_y, stand, pivot], null)


static func solids_lamp_boxes(lamp: Node3D, room_frame: Transform3D) -> Variant:
	return _call_variant(SOLIDS_PATH, "lamp_boxes", [lamp, room_frame], null)


# --- settings ---


static func setting(wanted: String) -> float:
	return OrbitApi.setting(wanted)


static func margin() -> float:
	return setting("collision_margin_m")


static func default_start_elevation() -> float:
	return Api.room_constant("CAMERA_ELEVATION_DEG")


# --- opening a room ---


## True when the camera has every method of the #26 plan; asserts it.
static func require_api(suite: GdUnitTestSuite, camera: Node) -> bool:
	var missing: PackedStringArray = PackedStringArray()
	for method: String in NEW_METHODS:
		if camera == null or not camera.has_method(method):
			missing.append(method)
	(
		suite
		. assert_bool(missing.is_empty())
		. override_failure_message("BuildCamera is missing: %s" % ", ".join(missing))
		. is_true()
	)
	return missing.is_empty()


## The room of `model` with a frozen camera. Returns {"ok", "viewport", "room", "camera",
## "default_distance", "home_pivot", "id"}; ok is false when the camera lacks the new API.
static func open(
	suite: GdUnitTestSuite,
	model: AquariumModel,
	size: Vector2i = Cam.SIZE_16_9,
	id: StringName = &""
) -> Dictionary:
	var rig: Dictionary = await Cam.open(suite, model, size)
	var camera: Camera3D = Cam.camera_of(rig["room"])
	(
		suite
		. assert_bool(camera != null)
		. override_failure_message("the room has no BuildCamera child (Camera3D)")
		. is_true()
	)
	var ok: bool = camera != null and require_api(suite, camera)
	var result: Dictionary = {
		"ok": ok,
		"viewport": rig["viewport"],
		"room": rig["room"],
		"camera": camera,
		"id": id,
		"default_distance": 0.0,
		"home_pivot": Vector3.ZERO,
	}
	if camera != null:
		result["default_distance"] = Cam.t_dist(camera)
		result["home_pivot"] = Cam.t_pivot(camera)
	return result


static func open_tank(
	suite: GdUnitTestSuite, id: StringName, size: Vector2i = Cam.SIZE_16_9
) -> Dictionary:
	return await open(suite, Rig.model_with(id), size, id)


# --- the new camera API, by name ---


static func set_distance(camera: Node, distance_m: float, instant: bool = true) -> void:
	camera.call("set_target_distance_m", distance_m, instant)


static func set_pivot(camera: Node, pivot: Vector3, instant: bool = true) -> void:
	camera.call("set_target_pivot", pivot, instant)


static func held_dist(camera: Node) -> float:
	return camera.call("get_held_distance_m")


static func default_dist(camera: Node) -> float:
	return camera.call("get_default_distance_m")


static func panning(camera: Node) -> bool:
	return camera.call("is_panning")


static func home(camera: Node) -> void:
	camera.call("go_home")


## Poses the camera at once: pivot, distance, then orbit (the elevation is clamped), then one zero
## frame so that the placement runs. The elevation -90 means "the lowest allowed".
static func pose(
	camera: Node, azimuth_deg: float, elevation_deg: float, distance_m: float, pivot: Vector3
) -> void:
	set_pivot(camera, pivot, true)
	set_distance(camera, distance_m, true)
	Cam.set_orbit(camera, azimuth_deg, elevation_deg, true)
	camera.call("step", 0.0)


static func zoom_in_distance(default_m: float) -> float:
	return default_m * setting("zoom_min_factor")


static func zoom_out_distance(default_m: float) -> float:
	return default_m * setting("zoom_max_factor")


# --- synthetic input ---


## One wheel notch (press and release, like the engine sends it).
static func wheel(
	viewport: Viewport,
	up: bool,
	factor: float = 1.0,
	modifiers: int = 0,
	at: Vector2 = Vector2(100.0, 100.0)
) -> void:
	var index: MouseButton = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = index
		event.pressed = pressed
		event.factor = factor
		event.position = at
		event.global_position = at
		event.ctrl_pressed = (modifiers & KEY_MASK_CTRL) != 0
		event.shift_pressed = (modifiers & KEY_MASK_SHIFT) != 0
		event.alt_pressed = (modifiers & KEY_MASK_ALT) != 0
		event.meta_pressed = (modifiers & KEY_MASK_META) != 0
		viewport.push_input(event)


static func middle_press(viewport: Viewport, at: Vector2 = Vector2(100.0, 100.0)) -> void:
	Cam.button(viewport, MOUSE_BUTTON_MIDDLE, true, at)


static func middle_release(viewport: Viewport, at: Vector2 = Vector2(100.0, 100.0)) -> void:
	Cam.button(viewport, MOUSE_BUTTON_MIDDLE, false, at)


static func middle_motion(
	viewport: Viewport, relative: Vector2, at: Vector2 = Vector2(100.0, 100.0)
) -> void:
	Cam.motion(viewport, relative, at, MOUSE_BUTTON_MASK_MIDDLE)


## A complete middle-drag by `relative` pixels in one motion event.
static func pan(viewport: Viewport, relative: Vector2, at: Vector2 = Vector2(100.0, 100.0)) -> void:
	middle_press(viewport, at)
	middle_motion(viewport, relative, at + relative)
	middle_release(viewport, at + relative)


static func home_key(viewport: Viewport, modifiers: int = 0) -> void:
	Cam.tap(viewport, KEY_HOME, modifiers)


static func focus_out(camera: Node, window: bool = false) -> void:
	if window:
		camera.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	else:
		camera.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)


static func focus_in(camera: Node, window: bool = false) -> void:
	if window:
		camera.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	else:
		camera.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)


# --- geometry of the camera ---


## tan of the vertical half field of view of the real camera at the aspect of its viewport.
static func real_tan_half_vfov(camera: Camera3D) -> float:
	var size: Vector2 = camera.get_viewport().get_visible_rect().size
	var half: float = tan(deg_to_rad(camera.fov) / 2.0)
	if camera.keep_aspect == Camera3D.KEEP_WIDTH:
		return half * size.y / size.x
	return half


static func viewport_height(camera: Camera3D) -> float:
	return camera.get_viewport().get_visible_rect().size.y


## The pivot movement a drag of `relative` pixels must give, built from the real camera basis
## (grab the world: minus camera-right, plus camera-up). `distance_m` is the target distance.
static func expected_pan(camera: Camera3D, relative: Vector2, distance_m: float) -> Vector3:
	var scale: float = (
		2.0
		* distance_m
		* real_tan_half_vfov(camera)
		* setting("pan_speed")
		/ viewport_height(camera)
	)
	var basis: Basis = camera.global_transform.basis
	return (-basis.x * relative.x + basis.y * relative.y) * scale


## Elevation of the camera as shown, from its real position and the displayed pivot.
static func shown_elevation(camera: Camera3D) -> float:
	var offset: Vector3 = camera.global_position - Cam.pivot(camera)
	if offset.length() < 0.000001:
		return 0.0
	return rad_to_deg(asin(clampf(offset.y / offset.length(), -1.0, 1.0)))


static func shown_direction(camera: Camera3D) -> Vector3:
	return (camera.global_position - Cam.pivot(camera)).normalized()


## The camera is held when its distance from the displayed pivot is larger than the eased request.
static func is_held(camera: Camera3D) -> bool:
	return held_dist(camera) > Cam.dist(camera) + 0.000001


# --- the oracle for the solids ---


static func stand_z(room: Node3D) -> float:
	var tank: Node3D = room.get_node_or_null("Tank") as Node3D
	return tank.position.z if tank != null else 0.0


static func tank_box(id: StringName, z: float) -> AABB:
	var outer: Vector3 = Table.exterior(id)
	var top: float = CABINET_TOP_M + Table.glass(id) + Table.interior(id).y + Table.TRIM_M
	return AABB(
		Vector3(-outer.x / 2.0, CABINET_TOP_M, z - outer.z / 2.0),
		Vector3(outer.x, top - CABINET_TOP_M, outer.z)
	)


static func cabinet_box(id: StringName, z: float) -> AABB:
	var foot: Vector2 = Table.cabinet_footprint(id)
	return AABB(
		Vector3(-foot.x / 2.0, 0.0, z - foot.y / 2.0), Vector3(foot.x, CABINET_TOP_M, foot.y)
	)


## The pivot box: interior footprint, from the tank floor to the water line.
static func pan_box(id: StringName, z: float) -> AABB:
	var inner: Vector3 = Table.interior(id)
	var floor_y: float = CABINET_TOP_M + Table.glass(id)
	return AABB(
		Vector3(-inner.x / 2.0, floor_y, z - inner.z / 2.0),
		Vector3(inner.x, Table.water_line(id), inner.z)
	)


static func box_corner(box: AABB, high_x: bool, high_y: bool, high_z: bool) -> Vector3:
	return Vector3(
		box.end.x if high_x else box.position.x,
		box.end.y if high_y else box.position.y,
		box.end.z if high_z else box.position.z
	)


## One box per visible mesh of the lamp node of the room, in room space.
static func lamp_boxes(room: Node3D) -> Array[AABB]:
	var boxes: Array[AABB] = []
	var lamp: Node3D = room.get_node_or_null("Lamp") as Node3D
	if lamp == null or not lamp.is_visible_in_tree():
		return boxes
	for instance: MeshInstance3D in Glb.mesh_instances(lamp):
		if not instance.is_visible_in_tree():
			continue
		var box: AABB = Glb.bounds_in(instance, room)
		if box.size.length() > 0.0:
			boxes.append(box)
	return boxes


## Tank, cabinet and lamp boxes of the room that shows tank `id`.
static func solids(room: Node3D, id: StringName) -> Array[AABB]:
	var z: float = stand_z(room)
	var all: Array[AABB] = [tank_box(id, z), cabinet_box(id, z)]
	all.append_array(lamp_boxes(room))
	return all


## True when `point` is inside a solid grown by margin - tolerance on every face.
static func inside_any(
	boxes: Array[AABB], margin_m: float, point: Vector3, tolerance_m: float = LENGTH_M
) -> bool:
	for box: AABB in boxes:
		var grown: AABB = box.grow(margin_m - tolerance_m)
		if (
			point.x > grown.position.x
			and point.x < grown.end.x
			and point.y > grown.position.y
			and point.y < grown.end.y
			and point.z > grown.position.z
			and point.z < grown.end.z
		):
			return true
	return false


## The smallest distance at or above `requested_m` (sampled every 0.5 mm) at which the point on
## the line is outside every grown solid; the exact boundary counts as outside.
static func oracle_held(
	boxes: Array[AABB], margin_m: float, pivot: Vector3, direction: Vector3, requested_m: float
) -> float:
	var t: float = requested_m
	while t < requested_m + 20.0:
		if not inside_any(boxes, margin_m, pivot + direction * t, 0.0):
			return t
		t += HELD_EPSILON_M
	return t


## Why the camera pose breaks the rules at this moment; empty when it is fine.
static func pose_failures(camera: Camera3D, boxes: Array[AABB], label: String) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	var position: Vector3 = camera.global_position
	if inside_any(boxes, margin(), position):
		failures.append("%s: camera %s is inside a solid plus margin" % [label, position])
	if position.y < CABINET_TOP_M - LENGTH_M:
		failures.append("%s: camera height %.4f is below the cabinet top" % [label, position.y])
	for problem: String in Cam.basis_failures(camera, Cam.pivot(camera)):
		failures.append("%s: %s" % [label, problem])
	return failures


## The first few failures of a sweep as one message.
static func summary(failures: PackedStringArray) -> String:
	var shown: PackedStringArray = PackedStringArray()
	for index: int in mini(failures.size(), 6):
		shown.append(failures[index])
	return "%d failures, first: %s" % [failures.size(), " | ".join(shown)]


## The frame type of AC 12 and AC 22. d_held is the oracle held distance of the eased pose.
## Steady: held (d_held more than 1 mm above the request) and the shown distance within 1 mm of
## d_held. Release: the shown distance is still more than 1 mm above d_held. Otherwise neither.
static func frame_class(camera: Camera3D, boxes: Array[AABB]) -> String:
	var requested: float = Cam.dist(camera)
	var pivot: Vector3 = Cam.pivot(camera)
	var direction: Vector3 = OrbitApi.offset(Cam.az(camera), Cam.el(camera), 1.0)
	var d_held: float = oracle_held(boxes, margin(), pivot, direction, requested)
	var shown: float = (camera.global_position - pivot).length()
	if shown > d_held + FRAME_CLASS_TOLERANCE_M:
		return RELEASE
	if (
		d_held > requested + FRAME_CLASS_TOLERANCE_M
		and absf(shown - d_held) <= FRAME_CLASS_TOLERANCE_M
	):
		return STEADY
	return NEITHER


## The raise of the displayed elevation over the eased elevation, in degrees.
static func raise_deg(camera: Camera3D) -> float:
	return shown_elevation(camera) - Cam.el(camera)
