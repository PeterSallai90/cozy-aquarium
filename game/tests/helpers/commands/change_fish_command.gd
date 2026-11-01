extends Command
## Test-only: replaces a fish with a copy that has the same uid.

var do_count: int = 0
var undo_count: int = 0

var _model: AquariumModel
var _after: FishInstance
var _before: FishInstance


func _init(model: AquariumModel, after: FishInstance) -> void:
	_model = model
	_after = after


func do() -> bool:
	do_count += 1
	var old: FishInstance = _model.get_fish(_after.uid)
	if old == null:
		return false
	_before = old
	return _model.apply_replace_fish(_after)


func undo() -> bool:
	undo_count += 1
	return _model.apply_replace_fish(_before)
