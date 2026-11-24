class_name FishZones
extends RefCounted
## The vertical range of a fish origin at a tank-local (x, z) (ADR 0013 rule 7). Static and pure:
## no Node, no cache. The surface comes in as a Callable (x, z) -> metres that is called on every
## query, so an uneven bed (#29) plugs in without changing the fish code; #35 reuses this helper.
##
## All heights are metres above the tank floor. S = surface(x, z), W = water line.
## The water column is H = W - TOP_MARGIN_M - S, split into BOTTOM 0 to BOTTOM_BAND_TOP, MIDDLE
## up to MIDDLE_BAND_TOP and TOP above (UNSET reads as MIDDLE). The origin never goes below
## S + extent_below, nor above W - extent_above; a BOTTOM fish keeps at least BOTTOM_CLEARANCE_MIN_M
## from the surface plus the grain allowance, and rests at the lower limit. A column too small for
## the fish pins the origin to the middle of the feasible span and says so.

const TOP_MARGIN_M: float = 0.03
const BOTTOM_CLEARANCE_MIN_M: float = 0.01
const BOTTOM_BAND_TOP: float = 0.25
const MIDDLE_BAND_TOP: float = 0.75


## The result of origin_range().
class OriginRange:
	extends RefCounted
	var min_y: float = 0.0
	var max_y: float = 0.0
	## True when the column is too small for the fish and the origin is pinned to the middle.
	var pinned: bool = false
	## The lowest and highest origin height of the fish over this surface (hard_limits()); both are
	## the pinned height when the fish is pinned.
	var hard_low: float = 0.0
	var hard_high: float = 0.0


static func origin_range(
	zone: FishSpecies.Zone,
	surface_at: Callable,
	x: float,
	z: float,
	water_line_m: float,
	grain_allowance_m: float,
	extents: FishExtents
) -> OriginRange:
	var result: OriginRange = OriginRange.new()
	fill_range(result, zone, surface_at.call(x, z), water_line_m, grain_allowance_m, extents)
	return result


## origin_range() for a bed of height `surface`, written into `out` (so a caller that asks every
## frame can reuse one object).
static func fill_range(
	out: OriginRange,
	zone: FishSpecies.Zone,
	surface: float,
	water_line_m: float,
	grain_allowance_m: float,
	extents: FishExtents
) -> void:
	var column: float = water_line_m - TOP_MARGIN_M - surface
	var is_bottom: bool = zone == FishSpecies.Zone.BOTTOM
	var limits: Vector2 = hard_limits(zone, surface, water_line_m, grain_allowance_m, extents)
	var low: float = limits.x
	var high: float = limits.y
	if low > high:
		out.min_y = (low + high) / 2.0
		out.max_y = out.min_y
		out.pinned = true
		out.hard_low = out.min_y
		out.hard_high = out.min_y
		return
	var band_low: float = surface + BOTTOM_BAND_TOP * column
	var band_high: float = surface + MIDDLE_BAND_TOP * column
	if is_bottom:
		band_low = low
		band_high = surface + BOTTOM_BAND_TOP * column
	elif zone == FishSpecies.Zone.TOP:
		band_low = surface + MIDDLE_BAND_TOP * column
		band_high = surface + column
	out.min_y = clampf(band_low, low, high)
	out.max_y = clampf(band_high, low, high)
	out.pinned = false
	out.hard_low = low
	out.hard_high = high


## The hard vertical limits of a fish origin over a surface of height `surface`: x is the lowest
## and y the highest origin height (x > y when the column is too small for the fish). Below that no
## fish goes and above that none either; the zone band lies inside them (#35 steering clamps to it).
static func hard_limits(
	zone: FishSpecies.Zone,
	surface: float,
	water_line_m: float,
	grain_allowance_m: float,
	extents: FishExtents
) -> Vector2:
	var low: float = surface + extents.below_m
	if zone == FishSpecies.Zone.BOTTOM:
		low = surface + maxf(BOTTOM_CLEARANCE_MIN_M, extents.below_m) + grain_allowance_m
	return Vector2(low, water_line_m - extents.above_m)


## A surface Callable (x, z) -> metres for SubstrateSurface.height_at with the given bed. A plain
## static method with bound arguments, not a lambda, so a Callable that outlives its caller (a test
## cache, a world kept by a simulation) holds no script lambda state.
static func surface_source(
	definition: SubstrateDefinition,
	heightmap: PackedFloat32Array,
	heightmap_size: Vector2i,
	interior_size_m: Vector3
) -> Callable:
	return _bed_height.bind(definition, heightmap, heightmap_size, interior_size_m)


static func _bed_height(
	x: float,
	z: float,
	definition: SubstrateDefinition,
	heightmap: PackedFloat32Array,
	heightmap_size: Vector2i,
	interior_size_m: Vector3
) -> float:
	return SubstrateSurface.height_at(definition, heightmap, heightmap_size, interior_size_m, x, z)
