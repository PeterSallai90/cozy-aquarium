extends RefCounted
## Builds the item browser (#30) for tests and fixes the contract the plan leaves open, in one
## place (pattern of substrate_ui_rig.gd). ItemBrowser and ItemBrowserList do not exist before the
## implementation, so they are reached by path and by name (a direct reference would be a parse
## error that aborts the whole run). ItemDefinition and ItemCatalog (#152) exist and are used
## directly.
##
## Contract of the technical plan, section 3.2 and 3.3:
## - res://ui/tank/tank_controls.tscn: setup(model, tanks, history, substrates, items) with the
##   item catalog as the fifth argument; Button "ItemsButton" in Group/Buttons.
## - The panel "ItemBrowser" (hidden until opened), setup(model, items) on res://ui/catalog/
##   item_browser.tscn, focus_start(by_keyboard), clear_pick(), get_picked_id() -> StringName and
##   the signal close_requested. Parts, found with find_child by name: "TitleLabel", "Categories"
##   with
##   Buttons "Category_all", "Category_rock", "Category_wood", "Category_ornament",
##   "Category_plant" (each with a child Control "SelectedMark", visible only on the selected one),
##   "SearchField" (LineEdit), "ClearButton", "Scroll" (ScrollContainer) holding "Cards"
##   (GridContainer), "EmptyLabel" and "CloseButton".
## - One Button "Card_<id>" per catalog item, built on the first open and kept (hidden, never
##   freed), in catalog order. A card holds "NameLabel", "SelectedLabel" (visible only on the pick),
##   "Thumbnail" (TextureRect, visible only with a usable texture) and "Placeholder" (Panel with a
##   StyleBoxFlat "panel", visible only without one).
## - Test decisions where the plan is silent:
##   * The card description is the card's tooltip_text (translated, empty without a key).
##   * A mouse open and a keyboard open are told apart by the gui_input signal of ItemsButton that
##     fires before pressed (plan 3.3). press_open() sends that event explicitly; a bare
##     pressed.emit() with no event before it is not tested.
##   * A query is typed by setting SearchField.text and emitting text_changed(text).
##   * A category is selected by setting button_pressed AND emitting pressed on its button, which
##     covers an implementation that listens to either signal.
##   * A card is clicked by emitting pressed on it.

const Ui := preload("res://tests/helpers/tank_ui_rig.gd")
const Rig := preload("res://tests/helpers/room_rig.gd")

const BROWSER_SCENE := "res://ui/catalog/item_browser.tscn"
const LIST_SCRIPT := "res://ui/catalog/item_browser_list.gd"
const BUTTON := "ItemsButton"
const PANEL := "ItemBrowser"
const FIXTURE_EN := "res://tests/fixtures/localization/item_browser_en.po"
const FIXTURE_HU := "res://tests/fixtures/localization/item_browser_hu.po"
const WINDOW := Vector2i(1152, 648)
const CATEGORY_NAMES: Array[String] = [
	"Category_all",
	"Category_rock",
	"Category_wood",
	"Category_ornament",
	"Category_plant",
]

