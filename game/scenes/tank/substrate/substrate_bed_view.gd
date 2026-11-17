class_name SubstrateBedView
extends Node3D
## One built substrate bed of one type (ADR 0011 rules 6, 11 and 12): the dark core, the floor
## skin and the instanced stones of assembled data. Main thread only.
##
## Children: `Core` (the box behind the shell) and `CoreFloor` (the skin over the whole inner
## floor, the only part that casts a shadow), for sand `SandSurface` (the procedural surface under
## the grains); then one MultiMeshInstance3D per chunk and mesh variant, `Chunk_<ix>_<iz>_v<n>`,
## and for sand one per top tile placement, `SandTop_<cell>_<part>` (cell = number of the lattice
## cell, part = number of the tile part drawn in that cell). begin() adds the core at once;
## build_step() adds the stones in steps so the caller can spread the work over frames.
##
## The view works on copies of the look's materials and sets the tint on the copies. The LOD of a
## chunk is the mesh of its MultiMesh, chosen from the camera distance (update_lod); sand top
## cells are drawn only within the real-grain range. The tank is expected to stand upright and
## unrotated in the world (the shaders get the bed origin, not a full transform).
##
## Cost of the LOD while the camera moves (#28: at most 0.5 ms per frame). The instance data goes
## straight into the GPU buffer of each MultiMesh (_upload), so changing the mesh of a MultiMesh
## never reads its buffer back from the GPU. update_lod works out again only the chunks and cells
## the camera may have changed: each keeps the distance the camera can travel before its LOD, its
## behind range, its pane side or its real-grain range can change (the distance to a box or a
## plane changes by at most the distance the camera moves), and a property is set only when its
## value changes. The result is the same as working out every chunk on every call.

const TINT_PARAMETER: StringName = &"substrate_tint"
## The camera must move this far before the LOD is worked out again.
const LOD_STEP_M: float = 0.005
const FLOOR_SKIN_Y_M: float = 0.00005
## Margin of the custom bounds of a chunk's MultiMesh around the chunk bounds (rounding only: the
## chunk bounds already hold the bounding sphere of every stone).
const BOUNDS_MARGIN_M: float = 0.001
## Bits of the draw state of a chunk: the stones kept behind are drawn, the camera is beyond a
## pane of the chunk (SubstrateChunkData.drawn_count).
const STATE_NEAR: int = 1
const STATE_OUTSIDE: int = 2
## Taken off every slack, so rounding can only make a chunk or cell be worked out a little early.
const SLACK_EPSILON_M: float = 0.00001

static var _grain_cache: Dictionary[String, Array] = {}
static var _quad: ArrayMesh = null

