extends GdUnitTestSuite
## #35 group style and schooling (owner: developer; BA decisions Q1, Q2 and Q8): in the large tank
## (100 x 40 cm), starting from the ADR 0013 resting poses of random uids, after a settling time of
## 30 simulated seconds and sampled every second until 120 s, 8 neon tetras stay within 3 body
## lengths (adult_length_cm) of their nearest school-mate on average and their heading changes over
## time; 4 angelfish keep at least 2 body lengths and at least 0.75 more than the tetras; 6 bronze
## corydoras stay in the bottom band, move as a small group and pause often; groups form only within
## a species and different species keep a personal-space distance and never chase or flee each
## other; a single fish swims on its own without oscillating and a second fish of its species
## (up to the tank length apart) is within 3 body lengths within 30 s and stays there on average,
## also for 2 corydoras; fish added or removed (undo and redo too) never make the others jump.
## SOLITARY and UNSET species get no group forces (personal space only) and UNSET behaves exactly
## like SOLITARY without any error. All numbers are (tuning); the structure does not change.
## Test decisions: tests run on the pure simulation at a fixed step 1/60 s with uids from a
## RandomNumberGenerator seeded 12345 and the steering source seeded 777; the "no chase or flee"
## measure is the mean cosine between a fish velocity and the direction to a nearby fish of another
## species (within 4 body lengths, above 10 percent of top speed), which must stay near 0.

const Api := preload("res://tests/helpers/fish_swim_api.gd")
const FishApi := preload("res://tests/helpers/fish_api.gd")
const Rig := preload("res://tests/helpers/fish_swim_rig.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")

const SETTLE_S := 30
const END_S := 120
const NEAR_BL := 3.0
const ANGEL_MIN_BL := 2.0
const ANGEL_GAP_BL := 0.75
const SECOND_FISH_S := 30.0
const CHASE_LIMIT := 0.4
const CHASE_RANGE_BL := 4.0
const FAR_APART_M := 0.7

static var _schools: Dictionary = {}


## {"ok", "mean_bl", "heading_span_deg", "pair_range_bl", "idle_share", "limits", "smooth"} of
## `count` fish of one species schooling from their rest poses (cached per species and count).
func _school(id: StringName, count: int) -> Dictionary:
	var key: String = "%s/%d" % [id, count]
	if not _schools.has(key):
		_schools[key] = _simulate_school(id, count)
	return _schools[key]


func _simulate_school(id: StringName, count: int) -> Dictionary:
	var setup: Rig.Setup = Rig.open(Rig.LARGE, Rig.crowd(id, count))
	if setup == null:
		return {"ok": false}
	var obs: Rig.Observer = Rig.Observer.new(setup)
	var smooth: Rig.Smooth = Rig.Smooth.new(setup.members)
	var limits: Rig.Limits = Rig.Limits.new(setup)
	var length: float = setup.members[0].length_m
	var idle_mode: int = Api.mode_id("IDLE")
	var idle_steps: int = 0
	var all_steps: int = 0
	var nearest_sum: float = 0.0
	var samples: int = 0
	var headings: PackedFloat64Array = PackedFloat64Array()
	var pair_low: float = INF
	var pair_high: float = 0.0
	for index: int in END_S * 60:
		setup.sim.call("step", Rig.STEP)
		var time: float = (index + 1) * Rig.STEP
		obs.read()
		smooth.check(obs, time, Rig.STEP)
		limits.check(obs, time)
		if index + 1 <= SETTLE_S * 60:
			continue
		for fish: int in count:
			all_steps += 1
			if obs.mode[fish] == idle_mode:
				idle_steps += 1
		if (index + 1) % 60 != 0:
			continue
		var nearest: PackedFloat64Array = Rig.nearest_same_species(setup, obs)
		nearest_sum += Rig.mean(nearest) / length
		samples += 1
		var direction: Vector2 = Vector2.ZERO
		for fish: int in count:
			direction += Vector2(sin(obs.yaw[fish]), cos(obs.yaw[fish]))
		headings.append(direction.angle())
		if count > 1:
			var apart: float = obs.position[0].distance_to(obs.position[1]) / length
			pair_low = minf(pair_low, apart)
			pair_high = maxf(pair_high, apart)
	var widest: float = 0.0
	for first: float in headings:
		for second: float in headings:
			widest = maxf(widest, absf(rad_to_deg(wrapf(first - second, -PI, PI))))
	return {
		"ok": true,
		"mean_bl": nearest_sum / maxi(samples, 1),
		"heading_span_deg": widest,
		"pair_range_bl": pair_high - pair_low,
		"idle_share": float(idle_steps) / maxf(float(all_steps), 1.0),
		"limits": limits,
		"smooth": smooth,
	}