## The fixture items: id, category (ItemDefinition.Category value), sort_order, thumbnail kind
## ("ok" 256 x 256 in memory, "none" null, "empty" a texture of size 0). Listed in a shuffled order
## on purpose; the catalog order is ORDER. plant_missing has no translation on purpose.
const ROWS: Array[Dictionary] = [
	{"id": &"plant_missing", "category": 4, "sort": 2, "thumb": "ok"},
	{"id": &"wood_root", "category": 2, "sort": 2, "thumb": "empty"},
	{"id": &"rock_osko", "category": 1, "sort": 3, "thumb": "ok"},
	{"id": &"ornament_bare", "category": 3, "sort": 2, "thumb": "ok"},
	{"id": &"rock_slate", "category": 1, "sort": 2, "thumb": "none"},
	{"id": &"plant_fern", "category": 4, "sort": 1, "thumb": "ok"},
	{"id": &"wood_drift", "category": 2, "sort": 1, "thumb": "ok"},
	{"id": &"ornament_vase", "category": 3, "sort": 1, "thumb": "ok"},
	{"id": &"rock_granite", "category": 1, "sort": 1, "thumb": "ok"},
]
const ORDER: Array[StringName] = [
	&"rock_granite",
	&"rock_slate",
	&"rock_osko",
	&"wood_drift",
	&"wood_root",
	&"ornament_vase",
	&"ornament_bare",
	&"plant_fern",
	&"plant_missing",
]
## The names of the fixture .po files; plant_missing is in neither.
const NAMES_EN: Dictionary = {
	"rock_granite": "Granite Boulder",
	"rock_slate": "Slate Rock",
	"rock_osko": "Őskő Rock",
	"wood_drift": "Drift Wood",
	"wood_root": "Árvíz Root",
	"ornament_vase": "Blue Vase",
	"ornament_bare": "Bare Ornament",
	"plant_fern": "Java Fern",
	"plant_missing": "item.plant_missing.name",
}
const NAMES_HU: Dictionary = {
	"rock_granite": "Gránit szikla",
	"rock_slate": "Pala kő",
	"rock_osko": "Őskő",
	"wood_drift": "Uszadékfa",
	"wood_root": "Árvízi gyökér",
	"ornament_vase": "Kék váza",
	"ornament_bare": "Csupasz dísz",
	"plant_fern": "Jáva páfrány",
	"plant_missing": "item.plant_missing.name",
}
const DESCRIPTION_EN := "A vase for testing."
const DESCRIPTION_HU := "Egy váza a teszthez."


## Counts what the EventBus pick signals did, in order.
class Listener:
	extends RefCounted
	var picked: Array[StringName] = []
	var cleared: int = 0
	var timeline: Array[String] = []

	func on_picked(catalog_id: StringName) -> void:
		picked.append(catalog_id)
		timeline.append("picked:%s" % catalog_id)

	func on_cleared() -> void:
		cleared += 1
		timeline.append("cleared")


# --- the pure helper, late-bound ---


static func list_exists() -> bool:
	return ResourceLoader.exists(LIST_SCRIPT)


static func _list() -> GDScript:
	return load(LIST_SCRIPT) as GDScript if ResourceLoader.exists(LIST_SCRIPT) else null


## ItemBrowserList.ALL, or -99 while the helper is missing.
static func all_value() -> int:
	var script: GDScript = _list()
	return -99 if script == null else script.get_script_constant_map().get("ALL", -99)


static func category_order() -> Array:
	var script: GDScript = _list()
	return [] if script == null else script.get_script_constant_map().get("CATEGORY_ORDER", [])


static func normalise(text: String) -> Variant:
	var script: GDScript = _list()
	return null if script == null else script.call("normalise_query", text)


static func matches(display_name: String, query: String) -> Variant:
	var script: GDScript = _list()
	return null if script == null else script.call("matches", display_name, query)


## The visible categories as ints (ALL first), or null while the helper is missing.
static func visible_categories(items: ItemCatalog) -> Variant:
	var script: GDScript = _list()
	if script == null:
		return null
	var result: Array = script.call("visible_categories", items)
	var values: Array[int] = []
	for value: Variant in result:
		values.append(int(value))
	return values


## The filtered ids as Strings, or null while the helper is missing. `names` maps id -> name.
static func filter(
	items: ItemCatalog, names: Dictionary, category_value: int, query: String
) -> Variant:
	var script: GDScript = _list()
	if script == null:
		return null
	var typed: Dictionary[StringName, String] = {}
	for key: Variant in names:
		typed[StringName(key)] = String(names[key])
	var result: Array = script.call("filter", items, typed, category_value, query)
	var ids: Array[String] = []
	for id: Variant in result:
		ids.append(String(id))
	return ids


# --- fixture data ---


static func thumbnail(kind: String) -> Texture2D:
	if kind == "none":
		return null
	if kind == "empty":
		return ImageTexture.new()
	var image: Image = Image.create(256, 256, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.4, 0.6, 0.5, 1.0))
	return ImageTexture.create_from_image(image)


static func make_definition(
	id: StringName, category_value: int, sort_order: int, kind: String = "ok", mode_2: bool = false
) -> ItemDefinition:
	var definition: ItemDefinition = ItemDefinition.new()
	definition.id = id
	definition.name_key = "item.%s.name" % id
	if id == &"ornament_vase" or id == &"plant_fern":
		definition.description_key = "item.%s.description" % id
	definition.category = category_value as ItemDefinition.Category
	definition.sort_order = sort_order
	definition.thumbnail = thumbnail(kind)
	if mode_2:
		_fill_mode_2(definition)
	return definition


