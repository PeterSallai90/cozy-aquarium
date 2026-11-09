class_name TankChangeDialog
extends Control
## The question before a tank change that would clear the tank. Modal through a full-screen
## dimmer that stops the mouse; the focus starts on Cancel and stays on Cancel and Confirm.
## It decides nothing: it reports `confirmed` or `cancelled`.

signal confirmed
signal cancelled

var _name_key: String = ""
var _active: bool = false

@onready var _body: Label = $Center/Box/Layout/BodyLabel
@onready var _cancel: Button = $Center/Box/Layout/Buttons/CancelButton
@onready var _confirm: Button = $Center/Box/Layout/Buttons/ConfirmButton


func _ready() -> void:
	_body.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_cancel.pressed.connect(cancel)
	_confirm.pressed.connect(_on_confirm_pressed)
	_cancel.focus_next = _cancel.get_path_to(_confirm)
	_cancel.focus_previous = _cancel.get_path_to(_confirm)
	_confirm.focus_next = _confirm.get_path_to(_cancel)
	_confirm.focus_previous = _confirm.get_path_to(_cancel)
	# Arrows keep the focus on the two buttons; the controls behind the dimmer are out of reach.
	var own: Array[Button] = [_cancel, _confirm]
	for button: Button in own:
		var self_path: NodePath = button.get_path_to(button)
		button.focus_neighbor_top = self_path
		button.focus_neighbor_bottom = self_path
	_cancel.focus_neighbor_left = _cancel.get_path_to(_cancel)
	_cancel.focus_neighbor_right = _cancel.get_path_to(_confirm)
	_confirm.focus_neighbor_left = _confirm.get_path_to(_cancel)
	_confirm.focus_neighbor_right = _confirm.get_path_to(_confirm)
	EventBus.language_changed.connect(_on_language_changed)


## Shows the question for the tank whose name key is given; the focus goes to Cancel.
func ask(new_tank_name_key: String) -> void:
	_name_key = new_tank_name_key
	_active = true
	_apply_texts()
	show()
	_cancel.grab_focus()


## Hides the dialog without answering.
func dismiss() -> void:
	_active = false
	_name_key = ""
	hide()


func is_active() -> bool:
	return _active


## Answers no. Does nothing when no question is open.
func cancel() -> void:
	if not _active:
		return
	dismiss()
	cancelled.emit()


func _on_confirm_pressed() -> void:
	if not _active:
		return
	dismiss()
	confirmed.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_apply_texts()


func _on_language_changed(_language: String) -> void:
	_apply_texts()


func _apply_texts() -> void:
	if _name_key.is_empty():
		_body.text = ""
		return
	_body.text = tr("tank.change.body") % tr(_name_key)
