class_name CameraSettings
extends Resource
## Tuning values of the build camera and the wall cut-away. One place, loaded by path.

@export var min_elevation_limit_deg: float = -10.0
@export var max_elevation_deg: float = 85.0
@export var damping_time_s: float = 0.15
@export var drag_deg_per_viewport_height: float = 180.0
@export var azimuth_step_deg: float = 45.0
@export var elevation_step_deg: float = 5.0
@export var key_repeat_interval_s: float = 0.25
@export var max_frame_time_s: float = 0.1
@export var wall_fade_time_s: float = 0.2
@export var wall_hysteresis_band_m: float = 0.05
