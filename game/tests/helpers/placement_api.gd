extends RefCounted
## Late-bound access to the #31 classes (PlacementRules, the two commands, ItemCatalogSource,
## RotationStep, GroundRay, ItemHitTest, RotateHold, PlacementTuning, PlacementHint).
##
## The tests were written before those classes exist. A direct reference to a missing class is a
## parse error that aborts the whole run, so everything goes through load() and call(). Each
## function returns a harmless stand-in while a script is missing; every test asserts exists()
## first, so it fails with a readable message instead of passing on the stand-in.
##
## Contract of the technical plan (comment on #31, section 1), plus the test decisions where the
## plan is silent (also listed in the test file headers):
## - PlacementRules.new(tank_catalog, item_source, substrate_catalog) (#33, ADR 0012 Amendment 2;
##   the #31 form took the tank catalog only and is still used while the script has one argument),
##   allows(model, candidate, before) -> bool, const TOLERANCE_M, static
##   item_top(surface_m, footprint_cm, item_scale) -> float and static
##   is_point_inside(interior_size_m, x, z) -> bool.
## - PlaceItemCommand.new(model, item, rules); TransformItemCommand.new(model, uid, position,
##   rotation_y, rules).
## - ItemCatalogSource.new(), get_catalog(), is_loaded(), get_load_count(), static
##   from_catalog(catalog).
## - RotationStep.normalise(deg), step(deg, direction, fine); GroundRay.intersect(origin,
##   direction, plane_y) -> {ok, point}; ItemHitTest.nearest(origin, direction, entries) with each
##   entry a Dictionary {"transform": Transform3D, "aabb": AABB} (test decision).
## - RotateHold: press(direction, start_deg, fine), tick(delta_s, fine) -> int, release(),
##   cancel(), is_active(), get_direction(), get_start_deg(), get_pending_deg().
## - PlacementTuning constants.

const RULES := "res://model/placement_rules.gd"
const PLACE := "res://model/place_item_command.gd"
const TRANSFORM := "res://model/transform_item_command.gd"
const SOURCE := "res://catalog/item_catalog_source.gd"
const TUNING := "res://systems/placement/placement_tuning.gd"
const STEP := "res://systems/placement/rotation_step.gd"
const GROUND := "res://systems/placement/ground_ray.gd"
const HIT := "res://systems/placement/item_hit_test.gd"
const HOLD := "res://systems/placement/rotate_hold.gd"
const SYSTEM := "res://systems/placement/placement_system.gd"
const VIEW := "res://scenes/tank/items/placed_items_view.gd"
const HINT := "res://ui/placement/placement_hint.gd"
const CUE := "res://systems/placement/refusal_cue.gd"
const MISSING_NUMBER := -999.0
const MISSING_TEXT := "<missing>"


static func script_of(path: String) -> GDScript:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as GDScript


static func exists(path: String) -> bool:
	return script_of(path) != null


static func constant(path: String, wanted: String, fallback: Variant) -> Variant:
	var script: GDScript = script_of(path)
	if script == null:
		return fallback
	return script.get_script_constant_map().get(wanted, fallback)


## A PlacementTuning constant as a float, or MISSING_NUMBER.
static func tuning(wanted: String) -> float:
	return float(constant(TUNING, wanted, MISSING_NUMBER))


static func call_static(path: String, method: String, args: Array, fallback: Variant) -> Variant:
	var script: GDScript = script_of(path)
	if script == null or not declares_method(script, method):
		return fallback
	return script.callv(method, args)


## True when the script declares the method (static or not).
static func declares_method(script: Script, method: String) -> bool:
	for entry: Dictionary in script.get_script_method_list():
		if entry["name"] == method:
			return true
	return false


static func call_on(object: Object, method: String, args: Array, fallback: Variant) -> Variant:
	if object == null or not object.has_method(method):
		return fallback
	return object.callv(method, args)


# --- model layer ---


## The rules with the shipped tank and substrate catalogs and, unless given, the shipped items.
## With the #31 constructor (one argument) the old form is used, so the missing #33 behaviour
## shows as failing assertions and not as engine errors.
static func rules(source: RefCounted = null, substrates: SubstrateCatalog = null) -> RefCounted:
	var used: RefCounted = source
	if used == null:
		used = source_from(ItemCatalog.load_dirs())
	var used_substrates: SubstrateCatalog = substrates
	if used_substrates == null:
		used_substrates = SubstrateCatalog.load_dir()
	return rules_with(TankCatalog.load_dir(), used, used_substrates)


