extends GdUnitTestSuite
## #35 movement states and the balanced feel (owner: developer): per species, 20 seeded fish swim 10
## simulated minutes in the large tank at a fixed step; the first 30 s are discarded as settling.
## The bounds apply to the population mean of the 20 fish; each single fish is held to the same
## bound widened by 20 percent (lower x 0.8, upper x 1.2), which is the extreme-personality edge, so
## there is no third rule (BA decision Q7). Mean cruise speed = the average 3D speed of the origin
## over the cruise-state steps, as a fraction of the species top speed (swim_speed x 3 body lengths
## per second, no personality); idle share = idle steps / all steps; dart rate = darts started /
## fish-seconds, checked on the interval; dart duration = time in the dart state. All numbers are
## (tuning). Frame-rate independence (BA decision Q6): the same bounds and caps hold at 1/60 and at
## 1/144 s; 1/30 is the same trajectory as 1/60 and is checked in test_fish_swim_smoothness.gd. Test
## decisions: every (species, step) run is simulated once and shared with the zone and smoothness
## tests (fish_swim_runs.gd); the extreme personalities (every factor at its range limit, 0.80 and
## 1.1999, depth preference at -0.20 and 0.1999) run as one fish per case with the same per-fish
## bounds; the cruise speed of the order tetra, corydoras, angelfish is in body lengths.

const Api := preload("res://tests/helpers/fish_swim_api.gd")
const FishApi := preload("res://tests/helpers/fish_api.gd")
const Rig := preload("res://tests/helpers/fish_swim_rig.gd")
const Runs := preload("res://tests/helpers/fish_swim_runs.gd")

const FAST_STEP := 1.0 / 144.0
const CRUISE_MEAN := Vector2(0.35, 0.60)
const WIDEN_LOW := 0.8
const WIDEN_HIGH := 1.2
## Species id to the bounds [idle low, idle high, interval low, interval high, duration low,
## duration high] of the domain BA table.
const BOUNDS: Dictionary[StringName, Array] = {
	&"neon_tetra": [0.15, 0.25, 20.0, 40.0, 0.5, 1.0],
	&"bronze_corydoras": [0.35, 0.45, 25.0, 50.0, 0.5, 1.0],
	&"angelfish": [0.25, 0.35, 40.0, 60.0, 0.8, 1.5],
}
const GLOBAL_IDLE := Vector2(0.15, 0.45)
const GLOBAL_INTERVAL := Vector2(20.0, 60.0)
const GLOBAL_DURATION := Vector2(0.5, 1.5)
const MIN_GAP_S := 5.0


func _run(id: StringName, step: float) -> Dictionary:
	var result: Dictionary = Runs.feel(id, step)
	(
		assert_bool(result.get("ok", false))
		. override_failure_message("the steering classes are missing")
		. is_true()
	)
	return result


func _in(value: float, low: float, high: float, what: String) -> void:
	(
		assert_float(value)
		. override_failure_message("%s is %.4f, expected %.4f to %.4f" % [what, value, low, high])
		. is_between(low, high)
	)


## The population-mean and the per-fish checks of one run. `per_fish` false for a single fish run.
func _check_feel(id: StringName, run: Dictionary) -> void:
	var bounds: Array = BOUNDS[id]
	var count: int = int(run["count"])
	var cruise: PackedFloat64Array = run["cruise_fraction"]
	var idle: PackedFloat64Array = run["idle_share"]
	var intervals: PackedFloat64Array = run["dart_interval"]
	var durations: PackedFloat64Array = run["dart_duration"]
	var darts: PackedInt32Array = run["darts"]
	var slack: float = float(run["step"])
	if count > 1:
		_in(Rig.mean(cruise), CRUISE_MEAN.x, CRUISE_MEAN.y, "%s mean cruise fraction" % id)
		_in(Rig.mean(idle), bounds[0], bounds[1], "%s mean idle share" % id)
		var total_darts: int = 0
		var total_seconds: float = float(run["seconds"]) * count
		var duration_sum: float = 0.0
		var duration_count: int = 0
		for index: int in count:
			total_darts += darts[index]
			if durations[index] > 0.0:
				duration_sum += durations[index]
				duration_count += 1
		assert_int(total_darts).override_failure_message("%s darted never" % id).is_greater(0)
		if total_darts > 0:
			_in(total_seconds / total_darts, bounds[2], bounds[3], "%s mean dart interval" % id)
			_in(
				duration_sum / maxi(duration_count, 1),
				bounds[4] - slack,
				bounds[5] + slack,
				"%s mean dart duration" % id
			)
	for index: int in count:
		var label: String = "%s fish %d" % [id, index]
		_in(cruise[index], CRUISE_MEAN.x * WIDEN_LOW, CRUISE_MEAN.y * WIDEN_HIGH, label + " cruise")
		_in(idle[index], bounds[0] * WIDEN_LOW, bounds[1] * WIDEN_HIGH, label + " idle share")
		_in(intervals[index], bounds[2] * WIDEN_LOW, bounds[3] * WIDEN_HIGH, label + " interval")
		_in(
			durations[index],
			bounds[4] * WIDEN_LOW - slack,
			bounds[5] * WIDEN_HIGH + slack,
			label + " dart duration"
		)
	var gap: float = float(run["min_gap"])
	(
		assert_float(gap)
		. override_failure_message("%s: two darts %.2f s apart" % [id, gap])
		. is_greater_equal(MIN_GAP_S - slack)
	)
	(
		assert_bool(run["darts_match"])
		. override_failure_message("%s: state.darts_started does not count the dart states" % id)
		. is_true()
	)
	var smooth: Rig.Smooth = run["smooth"]
	for kind: String in ["dart_cap", "speed_cap"]:
		(
			assert_int(smooth.violations.get(kind, 0))
			. override_failure_message("%s breaks %s: %s" % [id, kind, smooth.report()])
			. is_equal(0)
		)


