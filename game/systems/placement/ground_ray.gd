class_name GroundRay
extends RefCounted
## The pointer ray against the horizontal plane of the nominal substrate surface (#31, ADR 0012
## rule 3), static and pure, in tank-local space. A ray that is parallel to the plane, starts below
## it, points away from it or is not finite finds no point.

const PARALLEL_EPSILON: float = 1e-9


## {ok: bool, point: Vector3}; `point` is set only when ok is true.
static func intersect(origin: Vector3, direction: Vector3, plane_y: float) -> Dictionary:
	var miss: Dictionary = {"ok": false}
	if not (_finite(origin) and _finite(direction) and is_finite(plane_y)):
		return miss
	if direction.y > -PARALLEL_EPSILON:
		return miss
	if origin.y < plane_y:
		return miss
	var distance: float = (plane_y - origin.y) / direction.y
	var point: Vector3 = origin + direction * distance
	point.y = plane_y
	if not _finite(point):
		return miss
	return {"ok": true, "point": point}


static func _finite(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