## The rules with exactly these three catalogs (null allowed, for the null cases of AC 9b).
static func rules_with(
	tanks: TankCatalog, source: RefCounted, substrates: SubstrateCatalog
) -> RefCounted:
	var script: GDScript = script_of(RULES)
	if script == null:
		return null
	if init_arg_count(script) >= 3:
		return script.new(tanks, source, substrates) as RefCounted
	return script.new(tanks) as RefCounted


static func init_arg_count(script: Script) -> int:
	for entry: Dictionary in script.get_script_method_list():
		if entry["name"] == &"_init":
			return (entry["args"] as Array).size()
	return 0


## allows(model, candidate, before) as a Variant: true, false or null while the rules are missing.
static func allows(
	used: RefCounted, model: AquariumModel, candidate: PlacedItem, before: PlacedItem
) -> Variant:
	return call_on(used, "allows", [model, candidate, before], null)


static func item_top(surface_m: float, footprint_cm: Vector3, item_scale: float) -> float:
	return float(call_static(RULES, "item_top", [surface_m, footprint_cm, item_scale], NAN))


## PlacementRules.TOLERANCE_M, or MISSING_NUMBER.
static func tolerance() -> float:
	return float(constant(RULES, "TOLERANCE_M", MISSING_NUMBER))


static func place_command(model: AquariumModel, item: PlacedItem, used: RefCounted) -> Command:
	var script: GDScript = script_of(PLACE)
	if script == null:
		return null
	return script.new(model, item, used) as Command


static func transform_command(
	model: AquariumModel, uid: String, position: Vector3, rotation_y: float, used: RefCounted
) -> Command:
	var script: GDScript = script_of(TRANSFORM)
	if script == null:
		return null
	return script.new(model, uid, position, rotation_y, used) as Command


# --- catalog source ---


static func new_source() -> RefCounted:
	var script: GDScript = script_of(SOURCE)
	if script == null:
		return null
	return script.new() as RefCounted


static func source_from(catalog: ItemCatalog) -> RefCounted:
	return call_static(SOURCE, "from_catalog", [catalog], null) as RefCounted


# --- pure helpers ---


static func normalise(deg: float) -> float:
	return float(call_static(STEP, "normalise", [deg], MISSING_NUMBER))


static func step(deg: float, direction: int, fine: bool) -> float:
	return float(call_static(STEP, "step", [deg, direction, fine], MISSING_NUMBER))


static func intersect(origin: Vector3, direction: Vector3, plane_y: float) -> Dictionary:
	var result: Variant = call_static(GROUND, "intersect", [origin, direction, plane_y], null)
	return result if result is Dictionary else {}


static func nearest(origin: Vector3, direction: Vector3, entries: Array) -> int:
	return int(call_static(HIT, "nearest", [origin, direction, entries], -999))


static func is_point_inside(interior: Vector3, x: float, z: float) -> Variant:
	return call_static(RULES, "is_point_inside", [interior, x, z], null)


static func new_hold() -> RefCounted:
	var script: GDScript = script_of(HOLD)
	if script == null:
		return null
	return script.new() as RefCounted


## A fresh RefusalCue (#33), or null while the script is missing.
static func new_cue() -> RefCounted:
	var script: GDScript = script_of(CUE)
	if script == null:
		return null
	return script.new() as RefCounted


## RefusalCue.power_at(t_s, base) (fresnel_power), or MISSING_NUMBER.
static func cue_power_at(t_s: float, base: float) -> float:
	return float(call_static(CUE, "power_at", [t_s, base], MISSING_NUMBER))


## RefusalCue.colour_at(t_s, base) (glow_colour, sRGB), or a transparent magenta while missing.
static func cue_colour_at(t_s: float, base: Color) -> Color:
	var result: Variant = call_static(CUE, "colour_at", [t_s, base], null)
	return result if result is Color else Color(1.0, 0.0, 1.0, 0.0)


## RefusalCue.lift_at(t_s) (glow_lift, linear), or NaN components while missing.
static func cue_lift_at(t_s: float) -> Vector3:
	var result: Variant = call_static(CUE, "lift_at", [t_s], null)
	return result if result is Vector3 else Vector3(NAN, NAN, NAN)


## RefusalCue.strength_at(t_s, base), or MISSING_NUMBER.
static func cue_strength_at(t_s: float, base: float) -> float:
	return float(call_static(CUE, "strength_at", [t_s, base], MISSING_NUMBER))


static func hint_key_labels() -> String:
	return str(call_static(HINT, "key_labels", [], MISSING_TEXT))
