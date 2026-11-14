extends RefCounted
## Late-bound access to the #28 substrate classes (SubstrateDefinition, SubstrateCatalog,
## SetSubstrateCommand, SubstrateSetup) and the new constructor arguments of SaveStore.
##
## The tests were written before those classes exist. A direct reference to a missing class is a
## parse error, which aborts the whole run, so everything goes through load() and call(). Every
## function returns a harmless stand-in when the script is missing; the first assertion of a test
## then fails with a readable message and the rest of the suites keep running.
##
## Contract of the technical plan (comment on #28):
## - SubstrateCatalog.load_dir(path), get_definition(id), get_ids() (ordered by sort_order),
##   get_default(), is_swatch(id, colour), swatch_index(id, colour), colour_for_pick(current_id,
##   current_colour, picked_id) -> Color, constant DEFAULT_ID.
## - SetSubstrateCommand.new(model, catalog, id, colour), a Command.
## - SubstrateSetup.apply_default(model, catalog) and normalise(model, catalog) -> bool.
## - SaveStore.new(clock, codec, substrates).
## Swatches are always addressed by their number as the criteria count them: swatch 1 is the
## default, swatch 2 the next one.

const Factory := preload("res://tests/helpers/factory.gd")
const FailingCommand := preload("res://tests/helpers/commands/failing_command.gd")

const DEFINITION_PATH := "res://catalog/substrate_definition.gd"
const CATALOG_PATH := "res://catalog/substrate_catalog.gd"
const COMMAND_PATH := "res://model/set_substrate_command.gd"
const SETUP_PATH := "res://model/substrate_setup.gd"
const SAVE_STORE_PATH := "res://systems/save_store.gd"
const CATALOG_DIR := "res://catalog/substrates"

const SAND: StringName = &"sand_fine"
const GRAVEL: StringName = &"gravel_natural"
const PEBBLES: StringName = &"pebbles_river"
const BLACK: StringName = &"sand_black"
const COLOURED: StringName = &"gravel_coloured"
## The five types in the chooser order of the owner table.
const IDS: Array[StringName] = [SAND, GRAVEL, PEBBLES, BLACK, COLOURED]
## The decided Sand default (docs/architecture.md save sample); the only colour hard-coded here.
const SAND_DEFAULT: Color = Color8(0xE8, 0xD9, 0xB0)
## A colour that is a swatch of no type.
const NOT_A_SWATCH: Color = Color8(0x12, 0x34, 0x56)
## Stand-in colour of a missing catalog; no assertion accepts it.
const MISSING_COLOUR: Color = Color(-1.0, -1.0, -1.0, -1.0)
const UNKNOWN_ID: StringName = &"pebbles_x"
const STAMP := "2026-11-01T12:00:00Z"

const ERR_UNKNOWN_ID := "SetSubstrateCommand: unknown substrate id"
const ERR_COLOUR := "SetSubstrateCommand: colour"
const WARN_UNKNOWN_ID := "SubstrateSetup: unknown substrate id"

# --- the Mode 2 field names (14, exactly the list of the issue body) ---
const MODE_2_FLOATS: Array[String] = [
	"bulk_density_kg_per_l",
	"layer_depth_min_cm",
	"layer_depth_max_cm",
	"layer_depth_default_cm",
	"grain_size_min_mm",
	"grain_size_max_mm",
	"rooting_suitability",
	"nutrient_retention",
	"burrowing_suitability",
	"edge_smoothness",
	"waste_trapping",
	"cleaning_difficulty",
]
const MODE_2_ENUMS: Array[String] = ["ph_effect", "hardness_effect"]
const UNIT_RANGE_FIELDS: Array[String] = [
	"rooting_suitability",
	"nutrient_retention",
	"burrowing_suitability",
	"edge_smoothness",
	"waste_trapping",
	"cleaning_difficulty",
]


static func _script(path: String) -> GDScript:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as GDScript


static func script_exists(path: String) -> bool:
	return _script(path) != null


## A constant of a script by name, or `fallback` when the script or the constant is missing.
static func constant(path: String, wanted: String, fallback: Variant) -> Variant:
	var script: GDScript = _script(path)
	if script == null:
		return fallback
	return script.get_script_constant_map().get(wanted, fallback)


## The number of parameters of `_init` (0 when the script or the method is missing).
static func init_args(path: String) -> int:
	var script: GDScript = _script(path)
	if script == null:
		return 0
	for method: Dictionary in script.get_script_method_list():
		if method["name"] == "_init":
			var args: Array = method["args"]
			return args.size()
	return 0


## The number of parameters of a method of a script (-1 when missing).
static func method_args(path: String, method_name: String) -> int:
	var script: GDScript = _script(path)
	if script == null:
		return -1
	for method: Dictionary in script.get_script_method_list():
		if method["name"] == method_name:
			var args: Array = method["args"]
			return args.size()
	return -1


# --- catalog ---


static func new_definition() -> Resource:
	var script: GDScript = _script(DEFINITION_PATH)
	if script == null:
		return Resource.new()
	return script.new() as Resource


static func catalog(path: String = CATALOG_DIR) -> RefCounted:
	var script: GDScript = _script(CATALOG_PATH)
	if script == null:
		return RefCounted.new()
	return script.call("load_dir", path) as RefCounted


static func definition(cat: RefCounted, id: StringName) -> Resource:
	if cat == null or not cat.has_method("get_definition"):
		return null
	return cat.call("get_definition", id) as Resource


