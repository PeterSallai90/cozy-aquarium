class_name RefusalCue
extends RefCounted
## The timer and curves of the refusal pulse (#33 AC 13, 15, ADR 0012 Amendment 2 rule 16): the rim
## strength and power follow one half sine over REFUSAL_CUE_DURATION_S, the brightness lift
## (glow_lift) comes first and the coral colour second. Pure, driven by frame times. A new start()
## restarts it, so cues never stack; there is one state.

## Ends a little early so that a sum of frame steps that falls a rounding error short still ends.
const END_SLACK_S: float = 0.000001

var _active: bool = false
var _elapsed_s: float = 0.0
var _start_count: int = 0


func start() -> void:
	_active = true
	_elapsed_s = 0.0
	_start_count += 1


func cancel() -> void:
	_active = false
	_elapsed_s = 0.0


## Advances the cue; a delta of zero or less is ignored, and the cue ends at the duration.
func step(delta_s: float) -> void:
	if not _active or delta_s <= 0.0:
		return
	_elapsed_s += delta_s
	if _elapsed_s >= PlacementTuning.REFUSAL_CUE_DURATION_S - END_SLACK_S:
		_active = false
		_elapsed_s = 0.0


func is_active() -> bool:
	return _active


func get_elapsed_s() -> float:
	return _elapsed_s


## How many times start() was called.
func get_start_count() -> int:
	return _start_count


## The rim weight now (0 when the cue is not running).
func get_weight() -> float:
	return weight_at(_elapsed_s) if _active else 0.0


## The glow strength now: `base` when the cue is not running.
func get_strength(base: float) -> float:
	return strength_at(_elapsed_s, base) if _active else base


## sin(PI * (t - a) / (b - a)) for a <= t < b, otherwise 0.
static func half_sine(t_s: float, from_s: float, to_s: float) -> float:
	if t_s < from_s or t_s >= to_s:
		return 0.0
	return sin(PI * (t_s - from_s) / (to_s - from_s))


## The rim envelope over the whole pulse.
static func weight_at(t_s: float) -> float:
	return half_sine(t_s, 0.0, PlacementTuning.REFUSAL_CUE_DURATION_S)


## The curve: base + (peak - base) * w for 0 <= t < duration, else base.
static func strength_at(t_s: float, base: float) -> float:
	return base + (PlacementTuning.REFUSAL_CUE_PEAK_STRENGTH - base) * weight_at(t_s)


static func power_at(t_s: float, base: float) -> float:
	return base + (PlacementTuning.REFUSAL_CUE_PEAK_FRESNEL_POWER - base) * weight_at(t_s)


## glow_colour (sRGB values): the base towards the cue colour in the colour phase.
static func colour_at(t_s: float, base: Color) -> Color:
	var wc: float = half_sine(
		t_s, PlacementTuning.REFUSAL_CUE_COLOUR_START_S, PlacementTuning.REFUSAL_CUE_COLOUR_END_S
	)
	return base.lerp(PlacementTuning.REFUSAL_CUE_COLOUR, wc)


## glow_lift (linear light): the brightness term in the lift phase.
static func lift_at(t_s: float) -> Vector3:
	var wl: float = half_sine(
		t_s, PlacementTuning.REFUSAL_CUE_LIFT_START_S, PlacementTuning.REFUSAL_CUE_LIFT_END_S
	)
	return PlacementTuning.REFUSAL_CUE_LIFT * wl
