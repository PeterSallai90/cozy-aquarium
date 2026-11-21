class_name FishCatalog
extends RefCounted
## The fish species by id. Loaded from a directory of .tres files; uses
## ResourceLoader.list_directory() so it also works in exported builds. A definition that fails
## validation (or repeats an id) is skipped and reported through get_skipped(); nothing is logged.

const DEFAULT_DIR: String = "res://catalog/fish"

static var _id_pattern: RegEx = null

var _definitions: Dictionary = {}
var _ids: Array[String] = []
var _skipped: Array[SkippedSpecies] = []


## One skipped definition: where it came from and why.
class SkippedSpecies:
	extends RefCounted
	## load_dir: the res:// file path; from_definitions: "definitions[<index>]".
	var source: String = ""
	## Developer text in English, never translated, never logged.
	var reason: String = ""


## Loads every .tres of the directory in name order (the order decides duplicate ids).
static func load_dir(path: String = DEFAULT_DIR) -> FishCatalog:
	var resources: Array[Resource] = []
	var sources: Array[String] = []
	var names: PackedStringArray = ResourceLoader.list_directory(path)
	names.sort()
	for entry: String in names:
		if entry.ends_with("/"):
			continue
		var file: String = entry.trim_suffix(".remap")
		if not file.ends_with(".tres"):
			continue
		var full: String = path.path_join(file)
		resources.append(load(full) as Resource)
		sources.append(full)
	return _build(resources, sources)


static func from_definitions(definitions: Array[FishSpecies]) -> FishCatalog:
	var resources: Array[Resource] = []
	var sources: Array[String] = []
	for index: int in definitions.size():
		resources.append(definitions[index])
		sources.append("definitions[%d]" % index)
	return _build(resources, sources)


## True when the whole string is a safe species id: [a-z][a-z0-9_]{0,47}.
static func is_valid_id(id: String) -> bool:
	if _id_pattern == null:
		_id_pattern = RegEx.new()
		_id_pattern.compile("\\A[a-z][a-z0-9_]{0,47}\\z")
	return _id_pattern.search(id) != null


## The definition for `id`, or null when unknown.
func get_definition(id: StringName) -> FishSpecies:
	return _definitions.get(id) as FishSpecies


## The ids in catalog order (alphabetical). Plain Strings: a Godot sort of StringName values is
## by hash, not alphabetical, so callers (and tests) that sort the list get the order they expect.
func get_ids() -> Array[String]:
	return _ids.duplicate()


## One entry per skipped definition, in input order.
func get_skipped() -> Array[SkippedSpecies]:
	return _skipped.duplicate()


static func _build(resources: Array[Resource], sources: Array[String]) -> FishCatalog:
	var catalog: FishCatalog = FishCatalog.new()
	var winners: Dictionary = {}
	for index: int in resources.size():
		var source: String = sources[index]
		var reason: String = _invalid_reason(resources[index])
		if reason.is_empty():
			var definition: FishSpecies = resources[index] as FishSpecies
			if winners.has(definition.id):
				reason = (
					"duplicate id %s, kept the one from %s"
					% [definition.id, winners[definition.id]]
				)
			else:
				winners[definition.id] = source
				catalog._definitions[definition.id] = definition
		if not reason.is_empty():
			var skipped: SkippedSpecies = SkippedSpecies.new()
			skipped.source = source
			skipped.reason = reason
			catalog._skipped.append(skipped)
	var ids: Array[String] = []
	for id: Variant in catalog._definitions.keys():
		ids.append(String(id as StringName))
	ids.sort()
	catalog._ids = ids
	return catalog


static func _invalid_reason(resource: Resource) -> String:
	var definition: FishSpecies = resource as FishSpecies
	if definition == null:
		return "not a FishSpecies"
	if String(definition.id).is_empty():
		return "empty id"
	if not is_valid_id(String(definition.id)):
		return "id breaks the species id rule"
	if definition.name_key.is_empty():
		return "empty name_key"
	if definition.scene == null:
		return "no scene"
	if definition.colour_variants.is_empty():
		return "no colour variants"
	if definition.adult_length_cm <= 0.0:
		return "adult_length_cm is not above 0"
	return ""