var _data: SubstrateBedData = null
var _look: SubstrateBedLook = null
var _tint: Color = Color.WHITE
var _is_sand: bool = false
var _materials: Array[ShaderMaterial] = []
var _chunk_material: ShaderMaterial = null
var _top_grain_material: ShaderMaterial = null
## Per variant the meshes of its LOD chain, and their triangle counts.
var _meshes: Array = []
var _triangles: Array = []
## Chunks and top placements still to build (indices), in build order.
var _next_chunk: int = 0
var _next_placement: int = 0
var _cell_number: int = -1
var _cell_part: int = 0
var _last_cell: Vector2 = Vector2(INF, INF)
## Built chunks, by build index: data, bounds, LOD, draw state (STATE_*) and the camera path
## length (_travelled) at which the chunk must be worked out again.
var _chunk_data: Array[SubstrateChunkData] = []
var _chunk_low: PackedVector3Array = PackedVector3Array()
var _chunk_high: PackedVector3Array = PackedVector3Array()
var _chunk_lod: PackedInt32Array = PackedInt32Array()
var _chunk_state: PackedInt32Array = PackedInt32Array()
var _chunk_due: PackedFloat64Array = PackedFloat64Array()
var _chunk_panes: PackedInt32Array = PackedInt32Array()
## The MultiMeshes of chunk c are the items _chunk_items[c] to _chunk_items[c + 1] - 1: the
## MultiMesh, the LOD chain of its variant, the LOD of the mesh it has, the
## visible_instance_count it has and, for each draw state, the visible_instance_count it needs
## (4 per item: SubstrateChunkData.drawn_count, -1 for all).
var _chunk_items: PackedInt32Array = PackedInt32Array([0])
var _item_multimesh: Array[MultiMesh] = []
var _item_chain: Array[Array] = []
var _item_mesh_lod: PackedInt32Array = PackedInt32Array()
var _item_shown: PackedInt32Array = PackedInt32Array()
var _item_shown_by_state: PackedInt32Array = PackedInt32Array()
## Built top cells (sand), by build index: node, bounds, drawn, due as for the chunks.
var _cell_nodes: Array[MultiMeshInstance3D] = []
var _cell_low: PackedVector3Array = PackedVector3Array()
var _cell_high: PackedVector3Array = PackedVector3Array()
var _cell_near: PackedByteArray = PackedByteArray()
var _cell_due: PackedFloat64Array = PackedFloat64Array()
var _tile_multimeshes: Array[MultiMesh] = []
var _stone_nodes: Array[MultiMeshInstance3D] = []
var _stones_visible: bool = true
var _complete: bool = false
var _has_camera: bool = false
var _camera_local: Vector3 = Vector3.ZERO
## Path length of the camera over the update_lod calls (metres) and the smallest due mark.
var _travelled: float = 0.0
var _next_due: float = INF
## Hand-over distances of the LOD chain with the hysteresis (SubstrateLod.select): a chunk at LOD
## k goes up the chain beyond _lod_up[k] and down below _lod_down[k - 1]. The same for the behind
## range of the look (a chunk keeps drawing the stones kept behind up to _behind_up and starts
## below _behind_down, so the hidden row does not flicker; no range when _behind_limit is 0) and
## the end of the real-grain range.
var _lod_up: PackedFloat64Array = PackedFloat64Array()
var _lod_down: PackedFloat64Array = PackedFloat64Array()
var _behind_limit: float = 0.0
var _behind_up: float = 0.0
var _behind_down: float = 0.0
var _range_end: float = 0.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE or what == NOTIFICATION_TRANSFORM_CHANGED:
		_apply_origin()


## Starts a view of assembled data: the core and the floor skin (and the sand surface) exist and
## are visible after this call, no stone does. The materials of the look are copied here, once.
func begin(data: SubstrateBedData, look: SubstrateBedLook) -> void:
	_data = data
	_look = look
	_is_sand = look.grain_class == SubstrateBedLook.CLASS_SAND
	set_notify_transform(true)
	var core_material: ShaderMaterial = _copy(look.core_material)
	if core_material != null:
		_tint = _colour_of(core_material.get_shader_parameter(TINT_PARAMETER))
	var core: MeshInstance3D = MeshInstance3D.new()
	core.name = "Core"
	var box: BoxMesh = BoxMesh.new()
	box.size = data.core_size
	core.mesh = box
	core.position = data.core_centre
	core.material_override = core_material
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)
	# The floor skin is what shows between the lowest stones instead of the clear bottom pane,
	# and it casts the shadow of the bed: without it the lamp lights the cabinet top under the
	# tank.
	var interior: Vector3 = data.input.interior_size_m if data.input != null else Vector3.ZERO
	var skin: MeshInstance3D = MeshInstance3D.new()
	skin.name = "CoreFloor"
	var skin_mesh: PlaneMesh = PlaneMesh.new()
	skin_mesh.size = Vector2(interior.x, interior.z)
	skin.mesh = skin_mesh
	skin.position = Vector3(0.0, FLOOR_SKIN_Y_M, 0.0)
	skin.material_override = core_material
	skin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	add_child(skin)
	if _is_sand:
		_begin_sand(interior)
	else:
		_chunk_material = _copy(look.stone_material)
		_read_grain_meshes()
		for switch_m: float in look.lod_distances_m:
			_lod_up.append(switch_m * (1.0 + look.lod_hysteresis))
			_lod_down.append(switch_m * (1.0 - look.lod_hysteresis))
	_behind_limit = maxf(look.behind_range_m, 0.0)
	_behind_up = look.behind_range_m * (1.0 + look.lod_hysteresis)
	_behind_down = look.behind_range_m * (1.0 - look.lod_hysteresis)
	_range_end = look.sand_range_end_m
	_apply_origin()
	_complete = _data.chunks.is_empty() and _placement_count() == 0


