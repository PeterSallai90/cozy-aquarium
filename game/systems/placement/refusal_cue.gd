class_name RefusalCue
extends RefCounted
## The timer and curve of the refusal glow (#33 AC 15, ADR 0012 Amendment 2): one half sine of the
## selection glow strength from its base up to REFUSAL_CUE_PEAK_STRENGTH and back over
## REFUSAL_CUE_DURATION_S. Pure, driven by frame times. A new start() restarts it, so cues never
## stack; there is one state.

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


## The glow strength now: `base` when the cue is not running.
func get_strength(base: float) -> float:
	if not _active:
		return base
	return strength_at(_elapsed_s, base)


## The curve: base + (peak - base) * sin(PI * t / duration) for 0 <= t < duration, else base.
static func strength_at(t_s: float, base: float) -> float:
	var duration: float = PlacementTuning.REFUSAL_CUE_DURATION_S
	if t_s < 0.0 or t_s >= duration:
		return base
	return base + (PlacementTuning.REFUSAL_CUE_PEAK_STRENGTH - base) * sin(PI * t_s / duration)
