class_name ItemCatalog
extends RefCounted
## The placeable items (rocks, wood, ornaments, plants) by id. Loaded from directories of .tres
## files; uses ResourceLoader.list_directory() so it also works in exported builds. A definition
## that fails validation is skipped and reported through get_skipped(); nothing is logged (the
## reasons are developer text, ADR 0004). The loader never checks that a referenced file exists.

const DEFAULT_DIRS: Array[String] = ["res://catalog/decor", "res://catalog/plants"]

static var _id_pattern: RegEx = null
static var _device_pattern: RegEx = null

var _definitions: Dictionary = {}
var _ids: Array[StringName] = []
var _skipped: Array[SkippedItem] = []


## One skipped definition: where it came from and why.
class SkippedItem:
	extends RefCounted
	## load_dirs: the res:// file path; from_definitions: "definitions[<index>]".
	var source: String = ""
	## Developer text in English, never translated, never logged.
	var reason: String = ""


## Loads every .tres of the directories, in the given order (the order decides duplicate ids).
static func load_dirs(paths: Array[String] = DEFAULT_DIRS) -> ItemCatalog:
	var resources: Array[Resource] = []
	var sources: Array[String] = []
	for path: String in paths:
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


static func from_definitions(definitions: Array[ItemDefinition]) -> ItemCatalog:
	var resources: Array[Resource] = []
	var sources: Array[String] = []
	for index: int in definitions.size():
		resources.append(definitions[index])
		sources.append("definitions[%d]" % index)
	return _build(resources, sources)


## True when the whole string is a safe item id: [a-z][a-z0-9_]{0,47}, no Windows device name.
static func is_valid_id(id: String) -> bool:
	if _id_pattern == null:
		_id_pattern = RegEx.new()
		_id_pattern.compile("\\A[a-z][a-z0-9_]{0,47}\\z")
		_device_pattern = RegEx.new()
		_device_pattern.compile("\\A(con|prn|aux|nul|com[1-9]|lpt[1-9])\\z")
	if _id_pattern.search(id) == null:
		return false
	return _device_pattern.search(id) == null


## The definition for `id`, or null when unknown.
func get_definition(id: StringName) -> ItemDefinition:
	return _definitions.get(id) as ItemDefinition


## The ids in catalog order: category (rocks, wood, ornaments, plants), sort_order, id.
func get_ids() -> Array[StringName]:
	return _ids.duplicate()


## The ids of one category in catalog order; empty for UNSET or an unknown value.
func get_ids_in_category(category: ItemDefinition.Category) -> Array[StringName]:
	var result: Array[StringName] = []
	for id: StringName in _ids:
		if (_definitions[id] as ItemDefinition).category == category:
			result.append(id)
	return result


## One entry per skipped definition, in input order.
func get_skipped() -> Array[ItemCatalog.SkippedItem]:
	return _skipped.duplicate()


static func _build(resources: Array[Resource], sources: Array[String]) -> ItemCatalog:
	var catalog: ItemCatalog = ItemCatalog.new()
	var winners: Dictionary = {}
	for index: int in resources.size():
		var source: String = sources[index]
		var reason: String = _invalid_reason(resources[index])
		if reason.is_empty():
			var definition: ItemDefinition = resources[index] as ItemDefinition
			if winners.has(definition.id):
				reason = (
					"duplicate id %s, kept the one from %s"
					% [definition.id, winners[definition.id]]
				)
			else:
				winners[definition.id] = source
				catalog._definitions[definition.id] = definition
		if not reason.is_empty():
			var skipped: SkippedItem = SkippedItem.new()
			skipped.source = source
			skipped.reason = reason
			catalog._skipped.append(skipped)
	var ids: Array[StringName] = []
	for id: Variant in catalog._definitions.keys():
		ids.append(id as StringName)
	ids.sort_custom(catalog._before)
	catalog._ids = ids
	return catalog


static func _invalid_reason(resource: Resource) -> String:
	var definition: ItemDefinition = resource as ItemDefinition
	if definition == null:
		return "not an ItemDefinition"
	if String(definition.id).is_empty():
		return "empty id"
	if not is_valid_id(String(definition.id)):
		return "id breaks the item id rule"
	if (
		definition.category == ItemDefinition.Category.UNSET
		or not ItemDefinition.Category.values().has(definition.category)
	):
		return "category is unset or unknown"
	if definition.name_key.is_empty():
		return "empty name_key"
	if not definition.aquarium_safe:
		return "not aquarium safe"
	return ""


func _before(a: StringName, b: StringName) -> bool:
	var first: ItemDefinition = _definitions[a]
	var second: ItemDefinition = _definitions[b]
	if first.category != second.category:
		return first.category < second.category
	if first.sort_order != second.sort_order:
		return first.sort_order < second.sort_order
	return String(a) < String(b)
