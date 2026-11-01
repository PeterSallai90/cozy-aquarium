extends Command
## Test-only: removes an item by uid and restores it at its original index.

var do_count: int = 0
var undo_count: int = 0

var _model: AquariumModel
var _uid: String
var _stored: PlacedItem
var _index: int = -1


func _init(model: AquariumModel, uid: String) -> void:
	_model = model
	_uid = uid


func do() -> bool:
	do_count += 1
	var index: int = _model.get_item_index(_uid)
	if index < 0:
		return false
	_stored = _model.get_item_at(index)
	_index = index
	return _model.apply_remove_item(_uid)


func undo() -> bool:
	undo_count += 1
	return _model.apply_insert_item(_stored, _index)
