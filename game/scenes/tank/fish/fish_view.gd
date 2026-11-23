class_name FishView
extends Node3D
## Draws the fish of the model in the tank frame (ADR 0013 rule 8, Amendment 1; ADR 0015 rule 8).
## One pose node per fish uid (get_fish_node), whose only child is the species scene scaled by
## adult_length_cm / 100. A new fish starts at its derived resting pose (FishRestPose, never
## stored) and then swims: this node owns the steering simulation (FishSwimSim), processes while it
## has a fish node and a tank, and in advance(delta) steps the simulation, writes the pose node
## transforms, the tail phase and the swim speed, and emits poses_moved once. The tail bend itself
## is in the vertex shader.
##
## It listens to the model directly (fish_added, fish_removed, fish_changed, tank_changed,
## substrate_changed, heightmap_changed and model_reset); it resolves the tank and the substrate
## through the catalogs, as the room does, so the bed and the fish agree. A tank, substrate or
## heightmap change does not move a node at once: the simulation guides every fish that is outside
## its new limits back with the recovery ease. model_reset rebuilds every fish at its resting pose.
## Reads the model, never writes it. The EventBus relay signals fish_pause_requested,
## fish_override_requested and fish_override_cleared are forwarded to the simulation.
##
## Bad data never breaks the scene: an unknown species shows no fish (listed in get_skipped), a
## variant out of range shows variant 0, a column too small for a fish pins it to the middle; each
## gives exactly one push_warning per entry per build, prefixed "FishView:". The model is untouched.
##
## Read-only contract for presentation overlays (#164, #35): `refreshed` is emitted once after
## every handled model signal, when the pose nodes are final, and `poses_moved` once per advance()
## after the pose nodes moved; has_tank(), get_fish_node() and get_extents() answer from that state.
## Callers must not modify the view or its pose nodes and must not keep pose-node references (pose
## nodes are freed on every rebuild). The view itself knows no overlay.

## Emitted once at the end of every handled model signal (and of setup), after the pose nodes are
## in their final state, also when nothing visible changed (for example a nickname-only change).
signal refreshed
## Emitted once per advance() that moved the pose nodes, after they are in their new state.
signal poses_moved

## Instance shader parameters set on every GeometryInstance3D of a fish (the fish shader).
const PARAM_TINT_COLOUR: StringName = &"variant_tint_colour"
const PARAM_TINT_STRENGTH: StringName = &"variant_tint_strength"
const PARAM_SWIM_PHASE: StringName = &"swim_phase"
const PARAM_SWIM_SPEED: StringName = &"swim_speed"
## The material parameters FishTailPhase needs, read once per species.
const MATERIAL_FREQUENCY: StringName = &"swim_frequency"
const MATERIAL_SPEED_SCALE: StringName = &"swim_speed_scale"
## The bend moves vertices sideways; the cull box of a fish grows by this much (metres).
const CULL_MARGIN_M: float = 0.15
## swim_speed is only written again when it changed by more than this.
const SPEED_WRITE_STEP: float = 1.0e-3
## The steering random source starts from this seed, so a tank behaves the same on every run.
const SIM_SEED: int = 20261123
const WARNING_PREFIX: String = "FishView: "
const _META_SPECIES: StringName = &"fish_species_id"
const _META_VARIANT: StringName = &"fish_variant"

## True: _process does nothing and the caller steps the view with advance() (tests). Set before
## setup().
var manual_stepping: bool = false

