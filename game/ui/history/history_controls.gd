class_name HistoryControls
extends Control
## The Undo and Redo text buttons at the top right of the window and the shortcuts of the actions
## history_undo and history_redo (#32, ADR 0008 Amendment 2). The buttons are enabled from
## EventBus.history_changed and nothing else. A button press and a shortcut call undo() or redo()
## exactly once, and only when no modal dialog or photo mode blocks the world, no world gesture
## runs (WorldInput.is_gesture_running) and the history is not busy, so a busy history is never
## asked. The shortcut is read in _unhandled_input with exact match and no key echo, and is ignored
## while a text field has the focus (it keeps its own Ctrl+Z). Texts and tooltips re-translate at
## once on language_changed; the tooltips hold the live key label (#81).

const ACTION_UNDO: StringName = &"history_undo"
const ACTION_REDO: StringName = &"history_redo"

var _history: CommandHistory = null

@onready var _undo: Button = $Buttons/UndoButton
@onready var _redo: Button = $Buttons/RedoButton


## Hands over the history to act on; main.gd calls it before the node is ready.
func setup(history: CommandHistory) -> void:
	_history = history


func _ready() -> void:
	_undo.pressed.connect(_try_undo)
	_redo.pressed.connect(_try_redo)
	EventBus.history_changed.connect(_on_history_changed)
	EventBus.language_changed.connect(_on_language_changed)
	_apply_tooltips()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_apply_tooltips()


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed:
		return
	if key.is_action_pressed(ACTION_UNDO, false, true):
		if not WorldInput.is_text_focused(get_viewport()) and _try_undo():
			get_viewport().set_input_as_handled()
	elif key.is_action_pressed(ACTION_REDO, false, true):
		if not WorldInput.is_text_focused(get_viewport()) and _try_redo():
			get_viewport().set_input_as_handled()


func _on_history_changed(can_undo: bool, can_redo: bool) -> void:
	_undo.disabled = not can_undo
	_redo.disabled = not can_redo


func _on_language_changed(_language: String) -> void:
	_apply_tooltips()


func _apply_tooltips() -> void:
	_undo.tooltip_text = tr("ui.history.undo.tooltip") % InputLabels.primary_label(ACTION_UNDO)
	_redo.tooltip_text = tr("ui.history.redo.tooltip") % InputLabels.primary_label(ACTION_REDO)


func _may_act() -> bool:
	return (
		_history != null
		and not _history.is_busy()
		and not WorldInput.is_blocked(get_tree())
		and not WorldInput.is_gesture_running(get_tree())
	)


func _try_undo() -> bool:
	if not _may_act():
		return false
	_history.undo()
	return true


func _try_redo() -> bool:
	if not _may_act():
		return false
	_history.redo()
	return true