func _need(run: Dictionary) -> bool:
	(
		assert_bool(run.get("ok", false))
		. override_failure_message("the steering classes are missing")
		. is_true()
	)
	return run.get("ok", false)


func test_35_eight_neon_tetras_stay_within_3_body_lengths_of_their_nearest_school_mate() -> void:
	var run: Dictionary = _school(FishApi.NEON, 8)
	if not _need(run):
		return
	(
		assert_float(run["mean_bl"])
		. override_failure_message("mean nearest school-mate %.2f body lengths" % run["mean_bl"])
		. is_less_equal(NEAR_BL)
	)
	assert_int((run["smooth"] as Rig.Smooth).total()).is_equal(0)
	assert_int((run["limits"] as Rig.Limits).total()).is_equal(0)


func test_35_the_school_heading_changes_and_the_fish_do_not_keep_identical_offsets() -> void:
	var run: Dictionary = _school(FishApi.NEON, 8)
	if not _need(run):
		return
	(
		assert_float(run["heading_span_deg"])
		. override_failure_message("the school never turned: %.1f deg" % run["heading_span_deg"])
		. is_greater_equal(30.0)
	)
	(
		assert_float(run["pair_range_bl"])
		. override_failure_message(
			"two fish keep the same offset: %.2f body lengths" % run["pair_range_bl"]
		)
		. is_greater_equal(0.5)
	)


func test_35_four_angelfish_keep_at_least_2_body_lengths_and_more_than_the_tetras() -> void:
	var angels: Dictionary = _school(FishApi.ANGEL, 4)
	var tetras: Dictionary = _school(FishApi.NEON, 8)
	if not _need(angels) or not _need(tetras):
		return
	(
		assert_float(angels["mean_bl"])
		. override_failure_message("angelfish nearest %.2f body lengths" % angels["mean_bl"])
		. is_greater_equal(ANGEL_MIN_BL)
	)
	(
		assert_float(angels["mean_bl"])
		. override_failure_message(
			(
				"angelfish %.2f against tetras %.2f body lengths"
				% [angels["mean_bl"], tetras["mean_bl"]]
			)
		)
		. is_greater_equal(tetras["mean_bl"] + ANGEL_GAP_BL)
	)
	assert_int((angels["smooth"] as Rig.Smooth).total()).is_equal(0)
	assert_int((angels["limits"] as Rig.Limits).total()).is_equal(0)


func test_35_six_corydoras_stay_in_the_bottom_band_as_a_group_and_pause_often() -> void:
	var cory: Dictionary = _school(FishApi.CORY, 6)
	var tetras: Dictionary = _school(FishApi.NEON, 8)
	if not _need(cory) or not _need(tetras):
		return
	(
		assert_int((cory["limits"] as Rig.Limits).total())
		. override_failure_message((cory["limits"] as Rig.Limits).report())
		. is_equal(0)
	)
	assert_int((cory["smooth"] as Rig.Smooth).total()).is_equal(0)
	assert_float(cory["mean_bl"]).override_failure_message("corydoras nearest").is_less_equal(
		NEAR_BL
	)
	(
		assert_float(cory["idle_share"])
		. override_failure_message("corydoras pause too little")
		. is_greater_equal(0.28)
	)
	assert_float(cory["idle_share"]).is_greater(tetras["idle_share"])


# --- different species ---