## Builds chunks and sand cells until the budget (microseconds) is used; always at least one.
## True when the view is complete.
func build_step(budget_usec: int) -> bool:
	if _data == null or _complete:
		return _complete
	var started: int = Time.get_ticks_usec()
	while true:
		if _next_chunk < _data.chunks.size():
			_build_chunk(_data.chunks[_next_chunk])
			_next_chunk += 1
		elif _next_placement < _placement_count():
			_build_placement(_next_placement)
			_next_placement += 1
		if _next_chunk >= _data.chunks.size() and _next_placement >= _placement_count():
			_complete = true
			break
		if Time.get_ticks_usec() - started >= budget_usec:
			break
	return _complete


func build_all() -> void:
	while not build_step(1000000):
		pass


func is_complete() -> bool:
	return _complete


## Shows or hides every stone and grain; the core, the floor skin and the sand surface stay.
func set_stones_visible(on: bool) -> void:
	_stones_visible = on
	for node: MultiMeshInstance3D in _stone_nodes:
		node.visible = on
	for k: int in _cell_nodes.size():
		_cell_nodes[k].visible = on and _cell_near[k] != 0


## Sets the swatch colour on every material copy of the view, at once.
func set_tint(colour: Color) -> void:
	_tint = colour
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter(TINT_PARAMETER, colour)


func get_tint() -> Color:
	return _tint


## Chooses the LOD of every chunk from the camera position (in the space of the view) and shows
## the sand top cells within the real-grain range. Does nothing while the camera has moved less
## than 5 mm since the last call; chunks and cells built later take the state of the last camera
## at once. Works out again only what the camera may have changed (see the class description).
func update_lod(camera_local: Vector3) -> void:
	if _data == null:
		return
	if _has_camera:
		var moved: float = camera_local.distance_to(_camera_local)
		if moved < LOD_STEP_M:
			return
		_travelled += moved
	_has_camera = true
	_camera_local = camera_local
	if _travelled < _next_due:
		return
	var half: Vector2 = SubstrateLod.floor_half(_data)
	var next: float = INF
	for c: int in _chunk_due.size():
		if _chunk_due[c] <= _travelled:
			_update_chunk(c, half)
		next = minf(next, _chunk_due[c])
	for k: int in _cell_due.size():
		if _cell_due[k] <= _travelled:
			_update_cell(k)
		next = minf(next, _cell_due[k])
	_next_due = next


func get_multimesh_node_count() -> int:
	return _stone_nodes.size() + _cell_nodes.size()


func get_unique_stone_count() -> int:
	return _data.unique_stone_count() if _data != null else 0


## The drawn-triangle estimate of #28 AC 33 for a camera (SubstrateLod.estimate_triangles). The
## budget is defined at 1920 x 1080, so the frustum is the one of the camera's pose and lens at
## the reference aspect 16:9, whatever the size of the window is.
func get_drawn_triangle_estimate(camera: Camera3D) -> int:
	if _data == null or camera == null:
		return 0
	var to_local: Transform3D = global_transform.affine_inverse() * camera.global_transform
	var half: float = tan(deg_to_rad(camera.fov) / 2.0)
	var tan_h: float = half
	var tan_v: float = half
	if camera.keep_aspect == Camera3D.KEEP_WIDTH:
		tan_v = half / CameraFraming.REFERENCE_ASPECT
	else:
		tan_h = half * CameraFraming.REFERENCE_ASPECT
	# outward normals in camera space (the camera looks along -z), as Camera3D.get_frustum()
	var planes: Array[Plane] = [
		Plane(Vector3(-1.0, 0.0, tan_h).normalized(), 0.0),
		Plane(Vector3(1.0, 0.0, tan_h).normalized(), 0.0),
		Plane(Vector3(0.0, 1.0, tan_v).normalized(), 0.0),
		Plane(Vector3(0.0, -1.0, tan_v).normalized(), 0.0),
		Plane(Vector3(0.0, 0.0, 1.0), -camera.near),
		Plane(Vector3(0.0, 0.0, -1.0), camera.far),
	]
	var frustum: Array[Plane] = []
	for plane: Plane in planes:
		frustum.append(to_local * plane)
	return SubstrateLod.estimate_triangles(_data, _look, _triangles, frustum, to_local.origin)


## Bytes of the instance data the view was built from.
func get_memory_bytes() -> int:
	return _data.byte_size() if _data != null else 0


