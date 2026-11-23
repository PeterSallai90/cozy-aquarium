class_name FishSwimMember
extends RefCounted
## Everything FishSwimSim keeps about one fish (ADR 0015 rule 4); the public part is `state`.
## Internal to the simulation: nothing else reads or writes these fields.

var uid: String = ""
var params: FishSwimParams = null
var state: FishSwimState = FishSwimState.new()
var idx: int = -1
var position: Vector3 = Vector3.ZERO
var yaw: float = 0.0
var yaw_rate: float = 0.0
var travel_pitch: float = 0.0
var speed: float = 0.0
var bias: float = 0.0
var mode: FishSwimState.Mode = FishSwimState.Mode.IDLE
var resume_mode: FishSwimState.Mode = FishSwimState.Mode.CRUISE
var mode_left: float = 0.0
var dart_timer: float = 0.0
var dart_left: float = 0.0
var dart_yaw: float = 0.0
var since_dart: float = 1.0e9
var target: Vector3 = Vector3.ZERO
var has_override: bool = false
var override_goal: Vector3 = Vector3.ZERO
var override_raw: Vector3 = Vector3.ZERO
var detour_left: float = 0.0
var last_sign: int = 0
var flip_clock: float = 0.0
var want: Vector3 = Vector3.ZERO
var smooth_mode: FishSwimState.Mode = FishSwimState.Mode.IDLE
var low_time: float = 0.0
var ahead_low: float = 0.0
var ahead_high: float = 0.0
var vert: FishSwimLimits.Vertical = FishSwimLimits.Vertical.new()
var anchor: Vector2 = Vector2.ZERO
var was_pinned: bool = false
var drift_left: float = 0.0
var drift_goal: Vector2 = Vector2.ZERO
var recovering: bool = false
var rec_from: Vector3 = Vector3.ZERO
var rec_to: Vector3 = Vector3.ZERO
var rec_dir: Vector3 = Vector3.ZERO
var rec_len: float = 0.0
var rec_total: float = 0.0
var rec_speed: float = 0.0
var rec_time: float = 0.0
## The glass limits of the origin: hard (the clamp) and soft (what the steering keeps), x and z.
var hard: Vector2 = Vector2.ZERO
var soft: Vector2 = Vector2.ZERO