func test_35_groups_form_only_within_a_species_and_nobody_chases_or_flees() -> void:
	var setup: Rig.Setup = Rig.open(Rig.LARGE, Rig.mixed(8, 4, 6))
	assert_object(setup).override_failure_message("the steering classes are missing").is_not_null()
	if setup == null:
		return
	var obs: Rig.Observer = Rig.Observer.new(setup)
	var smooth: Rig.Smooth = Rig.Smooth.new(setup.members)
	var pairs: Rig.Pairs = Rig.Pairs.new(setup, true)
	var same: Dictionary[StringName, float] = {}
	var samples: int = 0
	var chase_sum: float = 0.0
	var chase_count: int = 0
	for index: int in END_S * 60:
		setup.sim.call("step", Rig.STEP)
		obs.read()
		smooth.check(obs, (index + 1) * Rig.STEP, Rig.STEP)
		if index + 1 <= SETTLE_S * 60:
			continue
		pairs.observe(obs, Rig.STEP)
		for fish: int in obs.count:
			var member: Rig.Member = setup.members[fish]
			if obs.speed[fish] <= member.top * 0.10:
				continue
			var heading: Vector3 = obs.velocity[fish].normalized()
			for other: int in obs.count:
				var rival: Rig.Member = setup.members[other]
				if rival.species_id == member.species_id:
					continue
				var offset: Vector3 = obs.position[other] - obs.position[fish]
				if offset.length() < CHASE_RANGE_BL * member.length_m:
					chase_sum += heading.dot(offset.normalized())
					chase_count += 1
		if (index + 1) % 60 == 0:
			samples += 1
			var nearest: PackedFloat64Array = Rig.nearest_same_species(setup, obs)
			for fish: int in obs.count:
				var member: Rig.Member = setup.members[fish]
				same[member.species_id] = (
					same.get(member.species_id, 0.0) + (nearest[fish] / member.length_m)
				)
	var per_species: Dictionary[StringName, int] = {
		FishApi.NEON: 8, FishApi.ANGEL: 4, FishApi.CORY: 6
	}
	for id: StringName in [FishApi.NEON, FishApi.CORY]:
		var mean_bl: float = same[id] / samples / per_species[id]
		(
			assert_float(mean_bl)
			. override_failure_message("%s nearest same-species %.2f body lengths" % [id, mean_bl])
			. is_less_equal(NEAR_BL)
		)
	(
		assert_float(pairs.worst())
		. override_failure_message(
			"two species in each other's personal space: %s" % pairs.report()
		)
		. is_less_equal(0.5)
	)
	if chase_count >= 200:
		(
			assert_float(absf(chase_sum / chase_count))
			. override_failure_message(
				"fish chase or flee another species: %.2f" % (chase_sum / chase_count)
			)
			. is_less_equal(CHASE_LIMIT)
		)
	assert_int(smooth.total()).override_failure_message(smooth.report()).is_equal(0)


# --- single fish and a second fish ---


func test_35_a_single_schooling_fish_swims_on_its_own_without_oscillating() -> void:
	for id: StringName in [FishApi.NEON, FishApi.CORY]:
		var setup: Rig.Setup = Rig.open(Rig.LARGE, Rig.crowd(id, 1))
		if setup == null:
			(
				assert_bool(false)
				. override_failure_message("the steering classes are missing")
				. is_true()
			)
			return
		var obs: Rig.Observer = Rig.Observer.new(setup)
		var smooth: Rig.Smooth = Rig.Smooth.new(setup.members)
		var limits: Rig.Limits = Rig.Limits.new(setup)
		var path: float = 0.0
		var last: Vector3 = Vector3.ZERO
		for index: int in END_S * 60:
			setup.sim.call("step", Rig.STEP)
			obs.read()
			smooth.check(obs, (index + 1) * Rig.STEP, Rig.STEP)
			limits.check(obs, (index + 1) * Rig.STEP)
			if index > 0:
				path += obs.position[0].distance_to(last)
			last = obs.position[0]
		assert_int(smooth.total()).override_failure_message(smooth.report()).is_equal(0)
		assert_int(limits.total()).override_failure_message(limits.report()).is_equal(0)
		assert_float(path).override_failure_message("%s hardly moved alone" % id).is_greater(0.5)


func _pair_run(id: StringName) -> void:
	var uids: Array[String] = Rig.uids(2)
	var setup: Rig.Setup = Rig.open(Rig.LARGE, [Rig.entry(id, uids[0])])
	if setup == null:
		assert_bool(false).override_failure_message("the steering classes are missing").is_true()
		return
	Rig.run(setup, 20.0)
	var first: Object = Rig.state_of(setup, uids[0])
	var at: Vector3 = first.get("position")
	var far_x: float = at.x - FAR_APART_M if at.x > 0.0 else at.x + FAR_APART_M
	var second: Rig.Member = Rig.member_of(id, uids[1])
	var span: Object = Api.script_of(FishApi.ZONES_PATH).call(
		"origin_range",
		second.zone,
		setup.surface,
		far_x,
		0.0,
		setup.water_line,
		setup.allowance,
		second.extents
	)
	var height: float = (float(span.get("min_y")) + float(span.get("max_y"))) / 2.0
	Rig.add(setup, Rig.entry(id, uids[1], null, Api.pose_of(Vector3(far_x, height, 0.0), 0.5)))
	var obs: Rig.Observer = Rig.Observer.new(setup)
	var smooth: Rig.Smooth = Rig.Smooth.new(setup.members)
	var near: float = NEAR_BL * setup.members[0].length_m
	var first_within: float = INF
	var after_sum: float = 0.0
	var after_count: int = 0
	for index: int in END_S * 60:
		setup.sim.call("step", Rig.STEP)
		var time: float = (index + 1) * Rig.STEP
		obs.read()
		smooth.check(obs, time, Rig.STEP)
		var apart: float = obs.position[0].distance_to(obs.position[1])
		if apart <= near and first_within == INF:
			first_within = time
		if time > SECOND_FISH_S:
			after_sum += apart
			after_count += 1
	(
		assert_float(first_within)
		. override_failure_message("%s: the two never came within 3 body lengths in 30 s" % id)
		. is_less_equal(SECOND_FISH_S)
	)
	(
		assert_float(after_sum / after_count)
		. override_failure_message("%s: the pair drifted apart afterwards" % id)
		. is_less_equal(near)
	)
	assert_int(smooth.total()).override_failure_message(smooth.report()).is_equal(0)


