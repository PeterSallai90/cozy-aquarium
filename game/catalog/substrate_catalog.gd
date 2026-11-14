class_name SubstrateCatalog
extends RefCounted
## The substrate definitions by id. Loaded from a directory of .tres files; uses
## ResourceLoader.list_directory() so it also works in exported builds (remapped resources).
## Colours are exact 8-bit values and are compared as such (Color.to_rgba32), so a swatch still
## matches after a save and load.

const DEFAULT_ID: StringName = &"sand_fine"

var _definitions: Dictionary = {}
var _ids: Array[StringName] = []


static func load_dir(path: String = "res://catalog/substrates") -> SubstrateCatalog:
	var definitions: Array[SubstrateDefinition] = []
	var names: PackedStringArray = ResourceLoader.list_directory(path)
	names.sort()
	for entry: String in names:
		if entry.ends_with("/"):
			continue
		var file: String = entry.trim_suffix(".remap")
		if not file.ends_with(".tres"):
			continue
		var definition: SubstrateDefinition = load(path.path_join(file)) as SubstrateDefinition
		if definition != null:
			definitions.append(definition)
	return from_definitions(definitions)


static func from_definitions(definitions: Array[SubstrateDefinition]) -> SubstrateCatalog:
	var catalog: SubstrateCatalog = SubstrateCatalog.new()
	for definition: SubstrateDefinition in definitions:
		catalog._definitions[definition.id] = definition
	var ids: Array[StringName] = []
	for id: Variant in catalog._definitions.keys():
		ids.append(id as StringName)
	ids.sort_custom(catalog._before)
	catalog._ids = ids
	return catalog


## The definition for `id`, or null when unknown.
func get_definition(id: StringName) -> SubstrateDefinition:
	return _definitions.get(id) as SubstrateDefinition


## The ids in chooser order: by sort_order, then by id.
func get_ids() -> Array[StringName]:
	return _ids.duplicate()


## The definition of DEFAULT_ID, or null when the catalog has none.
func get_default() -> SubstrateDefinition:
	return get_definition(DEFAULT_ID)


## Index of `colour` in the swatches of `id`, -1 when it is none or the id is unknown.
func swatch_index(id: StringName, colour: Color) -> int:
	var definition: SubstrateDefinition = get_definition(id)
	if definition == null:
		return -1
	for index: int in definition.colour_swatches.size():
		if definition.colour_swatches[index].to_rgba32() == colour.to_rgba32():
			return index
	return -1


func is_swatch(id: StringName, colour: Color) -> bool:
	return swatch_index(id, colour) >= 0


## The colour a pick of `picked_id` gives: the type in use keeps its colour (even one that is no
## swatch), another known type gives its default colour, an unknown id keeps the current colour.
func colour_for_pick(current_id: StringName, current_colour: Color, picked_id: StringName) -> Color:
	if picked_id == current_id:
		return current_colour
	var definition: SubstrateDefinition = get_definition(picked_id)
	if definition == null:
		return current_colour
	return definition.default_colour


func _before(a: StringName, b: StringName) -> bool:
	var order_a: int = _definitions[a].sort_order
	var order_b: int = _definitions[b].sort_order
	if order_a != order_b:
		return order_a < order_b
	return String(a) < String(b)
