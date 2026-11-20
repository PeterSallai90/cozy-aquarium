extends GdUnitTestSuite
## #31 AC 10, 27 and 41 (owner: developer): RotateHold as a pure state machine, driven by fixed
## frame times. press(direction, start_deg, fine) turns by one step at once; tick(delta_s, fine)
## returns the repeat steps of the frame: the first repeat comes after REPEAT_DELAY_S, then one
## step every REPEAT_INTERVAL_S (FINE_REPEAT_INTERVAL_S with Shift, read again at every tick);
## release() and cancel() end the hold. get_pending_deg() is the angle the view shows: the start
## angle plus or minus (N + 1) whole steps of 15 degrees (1 degree with Shift), normalised; the
## rule is additive, never snapping (AC 12, owner correction 2026-11-20). The constants come from
## PlacementTuning.
## Test decisions where the plan is silent: a single tick() call with a long delta returns every
## step that is due (it does not cap at one); the timing checks avoid the exact boundaries, so a
## timer that carries its remainder or resets it both pass; the "24 steps" edge case of AC 27 is
## 23 repeat ticks (press plus 23 ticks = 24 steps = 360 degrees) and holds from any start angle,
## a multiple of 15 and a free angle such as 10; 24 ticks end at start + 15.

const Api := preload("res://tests/helpers/placement_api.gd")

const FRAME_S: float = 1.0 / 120.0


func _have() -> bool:
	var found: bool = Api.exists(Api.HOLD) and Api.exists(Api.TUNING) and Api.exists(Api.STEP)
	(
		assert_bool(found)
		. override_failure_message(
			"rotate_hold.gd, rotation_step.gd or placement_tuning.gd missing"
		)
		. is_true()
	)
	return found


## The steps a hold made while `seconds` of fixed frames passed.
func _run(hold: RefCounted, seconds: float, fine: bool = false) -> int:
	var total: int = 0
	var left: float = seconds
	while left > 0.0:
		var dt: float = minf(FRAME_S, left)
		total += int(hold.call("tick", dt, fine))
		left -= dt
	return total


## The time at which exactly `ticks` repeat ticks have happened (between tick n and n + 1).
func _time_for(ticks: int, fine: bool = false) -> float:
	var interval: float = Api.tuning("FINE_REPEAT_INTERVAL_S" if fine else "REPEAT_INTERVAL_S")
	return Api.tuning("REPEAT_DELAY_S") + (ticks - 1) * interval + interval * 0.5


func _pending(hold: RefCounted) -> float:
	return float(hold.call("get_pending_deg"))


func _same_angle(actual: float, expected: float) -> void:
	var gap: float = absf(wrapf(actual - expected, -180.0, 180.0))
	assert_float(gap).override_failure_message("angle %s is not %s" % [actual, expected]).is_less(
		0.001
	)


func test_ac10_the_timing_constants_exist_in_one_place_and_are_positive() -> void:
	if not _have():
		return
	for constant_name: String in [
		"REPEAT_DELAY_S",
		"REPEAT_INTERVAL_S",
		"FINE_REPEAT_INTERVAL_S",
		"SAME_ANGLE_DEG",
		"SAME_SPOT_M",
		"DRAG_THRESHOLD_PX",
	]:
		assert_float(Api.tuning(constant_name)).override_failure_message(constant_name).is_greater(
			0.0
		)
	assert_float(Api.tuning("FINE_REPEAT_INTERVAL_S")).is_less(Api.tuning("REPEAT_INTERVAL_S"))


func test_ac27_a_new_hold_is_not_active() -> void:
	if not _have():
		return
	var hold: RefCounted = Api.new_hold()
	assert_bool(hold.call("is_active")).is_false()
	assert_int(_run(hold, 2.0)).is_equal(0)


