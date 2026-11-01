class_name CommandHistory
extends RefCounted
## Undo and redo stacks of executed commands. Holds no model reference.
##
## Model signals fire inside do()/undo(), before the stacks change. History signals fire after
## the stacks changed. Nested calls (from any signal handler) are rejected, never queued.

signal executed(command: Command)
signal undone(command: Command)
signal redone(command: Command)
signal history_changed(can_undo: bool, can_redo: bool)

var _undo_stack: Array[Command] = []
var _redo_stack: Array[Command] = []
var _busy: bool = false


## Runs the command. Returns false if it failed; a failed command is not recorded.
func execute(command: Command) -> bool:
	if _busy:
		push_error("CommandHistory: re-entrant execute() rejected")
		return false
	if command == null:
		push_error("CommandHistory: execute() called with a null command")
		return false
	_busy = true
	var ok: bool = command.do()
	if not ok:
		_busy = false
		return false
	_undo_stack.push_back(command)
	_redo_stack.clear()
	executed.emit(command)
	history_changed.emit(can_undo(), can_redo())
	_busy = false
	return true


func undo() -> bool:
	if _busy:
		push_error("CommandHistory: re-entrant undo() rejected")
		return false
	if _undo_stack.is_empty():
		return false
	_busy = true
	var command: Command = _undo_stack.back()
	if not command.undo():
		_fail("undo", command)
		return false
	_undo_stack.pop_back()
	_redo_stack.push_back(command)
	undone.emit(command)
	history_changed.emit(can_undo(), can_redo())
	_busy = false
	return true


func redo() -> bool:
	if _busy:
		push_error("CommandHistory: re-entrant redo() rejected")
		return false
	if _redo_stack.is_empty():
		return false
	_busy = true
	var command: Command = _redo_stack.back()
	if not command.do():
		_fail("redo", command)
		return false
	_redo_stack.pop_back()
	_undo_stack.push_back(command)
	redone.emit(command)
	history_changed.emit(can_undo(), can_redo())
	_busy = false
	return true


## Empties both stacks. Always emits history_changed(false, false).
func clear() -> bool:
	if _busy:
		push_error("CommandHistory: re-entrant clear() rejected")
		return false
	_busy = true
	_undo_stack.clear()
	_redo_stack.clear()
	history_changed.emit(false, false)
	_busy = false
	return true


func can_undo() -> bool:
	return not _undo_stack.is_empty()


func can_redo() -> bool:
	return not _redo_stack.is_empty()


func get_undo_count() -> int:
	return _undo_stack.size()


func get_redo_count() -> int:
	return _redo_stack.size()


func _fail(what: String, command: Command) -> void:
	var script: Script = command.get_script()
	var label: String = "Command"
	if script != null:
		label = String(script.get_global_name())
		if label.is_empty():
			label = script.resource_path
	push_error("CommandHistory: %s() of %s failed; history cleared" % [what, label])
	_undo_stack.clear()
	_redo_stack.clear()
	history_changed.emit(false, false)
	_busy = false