var _model: AquariumModel = null
var _tanks: TankCatalog = null
var _substrates: SubstrateCatalog = null
var _catalog: FishCatalog = null
var _tuning: FishSwimTuning = null
var _sim: FishSwimSim = null
var _world: FishSwimWorld = null
var _paused: bool = false
var _nodes: Dictionary[String, Node3D] = {}
var _tracks: Dictionary[String, _Track] = {}
var _skipped: Dictionary[String, String] = {}
var _pin_warned: Dictionary[String, bool] = {}
## Species of the entries skipped for their species, and the entries that already warned about a
## bad variant; both per build.
var _skipped_species: Dictionary[String, StringName] = {}
var _variant_warned: Dictionary[String, bool] = {}
## Scene path to [horizontal radius, below, above] of the unscaled model (metres per body unit).
var _unscaled: Dictionary[String, Vector3] = {}
## Species id to [swim_frequency, swim_speed_scale] of its material.
var _tail_rates: Dictionary[StringName, Vector2] = {}


## What the view keeps per drawn fish for the per-frame update.
class _Track:
	extends RefCounted
	var node: Node3D = null
	var geometries: Array[GeometryInstance3D] = []
	var state: FishSwimState = null
	var phase: float = 0.0
	var written_speed: float = 0.0
	var frequency: float = 0.0
	var speed_scale: float = 1.0


func _process(delta: float) -> void:
	if not manual_stepping:
		advance(delta)


func _exit_tree() -> void:
	_disconnect_bus()


## Connects to the model and draws its fish. `catalog` null loads the shipped catalog when the
## first fish has to be drawn (never at start-up with no fish); `tuning` null loads the shipped
## swim tuning. Call once, after the node is in the tree.
func setup(
	model: AquariumModel,
	tanks: TankCatalog,
	substrates: SubstrateCatalog,
	catalog: FishCatalog = null,
	tuning: FishSwimTuning = null
) -> void:
	_disconnect_model()
	_disconnect_bus()
	_model = model
	_tanks = tanks
	_substrates = substrates
	_catalog = catalog
	_tuning = tuning if tuning != null else FishSwimTuning.load_default()
	_model.fish_added.connect(_on_fish_added)
	_model.fish_removed.connect(_on_fish_removed)
	_model.fish_changed.connect(_on_fish_changed)
	_model.tank_changed.connect(_on_tank_changed)
	_model.substrate_changed.connect(_on_substrate_changed)
	_model.heightmap_changed.connect(_on_heightmap_changed)
	_model.model_reset.connect(_rebuild)
	EventBus.fish_pause_requested.connect(_on_pause_requested)
	EventBus.fish_override_requested.connect(_on_override_requested)
	EventBus.fish_override_cleared.connect(_on_override_cleared)
	_rebuild()


## Steps the simulation by `delta` seconds and moves every pose node (what _process calls). Nothing
## is written and nothing is emitted while paused with no recovery running, or for a delta of 0 or
## less.
func advance(delta: float) -> void:
	if _sim == null or _world == null or _tracks.is_empty():
		return
	var moving: bool = not _paused or _any_recovering()
	if not moving:
		return
	var seconds: float = _sim.clamp_delta(delta)
	if seconds <= 0.0:
		return
	_sim.step(seconds)
	var advance_tail: bool = not _paused
	for track: _Track in _tracks.values():
		var state: FishSwimState = track.state
		track.node.position = state.position
		track.node.basis = Basis(Vector3.UP, state.yaw) * Basis(Vector3.RIGHT, -state.pitch)
		var shown: float = state.shader_speed
		var write_speed: bool = absf(shown - track.written_speed) > SPEED_WRITE_STEP
		if advance_tail:
			track.phase = FishTailPhase.advance(
				track.phase, shown, track.frequency, track.speed_scale, seconds
			)
		if write_speed:
			track.written_speed = shown
		for instance: GeometryInstance3D in track.geometries:
			if advance_tail:
				instance.set_instance_shader_parameter(PARAM_SWIM_PHASE, track.phase)
			if write_speed:
				instance.set_instance_shader_parameter(PARAM_SWIM_SPEED, shown)
	poses_moved.emit()


## The pose node of a fish, or null when the fish is not drawn.
func get_fish_node(uid: String) -> Node3D:
	return _nodes.get(uid)


