class_name CameraFraming
extends RefCounted
## Pure camera framing maths (ADR 0005). The field of view is the horizontal angle at 16:9.

const REFERENCE_ASPECT: float = 16.0 / 9.0


## Distance from the pivot so that a box of exterior width W fills `width_share` of the screen
## width at the horizontal field of view; the front face is D / 2 closer than the pivot.
static func default_distance(
	exterior_width_m: float,
	exterior_depth_m: float,
	hfov_deg: float,
	elevation_deg: float,
	width_share: float
) -> float:
	return (
		exterior_width_m / (2.0 * width_share * tan(deg_to_rad(hfov_deg) / 2.0))
		+ exterior_depth_m / 2.0 * cos(deg_to_rad(elevation_deg))
	)


## The smallest distance from the pivot at which every point stays inside the vertical field of
## view of the reference aspect, with `margin` of the half screen height to spare (ADR 0006).
## `points` are relative to the pivot, the camera looks at the pivot from +Z and above. The height
## of a point on the screen does not depend on the distance, only its depth does, so the answer is
## closed form.
static func fit_distance(
	points: PackedVector3Array, hfov_deg: float, elevation_deg: float, margin: float
) -> float:
	var elevation: float = deg_to_rad(elevation_deg)
	var forward: Vector3 = Vector3(0.0, -sin(elevation), -cos(elevation))
	var up: Vector3 = Vector3(0.0, cos(elevation), -sin(elevation))
	var tan_vertical: float = tan(deg_to_rad(hfov_deg) / 2.0) / REFERENCE_ASPECT
	var wanted: float = 0.0
	for point: Vector3 in points:
		wanted = maxf(
			wanted, absf(point.dot(up)) / ((1.0 - margin) * tan_vertical) - point.dot(forward)
		)
	return wanted


## Camera position in front of and above the pivot (looking at it from +Z).
static func camera_position(pivot: Vector3, distance: float, elevation_deg: float) -> Vector3:
	var elevation: float = deg_to_rad(elevation_deg)
	return pivot + Vector3(0.0, sin(elevation), cos(elevation)) * distance


## Camera3D.KEEP_WIDTH up to `max_keep_width_aspect`, KEEP_HEIGHT above it.
static func keep_aspect_for(aspect: float, max_keep_width_aspect: float) -> Camera3D.KeepAspect:
	if aspect <= max_keep_width_aspect + 0.0001:
		return Camera3D.KEEP_WIDTH
	return Camera3D.KEEP_HEIGHT


## The Camera3D.fov to set: the horizontal angle with KEEP_WIDTH; with KEEP_HEIGHT the vertical
## angle that the horizontal angle has at `max_keep_width_aspect`.
static func fov_for(aspect: float, hfov_deg: float, max_keep_width_aspect: float) -> float:
	if keep_aspect_for(aspect, max_keep_width_aspect) == Camera3D.KEEP_WIDTH:
		return hfov_deg
	var half: float = tan(deg_to_rad(hfov_deg) / 2.0)
	return rad_to_deg(2.0 * atan(half / max_keep_width_aspect))
