extends GdUnitTestSuite
## #35 stuck rule for walls and fish (owner: developer; BA decision Q17; B24b #168 extends it to
## items and must not add a second implementation): a fish that intends to move (cruise, dart or
## override; not idle, not paused) and whose speed stays below 5 percent of its top speed for 5
## simulated seconds picks a new target. A pinned fish never triggers it (it only hovers). Corner
## test: 8 fish of one species started inside a 15 x 15 cm corner of the large tank swim for 60 s
## and no fish stays below 5 percent of top speed with intent to move for more than 6 s. Test
## decisions: the intent is read from the movement state (cruise, dart or override) and the speed
## from the state, never from the developer's private counter; the corner test runs for the neon
## tetra and the corydoras (8 angelfish cannot fit a 15 cm corner, their body radius is 10 cm); the
## pinned fish is a copy of the angelfish at 18 cm in the small tank; the start poses come from a
## RandomNumberGenerator seeded 12345 and are placed inside the corner by the test.

const Api := preload("res://tests/helpers/fish_swim_api.gd")
const FishApi := preload("res://tests/helpers/fish_api.gd")
const Rig := preload("res://tests/helpers/fish_swim_rig.gd")

const CORNER_M := 0.15
const SIXTY_S := 60
const LIMIT_S := 6.0
const LOW_FRACTION := 0.05


## 8 entries of one species with start poses inside the -x, -z corner of the large tank.
func _corner_entries(id: StringName) -> Array:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = Rig.UID_SEED
	var probe: Rig.Member = Rig.member_of(id, "00000000")
	if probe == null or probe.params == null:
		return []
	var radius: float = float(probe.extents.get("horizontal_radius_m"))
	var result: Array = []
	var tank: TankDefinition = Rig.tank_of(Rig.LARGE)
	var zones: GDScript = Api.script_of(FishApi.ZONES_PATH)
	for uid: String in Rig.uids(8):
		var x: float = -tank.interior_size_m.x / 2.0 + radius + 0.01 + random.randf() * 0.1
		var z: float = -tank.interior_size_m.z / 2.0 + radius + 0.01 + random.randf() * 0.1
		var span: Object = zones.call(
			"origin_range",
			probe.zone,
			Rig.flat_surface(Rig.LARGE),
			x,
			z,
			tank.water_line_height_m,
			Rig.sand_allowance(),
			probe.extents
		)
		var y: float = lerpf(span.get("min_y"), span.get("max_y"), random.randf())
		result.append(Rig.entry(id, uid, null, Api.pose_of(Vector3(x, y, z), random.randf() * TAU)))
	return result


## The longest time in seconds a fish had intent to move and a speed below 5 percent of its top.
func _longest_stuck(setup: Rig.Setup, steps: int) -> PackedFloat64Array:
	var obs: Rig.Observer = Rig.Observer.new(setup)
	var streak: PackedInt32Array = PackedInt32Array()
	var longest: PackedInt32Array = PackedInt32Array()
	streak.resize(obs.count)
	longest.resize(obs.count)
	var cruise: int = Api.mode_id("CRUISE")
	var dart: int = Api.mode_id("DART")
	var override: int = Api.mode_id("OVERRIDE")
	for _step: int in steps:
		setup.sim.call("step", Rig.STEP)
		obs.read()
		for fish: int in obs.count:
			var mode: int = obs.mode[fish]
			var intends: bool = mode == cruise or mode == dart or mode == override
			var slow: bool = obs.speed[fish] < LOW_FRACTION * setup.members[fish].top
			if intends and slow and obs.pinned[fish] == 0:
				streak[fish] += 1
				longest[fish] = maxi(longest[fish], streak[fish])
			else:
				streak[fish] = 0
	var seconds: PackedFloat64Array = PackedFloat64Array()
	for fish: int in obs.count:
		seconds.append(longest[fish] * Rig.STEP)
	return seconds