static func ids(cat: RefCounted) -> Array:
	if cat == null or not cat.has_method("get_ids"):
		return []
	return cat.call("get_ids")


static func prop(object: Object, wanted: String, fallback: Variant) -> Variant:
	if object == null:
		return fallback
	var value: Variant = object.get(wanted)
	return fallback if value == null else value


static func swatches(cat: RefCounted, id: StringName) -> Array[Color]:
	var result: Array[Color] = []
	var list: Variant = prop(definition(cat, id), "colour_swatches", [])
	for entry: Variant in list:
		result.append(entry)
	return result


static func default_colour(cat: RefCounted, id: StringName) -> Color:
	return prop(definition(cat, id), "default_colour", MISSING_COLOUR)


## Swatch `number` of the type, counted from 1 (the default). A stand-in when it does not exist.
static func swatch(cat: RefCounted, id: StringName, number: int) -> Color:
	var list: Array[Color] = swatches(cat, id)
	if number < 1 or number > list.size():
		return MISSING_COLOUR
	return list[number - 1]


static func is_swatch(cat: RefCounted, id: StringName, colour: Color) -> Variant:
	if cat == null or not cat.has_method("is_swatch"):
		return null
	return cat.call("is_swatch", id, colour)


static func swatch_index(cat: RefCounted, id: StringName, colour: Color) -> Variant:
	if cat == null or not cat.has_method("swatch_index"):
		return null
	return cat.call("swatch_index", id, colour)


static func pick(
	cat: RefCounted, current_id: StringName, current_colour: Color, picked_id: StringName
) -> Color:
	if cat == null or not cat.has_method("colour_for_pick"):
		return MISSING_COLOUR
	return cat.call("colour_for_pick", current_id, current_colour, picked_id)


static func default_id() -> StringName:
	return constant(CATALOG_PATH, "DEFAULT_ID", &"<missing>")


## The look of a type from the catalog: {"grain_scale", "grain_shape", "grain_contrast"}.
static func look(cat: RefCounted, id: StringName) -> Dictionary:
	var def: Resource = definition(cat, id)
	return {
		"grain_scale": prop(def, "grain_scale", MISSING_COLOUR.r),
		"grain_shape": prop(def, "grain_shape", -1),
		"grain_contrast": prop(def, "grain_contrast", MISSING_COLOUR.r),
	}


# --- command and setup ---


static func command_exists() -> bool:
	return script_exists(COMMAND_PATH)


## A SetSubstrateCommand, or, while the class is missing, a command whose do() fails.
static func command(
	model: AquariumModel, cat: RefCounted, id: StringName, colour: Color
) -> Command:
	var script: GDScript = _script(COMMAND_PATH)
	if script == null:
		return FailingCommand.new(model)
	return script.new(model, cat, id, colour) as Command


static func setup_exists() -> bool:
	return script_exists(SETUP_PATH)


static func apply_default(model: AquariumModel, cat: RefCounted) -> bool:
	var script: GDScript = _script(SETUP_PATH)
	if script == null:
		return false
	script.call("apply_default", model, cat)
	return true


## SubstrateSetup.normalise; null while the class is missing.
static func normalise(model: AquariumModel, cat: RefCounted) -> Variant:
	var script: GDScript = _script(SETUP_PATH)
	if script == null:
		return null
	return script.call("normalise", model, cat)


## A SaveStore that normalises with the catalog, or null while SaveStore has no third `_init`
## parameter (a call with too many arguments would be a runtime error, not a clean failure).
static func save_store(clock: Callable, cat: RefCounted) -> SaveStore:
	if init_args(SAVE_STORE_PATH) < 3:
		return null
	var script: GDScript = _script(SAVE_STORE_PATH)
	return script.new(clock, null, cat) as SaveStore


# --- models ---


## A model on the given tank with the given substrate, set directly (test setup, no Command).
static func model_with(
	id: StringName, colour: Color, tank_id: StringName = &"tank_medium_1"
) -> AquariumModel:
	var model: AquariumModel = AquariumModel.new(STAMP)
	model.apply_set_tank_id(tank_id)
	model.apply_set_substrate(id, colour)
	return model


## model_with() plus 3 items, 2 fish and a 3 x 2 non-flat heightmap.
static func furnished(
	id: StringName, colour: Color, tank_id: StringName = &"tank_medium_1"
) -> AquariumModel:
	var model: AquariumModel = model_with(id, colour, tank_id)
	model.apply_set_name("Reef")
	model.apply_set_heightmap(PackedFloat32Array([0.0, 0.1, 0.2, 0.3, 0.4, 0.5]), Vector2i(3, 2))
	model.apply_insert_item(Factory.item("a0000001", &"rock_a", Vector3(0.1, 0.0, 0.0)), 0)
	model.apply_insert_item(Factory.coloured_item("a0000002", Color(0.2, 0.4, 0.6)), 1)
	model.apply_insert_item(Factory.item("a0000003", &"plant_fern", Vector3(-0.2, 0.1, 0.05)), 2)
	model.apply_insert_fish(Factory.fish("f0000001", &"neon_tetra", 1, "Nemo"), 0)
	model.apply_insert_fish(Factory.fish("f0000002", &"guppy", 0, ""), 1)
	return model


## Same 8-bit colour (the precision of the save file).
static func same_colour(a: Color, b: Color) -> bool:
	return a.to_rgba32() == b.to_rgba32()


## A readable name for failure messages.
static func hex(colour: Color) -> String:
	return "#" + colour.to_html(false).to_upper()
