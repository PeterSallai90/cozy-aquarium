class_name TankControls
extends Control
## The tank-control group of the HUD: the Change tank, Tank details, Substrate and Items buttons,
## the choosers, the item browser, the Fish button and panel, the details panel and the
## confirmation dialog. Closing a panel
## puts the focus back on the button that opens it. It is also the panel group: only one panel is
## open at a time
## (open_panel, close_panels), and no panel opens while the dialog is open. It runs the
## change-tank and the set-substrate Commands; the choosers and the dialog only report what the
## player did.

var _model: AquariumModel = null
var _catalog: TankCatalog = null
var _substrates: SubstrateCatalog = null
var _items: ItemCatalog = null
var _item_source: ItemCatalogSource = null
var _fish: FishCatalog = null
var _items_by_keyboard: bool = false
var _history: CommandHistory = null
var _panels: Array[Control] = []
var _openers: Dictionary[Control, Button] = {}
var _asked_id: StringName = &""
var _asked_card: Button = null

@onready var _open_button: Button = $Group/Buttons/ChangeTankButton
@onready var _details_button: Button = $Group/Buttons/TankDetailsButton
@onready var _chooser: TankChooser = $Group/TankChooser
@onready var _details: TankDetails = $Group/TankDetails
@onready var _substrate_button: Button = $Group/Buttons/SubstrateButton
@onready var _substrate_chooser: SubstrateChooser = $Group/SubstrateChooser
@onready var _items_button: Button = $Group/Buttons/ItemsButton
@onready var _browser: ItemBrowser = $Group/ItemBrowser
@onready var _fish_button: Button = $Group/Buttons/FishButton
@onready var _fish_panel: FishPanel = $Group/FishPanel
@onready var _dialog: TankChangeDialog = $TankChangeDialog


## Before the node enters the tree. Without `substrates` the catalog directory is loaded. Without
## `items` the item browser loads the shipped item folders when it is first opened, through the
## shared `item_source` when there is one (#31). Without `fish` the fish panel loads the shipped
## fish folder when it is first opened.
func setup(
	model: AquariumModel,
	catalog: TankCatalog,
	history: CommandHistory,
	substrates: SubstrateCatalog = null,
	items: ItemCatalog = null,
	item_source: ItemCatalogSource = null,
	fish: FishCatalog = null
) -> void:
	_model = model
	_catalog = catalog
	_history = history
	_substrates = substrates
	_items = items
	_item_source = item_source
	_fish = fish


func _ready() -> void:
	if _model == null:
		_model = AquariumModel.new()
	if _catalog == null:
		_catalog = TankCatalog.load_dir()
	if _history == null:
		_history = CommandHistory.new()
	if _substrates == null:
		_substrates = SubstrateCatalog.load_dir()
	_panels.append(_chooser)
	_chooser.build(_catalog)
	_panels.append(_details)
	_panels.append(_substrate_chooser)
	_openers[_chooser] = _open_button
	_openers[_details] = _details_button
	_panels.append(_browser)
	_openers[_substrate_chooser] = _substrate_button
	_openers[_browser] = _items_button
	_panels.append(_fish_panel)
	_openers[_fish_panel] = _fish_button
	_browser.setup(_model, _items, _item_source)
	_fish_panel.setup(_model, _history, _fish)
	_substrate_chooser.setup(_model, _substrates)
	_details.setup(_model, _catalog)
	_open_button.pressed.connect(_on_open_pressed)
	_details_button.pressed.connect(_on_details_pressed)
	_substrate_button.pressed.connect(_on_substrate_pressed)
	_items_button.gui_input.connect(_on_items_gui_input)
	_items_button.pressed.connect(_on_items_pressed)
	_fish_button.pressed.connect(_on_fish_pressed)
	_browser.close_requested.connect(_cancel_or_close)
	_fish_panel.close_requested.connect(_cancel_or_close)
	EventBus.tank_displayed.connect(_on_tank_displayed)
	_substrate_chooser.type_picked.connect(_on_substrate_type_picked)
	_substrate_chooser.swatch_picked.connect(_on_swatch_picked)
	_substrate_chooser.close_requested.connect(close_panels)
	_details.close_requested.connect(close_panels)
	_chooser.picked.connect(_on_picked)
	_chooser.close_requested.connect(close_panels)
	_dialog.confirmed.connect(_on_confirmed)
	_dialog.cancelled.connect(_on_cancelled)
	_model.model_reset.connect(_on_model_reset)


