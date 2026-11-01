extends Command
## Test-only: replaces an item with a copy that has the same uid.

var do_count: int = 0
var undo_count: int = 0

var _model: AquariumModel
var _after: PlacedItem
var _before: PlacedItem


func _init(model: AquariumModel, after: PlacedItem) -> void:
	_model = model
	_after = after


func do() -> bool:
	do_count += 1
	var old: PlacedItem = _model.get_item(_after.uid)
	if old == null:
		return false
	_before = old
	return _model.apply_replace_item(_after)


func undo() -> bool:
	undo_count += 1
	return _model.apply_replace_item(_before)