# --- materials ---


func _copy(source: ShaderMaterial) -> ShaderMaterial:
	if source == null:
		return null
	var material: ShaderMaterial = source.duplicate() as ShaderMaterial
	material.set_shader_parameter(&"grain_m", _data.median_size_m)
	if _data.input != null:
		var interior: Vector3 = _data.input.interior_size_m
		material.set_shader_parameter(&"bed_half_size", Vector2(interior.x, interior.z) / 2.0)
		material.set_shader_parameter(&"bed_top", _data.input.depth())
	_materials.append(material)
	return material


func _colour_of(value: Variant) -> Color:
	if value is Color:
		return value
	return Color.WHITE


func _apply_origin() -> void:
	if not is_inside_tree():
		return
	var origin: Vector3 = global_position
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter(&"bed_origin", origin)


# --- sand ---


func _begin_sand(interior: Vector3) -> void:
	var surface: MeshInstance3D = MeshInstance3D.new()
	surface.name = "SandSurface"
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(interior.x, interior.z)
	surface.mesh = plane
	surface.position = Vector3(0.0, _data.input.depth() - _look.sand_surface_drop_m, 0.0)
	surface.material_override = _copy(_look.top_material)
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(surface)
	_chunk_material = _copy(_look.grain_material)
	# The grains of the shared top tiles: they thin out with the distance, and their tone is
	# drawn per cell from the tone spread of the look, so repeated tiles do not repeat it.
	_top_grain_material = _copy(_look.grain_material)
	if _top_grain_material != null:
		for key: Variant in _look.top_grain_parameters:
			_top_grain_material.set_shader_parameter(
				StringName(str(key)), _look.top_grain_parameters[key]
			)
		_top_grain_material.set_shader_parameter(&"fade_begin", _look.sand_range_begin_m)
		_top_grain_material.set_shader_parameter(&"fade_end", _look.sand_range_end_m)
		_top_grain_material.set_shader_parameter(&"world_hash_tint", 1.0)
		_top_grain_material.set_shader_parameter(&"tone_spread", _look.tone_lightness)
		_top_grain_material.set_shader_parameter(&"glint_share", _look.tone_glint_share)
		_top_grain_material.set_shader_parameter(&"glint_gain", _look.tone_glint_gain)
	if _quad == null:
		_quad = _make_quad()
	for tile: PackedFloat32Array in _data.top_tiles:
		_tile_multimeshes.append(null)


func _placement_count() -> int:
	if not _is_sand or _data.top_tiles.is_empty():
		return 0
	return _data.top_placements.size() / SubstrateBedData.PLACEMENT_FLOATS


func _build_placement(index: int) -> void:
	var at: int = index * SubstrateBedData.PLACEMENT_FLOATS
	var centre: Vector2 = Vector2(_data.top_placements[at], _data.top_placements[at + 1])
	if not centre.is_equal_approx(_last_cell):
		_last_cell = centre
		_cell_number += 1
		_cell_part = 0
	var tile: int = int(_data.top_placements[at + 4])
	if _data.tile_instance_count(tile) == 0:
		return
	if _tile_multimeshes[tile] == null:
		var half: float = _data.top_pitch_m / 2.0 + 0.003
		var bounds: AABB = AABB(
			Vector3(-half, _data.top_y_range.x - 0.003, -half),
			Vector3(2.0 * half, _data.top_y_range.y - _data.top_y_range.x + 0.006, 2.0 * half)
		)
		_tile_multimeshes[tile] = _make_multimesh(_data.top_tiles[tile], _quad, bounds)
	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	node.name = "SandTop_%d_%d" % [_cell_number, _cell_part]
	_cell_part += 1
	node.multimesh = _tile_multimeshes[tile]
	node.material_override = _top_grain_material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var basis: Basis = Basis(Vector3.UP, _data.top_placements[at + 2] * PI / 2.0)
	if _data.top_placements[at + 3] != 0.0:
		basis = basis * Basis.from_scale(Vector3(-1.0, 1.0, 1.0))
	node.transform = Transform3D(basis, Vector3(centre.x, 0.0, centre.y))
	# hidden until the camera finds the cell within the real-grain range
	node.visible = false
	add_child(node)
	var box: AABB = SubstrateLod.cell_bounds(_data, index)
	var k: int = _cell_nodes.size()
	_cell_nodes.append(node)
	_cell_low.append(box.position)
	_cell_high.append(box.end)
	_cell_near.append(0)
	_cell_due.append(-INF)
	if _has_camera:
		_update_cell(k)
	_next_due = minf(_next_due, _cell_due[k])


