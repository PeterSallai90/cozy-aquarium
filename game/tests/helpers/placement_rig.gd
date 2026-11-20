extends RefCounted
## Opens a placement session (see placement_session.gd) and builds the fixture items.
##
## Fixture items (test decisions; the plan lists them under tests/fixtures/items/placement/): the
## three shipped decor items, plus two in-memory definitions: "tall_post" (a 4 x 30 x 4 cm post,
## for AC 40) and "no_scene_item" (a definition without a scene, for AC 4). They are built in code
## so no extra resource files are needed.

const Session := preload("res://tests/helpers/placement_session.gd")
const Api := preload("res://tests/helpers/placement_api.gd")
const Cam := preload("res://tests/helpers/camera_rig.gd")
const Factory := preload("res://tests/helpers/factory.gd")

const ROOM_SCENE := "res://scenes/room/room_corner.tscn"
const WINDOW := Vector2i(1152, 648)
const STONE: StringName = &"river_stone"
const BRANCH: StringName = &"driftwood_branch"
const AMPHORA: StringName = &"clay_amphora"
const TALL: StringName = &"tall_post"
const SCENELESS: StringName = &"no_scene_item"
const UNKNOWN: StringName = &"no_such_item"
const SAND: StringName = &"sand_fine"
const PEBBLES: StringName = &"pebbles_river"
const TOP_ELEVATION_DEG: float = 60.0
const LOW_ELEVATION_DEG: float = 8.0
const TALL_HEIGHT_M: float = 0.30
const STAMP := "2026-11-01T12:00:00Z"
const CREAM := Color8(0xE8, 0xD9, 0xB0)


static func model(
	tank_id: StringName = &"tank_medium_1", substrate: StringName = SAND
) -> AquariumModel:
	var result: AquariumModel = AquariumModel.new(STAMP)
	result.apply_set_tank_id(tank_id)
	result.apply_set_substrate(substrate, CREAM)
	return result


static func add_item(
	target: AquariumModel,
	uid: String,
	catalog_id: StringName,
	x: float,
	z: float,
	rotation_y: float = 0.0
) -> void:
	var item: PlacedItem = Factory.item(uid, catalog_id, Vector3(x, 0.0, z), rotation_y, 1.0)
	target.apply_insert_item(item, target.get_item_count())


static func catalog() -> ItemCatalog:
	var shipped: ItemCatalog = ItemCatalog.load_dirs()
	var list: Array[ItemDefinition] = []
	for id: StringName in shipped.get_ids():
		list.append(shipped.get_definition(id))
	list.append(_definition(TALL, _tall_scene()))
	list.append(_definition(SCENELESS, null))
	return ItemCatalog.from_definitions(list)


static func _definition(id: StringName, scene: PackedScene) -> ItemDefinition:
	var definition: ItemDefinition = ItemDefinition.new()
	definition.id = id
	definition.name_key = "item.%s.name" % id
	definition.category = ItemDefinition.Category.ROCK
	definition.scene = scene
	return definition


static func _tall_scene() -> PackedScene:
	var root: Node3D = Node3D.new()
	root.name = "TallPost"
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.04, TALL_HEIGHT_M, 0.04)
	mesh.mesh = box
	mesh.position = Vector3(0.0, TALL_HEIGHT_M / 2.0, 0.0)
	root.add_child(mesh)
	mesh.owner = root
	var scene: PackedScene = PackedScene.new()
	scene.pack(root)
	root.free()
	return scene


## Opens the room of `target` with the Placement child, the camera frozen at the front view with
## the given elevation. The Session fields placement, view and ghost are null while the scene
## lacks the nodes. The caller closes the session in after_test.
static func open(
	suite: GdUnitTestSuite,
	target: AquariumModel = null,
	elevation: float = TOP_ELEVATION_DEG,
	size: Vector2i = WINDOW
) -> Session:
	var session: Session = Session.new()
	session.model = target if target != null else model()
	session.history = CommandHistory.new()
	session.items = catalog()
	session.source = Api.source_from(session.items)
	var viewport: SubViewport = SubViewport.new()
	viewport.size = size
	session.viewport = viewport
	suite.add_child(viewport)
	suite.auto_free(viewport)
	session.connect_bus()
	var scene: PackedScene = load(ROOM_SCENE) as PackedScene
	session.room = scene.instantiate() as Node3D
	_setup(session)
	session.viewport.add_child(session.room)
	await suite.get_tree().process_frame
	await suite.get_tree().process_frame
	session.camera = Cam.camera_of(session.room)
	Cam.freeze(session.room)
	Cam.set_orbit(session.camera, 0.0, elevation, true)
	session.placement = session.room.get_node_or_null("Placement")
	if session.placement != null:
		session.placement.set_process(false)
		session.view = session.placement.get_node_or_null("PlacedItems")
		session.ghost = session.placement.get_node_or_null("Ghost") as Node3D
	return session


## setup(model, tanks, fog, caustics, substrates, history, items) when the room takes seven
## arguments; the two-argument call otherwise, so a missing signature fails a test instead of
## raising an engine error.
static func _setup(session: Session) -> void:
	var tanks: TankCatalog = TankCatalog.load_dir()
	var script: Script = session.room.get_script() as Script
	var count: int = 0
	for entry: Dictionary in script.get_script_method_list():
		if entry["name"] == &"setup":
			count = (entry["args"] as Array).size()
	if count >= 7:
		var room: Node = session.room
		room.call("setup", session.model, tanks, null, null, null, session.history, session.source)
	else:
		session.room.call("setup", session.model, tanks)


## A session on the real Main scene (the real browser answers the pick clear request): the model
## and history of Main, its room, camera and Placement child, the camera frozen at the given
## elevation. The caller sets the root window size first and closes the session.
static func attach(main: Node, elevation: float = TOP_ELEVATION_DEG) -> Session:
	var session: Session = Session.new()
	session.model = main.call("get_model") as AquariumModel
	session.history = main.get("history") as CommandHistory
	session.viewport = main.get_viewport()
	session.room = main.get_node("RoomCorner") as Node3D
	session.camera = Cam.camera_of(session.room)
	Cam.freeze(session.room)
	Cam.set_orbit(session.camera, 0.0, elevation, true)
	session.placement = session.room.get_node_or_null("Placement")
	if session.placement != null:
		session.placement.set_process(false)
		session.view = session.placement.get_node_or_null("PlacedItems")
		session.ghost = session.placement.get_node_or_null("Ghost") as Node3D
	session.connect_bus(false)
	return session


static func close(session: Session) -> void:
	if session != null:
		session.disconnect_bus()
