class_name FishSwimLimits
extends RefCounted
## Where a fish may be (ADR 0015 rule 4), static and pure. Horizontally the hard limit is the glass
## minus the horizontal radius of the fish. Vertically it is FishZones: the hard limits (bed plus
## extent and clearance, water line minus extent) and the species band at (x, z), with the depth
## preference applied. #168 adds item obstacles here.


## The vertical limits at one (x, z); filled by vertical() so the simulation can reuse one object.
## min_y and max_y are the zone band, hard_low and hard_high the hard limits (all the pinned height
## when the column is too small for the fish).
class Vertical:
	extends FishZones.OriginRange

	## The preferred height: band centre plus the fraction of the band height, kept in the band.
	func preferred(fraction: float) -> float:
		return clampf(min_y + (max_y - min_y) * (0.5 + fraction), min_y, max_y)


## The largest |x| (or |z|) of the origin inside a glass span of `size_m`.
static func half_extent(size_m: float, radius_m: float) -> float:
	return maxf(size_m / 2.0 - radius_m, 0.0)


static func vertical(
	world: FishSwimWorld, params: FishSwimParams, x: float, z: float, out: Vertical
) -> void:
	FishZones.fill_range(
		out,
		params.zone,
		world.surface_at.call(x, z),
		world.water_line_m,
		world.grain_allowance_m,
		params.extents
	)


## True when the origin is outside the hard limits, or more than `margin_m` (plus `tolerance_m`)
## outside the band.
static func is_outside(
	world: FishSwimWorld,
	params: FishSwimParams,
	at: Vector3,
	margin_m: float,
	tolerance_m: float,
	scratch: Vertical
) -> bool:
	var radius: float = params.extents.horizontal_radius_m
	var half_x: float = half_extent(world.interior_size_m.x, radius)
	var half_z: float = half_extent(world.interior_size_m.z, radius)
	if absf(at.x) > half_x + tolerance_m or absf(at.z) > half_z + tolerance_m:
		return true
	vertical(world, params, at.x, at.z, scratch)
	if at.y < scratch.hard_low - tolerance_m or at.y > scratch.hard_high + tolerance_m:
		return true
	return (
		at.y < scratch.min_y - margin_m - tolerance_m
		or at.y > scratch.max_y + margin_m + tolerance_m
	)


## The nearest point that is valid for a fish: x and z clamped to the glass limits shrunk by
## `wall_margin_m`, the height moved into the band (shrunk by `inset_m`) at that (x, z).
static func nearest_valid(
	world: FishSwimWorld,
	params: FishSwimParams,
	at: Vector3,
	wall_margin_m: float,
	inset_m: float,
	scratch: Vertical
) -> Vector3:
	var radius: float = params.extents.horizontal_radius_m
	var half_x: float = maxf(half_extent(world.interior_size_m.x, radius) - wall_margin_m, 0.0)
	var half_z: float = maxf(half_extent(world.interior_size_m.z, radius) - wall_margin_m, 0.0)
	var x: float = clampf(at.x, -half_x, half_x)
	var z: float = clampf(at.z, -half_z, half_z)
	vertical(world, params, x, z, scratch)
	var low: float = scratch.min_y
	var high: float = scratch.max_y
	if high - low > 2.0 * inset_m:
		low += inset_m
		high -= inset_m
	return Vector3(x, clampf(at.y, low, high), z)
