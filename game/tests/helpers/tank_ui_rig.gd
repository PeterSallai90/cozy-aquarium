extends RefCounted
## Builds the tank controls for tests (#24) and fixes the names the UI tests rely on. The plan
## (section 6) names the scenes and the setup call but not the inner nodes, so the contract is here,
## in one place:
##
## - res://ui/tank/tank_controls.tscn, root script TankControls: setup(model, catalog, history)
##   before it enters the tree; open_panel(panel: Control) shows another panel of the group (and
##   closes the others, the chooser included; refused while the change dialog is open) and
##   close_panels() closes all.
## - Below it, found with find_child by name: Button "ChangeTankButton"; the chooser "TankChooser"
##   (hidden until opened, visible while open) with a Button "CloseButton", a Label "TitleLabel" and
##   one Button per catalog tank named "Card_<tank id>", in ascending size order in the tree. A card
##   holds Labels "NameLabel", "LitresLabel", "DescriptionLabel" and "InUseLabel" (visible only on
##   the tank the room displays); the card holds no other text.
## - The change dialog "TankChangeDialog" (hidden until needed) with Labels "TitleLabel" and
##   "BodyLabel", Buttons "CancelButton" and "ConfirmButton", and a full-rect dimmer Control
##   named "Dimmer" with MOUSE_FILTER_STOP.
## - The chooser follows the displayed tank through EventBus.tank_displayed(tank_id); the room is
##   the only emitter. The rig seeds it once after the room is ready, as Main does.
## TankControls and EventBus.tank_displayed do not exist before the implementation, so they are
## reached by path and by name (a direct member reference would be a parse error).
##
## The tank details panel (#117, plan section 3), also found with find_child by name:
## - Button "TankDetailsButton", in the same HBox as "ChangeTankButton" (Group/Buttons).
## - The panel "TankDetails" (hidden until opened) with a Label "TitleLabel", a VBox "Rows" with
##   exactly 8 children named ROW_NAMES in that order, a Label "FallbackLabel" (visible only when
##   the note is shown) and a Button "CloseButton". Every row holds a Label "ValueLabel"; the six
##   rows after the name and description also hold a Label "KeyLabel".
## - DETAILS_WIDTH mirrors TankDetails.PANEL_WIDTH; if the layout changes, both change together.
## TankDetails is reached by path and name only, never by class name, like the rest of this rig.

const Rig := preload("res://tests/helpers/room_rig.gd")
const Table := preload("res://tests/helpers/tank_table.gd")

const CONTROLS_SCENE := "res://ui/tank/tank_controls.tscn"
const OPEN_BUTTON := "ChangeTankButton"
const CHOOSER := "TankChooser"
const CLOSE_BUTTON := "CloseButton"
const DIALOG := "TankChangeDialog"
const CANCEL_BUTTON := "CancelButton"
const CONFIRM_BUTTON := "ConfirmButton"
const DIMMER := "Dimmer"
const TITLE := "TitleLabel"
const BODY := "BodyLabel"
const DETAILS_BUTTON := "TankDetailsButton"
const DETAILS := "TankDetails"
const ROWS := "Rows"
const ROW_NAMES: Array[String] = [
	"NameRow",
	"DescriptionRow",
	"LengthRow",
	"WidthRow",
	"HeightRow",
	"WaterLevelRow",
	"WaterVolumeRow",
	"GlassThicknessRow",
]
const KEY_LABEL := "KeyLabel"
const VALUE_LABEL := "ValueLabel"
const FALLBACK := "FallbackLabel"
const DETAILS_WIDTH := 360.0


## Room and controls on the given model, catalog and history, added below `suite`, with the
## chooser seeded. Returns {"room": Node3D, "controls": Control}; the controls are null while the
## scene is missing. The caller owns the nodes (auto_free them).
static func open(
	suite: Node, model: AquariumModel, catalog: RefCounted, history: CommandHistory
) -> Dictionary:
	var room: Node3D = Rig.instantiate(model, catalog)
	suite.add_child(room)
	var controls: Control = null
	if ResourceLoader.exists(CONTROLS_SCENE):
		var scene: PackedScene = load(CONTROLS_SCENE) as PackedScene
		controls = scene.instantiate() as Control
		if controls != null:
			controls.call("setup", model, catalog, history)
			suite.add_child(controls)
	await suite.get_tree().process_frame
	if controls != null and EventBus.has_signal("tank_displayed"):
		EventBus.emit_signal("tank_displayed", Rig.displayed_id(room))
		await suite.get_tree().process_frame
	return {"room": room, "controls": controls}


