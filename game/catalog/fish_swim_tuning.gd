class_name FishSwimTuning
extends Resource
## Every global tuning value of the fish steering model (ADR 0015 rule 3, BA decisions Q3 and Q19):
## catalog data and an input of FishSwimSim, never a literal in the steering code. Per-species
## numbers (idle share, dart interval and duration, turn rate, pitch limit, nose-down bias) are
## FishSpecies fields. Lives in catalog/behaviour because FishCatalog.load_dir reads every .tres in
## catalog/fish. All values are (tuning) the owner may judge at review; only k, the ramps, the
## recovery numbers, the stuck rule numbers and the step limits are fixed by BA decisions.

const DEFAULT_PATH: String = "res://catalog/behaviour/fish_swim_tuning.tres"

# --- speeds ---
## Species top speed in body lengths per second = swim_speed x k.
@export var top_speed_factor_k: float = 3.0
## Cruise speed as a fraction of the top speed (times the speed factor of the personality).
@export var cruise_speed_fraction: float = 0.0
## Dart speed as a fraction of the top speed (times the boldness, capped at 1).
@export var dart_speed_fraction: float = 0.0
## Two darts of one fish are never closer than this many seconds.
@export var min_dart_gap_s: float = 5.0
## Standstill to top speed takes this long (the test cap is 0.3 s) and so does braking.
@export var accel_ramp_s: float = 0.4
## The yaw rate changes from 0 to the turn rate cap in this time (the test cap is 0.25 s).
@export var yaw_ramp_s: float = 0.3
## Yaw rate below this fraction of the turn cap is not counted as a turn (the flip rule's level).
@export var yaw_deadband_fraction: float = 0.05
## A turn does not reverse before this many seconds after the last reversal (at most 2 heading-rate
## sign flips per second; the test window is 1 s, so this must stay above 0.5).
@export var min_flip_gap_s: float = 0.6
## Time constant in seconds with which the heading follows the wanted direction.
@export var yaw_response_s: float = 0.35
## Time constant in seconds with which the wanted direction follows the sum of the forces, so a
## force that flickers does not make the fish waggle (heading-rate sign flips).
@export var steer_smooth_s: float = 0.3
## The same for the pitch, and the pitch rate as a fraction of the turn rate cap.
@export var pitch_response_s: float = 0.6
@export var pitch_rate_fraction: float = 0.5
## Time in seconds in which the nose-down bias eases in or out.
@export var bias_ease_s: float = 0.4
## The speed fades with the heading error between these two angles (degrees): full speed below
## the first, standstill above the second, so a fish turns on the spot instead of orbiting.
@export var turn_slow_from_deg: float = 60.0
@export var turn_slow_to_deg: float = 150.0
## The speed never fades below this share of its value while turning, so a fish swims a curve
## instead of turning on the spot.
@export var turn_slow_floor: float = 0.75
## Arrival: the wanted speed near a target is this many 1/s times the distance.
@export var arrive_gain_per_s: float = 1.5
## A fish brakes so that it stops at this share of the free distance ahead (glass, school-mates).
@export var brake_safety: float = 0.92
## A fish held back (slower than the stuck speed while it intends to move) for give_way_after_s
## creeps on, the share of its cruise speed growing to give_way_fraction over give_way_ramp_s, even
## with a fish ahead, so a ring of fish that block each other dissolves.
@export var give_way_after_s: float = 1.0
@export var give_way_ramp_s: float = 1.5
@export var give_way_fraction: float = 0.5
## A fish stops this many times the sum of the half lengths before a fish ahead, so it never stops
## on the personal-space limit itself.
@export var clear_stop_factor: float = 1.1

# --- idle and darts ---
@export var idle_episode_min_s: float = 2.0
@export var idle_episode_max_s: float = 6.0
## Hover drift speed as a fraction of the top speed.
@export var idle_drift_fraction: float = 0.03
## Seconds before a dart that found no room tries again.
@export var dart_retry_s: float = 0.25
## Directions tried for a dart, as angle steps from the heading in degrees (both sides).
@export var dart_angle_step_deg: float = 40.0
@export var dart_angle_steps: int = 2

# --- wandering ---
## A wander target counts as reached within max(this many body lengths, this many turn radii).
@export var target_reach_bl: float = 0.6
@export var target_reach_turns: float = 1.0
## Height variation of a wander target in the band, as a fraction of the band height.
@export var wander_height_jitter: float = 0.05
## Chance that a fish adopts the target of a school-mate in view when it picks a new one.
@export var follow_target_chance: float = 1.0
## A school-mate is "far" beyond this many body lengths: the fish then catches up at top speed.
@export var catch_up_distance_bl: float = 6.0

