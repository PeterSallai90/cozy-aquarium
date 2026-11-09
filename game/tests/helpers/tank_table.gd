extends RefCounted
## The three delivered tanks as the issue #24 table states them, and the file names that follow
## from the id. These are the numbers of the acceptance criteria, not catalog reads, so a suite
## that uses them runs (and fails for the right reason) before the catalog entries exist.

const SMALL: StringName = &"tank_small_1"
const MEDIUM: StringName = &"tank_medium_1"
const LARGE: StringName = &"tank_large_1"
## Ascending size order.
const IDS: Array[StringName] = [SMALL, MEDIUM, LARGE]

const TRIM_M: float = 0.01
const CABINET_TOP_M: float = 0.75
const CABINET_MARGIN_M: float = 0.025
const LAMP_SHORTER_M: float = 0.03
const LAMP_DEPTH_M: float = 0.06

const TABLE: Dictionary = {
	"tank_small_1":
	{
		"interior": Vector3(0.40, 0.27, 0.25),
		"glass": 0.004,
		"water_line": 0.25,
		"litres": 25,
		"weight": 3.5,
		"heat_loss": 1.3,
		"evaporation": 0.3,
		"heater_slots": 1,
		"filter_slots": 1,
		"light_slots": 1,
		"heater_watts": 25,
		"filter_lph": 100,
		"name_en": "Small tank",
		"name_hu": "Kis akvárium",
		"description_en": "A small, quiet tank for a few tiny fish.",
		"description_hu": "Kicsi, csendes akvárium néhány apró halnak.",
	},
	"tank_medium_1":
	{
		"interior": Vector3(0.60, 0.35, 0.30),
		"glass": 0.005,
		"water_line": 0.33,
		"litres": 60,
		"weight": 8.0,
		"heat_loss": 1.0,
		"evaporation": 0.5,
		"heater_slots": 1,
		"filter_slots": 1,
		"light_slots": 1,
		"heater_watts": 50,
		"filter_lph": 240,
		"name_en": "Medium tank",
		"name_hu": "Közepes akvárium",
		"description_en": "A cozy, balanced tank for a small community.",
		"description_hu": "Hangulatos, kiegyensúlyozott akvárium egy kis közösségnek.",
	},
	"tank_large_1":
	{
		"interior": Vector3(1.00, 0.52, 0.40),
		"glass": 0.008,
		"water_line": 0.50,
		"litres": 200,
		"weight": 30.0,
		"heat_loss": 0.7,
		"evaporation": 1.1,
		"heater_slots": 2,
		"filter_slots": 1,
		"light_slots": 1,
		"heater_watts": 200,
		"filter_lph": 800,
		"name_en": "Large tank",
		"name_hu": "Nagy akvárium",
		"description_en": "A roomy tank with space for a big, lively community.",
		"description_hu": "Tágas akvárium egy nagy, élénk közösségnek.",
	},
}


static func row(id: StringName) -> Dictionary:
	return TABLE[String(id)]


static func interior(id: StringName) -> Vector3:
	return row(id)["interior"]


static func glass(id: StringName) -> float:
	return row(id)["glass"]


static func water_line(id: StringName) -> float:
	return row(id)["water_line"]


## Outer size of the glass box without the trim, like TankDefinition.get_exterior_size_m().
static func exterior(id: StringName) -> Vector3:
	var inner: Vector3 = interior(id)
	var thickness: float = glass(id)
	return Vector3(inner.x + 2.0 * thickness, inner.y + thickness, inner.z + 2.0 * thickness)


## Cabinet footprint (x width, z depth): the exterior plus 2.5 cm on every side.
static func cabinet_footprint(id: StringName) -> Vector2:
	var outer: Vector3 = exterior(id)
	return Vector2(outer.x + 2.0 * CABINET_MARGIN_M, outer.z + 2.0 * CABINET_MARGIN_M)


## The lamp bar length: the exterior length minus 3 cm.
static func lamp_bar_length(id: StringName) -> float:
	return exterior(id).x - LAMP_SHORTER_M


## The suffix of every file of a tank: the id without "tank_".
static func suffix(id: StringName) -> String:
	return String(id).trim_prefix("tank_")


static func glb_path(id: StringName) -> String:
	return "res://assets/tank/%s.glb" % id


static func scene_path(id: StringName) -> String:
	return "res://scenes/tank/%s.tscn" % id


static func cabinet_glb_path(id: StringName) -> String:
	return "res://assets/room/cabinet_%s.glb" % suffix(id)


static func lamp_glb_path(id: StringName) -> String:
	return "res://assets/room/lamp_%s.glb" % suffix(id)


static func lamp_scene_path(id: StringName) -> String:
	return "res://scenes/room/lamp_%s.tscn" % suffix(id)


static func catalog_path(id: StringName) -> String:
	return "res://catalog/tanks/%s.tres" % id