## A non-default value in the Mode 2 blocks (the browser must not care).
static func _fill_mode_2(definition: ItemDefinition) -> void:
	definition.material = ItemDefinition.ItemMaterial.STONE
	definition.weight_kg = 12.5
	definition.volume_displacement_l = 2.0
	definition.footprint_cm = Vector3(30.0, 20.0, 25.0)
	definition.ph_effect = ItemDefinition.WaterEffect.RAISES
	definition.hardness_effect = ItemDefinition.WaterEffect.RAISES_SLIGHTLY
	definition.tannin_release = 0.4
	definition.hiding_places = 3
	definition.hiding_quality = 0.7
	definition.shade_cover = 0.5
	definition.edge_smoothness = 0.9
	definition.breaks_down = true
	definition.growth_form = ItemDefinition.GrowthForm.STEM
	definition.anchoring = ItemDefinition.Anchoring.ROOTED
	definition.light_need = ItemDefinition.LightNeed.HIGH
	definition.growth_cm_per_week = 5.0
	definition.temp_min_c = 20.0
	definition.temp_max_c = 28.0
	definition.provides_cover = true


static func definitions(mode_2: bool = false, skip: Array[int] = []) -> Array[ItemDefinition]:
	var result: Array[ItemDefinition] = []
	for row: Dictionary in ROWS:
		if skip.has(int(row["category"])):
			continue
		result.append(
			make_definition(row["id"], row["category"], row["sort"], row["thumb"], mode_2)
		)
	return result


## The nine fixture items; `skip` lists categories to leave out.
static func catalog(mode_2: bool = false, skip: Array[int] = []) -> ItemCatalog:
	return ItemCatalog.from_definitions(definitions(mode_2, skip))


## `count` items over the four categories, ids item_000 ..., one in-memory texture each.
static func big_catalog(count: int) -> ItemCatalog:
	var list: Array[ItemDefinition] = []
	for index: int in count:
		list.append(make_definition(StringName("item_%03d" % index), 1 + index % 4, index))
	return ItemCatalog.from_definitions(list)


## ORDER as Strings.
static func order_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: StringName in ORDER:
		ids.append(String(id))
	return ids


static func ids_of(list: Array[ItemDefinition]) -> Array[String]:
	var ids: Array[String] = []
	for definition: ItemDefinition in list:
		ids.append(String(definition.id))
	return ids


## Adds the two fixture translations to the TranslationServer; pass the result to
## remove_translations in after_test.
static func add_translations() -> Array[Translation]:
	var list: Array[Translation] = [
		load(FIXTURE_EN) as Translation, load(FIXTURE_HU) as Translation
	]
	for translation: Translation in list:
		TranslationServer.add_translation(translation)
	return list


static func remove_translations(list: Array[Translation]) -> void:
	for translation: Translation in list:
		TranslationServer.remove_translation(translation)


# --- building ---


## TankControls on `model` with the item catalog as the fifth setup argument, added below
## `parent`. Null while the scene is missing. The caller owns the node. When setup() has no fifth
## parameter yet, it is called with four so the failure is "no ItemsButton", not an engine error.
static func open(
	parent: Node, model: AquariumModel, items: ItemCatalog, history: CommandHistory = null
) -> Control:
	if not ResourceLoader.exists(Ui.CONTROLS_SCENE):
		return null
	var controls: Control = (load(Ui.CONTROLS_SCENE) as PackedScene).instantiate() as Control
	if controls == null:
		return null
	var used: CommandHistory = history if history != null else CommandHistory.new()
	if _setup_arguments(controls) >= 5:
		controls.call("setup", model, Rig.default_catalog(), used, null, items)
	else:
		controls.call("setup", model, Rig.default_catalog(), used)
	parent.add_child(controls)
	await parent.get_tree().process_frame
	return controls


## TankControls with the three-argument setup of the existing UI tests: no item catalog is
## injected, so the browser loads the shipped folders on its first open.
static func open_shipped(parent: Node, model: AquariumModel) -> Control:
	if not ResourceLoader.exists(Ui.CONTROLS_SCENE):
		return null
	var controls: Control = (load(Ui.CONTROLS_SCENE) as PackedScene).instantiate() as Control
	controls.call("setup", model, Rig.default_catalog(), CommandHistory.new())
	parent.add_child(controls)
	await parent.get_tree().process_frame
	return controls