## The scaled extents (adult length applied) of a drawn fish, or null when the fish has no node.
## Read-only.
func get_extents(uid: String) -> FishExtents:
	var node: Node3D = _nodes.get(uid)
	if node == null:
		return null
	var species: FishSpecies = _species_catalog().get_definition(node.get_meta(_META_SPECIES))
	if species == null:
		return null
	return _scaled_extents(species)


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


func _disconnect_bus() -> void:
	if EventBus.fish_pause_requested.is_connected(_on_pause_requested):
		EventBus.fish_pause_requested.disconnect(_on_pause_requested)
	if EventBus.fish_override_requested.is_connected(_on_override_requested):
		EventBus.fish_override_requested.disconnect(_on_override_requested)
	if EventBus.fish_override_cleared.is_connected(_on_override_cleared):
		EventBus.fish_override_cleared.disconnect(_on_override_cleared)


func _tank() -> TankDefinition:
	if _model == null or _tanks == null:
		return null
	return _tanks.get_definition(_model.get_tank_id())


func _species_catalog() -> FishCatalog:
	if _catalog == null:
		_catalog = FishCatalog.load_dir()
	return _catalog


func _new_sim() -> FishSwimSim:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = SIM_SEED
	var created: FishSwimSim = FishSwimSim.new(_tuning, random)
	created.set_paused(_paused)
	return created


func _rebuild() -> void:
	for node: Node3D in _nodes.values():
		remove_child(node)
		node.queue_free()
	_nodes.clear()
	_tracks.clear()
	_skipped.clear()
	_skipped_species.clear()
	_pin_warned.clear()
	_variant_warned.clear()
	_sim = _new_sim()
	_world = _make_world()
	if _world != null:
		_sim.set_world(_world)
	visible = has_tank()
	for entry: FishInstance in _model.get_fish_list():
		_add_fish(entry.uid)
	_update_processing()
	refreshed.emit()


func _on_fish_added(uid: String, _index: int) -> void:
	_add_fish(uid)
	_update_processing()
	refreshed.emit()


func _on_fish_removed(uid: String, _index: int) -> void:
	_remove_fish(uid)
	_update_processing()
	refreshed.emit()


func _on_fish_changed(uid: String, _index: int) -> void:
	_update_fish(uid)
	_update_processing()
	refreshed.emit()


func _update_fish(uid: String) -> void:
	var entry: FishInstance = _model.get_fish(uid)
	var node: Node3D = _nodes.get(uid)
	if entry == null:
		return
	if node == null and _skipped_species.get(uid) == entry.species_id:
		return
	if node == null or node.get_meta(_META_SPECIES) != entry.species_id:
		var start: FishRestPose.Pose = _current_pose(uid)
		_remove_fish(uid)
		_add_fish(uid, start)
		return
	var species: FishSpecies = _species_catalog().get_definition(entry.species_id)
	if species == null:
		return
	var variant: int = _shown_variant(uid, entry, species)
	if variant != node.get_meta(_META_VARIANT):
		_apply_parameters(node, species, variant)


func _on_tank_changed(_tank_id: StringName) -> void:
	visible = has_tank()
	_sync_world()
	_update_processing()
	refreshed.emit()


func _on_substrate_changed(_substrate_id: StringName, _colour: Color) -> void:
	_sync_world()
	refreshed.emit()


func _on_heightmap_changed(_region: Rect2i) -> void:
	_sync_world()
	refreshed.emit()


func _on_pause_requested(paused: bool) -> void:
	_paused = paused
	if _sim != null:
		_sim.set_paused(paused)


func _on_override_requested(uid: String, target: Vector3) -> void:
	if _sim != null:
		_sim.set_override(uid, target)


func _on_override_cleared(uid: String) -> void:
	if _sim != null:
		_sim.clear_override(uid)


func _update_processing() -> void:
	set_process(not _nodes.is_empty() and has_tank())


func _any_recovering() -> bool:
	for track: _Track in _tracks.values():
		if track.state.recovering:
			return true
	return false


