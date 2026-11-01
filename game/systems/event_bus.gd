extends Node
## Autoload "EventBus". Re-emits the signals of the bound CommandHistory so systems need no
## direct reference to it. Model signals are not relayed: systems connect to the model.
##
## Listeners connect with a method on an Object (node.method). Godot then drops the connection
## when that object is freed. A lambda that captures a node is not dropped automatically and
## must be disconnected in _exit_tree.
##
## No class_name here: it would clash with the autoload name.

signal command_executed(command: Command)
signal command_undone(command: Command)
signal command_redone(command: Command)
signal history_changed(can_undo: bool, can_redo: bool)
signal language_changed(language: String)

var _history: CommandHistory = null


## Starts relaying the history. Binding the same history again does nothing; a null unbinds.
func bind_history(history: CommandHistory) -> void:
	if history == _history:
		return
	unbind_history()
	if history == null:
		return
	_history = history
	_history.executed.connect(_on_executed)
	_history.undone.connect(_on_undone)
	_history.redone.connect(_on_redone)
	_history.history_changed.connect(_on_history_changed)


func unbind_history() -> void:
	if _history == null:
		return
	if _history.executed.is_connected(_on_executed):
		_history.executed.disconnect(_on_executed)
	if _history.undone.is_connected(_on_undone):
		_history.undone.disconnect(_on_undone)
	if _history.redone.is_connected(_on_redone):
		_history.redone.disconnect(_on_redone)
	if _history.history_changed.is_connected(_on_history_changed):
		_history.history_changed.disconnect(_on_history_changed)
	_history = null


func _on_executed(command: Command) -> void:
	command_executed.emit(command)


func _on_undone(command: Command) -> void:
	command_undone.emit(command)


func _on_redone(command: Command) -> void:
	command_redone.emit(command)


func _on_history_changed(can_undo: bool, can_redo: bool) -> void:
	history_changed.emit(can_undo, can_redo)