func test_ac27_press_turns_one_step_at_once_and_records_direction_and_start() -> void:
	if not _have():
		return
	var hold: RefCounted = Api.new_hold()
	hold.call("press", 1, 10.0, false)
	assert_bool(hold.call("is_active")).is_true()
	assert_int(hold.call("get_direction")).is_equal(1)
	assert_float(hold.call("get_start_deg")).is_equal_approx(10.0, 0.0001)
	_same_angle(_pending(hold), 25.0)


func test_ac27_press_right_and_fine_follow_rotation_step() -> void:
	if not _have():
		return
	var hold: RefCounted = Api.new_hold()
	hold.call("press", -1, 10.0, false)
	_same_angle(_pending(hold), 355.0)
	hold.call("cancel")
	hold.call("press", -1, 0.0, true)
	_same_angle(_pending(hold), 359.0)
	assert_int(hold.call("get_direction")).is_equal(-1)
	hold.call("cancel")
	hold.call("press", 1, 37.0, true)
	_same_angle(_pending(hold), 38.0)


func test_ac10_no_repeat_comes_before_the_delay() -> void:
	if not _have():
		return
	var hold: RefCounted = Api.new_hold()
	hold.call("press", 1, 0.0, false)
	assert_int(_run(hold, Api.tuning("REPEAT_DELAY_S") * 0.9)).is_equal(0)
	_same_angle(_pending(hold), 15.0)


func test_ac27_hold_with_0_1_5_and_23_repeat_ticks_ends_at_start_plus_n_plus_1_steps() -> void:
	if not _have():
		return
	for ticks: int in [0, 1, 5, 23]:
		var hold: RefCounted = Api.new_hold()
		hold.call("press", 1, 30.0, false)
		var made: int = _run(hold, _time_for(ticks)) if ticks > 0 else 0
		(
			assert_int(made)
			. override_failure_message("%d ticks wanted, %d made" % [ticks, made])
			. is_equal(ticks)
		)
		_same_angle(_pending(hold), 30.0 + 15.0 * (ticks + 1))
		assert_bool(hold.call("is_active")).is_true()


func test_ac27_a_hold_from_the_free_angle_10_adds_whole_steps() -> void:
	if not _have():
		return
	for ticks: int in [0, 1, 5, 23]:
		var hold: RefCounted = Api.new_hold()
		hold.call("press", 1, 10.0, false)
		if ticks > 0:
			_run(hold, _time_for(ticks))
		_same_angle(_pending(hold), 10.0 + 15.0 * (ticks + 1))
	var five: RefCounted = Api.new_hold()
	five.call("press", 1, 10.0, false)
	_run(five, _time_for(5))
	_same_angle(_pending(five), 100.0)


func test_ac27_a_right_hold_from_the_free_angle_10_subtracts_whole_steps() -> void:
	if not _have():
		return
	for ticks: int in [0, 1, 5]:
		var hold: RefCounted = Api.new_hold()
		hold.call("press", -1, 10.0, false)
		if ticks > 0:
			_run(hold, _time_for(ticks))
		_same_angle(_pending(hold), 10.0 - 15.0 * (ticks + 1))


func test_ac27_23_ticks_of_15_degrees_come_back_to_the_start_from_any_angle() -> void:
	if not _have():
		return
	for start: float in [30.0, 10.0, 37.5]:
		for direction: int in [1, -1]:
			var hold: RefCounted = Api.new_hold()
			hold.call("press", direction, start, false)
			_run(hold, _time_for(23))
			_same_angle(_pending(hold), start)


func test_ac27_24_ticks_end_one_step_past_the_start() -> void:
	if not _have():
		return
	var hold: RefCounted = Api.new_hold()
	hold.call("press", 1, 30.0, false)
	_run(hold, _time_for(24))
	_same_angle(_pending(hold), 45.0)


func test_ac10_the_right_key_repeats_downward() -> void:
	if not _have():
		return
	var hold: RefCounted = Api.new_hold()
	hold.call("press", -1, 30.0, false)
	_run(hold, _time_for(3))
	_same_angle(_pending(hold), 30.0 - 15.0 * 4)


