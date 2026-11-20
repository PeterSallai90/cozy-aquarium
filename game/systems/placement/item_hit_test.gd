class_name ItemHitTest
extends RefCounted
## Picks the placed item under the pointer ray (#31 AC 19, ADR 0012 rule 3), static and pure. Each
## entry is a Dictionary {"transform": Transform3D, "aabb": AABB}: the item frame in tank-local
## space and the local bounds of its visual meshes. The ray is tested against each oriented box in
## the item frame (slab test); the smallest distance of at least 0 wins and a tie goes to the lower
## index.

const PARALLEL_EPSILON: float = 1e-12


## The index of the nearest hit entry, or -1.
static func nearest(origin: Vector3, direction: Vector3, entries: Array) -> int:
	var best: int = -1
	var best_distance: float = INF
	for index: int in entries.size():
		var entry: Dictionary = entries[index]
		var frame: Transform3D = entry["transform"]
		var box: AABB = entry["aabb"]
		var distance: float = _distance(origin, direction, frame, box)
		if distance >= 0.0 and distance < best_distance:
			best_distance = distance
			best = index
	return best


## The ray parameter where the ray enters the box (0 when it starts inside), or -1 for a miss.
static func _distance(origin: Vector3, direction: Vector3, frame: Transform3D, box: AABB) -> float:
	var inverse: Transform3D = frame.affine_inverse()
	var local_origin: Vector3 = inverse * origin
	var local_direction: Vector3 = inverse.basis * direction
	var near: float = -INF
	var far: float = INF
	for axis: int in 3:
		var low: float = box.position[axis]
		var high: float = box.end[axis]
		var start: float = local_origin[axis]
		var slope: float = local_direction[axis]
		if absf(slope) < PARALLEL_EPSILON:
			if start < low or start > high:
				return -1.0
			continue
		var first: float = (low - start) / slope
		var second: float = (high - start) / slope
		near = maxf(near, minf(first, second))
		far = minf(far, maxf(first, second))
	if near > far or far < 0.0:
		return -1.0
	return maxf(near, 0.0)
