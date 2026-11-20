class_name RotationStep
extends RefCounted
## The rotation rule of placement (#31 AC 12), static and pure. +1 is the left key (Comma), a
## counter-clockwise turn seen from above and a positive change of rotation_y; -1 is the right key
## (Period), clockwise and negative. This is the only place where the sign lives.
## Without Shift the angle turns by exactly one step (15 degrees) from any start angle; with Shift
## (fine) it turns by exactly the fine step. Results are in [0, 360).

const FULL_TURN_DEG: float = 360.0


## The angle in [0, 360); 360 becomes 0 and a value that is not finite gives 0.0.
static func normalise(deg: float) -> float:
	if not is_finite(deg):
		return 0.0
	var result: float = fposmod(deg, FULL_TURN_DEG)
	if result >= FULL_TURN_DEG:
		return 0.0
	return result


## The angle after one step in `direction` (+1 left, -1 right), normalised.
static func step(deg: float, direction: int, fine: bool) -> float:
	var angle: float = normalise(deg)
	var sign_value: float = 1.0 if direction >= 0 else -1.0
	var amount: float = PlacementTuning.FINE_STEP_DEG if fine else PlacementTuning.ROTATION_STEP_DEG
	return normalise(angle + sign_value * amount)
