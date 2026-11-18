extends RefCounted
## Late-bound access to ItemDefinition and ItemCatalog (#152), like substrate_api.gd.
##
## The tests were written before the two classes exist. A direct reference to a missing class is a
## parse error that aborts the whole run, so everything goes through load() and call(). Every
## function returns a harmless stand-in while a script is missing; the first assertion of a test
## then fails with a readable message and the other suites keep running.
##
## Contract of the technical plan (comment on #152): ItemCatalog.load_dirs(paths),
## from_definitions(definitions), is_valid_id(id), get_definition(id), get_ids(),
## get_ids_in_category(category), get_skipped() (entries with `source` and `reason`),
## constant DEFAULT_DIRS.

const DEFINITION_PATH := "res://catalog/item_definition.gd"
const CATALOG_PATH := "res://catalog/item_catalog.gd"
const FIXTURES := "res://tests/fixtures/items"
const MISSING_DIR := "res://tests/fixtures/items/does_not_exist"
const SHIPPED_DIRS: Array[String] = ["res://catalog/decor", "res://catalog/plants"]

# --- the enums, exactly the schema of the issue body (AC 2) ---
const ENUMS: Dictionary = {
	"Category": {"UNSET": 0, "ROCK": 1, "WOOD": 2, "ORNAMENT": 3, "PLANT": 4},
	"ItemMaterial":
	{
		"UNSET": 0,
		"STONE": 1,
		"WOOD": 2,
		"CERAMIC": 3,
		"RESIN": 4,
		"SHELL": 5,
		"LIVE_PLANT": 6,
	},
	"WaterEffect":
	{
		"UNSET": 0,
		"INERT": 1,
		"RAISES_SLIGHTLY": 2,
		"RAISES": 3,
		"LOWERS_SLIGHTLY": 4,
		"LOWERS": 5,
	},
	"LightNeed": {"UNSET": 0, "LOW": 1, "MODERATE": 2, "HIGH": 3},
	"GrowthForm":
	{
		"UNSET": 0,
		"STEM": 1,
		"ROSETTE": 2,
		"CARPET": 3,
		"RHIZOME": 4,
		"MOSS": 5,
		"FLOATING": 6,
		"BALL": 7,
	},
	"Anchoring": {"UNSET": 0, "ROOTED": 1, "EPIPHYTE": 2, "FLOATING": 3, "LOOSE": 4},
}

# --- the fields: name -> [Variant type, enum name or resource class or "", default] ---
const MODE_1: Dictionary = {
	"id": [TYPE_STRING_NAME, "", &""],
	"name_key": [TYPE_STRING, "", ""],
	"description_key": [TYPE_STRING, "", ""],
	"category": [TYPE_INT, "Category", 0],
	"scene": [TYPE_OBJECT, "PackedScene", null],
	"thumbnail": [TYPE_OBJECT, "Texture2D", null],
	"sort_order": [TYPE_INT, "", 0],
	"colourable": [TYPE_BOOL, "", false],
}
const COMMON: Dictionary = {
	"material": [TYPE_INT, "ItemMaterial", 0],
	"aquarium_safe": [TYPE_BOOL, "", true],
	"weight_kg": [TYPE_FLOAT, "", 0.0],
	"volume_displacement_l": [TYPE_FLOAT, "", 0.0],
	"footprint_cm": [TYPE_VECTOR3, "", Vector3.ZERO],
	"ph_effect": [TYPE_INT, "WaterEffect", 0],
	"hardness_effect": [TYPE_INT, "WaterEffect", 0],
	"tannin_release": [TYPE_FLOAT, "", 0.0],
	"hiding_places": [TYPE_INT, "", 0],
	"hiding_quality": [TYPE_FLOAT, "", 0.0],
	"shade_cover": [TYPE_FLOAT, "", 0.0],
	"edge_smoothness": [TYPE_FLOAT, "", 0.0],
	"flow_obstruction": [TYPE_FLOAT, "", 0.0],
	"waste_trapping": [TYPE_FLOAT, "", 0.0],
	"cleaning_difficulty": [TYPE_FLOAT, "", 0.0],
	"algae_surface": [TYPE_FLOAT, "", 0.0],
	"breaks_down": [TYPE_BOOL, "", false],
}
const PLANT: Dictionary = {
	"growth_form": [TYPE_INT, "GrowthForm", 0],
	"anchoring": [TYPE_INT, "Anchoring", 0],
	"light_need": [TYPE_INT, "LightNeed", 0],
	"growth_cm_per_week": [TYPE_FLOAT, "", 0.0],
	"max_height_cm": [TYPE_FLOAT, "", 0.0],
	"temp_min_c": [TYPE_FLOAT, "", 0.0],
	"temp_max_c": [TYPE_FLOAT, "", 0.0],
	"ph_min": [TYPE_FLOAT, "", 0.0],
	"ph_max": [TYPE_FLOAT, "", 0.0],
	"nutrient_uptake": [TYPE_FLOAT, "", 0.0],
	"oxygen_output": [TYPE_FLOAT, "", 0.0],
	"co2_need": [TYPE_FLOAT, "", 0.0],
	"substrate_rooting_need": [TYPE_FLOAT, "", 0.0],
	"nibble_vulnerability": [TYPE_FLOAT, "", 0.0],
	"provides_cover": [TYPE_BOOL, "", false],
}

