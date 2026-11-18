extends Node3D
## The session: owns the live aquarium model and the undo history, and hands them to the room and
## the tank controls. No undo shortcut is bound here; that is a later issue.

var history: CommandHistory = null

var _model: AquariumModel = null
var _catalog: TankCatalog = null
var _substrates: SubstrateCatalog = null

@onready var _room: RoomCorner = $RoomCorner


## The children exist but are not ready yet, so the services are handed over before their _ready.
func _enter_tree() -> void:
	_model = AquariumModel.new()
	_catalog = TankCatalog.load_dir()
	_substrates = SubstrateCatalog.load_dir()
	SubstrateSetup.apply_default(_model, _substrates)
	history = CommandHistory.new()
	EventBus.bind_history(history)
	(get_node("RoomCorner") as RoomCorner).setup(_model, _catalog, null, null, _substrates)
	(get_node("Hud/TankControls") as TankControls).setup(_model, _catalog, history, _substrates)


## The live model of the session.
func get_model() -> AquariumModel:
	return _model


func _ready() -> void:
	# The room announced its tank before the controls were listening; tell them once.
	EventBus.tank_displayed.emit(_room.get_displayed_tank_id())


func _exit_tree() -> void:
	EventBus.unbind_history()
