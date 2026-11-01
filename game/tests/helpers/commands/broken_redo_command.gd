extends Command
## Test-only: the first do() succeeds; every later do() fails. undo() succeeds.

var do_count: int = 0
var undo_count: int = 0

var _model: AquariumModel
var _tank: StringName
var _old_tank: StringName


func _init(model: AquariumModel, tank_id: StringName) -> void:
	_model = model
	_tank = tank_id


func do() -> bool:
	do_count += 1
	if do_count > 1:
		return false
	_old_tank = _model.get_tank_id()
	_model.apply_set_tank_id(_tank)
	return true


func undo() -> bool:
	undo_count += 1
	_model.apply_set_tank_id(_old_tank)
	return true
