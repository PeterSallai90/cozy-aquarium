# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #33 AC 15 (d) (owner: developer): RefusalCue, the pure timer of the refusal glow. start() sets
## t = 0 and makes it active (start count + 1); step(delta_s) advances it (a delta of zero or less
## is ignored) and ends it when t reaches REFUSAL_CUE_DURATION_S; get_strength(base) is
## base + (PEAK - base) * sin(PI * t / DURATION) while active and base otherwise. A new start()
## restarts the cue, so it never stacks. The constants come from PlacementTuning; the architect's
## table (base 0.7, steps of 0.05 s) is asserted at 1e-4.
## Test decisions: the base is the fresnel_strength of item_selection_material.tres, read from the
## file; the table is hard-coded here because it is the plan's fixed expectation; the peak guard is
## the same as test_the_glow_defaults_stay_below_the_environment_glow_threshold.

const Api := preload("res://tests/helpers/placement_api.gd")

const MATERIAL := "res://scenes/tank/items/item_selection_material.tres"
const ENVIRONMENT := "res://scenes/room/room_environment.tres"
const BASE: float = 0.7
const TOLERANCE: float = 0.0001
const STEP_S: float = 0.05
## strength after n steps of STEP_S (the plan's table) and whether the cue is still active.
const TABLE: Array[float] = [0.7, 0.8, 0.873205, 0.9, 0.873205, 0.8, 0.7]
## The architect addendum 2 table (0.05 s steps; steps 0 to 5, the end is the base): fresnel_power,
## glow_colour green and blue (red stays 1.0) and glow_lift green and blue (red stays 0.0).
const POWER: Array[float] = [1.6, 1.05, 0.647372, 0.5, 0.647372, 1.05]
const COLOUR_G: Array[float] = [0.86, 0.86, 0.86, 0.570086, 0.45, 0.570086]
const COLOUR_B: Array[float] = [0.62, 0.62, 0.62, 0.464437, 0.40, 0.464437]
const LIFT_G: Array[float] = [0.0, 0.212132, 0.3, 0.212132, 0.0, 0.0]
const LIFT_B: Array[float] = [0.0, 0.190919, 0.27, 0.190919, 0.0, 0.0]


func _have() -> bool:
	var found: bool = Api.exists(Api.CUE) and Api.exists(Api.TUNING)
	(
		assert_bool(found)
		. override_failure_message("refusal_cue.gd or placement_tuning.gd is missing")
		. is_true()
	)
	return found


func _strength(cue: RefCounted) -> float:
	return float(cue.call("get_strength", BASE))


func _active(cue: RefCounted) -> bool:
	return cue.call("is_active") == true


func _step(cue: RefCounted, seconds: float) -> void:
	cue.call("step", seconds)


func test_the_cue_constants_exist_in_placement_tuning() -> void:
	if not _have():
		return
	assert_float(Api.tuning("REFUSAL_CUE_DURATION_S")).is_equal_approx(0.30, 0.000001)
	assert_float(Api.tuning("REFUSAL_CUE_PEAK_STRENGTH")).is_equal_approx(0.90, 0.000001)
	assert_float(Api.tuning("REFUSAL_CUE_PEAK_FRESNEL_POWER")).is_equal_approx(0.5, 0.000001)
	assert_float(Api.tuning("REFUSAL_CUE_COLOUR_START_S")).is_equal_approx(0.10, 0.000001)
	assert_float(Api.tuning("REFUSAL_CUE_COLOUR_END_S")).is_equal_approx(0.30, 0.000001)
	assert_float(Api.tuning("REFUSAL_CUE_LIFT_START_S")).is_equal_approx(0.0, 0.000001)
	assert_float(Api.tuning("REFUSAL_CUE_LIFT_END_S")).is_equal_approx(0.20, 0.000001)
	assert_float(Api.tuning("REFUSAL_CUE_REFERENCE_FACING")).is_equal_approx(0.5, 0.000001)
	assert_float(Api.tuning("REFUSAL_CUE_GUARD_LIT_EDGE")).is_equal_approx(0.8, 0.000001)
	var colour: Variant = Api.constant(Api.TUNING, "REFUSAL_CUE_COLOUR", null)
	assert_bool(colour is Color).override_failure_message("REFUSAL_CUE_COLOUR missing").is_true()
	if colour is Color:
		assert_bool((colour as Color).is_equal_approx(Color(1.0, 0.45, 0.40))).is_true()
	var lift: Variant = Api.constant(Api.TUNING, "REFUSAL_CUE_LIFT", null)
	assert_bool(lift is Vector3).override_failure_message("REFUSAL_CUE_LIFT missing").is_true()
	if lift is Vector3:
		assert_bool((lift as Vector3).is_equal_approx(Vector3(0.0, 0.30, 0.27))).is_true()


