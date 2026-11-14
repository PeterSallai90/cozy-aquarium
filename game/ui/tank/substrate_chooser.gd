class_name SubstrateChooser
extends PanelContainer
## The substrate chooser panel: one card per catalog substrate in chooser order and, below them,
## the colour swatches of the type in use. The type and the swatch in use are marked (a text on the
## card, a drawn dot on the swatch; the swatch colour itself never changes). It reads the model and
## only reports a pick (`type_picked`, `swatch_picked`) or a wish to close (`close_requested`);
## TankControls runs the Command. The panel is non-modal (ADR 0008): it is not a world input
## blocker and every control of it stops the mouse so a press on it never starts an orbit or pan.

signal type_picked(substrate_id: StringName, card: Button)
signal swatch_picked(colour: Color, swatch: Button)
signal close_requested

const CARD_MIN_SIZE: Vector2 = Vector2(340.0, 90.0)
const SWATCH_SIZE: Vector2 = Vector2(44.0, 44.0)
const MARK_SIZE: float = 16.0
## Space kept free below the panel and the minimum height of the card list in a small window.
const SCREEN_MARGIN: float = 16.0
const MIN_SCROLL_HEIGHT: float = 120.0

var _model: AquariumModel = null
var _catalog: SubstrateCatalog = null
var _cards: Array[Button] = []
var _swatches: Array[Button] = []
var _row_id: StringName = &""
var _fit_queued: bool = false

@onready var _scroll: ScrollContainer = $Layout/Scroll
@onready var _card_box: VBoxContainer = $Layout/Scroll/Cards
@onready var _swatch_row: HBoxContainer = $Layout/Swatches
@onready var _close: Button = $Layout/CloseButton


func _ready() -> void:
	_close.pressed.connect(close_requested.emit)
	EventBus.language_changed.connect(_on_language_changed)
	visibility_changed.connect(_queue_fit)
	_card_box.minimum_size_changed.connect(_queue_fit)
	get_viewport().size_changed.connect(_queue_fit)


## Reads the model and the catalog and builds the cards. The model is never written.
func setup(model: AquariumModel, catalog: SubstrateCatalog) -> void:
	_model = model
	_catalog = catalog
	_model.substrate_changed.connect(_on_substrate_changed)
	_model.model_reset.connect(_refresh)
	for id: StringName in _catalog.get_ids():
		var card: Button = _make_card(_catalog.get_definition(id))
		_card_box.add_child(card)
		_cards.append(card)
	_apply_texts()
	_refresh()


## Puts the focus on the card in use, else on the first card, else on Close.
func focus_current() -> void:
	if _model != null:
		for card: Button in _cards:
			if _card_id(card) == _model.get_substrate_id():
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


func _on_substrate_changed(_substrate_id: StringName, _colour: Color) -> void:
	_refresh()


func _card_id(card: Button) -> StringName:
	return StringName(String(card.name).trim_prefix("Card_"))


func _make_card(definition: SubstrateDefinition) -> Button:
	var card: Button = Button.new()
	card.name = "Card_%s" % definition.id
	card.custom_minimum_size = CARD_MIN_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.pressed.connect(_on_card_pressed.bind(definition.id, card))
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	card.add_child(margin)
	margin.minimum_size_changed.connect(_fit_card.bind(card, margin))
	var rows: VBoxContainer = VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(rows)
	for label_name: String in ["NameLabel", "DescriptionLabel", "InUseLabel"]:
		var label: Label = Label.new()
		label.name = label_name
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		if label_name == "DescriptionLabel":
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		rows.add_child(label)
	return card


## The card is never shorter than its content, so wrapped text and the marker stay inside it.
func _fit_card(card: Button, margin: MarginContainer) -> void:
	var needed: float = maxf(CARD_MIN_SIZE.y, margin.get_combined_minimum_size().y)
	if not is_equal_approx(card.custom_minimum_size.y, needed):
		card.custom_minimum_size.y = needed


