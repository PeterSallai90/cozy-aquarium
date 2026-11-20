class_name ItemActions
extends Control
## The controls of the selected placed item, at the bottom centre above the hint line (#32): a
## Delete button and, for a colourable item, a row of colour dots with an "Original colour" button.
## It mirrors the selection from EventBus.item_selected and item_selection_cleared and reads the
## model for the colour ring; a press only emits EventBus.item_delete_requested or
## item_colour_requested, placement does the work (ADR 0012 Amendment 1 rule 10). The catalog is
## asked only after a selection. The controls hide while a modal dialog or photo mode blocks the
## world, and when a focused one hides the engine releases the focus; nothing here takes the focus.
## Each dot is a focusable Button in the exact stored swatch colour with the untranslated hex code
## as its tooltip; a border-only Ring panel on the dot (or on the Original colour button) marks the
## current colour, a shape cue besides the colour. A colour that is not a swatch marks nothing.

const DOT_SIZE: Vector2 = Vector2(28.0, 28.0)
const RING_NAME: StringName = &"Ring"

var _model: AquariumModel = null
var _source: ItemCatalogSource = null
var _selected_uid: String = ""
var _colourable: bool = false
var _swatches: Array[Color] = []
var _dots: Array[Button] = []

@onready var _delete: Button = $Layout/DeleteButton
@onready var _row: Control = $Layout/ColourRow
@onready var _dot_box: Control = $Layout/ColourRow/Swatches
@onready var _original: Button = $Layout/ColourRow/OriginalButton


## Hands over the model and the shared item source; main.gd calls it before the node is ready.
func setup(model: AquariumModel, source: ItemCatalogSource) -> void:
	_model = model
	_source = source
	_model.item_changed.connect(_on_item_changed)
	_model.model_reset.connect(_on_model_reset)


func _ready() -> void:
	_delete.pressed.connect(_on_delete_pressed)
	_original.pressed.connect(_on_original_pressed)
	_add_ring(_original, Color.WHITE)
	EventBus.item_selected.connect(_on_item_selected)
	EventBus.item_selection_cleared.connect(_on_item_selection_cleared)
	EventBus.language_changed.connect(_on_language_changed)
	_apply_tooltip()
	_apply_visibility()


func _process(_delta: float) -> void:
	_apply_visibility()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_apply_tooltip()


func _on_item_selected(uid: String) -> void:
	_selected_uid = uid
	_rebuild()


func _on_item_selection_cleared() -> void:
	_selected_uid = ""
	_rebuild()


func _on_item_changed(uid: String, _index: int) -> void:
	if uid == _selected_uid:
		_refresh_rings()


func _on_model_reset() -> void:
	_rebuild()


func _on_language_changed(_language: String) -> void:
	_apply_tooltip()


func _on_delete_pressed() -> void:
	EventBus.item_delete_requested.emit()


func _on_original_pressed() -> void:
	EventBus.item_colour_requested.emit(false, Color.WHITE)


func _on_dot_pressed(colour: Color) -> void:
	EventBus.item_colour_requested.emit(true, colour)


func _apply_tooltip() -> void:
	_delete.tooltip_text = tr("ui.item.delete.tooltip") % InputLabels.primary_label(&"item_delete")


## Reads the definition of the selection and builds the dots again.
func _rebuild() -> void:
	_colourable = false
	_swatches.clear()
	for dot: Button in _dots:
		_dot_box.remove_child(dot)
		dot.queue_free()
	_dots.clear()
	var item: PlacedItem = _model.get_item(_selected_uid) if _selected_uid != "" else null
	if item != null:
		var definition: ItemDefinition = _source.get_catalog().get_definition(item.catalog_id)
		if definition != null and definition.colourable:
			_colourable = true
			_swatches = definition.colour_swatches.duplicate()
	for colour: Color in _swatches:
		var dot: Button = _make_dot(colour)
		_dot_box.add_child(dot)
		_dots.append(dot)
	_refresh_rings()
	_apply_visibility()


func _make_dot(colour: Color) -> Button:
	var dot: Button = Button.new()
	dot.custom_minimum_size = DOT_SIZE
	dot.mouse_filter = Control.MOUSE_FILTER_STOP
	dot.focus_mode = Control.FOCUS_ALL
	dot.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	dot.tooltip_text = "#" + colour.to_html(false).to_upper()
	# Only normal, hover and pressed carry the colour; the focus style stays the theme's.
	for style_name: String in ["normal", "hover", "pressed"]:
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = colour
		style.set_corner_radius_all(8)
		style.set_border_width_all(2)
		style.border_color = colour.darkened(0.35) if style_name == "normal" else Color.WHITE
		dot.add_theme_stylebox_override(style_name, style)
	dot.pressed.connect(_on_dot_pressed.bind(colour))
	_add_ring(dot, Color.WHITE)
	return dot


## A border-only panel over the whole control; hidden until the control is the current colour.
func _add_ring(host: Control, colour: Color) -> void:
	var ring: Panel = Panel.new()
	ring.name = RING_NAME
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	style.border_color = colour
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	style.draw_center = false
	ring.add_theme_stylebox_override("panel", style)
	ring.visible = false
	host.add_child(ring)


## The ring sits on the dot equal to the stored colour by to_rgba32(); the Original colour button
## is marked only while the item has no colour.
func _refresh_rings() -> void:
	var item: PlacedItem = _model.get_item(_selected_uid) if _selected_uid != "" else null
	var current: int = item.colour.to_rgba32() if item != null else 0
	var has_colour: bool = item != null and item.has_colour
	for index: int in _dots.size():
		var ring: Control = _dots[index].get_node(NodePath(RING_NAME)) as Control
		ring.visible = has_colour and _swatches[index].to_rgba32() == current
	var original_ring: Control = _original.get_node(NodePath(RING_NAME)) as Control
	original_ring.visible = item != null and not has_colour


func _apply_visibility() -> void:
	var shown: bool = _selected_uid != "" and not WorldInput.is_blocked(get_tree())
	_delete.visible = shown
	_row.visible = shown and _colourable
