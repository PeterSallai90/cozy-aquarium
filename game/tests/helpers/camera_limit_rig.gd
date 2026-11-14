extends RefCounted
## Rig of the #27 camera limit suites: one room per catalog tank, a solid oracle built from the
## catalog definition (not from CameraSolids), the drives shared by the criteria and the
## meta-tests, and the seeded event sequences of the combined sweep. Input is simulated headless:
## synthetic events pushed into the SubViewport (camera_rig.gd, camera_zoom_rig.gd), never OS input.

const Cz := preload("res://tests/helpers/camera_zoom_rig.gd")
const Cam := preload("res://tests/helpers/camera_rig.gd")
const Inv := preload("res://tests/helpers/camera_invariants.gd")

const FRAME_S: float = 1.0 / 60.0
const FAILURE_CAP: int = 20
const MIN_TANKS: int = 3
const AFTER_EVENT: int = -1
const KIND_ORBIT := "orbit"
const KIND_WHEEL := "wheel"
const KIND_PAN := "pan"
const KIND_HOME := "home"
const DRAG_HEIGHTS: float = 100.0
const FLOOR_FRAMES: int = 240
const NOTCHES: int = 12
const SETTLE_FRAMES: int = 60


## Everything the limit suites need to know about one tank.
class TankRig:
	extends RefCounted
	var id: StringName = &""
	var definition: TankDefinition = null
	var viewport: SubViewport = null
	var room: Node3D = null
	var camera: BuildCamera = null
	var default_distance: float = 0.0
	var home_pivot: Vector3 = Vector3.ZERO
	var stand_z: float = 0.0
	var solids: Array[AABB] = []
	var water: AABB = AABB()
	var checker: Inv = null


static func production_settings() -> CameraSettings:
	return load(BuildCamera.SETTINGS_PATH) as CameraSettings


## The ids of every tank in the catalog folder (sorted file order).
static func tank_ids() -> Array[StringName]:
	return TankCatalog.load_dir().get_ids()


static func cabinet_top() -> float:
	return RoomCorner.CABINET_TOP_HEIGHT_M


## Tank, cabinet and lamp boxes from the catalog numbers and the lamp scene of the room.
static func solids_for(room: Node3D, definition: TankDefinition) -> Array[AABB]:
	var z: float = Cz.stand_z(room)
	var top: float = cabinet_top()
	var outer: Vector3 = definition.get_exterior_size_m()
	var tank_height: float = (
		definition.glass_thickness_m + definition.interior_size_m.y + definition.trim_size_m
	)
	var margin: float = RoomCorner.CABINET_MARGIN_M
	var all: Array[AABB] = [
		AABB(
			Vector3(-outer.x / 2.0, top, z - outer.z / 2.0), Vector3(outer.x, tank_height, outer.z)
		),
		AABB(
			Vector3(-outer.x / 2.0 - margin, 0.0, z - outer.z / 2.0 - margin),
			Vector3(outer.x + 2.0 * margin, top, outer.z + 2.0 * margin)
		),
	]
	all.append_array(Cz.lamp_boxes(room))
	return all


## Interior footprint, from the tank floor up to the water line (not the rim).
static func water_volume(definition: TankDefinition, stand_z: float) -> AABB:
	var inner: Vector3 = definition.interior_size_m
	var floor_y: float = cabinet_top() + definition.glass_thickness_m
	return AABB(
		Vector3(-inner.x / 2.0, floor_y, stand_z - inner.z / 2.0),
		Vector3(inner.x, definition.water_line_height_m, inner.z)
	)


## One room per catalog tank with a frozen camera. A tank whose room has no camera is left out
## (the open helper already failed the running test).
static func open_all(suite: GdUnitTestSuite) -> Array[TankRig]:
	var rigs: Array[TankRig] = []
	var catalog: TankCatalog = TankCatalog.load_dir()
	for id: StringName in catalog.get_ids():
		var opened: Dictionary = await Cz.open_tank(suite, id)
		if not opened["ok"]:
			continue
		var rig: TankRig = TankRig.new()
		rig.id = id
		rig.definition = catalog.get_definition(id)
		rig.viewport = opened["viewport"]
		rig.room = opened["room"]
		rig.camera = opened["camera"] as BuildCamera
		rig.default_distance = opened["default_distance"]
		rig.home_pivot = opened["home_pivot"]
		rig.stand_z = Cz.stand_z(rig.room)
		rig.solids = solids_for(rig.room, rig.definition)
		rig.water = water_volume(rig.definition, rig.stand_z)
		rig.checker = Inv.new(
			Inv.production_limits(), rig.solids, rig.water, cabinet_top(), rig.default_distance
		)
		rigs.append(rig)
	return rigs


# --- state ---


## Back to the home view with the production settings and no gesture or hold left over from an
## earlier test. Returns what is wrong with the reset state; empty when it is clean.
static func reset(rig: TankRig) -> PackedStringArray:
	var camera: BuildCamera = rig.camera
	Cz.focus_out(camera)
	Cz.focus_in(camera)
	camera.settings = production_settings()
	camera.set_target_pivot(rig.home_pivot, true)
	camera.set_target_distance_m(rig.default_distance, true)
	camera.set_orbit(0.0, RoomCorner.CAMERA_ELEVATION_DEG, true)
	camera.step(0.0)
	var failures: PackedStringArray = PackedStringArray()
	if camera.is_dragging() or camera.is_panning():
		failures.append("reset %s: a gesture is still running" % rig.id)
	if absf(camera.get_held_distance_m() - rig.default_distance) > Inv.LENGTH_TOLERANCE_M:
		failures.append(
			(
				"reset %s: held distance %.4f is not the default"
				% [rig.id, camera.get_held_distance_m()]
			)
		)
	if camera.get_target_pivot().distance_to(rig.home_pivot) > Inv.LENGTH_TOLERANCE_M:
		failures.append("reset %s: pivot is not home" % rig.id)
	for message: String in rig.checker.check(camera):
		failures.append("reset %s: %s" % [rig.id, message])
	return failures


