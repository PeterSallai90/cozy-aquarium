extends GdUnitTestSuite
## #35 pause and override seams (owner: developer; BA decisions Q16, ADR 0015 rule 7). `paused` is
## one global flag of FishSwimSim: positions, headings, shader speed, timers and darts freeze, and
## clearing it continues from where the fish were without a jump. An override target (the seam for
## #37) makes the fish move toward it and return to normal swimming when it is cleared: a target
## outside the tank or below the substrate is clamped to the nearest valid point of the hard limits,
## the zone band does not apply, separation, the turn rate cap, the acceleration cap, the pitch
## limit and the top speed still apply, there are no dart or idle states. An override set while
## paused is stored and applies on resume; a fish added while paused appears at its resting pose and
## stays frozen; after a tank change the recovery ease runs even while paused and everything else
## stays frozen. The EventBus relay of the three signals is tested in test_fish_view.gd. Test
## decisions: pure simulation, fixed step 1/60, uids seeded 12345; the clamp is checked with the
## hard limits only (glass, water line minus extent, substrate plus extent and bottom clearance).

const Api := preload("res://tests/helpers/fish_swim_api.gd")
const FishApi := preload("res://tests/helpers/fish_api.gd")
const Rig := preload("res://tests/helpers/fish_swim_rig.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")

const SECOND := 60
const SAND_DEPTH := 0.03


func _crowd() -> Rig.Setup:
	var setup: Rig.Setup = Rig.open(Rig.LARGE, Rig.mixed(4, 2, 3))
	assert_object(setup).override_failure_message("the steering classes are missing").is_not_null()
	return setup


func _one(id: StringName) -> Rig.Setup:
	var setup: Rig.Setup = Rig.open(Rig.LARGE, Rig.crowd(id, 1))
	assert_object(setup).override_failure_message("the steering classes are missing").is_not_null()
	return setup


func _same(a: Rig.Observer, b: Rig.Observer) -> String:
	for index: int in a.count:
		if (
			a.position[index] != b.position[index]
			or a.yaw[index] != b.yaw[index]
			or a.speed[index] != b.speed[index]
			or a.yaw_rate[index] != b.yaw_rate[index]
			or a.pitch[index] != b.pitch[index]
			or a.shader_speed[index] != b.shader_speed[index]
			or a.mode[index] != b.mode[index]
			or a.darts[index] != b.darts[index]
		):
			return "fish %d changed" % index
	return ""


# --- pause ---


func test_35_paused_freezes_positions_headings_shader_speed_and_darts() -> void:
	var setup: Rig.Setup = _crowd()
	if setup == null:
		return
	Rig.run(setup, 30.0)
	setup.sim.call("set_paused", true)
	assert_bool(setup.sim.call("is_paused")).is_true()
	var frozen: Rig.Observer = Rig.Observer.new(setup)
	var now: Rig.Observer = Rig.Observer.new(setup)
	frozen.read()
	var low_times: PackedFloat64Array = PackedFloat64Array()
	for member: Rig.Member in setup.members:
		low_times.append(Api.number(Rig.state_of(setup, member.uid), "low_speed_time"))
	for second: int in 120:
		Rig.run(setup, 1.0)
		now.read()
		(
			assert_str(_same(frozen, now))
			. override_failure_message("a fish moved while paused at %d s" % second)
			. is_empty()
		)
	for index: int in setup.members.size():
		var state: Object = Rig.state_of(setup, setup.members[index].uid)
		(
			assert_float(Api.number(state, "low_speed_time"))
			. override_failure_message("the stuck timer runs while paused")
			. is_equal(low_times[index])
		)
	assert_bool(setup.sim.call("is_paused")).is_true()


func test_35_clearing_pause_continues_from_where_the_fish_were_without_a_jump() -> void:
	var setup: Rig.Setup = _crowd()
	if setup == null:
		return
	Rig.run(setup, 30.0)
	var obs: Rig.Observer = Rig.Observer.new(setup)
	var smooth: Rig.Smooth = Rig.Smooth.new(setup.members)
	obs.read()
	smooth.check(obs, 0.0, Rig.STEP)
	setup.sim.call("set_paused", true)
	Rig.run(setup, 200.0)
	setup.sim.call("set_paused", false)
	assert_bool(setup.sim.call("is_paused")).is_false()
	var prior: Rig.Observer = Rig.Observer.new(setup)
	prior.read()
	for index: int in 20 * SECOND:
		setup.sim.call("step", Rig.STEP)
		obs.read()
		smooth.check(obs, (index + 1) * Rig.STEP, Rig.STEP)
		if index == 0:
			for fish: int in obs.count:
				var member: Rig.Member = setup.members[fish]
				(
					assert_float(obs.position[fish].distance_to(prior.position[fish]))
					. override_failure_message("%s jumped on resume" % member.uid)
					. is_less_equal(member.top * Rig.SPEED_FACTOR_MAX * Rig.STEP + 1e-7)
				)
	assert_int(smooth.total()).override_failure_message(smooth.report()).is_equal(0)


