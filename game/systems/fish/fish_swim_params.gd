class_name FishSwimParams
extends RefCounted
## The inputs of the steering model for one fish (ADR 0015 rule 4), in metres, seconds and radians:
## built from the species data, the derived personality, the global tuning and the fish extents.
## Mode 2 can build or override these inputs without touching the simulation.

## Fish of the same key form a group (the species id; never named in the steering code).
var species_key: StringName = &""
var zone: FishSpecies.Zone = FishSpecies.Zone.UNSET
var extents: FishExtents = null
var body_length_m: float = 0.0
var half_length_m: float = 0.0
## Species top speed (no personality) and the personality speed factor.
var top_speed_m_s: float = 0.0
var speed_factor: float = 1.0
var cruise_speed_m_s: float = 0.0
var dart_speed_m_s: float = 0.0
var catch_up_speed_m_s: float = 0.0
## Seconds between darts (boldness applied) and how long a dart lasts.
var dart_interval_min_s: float = 0.0
var dart_interval_max_s: float = 0.0
var dart_duration_min_s: float = 0.0
var dart_duration_max_s: float = 0.0
var idle_share: float = 0.0
var turn_rate_max: float = 0.0
var yaw_accel_max: float = 0.0
var accel_max: float = 0.0
var pitch_limit: float = 0.0
var nose_down_bias: float = 0.0
## Offset of the preferred height from the band centre, fraction of the band height.
var depth_fraction: float = 0.0
## FishSpecies.GroupStyle value with UNSET already read as SOLITARY.
var group_style: int = FishSpecies.GroupStyle.SOLITARY
var cohesion: float = 0.0
var alignment: float = 0.0
var spacing_m: float = 0.0
var view_radius_m: float = 0.0
## Derived numbers the per-frame steering reads (metres, seconds, radians).
var stuck_speed_m_s: float = 0.0
var idle_drift_m_s: float = 0.0
var catch_up_distance_m: float = 0.0
var target_reach_m: float = 0.0
var pitch_rate_max: float = 0.0
var bias_step_per_s: float = 0.0


static func create(
	species: FishSpecies,
	personality: FishPersonality,
	tuning: FishSwimTuning,
	fish_extents: FishExtents
) -> FishSwimParams:
	var result: FishSwimParams = FishSwimParams.new()
	result.species_key = species.id
	result.zone = species.preferred_zone
	result.extents = fish_extents
	result.body_length_m = species.adult_length_cm / 100.0
	result.half_length_m = result.body_length_m / 2.0
	result.top_speed_m_s = species.swim_speed * tuning.top_speed_factor_k * result.body_length_m
	result.speed_factor = personality.speed
	result.cruise_speed_m_s = (
		result.top_speed_m_s * tuning.cruise_speed_fraction * personality.speed
	)
	result.dart_speed_m_s = (
		result.top_speed_m_s
		* personality.speed
		* minf(1.0, tuning.dart_speed_fraction * personality.boldness)
	)
	result.catch_up_speed_m_s = result.top_speed_m_s
	result.dart_interval_min_s = species.dart_interval_min_s / personality.boldness
	result.dart_interval_max_s = species.dart_interval_max_s / personality.boldness
	result.dart_duration_min_s = species.dart_duration_min_s
	result.dart_duration_max_s = species.dart_duration_max_s
	result.idle_share = species.idle_share * personality.idle_share
	result.turn_rate_max = deg_to_rad(species.turn_rate_max_deg_s)
	result.yaw_accel_max = result.turn_rate_max / tuning.yaw_ramp_s
	result.accel_max = result.top_speed_m_s / tuning.accel_ramp_s
	result.pitch_limit = deg_to_rad(species.pitch_limit_deg)
	result.nose_down_bias = deg_to_rad(species.nose_down_bias_deg)
	result.depth_fraction = personality.depth_preference
	var style: FishGroupStyleTuning = tuning.style_of(species.group_style)
	result.group_style = (
		species.group_style
		if species.group_style > FishSpecies.GroupStyle.UNSET
		else FishSpecies.GroupStyle.SOLITARY
	)
	result.cohesion = style.cohesion * personality.sociability
	result.alignment = style.alignment
	result.spacing_m = style.spacing_bl * result.body_length_m
	result.view_radius_m = style.view_radius_bl * result.body_length_m
	result.stuck_speed_m_s = tuning.stuck_speed_fraction * result.top_speed_m_s
	result.idle_drift_m_s = result.top_speed_m_s * tuning.idle_drift_fraction * personality.speed
	result.catch_up_distance_m = tuning.catch_up_distance_bl * result.body_length_m
	result.target_reach_m = maxf(
		tuning.target_reach_bl * result.body_length_m,
		tuning.target_reach_turns * result.cruise_speed_m_s / maxf(result.turn_rate_max, 0.1)
	)
	result.pitch_rate_max = result.turn_rate_max * tuning.pitch_rate_fraction
	result.bias_step_per_s = result.nose_down_bias / tuning.bias_ease_s
	return result
