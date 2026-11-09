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

const Rig := preload("res://tests/helpers/room_rig.gd")

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
