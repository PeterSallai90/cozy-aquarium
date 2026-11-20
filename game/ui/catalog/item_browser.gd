class_name ItemBrowser
extends PanelContainer
## The item browser panel (#30): a category row, a search field and a scrolling grid of cards
## (thumbnail above the name) for the placeable items of an ItemCatalog. Picking a card marks it
## and emits EventBus.item_picked; picking the marked card again, clear_pick() and the model's
## model_reset emit EventBus.item_pick_cleared. The pick is only a transient id: the model is read
## (model_reset) and never written, and no Command runs. The panel is non-modal (ADR 0008): it is
## not a world input blocker and every interactive control of it stops the mouse.
##
## setup() only stores. Everything is built on the first show: the cards, their thumbnails and the
## category row. Filtering only shows and hides cards, so nothing is created or freed after that.
## Without an injected catalog the shared ItemCatalogSource (#31) loads the shipped folders on the
## first show; without a source the browser loads them itself.

signal close_requested

const COLUMNS: int = 4
const CARD_MIN_SIZE: Vector2 = Vector2(132.0, 188.0)
const THUMBNAIL_SIZE: Vector2 = Vector2(96.0, 96.0)
const CARD_MARGIN: int = 8
## Fixed panel width (four cards and the scroll bar), so the empty state is as wide as a full list.
const PANEL_WIDTH: float = 560.0
## Space kept free below the panel and the minimum height of the card list in a small window.
const SCREEN_MARGIN: float = 16.0
const MIN_SCROLL_HEIGHT: float = 120.0
const CATEGORY_BUTTONS: Dictionary[String, ItemDefinition.Category] = {
	"Category_all": ItemBrowserList.ALL,
	"Category_rock": ItemDefinition.Category.ROCK,
	"Category_wood": ItemDefinition.Category.WOOD,
	"Category_ornament": ItemDefinition.Category.ORNAMENT,
	"Category_plant": ItemDefinition.Category.PLANT,
}

var _model: AquariumModel = null
var _catalog: ItemCatalog = null
var _source: ItemCatalogSource = null
var _built: bool = false
var _category: ItemDefinition.Category = ItemBrowserList.ALL
var _query: String = ""
var _picked_id: StringName = &""
var _cards: Dictionary[StringName, Button] = {}
var _names: Dictionary[StringName, String] = {}
var _category_buttons: Array[Button] = []
var _fit_queued: bool = false

@onready var _search: LineEdit = $Layout/SearchRow/SearchField
@onready var _clear: Button = $Layout/SearchRow/ClearButton
@onready var _scroll: ScrollContainer = $Layout/Scroll
@onready var _card_box: GridContainer = $Layout/Scroll/Cards
@onready var _empty: Label = $Layout/EmptyLabel
@onready var _close: Button = $Layout/CloseButton


func _ready() -> void:
	_card_box.columns = COLUMNS
	custom_minimum_size.x = PANEL_WIDTH
	var group: ButtonGroup = ButtonGroup.new()
	for button_name: String in CATEGORY_BUTTONS:
		var button: Button = $Layout/Categories.get_node(button_name) as Button
		button.button_group = group
		button.pressed.connect(_on_category_pressed.bind(CATEGORY_BUTTONS[button_name]))
		_category_buttons.append(button)
	_clear.icon = _clear.get_theme_icon("clear", "LineEdit")
	_search.text_changed.connect(_on_text_changed)
	_search.gui_input.connect(_on_search_gui_input)
	_clear.pressed.connect(_on_clear_pressed)
	_close.pressed.connect(close_requested.emit)
	EventBus.language_changed.connect(_on_language_changed)
	EventBus.item_pick_clear_requested.connect(clear_pick)
	visibility_changed.connect(_on_visibility_changed)
	visibility_changed.connect(_queue_fit)
	_card_box.minimum_size_changed.connect(_queue_fit)
	get_viewport().size_changed.connect(_queue_fit)
	_update_category_marks()


## Stores the model and the catalog (null: the shipped folders are loaded on the first show).
## Nothing is built here. The model is only listened to, never written.
func setup(
	model: AquariumModel, catalog: ItemCatalog = null, source: ItemCatalogSource = null
) -> void:
	_model = model
	_catalog = catalog
	_source = source
	_model.model_reset.connect(clear_pick)


## The id of the picked item, or an empty name.
func get_picked_id() -> StringName:
	return _picked_id


