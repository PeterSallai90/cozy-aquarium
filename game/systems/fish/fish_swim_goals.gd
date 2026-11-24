class_name FishSwimGoals
extends RefCounted
## Where a fish wants to go (ADR 0015 rules 4 and 5): wander goals in the band of the tank and the
## clamped goal of an override target. Pure, no Node; split out of FishSwimSim to keep it short.
## All randomness comes from the injected RandomNumberGenerator of the simulation.

var _tuning: FishSwimTuning = null
var _rng: RandomNumberGenerator = null
var _scratch: FishSwimLimits.Vertical = FishSwimLimits.Vertical.new()


func _init(tuning: FishSwimTuning, rng: RandomNumberGenerator) -> void:
	_tuning = tuning
	_rng = rng


## A random point of the band, the farthest of three tries from the fish unless one is far enough.
func random(f: FishSwimMember, soft: Vector2, world: FishSwimWorld) -> Vector3:
	var p: FishSwimParams = f.params
	var best: Vector3 = f.position
	var best_gap: float = -1.0
	var wanted_gap: float = 3.0 * p.body_length_m
	var span_x: float = maxf(soft.x - p.avoid_m, 0.0)
	var span_z: float = maxf(soft.y - p.avoid_m, 0.0)
	for _attempt: int in 3:
		var x: float = _rng.randf_range(-span_x, span_x)
		var z: float = _rng.randf_range(-span_z, span_z)
		var candidate: Vector3 = inside(f, x, z, soft, 0.0, true, world)
		var gap: float = Vector2(candidate.x - f.position.x, candidate.z - f.position.z).length()
		if gap > best_gap:
			best = candidate
			best_gap = gap
		if gap >= wanted_gap:
			break
	return best


## A goal at (x, z) kept inside the soft box with a height in the band: the preferred height with
## a random variation, or `height` when `vary` is false.
func inside(
	f: FishSwimMember,
	x: float,
	z: float,
	soft: Vector2,
	height: float,
	vary: bool,
	world: FishSwimWorld
) -> Vector3:
	var p: FishSwimParams = f.params
	var gx: float = clampf(x, -soft.x, soft.x)
	var gz: float = clampf(z, -soft.y, soft.y)
	FishSwimLimits.vertical(world, p, gx, gz, _scratch)
	var low: float = _scratch.min_y
	var high: float = _scratch.max_y
	if high - low > 2.0 * _tuning.band_inset_m:
		low += _tuning.band_inset_m
		high -= _tuning.band_inset_m
	var y: float = height
	if vary:
		var band: float = _scratch.max_y - _scratch.min_y
		y = (
			_scratch.preferred(p.depth_fraction)
			+ band * _tuning.wander_height_jitter * _rng.randf_range(-1.0, 1.0)
		)
	return Vector3(gx, clampf(y, low, high), gz)


## The override target of a fish, clamped to the nearest valid point of the tank.
func refresh_override(f: FishSwimMember, world: FishSwimWorld) -> void:
	if not f.has_override or world == null:
		return
	var p: FishSwimParams = f.params
	var soft: Vector2 = f.soft
	var x: float = clampf(f.override_raw.x, -soft.x, soft.x)
	var z: float = clampf(f.override_raw.z, -soft.y, soft.y)
	FishSwimLimits.vertical(world, p, x, z, _scratch)
	var low: float = _scratch.hard_low
	var high: float = _scratch.hard_high
	if high - low > 2.0 * _tuning.band_inset_m:
		low += _tuning.band_inset_m
		high -= _tuning.band_inset_m
	f.override_goal = Vector3(x, clampf(f.override_raw.y, low, high), z)
