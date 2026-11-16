class_name SubstrateLod
extends RefCounted
## Level of detail of the substrate bed (ADR 0011 rules 11 and 18): the LOD of a chunk from the
## camera distance, and the drawn-triangle estimate of #28 AC 33. Static, pure maths, no state.


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


## The drawn-triangle estimate of a bed (AC 33): the sum over the chunks whose bounds intersect
## the frustum of instances x the triangles of the LOD the distance to the chunk bounds selects.
## Ray-cast sand grains count 2 triangles each; sand top cells count when they are in the frustum
## and within the real-grain range. `triangles` holds one PackedInt32Array of triangle counts per
## LOD for each mesh variant (empty for sand); `frustum` and `camera_local` are in the bed's
## space.
static func estimate_triangles(
	data: SubstrateBedData,
	look: SubstrateBedLook,
	triangles: Array,
	frustum: Array[Plane],
	camera_local: Vector3
) -> int:
	var total: int = 0
	var is_sand: bool = look.grain_class == SubstrateBedLook.CLASS_SAND
	for chunk: SubstrateChunkData in data.chunks:
		if not in_frustum(chunk.aabb, frustum):
			continue
		if is_sand:
			total += chunk.instance_count() * 2
			continue
		var lod: int = select(distance_to(chunk.aabb, camera_local), look.lod_distances_m, -1, 0.0)
		for v: int in chunk.counts.size():
			if v >= triangles.size():
				break
			var per_lod: PackedInt32Array = triangles[v]
			if per_lod.is_empty():
				continue
			total += chunk.counts[v] * per_lod[mini(lod, per_lod.size() - 1)]
	if not is_sand or data.top_tiles.is_empty():
		return total
	for index: int in data.top_placements.size() / SubstrateBedData.PLACEMENT_FLOATS:
		var box: AABB = cell_bounds(data, index)
		if distance_to(box, camera_local) >= look.sand_range_end_m:
			continue
		if not in_frustum(box, frustum):
			continue
		var tile: int = int(data.top_placements[index * SubstrateBedData.PLACEMENT_FLOATS + 4])
		total += data.tile_instance_count(tile) * 2
	return total