static func _setup_arguments(controls: Node) -> int:
	var script: Script = controls.get_script() as Script
	for entry: Dictionary in script.get_script_method_list():
		if entry["name"] == &"setup":
			return (entry["args"] as Array).size()
	return 0


## The panel scene alone with setup(model, items) called; the caller adds it to the tree.
static func panel_alone(model: AquariumModel, items: ItemCatalog) -> Control:
	if not ResourceLoader.exists(BROWSER_SCENE):
		return null
	var scene_panel: Control = (load(BROWSER_SCENE) as PackedScene).instantiate() as Control
	if scene_panel != null:
		scene_panel.call("setup", model, items)
	return scene_panel


# --- finding parts ---


static func part(controls: Node, node_name: String) -> Node:
	return controls.find_child(node_name, true, false)


static func open_button(controls: Node) -> Button:
	return part(controls, BUTTON) as Button


static func panel(controls: Node) -> Control:
	return part(controls, PANEL) as Control


static func _in_panel(controls: Node, node_name: String) -> Node:
	var holder: Control = panel(controls)
	return null if holder == null else holder.find_child(node_name, true, false)


static func search(controls: Node) -> LineEdit:
	return _in_panel(controls, "SearchField") as LineEdit


static func clear_button(controls: Node) -> Button:
	return _in_panel(controls, "ClearButton") as Button


static func close_button(controls: Node) -> Button:
	return _in_panel(controls, "CloseButton") as Button


static func scroll(controls: Node) -> ScrollContainer:
	return _in_panel(controls, "Scroll") as ScrollContainer


static func cards_box(controls: Node) -> GridContainer:
	return _in_panel(controls, "Cards") as GridContainer


static func empty_label(controls: Node) -> Label:
	return _in_panel(controls, "EmptyLabel") as Label


static func title_label(controls: Node) -> Label:
	return _in_panel(controls, "TitleLabel") as Label


static func category(controls: Node, node_name: String) -> Button:
	return _in_panel(controls, node_name) as Button


## The five category buttons in tree order (hidden ones included).
static func categories(controls: Node) -> Array[Button]:
	var found: Array[Button] = []
	for node_name: String in CATEGORY_NAMES:
		var button: Button = category(controls, node_name)
		if button != null:
			found.append(button)
	return found


## The category buttons that are visible in the tree, as node names, in tree order.
static func visible_category_names(controls: Node) -> Array[String]:
	var found: Array[String] = []
	for button: Button in categories(controls):
		if button.is_visible_in_tree():
			found.append(String(button.name))
	return found


## The category buttons whose SelectedMark is visible, as node names.
static func selected_category_names(controls: Node) -> Array[String]:
	var found: Array[String] = []
	for button: Button in categories(controls):
		var mark: Control = button.find_child("SelectedMark", true, false) as Control
		if mark != null and mark.is_visible_in_tree():
			found.append(String(button.name))
	return found


static func card(controls: Node, id: StringName) -> Button:
	return _in_panel(controls, "Card_%s" % id) as Button


## Every card in tree order, visible or not.
static func cards(controls: Node) -> Array[Button]:
	var found: Array[Button] = []
	var box: GridContainer = cards_box(controls)
	if box == null:
		return found
	for child: Node in box.get_children():
		if child is Button and String(child.name).begins_with("Card_"):
			found.append(child as Button)
	return found


static func card_id(button: Button) -> StringName:
	return StringName(String(button.name).trim_prefix("Card_"))


## The cards that are visible in the tree, in tree order.
static func visible_cards(controls: Node) -> Array[Button]:
	var found: Array[Button] = []
	for button: Button in cards(controls):
		if button.is_visible_in_tree():
			found.append(button)
	return found


static func visible_ids(controls: Node) -> Array[String]:
	var ids: Array[String] = []
	for button: Button in visible_cards(controls):
		ids.append(String(card_id(button)))
	return ids


static func all_ids(controls: Node) -> Array[String]:
	var ids: Array[String] = []
	for button: Button in cards(controls):
		ids.append(String(card_id(button)))
	return ids


