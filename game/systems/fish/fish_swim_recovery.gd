class_name FishSwimRecovery
extends RefCounted
## The speed profile of the recovery ease (ADR 0015 rule 6), static and pure: a fish that is outside
## its limits moves on a straight segment of `length` metres with a smoothstep ramp up, a plateau
## and a smoothstep ramp down, each ramp `ramp` seconds long.


## [total time, plateau speed] for a segment: the plateau speed is at most `cap`, the time at least
## two ramps and at most `max_time`.
static func plan(length: float, cap: float, ramp: float, max_time: float) -> Vector2:
	var total: float = clampf(length / cap + ramp, 2.0 * ramp, max_time)
	return Vector2(total, length / (total - ramp))


## The distance covered `time` seconds after the start of a segment of `length` metres.
static func distance(length: float, total: float, speed: float, ramp: float, time: float) -> float:
	if time >= total:
		return length
	if time < ramp:
		var u: float = time / ramp
		return speed * ramp * (u * u * u - u * u * u * u * 0.5)
	var left: float = total - time
	if left < ramp:
		var w: float = left / ramp
		return length - speed * ramp * (w * w * w - w * w * w * w * 0.5)
	return speed * ramp * 0.5 + speed * (time - ramp)