func test_35_edge_a_second_tetra_added_far_away_joins_within_30_seconds_and_stays() -> void:
	_pair_run(FishApi.NEON)


func test_35_edge_a_second_corydoras_added_far_away_joins_within_30_seconds_and_stays() -> void:
	_pair_run(FishApi.CORY)


# --- add, remove, undo, redo ---


func test_35_adding_and_removing_a_fish_never_makes_the_others_jump() -> void:
	var setup: Rig.Setup = Rig.open(Rig.LARGE, Rig.mixed(5, 3, 3))
	if setup == null:
		assert_bool(false).override_failure_message("the steering classes are missing").is_true()
		return
	Rig.run(setup, 40.0)
	var prior: Rig.Observer = Rig.Observer.new(setup)
	prior.read()
	var newcomer: String = Rig.uids(1, 999)[0]
	var added: Rig.Member = Rig.add(setup, Rig.entry(FishApi.NEON, newcomer))
	assert_object(added).is_not_null()
	if added == null:
		return
	var later: Rig.Observer = Rig.Observer.new(setup)
	later.read()
	for index: int in prior.count:
		(
			assert_vector(later.position[index])
			. override_failure_message("adding a fish moved %s" % setup.members[index].uid)
			. is_equal(prior.position[index])
		)
	(
		assert_float(later.speed[prior.count])
		. override_failure_message("the new fish starts moving")
		. is_equal(0.0)
	)
	var smooth: Rig.Smooth = Rig.Smooth.new(setup.members)
	smooth.check(later, 0.0, Rig.STEP)
	for index: int in 10 * 60:
		setup.sim.call("step", Rig.STEP)
		later.read()
		smooth.check(later, (index + 1) * Rig.STEP, Rig.STEP)
	assert_int(smooth.total()).override_failure_message("after add: %s" % smooth.report()).is_equal(
		0
	)
	var gone: String = setup.members[2].uid
	var kept: Rig.Observer = Rig.Observer.new(setup)
	kept.read()
	var positions: Dictionary[String, Vector3] = {}
	for index: int in kept.count:
		positions[setup.members[index].uid] = kept.position[index]
	Rig.remove(setup, gone)
	(
		assert_object(Rig.state_of(setup, gone))
		. override_failure_message("a removed fish keeps a state")
		. is_null()
	)
	var remaining: Rig.Observer = Rig.Observer.new(setup)
	remaining.read()
	for index: int in remaining.count:
		(
			assert_vector(remaining.position[index])
			. override_failure_message("removing a fish moved %s" % setup.members[index].uid)
			. is_equal(positions[setup.members[index].uid])
		)
	var again: Rig.Smooth = Rig.Smooth.new(setup.members)
	again.check(remaining, 0.0, Rig.STEP)
	for index: int in 10 * 60:
		setup.sim.call("step", Rig.STEP)
		remaining.read()
		again.check(remaining, (index + 1) * Rig.STEP, Rig.STEP)
	(
		assert_int(again.total())
		. override_failure_message("after remove: %s" % again.report())
		. is_equal(0)
	)


func test_35_a_removed_fish_that_comes_back_by_undo_starts_at_its_rest_pose_again() -> void:
	var setup: Rig.Setup = Rig.open(Rig.LARGE, Rig.mixed(3, 2, 2))
	if setup == null:
		assert_bool(false).override_failure_message("the steering classes are missing").is_true()
		return
	Rig.run(setup, 20.0)
	var member: Rig.Member = setup.members[1]
	var entry: Dictionary = Rig.entry(member.species_id, member.uid)
	var rest: Object = Rig.rest_pose(setup, member)
	Rig.remove(setup, member.uid)
	Rig.run(setup, 2.0)
	var back: Rig.Member = Rig.add(setup, entry)
	assert_object(back).is_not_null()
	if back == null:
		return
	var state: Object = Rig.state_of(setup, member.uid)
	assert_vector(state.get("position")).is_equal_approx(rest.get("position"), Vector3.ONE * 1e-6)
	assert_float(float(state.get("speed"))).is_equal(0.0)
	assert_int((setup.sim.call("get_uids") as Array).size()).is_equal(7)