func test_35_a_pause_does_not_advance_the_timers_so_the_run_continues_as_if_nothing_happened(
) -> void:
	var plain: Rig.Setup = _crowd()
	var paused: Rig.Setup = _crowd()
	if plain == null or paused == null:
		return
	Rig.run(plain, 30.0)
	Rig.run(paused, 30.0)
	paused.sim.call("set_paused", true)
	Rig.run(paused, 90.0)
	paused.sim.call("set_paused", false)
	Rig.run(plain, 60.0)
	Rig.run(paused, 60.0)
	var one: Rig.Observer = Rig.Observer.new(plain)
	var two: Rig.Observer = Rig.Observer.new(paused)
	one.read()
	two.read()
	for index: int in one.count:
		(
			assert_vector(two.position[index])
			. override_failure_message("fish %d differs after a pause" % index)
			. is_equal_approx(one.position[index], Vector3.ONE * 1e-9)
		)
		assert_int(two.darts[index]).is_equal(one.darts[index])


# --- override ---


func _override_run(id: StringName, target: Vector3) -> Dictionary:
	var setup: Rig.Setup = _one(id)
	if setup == null:
		return {}
	var uid: String = setup.members[0].uid
	var member: Rig.Member = setup.members[0]
	setup.sim.call("set_override", uid, target)
	var obs: Rig.Observer = Rig.Observer.new(setup)
	var smooth: Rig.Smooth = Rig.Smooth.new(setup.members)
	var limits: Rig.Limits = Rig.Limits.new(setup)
	var modes: Dictionary[int, bool] = {}
	var arrived: float = INF
	var fastest: float = 0.0
	for index: int in 90 * SECOND:
		setup.sim.call("step", Rig.STEP)
		obs.read()
		var time: float = (index + 1) * Rig.STEP
		smooth.check(obs, time, Rig.STEP)
		limits.check(obs, time, false)
		modes[obs.mode[0]] = true
		fastest = maxf(fastest, obs.speed[0])
		if arrived == INF and obs.position[0].distance_to(target) < 0.03:
			arrived = time
	return {
		"setup": setup,
		"member": member,
		"obs": obs,
		"smooth": smooth,
		"limits": limits,
		"modes": modes,
		"arrived": arrived,
		"fastest": fastest,
		"uid": uid,
	}


func test_35_an_overridden_fish_moves_to_the_target_without_idle_or_dart_and_keeps_its_caps(
) -> void:
	var targets: Dictionary[StringName, Vector3] = {
		FishApi.NEON: Vector3(0.30, 0.22, 0.05),
		FishApi.ANGEL: Vector3(-0.28, 0.25, -0.05),
		FishApi.CORY: Vector3(0.25, 0.07, 0.10),
	}
	for id: StringName in targets:
		var run: Dictionary = _override_run(id, targets[id])
		if run.is_empty():
			return
		var member: Rig.Member = run["member"]
		(
			assert_float(run["arrived"])
			. override_failure_message("%s never reached the override target" % id)
			. is_less_equal(60.0)
		)
		var modes: Dictionary = run["modes"]
		assert_bool(modes.has(Api.mode_id("OVERRIDE"))).is_true()
		(
			assert_bool(modes.has(Api.mode_id("IDLE")))
			. override_failure_message("idle while overridden")
			. is_false()
		)
		(
			assert_bool(modes.has(Api.mode_id("DART")))
			. override_failure_message("dart while overridden")
			. is_false()
		)
		(
			assert_float(run["fastest"])
			. override_failure_message("%s faster than top speed" % id)
			. is_less_equal(member.top + 1e-7)
		)
		var smooth: Rig.Smooth = run["smooth"]
		assert_int(smooth.total()).override_failure_message(smooth.report()).is_equal(0)
		var limits: Rig.Limits = run["limits"]
		assert_int(limits.total()).override_failure_message(limits.report()).is_equal(0)


