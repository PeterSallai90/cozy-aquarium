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
## The refusal cue (#33, ADR 0012 Amendment 2 rule 16): one pulse over this many seconds.
const REFUSAL_CUE_DURATION_S: float = 0.30
## The fresnel strength at the middle of the pulse (base 0.7 in the selection material).
const REFUSAL_CUE_PEAK_STRENGTH: float = 0.90
## The fresnel power at the middle of the pulse (base 1.6): a lower power widens the rim.
const REFUSAL_CUE_PEAK_FRESNEL_POWER: float = 0.5
## The colour of the pulse at its colour peak (soft coral, sRGB).
const REFUSAL_CUE_COLOUR: Color = Color(1.0, 0.45, 0.40)
## The colour phase: a half sine between these times.
const REFUSAL_CUE_COLOUR_START_S: float = 0.10
const REFUSAL_CUE_COLOUR_END_S: float = 0.30
## The brightness term (glow_lift, linear light; no red channel) at the lift peak.
const REFUSAL_CUE_LIFT: Vector3 = Vector3(0.0, 0.30, 0.27)
## The lift phase: a half sine between these times.
const REFUSAL_CUE_LIFT_START_S: float = 0.0
const REFUSAL_CUE_LIFT_END_S: float = 0.20
## The dot(NORMAL, VIEW) used for rim measurements.
const REFUSAL_CUE_REFERENCE_FACING: float = 0.5
## The assumed brightest lit item channel (linear) of the item-aware bloom check.
const REFUSAL_CUE_GUARD_LIT_EDGE: float = 0.8
## Visibility minimums of the cue (AC 15 d).
const REFUSAL_CUE_MIN_COLOUR_DISTANCE: float = 0.35
const REFUSAL_CUE_MIN_HUE_DISTANCE_DEG: float = 25.0
const REFUSAL_CUE_MIN_PEAK_FACTOR: float = 2.0
const REFUSAL_CUE_MIN_EDGE_LUMINANCE_CHANGE: float = 0.15
const REFUSAL_CUE_MIN_EDGE_COLOUR_DISTANCE: float = 0.20
