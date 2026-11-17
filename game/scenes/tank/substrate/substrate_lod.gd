class_name SubstrateLod
extends RefCounted
## Level of detail of the substrate bed (ADR 0011 rules 11 and 18): the LOD of a chunk from the
## camera distance, the bounds the renderer culls the stones by, and the drawn-triangle estimate
## of #28 AC 33. Static, pure maths, no state.

## Margin of the custom bounds of a chunk's MultiMesh around the chunk bounds (rounding only: the
## chunk bounds already hold the bounding sphere of every stone).
const CHUNK_BOUNDS_MARGIN_M: float = 0.001
## Margin of the custom bounds of a sand top tile's MultiMesh around the bounds of its cell.
const TILE_BOUNDS_MARGIN_M: float = 0.003
## SubstrateBedView.update_lod works the LOD out again only after the camera has moved this far
## since the camera it last worked it out for.
const LOD_STEP_M: float = 0.005
## Added to the cull bounds in the estimate only, so float rounding in the renderer can never
## draw a box the estimate leaves out.
const CULL_TOLERANCE_M: float = 0.00001


## The LOD of a chunk `distance` metres from the camera. `switch_m[k]` is the distance where LOD k
## hands over to LOD k + 1. With a current LOD the hand-over has a hysteresis: a chunk goes up the
## chain a share `hysteresis` beyond the switch distance and comes back the same share before it,
## so it never flickers at the edge. A negative `current` means "no state": the plain bands.
static func select(
	distance: float, switch_m: PackedFloat32Array, current: int, hysteresis: float
) -> int:
	var last: int = switch_m.size()
	if current < 0:
		var plain: int = 0
		while plain < last and distance > switch_m[plain]:
			plain += 1
		return plain
	var lod: int = mini(current, last)
	while lod < last and distance > switch_m[lod] * (1.0 + hysteresis):
		lod += 1
	while lod > 0 and distance < switch_m[lod - 1] * (1.0 - hysteresis):
		lod -= 1
	return lod


## The finest LOD a chunk `distance` metres from the camera can have whatever LOD it had before:
## the hysteresis of select() keeps LOD k up to a share `hysteresis` beyond its switch distance.
static func finest_lod(distance: float, switch_m: PackedFloat32Array, hysteresis: float) -> int:
	var last: int = switch_m.size()
	var lod: int = 0
	while lod < last and distance > switch_m[lod] * (1.0 + hysteresis):
		lod += 1
	return lod


## Distance from a point to the nearest point of a box (0 inside).
static func distance_to(box: AABB, point: Vector3) -> float:
	return point.clamp(box.position, box.end).distance_to(point)


## False when the box lies completely outside one of the planes (outward normals, the convention
## of Camera3D.get_frustum()).
static func in_frustum(box: AABB, frustum: Array[Plane]) -> bool:
	for plane: Plane in frustum:
		# the corner of the box furthest against the normal: if it is over the plane, all are
		var corner: Vector3 = Vector3(
			box.position.x if plane.normal.x > 0.0 else box.end.x,
			box.position.y if plane.normal.y > 0.0 else box.end.y,
			box.position.z if plane.normal.z > 0.0 else box.end.z
		)
		if plane.is_point_over(corner):
			return false
	return true


## The bounds of the top lattice cell of placement `index` (sand).
static func cell_bounds(data: SubstrateBedData, index: int) -> AABB:
	var at: int = index * SubstrateBedData.PLACEMENT_FLOATS
	var half: float = data.top_pitch_m / 2.0
	return AABB(
		Vector3(
			data.top_placements[at] - half, data.top_y_range.x, data.top_placements[at + 1] - half
		),
		Vector3(data.top_pitch_m, data.top_y_range.y - data.top_y_range.x, data.top_pitch_m)
	)


## The custom bounds of a chunk's MultiMeshes: the renderer culls the chunk by these.
static func chunk_cull_bounds(chunk: SubstrateChunkData) -> AABB:
	return chunk.aabb.grow(CHUNK_BOUNDS_MARGIN_M)


## The custom bounds of the MultiMesh of a sand top tile, in the frame of the tile (x and z
## around the cell centre): the bounds of a cell grown by TILE_BOUNDS_MARGIN_M. The square is
## centred, so the quarter turns and the mirror of a placement leave it as it is.
static func tile_bounds(data: SubstrateBedData) -> AABB:
	var half: float = data.top_pitch_m / 2.0
	var cell: AABB = AABB(
		Vector3(-half, data.top_y_range.x, -half),
		Vector3(data.top_pitch_m, data.top_y_range.y - data.top_y_range.x, data.top_pitch_m)
	)
	return cell.grow(TILE_BOUNDS_MARGIN_M)