## The simulation world of the current tank and bed, or null while the tank is unknown.
func _make_world() -> FishSwimWorld:
	var tank: TankDefinition = _tank()
	if tank == null or _substrates == null:
		return null
	var substrate: SubstrateDefinition = _substrates.resolve(_model.get_substrate_id())
	var made: FishSwimWorld = FishSwimWorld.new()
	made.interior_size_m = tank.interior_size_m
	made.water_line_m = tank.water_line_height_m
	made.surface_at = FishZones.surface_source(
		substrate, _model.get_heightmap(), _model.get_heightmap_size(), tank.interior_size_m
	)
	made.grain_allowance_m = SubstrateSurface.top_allowance(substrate)
	return made


## A tank, substrate or heightmap change: the simulation gets the new world and guides the fish
## that are outside it; nothing moves here. When the tank was unknown before, the fish start at
## their resting poses.
func _sync_world() -> void:
	var made: FishSwimWorld = _make_world()
	var was_known: bool = _world != null
	_world = made
	if made == null:
		_sim.clear()
		_tracks_forget_state()
		return
	_sim.set_world(made)
	if was_known:
		return
	for uid: String in _nodes:
		_start_in_sim(uid, null)


func _tracks_forget_state() -> void:
	for track: _Track in _tracks.values():
		track.state = null


func _add_fish(uid: String, start: FishRestPose.Pose = null) -> void:
	var entry: FishInstance = _model.get_fish(uid)
	if entry == null or _nodes.has(uid):
		return
	var species: FishSpecies = _species_catalog().get_definition(entry.species_id)
	if species == null:
		_skipped[uid] = 'unknown species "%s"' % entry.species_id
		_skipped_species[uid] = entry.species_id
		push_warning(WARNING_PREFIX + "%s shows no fish: %s" % [uid, _skipped[uid]])
		return
	var scene: Node3D = _instantiate(species.scene)
	if scene == null:
		_skipped[uid] = 'species "%s" has no loadable scene' % entry.species_id
		_skipped_species[uid] = entry.species_id
		push_warning(WARNING_PREFIX + "%s shows no fish: %s" % [uid, _skipped[uid]])
		return
	var node: Node3D = Node3D.new()
	node.name = uid
	scene.scale = Vector3.ONE * (species.adult_length_cm / 100.0)
	node.add_child(scene)
	add_child(node)
	_nodes[uid] = node
	node.set_meta(_META_SPECIES, entry.species_id)
	_apply_parameters(node, species, _shown_variant(uid, entry, species))
	_make_track(uid, node, species)
	_start_in_sim(uid, start)


func _remove_fish(uid: String) -> void:
	_skipped.erase(uid)
	_skipped_species.erase(uid)
	_pin_warned.erase(uid)
	_variant_warned.erase(uid)
	_tracks.erase(uid)
	if _sim != null:
		_sim.remove_fish(uid)
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
	if _variant_warned.has(uid):
		return 0
	_variant_warned[uid] = true
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


## Sets the tint, the shadow and the cull margin on every geometry of the fish.
func _apply_parameters(node: Node3D, species: FishSpecies, variant: int) -> void:
	node.set_meta(_META_VARIANT, variant)
	var colour: Color = species.colour_variants[variant]
	var strength: float = 0.0 if variant == 0 else 1.0
	for found: Node in node.find_children("*", "GeometryInstance3D", true, false):
		var instance: GeometryInstance3D = found as GeometryInstance3D
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.extra_cull_margin = CULL_MARGIN_M
		instance.set_instance_shader_parameter(PARAM_TINT_COLOUR, colour)
		instance.set_instance_shader_parameter(PARAM_TINT_STRENGTH, strength)


