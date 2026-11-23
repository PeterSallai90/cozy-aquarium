extends RefCounted
## Late-bound access to the #35 game classes (ADR 0015): FishPersonality, FishSwimSim,
## FishSwimParams, FishSwimWorld, FishSwimLimits, FishSwimState, FishSwimTuning,
## FishGroupStyleTuning and FishTailPhase. The tests were written before those classes exist, and
## a direct reference to a missing class is a parse error that aborts the whole run; going through
## load() keeps every other suite running and each test fails on its own with a readable message.
##
## The API the tests rely on is the one of the technical plan of #35 (section 2):
## - FishPersonality.derive(uid), to_array(), SALTS, FACTOR_MIN, FACTOR_SPAN, DEPTH_SPAN and the
##   fields speed, boldness, sociability, idle_share, depth_preference (a plain RefCounted, new()).
## - FishSwimTuning.load_default() and the resource res://catalog/behaviour/fish_swim_tuning.tres.
## - FishSwimParams.create(species, personality, tuning, extents).
## - FishSwimWorld.new() with the fields interior_size_m, water_line_m, surface_at and
##   grain_allowance_m.
## - FishSwimSim.new(tuning, rng) with set_world, add_fish(uid, params, rest_pose), remove_fish,
##   replace_params, clear, step, get_state, set_paused, is_paused, set_override, clear_override,
##   begin_recovery and get_uids.
## - FishSwimState (read only): position, velocity, speed, yaw, yaw_rate, travel_pitch, pitch,
##   shader_speed, mode, recovering, pinned, intends_to_move, darts_started, low_speed_time.
## - FishTailPhase.advance(phase, swim_speed, frequency, speed_scale, delta).

const PERSONALITY_PATH := "res://model/fish_personality.gd"
const SIM_PATH := "res://systems/fish/fish_swim_sim.gd"
const PARAMS_PATH := "res://systems/fish/fish_swim_params.gd"
const WORLD_PATH := "res://systems/fish/fish_swim_world.gd"
const LIMITS_PATH := "res://systems/fish/fish_swim_limits.gd"
const STATE_PATH := "res://systems/fish/fish_swim_state.gd"
const TUNING_PATH := "res://catalog/fish_swim_tuning.gd"
const STYLE_PATH := "res://catalog/fish_group_style_tuning.gd"
const TUNING_RES := "res://catalog/behaviour/fish_swim_tuning.tres"
const TAIL_PATH := "res://scenes/tank/fish/fish_tail_phase.gd"
const POSE_PATH := "res://model/fish_rest_pose.gd"
const SYSTEMS_DIR := "res://systems/fish"

## The five trait names in the frozen order (ADR 0015 rule 1) and their salts.
const TRAIT_NAMES: PackedStringArray = [
	"speed", "boldness", "sociability", "idle_share", "depth_preference"
]
const TRAIT_SALTS: PackedStringArray = [
	"fish.trait.speed",
	"fish.trait.boldness",
	"fish.trait.sociability",
	"fish.trait.idle_share",
	"fish.trait.depth_preference",
]
## FishSpecies.GroupStyle as fixed by the plan (UNSET = 0, append-only).
const STYLE_UNSET := 0
const STYLE_SOLITARY := 1
const STYLE_TIGHT_SCHOOL := 2
const STYLE_LOOSE_GROUP := 3
const STYLE_FORAGING_GROUP := 4
## Fallback order of FishSwimState.mode when the enum cannot be read.
const MODE_ORDER: PackedStringArray = ["IDLE", "CRUISE", "DART", "OVERRIDE"]
## The species top speed factor of the BA decision (k = 3) in body lengths per second.
const TOP_SPEED_K := 3.0
const MISSING_NUMBER := -999.0

static var _tuning: Resource = null
static var _modes: Dictionary = {}


static func script_of(path: String) -> GDScript:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as GDScript


static func has(path: String) -> bool:
	return ResourceLoader.exists(path)


## A constant of a script by name, or `fallback` when the script or the constant is missing.
static func constant(path: String, wanted: String, fallback: Variant) -> Variant:
	var script: GDScript = script_of(path)
	if script == null:
		return fallback
	return script.get_script_constant_map().get(wanted, fallback)


## The number of arguments of a static or member function of a script, or -1 when it is missing.
static func argument_count(path: String, function_name: String) -> int:
	var script: GDScript = script_of(path)
	if script == null:
		return -1
	for entry: Dictionary in script.get_script_method_list():
		if entry["name"] == StringName(function_name):
			return (entry["args"] as Array).size()
	return -1


## True when the script of `path` declares the function.
static func declares(path: String, function_name: String) -> bool:
	return argument_count(path, function_name) >= 0


