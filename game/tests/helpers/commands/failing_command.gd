extends Command
## Test-only: do() reports failure and touches nothing.

var do_count: int = 0
var undo_count: int = 0

var _model: AquariumModel


func _init(model: AquariumModel) -> void:
	_model = model


func do() -> bool:
	do_count += 1
	return false


func undo() -> bool:
	undo_count += 1
	return false
