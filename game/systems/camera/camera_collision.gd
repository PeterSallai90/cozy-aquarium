class_name CameraCollision
extends RefCounted
## Pure collision maths of the build camera (ADR 0009). A solid plus margin is the box grown by
## the margin on every face; a point on the grown boundary is outside.

const EPSILON: float = 0.000001
const FAR_M: float = 1000000.0


static func is_clear(solids: Array[AABB], margin_m: float, point: Vector3) -> bool:
	for box: AABB in solids:
		if _inside(box.grow(margin_m), point):
			return false
	return true


## The open interval (t_in, t_out) of the line origin + direction * t inside the box; t_in >= t_out
## means no hit.
static func line_interval(origin: Vector3, direction: Vector3, box: AABB) -> Vector2:
	var t_in: float = -INF
	var t_out: float = INF
	for axis: int in 3:
		var low: float = box.position[axis]
		var high: float = box.end[axis]
		if absf(direction[axis]) < EPSILON:
			if origin[axis] <= low or origin[axis] >= high:
				return Vector2(INF, -INF)
			continue
		var first: float = (low - origin[axis]) / direction[axis]
		var second: float = (high - origin[axis]) / direction[axis]
		t_in = maxf(t_in, minf(first, second))
		t_out = minf(t_out, maxf(first, second))
	return Vector2(t_in, t_out)


## The smallest distance at or above requested_m that is outside every grown solid.
static func held_distance(
	solids: Array[AABB], margin_m: float, pivot: Vector3, direction: Vector3, requested_m: float
) -> float:
	return _chain(solids, margin_m, pivot, direction, requested_m, false, 0.0)


## The lowest elevation at which a camera held outside the grown footprints of the solids that
## span the plane still reaches the plane height; -90 when the pivot is inside the footprint.
static func lowest_held_elevation_deg(
	solids: Array[AABB], margin_m: float, pivot: Vector3, azimuth_deg: float, plane_y: float
) -> float:
	var flat: Vector3 = OrbitMath.offset(azimuth_deg, 0.0, 1.0)
	var reach: float = _chain(solids, margin_m, pivot, flat, 0.0, true, plane_y)
	if reach <= EPSILON:
		return -90.0
	return -rad_to_deg(atan((pivot.y - plane_y) / reach))


## Leaves the grown solids one after the other. With footprints, only the solids whose grown
## box spans plane_y count, and only by their x/z extent. Allocates nothing.
static func _chain(
	solids: Array[AABB],
	margin_m: float,
	origin: Vector3,
	direction: Vector3,
	requested_m: float,
	footprints: bool,
	plane_y: float
) -> float:
	var t: float = requested_m
	for pass_index: int in solids.size() + 1:
		var moved: bool = false
		for box: AABB in solids:
			var grown: AABB = box.grow(margin_m)
			if footprints:
				if grown.position.y > plane_y or grown.end.y < plane_y:
					continue
				grown.position.y = -FAR_M
				grown.size.y = 2.0 * FAR_M
			var span: Vector2 = line_interval(origin, direction, grown)
			if span.x < t and t < span.y:
				t = span.y
				moved = true
		if not moved:
			break
	return t


static func _inside(box: AABB, point: Vector3) -> bool:
	return (
		point.x > box.position.x
		and point.x < box.end.x
		and point.y > box.position.y
		and point.y < box.end.y
		and point.z > box.position.z
		and point.z < box.end.z
	)