## Shows or hides a top cell for the last camera; the camera may travel the distance to the end
## of the real-grain range before the cell changes.
func _update_cell(k: int) -> void:
	var camera: Vector3 = _camera_local
	var distance: float = camera.clamp(_cell_low[k], _cell_high[k]).distance_to(camera)
	var near: bool = distance < _range_end
	_cell_due[k] = _travelled + absf(distance - _range_end) - SLACK_EPSILON_M
	if near != (_cell_near[k] != 0):
		_cell_near[k] = 1 if near else 0
		_cell_nodes[k].visible = near and _stones_visible


# --- chunks ---


func _build_chunk(chunk: SubstrateChunkData) -> void:
	var c: int = _chunk_data.size()
	var half: Vector2 = SubstrateLod.floor_half(_data)
	# no camera yet: everything at the coarsest mesh and drawn, the first camera refines it
	var lod: int = 0 if _is_sand else _look.lod_distances_m.size()
	var state: int = STATE_NEAR | STATE_OUTSIDE
	var due: float = -INF
	if _has_camera:
		var distance: float = SubstrateLod.distance_to(chunk.aabb, _camera_local)
		if not _is_sand:
			lod = SubstrateLod.select(distance, _look.lod_distances_m, -1, 0.0)
		var near: bool = SubstrateLod.behind_near(distance, _look)
		var outside: bool = chunk.is_outside(_camera_local, half)
		state = (STATE_NEAR if near else 0) | (STATE_OUTSIDE if outside else 0)
		due = _travelled + _chunk_slack(distance, lod, near, chunk.panes, half)
	_chunk_data.append(chunk)
	_chunk_low.append(chunk.aabb.position)
	_chunk_high.append(chunk.aabb.end)
	_chunk_lod.append(lod)
	_chunk_state.append(state)
	_chunk_due.append(due)
	_chunk_panes.append(chunk.panes)
	_next_due = minf(_next_due, due)
	var bounds: AABB = chunk.aabb.grow(BOUNDS_MARGIN_M)
	for v: int in chunk.buffers.size():
		if chunk.counts[v] == 0:
			continue
		var chain: Array = _chain_of(v)
		var mesh_lod: int = 0 if _is_sand else mini(lod, chain.size() - 1)
		var mesh: Mesh = _quad if _is_sand else (chain[mesh_lod] if mesh_lod >= 0 else null)
		var multimesh: MultiMesh = _make_multimesh(chunk.buffers[v], mesh, bounds)
		var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
		node.name = "Chunk_%d_%d_v%d" % [chunk.key.x, chunk.key.y, v]
		node.multimesh = multimesh
		node.material_override = _chunk_material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		node.visible = _stones_visible
		add_child(node)
		_stone_nodes.append(node)
		_item_multimesh.append(multimesh)
		_item_chain.append(chain)
		_item_mesh_lod.append(mesh_lod)
		_item_shown.append(-1)
		for each: int in 4:
			var drawn: int = chunk.drawn_count(
				v, (each & STATE_NEAR) != 0, (each & STATE_OUTSIDE) != 0
			)
			_item_shown_by_state.append(-1 if drawn >= chunk.counts[v] else drawn)
	_chunk_items.append(_item_multimesh.size())
	_apply_lod(c)


