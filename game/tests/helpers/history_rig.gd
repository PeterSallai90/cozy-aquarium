extends RefCounted
## A placement session (placement_rig.gd) with the real HistoryControls HUD node added to its
## viewport after the room, like Hud comes after RoomCorner in Main, and the EventBus bound to the
## session history (Main does that too). HistoryControls.setup(history) is called before the node
## enters the tree, as main.gd does in _enter_tree. The caller closes the session in after_test.
## History steps for the tests are test-only AddItemCommands, so a shortcut test does not depend
## on the #32 commands.

const Rig := preload("res://tests/helpers/placement_rig.gd")
const Session := preload("res://tests/helpers/placement_session.gd")
const Edit := preload("res://tests/helpers/edit_api.gd")
const Factory := preload("res://tests/helpers/factory.gd")
const AddItemCommand := preload("res://tests/helpers/commands/add_item_command.gd")

const FIRST := "a0000001"
const SECOND := "a0000002"
const META := "history_controls"


## The room with two items (FIRST at 10 degrees, SECOND) and the HistoryControls HUD node.
static func open(suite: GdUnitTestSuite, model: AquariumModel = null) -> Session:
	var start: AquariumModel = model
	if start == null:
		start = Rig.model()
		Rig.add_item(start, FIRST, Rig.BRANCH, -0.1, 0.0, 10.0)
		Rig.add_item(start, SECOND, Rig.STONE, 0.15, 0.0, 0.0)
	var session: Session = await Rig.open(suite, start)
	EventBus.bind_history(session.history)
	var node: Control = Edit.instance(Edit.HISTORY_SCENE)
	if node != null:
		node.call("setup", session.history)
		session.viewport.add_child(node)
		session.set_meta(META, node)
		await suite.get_tree().process_frame
	return session


static func close(session: Session) -> void:
	Rig.close(session)
	EventBus.unbind_history()


static func controls(session: Session) -> Control:
	if not session.has_meta(META):
		return null
	return session.get_meta(META) as Control


static func undo_button(session: Session) -> Button:
	var node: Control = controls(session)
	return node.find_child("UndoButton", true, false) as Button if node != null else null


static func redo_button(session: Session) -> Button:
	var node: Control = controls(session)
	return node.find_child("RedoButton", true, false) as Button if node != null else null


## One undo step: a test-only command that appends a stone with the given uid.
static func step(session: Session, uid: String, x: float = 0.0) -> void:
	var item: PlacedItem = Factory.item(uid, Rig.STONE, Vector3(x, 0.0, -0.1), 0.0, 1.0)
	session.history.execute(AddItemCommand.new(session.model, item))
