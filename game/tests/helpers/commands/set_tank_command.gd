extends Command
## Test-only: sets the tank id.

var do_count: int = 0
var undo_count: int = 0

var _model: AquariumModel
var _new_tank: StringName
var _old_tank: StringName


func _init(model: AquariumModel, tank_id: StringName) -> void:
	_model = model
	_new_tank = tank_id


func do() -> bool:
	do_count += 1
	_old_tank = _model.get_tank_id()
	_model.apply_set_tank_id(_new_tank)
	return true


func undo() -> bool:
	undo_count += 1
	_model.apply_set_tank_id(_old_tank)
	return true