## Clears the pick. Emits EventBus.item_pick_cleared only when there was one.
func clear_pick() -> void:
	if _picked_id == &"":
		return
	_picked_id = &""
	_update_picked_marks()
	EventBus.item_pick_cleared.emit()


## Puts the focus on the search field (keyboard open) or on the selected category (mouse open: a
## focused text field would switch off the camera wheel and pan).
func focus_start(by_keyboard: bool) -> void:
	_ensure_built()
	if by_keyboard:
		_search.grab_focus()
		return
	for button: Button in _category_buttons:
		if CATEGORY_BUTTONS[String(button.name)] == _category and button.visible:
			button.grab_focus()
			return
	_search.grab_focus()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _built:
		_apply_texts()


func _on_language_changed(_language: String) -> void:
	if _built:
		_apply_texts()


func _on_visibility_changed() -> void:
	if visible:
		_ensure_built()


# --- building ---


func _ensure_built() -> void:
	if _built or not is_node_ready():
		return
	_built = true
	if _catalog == null:
		_catalog = _source.get_catalog() if _source != null else ItemCatalog.load_dirs()
	var shown: Array[ItemDefinition.Category] = ItemBrowserList.visible_categories(_catalog)
	for button: Button in _category_buttons:
		button.visible = shown.has(CATEGORY_BUTTONS[String(button.name)])
	for id: StringName in _catalog.get_ids():
		var card: Button = _make_card(_catalog.get_definition(id))
		_card_box.add_child(card)
		_cards[id] = card
	_apply_texts()


func _make_card(definition: ItemDefinition) -> Button:
	var card: Button = Button.new()
	card.name = "Card_%s" % definition.id
	card.custom_minimum_size = CARD_MIN_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	card.pressed.connect(_on_card_pressed.bind(definition.id))
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, CARD_MARGIN)
	card.add_child(margin)
	margin.minimum_size_changed.connect(_fit_card.bind(card, margin))
	var rows: VBoxContainer = VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(rows)
	var usable: bool = (
		definition.thumbnail != null
		and definition.thumbnail.get_width() > 0
		and definition.thumbnail.get_height() > 0
	)
	if usable:
		rows.add_child(_make_thumbnail(definition.thumbnail))
	else:
		rows.add_child(_make_placeholder())
	rows.add_child(_make_label("NameLabel", true))
	rows.add_child(_make_label("SelectedLabel", false))
	return card


func _make_thumbnail(texture: Texture2D) -> TextureRect:
	var picture: TextureRect = TextureRect.new()
	picture.name = "Thumbnail"
	picture.texture = texture
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	picture.custom_minimum_size = THUMBNAIL_SIZE
	picture.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return picture


func _make_placeholder() -> Panel:
	var stand_in: Panel = Panel.new()
	stand_in.name = "Placeholder"
	stand_in.custom_minimum_size = THUMBNAIL_SIZE
	stand_in.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stand_in.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.5, 0.58, 0.62, 0.25)
	style.border_color = Color(0.7, 0.78, 0.82, 0.6)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	stand_in.add_theme_stylebox_override("panel", style)
	return stand_in


func _make_label(label_name: String, wraps: bool) -> Label:
	var label: Label = Label.new()
	label.name = label_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if wraps:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		label.visible = false
	return label


## The card is never shorter than its content, so wrapped text and the marker stay inside it.
func _fit_card(card: Button, margin: MarginContainer) -> void:
	var needed: float = maxf(CARD_MIN_SIZE.y, margin.get_combined_minimum_size().y)
	if not is_equal_approx(card.custom_minimum_size.y, needed):
		card.custom_minimum_size.y = needed


# --- texts, filter, marks ---


## Sets every code-made text and the tooltips, rebuilds the name table and filters again.
func _apply_texts() -> void:
	for id: StringName in _cards:
		var definition: ItemDefinition = _catalog.get_definition(id)
		var card: Button = _cards[id]
		_names[id] = tr(definition.name_key)
		(card.find_child("NameLabel", true, false) as Label).text = _names[id]
		(card.find_child("SelectedLabel", true, false) as Label).text = tr("item.browser.selected")
		card.tooltip_text = (
			tr(definition.description_key) if definition.description_key != "" else ""
		)
	_apply_filter()


