extends Command
## Test-only: appends a complete item, uid fixed at creation.

var do_count: int = 0
var undo_count: int = 0

var _model: AquariumModel
var _item: PlacedItem


func _init(model: AquariumModel, item: PlacedItem) -> void:
	_model = model
	_item = item


func do() -> bool:
	do_count += 1
	if _model.has_uid(_item.uid):
		return false
	return _model.apply_insert_item(_item, _model.get_item_count())


func undo() -> bool:
	undo_count += 1
	return _model.apply_remove_item(_item.uid)