func test_the_base_strength_is_the_one_of_the_selection_material() -> void:
	var material: ShaderMaterial = load(MATERIAL) as ShaderMaterial
	assert_object(material).is_not_null()
	assert_float(float(material.get_shader_parameter("fresnel_strength"))).is_equal(BASE)


func test_the_peak_times_the_brightest_glow_channel_stays_below_the_bloom_threshold() -> void:
	if not _have():
		return
	var environment: Environment = load(ENVIRONMENT) as Environment
	var material: ShaderMaterial = load(MATERIAL) as ShaderMaterial
	var colour: Color = material.get_shader_parameter("glow_colour")
	var brightest: float = maxf(colour.r, maxf(colour.g, colour.b))
	var peak: float = Api.tuning("REFUSAL_CUE_PEAK_STRENGTH")
	assert_float(peak).is_greater(BASE)
	assert_float(peak).is_less_equal(1.0)
	assert_float(brightest * peak).is_less(environment.glow_hdr_threshold)


func test_a_new_cue_is_inactive_at_the_base_strength_and_counts_no_start() -> void:
	if not _have():
		return
	var cue: RefCounted = Api.new_cue()
	assert_bool(_active(cue)).is_false()
	assert_float(_strength(cue)).is_equal(BASE)
	assert_int(cue.call("get_start_count")).is_equal(0)
	assert_float(float(cue.call("get_elapsed_s"))).is_equal(0.0)


func test_start_begins_at_the_base_strength_and_counts() -> void:
	if not _have():
		return
	var cue: RefCounted = Api.new_cue()
	cue.call("start")
	assert_bool(_active(cue)).is_true()
	assert_float(_strength(cue)).is_equal_approx(BASE, TOLERANCE)
	assert_float(float(cue.call("get_elapsed_s"))).is_equal(0.0)
	assert_int(cue.call("get_start_count")).is_equal(1)


func test_the_strength_follows_the_half_sine_table_at_steps_of_50_ms() -> void:
	if not _have():
		return
	var cue: RefCounted = Api.new_cue()
	cue.call("start")
	for index: int in TABLE.size():
		if index > 0:
			_step(cue, STEP_S)
		var label: String = "after %d steps" % index
		(
			assert_float(_strength(cue))
			. override_failure_message(
				"%s: %s, expected %s" % [label, _strength(cue), TABLE[index]]
			)
			. is_equal_approx(TABLE[index], TOLERANCE)
		)
		var last: bool = index == TABLE.size() - 1
		assert_bool(_active(cue)).override_failure_message(label).is_equal(not last)


func test_the_static_curve_gives_the_same_table() -> void:
	if not _have():
		return
	for index: int in TABLE.size():
		var t_s: float = STEP_S * index
		assert_float(Api.cue_strength_at(t_s, BASE)).is_equal_approx(TABLE[index], TOLERANCE)


func test_the_curve_is_the_base_outside_the_cue_time() -> void:
	if not _have():
		return
	var duration: float = Api.tuning("REFUSAL_CUE_DURATION_S")
	assert_float(Api.cue_strength_at(duration + 0.01, BASE)).is_equal_approx(BASE, TOLERANCE)
	assert_float(Api.cue_strength_at(10.0, BASE)).is_equal_approx(BASE, TOLERANCE)
	assert_float(Api.cue_strength_at(-0.05, BASE)).is_equal_approx(BASE, TOLERANCE)


func test_the_curve_scales_with_another_base() -> void:
	if not _have():
		return
	var peak: float = Api.tuning("REFUSAL_CUE_PEAK_STRENGTH")
	var duration: float = Api.tuning("REFUSAL_CUE_DURATION_S")
	assert_float(Api.cue_strength_at(duration / 2.0, 0.5)).is_equal_approx(peak, TOLERANCE)
	assert_float(Api.cue_strength_at(duration / 4.0, 0.5)).is_equal_approx(
		0.5 + (peak - 0.5) * sin(PI / 4.0), TOLERANCE
	)


