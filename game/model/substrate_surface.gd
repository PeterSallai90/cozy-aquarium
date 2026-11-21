class_name SubstrateSurface
extends RefCounted
## The one source of the nominal substrate surface height (ADR 0011 rule 4). Static and pure: it
## reads catalog definitions only, needs no Node and keeps no state.
##
## Item heights are measured from this surface (H1): an item's position.y is its height above the
## surface at its (x, z), 0 means resting on the substrate. Placement, fish, photo mode and the bed
## ask here and never assume that y = 0 is the visible floor.
##
## In #28 the bed is flat at the fill depth of the type: the heightmap is ignored on purpose,
## exactly like the drawn bed (#29 honours it and flips the pinned test). The value is the nominal
## (mean) surface of the drawn bed; single stones may lie a little above or below it.

## No bed is shallower than this (metres).
const MIN_DEPTH_M: float = 0.03
const ERR_NO_DEFINITION: String = "SubstrateSurface: no substrate definition"
## Reach of single grains above the nominal surface by grain shape, metres (ADR 0011 rule 5).
const TOP_ALLOWANCE_SAND_M: float = 0.0015
const TOP_ALLOWANCE_ANGULAR_M: float = 0.003
const TOP_ALLOWANCE_ROUND_M: float = 0.00325
const TOP_ALLOWANCE_PEBBLE_M: float = 0.016


## The depth of a flat bed of the type in metres, never below MIN_DEPTH_M. A null definition logs
## one error and gives MIN_DEPTH_M.
static func flat_depth(definition: SubstrateDefinition) -> float:
	if definition == null:
		push_error(ERR_NO_DEFINITION)
		return MIN_DEPTH_M
	var depth: float = definition.fill_depth_m
	if is_nan(depth) or depth < MIN_DEPTH_M:
		return MIN_DEPTH_M
	return depth


## The surface height in metres above the tank floor (y = 0) at tank-local (x, z). The heightmap
## (absolute metres above the tank floor, `heightmap_size` columns x rows, empty = flat at the fill
## depth), the interior size and the point are the stable contract for #29, which samples the
## heightmap at (x, z) clamped to the interior. In #28 the bed is flat: the result is the flat depth
## of the type for every input, so x and z outside the interior, NaN and infinity never reach it
## and never raise an error.
static func height_at(
	definition: SubstrateDefinition,
	_heightmap: PackedFloat32Array,
	_heightmap_size: Vector2i,
	_interior_size_m: Vector3,
	_x: float,
	_z: float
) -> float:
	return flat_depth(definition)


## How far single grains or stones of the type reach above the nominal surface in metres (ADR 0011
## rule 5, by grain shape). Fish use it so a bottom fish rests on the stone tops, not in them. A
## null definition gives the sand value without logging; height_at is not affected.
static func top_allowance(definition: SubstrateDefinition) -> float:
	if definition == null:
		return TOP_ALLOWANCE_SAND_M
	match definition.grain_shape:
		SubstrateDefinition.GrainShape.ANGULAR:
			return TOP_ALLOWANCE_ANGULAR_M
		SubstrateDefinition.GrainShape.ROUND:
			return TOP_ALLOWANCE_ROUND_M
		SubstrateDefinition.GrainShape.PEBBLE:
			return TOP_ALLOWANCE_PEBBLE_M
	return TOP_ALLOWANCE_SAND_M


## The tank-local height an item stands at: the surface at its (x, z) plus its position.y (H1).
static func absolute_y(
	definition: SubstrateDefinition,
	heightmap: PackedFloat32Array,
	heightmap_size: Vector2i,
	interior_size_m: Vector3,
	position: Vector3
) -> float:
	return (
		height_at(definition, heightmap, heightmap_size, interior_size_m, position.x, position.z)
		+ position.y
	)
