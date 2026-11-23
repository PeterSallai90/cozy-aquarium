extends RefCounted
## Builds the fish panel (#36) for tests and fixes the contract of the technical plan, section 2,
## in one place (pattern of item_browser_rig.gd). FishPanel, FishInfoCard and FishNameText do not
## exist before the implementation, so everything goes by scene path and by node name; a missing
## scene gives null and a readable failure instead of a parse error that aborts the run.
##
## Contract (plan section 2):
## - res://ui/fish/fish_panel.tscn, root FishPanel: setup(model, history, species = null,
##   uids = null, rng = null), get_selected_species_id() -> StringName, get_shown_fish_uid() ->
##   String, focus_start(), signal close_requested. Lists are built on the first show.
## - TankControls (res://ui/tank/tank_controls.tscn): Button "FishButton" and panel "FishPanel";
##   setup() takes an optional last parameter fish: FishCatalog.
## - Parts found by name: TitleLabel, CloseButton, SpeciesHeading, SpeciesList with toggle Buttons
##   "Species_<id>", AddButton, InTankHeading, CountLabel, TankScroll holding Rows with one
##   "Row_<uid>" per fish (NameButton, SpeciesLabel, RemoveButton), EmptyTankLabel, InfoCard with
##   FishNameLabel, CommonNameLabel, LatinLabel, DescriptionLabel, LengthRow (LengthCaption,
##   LengthValue) and ZoneRow (ZoneCaption, ZoneValue).
## - Test decisions where the plan is silent: a species is selected by setting button_pressed and
##   emitting pressed on its button; a row name or Remove or Add is pressed by emitting pressed.

const Ui := preload("res://tests/helpers/tank_ui_rig.gd")
const Rig := preload("res://tests/helpers/room_rig.gd")
const Api := preload("res://tests/helpers/fish_api.gd")

const PANEL_SCENE := "res://ui/fish/fish_panel.tscn"
const BUTTON := "FishButton"
const PANEL := "FishPanel"
const TANK := &"tank_medium_1"


## A UidGenerator that always returns the same uid (a used one forces the failure case).
class FixedUid:
	extends UidGenerator
	var fixed: String = ""

	func _init(uid: String = "") -> void:
		super(1)
		fixed = uid

	func generate(_model: AquariumModel) -> String:
		return fixed


# --- building ---


static func _setup_arguments(controls: Node) -> int:
	var script: Script = controls.get_script() as Script
	for entry: Dictionary in script.get_script_method_list():
		if entry["name"] == &"setup":
			return (entry["args"] as Array).size()
	return 0


## TankControls on `model` with the optional fish catalog as the seventh setup argument, the tank
## announced as displayed. Null while the scene is missing. The caller owns the node.
static func open_controls(
	parent: Node,
	model: AquariumModel,
	species: RefCounted = null,
	history: CommandHistory = null,
	displayed: StringName = TANK
) -> Control:
	if not ResourceLoader.exists(Ui.CONTROLS_SCENE):
		return null
	var controls: Control = (load(Ui.CONTROLS_SCENE) as PackedScene).instantiate() as Control
	if controls == null:
		return null
	var used: CommandHistory = history if history != null else CommandHistory.new()
	if _setup_arguments(controls) >= 7:
		controls.call("setup", model, Rig.default_catalog(), used, null, null, null, species)
	else:
		controls.call("setup", model, Rig.default_catalog(), used)
	parent.add_child(controls)
	await parent.get_tree().process_frame
	EventBus.tank_displayed.emit(displayed)
	await parent.get_tree().process_frame
	return controls


## The panel scene alone, set up and shown (the lists are built on the first show). Null while
## the scene is missing. The caller owns the node.
static func open_panel_alone(
	parent: Node,
	model: AquariumModel,
	history: CommandHistory,
	species: RefCounted = null,
	uids: UidGenerator = null,
	rng: RandomNumberGenerator = null
) -> Control:
	if not ResourceLoader.exists(PANEL_SCENE):
		return null
	var panel: Control = (load(PANEL_SCENE) as PackedScene).instantiate() as Control
	if panel == null:
		return null
	panel.call("setup", model, history, species, uids, rng)
	panel.visible = false
	parent.add_child(panel)
	await parent.get_tree().process_frame
	panel.visible = true
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	return panel


static func frames(suite: Node, count: int = 2) -> void:
	for i: int in count:
		await suite.get_tree().process_frame


## A seeded generator pair so ids and colours are repeatable.
static func seeded_rng(seed_value: int = 5) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## A fish catalog of the given definitions (FishCatalog.from_definitions); null when missing.
static func catalog_of(definitions: Array) -> RefCounted:
	return Api.catalog_from(definitions)


## A species that holds only the fields the card reads.
static func species_fixture(
	id: StringName, length_cm: float, zone: int, latin: String = "Genus species"
) -> FishSpecies:
	var species: FishSpecies = FishSpecies.new()
	species.id = id
	species.name_key = "fish.%s.name" % id
	species.description_key = "fish.%s.description" % id
	species.scientific_name = latin
	species.adult_length_cm = length_cm
	species.preferred_zone = zone as FishSpecies.Zone
	species.colour_variants = [Color.ORANGE, Color.AQUA]
	return species