## Poses at once at the default distance and the home pivot; returns the violations of the pose.
static func pose_home(rig: TankRig, azimuth_deg: float, elevation_deg: float) -> PackedStringArray:
	var camera: BuildCamera = rig.camera
	camera.set_target_pivot(rig.home_pivot, true)
	camera.set_target_distance_m(rig.default_distance, true)
	camera.set_orbit(azimuth_deg, elevation_deg, true)
	camera.step(0.0)
	return rig.checker.check(camera)


# --- checked frames ---


## Checks the camera as it is now and appends labelled violations; stops at the cap.
static func record(rig: TankRig, failures: PackedStringArray, label: String, index: int) -> void:
	if failures.size() >= FAILURE_CAP:
		return
	var bad: PackedStringArray = rig.checker.check(rig.camera)
	for message: String in bad:
		failures.append("%s frame=%d: %s" % [label, index, message])


## One step of dt seconds, then a check.
static func frame(
	rig: TankRig, dt: float, failures: PackedStringArray, label: String, index: int
) -> void:
	rig.camera.step(dt)
	record(rig, failures, label, index)


static func settle(
	rig: TankRig, frames: int, failures: PackedStringArray, label: String, first_index: int = 0
) -> void:
	for index: int in frames:
		frame(rig, FRAME_S, failures, label, first_index + index)


# --- drives shared by the criteria and the meta-tests ---


## A right-drag of 100 viewport heights down, checked after the event and at every frame.
static func drive_floor_drag(
	rig: TankRig, label: String, frames: int = FLOOR_FRAMES
) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	Cam.drag(rig.viewport, Vector2(0.0, DRAG_HEIGHTS * float(rig.viewport.size.y)))
	record(rig, failures, label, AFTER_EVENT)
	settle(rig, frames, failures, label)
	return failures


## `notches` wheel-in notches with one frame after each, checked at every frame.
static func notch_in(
	rig: TankRig, label: String, failures: PackedStringArray, notches: int = NOTCHES
) -> void:
	for index: int in notches:
		Cz.wheel(rig.viewport, true)
		record(rig, failures, label, AFTER_EVENT)
		frame(rig, FRAME_S, failures, label, index)


## Zoom in far past the limit, then settle.
static func drive_zoom_in(
	rig: TankRig, label: String, notches: int = NOTCHES, settle_frames: int = SETTLE_FRAMES
) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	notch_in(rig, label, failures, notches)
	settle(rig, settle_frames, failures, label, notches)
	return failures


# --- seeded sequences ---


static func sequence_seed(
	base: int, tank_index: int, frame_time_index: int, sequence_index: int
) -> int:
	return base + 10000 * tank_index + 1000 * frame_time_index + sequence_index


## The 40 events of one sequence. The call order of the generator is fixed, so a seed always
## replays the same sequence: kind, then its parameters, then the frame count.
static func sequence(
	rng: RandomNumberGenerator, viewport_size: Vector2, events: int = 40
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for _index: int in events:
		var roll: int = rng.randi_range(1, 12)
		var event: Dictionary = {"kind": KIND_HOME, "x": 0.0, "y": 0.0, "n": 0, "up": false}
		if roll <= 4:
			event["kind"] = KIND_ORBIT
			event["x"] = rng.randf_range(-3.0, 3.0) * viewport_size.y
			event["y"] = rng.randf_range(-3.0, 3.0) * viewport_size.y
		elif roll <= 8:
			event["kind"] = KIND_WHEEL
			event["n"] = rng.randi_range(1, 5)
			event["up"] = rng.randf() < 0.5
		elif roll <= 11:
			event["kind"] = KIND_PAN
			event["x"] = rng.randf_range(-1.0, 1.0) * viewport_size.x
			event["y"] = rng.randf_range(-1.0, 1.0) * viewport_size.y
		event["frames"] = 0 if rng.randf() < 0.1 else rng.randi_range(1, 6)
		result.append(event)
	return result


static func apply_event(rig: TankRig, event: Dictionary) -> void:
	var kind: String = event["kind"]
	var amount: Vector2 = Vector2(event["x"], event["y"])
	if kind == KIND_ORBIT:
		Cam.drag(rig.viewport, amount)
	elif kind == KIND_WHEEL:
		for _notch: int in int(event["n"]):
			Cz.wheel(rig.viewport, event["up"])
	elif kind == KIND_PAN:
		Cz.pan(rig.viewport, amount)
	else:
		Cz.home_key(rig.viewport)


## Applies the events with frames of dt seconds; checks after every event and at every frame.
static func run_sequence(
	rig: TankRig, events: Array[Dictionary], dt: float, label: String
) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	for event_index: int in events.size():
		var event: Dictionary = events[event_index]
		apply_event(rig, event)
		if failures.size() < FAILURE_CAP:
			var bad: PackedStringArray = rig.checker.check(rig.camera)
			for message: String in bad:
				failures.append(
					"%s event=%d %s after-event: %s" % [label, event_index, event, message]
				)
		for frame_index: int in int(event["frames"]):
			rig.camera.step(dt)
			if failures.size() < FAILURE_CAP:
				var bad: PackedStringArray = rig.checker.check(rig.camera)
				for message: String in bad:
					failures.append(
						(
							"%s event=%d %s frame=%d: %s"
							% [label, event_index, event, frame_index, message]
						)
					)
	return failures
