class_name OrbitMath
extends RefCounted
## Pure orbit camera maths (ADR 0008). Azimuth 0 is the front (+Z), 90 is right (+X), 270 is left
## (-X); azimuth grows counter-clockwise seen from above. Elevation is positive above the pivot.

## Half a percent of the gap is left after the damping time: 99 percent is closed.
const DAMPING_CLOSED_SHARE_INVERSE: float = 100.0


## The lowest elevation that keeps the camera at or above the cabinet top: the story limit, or
## the angle at which the camera height over the cabinet reaches zero, whichever is higher.
static func min_elevation_deg(
	limit_deg: float, pivot_above_cabinet_m: float, distance_m: float
) -> float:
	if distance_m <= 0.0:
		return limit_deg
	var ratio: float = clampf(pivot_above_cabinet_m / distance_m, -1.0, 1.0)
	return maxf(limit_deg, -rad_to_deg(asin(ratio)))


## Camera position relative to the pivot.
static func offset(azimuth_deg: float, elevation_deg: float, distance_m: float) -> Vector3:
	var az: float = deg_to_rad(azimuth_deg)
	var el: float = deg_to_rad(elevation_deg)
	return Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el)) * distance_m


## Euler angles (YXZ) of a camera that looks at the pivot; built from the angles, never from
## look_at, so the basis cannot degenerate.
static func camera_rotation(azimuth_deg: float, elevation_deg: float) -> Vector3:
	return Vector3(-deg_to_rad(elevation_deg), deg_to_rad(azimuth_deg), 0.0)


## Share of the remaining gap to close in one frame; 0 or less damping time is instant.
static func damp_factor(delta_s: float, damping_time_s: float) -> float:
	if damping_time_s <= 0.0:
		return 1.0
	return 1.0 - exp(-log(DAMPING_CLOSED_SHARE_INVERSE) * delta_s / damping_time_s)


## Degrees for a pointer movement; a full viewport height is `deg_per_viewport_height`.
static func drag_deg(
	pixels: float, viewport_height_px: float, deg_per_viewport_height: float
) -> float:
	if viewport_height_px <= 0.0:
		return 0.0
	return pixels / viewport_height_px * deg_per_viewport_height
