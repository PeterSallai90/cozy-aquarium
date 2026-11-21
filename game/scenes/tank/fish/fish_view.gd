class_name FishView
extends Node3D
## Draws the fish of the model in the tank frame (ADR 0013 rule 8). One pose node per fish uid
## (get_fish_node), whose only child is the species scene scaled by adult_length_cm / 100. The pose
## is derived (FishRestPose), never stored; the tail bend is in the vertex shader, so this node has
## no per-frame code.
##
## It listens to the model directly and repositions synchronously inside the signal handlers
## (fish_added, fish_removed, fish_changed, tank_changed, substrate_changed, heightmap_changed and
## model_reset); it resolves the tank and the substrate through the catalogs, as the room does, so
## the bed and the fish agree. Reads the model, never writes it.
##
## Bad data never breaks the scene: an unknown species shows no fish (listed in get_skipped), a
## variant out of range shows variant 0, a column too small for a fish pins it to the middle; each
## gives exactly one push_warning per entry per build, prefixed "FishView:". The model is untouched.

## The resting fish bends at its species swim_speed times this factor, until #35 moves fish.
const IDLE_SPEED_FACTOR: float = 0.35
## Instance shader parameters set on every GeometryInstance3D of a fish (the fish shader).
const PARAM_TINT_COLOUR: StringName = &"variant_tint_colour"
const PARAM_TINT_STRENGTH: StringName = &"variant_tint_strength"
const PARAM_SWIM_PHASE: StringName = &"swim_phase"
const PARAM_SWIM_SPEED: StringName = &"swim_speed"
## The bend moves vertices sideways; the cull box of a fish grows by this much (metres).
const CULL_MARGIN_M: float = 0.15
const WARNING_PREFIX: String = "FishView: "
const _META_SPECIES: StringName = &"fish_species_id"
const _META_VARIANT: StringName = &"fish_variant"

var _model: AquariumModel = null
var _tanks: TankCatalog = null
var _substrates: SubstrateCatalog = null
var _catalog: FishCatalog = null
var _nodes: Dictionary[String, Node3D] = {}
var _skipped: Dictionary[String, String] = {}
var _pin_warned: Dictionary[String, bool] = {}
## Scene path to [horizontal radius, below, above] of the unscaled model (metres per body unit).
var _unscaled: Dictionary[String, Vector3] = {}


## Connects to the model and draws its fish. `catalog` null loads the shipped catalog when the
## first fish has to be drawn (never at start-up with no fish). Call once, after the node is in
## the tree.
func setup(
	model: AquariumModel,
	tanks: TankCatalog,
	substrates: SubstrateCatalog,
	catalog: FishCatalog = null
) -> void:
	_disconnect_model()
	_model = model
	_tanks = tanks
	_substrates = substrates
	_catalog = catalog
	_model.fish_added.connect(_on_fish_added)
	_model.fish_removed.connect(_on_fish_removed)
	_model.fish_changed.connect(_on_fish_changed)
	_model.tank_changed.connect(_on_tank_changed)
	_model.substrate_changed.connect(_on_substrate_changed)
	_model.heightmap_changed.connect(_on_heightmap_changed)
	_model.model_reset.connect(_rebuild)
	_rebuild()


## The pose node of a fish, or null when the fish is not drawn.
func get_fish_node(uid: String) -> Node3D:
	return _nodes.get(uid)


## The entries that show no fish (uid to developer text), as a copy.
func get_skipped() -> Dictionary[String, String]:
	return _skipped.duplicate()


## True when the tank of the model is known, so the fish have a place; the view is hidden otherwise.
func has_tank() -> bool:
	return _tank() != null


func _disconnect_model() -> void:
	if _model == null:
		return
	_model.fish_added.disconnect(_on_fish_added)
	_model.fish_removed.disconnect(_on_fish_removed)
	_model.fish_changed.disconnect(_on_fish_changed)
	_model.tank_changed.disconnect(_on_tank_changed)
	_model.substrate_changed.disconnect(_on_substrate_changed)
	_model.heightmap_changed.disconnect(_on_heightmap_changed)
	_model.model_reset.disconnect(_rebuild)