func test_35_neon_tetras_have_the_balanced_feel_at_1_60() -> void:
	var run: Dictionary = _run(FishApi.NEON, Rig.STEP)
	if run.get("ok", false):
		_check_feel(FishApi.NEON, run)


func test_35_angelfish_have_the_balanced_feel_at_1_60() -> void:
	var run: Dictionary = _run(FishApi.ANGEL, Rig.STEP)
	if run.get("ok", false):
		_check_feel(FishApi.ANGEL, run)


func test_35_corydoras_have_the_balanced_feel_at_1_60() -> void:
	var run: Dictionary = _run(FishApi.CORY, Rig.STEP)
	if run.get("ok", false):
		_check_feel(FishApi.CORY, run)


func test_35_neon_tetras_have_the_balanced_feel_at_1_144() -> void:
	var run: Dictionary = _run(FishApi.NEON, FAST_STEP)
	if run.get("ok", false):
		_check_feel(FishApi.NEON, run)


func test_35_angelfish_have_the_balanced_feel_at_1_144() -> void:
	var run: Dictionary = _run(FishApi.ANGEL, FAST_STEP)
	if run.get("ok", false):
		_check_feel(FishApi.ANGEL, run)


func test_35_corydoras_have_the_balanced_feel_at_1_144() -> void:
	var run: Dictionary = _run(FishApi.CORY, FAST_STEP)
	if run.get("ok", false):
		_check_feel(FishApi.CORY, run)


func test_35_the_global_balanced_bounds_hold_for_every_species() -> void:
	for id: StringName in FishApi.IDS:
		var run: Dictionary = _run(id, Rig.STEP)
		if not run.get("ok", false):
			return
		_in(Rig.mean(run["idle_share"]), GLOBAL_IDLE.x, GLOBAL_IDLE.y, "%s idle share" % id)
		_in(Rig.mean(run["cruise_fraction"]), CRUISE_MEAN.x, CRUISE_MEAN.y, "%s cruise" % id)
		var total_darts: int = 0
		for count: int in run["darts"] as PackedInt32Array:
			total_darts += count
		if total_darts > 0:
			var interval: float = float(run["seconds"]) * float(run["count"]) / total_darts
			_in(interval, GLOBAL_INTERVAL.x, GLOBAL_INTERVAL.y, "%s dart interval" % id)
		for duration: float in run["dart_duration"] as PackedFloat64Array:
			_in(duration, 0.0, GLOBAL_DURATION.y * WIDEN_HIGH + 0.02, "%s dart duration" % id)


func test_35_the_speed_order_in_body_lengths_is_tetra_then_corydoras_then_angelfish() -> void:
	var rates: Dictionary[StringName, float] = {}
	for id: StringName in FishApi.IDS:
		var run: Dictionary = _run(id, Rig.STEP)
		if not run.get("ok", false):
			return
		var swim_speed: float = float(FishApi.field(id, "swim_speed", 0.0))
		rates[id] = Rig.mean(run["cruise_fraction"]) * swim_speed * Api.TOP_SPEED_K
	assert_bool(rates[FishApi.NEON] > rates[FishApi.CORY]).is_true()
	assert_bool(rates[FishApi.CORY] > rates[FishApi.ANGEL]).is_true()
	_in(rates[FishApi.NEON], 1.4, 2.3, "tetra cruise in body lengths per second")
	_in(rates[FishApi.CORY], 0.8, 1.4, "corydoras cruise in body lengths per second")
	_in(rates[FishApi.ANGEL], 0.5, 0.9, "angelfish cruise in body lengths per second")


