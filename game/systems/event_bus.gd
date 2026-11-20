extends Node
## Autoload "EventBus". Re-emits the signals of the bound CommandHistory so systems need no
## direct reference to it. Model signals are not relayed: systems connect to the model.
## language_changed is also here: Localization relays its own change to it. setting_changed is
## relayed by the Settings autoload: once per real change, never at startup, never for the language.
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
# Relay signal: emitted from other scripts, so the analyser sees no emit in this one.
@warning_ignore("unused_signal")
signal language_changed(language: String)
# Relay signal: emitted from other scripts, so the analyser sees no emit in this one.
@warning_ignore("unused_signal")
signal setting_changed(section: String, key: String, value: Variant)
# Relay signal: emitted from other scripts, so the analyser sees no emit in this one.
## Emitted by the room after it has swapped the tank; an empty id means no tank is shown.
@warning_ignore("unused_signal")
signal tank_displayed(tank_id: StringName)
# Relay signal: emitted from other scripts, so the analyser sees no emit in this one.
## Emitted by the item browser when the player picks an item to place (#30); #31 listens.
@warning_ignore("unused_signal")
signal item_picked(catalog_id: StringName)
# Relay signal: emitted from other scripts, so the analyser sees no emit in this one.
## Emitted once when a pick is cleared: re-pick of the marked card, clear_pick(), model_reset.
@warning_ignore("unused_signal")
signal item_pick_cleared

# Relay signal: emitted from other scripts, so the analyser sees no emit in this one.
## Emitted by placement when it wants the pick cleared (Esc, #31); the item browser answers by
## calling clear_pick(), which emits item_pick_cleared once when there was a pick.
@warning_ignore("unused_signal")
signal item_pick_clear_requested
# Relay signal: emitted from other scripts, so the analyser sees no emit in this one.
## Emitted by placement when the selected placed item changes (also straight from one to another).
@warning_ignore("unused_signal")
signal item_selected(uid: String)
# Relay signal: emitted from other scripts, so the analyser sees no emit in this one.
## Emitted once when the selection becomes empty (#31).
@warning_ignore("unused_signal")
signal item_selection_cleared
# Relay signal: emitted from other scripts, so the analyser sees no emit in this one.
## Emitted by the HUD when the player asks to delete the selected item (#32); placement applies
## the same guards as the Delete key and runs the command.
@warning_ignore("unused_signal")
signal item_delete_requested
# Relay signal: emitted from other scripts, so the analyser sees no emit in this one.
## Emitted by the HUD when the player picks a colour for the selected item (#32): has_colour false
## means the original colour. Placement runs the recolour command; no uid is passed.
@warning_ignore("unused_signal")
signal item_colour_requested(has_colour: bool, colour: Color)

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