## Works out the LOD and the draw state of a built chunk for the last camera, applies what
## changed and keeps the distance the camera may travel before anything can change again: the
## distance to the next hand-over of the LOD chain and of the behind range (both with the
## hysteresis) and to the inner glass plane of each pane of the chunk. The rules are the ones of
## SubstrateLod.select, of the behind range above and of SubstrateChunkData.is_outside, written
## out here because this runs for many chunks per frame while the camera moves.
func _update_chunk(c: int, half: Vector2) -> void:
	var camera: Vector3 = _camera_local
	var distance: float = camera.clamp(_chunk_low[c], _chunk_high[c]).distance_to(camera)
	var state: int = _chunk_state[c]
	var lod: int = _chunk_lod[c]
	var slack: float = INF
	if not _is_sand:
		var last: int = _lod_up.size()
		while lod < last and distance > _lod_up[lod]:
			lod += 1
		while lod > 0 and distance < _lod_down[lod - 1]:
			lod -= 1
		if lod < last:
			slack = _lod_up[lod] - distance
		if lod > 0:
			slack = minf(slack, distance - _lod_down[lod - 1])
	var new_state: int = STATE_NEAR
	if _behind_limit > 0.0:
		if (state & STATE_NEAR) != 0:
			if distance <= _behind_up:
				slack = minf(slack, _behind_up - distance)
			else:
				new_state = 0
				slack = minf(slack, distance - _behind_down)
		elif distance < _behind_down:
			slack = minf(slack, _behind_up - distance)
		else:
			new_state = 0
			slack = minf(slack, distance - _behind_down)
	var panes: int = _chunk_panes[c]
	if panes != 0:
		var outside: bool = false
		if (panes & SubstrateChunkData.PANE_FRONT) != 0:
			outside = camera.z > half.y
			slack = minf(slack, absf(camera.z - half.y))
		if (panes & SubstrateChunkData.PANE_BACK) != 0:
			outside = outside or camera.z < -half.y
			slack = minf(slack, absf(camera.z + half.y))
		if (panes & SubstrateChunkData.PANE_LEFT) != 0:
			outside = outside or camera.x < -half.x
			slack = minf(slack, absf(camera.x + half.x))
		if (panes & SubstrateChunkData.PANE_RIGHT) != 0:
			outside = outside or camera.x > half.x
			slack = minf(slack, absf(camera.x - half.x))
		if outside:
			new_state |= STATE_OUTSIDE
	_chunk_due[c] = _travelled + maxf(slack - SLACK_EPSILON_M, 0.0)
	if lod != _chunk_lod[c] or new_state != state:
		_chunk_lod[c] = lod
		_chunk_state[c] = new_state
		_apply_lod(c)


## How far the camera may move from where a new chunk `distance` metres away has `lod` and
## `near` before anything can change (_update_chunk).
func _chunk_slack(distance: float, lod: int, near: bool, panes: int, half: Vector2) -> float:
	var slack: float = INF
	if not _is_sand:
		if lod < _lod_up.size():
			slack = _lod_up[lod] - distance
		if lod > 0 and lod <= _lod_down.size():
			slack = minf(slack, distance - _lod_down[lod - 1])
	if _behind_limit > 0.0:
		slack = minf(slack, _behind_up - distance if near else distance - _behind_down)
	var camera: Vector3 = _camera_local
	if (panes & SubstrateChunkData.PANE_FRONT) != 0:
		slack = minf(slack, absf(camera.z - half.y))
	if (panes & SubstrateChunkData.PANE_BACK) != 0:
		slack = minf(slack, absf(camera.z + half.y))
	if (panes & SubstrateChunkData.PANE_LEFT) != 0:
		slack = minf(slack, absf(camera.x + half.x))
	if (panes & SubstrateChunkData.PANE_RIGHT) != 0:
		slack = minf(slack, absf(camera.x - half.x))
	return maxf(slack - SLACK_EPSILON_M, 0.0)


## Gives the MultiMeshes of a built chunk the mesh of its LOD and the number of instances it
## draws (a prefix of the buffer); sets only what changes.
func _apply_lod(c: int) -> void:
	var state: int = _chunk_state[c]
	var lod: int = _chunk_lod[c]
	for i: int in range(_chunk_items[c], _chunk_items[c + 1]):
		if not _is_sand:
			var chain: Array = _item_chain[i]
			var mesh_lod: int = mini(lod, chain.size() - 1)
			if mesh_lod != _item_mesh_lod[i]:
				_item_mesh_lod[i] = mesh_lod
				_item_multimesh[i].mesh = chain[mesh_lod]
		var shown: int = _item_shown_by_state[i * 4 + state]
		if shown != _item_shown[i]:
			_item_shown[i] = shown
			_item_multimesh[i].visible_instance_count = shown


## The LOD chain of a mesh variant (empty for sand and for a variant without meshes).
func _chain_of(variant: int) -> Array:
	if _is_sand or variant >= _meshes.size():
		return []
	return _meshes[variant]