# --- finding parts ---


static func part(root: Node, node_name: String) -> Node:
	return root.find_child(node_name, true, false)


## The panel inside TankControls, or the node itself when it is the panel.
static func panel_of(root: Node) -> Control:
	if root.name == PANEL:
		return root as Control
	return part(root, PANEL) as Control


static func button_of(controls: Node) -> Button:
	return part(controls, BUTTON) as Button


static func control(root: Node, node_name: String) -> Control:
	var holder: Control = panel_of(root)
	return null if holder == null else holder.find_child(node_name, true, false) as Control


static func label(root: Node, node_name: String) -> Label:
	return control(root, node_name) as Label


static func btn(root: Node, node_name: String) -> Button:
	return control(root, node_name) as Button


static func add_button(root: Node) -> Button:
	return btn(root, "AddButton")


static func close_button(root: Node) -> Button:
	return btn(root, "CloseButton")


static func species_button(root: Node, id: StringName) -> Button:
	return btn(root, "Species_%s" % id)


static func species_buttons(root: Node) -> Array[Button]:
	var found: Array[Button] = []
	var box: Control = control(root, "SpeciesList")
	if box == null:
		return found
	for child: Node in box.get_children():
		if child is Button and String(child.name).begins_with("Species_"):
			found.append(child as Button)
	return found


static func species_ids(root: Node) -> Array[String]:
	var ids: Array[String] = []
	for button: Button in species_buttons(root):
		ids.append(String(button.name).trim_prefix("Species_"))
	return ids


static func rows(root: Node) -> Array[Control]:
	var found: Array[Control] = []
	var box: Control = control(root, "Rows")
	if box == null:
		return found
	for child: Node in box.get_children():
		if child is Control and String(child.name).begins_with("Row_"):
			found.append(child as Control)
	return found


static func row_uids(root: Node) -> Array[String]:
	var uids: Array[String] = []
	for entry: Control in rows(root):
		uids.append(String(entry.name).trim_prefix("Row_"))
	return uids


static func row(root: Node, uid: String) -> Control:
	var box: Control = control(root, "Rows")
	return null if box == null else box.get_node_or_null("Row_%s" % uid) as Control


static func name_button(root: Node, uid: String) -> Button:
	var holder: Control = row(root, uid)
	return null if holder == null else holder.find_child("NameButton", true, false) as Button


static func row_species_label(root: Node, uid: String) -> Label:
	var holder: Control = row(root, uid)
	return null if holder == null else holder.find_child("SpeciesLabel", true, false) as Label


static func remove_button(root: Node, uid: String) -> Button:
	var holder: Control = row(root, uid)
	return null if holder == null else holder.find_child("RemoveButton", true, false) as Button


static func scroll(root: Node) -> ScrollContainer:
	return control(root, "TankScroll") as ScrollContainer


static func card(root: Node) -> Control:
	return control(root, "InfoCard")


## The text of a control as the player reads it.
static func shown(node: Control) -> String:
	if node == null:
		return "<missing node>"
	return node.atr(node.get("text"))


static func tooltip_of(node: Control) -> String:
	return "<missing node>" if node == null else node.atr(node.tooltip_text)


static func count_text(root: Node) -> String:
	return shown(label(root, "CountLabel"))


static func is_open(controls: Node) -> bool:
	var holder: Control = panel_of(controls)
	return holder != null and holder.is_visible_in_tree()


static func visible_in_tree(node: Control) -> bool:
	return node != null and node.is_visible_in_tree()


static func selected_species(root: Node) -> String:
	var holder: Control = panel_of(root)
	if holder == null or not holder.has_method("get_selected_species_id"):
		return "<missing>"
	return String(holder.call("get_selected_species_id"))


static func shown_fish(root: Node) -> String:
	var holder: Control = panel_of(root)
	if holder == null or not holder.has_method("get_shown_fish_uid"):
		return "<missing>"
	return String(holder.call("get_shown_fish_uid"))


# --- driving ---


## Presses the Fish button the way the player would.
static func press_open(suite: Node, controls: Node) -> void:
	button_of(controls).pressed.emit()
	await frames(suite)


static func click(suite: Node, button: Button) -> void:
	button.pressed.emit()
	await frames(suite)


## Selects a species the way a click on its toggle button would.
static func select_species(suite: Node, root: Node, id: StringName) -> void:
	var button: Button = species_button(root, id)
	button.button_pressed = true
	button.pressed.emit()
	await frames(suite)


static func focus_owner(root: Node) -> Control:
	return root.get_viewport().gui_get_focus_owner()


## Fills the model with `count` fish of the given species (uids f0000001 ...), no command.
static func fill(model: AquariumModel, count: int, species_id: StringName = &"neon_tetra") -> void:
	for index: int in count:
		var fish: FishInstance = FishInstance.new()
		fish.uid = "f%07x" % (index + 1)
		fish.species_id = species_id
		model.apply_insert_fish(fish, model.get_fish_count())


static func model_with_tank() -> AquariumModel:
	return Rig.model_with(TANK)
