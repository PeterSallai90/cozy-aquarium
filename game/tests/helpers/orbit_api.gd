extends RefCounted
## Late-bound access to the #25 classes (OrbitMath, CameraSettings, WorldInput, WallCutaway). The
## tests were written before the classes exist; a direct reference to a missing class is a parse
## error that aborts the whole run, so everything goes through load(). Every function returns a
## stand-in that no assertion accepts while the script is missing.

const Api := preload("res://tests/helpers/late_api.gd")

const MATH_PATH := "res://systems/camera/orbit_math.gd"
const SETTINGS_PATH := "res://systems/camera/camera_settings.gd"
const SETTINGS_RESOURCE := "res://systems/camera/camera_settings.tres"
const WORLD_INPUT_PATH := "res://systems/input/world_input.gd"
const WALL_PATH := "res://scenes/room/wall_cutaway.gd"
const MISSING_NUMBER: float = Api.MISSING_NUMBER


static func _script(path: String) -> GDScript:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as GDScript


static func math_exists() -> bool:
	return _script(MATH_PATH) != null


static func world_input_exists() -> bool:
	return _script(WORLD_INPUT_PATH) != null


static func wall_exists() -> bool:
	return _script(WALL_PATH) != null


static func min_elevation(limit_deg: float, above_m: float, distance_m: float) -> float:
	var script: GDScript = _script(MATH_PATH)
	if script == null:
		return MISSING_NUMBER
	return script.call("min_elevation_deg", limit_deg, above_m, distance_m)


static func offset(azimuth_deg: float, elevation_deg: float, distance_m: float) -> Vector3:
	var script: GDScript = _script(MATH_PATH)
	if script == null:
		return Vector3.ONE * MISSING_NUMBER
	return script.call("offset", azimuth_deg, elevation_deg, distance_m)


static func camera_rotation(azimuth_deg: float, elevation_deg: float) -> Vector3:
	var script: GDScript = _script(MATH_PATH)
	if script == null:
		return Vector3.ONE * MISSING_NUMBER
	return script.call("camera_rotation", azimuth_deg, elevation_deg)


static func damp_factor(delta_s: float, damping_time_s: float) -> float:
	var script: GDScript = _script(MATH_PATH)
	if script == null:
		return MISSING_NUMBER
	return script.call("damp_factor", delta_s, damping_time_s)


static func drag_deg(pixels: float, viewport_height_px: float, deg_per_height: float) -> float:
	var script: GDScript = _script(MATH_PATH)
	if script == null:
		return MISSING_NUMBER
	return script.call("drag_deg", pixels, viewport_height_px, deg_per_height)


## The shared camera settings resource, or null while it is missing.
static func settings() -> Resource:
	if not ResourceLoader.exists(SETTINGS_RESOURCE):
		return null
	return load(SETTINGS_RESOURCE) as Resource


## One value of the shared settings resource, or the stand-in.
static func setting(wanted: String) -> float:
	var resource: Resource = settings()
	if resource == null:
		return MISSING_NUMBER
	var value: Variant = resource.get(wanted)
	return MISSING_NUMBER if value == null else float(value)


static func blocker_group() -> StringName:
	return Api.constant(WORLD_INPUT_PATH, "BLOCKER_GROUP", &"<missing>")


static func is_blocked(tree: SceneTree) -> Variant:
	var script: GDScript = _script(WORLD_INPUT_PATH)
	if script == null:
		return null
	return script.call("is_blocked", tree)


static func next_hidden(was_hidden: bool, distance_m: float, band_m: float) -> Variant:
	var script: GDScript = _script(WALL_PATH)
	if script == null:
		return null
	return script.call("next_hidden", was_hidden, distance_m, band_m)


static func wall_constant(wanted: String) -> StringName:
	return Api.constant(WALL_PATH, wanted, &"<missing>")
