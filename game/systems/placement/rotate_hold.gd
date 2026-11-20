class_name RotateHold
extends RefCounted
## One press-and-hold of a rotate key as a pure state machine (#31 AC 10, 27, 41), driven by
## frame times. press() turns by one step at once; tick() returns the repeat steps that are due:
## the first after REPEAT_DELAY_S, then one every REPEAT_INTERVAL_S (FINE_REPEAT_INTERVAL_S with
## Shift, read again at every tick). release() and cancel() end the hold. The pending angle is
## what the view shows; the commit of a hold is the caller's business.

var _active: bool = false
var _direction: int = 1
var _start_deg: float = 0.0
var _pending_deg: float = 0.0
var _timer_s: float = 0.0
var _repeating: bool = false


## Starts a hold and makes the first step. direction is +1 (left, Comma) or -1 (right, Period).
func press(direction: int, start_deg: float, fine: bool) -> void:
	_active = true
	_direction = 1 if direction >= 0 else -1
	_start_deg = start_deg
	_pending_deg = RotationStep.step(start_deg, _direction, fine)
	_timer_s = 0.0
	_repeating = false


## Advances the repeat timer; returns the number of steps made (every due step, not capped).
func tick(delta_s: float, fine: bool) -> int:
	if not _active or delta_s <= 0.0:
		return 0
	_timer_s += delta_s
	var interval: float = (
		PlacementTuning.FINE_REPEAT_INTERVAL_S if fine else PlacementTuning.REPEAT_INTERVAL_S
	)
	var made: int = 0
	while _timer_s >= (interval if _repeating else PlacementTuning.REPEAT_DELAY_S):
		_timer_s -= interval if _repeating else PlacementTuning.REPEAT_DELAY_S
		_repeating = true
		_pending_deg = RotationStep.step(_pending_deg, _direction, fine)
		made += 1
	return made


func release() -> void:
	_active = false


func cancel() -> void:
	_active = false


func is_active() -> bool:
	return _active


func get_direction() -> int:
	return _direction


func get_start_deg() -> float:
	return _start_deg


## The angle after the press and every repeat so far, in [0, 360).
func get_pending_deg() -> float:
	return _pending_deg
