class_name DeleteItemCommand
extends Command
## Deletes one placed item (#32). do() records the instance itself and its list index, undo()
## inserts the same instance at that index again, so uid, catalog id, transform and colour come
## back exactly. A uid that is not in the model is refused with the model untouched and no signal.

var _model: AquariumModel = null
var _uid: String = ""

var _item: PlacedItem = null
var _index: int = -1


func _init(model: AquariumModel, uid: String) -> void:
	_model = model
	_uid = uid


func do() -> bool:
	var index: int = _model.get_item_index(_uid)
	if index < 0:
		return false
	var item: PlacedItem = _model.get_item(_uid)
	if not _model.apply_remove_item(_uid):
		return false
	_item = item
	_index = index
	return true


func undo() -> bool:
	return _model.apply_insert_item(_item, _index)
