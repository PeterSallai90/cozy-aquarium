extends GdUnitTestSuite
## #35 recovery ease (owner: developer; BA decision Q9, ADR 0015 rule 6): when a tank, substrate or
## surface change leaves a fish outside its limits (hard limits, or more than the 1 cm band margin
## outside its band), it is guided to the nearest valid point within 2 simulated seconds for any
## distance up to 1.0 m: the speed ramps smoothly (no velocity step, at least 0.3 s at the start and
## at the end), the recovery speed cap is 6 times the species top speed, the speed cap, acceleration
## cap and head-first rule are exempt, the turn rate cap, the pitch limit and the hard limits are
## not. No teleport, no reset to resting poses. FishSwimSim.begin_recovery(uid) is the one public
## mechanism that B24b (#168) reuses for items placed over a fish. Test decisions: the smoothness
## checker skips only the speed, acceleration and head-first checks of recovering steps; the ramp is
## checked on the speed series of the recovering steps (the speed at 0.15 s after the start and
## before the end is at most 0.6 of the plateau, the first step at most 0.1, the per-step change at
## most the smoothstep slope of 1.5 plateaus per 0.3 s); the pure simulation is the object, the
## scene part is in test_fish_view.gd.

const Api := preload("res://tests/helpers/fish_swim_api.gd")
const FishApi := preload("res://tests/helpers/fish_api.gd")
const Rig := preload("res://tests/helpers/fish_swim_rig.gd")

const LIMIT_S := 2.0
const RAMP_S := 0.3
const SMALL_TANK_X := 0.2
const WIDE := Vector3(2.4, 0.5, 0.4)
const WIDE_WATER := 0.5
const RAISED_BED_M := 0.12
const BED_M := 0.03


func _flat(_x: float, _z: float) -> float:
	return BED_M


func _raised(_x: float, _z: float) -> float:
	return RAISED_BED_M


## Steps `seconds` and returns {"series", "smooth", "ever", "first_normal", "recovering_at_end"}.
func _ease(setup: Rig.Setup, seconds: float, step: float = Rig.STEP) -> Dictionary:
	var obs: Rig.Observer = Rig.Observer.new(setup)
	var smooth: Rig.Smooth = Rig.Smooth.new(setup.members)
	var count: int = setup.members.size()
	var series: Array[PackedFloat64Array] = []
	var first_normal: PackedFloat64Array = PackedFloat64Array()
	var ever: PackedByteArray = PackedByteArray()
	var done: PackedByteArray = PackedByteArray()
	first_normal.resize(count)
	ever.resize(count)
	done.resize(count)
	for _index: int in count:
		series.append(PackedFloat64Array())
	obs.read()
	smooth.check(obs, 0.0, step)
	for index: int in roundi(seconds / step):
		setup.sim.call("step", step)
		obs.read()
		smooth.check(obs, (index + 1) * step, step)
		for fish: int in count:
			if obs.recovering[fish] == 1:
				series[fish].append(obs.speed[fish])
				ever[fish] = 1
			elif ever[fish] == 1 and done[fish] == 0:
				first_normal[fish] = obs.speed[fish]
				done[fish] = 1
	return {
		"series": series,
		"smooth": smooth,
		"ever": ever,
		"first_normal": first_normal,
		"obs": obs,
		"done": done,
	}


