class_name TankChooser
extends PanelContainer
## The tank chooser panel: one card per catalog tank in ascending size order, each with the name,
## the litres, a short description and an In use marker on the tank the room displays. It only
## reports a pick (`picked`) or a wish to close (`close_requested`); it never touches the model.

signal picked(tank_id: StringName, card: Button)
signal close_requested

var _displayed_id: StringName = &""
var _cards: Array[Button] = []
var _definitions: Dictionary = {}

@onready var _card_box: VBoxContainer = $Layout/Cards
@onready var _close: Button = $Layout/CloseButton


func _ready() -> void:
	_close.pressed.connect(close_requested.emit)
	EventBus.tank_displayed.connect(set_displayed_tank)
	EventBus.language_changed.connect(_on_language_changed)


## Builds the cards from the catalog: ascending litres, the id as tie-breaker.
func build(catalog: TankCatalog) -> void:
	for card: Button in _cards:
		_card_box.remove_child(card)
		card.queue_free()
	_cards.clear()
	_definitions.clear()
	var definitions: Array[TankDefinition] = []
	for id: StringName in catalog.get_ids():
		definitions.append(catalog.get_definition(id))
	definitions.sort_custom(_is_smaller)
	for definition: TankDefinition in definitions:
		var card: Button = _make_card(definition)
		_card_box.add_child(card)
		_cards.append(card)
		_definitions[card] = definition
	_wire_focus()
	_apply_texts()


## The marker follows the tank the room displays; an empty id means none.
func set_displayed_tank(tank_id: StringName) -> void:
	_displayed_id = tank_id
	_update_markers()


## Puts the focus on the card of the displayed tank, else on the first card, else on Close.
func focus_current() -> void:
	for card: Button in _cards:
		if (_definitions[card] as TankDefinition).id == _displayed_id:
			card.grab_focus()
			return
	if not _cards.is_empty():
		_cards[0].grab_focus()
	else:
		_close.grab_focus()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_apply_texts()


func _on_language_changed(_language: String) -> void:
	_apply_texts()


static func _is_smaller(a: TankDefinition, b: TankDefinition) -> bool:
	if a.volume_litres != b.volume_litres:
		return a.volume_litres < b.volume_litres
	return String(a.id) < String(b.id)


func _make_card(definition: TankDefinition) -> Button:
	var card: Button = Button.new()
	card.name = "Card_%s" % definition.id
	card.custom_minimum_size = Vector2(340.0, 120.0)
	card.pressed.connect(_on_card_pressed.bind(definition.id, card))
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	card.add_child(margin)
	var rows: VBoxContainer = VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(rows)
	for label_name: String in ["NameLabel", "LitresLabel", "DescriptionLabel", "InUseLabel"]:
		var label: Label = Label.new()
		label.name = label_name
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		if label_name == "DescriptionLabel":
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		rows.add_child(label)
	return card


## Tab and Shift+Tab run through the cards in size order, then Close, and wrap inside the panel.
func _wire_focus() -> void:
	var order: Array[Control] = []
	for card: Button in _cards:
		order.append(card)
	order.append(_close)
	for index: int in order.size():
		var next: Control = order[(index + 1) % order.size()]
		var previous: Control = order[(index + order.size() - 1) % order.size()]
		order[index].focus_next = order[index].get_path_to(next)
		order[index].focus_previous = order[index].get_path_to(previous)


func _on_card_pressed(tank_id: StringName, card: Button) -> void:
	picked.emit(tank_id, card)


func _apply_texts() -> void:
	var numbers: LocalFormat = Localization.local_format()
	for card: Button in _cards:
		var definition: TankDefinition = _definitions[card]
		_label(card, "NameLabel").text = tr(definition.name_key)
		var litres: String = numbers.format_number(definition.volume_litres, 0)
		_label(card, "LitresLabel").text = tr("unit.litre") % litres
		_label(card, "DescriptionLabel").text = tr(definition.description_key)
		_label(card, "InUseLabel").text = tr("tank.chooser.current")
	_update_markers()


func _update_markers() -> void:
	for card: Button in _cards:
		var definition: TankDefinition = _definitions[card]
		_label(card, "InUseLabel").visible = definition.id == _displayed_id


func _label(card: Button, label_name: String) -> Label:
	return card.find_child(label_name, true, false) as Label