## Shows the panel and closes the other panels of the group. Refused while the dialog is open.
## The optional opener is the button the focus returns to when the panel closes.
func open_panel(panel: Control, opener: Button = null) -> void:
	if _dialog.is_active():
		return
	if opener != null:
		_openers[panel] = opener
	if not _panels.has(panel):
		_panels.append(panel)
	for other: Control in _panels:
		if other != panel:
			other.hide()
	panel.show()
	if panel == _chooser:
		_chooser.focus_current()
	elif panel == _details:
		_details.focus_start()
	elif panel == _substrate_chooser:
		_substrate_chooser.focus_current()
	elif panel == _browser:
		_browser.focus_start(_items_by_keyboard)
	elif panel == _fish_panel:
		EventBus.item_pick_clear_requested.emit()
		_fish_panel.focus_start()


## Closes every panel and the dialog; the focus goes back to the button of the panel that was
## open (Change tank when there was none).
func close_panels() -> void:
	var was_open: bool = _dialog.is_active()
	var target: Button = _open_button
	for open_one: Control in _panels:
		if open_one.visible:
			target = _openers.get(open_one, _open_button)
	_dialog.dismiss()
	_asked_id = &""
	_asked_card = null
	for panel: Control in _panels:
		was_open = was_open or panel.visible
		panel.hide()
	if was_open:
		target.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _dialog.is_active() or _any_panel_open():
		_cancel_or_close()
		get_viewport().set_input_as_handled()


## Esc: the dialog is cancelled first, else every panel closes.
func _cancel_or_close() -> void:
	if _dialog.is_active():
		_dialog.cancel()
	else:
		close_panels()


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


func _on_details_pressed() -> void:
	if _dialog.is_active():
		return
	if _details.visible:
		close_panels()
	else:
		open_panel(_details)


func _on_substrate_pressed() -> void:
	if _dialog.is_active():
		return
	if _substrate_chooser.visible:
		close_panels()
	else:
		open_panel(_substrate_chooser)


## Told before pressed: a key or a mouse click opened the browser (a mouse open must not put the
## focus in the search field, which would switch off the camera wheel and pan).
func _on_items_gui_input(event: InputEvent) -> void:
	if event is InputEventKey:
		_items_by_keyboard = true
	elif event is InputEventMouseButton:
		_items_by_keyboard = false


func _on_items_pressed() -> void:
	if _dialog.is_active():
		return
	if _browser.visible:
		close_panels()
	else:
		open_panel(_browser)


func _on_fish_pressed() -> void:
	if _dialog.is_active():
		return
	if _fish_panel.visible:
		close_panels()
	else:
		open_panel(_fish_panel)


## No tank on show: the Fish button is off and the fish panel closed.
func _on_tank_displayed(tank_id: StringName) -> void:
	var has_tank: bool = tank_id != &""
	_fish_button.disabled = not has_tank
	if not has_tank and _fish_panel.visible:
		close_panels()


## A card: the pick rule of the catalog gives the colour (the type in use keeps it).
func _on_substrate_type_picked(substrate_id: StringName, _card: Button) -> void:
	var colour: Color = _substrates.colour_for_pick(
		_model.get_substrate_id(), _model.get_substrate_colour(), substrate_id
	)
	_set_substrate(substrate_id, colour)


## A swatch of the type in use.
func _on_swatch_picked(colour: Color, _swatch: Button) -> void:
	_set_substrate(_model.get_substrate_id(), colour)


## The panel stays open. Nothing happens while the dialog is open, the history is busy or the
## model already holds this type and colour.
func _set_substrate(substrate_id: StringName, colour: Color) -> void:
	if _dialog.is_active() or _history.is_busy():
		return
	if (
		substrate_id == _model.get_substrate_id()
		and colour.to_rgba32() == _model.get_substrate_colour().to_rgba32()
	):
		return
	_history.execute(SetSubstrateCommand.new(_model, _substrates, substrate_id, colour))


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
