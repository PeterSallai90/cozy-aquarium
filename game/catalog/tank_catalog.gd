class_name TankCatalog
extends RefCounted
## The tank definitions by id. Loaded from a directory of .tres files; uses
## ResourceLoader.list_directory() so it also works in exported builds (remapped resources).

var _definitions: Dictionary = {}
var _ids: Array[StringName] = []


static func load_dir(path: String = "res://catalog/tanks") -> TankCatalog:
	var definitions: Array[TankDefinition] = []
	var names: PackedStringArray = ResourceLoader.list_directory(path)
	names.sort()
	for entry: String in names:
		if entry.ends_with("/"):
			continue
		var file: String = entry.trim_suffix(".remap")
		if not file.ends_with(".tres"):
			continue
		var definition: TankDefinition = load(path.path_join(file)) as TankDefinition
		if definition != null:
			definitions.append(definition)
	return from_definitions(definitions)


static func from_definitions(definitions: Array[TankDefinition]) -> TankCatalog:
	var catalog: TankCatalog = TankCatalog.new()
	for definition: TankDefinition in definitions:
		if not catalog._definitions.has(definition.id):
			catalog._ids.append(definition.id)
		catalog._definitions[definition.id] = definition
	return catalog


## The definition for `id`, or null when unknown.
func get_definition(id: StringName) -> TankDefinition:
	return _definitions.get(id) as TankDefinition


func get_ids() -> Array[StringName]:
	return _ids.duplicate()