func test_the_strength_never_goes_above_the_peak_nor_below_the_base() -> void:
	if not _have():
		return
	var peak: float = Api.tuning("REFUSAL_CUE_PEAK_STRENGTH")
	var cue: RefCounted = Api.new_cue()
	cue.call("start")
	for frame: int in 40:
		_step(cue, 1.0 / 120.0)
		assert_float(_strength(cue)).is_less_equal(peak + TOLERANCE)
		assert_float(_strength(cue)).is_greater_equal(BASE - TOLERANCE)


func test_the_cue_ends_at_the_duration_and_stays_ended() -> void:
	if not _have():
		return
	var duration: float = Api.tuning("REFUSAL_CUE_DURATION_S")
	var cue: RefCounted = Api.new_cue()
	cue.call("start")
	_step(cue, duration - 0.01)
	assert_bool(_active(cue)).is_true()
	_step(cue, 0.02)
	assert_bool(_active(cue)).is_false()
	assert_float(_strength(cue)).is_equal_approx(BASE, TOLERANCE)
	_step(cue, 1.0)
	assert_bool(_active(cue)).is_false()
	assert_float(_strength(cue)).is_equal_approx(BASE, TOLERANCE)
	assert_int(cue.call("get_start_count")).is_equal(1)


func test_one_large_step_ends_the_cue_at_once() -> void:
	if not _have():
		return
	var cue: RefCounted = Api.new_cue()
	cue.call("start")
	_step(cue, 5.0)
	assert_bool(_active(cue)).is_false()
	assert_float(_strength(cue)).is_equal_approx(BASE, TOLERANCE)


func test_a_delta_of_zero_or_less_is_ignored() -> void:
	if not _have():
		return
	var cue: RefCounted = Api.new_cue()
	cue.call("start")
	_step(cue, 0.1)
	var elapsed: float = float(cue.call("get_elapsed_s"))
	_step(cue, 0.0)
	_step(cue, -0.5)
	assert_float(float(cue.call("get_elapsed_s"))).is_equal(elapsed)
	assert_bool(_active(cue)).is_true()


func test_a_step_without_a_start_does_nothing() -> void:
	if not _have():
		return
	var cue: RefCounted = Api.new_cue()
	_step(cue, 0.1)
	assert_bool(_active(cue)).is_false()
	assert_float(float(cue.call("get_elapsed_s"))).is_equal(0.0)
	assert_float(_strength(cue)).is_equal_approx(BASE, TOLERANCE)


func test_a_new_start_restarts_the_cue_and_does_not_stack() -> void:
	if not _have():
		return
	var peak: float = Api.tuning("REFUSAL_CUE_PEAK_STRENGTH")
	var cue: RefCounted = Api.new_cue()
	cue.call("start")
	_step(cue, 0.15)
	assert_float(_strength(cue)).is_equal_approx(peak, TOLERANCE)
	cue.call("start")
	assert_float(float(cue.call("get_elapsed_s"))).is_equal(0.0)
	assert_float(_strength(cue)).is_equal_approx(BASE, TOLERANCE)
	assert_int(cue.call("get_start_count")).is_equal(2)
	assert_bool(_active(cue)).is_true()
	# Another start in the middle of the run: still one state, never above the peak.
	_step(cue, 0.1)
	cue.call("start")
	_step(cue, 0.05)
	assert_float(_strength(cue)).is_equal_approx(TABLE[1], TOLERANCE)
	assert_int(cue.call("get_start_count")).is_equal(3)


func test_a_start_after_the_end_runs_the_full_cue_again() -> void:
	if not _have():
		return
	var cue: RefCounted = Api.new_cue()
	cue.call("start")
	_step(cue, 1.0)
	assert_bool(_active(cue)).is_false()
	cue.call("start")
	assert_bool(_active(cue)).is_true()
	_step(cue, 0.15)
	assert_float(_strength(cue)).is_equal_approx(TABLE[3], TOLERANCE)
	assert_int(cue.call("get_start_count")).is_equal(2)


