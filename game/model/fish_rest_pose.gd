class_name FishRestPose
extends RefCounted
## Where a fish rests (ADR 0013 rule 6): a pure function of the uid, the zone, the fish extents,
## the tank interior, the water line and the substrate surface. Never stored; the same input gives
## the same pose, and removing a fish moves no other fish. #34 only places the fish and bends its
## tail; all movement is #35.

## Distance kept to the glass on every side, on top of the horizontal radius of the fish.
const GLASS_MARGIN_M: float = 0.01


## The result of compute(): tank-local position, yaw about +Y, and whether the column was too small.
class Pose:
	extends RefCounted
	var position: Vector3 = Vector3.ZERO
	var yaw: float = 0.0
	var pinned: bool = false


static func compute(
	uid: String,
	zone: FishSpecies.Zone,
	extents: FishExtents,
	interior_size_m: Vector3,
	water_line_m: float,
	surface_at: Callable,
	grain_allowance_m: float
) -> Pose:
	var pose: Pose = Pose.new()
	var x: float = _axis(interior_size_m.x, extents, FishHash.unit(uid, FishHash.SALT_REST_X))
	var z: float = _axis(interior_size_m.z, extents, FishHash.unit(uid, FishHash.SALT_REST_Z))
	var span: FishZones.OriginRange = FishZones.origin_range(
		zone, surface_at, x, z, water_line_m, grain_allowance_m, extents
	)
	var y: float = span.min_y
	if zone != FishSpecies.Zone.BOTTOM:
		y += FishHash.unit(uid, FishHash.SALT_REST_Y) * (span.max_y - span.min_y)
	pose.position = Vector3(x, y, z)
	pose.yaw = TAU * FishHash.unit(uid, FishHash.SALT_REST_YAW)
	pose.pinned = span.pinned
	return pose


## One horizontal coordinate: inside the interior shrunk by the radius and the glass margin on
## both sides, 0 when that range is empty.
static func _axis(size_m: float, extents: FishExtents, unit: float) -> float:
	var margin: float = extents.horizontal_radius_m + GLASS_MARGIN_M
	var low: float = -size_m / 2.0 + margin
	var high: float = size_m / 2.0 - margin
	if low > high:
		return 0.0
	return lerpf(low, high, unit)