static func part(controls: Node, node_name: String) -> Node:
	return controls.find_child(node_name, true, false)


static func change_button(controls: Node) -> Button:
	return part(controls, OPEN_BUTTON) as Button


static func chooser(controls: Node) -> Control:
	return part(controls, CHOOSER) as Control


static func dialog(controls: Node) -> Control:
	return part(controls, DIALOG) as Control


static func close_button(controls: Node) -> Button:
	return chooser(controls).find_child(CLOSE_BUTTON, true, false) as Button


static func cancel_button(controls: Node) -> Button:
	return dialog(controls).find_child(CANCEL_BUTTON, true, false) as Button


static func confirm_button(controls: Node) -> Button:
	return dialog(controls).find_child(CONFIRM_BUTTON, true, false) as Button


static func card(controls: Node, id: StringName) -> Button:
	return chooser(controls).find_child("Card_%s" % id, true, false) as Button


## The cards in tree order, which must be ascending size order.
static func cards(controls: Node) -> Array[Button]:
	var found: Array[Button] = []
	for node: Node in chooser(controls).find_children("Card_*", "Button", true, false):
		found.append(node as Button)
	return found


static func card_label(controls: Node, id: StringName, label_name: String) -> Label:
	return card(controls, id).find_child(label_name, true, false) as Label


## The card ids in tree order.
static func card_ids(controls: Node) -> Array[StringName]:
	var ids: Array[StringName] = []
	for button: Button in cards(controls):
		ids.append(StringName(String(button.name).trim_prefix("Card_")))
	return ids


## The ids of the cards whose In use marker is visible.
static func marked_ids(controls: Node) -> Array[StringName]:
	var ids: Array[StringName] = []
	for button: Button in cards(controls):
		var marker: Control = button.find_child("InUseLabel", true, false) as Control
		if marker != null and marker.is_visible_in_tree():
			ids.append(StringName(String(button.name).trim_prefix("Card_")))
	return ids


## The text a control shows now (translated as the player sees it).
static func shown(control: Control) -> String:
	if control == null:
		return "<missing node>"
	return control.atr(control.get("text"))


static func is_open(controls: Node) -> bool:
	var panel: Control = chooser(controls)
	return panel != null and panel.is_visible_in_tree()


static func dialog_open(controls: Node) -> bool:
	var panel: Control = dialog(controls)
	return panel != null and panel.is_visible_in_tree()


static func open_chooser(suite: Node, controls: Node) -> void:
	change_button(controls).pressed.emit()
	await suite.get_tree().process_frame
	await suite.get_tree().process_frame


static func focus_owner(controls: Node) -> Control:
	return controls.get_viewport().gui_get_focus_owner()


static func key_event(keycode: Key, pressed: bool, shift: bool = false) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	event.shift_pressed = shift
	return event


## Presses and releases a key through the viewport, like the player would.
static func tap(controls: Node, keycode: Key, shift: bool = false) -> void:
	var viewport: Viewport = controls.get_viewport()
	viewport.push_input(key_event(keycode, true, shift))
	viewport.push_input(key_event(keycode, false, shift))


## A model with the given tank, one item, one fish and a sculpted heightmap.
static func furnished_model(tank_id: StringName) -> AquariumModel:
	var model: AquariumModel = Rig.model_with(tank_id)
	model.apply_set_heightmap(PackedFloat32Array([0.0, 0.2, 0.1, 0.0]), Vector2i(2, 2))
	var item: PlacedItem = PlacedItem.new()
	item.uid = "a0000001"
	item.catalog_id = &"rock_a"
	model.apply_insert_item(item, 0)
	var fish: FishInstance = FishInstance.new()
	fish.uid = "f0000001"
	fish.species_id = &"neon_tetra"
	model.apply_insert_fish(fish, 0)
	return model


# --- the tank details panel (#117) ---


static func details_button(controls: Node) -> Button:
	return part(controls, DETAILS_BUTTON) as Button


