extends Node
## Test-only listener that is freed while still connected to an EventBus signal.

var calls: int = 0


func on_history_changed(_can_undo: bool, _can_redo: bool) -> void:
	calls += 1


func on_command(_command: Command) -> void:
	calls += 1
