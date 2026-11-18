class_name Command
extends RefCounted
## Base class of every model change. Subclasses take the model and their arguments in _init.
##
## Rules for every command:
## 1. Validate before mutating. A false return means the model was not touched and no signal
##    was emitted.
## 2. Store before and after values, or the instance itself. Never undo by inverse arithmetic.
## 3. An add command receives the complete instance, uid included, in _init.
## 4. A remove command records the instance and its index in do(), and undo() re-inserts it at
##    that index.
## 5. A command that makes several model changes undoes them in reverse order.
## 6. Never touch created or modified.
## 7. Redo calls do() again, so do() must be repeatable after undo().


## Applies the change. Returns false if it could not be applied.
func do() -> bool:
	push_error("%s: do() not implemented" % _script_name())
	return false


## Reverts the change. Returns false if it could not be reverted.
func undo() -> bool:
	push_error("%s: undo() not implemented" % _script_name())
	return false


func _script_name() -> String:
	var script: Script = get_script()
	if script == null:
		return "Command"
	var global_name: StringName = script.get_global_name()
	if global_name != &"":
		return String(global_name)
	return script.resource_path