## Asserts the plan rules of the ease for every fish that recovered; returns how many did.
func _check_ease(setup: Rig.Setup, result: Dictionary, step: float = Rig.STEP) -> int:
	var series: Array = result["series"]
	var ever: PackedByteArray = result["ever"]
	var first_normal: PackedFloat64Array = result["first_normal"]
	var smooth: Rig.Smooth = result["smooth"]
	(
		assert_int(smooth.total())
		. override_failure_message("a cap broke during the ease: %s" % smooth.report())
		. is_equal(0)
	)
	var recovered: int = 0
	for index: int in setup.members.size():
		if ever[index] == 0:
			continue
		recovered += 1
		var member: Rig.Member = setup.members[index]
		var speeds: PackedFloat64Array = series[index]
		var peak: float = 0.0
		for speed: float in speeds:
			peak = maxf(peak, speed)
		var label: String = "%s %s" % [member.species_id, member.uid]
		assert_float(peak).override_failure_message(label + " never moved").is_greater(0.0)
		(
			assert_float(peak)
			. override_failure_message(
				"%s peak %.3f over 6 x top %.3f" % [label, peak, 6.0 * member.top]
			)
			. is_less_equal(Rig.RECOVERY_FACTOR * member.top + 1e-9)
		)
		(
			assert_float(speeds.size() * step)
			. override_failure_message("%s recovered for %d steps" % [label, speeds.size()])
			. is_less_equal(LIMIT_S + step)
		)
		var ramp_steps: int = roundi(0.15 / step)
		(
			assert_float(speeds[0])
			. override_failure_message(label + " starts with a velocity step")
			. is_less_equal(0.1 * peak + 1e-9)
		)
		if speeds.size() > ramp_steps * 2:
			(
				assert_float(speeds[ramp_steps - 1])
				. override_failure_message(label + " ramps up faster than 0.3 s")
				. is_less_equal(0.6 * peak)
			)
			(
				assert_float(speeds[speeds.size() - ramp_steps])
				. override_failure_message(label + " ramps down faster than 0.3 s")
				. is_less_equal(0.6 * peak)
			)
		var slope: float = peak / RAMP_S * 1.5 * step * 1.05 + 1e-9
		for at: int in range(1, speeds.size()):
			if absf(speeds[at] - speeds[at - 1]) > slope:
				(
					assert_float(absf(speeds[at] - speeds[at - 1]))
					. override_failure_message(
						"%s has a velocity step at recovery step %d" % [label, at]
					)
					. is_less_equal(slope)
				)
				break
		(
			assert_float(first_normal[index])
			. override_failure_message(
				"%s starts normal steering from speed %.4f" % [label, first_normal[index]]
			)
			. is_less_equal(member.top / Rig.ACCEL_TIME_S * step * 2.0 + 1e-9)
		)
	return recovered


func _inside_now(setup: Rig.Setup, result: Dictionary, what: String) -> void:
	var limits: Rig.Limits = Rig.Limits.new(setup)
	limits.check(result["obs"], LIMIT_S)
	(
		assert_int(limits.total())
		. override_failure_message(
			"%s: a fish is outside the new limits after 2 s: %s" % [what, limits.report()]
		)
		. is_equal(0)
	)


func test_35_a_tank_change_from_large_to_small_brings_every_fish_back_inside_within_2_seconds(
) -> void:
	var setup: Rig.Setup = Rig.open(Rig.LARGE, Rig.mixed(8, 4, 6))
	assert_object(setup).override_failure_message("the steering classes are missing").is_not_null()
	if setup == null:
		return
	Rig.run(setup, 20.0)
	Rig.change_tank(setup, Rig.SMALL)
	var result: Dictionary = _ease(setup, LIMIT_S + Rig.STEP)
	(
		assert_int(_check_ease(setup, result))
		. override_failure_message("the change should leave fish outside the new tank")
		. is_greater_equal(5)
	)
	_inside_now(setup, result, "large to small")
	for member: Rig.Member in setup.members:
		var state: Object = Rig.state_of(setup, member.uid)
		(
			assert_bool(bool(state.get("recovering")))
			. override_failure_message("%s is still recovering after 2 s" % member.uid)
			. is_false()
		)


func test_35_edge_a_fish_up_to_1_m_from_its_nearest_valid_point_arrives_within_2_seconds() -> void:
	var small_valid: float = SMALL_TANK_X - 0.01
	for id: StringName in FishApi.IDS:
		var uid: String = Rig.uids(1)[0]
		var member: Rig.Member = Rig.member_of(id, uid)
		if member == null:
			(
				assert_bool(false)
				. override_failure_message("the steering classes are missing")
				. is_true()
			)
			return
		var radius: float = float(member.extents.get("horizontal_radius_m"))
		var start_x: float = small_valid - radius + 0.95
		var height: float = 0.06 if id == FishApi.CORY else 0.14
		var pose: Object = Api.pose_of(Vector3(start_x, height, 0.0), 1.0)
		var setup: Rig.Setup = Rig.open_box(
			WIDE, WIDE_WATER, [Rig.entry(id, uid, null, pose)], _flat
		)
		if setup == null:
			(
				assert_bool(false)
				. override_failure_message("the steering classes are missing")
				. is_true()
			)
			return
		Rig.change_tank(setup, Rig.SMALL)
		var result: Dictionary = _ease(setup, LIMIT_S + Rig.STEP)
		(
			assert_int(_check_ease(setup, result))
			. override_failure_message("%s should recover" % id)
			. is_equal(1)
		)
		_inside_now(setup, result, "%s from 0.95 m" % id)


