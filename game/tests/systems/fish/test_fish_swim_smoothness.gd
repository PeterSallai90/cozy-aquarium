extends GdUnitTestSuite
## #35 smoothness caps, frame-rate independence, hitch and zero or negative delta (owner: developer;
## BA decisions Q5 and Q6). The smoothness checker (FishSwimRig.Smooth) reads every step of every
## fish in every steering test: the acceleration cap (standstill to top speed takes at least 0.3 s,
## so the speed change per step is at most top / 0.3 s times the step), the yaw acceleration cap
## (the yaw rate changes by at most the turn cap per 0.25 s), at most 2 heading-rate sign flips per
## second counted only above 5 percent of the turn cap, the pitch limit plus 0.5 deg, head-first
## (heading to velocity at most 30 deg above 10 percent of top speed), the turn rate cap and no
## teleport; the acceleration, speed and head-first checks skip the steps of the recovery ease (DoR
## note 2). The 10-minute runs of 20 fish per species at 1/60 and at 1/144 s are shared with the
## feel tests; 1/30 s is asserted to be the same trajectory as two steps of 1/60 s (the simulation
## splits a delta into equal substeps of at most 1/60 s, ADR 0015 rule 5), so the 1/60 results carry
## over without a third 10-minute run. A 0.5 s hitch moves a fish by at most its top speed times 0.5
## s (times the speed factor above 1), turns it by at most the turn cap times 0.5 s, keeps the
## acceleration caps and does not teleport; a zero or negative delta changes nothing and a delta
## above 0.5 s acts like 0.5 s. Test decisions: the mixed crowd of 8 tetras, 4 angelfish and 6
## corydoras in the large tank.

const FishApi := preload("res://tests/helpers/fish_api.gd")
const Rig := preload("res://tests/helpers/fish_swim_rig.gd")
const Runs := preload("res://tests/helpers/fish_swim_runs.gd")

const FAST_STEP := 1.0 / 144.0
const HALF_STEP := 1.0 / 30.0
const HITCH_S := 0.5
const SAME := 1e-9


func _mixed() -> Rig.Setup:
	var setup: Rig.Setup = Rig.open(Rig.LARGE, Rig.mixed(8, 4, 6))
	assert_object(setup).override_failure_message("the steering classes are missing").is_not_null()
	return setup


## An empty string when both observers hold the same values, else what differs.
func _difference(a: Rig.Observer, b: Rig.Observer, setup: Rig.Setup, tolerance: float) -> String:
	for index: int in a.count:
		var uid: String = setup.members[index].uid
		if a.position[index].distance_to(b.position[index]) > tolerance:
			return "%s position %s against %s" % [uid, a.position[index], b.position[index]]
		if absf(a.yaw[index] - b.yaw[index]) > tolerance:
			return "%s yaw" % uid
		if absf(a.speed[index] - b.speed[index]) > tolerance:
			return "%s speed" % uid
		if absf(a.shader_speed[index] - b.shader_speed[index]) > tolerance:
			return "%s shader speed" % uid
		if a.mode[index] != b.mode[index] or a.darts[index] != b.darts[index]:
			return "%s state" % uid
	return ""


func _smooth_run(id: StringName, step: float) -> void:
	var run: Dictionary = Runs.feel(id, step)
	(
		assert_bool(run.get("ok", false))
		. override_failure_message("the steering classes are missing")
		. is_true()
	)
	if not run.get("ok", false):
		return
	for part: Dictionary in run.get("parts", [run]):
		var smooth: Rig.Smooth = part["smooth"]
		(
			assert_int(smooth.total())
			. override_failure_message("%s at 1/%d: %s" % [id, roundi(1.0 / step), smooth.report()])
			. is_equal(0)
		)
		assert_int(smooth.steps).is_equal(roundi(Runs.TOTAL_S / step))


func test_35_neon_tetras_keep_every_cap_for_10_minutes_at_1_60() -> void:
	_smooth_run(FishApi.NEON, Rig.STEP)


