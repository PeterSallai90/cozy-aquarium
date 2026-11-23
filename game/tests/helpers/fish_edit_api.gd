extends RefCounted
## Late-bound access to the #36 model and UI classes (FishDefaultName, AddFishCommand,
## RemoveFishCommand, FishNameText). They do not exist when the tests are written, and a direct
## reference to a missing class is a parse error that aborts the whole run. Every function returns
## a harmless stand-in (null, empty text, MISSING) when the script is missing, so each test fails
## on its own with a readable message.

const DEFAULT_NAME := "res://model/fish_default_name.gd"
const ADD := "res://model/add_fish_command.gd"
const REMOVE := "res://model/remove_fish_command.gd"
const NAME_TEXT := "res://ui/fish/fish_name_text.gd"
const HASH := "res://model/fish_hash.gd"

const MISSING := "<missing>"
const MISSING_INT := -999


static func exists(path: String) -> bool:
	return ResourceLoader.exists(path)


static func _script(path: String) -> GDScript:
	return load(path) as GDScript if ResourceLoader.exists(path) else null


static func constant(path: String, wanted: String, fallback: Variant) -> Variant:
	var script: GDScript = _script(path)
	if script == null:
		return fallback
	return script.get_script_constant_map().get(wanted, fallback)


# --- FishDefaultName ---


static func count() -> int:
	return constant(DEFAULT_NAME, "COUNT", MISSING_INT)


static func key_for(uid: String) -> String:
	var script: GDScript = _script(DEFAULT_NAME)
	return MISSING if script == null else script.call("key_for", uid)


static func key_at(index: int) -> String:
	var script: GDScript = _script(DEFAULT_NAME)
	return MISSING if script == null else script.call("key_at", index)


static func index_for_unit(unit: float) -> int:
	var script: GDScript = _script(DEFAULT_NAME)
	return MISSING_INT if script == null else script.call("index_for_unit", unit)


static func all_keys() -> PackedStringArray:
	var script: GDScript = _script(DEFAULT_NAME)
	if script == null:
		return PackedStringArray()
	return script.call("all_keys")


# --- commands ---


## AddFishCommand.new(model, fish); null while the class is missing.
static func add_command(model: AquariumModel, fish: FishInstance) -> Command:
	var script: GDScript = _script(ADD)
	return null if script == null else script.new(model, fish) as Command


## RemoveFishCommand.new(model, uid); null while the class is missing.
static func remove_command(model: AquariumModel, uid: String) -> Command:
	var script: GDScript = _script(REMOVE)
	return null if script == null else script.new(model, uid) as Command


## AddFishCommand.make_fish(uid, species, rng); null while the class is missing.
static func make_fish(
	uid: String, species: FishSpecies, rng: RandomNumberGenerator
) -> FishInstance:
	var script: GDScript = _script(ADD)
	if script == null:
		return null
	return script.call("make_fish", uid, species, rng) as FishInstance


# --- FishNameText ---


static func shown_name(fish: FishInstance, translator: Object) -> String:
	var script: GDScript = _script(NAME_TEXT)
	return MISSING if script == null else script.call("shown_name", fish, translator)


static func one_line(text: String) -> String:
	var script: GDScript = _script(NAME_TEXT)
	return MISSING if script == null else script.call("one_line", text)