## The bounds the renderer culls top placement `index` by (sand), in the bed's space: the tile
## bounds at the cell, i.e. the cell bounds grown by TILE_BOUNDS_MARGIN_M.
static func cell_cull_bounds(data: SubstrateBedData, index: int) -> AABB:
	return cell_bounds(data, index).grow(TILE_BOUNDS_MARGIN_M)


## Half the inner floor size of a bed (x, z), the planes of its panes; infinite without an input.
static func floor_half(data: SubstrateBedData) -> Vector2:
	if data == null or data.input == null:
		return Vector2(INF, INF)
	return Vector2(data.input.interior_size_m.x, data.input.interior_size_m.z) / 2.0


## True when a chunk `distance` metres from the camera draws the stones kept behind the visible
## ones (always when the look has no behind range).
static func behind_near(distance: float, look: SubstrateBedLook) -> bool:
	return look.behind_range_m <= 0.0 or distance <= look.behind_range_m


## True when a chunk `distance` metres from the camera may draw the stones kept behind the visible
## ones whatever it drew before: the view keeps drawing them up to the share lod_hysteresis
## beyond the behind range.
static func may_draw_behind(distance: float, look: SubstrateBedLook) -> bool:
	return (
		look.behind_range_m <= 0.0 or distance <= look.behind_range_m * (1.0 + look.lod_hysteresis)
	)


## The drawn-triangle estimate of a bed (AC 33, checked against the triangles Godot draws by
## AC 34(c)): the sum over the chunks the renderer draws of the instances the chunk draws for the
## camera x the triangles of its LOD. It is an upper bound of what the view draws, whatever the
## camera did before:
## - a chunk counts when its cull bounds (chunk_cull_bounds, the custom bounds of its MultiMeshes)
##   intersect the frustum, a sand top cell when the tile bounds at the cell (cell_cull_bounds)
##   do; both grown by CULL_TOLERANCE_M;
## - the view may still hold the state of a camera up to LOD_STEP_M away (update_lod), so every
##   distance is taken LOD_STEP_M shorter and a pane counts as passed within LOD_STEP_M of its
##   glass plane;
## - a chunk counts at the finest LOD the hysteresis can keep at that distance (finest_lod) and
##   with the stones kept behind within the behind range plus the hysteresis (may_draw_behind).
## A chunk draws what SubstrateChunkData.drawn_count gives: the stones seen only through a pane
## when the camera is beyond that pane, the stones kept behind the visible ones within the
## behind range. Ray-cast sand grains count 2 triangles each; sand top cells count within the
## real-grain range. The core, the floor skin and the sand surface (16 triangles at most) are not
## counted. `triangles` holds one PackedInt32Array of triangle counts per LOD for each mesh
## variant (empty for sand); `frustum` and `camera_local` are in the bed's space.
static func estimate_triangles(
	data: SubstrateBedData,
	look: SubstrateBedLook,
	triangles: Array,
	frustum: Array[Plane],
	camera_local: Vector3
) -> int:
	var total: int = 0
	var is_sand: bool = look.grain_class == SubstrateBedLook.CLASS_SAND
	var pane_half: Vector2 = floor_half(data) - Vector2(LOD_STEP_M, LOD_STEP_M)
	for chunk: SubstrateChunkData in data.chunks:
		if not in_frustum(chunk_cull_bounds(chunk).grow(CULL_TOLERANCE_M), frustum):
			continue
		var distance: float = maxf(distance_to(chunk.aabb, camera_local) - LOD_STEP_M, 0.0)
		var near: bool = may_draw_behind(distance, look)
		var outside: bool = chunk.is_outside(camera_local, pane_half)
		if is_sand:
			for v: int in chunk.counts.size():
				total += chunk.drawn_count(v, near, outside) * 2
			continue
		var lod: int = finest_lod(distance, look.lod_distances_m, look.lod_hysteresis)
		for v: int in chunk.counts.size():
			if v >= triangles.size():
				break
			var per_lod: PackedInt32Array = triangles[v]
			if per_lod.is_empty():
				continue
			total += chunk.drawn_count(v, near, outside) * per_lod[mini(lod, per_lod.size() - 1)]
	if not is_sand or data.top_tiles.is_empty():
		return total
	for index: int in data.top_placements.size() / SubstrateBedData.PLACEMENT_FLOATS:
		var box: AABB = cell_bounds(data, index)
		if distance_to(box, camera_local) - LOD_STEP_M >= look.sand_range_end_m:
			continue
		if not in_frustum(cell_cull_bounds(data, index).grow(CULL_TOLERANCE_M), frustum):
			continue
		var tile: int = int(data.top_placements[index * SubstrateBedData.PLACEMENT_FLOATS + 4])
		total += data.tile_instance_count(tile) * 2
	return total