# --- the shared item-id list of the issue body (identical to #153) ---
const VALID_IDS: Array[String] = [
	"a",
	"rock_1",
	"driftwood_large",
	"moss_ball",
	"a2345678901234567890123456789012345678901234567x",
]
const INVALID_IDS: Array[String] = [
	"",
	"Rock",
	"1rock",
	"_rock",
	"rock-1",
	"rock 1",
	"rock.png",
	"rock/x",
	"rock\n",
	"a23456789012345678901234567890123456789012345678x",
	"con",
	"nul",
	"aux",
	"prn",
	"com1",
	"lpt9",
	"rocké",
]


static func _script(path: String) -> GDScript:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as GDScript


static func script_exists(path: String) -> bool:
	return _script(path) != null


static func enum_map(enum_name: String) -> Dictionary:
	var script: GDScript = _script(DEFINITION_PATH)
	if script == null:
		return {}
	return script.get_script_constant_map().get(enum_name, {})


## The value of an enum member, or -99 while the class or member is missing.
static func enum_value(enum_name: String, member: String) -> int:
	return enum_map(enum_name).get(member, -99)


static func all_field_names() -> Array[String]:
	var names: Array[String] = []
	for block: Dictionary in [MODE_1, COMMON, PLANT]:
		for field: String in block:
			names.append(field)
	return names


## The stored script variables of ItemDefinition by name, in declaration order (property-list
## dictionaries). Empty while the class is missing.
static func properties() -> Dictionary:
	var result: Dictionary = {}
	var script: GDScript = _script(DEFINITION_PATH)
	if script == null:
		return result
	for entry: Dictionary in script.get_script_property_list():
		var usage: int = entry["usage"]
		var wanted: int = PROPERTY_USAGE_SCRIPT_VARIABLE | PROPERTY_USAGE_STORAGE
		if usage & wanted == wanted:
			result[String(entry["name"])] = entry
	return result


static func property_names() -> Array[String]:
	var names: Array[String] = []
	for key: Variant in properties().keys():
		names.append(String(key))
	return names


static func new_definition() -> Resource:
	var script: GDScript = _script(DEFINITION_PATH)
	if script == null:
		return Resource.new()
	return script.new() as Resource