func test_35_angelfish_keep_every_cap_for_10_minutes_at_1_60() -> void:
	_smooth_run(FishApi.ANGEL, Rig.STEP)


func test_35_corydoras_keep_every_cap_for_10_minutes_at_1_60() -> void:
	_smooth_run(FishApi.CORY, Rig.STEP)


func test_35_neon_tetras_keep_every_cap_for_10_minutes_at_1_144() -> void:
	_smooth_run(FishApi.NEON, FAST_STEP)


func test_35_angelfish_keep_every_cap_for_10_minutes_at_1_144() -> void:
	_smooth_run(FishApi.ANGEL, FAST_STEP)


func test_35_corydoras_keep_every_cap_for_10_minutes_at_1_144() -> void:
	_smooth_run(FishApi.CORY, FAST_STEP)


func test_35_the_fish_really_reach_speed_so_the_caps_are_exercised() -> void:
	for id: StringName in FishApi.IDS:
		var run: Dictionary = Runs.feel(id, Rig.STEP)
		if not run.get("ok", false):
			(
				assert_bool(false)
				. override_failure_message("the steering classes are missing")
				. is_true()
			)
			return
		var best: float = 0.0
		for part: Dictionary in run.get("parts", [run]):
			best = maxf(best, (part["smooth"] as Rig.Smooth).max_speed_ratio)
		assert_float(best).override_failure_message(str(id)).is_greater(0.8)


# --- frame-rate independence ---


func test_35_a_step_of_1_30_is_the_same_trajectory_as_two_steps_of_1_60_for_60_seconds() -> void:
	var slow: Rig.Setup = _mixed()
	var fast: Rig.Setup = _mixed()
	if slow == null or fast == null:
		return
	var obs_slow: Rig.Observer = Rig.Observer.new(slow)
	var obs_fast: Rig.Observer = Rig.Observer.new(fast)
	var smooth: Rig.Smooth = Rig.Smooth.new(slow.members)
	for index: int in 1800:
		slow.sim.call("step", HALF_STEP)
		fast.sim.call("step", Rig.STEP)
		fast.sim.call("step", Rig.STEP)
		obs_slow.read()
		obs_fast.read()
		smooth.check(obs_slow, (index + 1) * HALF_STEP, HALF_STEP)
		var difference: String = _difference(obs_slow, obs_fast, slow, SAME)
		if not difference.is_empty():
			(
				assert_str(difference)
				. override_failure_message(
					"1/30 and 2 x 1/60 differ at %.3f s: %s" % [(index + 1) * HALF_STEP, difference]
				)
				. is_empty()
			)
			return
	assert_int(smooth.total()).override_failure_message(smooth.report()).is_equal(0)


# --- hitch ---


