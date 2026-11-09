class_name TankControls
extends Control
## The tank-control group of the HUD: the Change tank button, the chooser and the confirmation
## dialog. It is also the panel group: only one panel is open at a time (open_panel, close_panels),
## and no panel opens while the dialog is open. It runs the change-tank Command; the chooser and
## the dialog only report what the player did.

var _model: AquariumModel = null
var _catalog: TankCatalog = null
var _history: CommandHistory = null
var _panels: Array[Control] = []
var _asked_id: StringName = &""
var _asked_card: Button = null

@onready var _open_button: Button = $Group/ChangeTankButton
@onready var _chooser: TankChooser = $Group/TankChooser
@onready var _dialog: TankChangeDialog = $TankChangeDialog


## Before the node enters the tree.
func setup(model: AquariumModel, catalog: TankCatalog, history: CommandHistory) -> void:
	_model = model
	_catalog = catalog
	_history = history


func _ready() -> void:
	if _model == null:
		_model = AquariumModel.new()
	if _catalog == null:
		_catalog = TankCatalog.load_dir()
	if _history == null:
		_history = CommandHistory.new()
	_panels.append(_chooser)
	_chooser.build(_catalog)
	_open_button.pressed.connect(_on_open_pressed)
	_chooser.picked.connect(_on_picked)
	_chooser.close_requested.connect(close_panels)
	_dialog.confirmed.connect(_on_confirmed)
	_dialog.cancelled.connect(_on_cancelled)
	_model.model_reset.connect(_on_model_reset)


## Shows the panel and closes the other panels of the group. Refused while the dialog is open.
func open_panel(panel: Control) -> void:
	if _dialog.is_active():
		return
	if not _panels.has(panel):
		_panels.append(panel)
	for other: Control in _panels:
		if other != panel:
			other.hide()
	panel.show()
	if panel == _chooser:
		_chooser.focus_current()


## Closes every panel and the dialog; the focus goes back to the Change tank button when
## something was open.
func close_panels() -> void:
	var was_open: bool = _dialog.is_active()
	_dialog.dismiss()
	_asked_id = &""
	_asked_card = null
	for panel: Control in _panels:
		was_open = was_open or panel.visible
		panel.hide()
	if was_open:
		_open_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _dialog.is_active():
		_dialog.cancel()
		get_viewport().set_input_as_handled()
	elif _any_panel_open():
		close_panels()
		get_viewport().set_input_as_handled()


func _any_panel_open() -> bool:
	for panel: Control in _panels:
		if panel.visible:
			return true
	return false


func _on_open_pressed() -> void:
	if _dialog.is_active():
		return
	if _chooser.visible:
		close_panels()
	else:
		open_panel(_chooser)


func _on_picked(tank_id: StringName, card: Button) -> void:
	if _dialog.is_active() or _history.is_busy():
		return
	if tank_id == _model.get_tank_id():
		close_panels()
		return
	if ChangeTankCommand.would_clear(_model):
		_asked_id = tank_id
		_asked_card = card
		_dialog.ask(_catalog.get_definition(tank_id).name_key)
		return
	_change_tank(tank_id)


func _on_confirmed() -> void:
	var tank_id: StringName = _asked_id
	_asked_id = &""
	_asked_card = null
	if tank_id == &"":
		return
	_change_tank(tank_id)


func _on_cancelled() -> void:
	var card: Button = _asked_card
	_asked_id = &""
	_asked_card = null
	if card != null and card.is_visible_in_tree():
		card.grab_focus()


func _on_model_reset() -> void:
	if not _dialog.is_active():
		return
	_dialog.dismiss()
	_asked_id = &""
	_asked_card = null
	if _chooser.visible:
		_chooser.focus_current()


func _change_tank(tank_id: StringName) -> void:
	if _history.is_busy():
		return
	_history.execute(ChangeTankCommand.new(_model, _catalog, tank_id))
	close_panels()