## A definition with the given Mode 1 values; scene and thumbnail stay null. The name key is the
## shipped pattern of the id unless given.
static func make(
	id: String,
	category: int,
	name_key: String = "",
	sort_order: int = 0,
	safe: bool = true,
) -> Resource:
	var item: Resource = new_definition()
	if not script_exists(DEFINITION_PATH):
		return item
	item.set("id", StringName(id))
	item.set("category", category)
	item.set("name_key", name_key if not name_key.is_empty() else "item.%s.name" % id)
	item.set("sort_order", sort_order)
	item.set("aquarium_safe", safe)
	return item


## A typed Array[ItemDefinition] built without naming the class. Elements may be null.
static func typed_definitions(definitions: Array) -> Array:
	var script: GDScript = _script(DEFINITION_PATH)
	if script == null:
		return Array([], TYPE_OBJECT, &"Resource", null)
	return Array(definitions, TYPE_OBJECT, &"Resource", script)


# --- catalog ---


static func load_dirs(paths: Array[String]) -> RefCounted:
	var script: GDScript = _script(CATALOG_PATH)
	if script == null:
		return null
	return script.call("load_dirs", paths) as RefCounted


## load_dirs() with no argument (the default folders).
static func load_default_dirs() -> RefCounted:
	var script: GDScript = _script(CATALOG_PATH)
	if script == null:
		return null
	return script.call("load_dirs") as RefCounted


static func from_definitions(definitions: Array) -> RefCounted:
	var script: GDScript = _script(CATALOG_PATH)
	if script == null:
		return null
	return script.call("from_definitions", typed_definitions(definitions)) as RefCounted


## A catalog of one fixture folder under FIXTURES.
static func fixture(folder: String) -> RefCounted:
	var paths: Array[String] = [FIXTURES.path_join(folder)]
	return load_dirs(paths)


static func is_valid_id(id: String) -> Variant:
	var script: GDScript = _script(CATALOG_PATH)
	if script == null:
		return null
	return script.call("is_valid_id", id)


static func default_dirs() -> Variant:
	var script: GDScript = _script(CATALOG_PATH)
	if script == null:
		return null
	return script.get_script_constant_map().get("DEFAULT_DIRS", null)


static func definition(cat: RefCounted, id: StringName) -> Resource:
	if cat == null or not cat.has_method("get_definition"):
		return null
	return cat.call("get_definition", id) as Resource


## The ids in catalog order as Strings (empty while the catalog is missing).
static func ids(cat: RefCounted) -> Array[String]:
	var result: Array[String] = []
	if cat == null or not cat.has_method("get_ids"):
		return result
	for id: Variant in cat.call("get_ids"):
		result.append(String(id))
	return result


static func ids_in(cat: RefCounted, category: int) -> Array[String]:
	var result: Array[String] = []
	if cat == null or not cat.has_method("get_ids_in_category"):
		return result
	for id: Variant in cat.call("get_ids_in_category", category):
		result.append(String(id))
	return result


## The skipped entries as dictionaries {"source": String, "reason": String} (empty while the
## accessor is missing; use has_api() to tell that from "nothing skipped").
static func skipped(cat: RefCounted) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if cat == null or not cat.has_method("get_skipped"):
		return result
	for entry: Variant in cat.call("get_skipped"):
		var object: Object = entry as Object
		var record: Dictionary = {
			"source": String(object.get("source")),
			"reason": String(object.get("reason")),
		}
		result.append(record)
	return result


static func skipped_sources(cat: RefCounted) -> Array[String]:
	var result: Array[String] = []
	for entry: Dictionary in skipped(cat):
		result.append(entry["source"])
	return result


## True while the catalog exists and has the whole public read API.
static func has_api(cat: RefCounted) -> bool:
	if cat == null:
		return false
	for method: String in ["get_definition", "get_ids", "get_ids_in_category", "get_skipped"]:
		if not cat.has_method(method):
			return false
	return true


static func prop(object: Object, wanted: String, fallback: Variant) -> Variant:
	if object == null:
		return fallback
	var value: Variant = object.get(wanted)
	return fallback if value == null else value
