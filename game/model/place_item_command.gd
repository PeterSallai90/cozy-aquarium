class_name PlaceItemCommand
extends Command
## Puts one complete PlacedItem (uid included, fixed by the caller) at the end of the item list.
## Redo re-inserts it at the index of the first do(); undo removes it. Refuses a null item, a used
## uid and anything PlacementRules does not allow, with the model untouched and no signal.

var _model: AquariumModel = null
var _item: PlacedItem = null
var _rules: PlacementRules = null
var _index: int = -1


func _init(model: AquariumModel, item: PlacedItem, rules: PlacementRules) -> void:
	_model = model
	_item = item
	_rules = rules


func do() -> bool:
	if _model == null or _item == null or _item.uid.is_empty() or _model.has_uid(_item.uid):
		return false
	if _rules == null or not _rules.allows(_model, _item, null):
		return false
	var at: int = _index
	if at < 0 or at > _model.get_item_count():
		at = _model.get_item_count()
	if not _model.apply_insert_item(_item, at):
		return false
	_index = at
	return true


func undo() -> bool:
	return _model.apply_remove_item(_item.uid)
