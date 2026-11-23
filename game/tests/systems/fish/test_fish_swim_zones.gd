extends GdUnitTestSuite
## #35 zones and tank limits (owner: developer): a swimming fish of any species stays, for 10
## simulated minutes, inside the FishZones.origin_range of its zone at its current x/z (with its
## depth preference applied) with a steering overshoot of at most 1 cm at the band edges only; the
## hard limits (glass, water line minus the extent, substrate height plus extent and bottom
## clearance) have no tolerance (BA decision Q4). Over an uneven bed (up to 6 cm) a bottom fish
## rises with the bed and keeps the ADR 0013 rule 7 clearance. A fish the column cannot hold
## (pinned) hovers at the pinned height with small sideways motion, does not jitter and stays in the
## tank. Test decisions: the 10-minute runs are shared with the feel tests (fish_swim_runs.gd, 20
## fish per species, large tank, fixed step 1/60, seeded 12345 and 777); the zone checker reads
## every step. The pinned fish is a copy of the angelfish at 18 cm (the real angelfish is not pinned
## in any shipped tank, only a species the column cannot hold is); its model is the angelfish model.

const FishApi := preload("res://tests/helpers/fish_api.gd")
const Rig := preload("res://tests/helpers/fish_swim_rig.gd")
const Runs := preload("res://tests/helpers/fish_swim_runs.gd")

const MOUND_PEAK_M := 0.06
const FLOOR_M := 0.03
const MOUND_SIGMA_M := 0.12


func _run(id: StringName) -> Dictionary:
	var result: Dictionary = Runs.feel(id, Rig.STEP)
	(
		assert_bool(result.get("ok", false))
		. override_failure_message("the steering classes are missing")
		. is_true()
	)
	return result


func _no_violations(id: StringName) -> void:
	var run: Dictionary = _run(id)
	if not run.get("ok", false):
		return
	var limits: Rig.Limits = run["limits"]
	(
		assert_int(limits.total())
		. override_failure_message("%s left its zone or the tank: %s" % [id, limits.report()])
		. is_equal(0)
	)


func test_35_neon_tetras_stay_in_the_middle_band_and_the_tank_for_10_minutes() -> void:
	_no_violations(FishApi.NEON)


func test_35_angelfish_stay_in_the_middle_band_and_the_tank_for_10_minutes() -> void:
	_no_violations(FishApi.ANGEL)


func test_35_corydoras_stay_in_the_bottom_band_and_the_tank_for_10_minutes() -> void:
	_no_violations(FishApi.CORY)


func test_35_the_tetras_and_the_corydoras_really_use_their_own_zones() -> void:
	var neon: Dictionary = _run(FishApi.NEON)
	var cory: Dictionary = _run(FishApi.CORY)
	if not neon.get("ok", false) or not cory.get("ok", false):
		return
	var neon_height: float = Rig.mean(neon["mean_height"])
	var cory_height: float = Rig.mean(cory["mean_height"])
	assert_float(neon_height).is_greater(cory_height + 0.05)
	assert_float(cory_height).is_less(0.15)


# --- uneven bed ---


func _mound(x: float, z: float) -> float:
	var distance_squared: float = x * x + z * z
	var rise: float = (MOUND_PEAK_M - FLOOR_M) * exp(-distance_squared / (2.0 * MOUND_SIGMA_M ** 2))
	return FLOOR_M + rise