func _hitch_from(setup: Rig.Setup, warm_seconds: float) -> void:
	var obs: Rig.Observer = Rig.Observer.new(setup)
	var smooth: Rig.Smooth = Rig.Smooth.new(setup.members)
	var time: float = 0.0
	for _index: int in roundi(warm_seconds / Rig.STEP):
		setup.sim.call("step", Rig.STEP)
		time += Rig.STEP
		obs.read()
		smooth.check(obs, time, Rig.STEP)
	obs.read()
	var before_position: PackedVector3Array = obs.position.duplicate()
	var before_yaw: PackedFloat64Array = obs.yaw.duplicate()
	var before_speed: PackedFloat64Array = obs.speed.duplicate()
	var before_rate: PackedFloat64Array = obs.yaw_rate.duplicate()
	setup.sim.call("step", HITCH_S)
	time += HITCH_S
	obs.read()
	smooth.check(obs, time, HITCH_S)
	for index: int in obs.count:
		var member: Rig.Member = setup.members[index]
		var label: String = member.uid
		var reach: float = member.top * maxf(1.0, member.speed_factor) * HITCH_S
		(
			assert_float(obs.position[index].distance_to(before_position[index]))
			. override_failure_message("%s teleported across the hitch" % label)
			. is_less_equal(reach + 1e-7)
		)
		(
			assert_float(absf(wrapf(obs.yaw[index] - before_yaw[index], -PI, PI)))
			. override_failure_message("%s turned more than the cap across the hitch" % label)
			. is_less_equal(member.turn_cap * HITCH_S + 1e-7)
		)
		(
			assert_float(absf(obs.speed[index] - before_speed[index]))
			. override_failure_message("%s broke the acceleration cap across the hitch" % label)
			. is_less_equal(member.top / Rig.ACCEL_TIME_S * HITCH_S + 1e-9)
		)
		(
			assert_float(absf(obs.yaw_rate[index] - before_rate[index]))
			. override_failure_message("%s broke the yaw acceleration cap across the hitch" % label)
			. is_less_equal(member.turn_cap / Rig.YAW_ACCEL_TIME_S * HITCH_S + 1e-7)
		)
	for _index: int in roundi(5.0 / Rig.STEP):
		setup.sim.call("step", Rig.STEP)
		time += Rig.STEP
		obs.read()
		smooth.check(obs, time, Rig.STEP)
	assert_int(smooth.total()).override_failure_message(smooth.report()).is_equal(0)


func test_35_one_hitch_of_half_a_second_after_settling_keeps_every_cap_and_does_not_teleport(
) -> void:
	var setup: Rig.Setup = _mixed()
	if setup != null:
		_hitch_from(setup, 40.0)


func test_35_a_hitch_in_the_first_frame_does_not_break_a_cap() -> void:
	var setup: Rig.Setup = _mixed()
	if setup != null:
		_hitch_from(setup, 0.0)


func test_35_a_delta_above_half_a_second_acts_like_half_a_second() -> void:
	var long: Rig.Setup = _mixed()
	var half: Rig.Setup = _mixed()
	if long == null or half == null:
		return
	for _index: int in 600:
		long.sim.call("step", Rig.STEP)
		half.sim.call("step", Rig.STEP)
	long.sim.call("step", 10.0)
	half.sim.call("step", HITCH_S)
	var obs_long: Rig.Observer = Rig.Observer.new(long)
	var obs_half: Rig.Observer = Rig.Observer.new(half)
	obs_long.read()
	obs_half.read()
	assert_str(_difference(obs_long, obs_half, long, SAME)).is_empty()


# --- zero and negative delta ---


func test_35_a_zero_or_negative_delta_changes_nothing() -> void:
	var setup: Rig.Setup = _mixed()
	if setup == null:
		return
	var obs: Rig.Observer = Rig.Observer.new(setup)
	var later: Rig.Observer = Rig.Observer.new(setup)
	for _index: int in 300:
		setup.sim.call("step", Rig.STEP)
	obs.read()
	for delta: float in [0.0, -0.1, -1e-12, -5.0]:
		setup.sim.call("step", delta)
		later.read()
		(
			assert_str(_difference(obs, later, setup, 0.0))
			. override_failure_message("step(%s) changed a fish" % delta)
			. is_empty()
		)


func test_35_zero_and_negative_steps_do_not_advance_any_timer() -> void:
	var plain: Rig.Setup = _mixed()
	var noisy: Rig.Setup = _mixed()
	if plain == null or noisy == null:
		return
	for _index: int in 1200:
		plain.sim.call("step", Rig.STEP)
		noisy.sim.call("step", 0.0)
		noisy.sim.call("step", Rig.STEP)
		noisy.sim.call("step", -0.25)
	var obs_plain: Rig.Observer = Rig.Observer.new(plain)
	var obs_noisy: Rig.Observer = Rig.Observer.new(noisy)
	obs_plain.read()
	obs_noisy.read()
	assert_str(_difference(obs_plain, obs_noisy, plain, SAME)).is_empty()