func _corner(id: StringName) -> void:
	var setup: Rig.Setup = Rig.open(Rig.LARGE, _corner_entries(id))
	assert_object(setup).override_failure_message("the steering classes are missing").is_not_null()
	if setup == null:
		return
	var start: Rig.Observer = Rig.Observer.new(setup)
	start.read()
	for fish: int in start.count:
		(
			assert_bool(
				(
					start.position[fish].x < -0.5 + CORNER_M + 0.05
					and start.position[fish].z < -0.2 + CORNER_M + 0.05
				)
			)
			. override_failure_message("fish %d did not start in the corner" % fish)
			. is_true()
		)
	var longest: PackedFloat64Array = _longest_stuck(setup, SIXTY_S * 60)
	for fish: int in longest.size():
		(
			assert_float(longest[fish])
			. override_failure_message(
				"%s fish %d was stuck for %.2f s" % [id, fish, longest[fish]]
			)
			. is_less_equal(LIMIT_S)
		)


func test_35_eight_tetras_started_in_a_15_cm_corner_are_never_stuck_for_more_than_6_seconds(
) -> void:
	_corner(FishApi.NEON)


func test_35_eight_corydoras_started_in_a_15_cm_corner_are_never_stuck_for_more_than_6_seconds(
) -> void:
	_corner(FishApi.CORY)


func test_35_an_overridden_fish_waiting_at_its_target_is_never_stuck_for_more_than_6_seconds(
) -> void:
	for id: StringName in [FishApi.NEON, FishApi.CORY]:
		var setup: Rig.Setup = Rig.open(Rig.LARGE, Rig.crowd(id, 1))
		if setup == null:
			(
				assert_bool(false)
				. override_failure_message("the steering classes are missing")
				. is_true()
			)
			return
		setup.sim.call("set_override", setup.members[0].uid, Vector3(-5.0, 0.07, -5.0))
		var longest: PackedFloat64Array = _longest_stuck(setup, 60 * 60)
		(
			assert_float(longest[0])
			. override_failure_message(
				"%s stuck at the override target for %.2f s" % [id, longest[0]]
			)
			. is_less_equal(LIMIT_S)
		)


func test_35_a_pinned_fish_never_intends_to_move_so_the_stuck_rule_never_fires() -> void:
	var giant: Resource = Rig.pinned_species()
	if giant == null:
		assert_bool(false).override_failure_message("FishSpecies is missing").is_true()
		return
	var uid: String = Rig.uids(1)[0]
	var setup: Rig.Setup = Rig.open(Rig.SMALL, [Rig.pinned_entry(uid)])
	if setup == null:
		assert_bool(false).override_failure_message("the steering classes are missing").is_true()
		return
	var obs: Rig.Observer = Rig.Observer.new(setup)
	var start: Vector3 = Vector3.ZERO
	var farthest: float = 0.0
	for index: int in 60 * 60:
		setup.sim.call("step", Rig.STEP)
		obs.read()
		if index == 0:
			start = obs.position[0]
		farthest = maxf(farthest, obs.position[0].distance_to(start))
		assert_int(obs.pinned[0]).is_equal(1)
		(
			assert_int(obs.intends[0])
			. override_failure_message("a pinned fish intends to move at step %d" % index)
			. is_equal(0)
		)
	(
		assert_float(farthest)
		. override_failure_message("the pinned fish chose a new target")
		. is_less_equal(0.02)
	)


func test_35_a_paused_fish_is_never_counted_as_stuck_and_picks_no_new_target() -> void:
	var setup: Rig.Setup = Rig.open(Rig.LARGE, Rig.crowd(FishApi.NEON, 4))
	if setup == null:
		assert_bool(false).override_failure_message("the steering classes are missing").is_true()
		return
	Rig.run(setup, 20.0)
	setup.sim.call("set_paused", true)
	var obs: Rig.Observer = Rig.Observer.new(setup)
	obs.read()
	var prior: PackedVector3Array = obs.position.duplicate()
	Rig.run(setup, 30.0)
	obs.read()
	for fish: int in obs.count:
		assert_vector(obs.position[fish]).is_equal(prior[fish])
		(
			assert_int(obs.intends[fish])
			. override_failure_message("a paused fish intends to move")
			. is_equal(0)
		)