## The per-frame record of a fish: its geometries, and its tail phase at the start value of its
## uid with the tail at rest.
func _make_track(uid: String, node: Node3D, species: FishSpecies) -> void:
	var track: _Track = _Track.new()
	track.node = node
	track.phase = TAU * FishHash.unit(uid, FishHash.SALT_SWIM_PHASE)
	var rates: Vector2 = _tail_rate_of(species, node)
	track.frequency = rates.x
	track.speed_scale = rates.y
	for found: Node in node.find_children("*", "GeometryInstance3D", true, false):
		var instance: GeometryInstance3D = found as GeometryInstance3D
		track.geometries.append(instance)
		instance.set_instance_shader_parameter(PARAM_SWIM_PHASE, track.phase)
		instance.set_instance_shader_parameter(PARAM_SWIM_SPEED, 0.0)
	_tracks[uid] = track


## [swim_frequency, swim_speed_scale] of the species material, read once per species; the shader
## defaults (with one warning) when the material has no such parameter.
func _tail_rate_of(species: FishSpecies, node: Node3D) -> Vector2:
	if _tail_rates.has(species.id):
		return _tail_rates[species.id]
	var rates: Vector2 = Vector2(FishTailPhase.DEFAULT_FREQUENCY, FishTailPhase.DEFAULT_SPEED_SCALE)
	var found: bool = false
	for child: Node in node.find_children("*", "MeshInstance3D", true, false):
		var material: Material = (child as MeshInstance3D).get_active_material(0)
		if material is ShaderMaterial:
			var shader_material: ShaderMaterial = material as ShaderMaterial
			var frequency: Variant = shader_material.get_shader_parameter(MATERIAL_FREQUENCY)
			var speed_scale: Variant = shader_material.get_shader_parameter(MATERIAL_SPEED_SCALE)
			if frequency != null and speed_scale != null:
				rates = Vector2(float(frequency), float(speed_scale))
				found = true
				break
	if not found:
		push_warning(
			(
				WARNING_PREFIX
				+ "%s has no swim_frequency in its material: shader defaults" % species.id
			)
		)
	_tail_rates[species.id] = rates
	return rates


## Puts the fish into the simulation at `start`, or at its derived resting pose; the node follows.
## A fish that starts outside its limits (a species change) is eased in.
func _start_in_sim(uid: String, start: FishRestPose.Pose) -> void:
	var node: Node3D = _nodes.get(uid)
	var track: _Track = _tracks.get(uid)
	if node == null or track == null or _world == null or _substrates == null:
		return
	var species: FishSpecies = _species_catalog().get_definition(node.get_meta(_META_SPECIES))
	if species == null:
		return
	var extents: FishExtents = _scaled_extents(species)
	var pose: FishRestPose.Pose = start
	if pose == null:
		pose = _rest_pose(uid, species, extents)
		if not pose.pinned:
			_pin_warned.erase(uid)
		elif not _pin_warned.has(uid):
			_pin_warned[uid] = true
			push_warning(
				WARNING_PREFIX + "%s is pinned to the middle: the water column is too small" % uid
			)
	var params: FishSwimParams = FishSwimParams.create(
		species, FishPersonality.derive(uid), _tuning, extents
	)
	_sim.add_fish(uid, params, pose)
	if start != null:
		_sim.begin_recovery(uid)
	track.state = _sim.get_state(uid)
	track.written_speed = 0.0
	node.position = pose.position
	node.basis = Basis(Vector3.UP, pose.yaw)


## Where the fish is now (position and heading), or null when it has no state.
func _current_pose(uid: String) -> FishRestPose.Pose:
	var track: _Track = _tracks.get(uid)
	if track == null or track.state == null:
		return null
	var pose: FishRestPose.Pose = FishRestPose.Pose.new()
	pose.position = track.state.position
	pose.yaw = track.state.yaw
	return pose


func _rest_pose(uid: String, species: FishSpecies, extents: FishExtents) -> FishRestPose.Pose:
	return FishRestPose.compute(
		uid,
		species.preferred_zone,
		extents,
		_world.interior_size_m,
		_world.water_line_m,
		_world.surface_at,
		_world.grain_allowance_m
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
