extends RefCounted
## Late-bound access to the #22 game classes (TankDefinition, TankCatalog, CameraFraming,
## RoomCorner and the new AquariumModel constant).
##
## The tests were written before those classes exist. A direct reference to a missing class is a
## parse error, and GdUnit4 then aborts the whole run. Going through load() keeps every other suite
## running, and each test fails on its own with a readable message until the class exists. Every
## function returns a harmless stand-in when the script is missing, so a test never dies on a null.

const DEFINITION_PATH := "res://catalog/tank_definition.gd"
const CATALOG_PATH := "res://catalog/tank_catalog.gd"
const FRAMING_PATH := "res://systems/camera/camera_framing.gd"
const ROOM_SCRIPT_PATH := "res://scenes/room/room_corner.gd"
const MODEL_PATH := "res://model/aquarium_model.gd"
const MISSING: StringName = &"<missing>"
## Stand-in for a number of a missing class: a value no assertion in the suites accepts. NAN is
## not used because GdUnit4 float asserts let NaN pass.
const MISSING_NUMBER := -999.0


static func _script(path: String) -> GDScript:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as GDScript


## A constant of a script by name, or `fallback` when the script or the constant is missing.
static func constant(path: String, wanted: String, fallback: Variant) -> Variant:
	var script: GDScript = _script(path)
	if script == null:
		return fallback
	return script.get_script_constant_map().get(wanted, fallback)


static func default_tank_id() -> StringName:
	return constant(MODEL_PATH, "DEFAULT_TANK_ID", MISSING)


static func room_constant(wanted: String) -> float:
	return constant(ROOM_SCRIPT_PATH, wanted, MISSING_NUMBER)


static func prop(object: Object, wanted: String, fallback: Variant) -> Variant:
	if object == null:
		return fallback
	var value: Variant = object.get(wanted)
	return fallback if value == null else value


# --- TankDefinition and TankCatalog ---


static func new_definition() -> Resource:
	var script: GDScript = _script(DEFINITION_PATH)
	if script == null:
		return Resource.new()
	return script.new() as Resource


static func catalog_load_dir(path: String = "res://catalog/tanks") -> RefCounted:
	var script: GDScript = _script(CATALOG_PATH)
	if script == null:
		return RefCounted.new()
	return script.call("load_dir", path) as RefCounted


static func catalog_from(definitions: Array) -> RefCounted:
	var script: GDScript = _script(CATALOG_PATH)
	if script == null:
		return RefCounted.new()
	var typed: Array = Array(definitions, TYPE_OBJECT, &"Resource", _script(DEFINITION_PATH))
	return script.call("from_definitions", typed) as RefCounted


## The definition for `id`, or null (also when the catalog class is missing).
static func definition_of(catalog: RefCounted, id: StringName) -> Resource:
	if catalog == null or not catalog.has_method("get_definition"):
		return null
	return catalog.call("get_definition", id) as Resource


static func ids_of(catalog: RefCounted) -> Array:
	if catalog == null or not catalog.has_method("get_ids"):
		return []
	return catalog.call("get_ids")


static func call_on(object: Object, method: String, args: Array, fallback: Variant) -> Variant:
	if object == null or not object.has_method(method):
		return fallback
	return object.callv(method, args)


# --- CameraFraming ---


static func default_distance(
	width: float, depth: float, hfov: float, elevation: float, share: float
) -> float:
	var script: GDScript = _script(FRAMING_PATH)
	if script == null:
		return MISSING_NUMBER
	return script.call("default_distance", width, depth, hfov, elevation, share)


static func camera_position(pivot: Vector3, distance: float, elevation: float) -> Vector3:
	var script: GDScript = _script(FRAMING_PATH)
	if script == null:
		return Vector3.ONE * MISSING_NUMBER
	return script.call("camera_position", pivot, distance, elevation)