# --- forces ---
## The vertical part of the school and separation forces is scaled by this, so fish keep their
## depth zone while they keep together.
@export var social_vertical_scale: float = 0.5
## The summed spacing and separation pushes of all neighbours are capped at these lengths (before
## their weights), so a crowd can not push a fish into the glass and hold it there.
@export var spacing_force_cap: float = 3.0
@export var separation_force_cap: float = 1.5
## A fish steers away from a fish whose path will cross its own within this many seconds, if they
## would pass closer than this share of the sum of their half lengths; summed and capped like the
## other pushes.
@export var avoid_horizon_s: float = 1.5
@export var avoid_radius_factor: float = 1.3
@export var avoid_weight: float = 3.0
@export var avoid_force_cap: float = 1.0
## The last resort against overlap: a pair closer than contact_distance_factor times the sum of
## the half lengths is pushed apart. A nearly still fish may be pushed by up to
## contact_still_fraction of its top speed (so a fish at rest is not driven faster than the speed
## from which its heading must match its motion), a moving one by contact_follow_fraction of its
## own speed. Pairs within contact_reach_factor times that sum plus contact_reach_m at the last
## search are watched.
@export var contact_distance_factor: float = 1.003
@export var contact_still_fraction: float = 0.095
@export var contact_follow_fraction: float = 0.4
@export var contact_reach_factor: float = 1.6
@export var contact_reach_m: float = 0.02
## The pull of a fish back to its own height in the band (depth preference), as a share of the
## band height per metre of distance, capped at 1.
@export var depth_restore_weight: float = 1.5
@export var wander_weight: float = 1.0
@export var cohesion_weight: float = 3.0
@export var alignment_weight: float = 0.5
@export var spacing_weight: float = 16.0
@export var separation_weight: float = 3.0
## Personal space = this x the sum of the half lengths of two fish.
@export var separation_factor: float = 1.25
## The push of the personal space reaches 1 at the sum of the half lengths and grows to
## separation_max over this fraction of that sum.
@export var separation_ramp_fraction: float = 0.25
@export var separation_max: float = 4.0
## Seconds between two neighbour searches.
@export var neighbour_period_s: float = 0.05

# --- limits ---
## The wander target stays this far inside the band; the steering clamp is band_margin_m outside.
@export var band_inset_m: float = 0.005
@export var band_margin_m: float = 0.01
## The steering keeps this far inside the glass limits (the hard clamp has none).
@export var wall_margin_m: float = 0.01
## Braking stops a fish this far inside the glass limits (between the steering margin and the hard
## clamp), so a fish that sits a hair outside the steering margin still swims along the glass.
@export var brake_margin_m: float = 0.005
## A fish may be this far past the braking limit before it must stop: a fish that sits flush at the
## limit and swims along the glass is not blocked by the sign of a rounding error.
@export var brake_slack_m: float = 0.001
## A fish flush with the glass whose heading points into it by at most this share (the sine of the
## angle, 0.25 is about 14 degrees) glides along the glass instead of stopping.
@export var glass_glide_sin: float = 0.2
## Within this many turning radii (at cruise speed) of the glass a fish steers away from it with
## this weight; wander targets keep the same distance from the glass.
@export var wall_avoid_turns: float = 1.0
@export var wall_avoid_weight: float = 1.5
## The wish that points into the glass fades out within this many braking distances plus the margin.
@export var wall_slide_zone_factor: float = 1.5
## Seconds ahead in which the bed is looked at for the height of the band.
@export var look_ahead_s: float = 0.5

# --- recovery ease ---
@export var recovery_speed_factor: float = 6.0
@export var recovery_ramp_s: float = 0.3
@export var recovery_max_s: float = 2.0
## A fish counts as outside its band beyond band_margin_m plus this tolerance.
@export var recovery_tolerance_m: float = 1e-6

# --- stuck rule ---
@export var stuck_speed_fraction: float = 0.05
@export var stuck_time_s: float = 5.0
@export var detour_s: float = 2.0
## An overridden fish that has arrived turns to face the middle of the tank with this weight, so
## that its hop (below) needs no big turn.
@export var arrival_turn_weight: float = 0.3
## An overridden fish that waits at its target hops to a point this many body lengths away.
@export var detour_radius_bl: float = 0.4

# --- pinned fish ---
## A pinned fish drifts at most this far (metres) around its anchor.
@export var pinned_drift_m: float = 0.008
@export var pinned_drift_period_s: float = 5.0

# --- time steps ---
@export var max_substep_s: float = 0.016666666666666666
@export var max_delta_s: float = 0.5

## One entry per FishSpecies.GroupStyle value, indexed by the value.
@export var group_styles: Array[FishGroupStyleTuning] = []


static func load_default() -> FishSwimTuning:
	return load(DEFAULT_PATH) as FishSwimTuning


## The entry of a group style; UNSET and out-of-range values read as SOLITARY.
func style_of(group_style: int) -> FishGroupStyleTuning:
	if group_style <= 0 or group_style >= group_styles.size():
		return group_styles[FishSpecies.GroupStyle.SOLITARY]
	return group_styles[group_style]