## The names of the script variables (members) of a script.
static func members(path: String) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var script: GDScript = script_of(path)
	if script == null:
		return result
	for entry: Dictionary in script.get_script_property_list():
		result.append(String(entry["name"]))
	return result


# --- personality ---


## FishPersonality.derive(uid); null while the class is missing.
static func personality(uid: String) -> Object:
	var script: GDScript = script_of(PERSONALITY_PATH)
	if script == null:
		return null
	return script.call("derive", uid) as Object


## A FishPersonality with the five traits set by hand (extreme personalities); null while missing.
static func personality_of(values: PackedFloat64Array) -> Object:
	var script: GDScript = script_of(PERSONALITY_PATH)
	if script == null:
		return null
	var result: Object = script.new() as Object
	for index: int in TRAIT_NAMES.size():
		result.set(TRAIT_NAMES[index], values[index])
	return result


## The five traits of a uid in the frozen order, empty while the class is missing.
static func traits(uid: String) -> PackedFloat64Array:
	var made: Object = personality(uid)
	if made == null:
		return PackedFloat64Array()
	return made.call("to_array") as PackedFloat64Array


# --- tuning, params, world, sim ---


## The shipped global tuning resource, loaded once; null while it is missing.
static func tuning() -> Resource:
	if _tuning != null:
		return _tuning
	var script: GDScript = script_of(TUNING_PATH)
	if script != null and declares(TUNING_PATH, "load_default"):
		_tuning = script.call("load_default") as Resource
	elif ResourceLoader.exists(TUNING_RES):
		_tuning = load(TUNING_RES) as Resource
	return _tuning


## A copy of the shipped tuning with the given fields changed (never touches the shared one).
static func tuning_with(changes: Dictionary) -> Resource:
	var source: Resource = tuning()
	if source == null:
		return null
	var copy: Resource = source.duplicate(true) as Resource
	for key: Variant in changes:
		copy.set(str(key), changes[key])
	return copy


static func make_params(species: Resource, made: Object, extents: Object) -> Object:
	var script: GDScript = script_of(PARAMS_PATH)
	var shared: Resource = tuning()
	if script == null or shared == null or made == null:
		return null
	return script.call("create", species, made, shared, extents) as Object


static func make_world(
	interior_size_m: Vector3, water_line_m: float, surface: Callable, allowance_m: float
) -> Object:
	var script: GDScript = script_of(WORLD_PATH)
	if script == null:
		return null
	var world: Object = script.new() as Object
	world.set("interior_size_m", interior_size_m)
	world.set("water_line_m", water_line_m)
	world.set("surface_at", surface)
	world.set("grain_allowance_m", allowance_m)
	return world


## A FishSwimSim with the shipped tuning and a random source seeded with `seed_value`.
static func make_sim(seed_value: int = 777, with_tuning: Resource = null) -> Object:
	var script: GDScript = script_of(SIM_PATH)
	var used: Resource = with_tuning if with_tuning != null else tuning()
	if script == null or used == null:
		return null
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed_value
	return script.new(used, random) as Object


## A FishRestPose.Pose with the three values set (a hand-made start for a fish).
static func pose_of(position: Vector3, yaw: float, pinned: bool = false) -> Object:
	var script: GDScript = script_of(POSE_PATH)
	if script == null:
		return null
	var pose_class: GDScript = script.get_script_constant_map().get("Pose") as GDScript
	if pose_class == null:
		return null
	var pose: Object = pose_class.new() as Object
	pose.set("position", position)
	pose.set("yaw", yaw)
	pose.set("pinned", pinned)
	return pose


## The value of an enum constant of FishSwimState (mode) by name, falling back to the plan order.
static func mode_id(mode_name: String) -> int:
	if _modes.is_empty():
		var found: bool = false
		var script: GDScript = script_of(STATE_PATH)
		if script != null:
			for value: Variant in script.get_script_constant_map().values():
				if value is Dictionary and (value as Dictionary).has("IDLE"):
					if (value as Dictionary).has("CRUISE") and (value as Dictionary).has("DART"):
						_modes = (value as Dictionary).duplicate()
						found = true
		if not found:
			for index: int in MODE_ORDER.size():
				_modes[MODE_ORDER[index]] = index
	return int(_modes.get(mode_name, -1))


## A field of a state object as a float (MISSING_NUMBER when the state is missing).
static func number(state: Object, field: String) -> float:
	if state == null:
		return MISSING_NUMBER
	return float(state.get(field))


static func vector(state: Object, field: String) -> Vector3:
	if state == null:
		return Vector3.ONE * MISSING_NUMBER
	return state.get(field) as Vector3


static func flag(state: Object, field: String) -> bool:
	return state != null and bool(state.get(field))