func _tank() -> TankDefinition:
	if _model == null or _tanks == null:
		return null
	return _tanks.get_definition(_model.get_tank_id())


func _species_catalog() -> FishCatalog:
	if _catalog == null:
		_catalog = FishCatalog.load_dir()
	return _catalog


func _rebuild() -> void:
	for node: Node3D in _nodes.values():
		remove_child(node)
		node.queue_free()
	_nodes.clear()
	_skipped.clear()
	_pin_warned.clear()
	visible = has_tank()
	for entry: FishInstance in _model.get_fish_list():
		_add_fish(entry.uid)


func _on_fish_added(uid: String, _index: int) -> void:
	_add_fish(uid)


func _on_fish_removed(uid: String, _index: int) -> void:
	_remove_fish(uid)


func _on_fish_changed(uid: String, _index: int) -> void:
	var entry: FishInstance = _model.get_fish(uid)
	var node: Node3D = _nodes.get(uid)
	if entry == null:
		return
	if node == null or node.get_meta(_META_SPECIES) != entry.species_id:
		_remove_fish(uid)
		_add_fish(uid)
		return
	var species: FishSpecies = _species_catalog().get_definition(entry.species_id)
	if species == null:
		return
	var variant: int = _shown_variant(uid, entry, species)
	if variant != node.get_meta(_META_VARIANT):
		_apply_parameters(node, uid, species, variant)


func _on_tank_changed(_tank_id: StringName) -> void:
	visible = has_tank()
	_reposition_all()


func _on_substrate_changed(_substrate_id: StringName, _colour: Color) -> void:
	_reposition_all()


func _on_heightmap_changed(_region: Rect2i) -> void:
	_reposition_all()


func _add_fish(uid: String) -> void:
	var entry: FishInstance = _model.get_fish(uid)
	if entry == null or _nodes.has(uid):
		return
	var species: FishSpecies = _species_catalog().get_definition(entry.species_id)
	if species == null:
		_skipped[uid] = 'unknown species "%s"' % entry.species_id
		push_warning(WARNING_PREFIX + "%s shows no fish: %s" % [uid, _skipped[uid]])
		return
	var scene: Node3D = _instantiate(species.scene)
	if scene == null:
		_skipped[uid] = 'species "%s" has no loadable scene' % entry.species_id
		push_warning(WARNING_PREFIX + "%s shows no fish: %s" % [uid, _skipped[uid]])
		return
	var node: Node3D = Node3D.new()
	node.name = uid
	scene.scale = Vector3.ONE * (species.adult_length_cm / 100.0)
	node.add_child(scene)
	add_child(node)
	_nodes[uid] = node
	node.set_meta(_META_SPECIES, entry.species_id)
	_apply_parameters(node, uid, species, _shown_variant(uid, entry, species))
	_place(uid)


func _remove_fish(uid: String) -> void:
	_skipped.erase(uid)
	_pin_warned.erase(uid)
	var node: Node3D = _nodes.get(uid)
	if node == null:
		return
	_nodes.erase(uid)
	remove_child(node)
	node.queue_free()


func _instantiate(scene: PackedScene) -> Node3D:
	if scene == null:
		return null
	var instance: Node = scene.instantiate()
	if instance is Node3D:
		return instance as Node3D
	if instance != null:
		instance.free()
	return null


## The variant to show: the saved one, or 0 (with one warning) when it is not a variant of the
## species.
func _shown_variant(uid: String, entry: FishInstance, species: FishSpecies) -> int:
	if entry.variant >= 0 and entry.variant < species.colour_variants.size():
		return entry.variant
	push_warning(
		(
			WARNING_PREFIX
			+ (
				"%s shows variant 0: variant %d is not one of the %d variants of %s"
				% [uid, entry.variant, species.colour_variants.size(), entry.species_id]
			)
		)
	)
	return 0


