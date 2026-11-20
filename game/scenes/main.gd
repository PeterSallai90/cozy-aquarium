extends Node3D
## The session: owns the live aquarium model and the undo history, and hands them to the room and
## the tank controls. No undo shortcut is bound here; that is a later issue.

var history: CommandHistory = null

var _item_source: ItemCatalogSource = null

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
	_item_source = ItemCatalogSource.new()
	EventBus.bind_history(history)
	(get_node("RoomCorner") as RoomCorner).setup(
		_model, _catalog, null, null, _substrates, history, _item_source
	)
	(get_node("Hud/TankControls") as TankControls).setup(
		_model, _catalog, history, _substrates, null, _item_source
	)


## The item catalog source shared by the item browser and placement; it loads on first need.
func get_item_source() -> ItemCatalogSource:
	return _item_source


## The live model of the session.
func get_model() -> AquariumModel:
	return _model


func _ready() -> void:
	# The room announced its tank before the controls were listening; tell them once.
	EventBus.tank_displayed.emit(_room.get_displayed_tank_id())


func _exit_tree() -> void:
	EventBus.unbind_history()