func test_cancel_ends_the_cue_at_the_base_and_keeps_the_count() -> void:
	if not _have():
		return
	var cue: RefCounted = Api.new_cue()
	cue.call("start")
	_step(cue, 0.1)
	cue.call("cancel")
	assert_bool(_active(cue)).is_false()
	assert_float(_strength(cue)).is_equal_approx(BASE, TOLERANCE)
	assert_int(cue.call("get_start_count")).is_equal(1)
	_step(cue, 0.1)
	assert_bool(_active(cue)).is_false()
	cue.call("cancel")
	assert_bool(_active(cue)).is_false()


# --- addendum 2: the colour, power and lift curves (file group: developer, pure) ---


func _cream() -> Color:
	var material: ShaderMaterial = load(MATERIAL) as ShaderMaterial
	return material.get_shader_parameter("glow_colour")


func test_the_colour_follows_the_coral_phase_from_0_10_to_0_30_s() -> void:
	if not _have():
		return
	var cream: Color = _cream()
	for index: int in COLOUR_G.size():
		var got: Color = Api.cue_colour_at(STEP_S * index, cream)
		var label: String = "step %d" % index
		assert_float(got.r).override_failure_message(label).is_equal_approx(1.0, TOLERANCE)
		assert_float(got.g).override_failure_message(label).is_equal_approx(
			COLOUR_G[index], TOLERANCE
		)
		assert_float(got.b).override_failure_message(label).is_equal_approx(
			COLOUR_B[index], TOLERANCE
		)


func test_the_colour_is_the_base_outside_the_cue_time() -> void:
	if not _have():
		return
	var cream: Color = _cream()
	for t_s: float in [-0.05, 0.30, 0.31, 5.0]:
		assert_bool(Api.cue_colour_at(t_s, cream).is_equal_approx(cream)).is_true()
	# Before 0.10 s the colour has not started to move.
	assert_bool(Api.cue_colour_at(0.09, cream).g > 0.8).is_true()


func test_the_colour_reaches_the_cue_colour_at_0_20_s_and_is_not_the_base() -> void:
	if not _have():
		return
	var cue_colour: Variant = Api.constant(Api.TUNING, "REFUSAL_CUE_COLOUR", Color.BLACK)
	var at_peak: Color = Api.cue_colour_at(0.20, _cream())
	assert_bool(at_peak.is_equal_approx(cue_colour as Color)).is_true()
	assert_bool(at_peak.is_equal_approx(_cream())).is_false()


func test_the_fresnel_power_follows_the_table_and_is_the_base_outside() -> void:
	if not _have():
		return
	for index: int in POWER.size():
		(
			assert_float(Api.cue_power_at(STEP_S * index, 1.6))
			. override_failure_message("step %d" % index)
			. is_equal_approx(POWER[index], TOLERANCE)
		)
	for t_s: float in [-0.05, 0.30, 0.5]:
		assert_float(Api.cue_power_at(t_s, 1.6)).is_equal_approx(1.6, TOLERANCE)
	assert_float(Api.cue_power_at(0.15, 1.6)).is_equal_approx(
		Api.tuning("REFUSAL_CUE_PEAK_FRESNEL_POWER"), TOLERANCE
	)


func test_the_lift_follows_the_brightness_phase_from_0_to_0_20_s() -> void:
	if not _have():
		return
	for index: int in LIFT_G.size():
		var got: Vector3 = Api.cue_lift_at(STEP_S * index)
		var label: String = "step %d" % index
		assert_float(got.x).override_failure_message(label).is_equal_approx(0.0, TOLERANCE)
		assert_float(got.y).override_failure_message(label).is_equal_approx(
			LIFT_G[index], TOLERANCE
		)
		assert_float(got.z).override_failure_message(label).is_equal_approx(
			LIFT_B[index], TOLERANCE
		)


func test_the_lift_is_zero_outside_the_lift_time_and_has_no_red() -> void:
	if not _have():
		return
	for t_s: float in [-0.05, 0.20, 0.25, 0.30, 1.0]:
		assert_bool(Api.cue_lift_at(t_s).is_equal_approx(Vector3.ZERO)).is_true()
	for index: int in 61:
		assert_float(Api.cue_lift_at(0.005 * index).x).is_equal(0.0)


func test_the_lift_peaks_at_0_10_s_with_the_named_vector() -> void:
	if not _have():
		return
	var lift: Variant = Api.constant(Api.TUNING, "REFUSAL_CUE_LIFT", Vector3.ZERO)
	assert_bool(Api.cue_lift_at(0.10).is_equal_approx(lift as Vector3)).is_true()
