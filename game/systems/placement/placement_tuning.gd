class_name PlacementTuning
extends RefCounted
## Every tuning number of placement in one place (#31). Tests read these constants and never
## repeat the values; playtesting may change them.

## Rotation step of a rotate key without a modifier, degrees.
const ROTATION_STEP_DEG: float = 15.0
## Rotation step with Shift held, degrees.
const FINE_STEP_DEG: float = 1.0
## A press that moves further than this (logical pixels at 1152 x 648) becomes a drag.
const DRAG_THRESHOLD_PX: float = 6.0
## Held rotate key: first repeat after this many seconds.
const REPEAT_DELAY_S: float = 0.4
## Held rotate key: seconds between repeats for the 15 degree step.
const REPEAT_INTERVAL_S: float = 0.25
## Held rotate key with Shift: seconds between repeats (20 degrees per second).
const FINE_REPEAT_INTERVAL_S: float = 0.05
## A drop within this distance (metres) of the start counts as the same spot.
const SAME_SPOT_M: float = 0.0001
## A rotation within this many degrees of the start counts as the same angle.
const SAME_ANGLE_DEG: float = 0.01
## The refusal cue (#33): the selection glow rises from its base to the peak and falls back once
## over this many seconds.
const REFUSAL_CUE_DURATION_S: float = 0.30
## The fresnel strength at the middle of the cue. Times the brightest glow channel it stays below
## the bloom threshold of the room environment.
const REFUSAL_CUE_PEAK_STRENGTH: float = 0.95