## A MultiMesh of the instance buffer with the mesh, drawn within `bounds` (its custom AABB).
func _make_multimesh(buffer: PackedFloat32Array, mesh: Mesh, bounds: AABB) -> MultiMesh:
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.custom_aabb = bounds
	multimesh.instance_count = buffer.size() / SubstrateBedData.FLOATS
	_upload(multimesh, buffer)
	return multimesh


## Writes the instance data of a new MultiMesh. With a RenderingDevice (Forward+) the data goes
## straight into the GPU buffer of the MultiMesh: the rendering server keeps no CPU copy, makes
## no second buffer half for per-instance motion vectors (the stones never move; TAA reprojects
## them with the camera) and, because it never saw the data, never reads the buffer back from the
## GPU when the LOD changes the mesh (through the `buffer` property every mesh change stalled for
## 0.1 to 0.85 ms). So the MultiMesh needs its custom AABB: the server computes no bounds from
## data it never saw. Without a RenderingDevice (headless, Compatibility) the `buffer` property
## is set. The copy runs on the render thread (at once with the default thread model).
static func _upload(multimesh: MultiMesh, buffer: PackedFloat32Array) -> void:
	if RenderingServer.get_rendering_device() == null:
		multimesh.buffer = buffer
		return
	RenderingServer.call_on_render_thread(_upload_on_render_thread.bind(multimesh, buffer))


static func _upload_on_render_thread(multimesh: MultiMesh, buffer: PackedFloat32Array) -> void:
	var device: RenderingDevice = RenderingServer.get_rendering_device()
	var target: RID = RenderingServer.multimesh_get_buffer_rd_rid(multimesh.get_rid())
	if device == null or not target.is_valid():
		multimesh.buffer = buffer
		return
	var bytes: PackedByteArray = buffer.to_byte_array()
	device.buffer_update(target, 0, bytes.size(), bytes)


## Reads the LOD chains of the look's grain glb (nodes <class>_v<n>_lod<k>), once per file.
func _read_grain_meshes() -> void:
	var scene: PackedScene = _look.grain_glb
	if scene == null:
		return
	var path: String = scene.resource_path
	if not _grain_cache.has(path):
		_grain_cache[path] = _load_grain_meshes(scene)
	var cached: Array = _grain_cache[path]
	_meshes = cached[0]
	_triangles = cached[1]


static func _load_grain_meshes(scene: PackedScene) -> Array:
	var root: Node = scene.instantiate()
	var pattern: RegEx = RegEx.create_from_string("_v(\\d+)_lod(\\d+)$")
	var by_variant: Dictionary[int, Dictionary] = {}
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var found: RegExMatch = pattern.search(String(node.name))
		if found == null:
			continue
		var variant: int = int(found.get_string(1))
		var chain: Dictionary = by_variant.get(variant, {})
		chain[int(found.get_string(2))] = (node as MeshInstance3D).mesh
		by_variant[variant] = chain
	root.free()
	var meshes: Array = []
	var triangles: Array = []
	var variants: Array = by_variant.keys()
	variants.sort()
	for variant: int in variants:
		var chain: Dictionary = by_variant[variant]
		var lods: Array = chain.keys()
		lods.sort()
		var chain_meshes: Array = []
		var counts: PackedInt32Array = PackedInt32Array()
		for lod: int in lods:
			var mesh: Mesh = chain[lod]
			chain_meshes.append(mesh)
			counts.append(_triangle_count(mesh))
		meshes.append(chain_meshes)
		triangles.append(counts)
	return [meshes, triangles]


static func _triangle_count(mesh: Mesh) -> int:
	var total: int = 0
	var array_mesh: ArrayMesh = mesh as ArrayMesh
	if array_mesh == null:
		return 0
	for surface: int in array_mesh.get_surface_count():
		var indices: int = array_mesh.surface_get_array_index_len(surface)
		if indices > 0:
			total += indices / 3
		else:
			total += array_mesh.surface_get_array_len(surface) / 3
	return total


## The quad of a ray-cast grain. The vertex shader turns it to the camera, so the bounds of the
## mesh must cover the unit sphere.
static func _make_quad() -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(
		[Vector3(-1, -1, 0), Vector3(1, -1, 0), Vector3(1, 1, 0), Vector3(-1, 1, 0)]
	)
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(
		[Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1)]
	)
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 0, 3, 2])
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.custom_aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
	return mesh