## Sets the four instance parameters, the shadow and the cull margin on every geometry of the fish.
func _apply_parameters(node: Node3D, uid: String, species: FishSpecies, variant: int) -> void:
	node.set_meta(_META_VARIANT, variant)
	var colour: Color = species.colour_variants[variant]
	var strength: float = 0.0 if variant == 0 else 1.0
	var phase: float = TAU * FishHash.unit(uid, FishHash.SALT_SWIM_PHASE)
	var speed: float = minf(species.swim_speed * IDLE_SPEED_FACTOR, 1.0)
	for found: Node in node.find_children("*", "GeometryInstance3D", true, false):
		var instance: GeometryInstance3D = found as GeometryInstance3D
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.extra_cull_margin = CULL_MARGIN_M
		instance.set_instance_shader_parameter(PARAM_TINT_COLOUR, colour)
		instance.set_instance_shader_parameter(PARAM_TINT_STRENGTH, strength)
		instance.set_instance_shader_parameter(PARAM_SWIM_PHASE, phase)
		instance.set_instance_shader_parameter(PARAM_SWIM_SPEED, speed)


func _reposition_all() -> void:
	for uid: String in _nodes:
		_place(uid)


## Puts the fish at its derived resting pose; nothing happens while the tank is unknown.
func _place(uid: String) -> void:
	var node: Node3D = _nodes.get(uid)
	var tank: TankDefinition = _tank()
	if node == null or tank == null or _substrates == null:
		return
	var species: FishSpecies = _species_catalog().get_definition(node.get_meta(_META_SPECIES))
	if species == null:
		return
	var substrate: SubstrateDefinition = _substrates.resolve(_model.get_substrate_id())
	var surface: Callable = FishZones.surface_source(
		substrate, _model.get_heightmap(), _model.get_heightmap_size(), tank.interior_size_m
	)
	var pose: FishRestPose.Pose = FishRestPose.compute(
		uid,
		species.preferred_zone,
		_scaled_extents(species),
		tank.interior_size_m,
		tank.water_line_height_m,
		surface,
		SubstrateSurface.top_allowance(substrate)
	)
	node.position = pose.position
	node.basis = Basis(Vector3.UP, pose.yaw)
	if not pose.pinned:
		_pin_warned.erase(uid)
	elif not _pin_warned.has(uid):
		_pin_warned[uid] = true
		push_warning(
			WARNING_PREFIX + "%s is pinned to the middle: the water column is too small" % uid
		)


## The extents of the species model times its scale.
func _scaled_extents(species: FishSpecies) -> FishExtents:
	var path: String = species.scene.resource_path
	if not _unscaled.has(path):
		_unscaled[path] = _measure(species.scene)
	var row: Vector3 = _unscaled[path]
	var factor: float = species.adult_length_cm / 100.0
	return FishExtents.create(row.x * factor, row.y * factor, row.z * factor)


## [horizontal radius, below, above] of every vertex of the scene, fins included (body units).
func _measure(scene: PackedScene) -> Vector3:
	var root: Node3D = _instantiate(scene)
	if root == null:
		return Vector3.ZERO
	var radius: float = 0.0
	var low: float = INF
	var high: float = -INF
	for found: Node in root.find_children("*", "MeshInstance3D", true, false):
		var instance: MeshInstance3D = found as MeshInstance3D
		if instance.mesh == null:
			continue
		var to_root: Transform3D = _transform_to(instance, root)
		for surface: int in instance.mesh.get_surface_count():
			var arrays: Array = instance.mesh.surface_get_arrays(surface)
			for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array:
				var point: Vector3 = to_root * vertex
				radius = maxf(radius, Vector2(point.x, point.z).length())
				low = minf(low, point.y)
				high = maxf(high, point.y)
	root.free()
	if low > high:
		return Vector3.ZERO
	return Vector3(radius, -low, high)


func _transform_to(node: Node3D, root: Node3D) -> Transform3D:
	var result: Transform3D = Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result
