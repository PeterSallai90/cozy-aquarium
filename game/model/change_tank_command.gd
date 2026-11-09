class_name ChangeTankCommand
extends Command
## Changes the tank of the model. Clears items, fish and the heightmap in the same undoable step;
## substrate id and colour stay. The tank id is written last, so tank_changed fires once, after the
## contents are gone. Undo writes the old id first, then brings the contents back.

var _model: AquariumModel = null
var _catalog: TankCatalog = null
var _new_id: StringName = &""

var _old_id: StringName = &""
var _old_items: Array[PlacedItem] = []
var _old_fish: Array[FishInstance] = []
var _old_heightmap: PackedFloat32Array = PackedFloat32Array()
var _old_heightmap_size: Vector2i = Vector2i.ZERO
var _heightmap_cleared: bool = false


func _init(model: AquariumModel, catalog: TankCatalog, tank_id: StringName) -> void:
	_model = model
	_catalog = catalog
	_new_id = tank_id


## True when the heightmap is the empty array of size (0, 0); anything else counts as sculpted.
static func is_heightmap_flat(model: AquariumModel) -> bool:
	return model.get_heightmap_size() == Vector2i.ZERO and model.get_heightmap().is_empty()


## True when changing the tank would remove something: an item, a fish or a sculpted heightmap.
static func would_clear(model: AquariumModel) -> bool:
	return model.get_item_count() > 0 or model.get_fish_count() > 0 or not is_heightmap_flat(model)


func do() -> bool:
	if _new_id == _model.get_tank_id():
		return false
	if _new_id == &"" or _catalog == null or _catalog.get_definition(_new_id) == null:
		push_error('ChangeTankCommand: unknown tank id "%s"' % _new_id)
		return false
	_old_id = _model.get_tank_id()
	_old_items = _model.get_items()
	_old_fish = _model.get_fish_list()
	_old_heightmap = _model.get_heightmap()
	_old_heightmap_size = _model.get_heightmap_size()
	_heightmap_cleared = not is_heightmap_flat(_model)
	for fish: FishInstance in _old_fish:
		_model.apply_remove_fish(fish.uid)
	for index: int in range(_old_items.size() - 1, -1, -1):
		_model.apply_remove_item(_old_items[index].uid)
	if _heightmap_cleared:
		_model.apply_set_heightmap(PackedFloat32Array(), Vector2i.ZERO)
	_model.apply_set_tank_id(_new_id)
	return true


func undo() -> bool:
	_model.apply_set_tank_id(_old_id)
	if _heightmap_cleared:
		_model.apply_set_heightmap(_old_heightmap, _old_heightmap_size)
	for index: int in _old_items.size():
		_model.apply_insert_item(_old_items[index], index)
	for index: int in _old_fish.size():
		_model.apply_insert_fish(_old_fish[index], index)
	return true