func _apply_filter() -> void:
	var found: Array[StringName] = ItemBrowserList.filter(_catalog, _names, _category, _query)
	var lookup: Dictionary[StringName, bool] = {}
	for id: StringName in found:
		lookup[id] = true
	for id: StringName in _cards:
		_cards[id].visible = lookup.has(id)
	_scroll.visible = not found.is_empty()
	if _cards.is_empty():
		_empty.text = tr("item.browser.empty_catalog")
		_empty.visible = true
	elif found.is_empty():
		_empty.text = tr("item.browser.empty_search")
		_empty.visible = true
	else:
		_empty.visible = false
	_update_picked_marks()
	_wire_focus(found)


func _update_picked_marks() -> void:
	for id: StringName in _cards:
		(_cards[id].find_child("SelectedLabel", true, false) as Label).visible = id == _picked_id


func _update_category_marks() -> void:
	for button: Button in _category_buttons:
		var is_selected: bool = CATEGORY_BUTTONS[String(button.name)] == _category
		button.set_pressed_no_signal(is_selected)
		(button.get_node("SelectedMark") as Control).visible = is_selected


func _on_category_pressed(category: ItemDefinition.Category) -> void:
	_category = category
	_update_category_marks()
	if _built:
		_apply_filter()


func _on_text_changed(text: String) -> void:
	_query = text
	if _built:
		_apply_filter()


func _on_clear_pressed() -> void:
	_search.text = ""
	_on_text_changed("")


func _on_card_pressed(id: StringName) -> void:
	if id == _picked_id:
		clear_pick()
		return
	_picked_id = id
	_update_picked_marks()
	EventBus.item_picked.emit(id)


## Esc in the search field: a LineEdit that is editing would swallow ui_cancel, so it is caught
## here (the gui_input signal comes before the LineEdit's own handling). TankControls decides what
## closes (the dialog first). The search text is kept.
func _on_search_gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_search.accept_event()
		close_requested.emit()


# --- focus ---


## Tab and Shift+Tab run through the search field, the clear button, the visible categories, the
## visible cards and Close, and wrap inside the panel. The arrows move along the category row and
## across the grid (hidden cards are skipped).
func _wire_focus(found: Array[StringName]) -> void:
	var order: Array[Control] = [_search, _clear]
	var shown_categories: Array[Button] = []
	for button: Button in _category_buttons:
		if button.visible:
			shown_categories.append(button)
	order.append_array(shown_categories)
	var shown_cards: Array[Button] = []
	for id: StringName in found:
		shown_cards.append(_cards[id])
	order.append_array(shown_cards)
	order.append(_close)
	for index: int in order.size():
		var next: Control = order[(index + 1) % order.size()]
		var previous: Control = order[(index + order.size() - 1) % order.size()]
		order[index].focus_next = order[index].get_path_to(next)
		order[index].focus_previous = order[index].get_path_to(previous)
	for index: int in shown_categories.size():
		var button: Button = shown_categories[index]
		var left: Control = shown_categories[maxi(index - 1, 0)]
		var right: Control = shown_categories[mini(index + 1, shown_categories.size() - 1)]
		button.focus_neighbor_left = button.get_path_to(left)
		button.focus_neighbor_right = button.get_path_to(right)
	for index: int in shown_cards.size():
		_wire_card(shown_cards, index)


func _wire_card(shown_cards: Array[Button], index: int) -> void:
	var card: Button = shown_cards[index]
	var count: int = shown_cards.size()
	var row_start: int = index - index % COLUMNS
	var row_end: int = mini(row_start + COLUMNS, count) - 1
	card.focus_neighbor_left = card.get_path_to(shown_cards[maxi(index - 1, row_start)])
	card.focus_neighbor_right = card.get_path_to(shown_cards[mini(index + 1, row_end)])
	var above: Control = shown_cards[index - COLUMNS] if index >= COLUMNS else card
	var below: Control = card
	if index + COLUMNS < count:
		below = shown_cards[index + COLUMNS]
	elif row_start + COLUMNS < count:
		below = shown_cards[count - 1]
	card.focus_neighbor_top = card.get_path_to(above)
	card.focus_neighbor_bottom = card.get_path_to(below)


# --- fit ---


func _queue_fit() -> void:
	if _fit_queued or not is_inside_tree():
		return
	_fit_queued = true
	_fit_scroll.call_deferred()


## Caps the height of the card list so the panel fits the window; the list scrolls when it is
## taller.
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