func test_35_clearing_the_override_returns_to_normal_swimming_without_a_jump() -> void:
	var run: Dictionary = _override_run(FishApi.NEON, Vector3(0.30, 0.22, 0.05))
	if run.is_empty():
		return
	var setup: Rig.Setup = run["setup"]
	var obs: Rig.Observer = run["obs"]
	var smooth: Rig.Smooth = run["smooth"]
	setup.sim.call("clear_override", run["uid"])
	var modes: Dictionary[int, bool] = {}
	var start: Vector3 = obs.position[0]
	var farthest: float = 0.0
	for index: int in 120 * SECOND:
		setup.sim.call("step", Rig.STEP)
		obs.read()
		smooth.check(obs, 90.0 + (index + 1) * Rig.STEP, Rig.STEP)
		modes[obs.mode[0]] = true
		farthest = maxf(farthest, obs.position[0].distance_to(start))
		if index == 0:
			assert_int(obs.mode[0]).override_failure_message("still overridden").is_not_equal(
				Api.mode_id("OVERRIDE")
			)
	assert_bool(modes.has(Api.mode_id("OVERRIDE"))).is_false()
	assert_bool(modes.has(Api.mode_id("CRUISE"))).is_true()
	assert_float(farthest).override_failure_message("the fish stayed at the old target").is_greater(
		0.1
	)
	assert_int(smooth.total()).override_failure_message(smooth.report()).is_equal(0)


func test_35_two_overridden_fish_with_one_target_still_keep_a_separation() -> void:
	var setup: Rig.Setup = Rig.open(Rig.LARGE, Rig.crowd(FishApi.NEON, 2))
	if setup == null:
		assert_bool(false).override_failure_message("the steering classes are missing").is_true()
		return
	var target: Vector3 = Vector3(0.2, 0.2, 0.0)
	for member: Rig.Member in setup.members:
		setup.sim.call("set_override", member.uid, target)
	var obs: Rig.Observer = Rig.Observer.new(setup)
	var closest: float = INF
	for index: int in 90 * SECOND:
		setup.sim.call("step", Rig.STEP)
		obs.read()
		if index > 60 * SECOND:
			closest = minf(closest, obs.position[0].distance_to(obs.position[1]))
	var half_sum: float = setup.members[0].length_m
	(
		assert_float(closest)
		. override_failure_message("the two merged: %.4f m" % closest)
		. is_greater_equal(half_sum * 0.9)
	)


func test_35_a_target_outside_the_tank_is_clamped_to_the_nearest_valid_point() -> void:
	var run: Dictionary = _override_run(FishApi.NEON, Vector3(5.0, 5.0, 5.0))
	if run.is_empty():
		return
	var setup: Rig.Setup = run["setup"]
	var member: Rig.Member = run["member"]
	var obs: Rig.Observer = run["obs"]
	var radius: float = float(member.extents.get("horizontal_radius_m"))
	var above: float = float(member.extents.get("above_m"))
	var at: Vector3 = obs.position[0]
	assert_float(at.x).is_greater(setup.interior.x / 2.0 - radius - 0.03)
	assert_float(at.z).is_greater(setup.interior.z / 2.0 - radius - 0.03)
	assert_float(at.y).is_greater(setup.water_line - above - 0.03)
	var limits: Rig.Limits = run["limits"]
	assert_int(limits.total()).override_failure_message(limits.report()).is_equal(0)


func test_35_a_target_below_the_substrate_is_clamped_above_the_bed() -> void:
	var run: Dictionary = _override_run(FishApi.CORY, Vector3(0.0, -1.0, 0.0))
	if run.is_empty():
		return
	var setup: Rig.Setup = run["setup"]
	var member: Rig.Member = run["member"]
	var floor_y: float = (
		SAND_DEPTH + maxf(0.01, float(member.extents.get("below_m"))) + setup.allowance
	)
	var obs: Rig.Observer = run["obs"]
	(
		assert_float(obs.position[0].y)
		. override_failure_message("below the bed clearance")
		. is_greater_equal(floor_y - 1e-9)
	)
	(
		assert_float(obs.position[0].y)
		. override_failure_message("did not reach the floor")
		. is_less_equal(floor_y + 0.03)
	)
	var limits: Rig.Limits = run["limits"]
	assert_int(limits.total()).override_failure_message(limits.report()).is_equal(0)


