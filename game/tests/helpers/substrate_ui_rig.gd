extends RefCounted
## Finds the parts of the substrate chooser for the #28 UI tests and fixes the node names the plan
## leaves to the implementation, in one place (the contract, like tank_ui_rig.gd for #24):
##
## - Below the tank controls, found with find_child by name: Button "SubstrateButton" in the same
##   HBox as "ChangeTankButton" and "TankDetailsButton", after the details button.
## - The panel "SubstrateChooser" (hidden until opened) with a Label "TitleLabel", a ScrollContainer
##   "Scroll" holding the cards, a Label "ColourLabel", a row "Swatches" and a Button "CloseButton".
##   The swatch row and Close are outside the scroll, so they stay visible.
## - One Button "Card_<id>" per type, in tree order the chooser order, each with Labels "NameLabel",
##   "DescriptionLabel" and "InUseLabel" (visible only on the type in use).
## - One focusable Button "Swatch_<n>" per swatch of the current type, in tree order the catalog
##   order, each with a child Control "InUseMark" (visible only on the in-use swatch). The colour is
##   a StyleBoxFlat override of "normal"; the focus style is the theme's.
## The chooser is reached by path and name only, never by class name (it does not exist before the
## implementation).

const Ui := preload("res://tests/helpers/tank_ui_rig.gd")
const Sub := preload("res://tests/helpers/substrate_api.gd")

const BUTTON := "SubstrateButton"
const PANEL := "SubstrateChooser"
const SCROLL := "Scroll"
const SWATCHES := "Swatches"
const IN_USE_MARK := "InUseMark"
const COLOUR_LABEL := "ColourLabel"
const WINDOW := Vector2i(1152, 648)


static func part(controls: Node, node_name: String) -> Node:
	return controls.find_child(node_name, true, false)


static func open_button(controls: Node) -> Button:
	return part(controls, BUTTON) as Button


static func panel(controls: Node) -> Control:
	return part(controls, PANEL) as Control


static func scroll(controls: Node) -> ScrollContainer:
	var holder: Control = panel(controls)
	return null if holder == null else holder.find_child(SCROLL, true, false) as ScrollContainer


static func close_button(controls: Node) -> Button:
	var holder: Control = panel(controls)
	return null if holder == null else holder.find_child("CloseButton", true, false) as Button


static func title_label(controls: Node) -> Label:
	var holder: Control = panel(controls)
	return null if holder == null else holder.find_child(Ui.TITLE, true, false) as Label


static func colour_label(controls: Node) -> Label:
	var holder: Control = panel(controls)
	return null if holder == null else holder.find_child(COLOUR_LABEL, true, false) as Label


static func swatch_row(controls: Node) -> Control:
	var holder: Control = panel(controls)
	return null if holder == null else holder.find_child(SWATCHES, true, false) as Control


static func card(controls: Node, id: StringName) -> Button:
	var holder: Control = panel(controls)
	return null if holder == null else holder.find_child("Card_%s" % id, true, false) as Button


## The cards in tree order, which must be the chooser order.
static func cards(controls: Node) -> Array[Button]:
	var found: Array[Button] = []
	var holder: Control = panel(controls)
	if holder == null:
		return found
	for node: Node in holder.find_children("Card_*", "Button", true, false):
		found.append(node as Button)
	return found


static func card_ids(controls: Node) -> Array[StringName]:
	var ids: Array[StringName] = []
	for button: Button in cards(controls):
		ids.append(StringName(String(button.name).trim_prefix("Card_")))
	return ids


static func card_label(controls: Node, id: StringName, label_name: String) -> Label:
	var button: Button = card(controls, id)
	return null if button == null else button.find_child(label_name, true, false) as Label


## The ids of the cards whose In use label is visible.
static func marked_ids(controls: Node) -> Array[StringName]:
	var ids: Array[StringName] = []
	for button: Button in cards(controls):
		var marker: Control = button.find_child("InUseLabel", true, false) as Control
		if marker != null and marker.is_visible_in_tree():
			ids.append(StringName(String(button.name).trim_prefix("Card_")))
	return ids


## The swatches of the current type in tree order (the catalog order).
static func swatches(controls: Node) -> Array[Button]:
	var found: Array[Button] = []
	var row: Control = swatch_row(controls)
	if row == null:
		return found
	for node: Node in row.find_children("Swatch_*", "Button", true, false):
		found.append(node as Button)
	return found


## The colour a swatch shows: the bg_color of its normal StyleBoxFlat.
static func swatch_colour(swatch: Button) -> Color:
	var style: StyleBoxFlat = swatch.get_theme_stylebox("normal") as StyleBoxFlat
	return Sub.MISSING_COLOUR if style == null else style.bg_color


static func swatch_colours(controls: Node) -> Array[Color]:
	var colours: Array[Color] = []
	for swatch: Button in swatches(controls):
		colours.append(swatch_colour(swatch))
	return colours


## The 0-based positions of the swatches whose InUseMark is visible.
static func marked_swatches(controls: Node) -> Array[int]:
	var found: Array[int] = []
	var list: Array[Button] = swatches(controls)
	for index: int in list.size():
		var mark: Control = list[index].find_child(IN_USE_MARK, true, false) as Control
		if mark != null and mark.is_visible_in_tree():
			found.append(index)
	return found


static func is_open(controls: Node) -> bool:
	var holder: Control = panel(controls)
	return holder != null and holder.is_visible_in_tree()


## Presses the Substrate button and waits two frames.
static func press_open(suite: Node, controls: Node) -> void:
	open_button(controls).pressed.emit()
	await suite.get_tree().process_frame
	await suite.get_tree().process_frame


## The text a control shows now (translated as the player sees it).
static func shown(control: Control) -> String:
	if control == null:
		return "<missing node>"
	return control.atr(control.get("text"))


## Every visible text of the panel, as the player reads it: Labels and Buttons that are visible in
## the tree, and every tooltip. Entries are "<node name>: <text>".
static func visible_texts(controls: Node) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var holder: Control = panel(controls)
	if holder == null:
		return found
	var nodes: Array[Node] = holder.find_children("*", "Control", true, false)
	nodes.append(holder)
	for node: Node in nodes:
		var control: Control = node as Control
		if control.tooltip_text != "":
			found.append("%s tooltip: %s" % [control.name, control.atr(control.tooltip_text)])
		if not control.is_visible_in_tree():
			continue
		if control is Label or control is Button:
			var text: String = shown(control)
			if text != "":
				found.append("%s: %s" % [control.name, text])
	return found
