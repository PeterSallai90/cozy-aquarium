class_name RemoveFishCommand
extends Command
## Removes one fish. do() records the instance itself and its list index, undo() inserts the same
## instance at that index again. A uid that is not in the model is refused with the model
## untouched and no signal.

var _model: AquariumModel = null
var _uid: String = ""

var _fish: FishInstance = null
var _index: int = -1


func _init(model: AquariumModel, uid: String) -> void:
	_model = model
	_uid = uid


func do() -> bool:
	if _model == null:
		return false
	var index: int = _model.get_fish_index(_uid)
	if index < 0:
		return false
	var fish: FishInstance = _model.get_fish(_uid)
	if not _model.apply_remove_fish(_uid):
		return false
	_fish = fish
	_index = index
	return true


func undo() -> bool:
	return _model.apply_insert_fish(_fish, _index)