func test_35_the_zone_band_does_not_apply_while_overridden_a_bottom_fish_may_go_to_the_surface(
) -> void:
	var run: Dictionary = _override_run(FishApi.CORY, Vector3(0.0, 0.45, 0.0))
	if run.is_empty():
		return
	var obs: Rig.Observer = run["obs"]
	assert_float(obs.position[0].y).override_failure_message("held in the bottom band").is_greater(
		0.40
	)


func test_35_an_override_for_an_unknown_fish_or_a_fish_without_one_is_harmless() -> void:
	var setup: Rig.Setup = _crowd()
	if setup == null:
		return
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void:
			setup.sim.call("set_override", "nobody", Vector3.ZERO)
			setup.sim.call("clear_override", "nobody")
			setup.sim.call("clear_override", setup.members[0].uid)
			Rig.run(setup, 2.0)
	)
	assert_dict(seen["errors"]).override_failure_message("errors: %s" % [seen["errors"]]).is_empty()
	(
		assert_dict(seen["warnings"])
		. override_failure_message("warnings: %s" % [seen["warnings"]])
		. is_empty()
	)


# --- override and add while paused ---


func test_35_an_override_set_while_paused_is_stored_and_applies_on_resume() -> void:
	var setup: Rig.Setup = _one(FishApi.NEON)
	if setup == null:
		return
	var uid: String = setup.members[0].uid
	Rig.run(setup, 10.0)
	setup.sim.call("set_paused", true)
	var target: Vector3 = Vector3(-0.3, 0.2, -0.1)
	setup.sim.call("set_override", uid, target)
	var obs: Rig.Observer = Rig.Observer.new(setup)
	obs.read()
	var frozen_at: Vector3 = obs.position[0]
	Rig.run(setup, 5.0)
	obs.read()
	assert_vector(obs.position[0]).override_failure_message("moved while paused").is_equal(
		frozen_at
	)
	setup.sim.call("set_paused", false)
	Rig.run(setup, 60.0)
	obs.read()
	(
		assert_float(obs.position[0].distance_to(target))
		. override_failure_message("did not go to the stored target")
		. is_less(0.05)
	)


func test_35_a_fish_added_while_paused_appears_at_its_resting_pose_and_stays_frozen() -> void:
	var setup: Rig.Setup = _crowd()
	if setup == null:
		return
	Rig.run(setup, 10.0)
	setup.sim.call("set_paused", true)
	var uid: String = Rig.uids(1, 4242)[0]
	var added: Rig.Member = Rig.add(setup, Rig.entry(FishApi.NEON, uid))
	assert_object(added).is_not_null()
	if added == null:
		return
	var rest: Object = Rig.rest_pose(setup, added)
	Rig.run(setup, 5.0)
	var state: Object = Rig.state_of(setup, uid)
	assert_vector(state.get("position")).is_equal_approx(rest.get("position"), Vector3.ONE * 1e-6)
	assert_float(float(state.get("speed"))).is_equal(0.0)
	setup.sim.call("set_paused", false)
	Rig.run(setup, 20.0)
	var moved: Object = Rig.state_of(setup, uid)
	assert_float((moved.get("position") as Vector3).distance_to(rest.get("position"))).is_greater(
		0.01
	)


func test_35_a_tank_change_while_paused_runs_the_recovery_and_freezes_everything_else() -> void:
	var setup: Rig.Setup = _crowd()
	if setup == null:
		return
	Rig.run(setup, 20.0)
	setup.sim.call("set_paused", true)
	Rig.change_tank(setup, Rig.SMALL)
	var obs: Rig.Observer = Rig.Observer.new(setup)
	var start: Rig.Observer = Rig.Observer.new(setup)
	start.read()
	var recovered: PackedByteArray = PackedByteArray()
	recovered.resize(obs.count)
	for _index: int in roundi(2.0 / Rig.STEP) + 1:
		setup.sim.call("step", Rig.STEP)
		obs.read()
		for fish: int in obs.count:
			if obs.recovering[fish] == 1:
				recovered[fish] = 1
	var limits: Rig.Limits = Rig.Limits.new(setup)
	limits.check(obs, 2.0)
	(
		assert_int(limits.total())
		. override_failure_message(
			"a fish stays outside the water while paused: %s" % limits.report()
		)
		. is_equal(0)
	)
	var moving: int = 0
	for fish: int in obs.count:
		if recovered[fish] == 1:
			moving += 1
		else:
			(
				assert_vector(obs.position[fish])
				. override_failure_message("a fish that needed no recovery moved while paused")
				. is_equal(start.position[fish])
			)
	assert_int(moving).override_failure_message("no fish had to recover").is_greater(0)