# --- SOLITARY and UNSET ---


func _group_copy(style: int, id: StringName) -> Resource:
	return FishApi.variant_of(FishApi.NEON, {"id": id, "group_style": style, "schooling": false})


func _solo_entries(species: Resource, id: StringName) -> Array:
	var result: Array = []
	for uid: String in Rig.uids(8):
		result.append(Rig.entry(id, uid, species, null, FishApi.NEON))
	return result


func _solo_run(style: int, id: StringName, seconds: int) -> Dictionary:
	var species: Resource = _group_copy(style, id)
	if species == null:
		return {"ok": false}
	var setup: Rig.Setup = Rig.open(Rig.LARGE, _solo_entries(species, id))
	if setup == null:
		return {"ok": false}
	var obs: Rig.Observer = Rig.Observer.new(setup)
	var pairs: Rig.Pairs = Rig.Pairs.new(setup)
	var smooth: Rig.Smooth = Rig.Smooth.new(setup.members)
	var nearest_sum: float = 0.0
	var samples: int = 0
	for index: int in seconds * 60:
		setup.sim.call("step", Rig.STEP)
		obs.read()
		smooth.check(obs, (index + 1) * Rig.STEP, Rig.STEP)
		if index + 1 > SETTLE_S * 60:
			pairs.observe(obs, Rig.STEP)
			if (index + 1) % 60 == 0:
				nearest_sum += (
					Rig.mean(Rig.nearest_same_species(setup, obs)) / setup.members[0].length_m
				)
				samples += 1
	return {
		"ok": true,
		"mean_bl": nearest_sum / maxi(samples, 1),
		"pairs": pairs,
		"smooth": smooth,
		"obs": obs,
		"setup": setup,
	}


func test_35_a_solitary_species_has_no_group_forces_and_keeps_its_personal_space() -> void:
	var holder: Array = []
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void: holder.append(_solo_run(Api.STYLE_SOLITARY, &"solo_tetra", END_S))
	)
	var run: Dictionary = holder[0]
	var school: Dictionary = _school(FishApi.NEON, 8)
	if not _need(run) or not _need(school):
		return
	assert_dict(seen["errors"]).override_failure_message("errors: %s" % [seen["errors"]]).is_empty()
	(
		assert_dict(seen["warnings"])
		. override_failure_message("warnings: %s" % [seen["warnings"]])
		. is_empty()
	)
	(
		assert_float(run["mean_bl"])
		. override_failure_message(
			(
				"solitary %.2f against the tight school %.2f body lengths"
				% [run["mean_bl"], school["mean_bl"]]
			)
		)
		. is_greater(school["mean_bl"] * 1.3)
	)
	var pairs: Rig.Pairs = run["pairs"]
	(
		assert_float(pairs.worst())
		. override_failure_message("personal space broken: %s" % pairs.report())
		. is_less_equal(0.5)
	)
	assert_int((run["smooth"] as Rig.Smooth).total()).is_equal(0)


func test_35_an_unset_group_style_behaves_exactly_like_solitary_without_an_error() -> void:
	var holder: Array = []
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void:
			holder.append(_solo_run(Api.STYLE_UNSET, &"unset_tetra", 60))
			holder.append(_solo_run(Api.STYLE_SOLITARY, &"solo_tetra", 60))
	)
	var unset: Dictionary = holder[0]
	var solitary: Dictionary = holder[1]
	if not _need(unset) or not _need(solitary):
		return
	assert_dict(seen["errors"]).override_failure_message("errors: %s" % [seen["errors"]]).is_empty()
	(
		assert_dict(seen["warnings"])
		. override_failure_message("warnings: %s" % [seen["warnings"]])
		. is_empty()
	)
	var one: Rig.Observer = unset["obs"]
	var two: Rig.Observer = solitary["obs"]
	for index: int in one.count:
		(
			assert_vector(one.position[index])
			. override_failure_message("UNSET and SOLITARY fish %d differ" % index)
			. is_equal_approx(two.position[index], Vector3.ONE * 1e-9)
		)