func test_35_a_bottom_fish_rises_with_a_6_cm_mound_and_keeps_the_bottom_clearance() -> void:
	var setup: Rig.Setup = Rig.open(Rig.LARGE, Rig.crowd(FishApi.CORY, 6), _mound)
	assert_object(setup).override_failure_message("the steering classes are missing").is_not_null()
	if setup == null:
		return
	var obs: Rig.Observer = Rig.Observer.new(setup)
	var limits: Rig.Limits = Rig.Limits.new(setup)
	var over_mound: PackedFloat64Array = PackedFloat64Array()
	var away: PackedFloat64Array = PackedFloat64Array()
	var lowest_clearance: float = INF
	var steps: int = 300 * 60
	for index: int in steps:
		setup.sim.call("step", Rig.STEP)
		obs.read()
		limits.check(obs, (index + 1) * Rig.STEP)
		for fish: int in obs.count:
			var at: Vector3 = obs.position[fish]
			var bed: float = _mound(at.x, at.z)
			lowest_clearance = minf(lowest_clearance, at.y - bed)
			if Vector2(at.x, at.z).length() < 0.08:
				over_mound.append(at.y)
			elif Vector2(at.x, at.z).length() > 0.30:
				away.append(at.y)
	assert_int(limits.total()).override_failure_message(limits.report()).is_equal(0)
	var member: Rig.Member = setup.members[0]
	var clearance: float = maxf(0.01, float(member.extents.get("below_m"))) + setup.allowance
	(
		assert_float(lowest_clearance)
		. override_failure_message("a fish came closer than the rule 7 clearance to the bed")
		. is_greater_equal(clearance - 1e-9)
	)
	assert_int(over_mound.size()).override_failure_message("nobody crossed the mound").is_greater(
		100
	)
	assert_int(away.size()).override_failure_message("nobody swam away from the mound").is_greater(
		100
	)
	if over_mound.size() > 100 and away.size() > 100:
		(
			assert_float(Rig.mean(over_mound))
			. override_failure_message("fish over the mound are not higher than fish away from it")
			. is_greater(Rig.mean(away) + 0.008)
		)


func test_35_the_swim_floor_is_the_substrate_height_never_zero() -> void:
	var setup: Rig.Setup = Rig.open(Rig.LARGE, Rig.crowd(FishApi.CORY, 6), _mound)
	if setup == null:
		assert_bool(false).override_failure_message("the steering classes are missing").is_true()
		return
	var obs: Rig.Observer = Rig.Observer.new(setup)
	var lowest: float = INF
	for _step: int in 60 * 60:
		setup.sim.call("step", Rig.STEP)
		obs.read()
		for fish: int in obs.count:
			lowest = minf(lowest, obs.position[fish].y)
	(
		assert_float(lowest)
		. override_failure_message("the swim floor is 0 or inside the bed")
		. is_greater(FLOOR_M)
	)


# --- pinned ---


func test_35_edge_a_pinned_fish_hovers_with_small_sideways_motion_and_stays_in_the_tank() -> void:
	var giant: Resource = Rig.pinned_species()
	if giant == null:
		assert_bool(false).override_failure_message("FishSpecies is missing").is_true()
		return
	var uid: String = Rig.uids(1)[0]
	var setup: Rig.Setup = Rig.open(Rig.SMALL, [Rig.pinned_entry(uid)])
	assert_object(setup).override_failure_message("the steering classes are missing").is_not_null()
	if setup == null:
		return
	var rest: Object = Rig.rest_pose(setup, setup.members[0])
	(
		assert_bool(bool(rest.get("pinned")))
		. override_failure_message("the 18 cm angelfish must be pinned in the small tank")
		. is_true()
	)
	var obs: Rig.Observer = Rig.Observer.new(setup)
	var smooth: Rig.Smooth = Rig.Smooth.new(setup.members)
	var limits: Rig.Limits = Rig.Limits.new(setup)
	var start: Vector3 = rest.get("position")
	var farthest: float = 0.0
	var pinned_seen: bool = true
	for index: int in 30 * 60:
		setup.sim.call("step", Rig.STEP)
		obs.read()
		var time: float = (index + 1) * Rig.STEP
		smooth.check(obs, time, Rig.STEP)
		limits.check(obs, time)
		farthest = maxf(farthest, obs.position[0].distance_to(start))
		pinned_seen = pinned_seen and obs.pinned[0] == 1
		assert_bool(Rig.inside_tank(setup, obs.position[0])).is_true()
	assert_bool(pinned_seen).override_failure_message("state.pinned is not true").is_true()
	assert_float(farthest).override_failure_message("a pinned fish wandered").is_less_equal(0.02)
	assert_int(smooth.total()).override_failure_message(smooth.report()).is_equal(0)
	assert_int(limits.total()).override_failure_message(limits.report()).is_equal(0)