func _make_swatch(number: int, colour: Color) -> Button:
	var swatch: Button = Button.new()
	swatch.name = "Swatch_%d" % number
	swatch.custom_minimum_size = SWATCH_SIZE
	swatch.mouse_filter = Control.MOUSE_FILTER_STOP
	swatch.focus_mode = Control.FOCUS_ALL
	# Only normal, hover and pressed carry the colour; the focus style stays the theme's.
	for style_name: String in ["normal", "hover", "pressed"]:
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = colour
		style.set_corner_radius_all(8)
		style.set_border_width_all(2)
		style.border_color = colour.darkened(0.35) if style_name == "normal" else Color.WHITE
		swatch.add_theme_stylebox_override(style_name, style)
	swatch.pressed.connect(_on_swatch_pressed.bind(colour, swatch))
	var mark: Panel = Panel.new()
	mark.name = "InUseMark"
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.set_anchors_preset(Control.PRESET_CENTER)
	mark.offset_left = -MARK_SIZE / 2.0
	mark.offset_right = MARK_SIZE / 2.0
	mark.offset_top = -MARK_SIZE / 2.0
	mark.offset_bottom = MARK_SIZE / 2.0
	var dot: StyleBoxFlat = StyleBoxFlat.new()
	dot.bg_color = Color(1.0, 1.0, 1.0)
	dot.border_color = Color(0.1, 0.1, 0.12)
	dot.set_border_width_all(3)
	dot.set_corner_radius_all(int(MARK_SIZE))
	mark.add_theme_stylebox_override("panel", dot)
	mark.visible = false
	swatch.add_child(mark)
	return swatch


func _on_card_pressed(substrate_id: StringName, card: Button) -> void:
	type_picked.emit(substrate_id, card)


func _on_swatch_pressed(colour: Color, swatch: Button) -> void:
	swatch_picked.emit(colour, swatch)


func _apply_texts() -> void:
	if _catalog == null:
		return
	for card: Button in _cards:
		var definition: SubstrateDefinition = _catalog.get_definition(_card_id(card))
		_label(card, "NameLabel").text = tr(definition.name_key)
		_label(card, "DescriptionLabel").text = tr(definition.description_key)
		_label(card, "InUseLabel").text = tr("substrate.chooser.current")
	_update_marks()


## Rebuilds the swatch row only when the type changed; otherwise only the marks move, so the
## focus stays on the control the player used.
func _refresh() -> void:
	if _model == null:
		return
	if _row_id != _model.get_substrate_id() or _swatches.is_empty():
		_build_swatches()
	_update_marks()


func _build_swatches() -> void:
	for swatch: Button in _swatches:
		_swatch_row.remove_child(swatch)
		swatch.queue_free()
	_swatches.clear()
	_row_id = _model.get_substrate_id()
	var definition: SubstrateDefinition = _catalog.get_definition(_row_id)
	if definition != null:
		for index: int in definition.colour_swatches.size():
			var swatch: Button = _make_swatch(index + 1, definition.colour_swatches[index])
			_swatch_row.add_child(swatch)
			_swatches.append(swatch)
	_wire_focus()
	_queue_fit()


func _update_marks() -> void:
	if _model == null:
		return
	var id: StringName = _model.get_substrate_id()
	for card: Button in _cards:
		_label(card, "InUseLabel").visible = _card_id(card) == id
	var in_use: int = _catalog.swatch_index(id, _model.get_substrate_colour())
	for index: int in _swatches.size():
		(_swatches[index].get_node("InUseMark") as Control).visible = index == in_use


## Tab and Shift+Tab run through the cards, then the swatches, then Close, and wrap inside the
## panel; the arrow keys move between swatches.
func _wire_focus() -> void:
	var order: Array[Control] = []
	for card: Button in _cards:
		order.append(card)
	for swatch: Button in _swatches:
		order.append(swatch)
	order.append(_close)
	for index: int in order.size():
		var next: Control = order[(index + 1) % order.size()]
		var previous: Control = order[(index + order.size() - 1) % order.size()]
		order[index].focus_next = order[index].get_path_to(next)
		order[index].focus_previous = order[index].get_path_to(previous)
	for index: int in _swatches.size():
		var left: Control = _swatches[maxi(index - 1, 0)]
		var right: Control = _swatches[mini(index + 1, _swatches.size() - 1)]
		_swatches[index].focus_neighbor_left = _swatches[index].get_path_to(left)
		_swatches[index].focus_neighbor_right = _swatches[index].get_path_to(right)


func _label(card: Button, label_name: String) -> Label:
	return card.find_child(label_name, true, false) as Label


func _queue_fit() -> void:
	if _fit_queued or not is_inside_tree():
		return
	_fit_queued = true
	_fit_scroll.call_deferred()


## Caps the height of the card list so the panel, with the swatch row and Close below it, fits the
## window; the list scrolls when it is taller.
func _fit_scroll() -> void:
	_fit_queued = false
	if not is_inside_tree():
		return
	_scroll.custom_minimum_size.y = 0.0
	var content: float = _card_box.get_combined_minimum_size().y
	var others: float = get_combined_minimum_size().y
	var available: float = (
		get_viewport().get_visible_rect().size.y - global_position.y - SCREEN_MARGIN - others
	)
	_scroll.custom_minimum_size.y = clampf(content, 0.0, maxf(available, MIN_SCROLL_HEIGHT))
