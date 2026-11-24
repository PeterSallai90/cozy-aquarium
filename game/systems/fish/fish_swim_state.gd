class_name FishSwimState
extends RefCounted
## The read-only result of the simulation for one fish (ADR 0015 rule 4): written by FishSwimSim
## only; the view and the tests read it. Metres, seconds, radians; the tank frame.

## What the fish is doing. A dart and the recovery ease are never idle.
enum Mode { IDLE = 0, CRUISE = 1, DART = 2, OVERRIDE = 3 }

var position: Vector3 = Vector3.ZERO
## The swimming motion of the last step (displacement of the fish's own movement, glass clamp
## included) divided by its length; a push from a touching fish (personal space) is not part of it.
var velocity: Vector3 = Vector3.ZERO
## The speed along the heading (what the speed caps and ramps act on).
var speed: float = 0.0
## Heading about +Y (0 faces +Z) and its rate.
var yaw: float = 0.0
var yaw_rate: float = 0.0
## Pitch of the direction of travel, and of the body (travel pitch minus the nose-down bias).
var travel_pitch: float = 0.0
var pitch: float = 0.0
## clamp(distance moved per second / species top speed, 0, 1): the swim_speed shader parameter,
## so the tail beats with the real motion (also while a touching fish pushes this one).
var shader_speed: float = 0.0
var mode: Mode = Mode.IDLE
## True while the recovery ease guides the fish back into its limits.
var recovering: bool = false
## True when the water column is too small for the fish (FishZones pinned).
var pinned: bool = false
## True in cruise, dart and override, while not paused and not pinned.
var intends_to_move: bool = false
var darts_started: int = 0
## Seconds the fish intended to move but was slower than the stuck speed.
var low_speed_time: float = 0.0
