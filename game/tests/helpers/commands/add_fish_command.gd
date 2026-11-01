extends Command
## Test-only: appends a complete fish, uid fixed at creation.

var do_count: int = 0
var undo_count: int = 0

var _model: AquariumModel
var _fish: FishInstance


func _init(model: AquariumModel, fish: FishInstance) -> void:
	_model = model
	_fish = fish


func do() -> bool:
	do_count += 1
	if _model.has_uid(_fish.uid):
		return false
	return _model.apply_insert_fish(_fish, _model.get_fish_count())


func undo() -> bool:
	undo_count += 1
	return _model.apply_remove_fish(_fish.uid)
