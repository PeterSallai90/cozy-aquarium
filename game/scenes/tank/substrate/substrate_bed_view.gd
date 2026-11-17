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

const TINT_PARAMETER: StringName = &"substrate_tint"
## The camera must move this far before the LOD is worked out again.
const LOD_STEP_M: float = 0.005
const FLOOR_SKIN_Y_M: float = 0.00005

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
## Built chunks: {"data": SubstrateChunkData, "lod": int, "near": bool (the stones kept behind
## are drawn), "outside": bool (the camera is beyond a pane of the chunk), "items": Array of
## [MultiMesh, variant]}.
var _chunks: Array[Dictionary] = []
## Built top cells: {"node": MultiMeshInstance3D, "box": AABB, "near": bool}.
var _top_cells: Array[Dictionary] = []
var _tile_multimeshes: Array[MultiMesh] = []
var _stone_nodes: Array[MultiMeshInstance3D] = []
var _stones_visible: bool = true
var _complete: bool = false
var _has_camera: bool = false
var _camera_local: Vector3 = Vector3.ZERO
var _lod_dirty: bool = false


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
	_lod_dirty = true
	if _has_camera:
		update_lod(_camera_local)
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
	for cell: Dictionary in _top_cells:
		(cell["node"] as MultiMeshInstance3D).visible = on and bool(cell["near"])


## Sets the swatch colour on every material copy of the view, at once.
func set_tint(colour: Color) -> void:
	_tint = colour
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter(TINT_PARAMETER, colour)


func get_tint() -> Color:
	return _tint


## Chooses the LOD of every chunk from the camera position (in the space of the view) and shows
## the sand top cells within the real-grain range. Does nothing while the camera has moved less
## than 5 mm since the last call and nothing new was built.
func update_lod(camera_local: Vector3) -> void:
	if _has_camera and not _lod_dirty and camera_local.distance_to(_camera_local) < LOD_STEP_M:
		return
	_has_camera = true
	_lod_dirty = false
	_camera_local = camera_local
	var half: Vector2 = SubstrateLod.floor_half(_data)
	for chunk: Dictionary in _chunks:
		var data: SubstrateChunkData = chunk["data"]
		var distance: float = SubstrateLod.distance_to(data.aabb, camera_local)
		var lod: int = 0
		if not _is_sand:
			lod = SubstrateLod.select(
				distance, _look.lod_distances_m, chunk["lod"], _look.lod_hysteresis
			)
		var near: bool = _behind_drawn(distance, chunk["near"])
		var outside: bool = data.is_outside(camera_local, half)
		if lod != int(chunk["lod"]) or near != bool(chunk["near"]) or outside != chunk["outside"]:
			chunk["lod"] = lod
			chunk["near"] = near
			chunk["outside"] = outside
			_apply_lod(chunk)
	for cell: Dictionary in _top_cells:
		var near: bool = (
			SubstrateLod.distance_to(cell["box"], camera_local) < _look.sand_range_end_m
		)
		cell["near"] = near
		(cell["node"] as MultiMeshInstance3D).visible = near and _stones_visible


func get_multimesh_node_count() -> int:
	return _stone_nodes.size() + _top_cells.size()


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
		var shared: MultiMesh = _make_multimesh(_data.top_tiles[tile], _quad)
		shared.custom_aabb = AABB(
			Vector3(-half, _data.top_y_range.x - 0.003, -half),
			Vector3(2.0 * half, _data.top_y_range.y - _data.top_y_range.x + 0.006, 2.0 * half)
		)
		_tile_multimeshes[tile] = shared
	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	node.name = "SandTop_%d_%d" % [_cell_number, _cell_part]
	_cell_part += 1
	node.multimesh = _tile_multimeshes[tile]
	node.material_override = _top_grain_material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var basis: Basis = Basis(Vector3.UP, _data.top_placements[at + 2] * PI / 2.0)
	if _data.top_placements[at + 3] != 0.0:
		basis = basis * Basis.from_scale(Vector3(-1.0, 1.0, 1.0))
	node.transform = Transform3D(basis, Vector3(centre.x, 0.0, centre.y))
	# hidden until update_lod finds the cell within the real-grain range
	node.visible = false
	add_child(node)
	_top_cells.append({"node": node, "box": SubstrateLod.cell_bounds(_data, index), "near": false})


# --- chunks ---


func _build_chunk(chunk: SubstrateChunkData) -> void:
	var items: Array = []
	var lod: int = 0
	# no camera yet: everything at the coarsest mesh, update_lod refines it
	var near: bool = true
	var outside: bool = true
	if not _is_sand:
		lod = _look.lod_distances_m.size()
	if _has_camera:
		var distance: float = SubstrateLod.distance_to(chunk.aabb, _camera_local)
		if not _is_sand:
			lod = SubstrateLod.select(distance, _look.lod_distances_m, -1, 0.0)
		near = SubstrateLod.behind_near(distance, _look)
		outside = chunk.is_outside(_camera_local, SubstrateLod.floor_half(_data))
	for v: int in chunk.buffers.size():
		if chunk.counts[v] == 0:
			continue
		var mesh: Mesh = _quad if _is_sand else _mesh_of(v, lod)
		var multimesh: MultiMesh = _make_multimesh(chunk.buffers[v], mesh)
		var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
		node.name = "Chunk_%d_%d_v%d" % [chunk.key.x, chunk.key.y, v]
		node.multimesh = multimesh
		node.material_override = _chunk_material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visible = _stones_visible
		add_child(node)
		_stone_nodes.append(node)
		items.append([multimesh, v])
	var entry: Dictionary = {
		"data": chunk, "lod": lod, "near": near, "outside": outside, "items": items
	}
	_chunks.append(entry)
	_apply_lod(entry)


## Gives the MultiMeshes of a built chunk the mesh of its LOD and the number of instances it
## draws (SubstrateChunkData.drawn_count: a prefix of the buffer).
func _apply_lod(chunk: Dictionary) -> void:
	var data: SubstrateChunkData = chunk["data"]
	var items: Array = chunk["items"]
	for item: Array in items:
		var multimesh: MultiMesh = item[0]
		var variant: int = int(item[1])
		if not _is_sand:
			multimesh.mesh = _mesh_of(variant, int(chunk["lod"]))
		var drawn: int = data.drawn_count(variant, bool(chunk["near"]), bool(chunk["outside"]))
		multimesh.visible_instance_count = -1 if drawn >= data.counts[variant] else drawn


## True when a chunk at `distance` draws the stones kept behind the visible ones too (with the
## hysteresis of the LOD, so the hidden row does not flicker at the edge of the range).
func _behind_drawn(distance: float, current: bool) -> bool:
	var limit: float = _look.behind_range_m
	if limit <= 0.0:
		return true
	if current:
		return distance <= limit * (1.0 + _look.lod_hysteresis)
	return distance < limit * (1.0 - _look.lod_hysteresis)


func _mesh_of(variant: int, lod: int) -> Mesh:
	if variant >= _meshes.size():
		return null
	var chain: Array = _meshes[variant]
	if chain.is_empty():
		return null
	return chain[mini(lod, chain.size() - 1)]


func _make_multimesh(buffer: PackedFloat32Array, mesh: Mesh) -> MultiMesh:
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = buffer.size() / SubstrateBedData.FLOATS
	multimesh.buffer = buffer
	return multimesh


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
