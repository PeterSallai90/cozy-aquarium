extends GdUnitTestSuite
## #35 fish separation (owner: developer; BA decision Q10): in the large tank with 30 neon tetras,
## 15 bronze corydoras and 15 angelfish (random uids, 30 s settling, then 60 s measured at 1/60 s
## steps) no pair of non-pinned fish has origins closer than the sum of their half-lengths
## (adult_length_cm / 2 each) for more than 0.5 simulated seconds in total. A pinned fish is
## excluded and never moves away: only the other fish yield. In the small tank (40 x 25 cm) with one
## pinned fish and three tetras the pinned fish moves at most 2 cm in 30 s, does not oscillate (the
## heading flip rule of Q5) and nobody leaves the tank. Smoke: 60 fish in the small tank, nobody
## leaves the tank, no separation assertion; the step time is only logged (the frame budget is #49).
## Test decisions: the pinned fish is a copy of the angelfish at 18 cm (no shipped species is pinned
## in a shipped tank); the 60-fish run reports the mean step time with print().

const FishApi := preload("res://tests/helpers/fish_api.gd")
const Rig := preload("res://tests/helpers/fish_swim_rig.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")

const SETTLE_STEPS := 30 * 60
const MEASURE_STEPS := 60 * 60
const PINNED_STEPS := 30 * 60
const SMOKE_STEPS := 30 * 60


func test_35_sixty_fish_in_the_large_tank_keep_their_personal_space() -> void:
	var setup: Rig.Setup = Rig.open(Rig.LARGE, Rig.mixed(30, 15, 15))
	assert_object(setup).override_failure_message("the steering classes are missing").is_not_null()
	if setup == null:
		return
	assert_int(setup.members.size()).is_equal(60)
	var obs: Rig.Observer = Rig.Observer.new(setup)
	var smooth: Rig.Smooth = Rig.Smooth.new(setup.members)
	var limits: Rig.Limits = Rig.Limits.new(setup)
	var pairs: Rig.Pairs = Rig.Pairs.new(setup)
	var started: int = Time.get_ticks_msec()
	for index: int in SETTLE_STEPS + MEASURE_STEPS:
		setup.sim.call("step", Rig.STEP)
		obs.read()
		var time: float = (index + 1) * Rig.STEP
		smooth.check(obs, time, Rig.STEP)
		limits.check(obs, time, false)
		if index >= SETTLE_STEPS:
			pairs.observe(obs, Rig.STEP)
	print(
		(
			"FishSwim 60 fish large tank: %d ms for %d steps"
			% [Time.get_ticks_msec() - started, SETTLE_STEPS + MEASURE_STEPS]
		)
	)
	(
		assert_float(pairs.worst())
		. override_failure_message("a pair stayed too close: %s" % pairs.report())
		. is_less_equal(0.5)
	)
	assert_int(limits.total()).override_failure_message(limits.report()).is_equal(0)
	assert_int(smooth.total()).override_failure_message(smooth.report()).is_equal(0)


func test_35_a_pinned_angelfish_among_three_tetras_moves_at_most_2_cm_and_does_not_oscillate(
) -> void:
	var giant: Resource = Rig.pinned_species()
	if giant == null:
		assert_bool(false).override_failure_message("FishSpecies is missing").is_true()
		return
	var uids: Array[String] = Rig.uids(4)
	var entries: Array = [Rig.pinned_entry(uids[0])]
	for index: int in 3:
		entries.append(Rig.entry(FishApi.NEON, uids[index + 1]))
	var setup: Rig.Setup = Rig.open(Rig.SMALL, entries)
	assert_object(setup).override_failure_message("the steering classes are missing").is_not_null()
	if setup == null:
		return
	var obs: Rig.Observer = Rig.Observer.new(setup)
	var smooth: Rig.Smooth = Rig.Smooth.new(setup.members)
	obs.read()
	var start: Vector3 = obs.position[0]
	var farthest: float = 0.0
	var outside: int = 0
	for index: int in PINNED_STEPS:
		setup.sim.call("step", Rig.STEP)
		obs.read()
		smooth.check(obs, (index + 1) * Rig.STEP, Rig.STEP)
		farthest = maxf(farthest, obs.position[0].distance_to(start))
		for fish: int in obs.count:
			if not Rig.inside_tank(setup, obs.position[fish]):
				outside += 1
	(
		assert_int(obs.pinned[0])
		. override_failure_message("the 18 cm angelfish is not pinned")
		. is_equal(1)
	)
	(
		assert_float(farthest)
		. override_failure_message("the pinned fish moved %.3f m" % farthest)
		. is_less_equal(0.02)
	)
	assert_int(outside).override_failure_message("a fish left the tank").is_equal(0)
	assert_int(smooth.total()).override_failure_message(smooth.report()).is_equal(0)


func test_35_smoke_sixty_fish_in_the_small_tank_nobody_leaves_the_tank() -> void:
	var holder: Array = []
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void: holder.append(Rig.open(Rig.SMALL, Rig.mixed(30, 15, 15)))
	)
	var setup: Rig.Setup = holder[0]
	assert_object(setup).override_failure_message("the steering classes are missing").is_not_null()
	if setup == null:
		return
	assert_dict(seen["errors"]).is_empty()
	var obs: Rig.Observer = Rig.Observer.new(setup)
	var outside: Array[int] = [0]
	var started: int = Time.get_ticks_msec()
	var run_seen: Dictionary = await EngineOutput.capture(
		func() -> void:
			for _index: int in SMOKE_STEPS:
				setup.sim.call("step", Rig.STEP)
				obs.read()
				for fish: int in obs.count:
					if not Rig.inside_tank(setup, obs.position[fish]):
						outside[0] += 1
	)
	var elapsed: int = Time.get_ticks_msec() - started
	print("FishSwim 60 fish small tank: %.3f ms per step" % (float(elapsed) / SMOKE_STEPS))
	(
		assert_dict(run_seen["errors"])
		. override_failure_message("errors: %s" % [run_seen["errors"]])
		. is_empty()
	)
	assert_int(outside[0]).override_failure_message("a fish left the small tank").is_equal(0)
