extends RefCounted
## Late-bound access to the #32 classes (DeleteItemCommand, RecolourItemCommand, InputLabels, the
## two HUD scenes).
##
## The tests were written before those files exist. A direct reference to a missing class is a
## parse error that aborts the whole run, so everything goes through load() and call(). Each
## function returns a harmless stand-in while a file is missing; every test asserts the file
## exists first, so it fails with a readable message instead of passing on the stand-in.
##
## Contract of the technical plan (comment on #32): DeleteItemCommand.new(model, uid),
## RecolourItemCommand.new(model, uid, has_colour, colour), InputLabels.primary_label(action),
## WorldInput.is_gesture_running(tree) and GESTURE_GROUP, HistoryControls.setup(history) with
## the children UndoButton and RedoButton, ItemActions.setup(model, source) with DeleteButton,
## ColourRow (ColourLabel, Swatches, OriginalButton) and a Ring panel on the current dot.

const DELETE := "res://model/delete_item_command.gd"
const RECOLOUR := "res://model/recolour_item_command.gd"
const LABELS := "res://systems/input/input_labels.gd"
const HISTORY_SCENE := "res://ui/history/history_controls.tscn"
const ACTIONS_SCENE := "res://ui/placement/item_actions.tscn"
const WORLD_INPUT := "res://systems/input/world_input.gd"
const MAIN_SCENE := "res://scenes/main.tscn"
const AMPHORA: StringName = &"clay_amphora"
const GESTURE_GROUP: StringName = &"world_gesture_sources"


static func exists(path: String) -> bool:
	return ResourceLoader.exists(path)


static func delete_command(model: AquariumModel, uid: String) -> Command:
	if not exists(DELETE):
		return null
	return (load(DELETE) as GDScript).new(model, uid) as Command


static func recolour_command(
	model: AquariumModel, uid: String, has_colour: bool, colour: Color
) -> Command:
	if not exists(RECOLOUR):
		return null
	return (load(RECOLOUR) as GDScript).new(model, uid, has_colour, colour) as Command


## InputLabels.primary_label(action), or "<missing>".
static func primary_label(action: StringName) -> String:
	if not exists(LABELS):
		return "<missing>"
	var script: GDScript = load(LABELS) as GDScript
	if not script.has_method("primary_label"):
		return "<missing>"
	return str(script.call("primary_label", action))


static func is_gesture_running(tree: SceneTree) -> Variant:
	if not exists(WORLD_INPUT):
		return null
	var script: GDScript = load(WORLD_INPUT) as GDScript
	if not script.has_method("is_gesture_running"):
		return null
	return script.call("is_gesture_running", tree)


## The instance of a scene that may not exist yet, or null.
static func instance(path: String) -> Control:
	if not exists(path):
		return null
	return (load(path) as PackedScene).instantiate() as Control


## The first event of an action as text: the logical label when it binds a keycode, the physical
## label otherwise. Independent of the production helper (the formula of the plan).
static func live_label(action: StringName) -> String:
	if not InputMap.has_action(action):
		return "<no action>"
	for event: InputEvent in InputMap.action_get_events(action):
		var key: InputEventKey = event as InputEventKey
		if key != null:
			if key.keycode != 0:
				return key.as_text_keycode()
			return key.as_text_physical_keycode()
	return "<no key event>"