static func details(controls: Node) -> Control:
	return part(controls, DETAILS) as Control


## Scoped to the details panel: close_button() belongs to the chooser.
static func details_close_button(controls: Node) -> Button:
	var panel: Control = details(controls)
	return null if panel == null else panel.find_child(CLOSE_BUTTON, true, false) as Button


## The children of Rows in tree order; empty while the panel is missing.
static func details_rows(controls: Node) -> Array[Control]:
	var rows: Array[Control] = []
	var panel: Control = details(controls)
	var holder: Node = null if panel == null else panel.find_child(ROWS, true, false)
	if holder == null:
		return rows
	for child: Node in holder.get_children():
		rows.append(child as Control)
	return rows


static func row(controls: Node, row_name: String) -> Control:
	var panel: Control = details(controls)
	return null if panel == null else panel.find_child(row_name, true, false) as Control


static func row_value(controls: Node, row_name: String) -> String:
	var holder: Control = row(controls, row_name)
	return shown(null if holder == null else holder.find_child(VALUE_LABEL, true, false) as Label)


static func row_key(controls: Node, row_name: String) -> String:
	var holder: Control = row(controls, row_name)
	return shown(null if holder == null else holder.find_child(KEY_LABEL, true, false) as Label)


## The eight value texts in ROW_NAMES order.
static func row_values(controls: Node) -> Array[String]:
	var values: Array[String] = []
	for row_name: String in ROW_NAMES:
		values.append(row_value(controls, row_name))
	return values


static func fallback_shown(controls: Node) -> bool:
	var panel: Control = details(controls)
	var note: Control = (
		null if panel == null else panel.find_child(FALLBACK, true, false) as Control
	)
	return note != null and note.is_visible_in_tree()


static func details_open(controls: Node) -> bool:
	var panel: Control = details(controls)
	return panel != null and panel.is_visible_in_tree()


static func open_details(suite: Node, controls: Node) -> void:
	details_button(controls).pressed.emit()
	await suite.get_tree().process_frame
	await suite.get_tree().process_frame


## Switches the language through the Localization autoload, like the settings screen, so the
## number format follows too, then waits two frames.
static func set_language(suite: Node, code: String) -> void:
	Localization.set_language(code)
	await suite.get_tree().process_frame
	await suite.get_tree().process_frame


## TankControls without a room, added below `parent`, on `model`, `catalog` and `history`, with
## the displayed tank announced as `displayed_id` (as the room would). Use it for fixture catalogs:
## the room would log errors for definitions without a scene. The caller owns the node.
static func open_controls_only(
	parent: Node,
	model: AquariumModel,
	catalog: RefCounted,
	history: CommandHistory,
	displayed_id: StringName
) -> Control:
	if not ResourceLoader.exists(CONTROLS_SCENE):
		return null
	var scene: PackedScene = load(CONTROLS_SCENE) as PackedScene
	var controls: Control = scene.instantiate() as Control
	if controls == null:
		return null
	controls.call("setup", model, catalog, history)
	parent.add_child(controls)
	await parent.get_tree().process_frame
	if EventBus.has_signal("tank_displayed"):
		EventBus.emit_signal("tank_displayed", displayed_id)
	await parent.get_tree().process_frame
	return controls


## A definition with the tank_medium_1 values (id, text keys, sizes) from the issue table, the
## given overrides applied (property name -> value) and no scene.
static func fixture_definition(overrides: Dictionary = {}) -> TankDefinition:
	var definition: TankDefinition = TankDefinition.new()
	definition.id = Table.MEDIUM
	definition.name_key = "tank.medium_1.name"
	definition.description_key = "tank.medium_1.description"
	definition.interior_size_m = Table.interior(Table.MEDIUM)
	definition.glass_thickness_m = Table.glass(Table.MEDIUM)
	definition.water_line_height_m = Table.water_line(Table.MEDIUM)
	definition.volume_litres = Table.row(Table.MEDIUM)["litres"]
	definition.scene = null
	for property: Variant in overrides:
		definition.set(property, overrides[property])
	return definition


static func fixture_catalog(definitions: Array[TankDefinition]) -> TankCatalog:
	return TankCatalog.from_definitions(definitions)
