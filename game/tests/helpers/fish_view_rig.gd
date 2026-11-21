extends RefCounted
## Builds a FishView in a test tree and computes the expected pose of a fish with the real model
## extents (#34 plan section 1, "Extents"). FishView is reached by path (FishApi), so a missing
## class gives a null view and a readable failure instead of a parse error.
## Test decision: setup() is called after the view entered the tree, as the room does.

const Api := preload("res://tests/helpers/fish_api.gd")
const Checks := preload("res://tests/helpers/fish_species_checks.gd")
const Factory := preload("res://tests/helpers/factory.gd")

const STAMP := "2026-11-01T12:00:00Z"
const SAND: StringName = &"sand_fine"
const PEBBLES: StringName = &"pebbles_river"
const SMALL: StringName = &"tank_small_1"
const MEDIUM: StringName = &"tank_medium_1"
const LARGE: StringName = &"tank_large_1"
const IDLE_FACTOR := 0.35

## species id: [horizontal radius, extent below, extent above] of the unscaled model.
static var _unscaled: Dictionary = {}


class Rig:
	extends RefCounted
	var model: AquariumModel = null
	var tanks: TankCatalog = null
	var substrates: SubstrateCatalog = null
	var catalog: RefCounted = null
	var host: Node3D = null
	var view: Node3D = null


## A model with the tank, the substrate (its default colour) and the given FishInstance list.
static func model(
	tank: StringName = MEDIUM, substrate: StringName = SAND, fish_list: Array = []
) -> AquariumModel:
	var result: AquariumModel = AquariumModel.new(STAMP)
	result.apply_set_tank_id(tank)
	var definition: SubstrateDefinition = SubstrateCatalog.load_dir().get_definition(substrate)
	result.apply_set_substrate(substrate, definition.default_colour)
	for entry: FishInstance in fish_list:
		result.apply_insert_fish(entry, result.get_fish_count())
	return result


static func fish(uid: String, species: StringName, variant: int = 0) -> FishInstance:
	return Factory.fish(uid, species, variant)


## A model with one fish of each species (uids f1000001, f1000003, f1000006).
static func trio(tank: StringName = MEDIUM, substrate: StringName = SAND) -> AquariumModel:
	return model(
		tank,
		substrate,
		[
			fish("f1000001", Api.NEON),
			fish("f1000003", Api.ANGEL),
			fish("f1000006", Api.CORY),
		]
	)


## Creates the host and the view, adds them to the suite and calls setup(). The view is null when
## the FishView script is missing. `catalog` null lets the view load the shipped catalog.
static func open(suite: GdUnitTestSuite, source: AquariumModel, catalog: RefCounted = null) -> Rig:
	var rig: Rig = Rig.new()
	rig.model = source
	rig.tanks = TankCatalog.load_dir()
	rig.substrates = SubstrateCatalog.load_dir()
	rig.catalog = catalog if catalog != null else Api.shipped()
	rig.host = Node3D.new()
	suite.add_child(rig.host)
	suite.auto_free(rig.host)
	var script: GDScript = Api.script_of(Api.VIEW_PATH)
	if script == null:
		return rig
	rig.view = script.new() as Node3D
	rig.host.add_child(rig.view)
	rig.view.call("setup", source, rig.tanks, rig.substrates, catalog)
	return rig


static func node_of(rig: Rig, uid: String) -> Node3D:
	if rig.view == null:
		return null
	return rig.view.call("get_fish_node", uid) as Node3D


static func geometry(node: Node) -> Array[GeometryInstance3D]:
	var found: Array[GeometryInstance3D] = []
	for child: Node in node.find_children("*", "GeometryInstance3D", true, false):
		found.append(child as GeometryInstance3D)
	return found


## [radius, below, above] of the unscaled species model: the largest sqrt(x^2 + z^2), minus the
## lowest y and the highest y of every vertex, fins included.
static func unscaled_extents(id: StringName) -> Array:
	if _unscaled.has(id):
		return _unscaled[id]
	var model_data: Checks.FishModel = Checks.open(id)
	var row: Array = [0.0, 0.0, 0.0]
	if model_data.problem.is_empty():
		var radius: float = 0.0
		var low: float = INF
		var high: float = -INF
		for point: Vector3 in Checks.all_points(model_data):
			radius = maxf(radius, Vector2(point.x, point.z).length())
			low = minf(low, point.y)
			high = maxf(high, point.y)
		row = [radius, -low, high]
		_unscaled[id] = row
	model_data.release()
	return row


## The FishExtents of a species scaled by adult_length_cm / 100.
static func extents_of(id: StringName, adult_length_cm: float) -> Object:
	var row: Array = unscaled_extents(id)
	var scale: float = adult_length_cm / 100.0
	return Api.extents(row[0] * scale, row[1] * scale, row[2] * scale)


## The pose the plan fixes for a fish of the model: {"position", "yaw", "pinned"} (empty when a
## class is missing).
static func expected_pose(rig: Rig, uid: String) -> Dictionary:
	var entry: FishInstance = rig.model.get_fish(uid)
	var species: Resource = rig.catalog.call("get_definition", entry.species_id) as Resource
	var tank: TankDefinition = rig.tanks.get_definition(rig.model.get_tank_id())
	var substrate: SubstrateDefinition = rig.substrates.resolve(rig.model.get_substrate_id())
	var surface: Callable = Api.surface_source(
		substrate, rig.model.get_heightmap(), rig.model.get_heightmap_size(), tank.interior_size_m
	)
	return Api.rest_pose(
		uid,
		species.get("preferred_zone"),
		extents_of(entry.species_id, species.get("adult_length_cm")),
		tank.interior_size_m,
		tank.water_line_height_m,
		surface,
		Api.top_allowance(substrate)
	)


## True when the node stands at the expected pose (position and yaw).
static func at_pose(node: Node3D, pose: Dictionary) -> bool:
	if node == null or pose.is_empty():
		return false
	var position: Vector3 = pose["position"]
	var turned: Basis = Basis(Vector3.UP, float(pose["yaw"]))
	return (
		node.position.is_equal_approx(position)
		and node.basis.orthonormalized().is_equal_approx(turned)
	)