## The ids of the visible cards whose SelectedLabel is visible.
static func marked_ids(controls: Node) -> Array[String]:
	var ids: Array[String] = []
	for button: Button in cards(controls):
		var mark: Control = button.find_child("SelectedLabel", true, false) as Control
		if mark != null and mark.is_visible_in_tree():
			ids.append(String(card_id(button)))
	return ids


static func card_part(controls: Node, id: StringName, node_name: String) -> Control:
	var button: Button = card(controls, id)
	return null if button == null else button.find_child(node_name, true, false) as Control


## The text of a control as the player reads it.
static func shown(control: Control) -> String:
	if control == null:
		return "<missing node>"
	return control.atr(control.get("text"))


static func name_of(controls: Node, id: StringName) -> String:
	return shown(card_part(controls, id, "NameLabel"))


static func tooltip_of(controls: Node, id: StringName) -> String:
	var button: Button = card(controls, id)
	return "<missing node>" if button == null else button.atr(button.tooltip_text)


## The names of the visible cards, in order.
static func visible_names(controls: Node) -> Array[String]:
	var names: Array[String] = []
	for button: Button in visible_cards(controls):
		names.append(name_of(controls, card_id(button)))
	return names


## True while the thumbnail is shown and the placeholder is not.
static func thumbnail_shown(controls: Node, id: StringName) -> bool:
	var picture: Control = card_part(controls, id, "Thumbnail")
	var stand_in: Control = card_part(controls, id, "Placeholder")
	return (
		picture != null
		and picture.is_visible_in_tree()
		and (stand_in == null or not stand_in.is_visible_in_tree())
	)


## True while the placeholder is shown and the thumbnail is not.
static func placeholder_shown(controls: Node, id: StringName) -> bool:
	var picture: Control = card_part(controls, id, "Thumbnail")
	var stand_in: Control = card_part(controls, id, "Placeholder")
	return (
		stand_in != null
		and stand_in.is_visible_in_tree()
		and (picture == null or not picture.is_visible_in_tree())
	)


static func is_open(controls: Node) -> bool:
	var holder: Control = panel(controls)
	return holder != null and holder.is_visible_in_tree()


static func picked_id(controls: Node) -> String:
	var holder: Control = panel(controls)
	if holder == null or not holder.has_method("get_picked_id"):
		return "<missing>"
	return String(holder.call("get_picked_id"))


# --- driving ---


static func _frames(suite: Node) -> void:
	await suite.get_tree().process_frame
	await suite.get_tree().process_frame


## Presses the Items button the way the player would: the gui_input event first, then pressed.
static func press_open(suite: Node, controls: Node, by_keyboard: bool = false) -> void:
	var button: Button = open_button(controls)
	var event: InputEvent = null
	if by_keyboard:
		event = Ui.key_event(KEY_ENTER, true)
	else:
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		event = click
	button.gui_input.emit(event)
	button.pressed.emit()
	await _frames(suite)


## Types text into the search field: sets the text and emits text_changed, no frame wait.
static func type_text(controls: Node, text: String) -> void:
	var field: LineEdit = search(controls)
	field.text = text
	field.text_changed.emit(text)


## Selects a category the way a click would (see the header).
static func select_category(controls: Node, node_name: String) -> void:
	var button: Button = category(controls, node_name)
	button.button_pressed = true
	button.pressed.emit()


static func click_card(controls: Node, id: StringName) -> void:
	card(controls, id).pressed.emit()


static func focus_owner(controls: Node) -> Control:
	return controls.get_viewport().gui_get_focus_owner()


## Connects a Listener to the two EventBus pick signals (late-bound, they do not exist yet).
static func listen() -> Listener:
	var listener: Listener = Listener.new()
	if EventBus.has_signal("item_picked"):
		EventBus.connect("item_picked", listener.on_picked)
	if EventBus.has_signal("item_pick_cleared"):
		EventBus.connect("item_pick_cleared", listener.on_cleared)
	return listener


static func unlisten(listener: Listener) -> void:
	if (
		EventBus.has_signal("item_picked")
		and EventBus.is_connected("item_picked", listener.on_picked)
	):
		EventBus.disconnect("item_picked", listener.on_picked)
	if (
		EventBus.has_signal("item_pick_cleared")
		and EventBus.is_connected("item_pick_cleared", listener.on_cleared)
	):
		EventBus.disconnect("item_pick_cleared", listener.on_cleared)
