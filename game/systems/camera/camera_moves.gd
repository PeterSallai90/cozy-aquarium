class_name CameraMoves
extends RefCounted
## Pure zoom, pan and Home maths of the build camera (#26). No nodes, no state.


## step_factor to the power of the event factor; a factor of 0 or less counts as 1. Zoom out
## passes 1 / step_factor.
static func zoom_multiplier(step_factor: float, event_factor: float) -> float:
	var power: float = event_factor if event_factor > 0.0 else 1.0
	return pow(step_factor, power)


## The distance kept between min_factor and max_factor times the default distance.
static func clamp_distance(
	distance_m: float, default_m: float, min_factor: float, max_factor: float
) -> float:
	return clampf(distance_m, default_m * min_factor, default_m * max_factor)


## tan of the vertical half field of view; fov_deg is the one kept by keep_aspect.
static func tan_half_vertical_fov(
	fov_deg: float, keep_aspect: Camera3D.KeepAspect, aspect: float
) -> float:
	var half: float = tan(deg_to_rad(fov_deg) / 2.0)
	if keep_aspect == Camera3D.KEEP_WIDTH and aspect > 0.0:
		return half / aspect
	return half


## The pivot movement of a pan drag: the world follows the cursor, so the pivot moves along minus
## camera right for a drag to the right and along plus camera up for a drag down.
static func pan_offset(
	relative_px: Vector2,
	viewport_height_px: float,
	distance_m: float,
	tan_half_vfov: float,
	pan_speed: float,
	azimuth_deg: float,
	elevation_deg: float
) -> Vector3:
	if viewport_height_px <= 0.0:
		return Vector3.ZERO
	var scale: float = 2.0 * distance_m * tan_half_vfov * pan_speed / viewport_height_px
	var axes: Basis = Basis.from_euler(
		OrbitMath.camera_rotation(azimuth_deg, elevation_deg), EULER_ORDER_YXZ
	)
	return (-axes.x * relative_px.x + axes.y * relative_px.y) * scale


## Each axis on its own, so the pivot slides along an edge.
static func clamp_pivot(pivot: Vector3, box: AABB) -> Vector3:
	return pivot.clamp(box.position, box.end)


## The nearest multiple of 360 degrees; an exact tie goes to the higher one.
static func home_azimuth_deg(target_azimuth_deg: float) -> float:
	return 360.0 * floorf(target_azimuth_deg / 360.0 + 0.5)