func test_35_the_corydoras_pause_more_than_tetras_and_cruise_with_the_nose_down() -> void:
	var cory: Dictionary = _run(FishApi.CORY, Rig.STEP)
	var neon: Dictionary = _run(FishApi.NEON, Rig.STEP)
	if not cory.get("ok", false) or not neon.get("ok", false):
		return
	assert_float(Rig.mean(cory["idle_share"])).is_greater(Rig.mean(neon["idle_share"]) + 0.10)
	var pitch_deg: float = rad_to_deg(Rig.mean(cory["cruise_pitch"]))
	(
		assert_float(pitch_deg)
		. override_failure_message(
			"corydoras cruise pitch is %.1f deg, need -5 or lower" % pitch_deg
		)
		. is_less_equal(-5.0)
	)


func test_35_the_depth_preference_shows_in_the_mean_height_of_the_middle_species() -> void:
	for id: StringName in [FishApi.NEON, FishApi.ANGEL]:
		var run: Dictionary = _run(id, Rig.STEP)
		if not run.get("ok", false):
			return
		var heights: PackedFloat64Array = run["mean_height"]
		var preferences: PackedFloat64Array = run["depth_fraction"]
		var mean_height: float = Rig.mean(heights)
		var mean_preference: float = Rig.mean(preferences)
		var covariance: float = 0.0
		var spread_height: float = 0.0
		var spread_preference: float = 0.0
		for index: int in heights.size():
			covariance += (heights[index] - mean_height) * (preferences[index] - mean_preference)
			spread_height += (heights[index] - mean_height) ** 2
			spread_preference += (preferences[index] - mean_preference) ** 2
		var correlation: float = covariance / sqrt(maxf(spread_height * spread_preference, 1e-18))
		(
			assert_float(correlation)
			. override_failure_message(
				"%s: height follows depth preference with r = %.2f" % [id, correlation]
			)
			. is_greater(0.5)
		)


# --- extreme personalities ---


func _extreme(id: StringName, high: bool) -> void:
	var factor: float = 1.1999 if high else 0.80
	var depth: float = 0.1999 if high else -0.20
	var made: Object = Api.personality_of(
		PackedFloat64Array([factor, factor, factor, factor, depth])
	)
	if made == null:
		assert_bool(false).override_failure_message("FishPersonality is missing").is_true()
		return
	var uid: String = Rig.uids(1)[0]
	var key: String = "extreme_%s_%s" % [id, "high" if high else "low"]
	var run: Dictionary = Runs.custom(
		key, id, [Rig.entry(id, uid, null, null, &"", made)], Rig.STEP
	)
	(
		assert_bool(run.get("ok", false))
		. override_failure_message("the steering classes are missing")
		. is_true()
	)
	if not run.get("ok", false):
		return
	_check_feel(id, run)
	var smooth: Rig.Smooth = run["smooth"]
	(
		assert_int(smooth.total())
		. override_failure_message("%s extreme looks jittery: %s" % [id, smooth.report()])
		. is_equal(0)
	)
	var limits: Rig.Limits = run["limits"]
	assert_int(limits.total()).override_failure_message(limits.report()).is_equal(0)


func test_35_edge_the_neon_tetra_with_every_factor_at_the_low_limit_stays_in_bounds() -> void:
	_extreme(FishApi.NEON, false)


func test_35_edge_the_neon_tetra_with_every_factor_at_the_high_limit_stays_in_bounds() -> void:
	_extreme(FishApi.NEON, true)


func test_35_edge_the_angelfish_with_every_factor_at_the_low_limit_stays_in_bounds() -> void:
	_extreme(FishApi.ANGEL, false)


func test_35_edge_the_angelfish_with_every_factor_at_the_high_limit_stays_in_bounds() -> void:
	_extreme(FishApi.ANGEL, true)


func test_35_edge_the_corydoras_with_every_factor_at_the_low_limit_stays_in_bounds() -> void:
	_extreme(FishApi.CORY, false)


func test_35_edge_the_corydoras_with_every_factor_at_the_high_limit_stays_in_bounds() -> void:
	_extreme(FishApi.CORY, true)