func test_ac10_the_fine_step_repeats_at_the_fine_interval() -> void:
	if not _have():
		return
	var hold: RefCounted = Api.new_hold()
	hold.call("press", 1, 0.0, true)
	var made: int = _run(hold, _time_for(10, true), true)
	assert_int(made).is_equal(10)
	_same_angle(_pending(hold), 11.0)


func test_ac10_shift_is_read_again_at_every_tick_so_the_step_size_follows_it() -> void:
	if not _have():
		return
	var plain: RefCounted = Api.new_hold()
	plain.call("press", 1, 0.0, false)
	_run(plain, Api.tuning("REPEAT_DELAY_S") * 1.1)
	var plain_steps: int = _run(plain, 0.5, false)
	var fine: RefCounted = Api.new_hold()
	fine.call("press", 1, 0.0, false)
	_run(fine, Api.tuning("REPEAT_DELAY_S") * 1.1)
	var fine_steps: int = _run(fine, 0.5, true)
	var plain_due: int = roundi(0.5 / Api.tuning("REPEAT_INTERVAL_S"))
	var fine_due: int = roundi(0.5 / Api.tuning("FINE_REPEAT_INTERVAL_S"))
	assert_int(plain_steps).is_between(plain_due - 1, plain_due + 1)
	assert_int(fine_steps).is_between(fine_due - 1, fine_due + 1)
	assert_int(fine_steps).is_greater(plain_steps)


func test_ac10_one_long_frame_returns_every_due_step() -> void:
	if not _have():
		return
	var hold: RefCounted = Api.new_hold()
	hold.call("press", 1, 0.0, false)
	var delta: float = Api.tuning("REPEAT_DELAY_S") + Api.tuning("REPEAT_INTERVAL_S") * 2.5
	assert_int(hold.call("tick", delta, false)).is_equal(3)
	_same_angle(_pending(hold), 15.0 * 4)


func test_ac27_release_ends_the_hold_and_no_more_steps_come() -> void:
	if not _have():
		return
	var hold: RefCounted = Api.new_hold()
	hold.call("press", 1, 0.0, false)
	_run(hold, _time_for(2))
	hold.call("release")
	assert_bool(hold.call("is_active")).is_false()
	assert_int(_run(hold, 3.0)).is_equal(0)


func test_ac41_cancel_ends_the_hold_and_no_more_steps_come() -> void:
	if not _have():
		return
	var hold: RefCounted = Api.new_hold()
	hold.call("press", 1, 0.0, false)
	_run(hold, _time_for(2))
	hold.call("cancel")
	assert_bool(hold.call("is_active")).is_false()
	assert_int(_run(hold, 3.0)).is_equal(0)


func test_ac41_a_new_press_after_a_cancel_starts_a_fresh_hold_with_a_fresh_delay() -> void:
	if not _have():
		return
	var hold: RefCounted = Api.new_hold()
	hold.call("press", 1, 0.0, false)
	_run(hold, _time_for(3))
	hold.call("cancel")
	hold.call("press", -1, 100.0, false)
	assert_int(hold.call("get_direction")).is_equal(-1)
	assert_float(hold.call("get_start_deg")).is_equal_approx(100.0, 0.0001)
	_same_angle(_pending(hold), 85.0)
	assert_int(_run(hold, Api.tuning("REPEAT_DELAY_S") * 0.9)).is_equal(0)
	_run(hold, Api.tuning("REPEAT_DELAY_S") * 0.2)
	_same_angle(_pending(hold), 70.0)


func test_ac41_switching_keys_is_a_release_and_a_new_press() -> void:
	if not _have():
		return
	var hold: RefCounted = Api.new_hold()
	hold.call("press", 1, 10.0, false)
	hold.call("release")
	hold.call("press", -1, 15.0, false)
	assert_bool(hold.call("is_active")).is_true()
	assert_int(hold.call("get_direction")).is_equal(-1)
	_same_angle(_pending(hold), 0.0)
