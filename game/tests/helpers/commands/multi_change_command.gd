extends Command
## Test-only: sets name, then tank, then appends an item; undoes them in reverse order.

var do_count: int = 0
var undo_count: int = 0

var _model: AquariumModel
var _new_name: String
var _new_tank: StringName
var _item: PlacedItem
var _old_name: String
var _old_tank: StringName


func _init(model: AquariumModel, new_name: String, tank_id: StringName, item: PlacedItem) -> void:
	_model = model
	_new_name = new_name
	_new_tank = tank_id
	_item = item


func do() -> bool:
	do_count += 1
	if _model.has_uid(_item.uid):
		return false
	_old_name = _model.get_aquarium_name()
	_old_tank = _model.get_tank_id()
	_model.apply_set_name(_new_name)
	_model.apply_set_tank_id(_new_tank)
	return _model.apply_insert_item(_item, _model.get_item_count())


func undo() -> bool:
	undo_count += 1
	var removed: bool = _model.apply_remove_item(_item.uid)
	_model.apply_set_tank_id(_old_tank)
	_model.apply_set_name(_old_name)
	return removed