func test_35_a_substrate_change_that_raises_the_bed_lifts_a_bottom_fish_within_2_seconds() -> void:
	var setup: Rig.Setup = Rig.open(Rig.LARGE, Rig.crowd(FishApi.CORY, 6))
	if setup == null:
		assert_bool(false).override_failure_message("the steering classes are missing").is_true()
		return
	Rig.run(setup, 10.0)
	Rig.change_tank(setup, Rig.LARGE, _raised)
	var result: Dictionary = _ease(setup, LIMIT_S + Rig.STEP)
	assert_int(_check_ease(setup, result)).is_greater_equal(1)
	_inside_now(setup, result, "raised bed")
	var obs: Rig.Observer = result["obs"]
	for index: int in obs.count:
		assert_float(obs.position[index].y).is_greater(RAISED_BED_M)


func test_35_lowering_the_bed_again_keeps_every_cap_and_ends_inside_the_limits() -> void:
	var setup: Rig.Setup = Rig.open(Rig.LARGE, Rig.crowd(FishApi.CORY, 6), _raised)
	if setup == null:
		assert_bool(false).override_failure_message("the steering classes are missing").is_true()
		return
	Rig.run(setup, 10.0)
	Rig.change_tank(setup, Rig.LARGE)
	var result: Dictionary = _ease(setup, LIMIT_S + Rig.STEP)
	_check_ease(setup, result)
	_inside_now(setup, result, "lowered bed")


func test_35_a_change_that_leaves_every_fish_inside_starts_no_recovery() -> void:
	var setup: Rig.Setup = Rig.open(Rig.LARGE, Rig.mixed(8, 4, 6))
	if setup == null:
		assert_bool(false).override_failure_message("the steering classes are missing").is_true()
		return
	Rig.run(setup, 20.0)
	Rig.change_tank(setup, Rig.LARGE)
	var result: Dictionary = _ease(setup, 1.0)
	(
		assert_array(Array(result["ever"]))
		. override_failure_message("a fish recovered after a change that left it inside")
		. has_size(18)
	)
	for flag: int in result["ever"] as PackedByteArray:
		assert_int(flag).is_equal(0)
	_check_ease(setup, result)


func test_35_begin_recovery_is_the_public_seam_for_a_fish_the_world_moved_under() -> void:
	var bed: Array[float] = [BED_M]
	var surface: Callable = func(_x: float, _z: float) -> float: return bed[0]
	var uid: String = Rig.uids(1)[0]
	var setup: Rig.Setup = Rig.open(Rig.LARGE, [Rig.entry(FishApi.CORY, uid)], surface)
	if setup == null:
		assert_bool(false).override_failure_message("the steering classes are missing").is_true()
		return
	Rig.run(setup, 5.0)
	bed[0] = RAISED_BED_M
	setup.sim.call("begin_recovery", uid)
	var result: Dictionary = _ease(setup, LIMIT_S + Rig.STEP)
	assert_array(Array(result["ever"])).is_equal([1])
	_check_ease(setup, result)
	_inside_now(setup, result, "begin_recovery")


func test_35_the_ease_also_holds_at_1_144_s() -> void:
	var setup: Rig.Setup = Rig.open(Rig.LARGE, Rig.mixed(8, 4, 6))
	if setup == null:
		assert_bool(false).override_failure_message("the steering classes are missing").is_true()
		return
	var fast: float = 1.0 / 144.0
	for _index: int in 20 * 144:
		setup.sim.call("step", fast)
	Rig.change_tank(setup, Rig.SMALL)
	var result: Dictionary = _ease(setup, LIMIT_S + fast, fast)
	_check_ease(setup, result, fast)
	_inside_now(setup, result, "1/144")
