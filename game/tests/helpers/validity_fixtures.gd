extends RefCounted
## Fixtures of the #33 placement validity tests: in-memory item definitions with known footprints
## and categories, models on a chosen tank and substrate, and rules built on them.
##
## Tank interiors (x, y, z in m): small 0.40 x 0.27 x 0.25, medium 0.60 x 0.35 x 0.30, large
## 1.00 x 0.52 x 0.40; water lines 0.25, 0.33 and 0.50. Beds (fill depth): sand_fine and
## sand_black 0.03, gravel 0.04, pebbles_river 0.06. The shipped footprints in cm are river_stone
## 11 x 6 x 8, clay_amphora 9 x 14 x 8 and driftwood_branch 28 x 8 x 7 (x width, y height, z depth).

const Api := preload("res://tests/helpers/placement_api.gd")
const Factory := preload("res://tests/helpers/factory.gd")

const STAMP := "2026-11-01T12:00:00Z"
const CREAM := Color8(0xE8, 0xD9, 0xB0)
const SMALL: StringName = &"tank_small_1"
const MEDIUM: StringName = &"tank_medium_1"
const LARGE: StringName = &"tank_large_1"
const TANKS: Array[StringName] = [SMALL, MEDIUM, LARGE]
const SAND: StringName = &"sand_fine"
const PEBBLES: StringName = &"pebbles_river"
const STONE: StringName = &"river_stone"
const BRANCH: StringName = &"driftwood_branch"
const AMPHORA: StringName = &"clay_amphora"
const FAR: float = 0.0001
## Stand-ins for "within the tolerance" and "clearly beyond it" (the tolerance is 0.1 mm).
const INSIDE_TOLERANCE_M: float = 0.00005
const BEYOND_TOLERANCE_M: float = 0.00015


static func definition(
	id: StringName, category: ItemDefinition.Category, footprint_cm: Vector3
) -> ItemDefinition:
	var result: ItemDefinition = ItemDefinition.new()
	result.id = id
	result.name_key = "item.%s.name" % id
	result.category = category
	result.footprint_cm = footprint_cm
	return result


static func source_of(definitions: Array[ItemDefinition]) -> RefCounted:
	return Api.source_from(ItemCatalog.from_definitions(definitions))


## Rules over fixture definitions (the shipped tanks and substrates).
static func rules_of(definitions: Array[ItemDefinition]) -> RefCounted:
	return Api.rules(source_of(definitions))


static func model(tank_id: StringName = MEDIUM, substrate: StringName = SAND) -> AquariumModel:
	var result: AquariumModel = AquariumModel.new(STAMP)
	result.apply_set_tank_id(tank_id)
	result.apply_set_substrate(substrate, CREAM)
	return result


static func item(
	uid: String,
	catalog_id: StringName,
	x: float,
	z: float,
	rotation_y: float = 0.0,
	item_scale: float = 1.0
) -> PlacedItem:
	return Factory.item(uid, catalog_id, Vector3(x, 0.0, z), rotation_y, item_scale)


static func add(
	target: AquariumModel,
	uid: String,
	catalog_id: StringName,
	x: float,
	z: float,
	rotation_y: float = 0.0,
	item_scale: float = 1.0
) -> PlacedItem:
	var placed: PlacedItem = item(uid, catalog_id, x, z, rotation_y, item_scale)
	target.apply_insert_item(placed, target.get_item_count())
	return placed


static func interior(tank_id: StringName) -> Vector3:
	return TankCatalog.load_dir().get_definition(tank_id).interior_size_m


static func water_line(tank_id: StringName) -> float:
	return TankCatalog.load_dir().get_definition(tank_id).water_line_height_m


## The fill depth of a substrate in metres.
static func bed(substrate: StringName) -> float:
	return SubstrateCatalog.load_dir().get_definition(substrate).fill_depth_m


## The result of allows() as a bool (a missing implementation reads as false-by-null).
static func ok(
	rules: RefCounted, target: AquariumModel, candidate: PlacedItem, before: PlacedItem = null
) -> bool:
	return Api.allows(rules, target, candidate, before) == true


## True when the result is exactly false (so a missing rules script, null, is not a refusal).
static func refused(
	rules: RefCounted, target: AquariumModel, candidate: PlacedItem, before: PlacedItem = null
) -> bool:
	return Api.allows(rules, target, candidate, before) == false
