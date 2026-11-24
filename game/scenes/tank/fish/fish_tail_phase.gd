class_name FishTailPhase
extends RefCounted
## The tail phase of one fish, advanced on the CPU (ADR 0013 Amendment 1, ADR 0015 rule 9). The
## vertex shader bends the tail with sin(swim_phase - k * s); this class advances swim_phase every
## frame by TAU * swim_frequency * mix(REST_FREQUENCY, 1, clamp(swim_speed * swim_speed_scale, 0,
## 1)) * delta. So the phase never jumps when the speed changes, a frame never advances it by more
## than the full-speed beat and a fish that is not advanced keeps its tail pose. At a constant speed
## the phase is phase0 + TAU * f * t, which is the #34 look. Static and pure.

## Pinned to SWIM_REST_FREQUENCY of game/shaders/fish_common.gdshaderinc (a test checks it).
const REST_FREQUENCY: float = 0.4
## Pinned to the uniform defaults of game/shaders/fish.gdshader (a test checks them).
const DEFAULT_FREQUENCY: float = 1.5
const DEFAULT_SPEED_SCALE: float = 1.0


## The phase after `delta` seconds, wrapped into [0, TAU).
static func advance(
	phase: float, swim_speed: float, frequency: float, speed_scale: float, delta: float
) -> float:
	var mix_amount: float = clampf(swim_speed * speed_scale, 0.0, 1.0)
	var rate: float = frequency * lerpf(REST_FREQUENCY, 1.0, mix_amount)
	return fposmod(phase + TAU * rate * delta, TAU)
