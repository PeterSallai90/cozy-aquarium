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


static func origin_range(
	zone: FishSpecies.Zone,
	surface_at: Callable,
	x: float,
	z: float,
	water_line_m: float,
	grain_allowance_m: float,
	extents: FishExtents
) -> OriginRange:
	var surface: float = surface_at.call(x, z)
	var column: float = water_line_m - TOP_MARGIN_M - surface
	var is_bottom: bool = zone == FishSpecies.Zone.BOTTOM
	var low: float = surface + extents.below_m
	if is_bottom:
		low = surface + maxf(BOTTOM_CLEARANCE_MIN_M, extents.below_m) + grain_allowance_m
	var high: float = water_line_m - extents.above_m
	var result: OriginRange = OriginRange.new()
	if low > high:
		result.min_y = (low + high) / 2.0
		result.max_y = result.min_y
		result.pinned = true
		return result
	var band_low: float = surface + BOTTOM_BAND_TOP * column
	var band_high: float = surface + MIDDLE_BAND_TOP * column
	if is_bottom:
		band_low = low
		band_high = surface + BOTTOM_BAND_TOP * column
	elif zone == FishSpecies.Zone.TOP:
		band_low = surface + MIDDLE_BAND_TOP * column
		band_high = surface + column
	result.min_y = clampf(band_low, low, high)
	result.max_y = clampf(band_high, low, high)
	return result


## A surface Callable (x, z) -> metres for SubstrateSurface.height_at with the given bed.
static func surface_source(
	definition: SubstrateDefinition,
	heightmap: PackedFloat32Array,
	heightmap_size: Vector2i,
	interior_size_m: Vector3
) -> Callable:
	return func(x: float, z: float) -> float:
		return SubstrateSurface.height_at(
			definition, heightmap, heightmap_size, interior_size_m, x, z
		)
