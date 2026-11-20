extends GdUnitTestSuite
## #31 AC 12 (owner: developer): RotationStep, static and pure. Comma (+1, left) turns
## counter-clockwise, a positive change of rotation_y; Period (-1, right) turns clockwise. The
## rule is additive (owner correction 2026-11-20): without Shift every press adds or subtracts
## exactly 15 degrees, so 10 becomes 25 and 100 becomes 85; there is no snapping to multiples of
## 15. With Shift (fine) a press moves by exactly 1 degree. Results are normalised to 0 up to
## below 360 (360 becomes 0). Non-finite input gives a finite result and no engine error. The
## step sizes are read from PlacementTuning, never repeated as literals where the constant is the
## point; the AC numbers (15, 25, 115, 85, 355, 345, 1, 359) are the test cases themselves.

const Api := preload("res://tests/helpers/placement_api.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")


func _have() -> bool:
	var found: bool = Api.exists(Api.STEP) and Api.exists(Api.TUNING)
	(
		assert_bool(found)
		. override_failure_message("rotation_step.gd or placement_tuning.gd is missing")
		. is_true()
	)
	return found


func _left(deg: float, fine: bool = false) -> float:
	return Api.step(deg, 1, fine)


func _right(deg: float, fine: bool = false) -> float:
	return Api.step(deg, -1, fine)


func test_ac12_the_tuning_constants_are_15_and_1_degree() -> void:
	if not _have():
		return
	assert_float(Api.tuning("ROTATION_STEP_DEG")).is_equal(15.0)
	assert_float(Api.tuning("FINE_STEP_DEG")).is_equal(1.0)


func test_ac12_left_from_an_exact_multiple_adds_one_step() -> void:
	if not _have():
		return
	var step: float = Api.tuning("ROTATION_STEP_DEG")
	assert_float(_left(0.0)).is_equal_approx(step, 0.0001)
	assert_float(_left(15.0)).is_equal_approx(30.0, 0.0001)
	assert_float(_left(330.0)).is_equal_approx(345.0, 0.0001)


func test_ac12_left_wraps_from_345_to_0() -> void:
	if not _have():
		return
	assert_float(_left(345.0)).is_equal_approx(0.0, 0.0001)


func test_ac12_left_from_a_free_angle_adds_a_whole_step_and_does_not_snap() -> void:
	if not _have():
		return
	assert_float(_left(10.0)).is_equal_approx(25.0, 0.0001)
	assert_float(_left(100.0)).is_equal_approx(115.0, 0.0001)
	assert_float(_left(104.9)).is_equal_approx(119.9, 0.0001)
	assert_float(_left(0.5)).is_equal_approx(15.5, 0.0001)
	assert_float(_left(359.5)).is_equal_approx(14.5, 0.0001)
	assert_float(_left(350.0)).is_equal_approx(5.0, 0.0001)


func test_ac12_right_from_an_exact_multiple_subtracts_one_step() -> void:
	if not _have():
		return
	assert_float(_right(15.0)).is_equal_approx(0.0, 0.0001)
	assert_float(_right(30.0)).is_equal_approx(15.0, 0.0001)


func test_ac12_right_wraps_from_0_to_345() -> void:
	if not _have():
		return
	assert_float(_right(0.0)).is_equal_approx(345.0, 0.0001)


func test_ac12_right_from_a_free_angle_subtracts_a_whole_step_and_does_not_snap() -> void:
	if not _have():
		return
	assert_float(_right(100.0)).is_equal_approx(85.0, 0.0001)
	assert_float(_right(10.0)).is_equal_approx(355.0, 0.0001)
	assert_float(_right(90.1)).is_equal_approx(75.1, 0.0001)
	assert_float(_right(0.5)).is_equal_approx(345.5, 0.0001)
	assert_float(_right(14.0)).is_equal_approx(359.0, 0.0001)


func test_ac12_24_steps_of_15_degrees_return_to_the_start_from_any_angle() -> void:
	if not _have():
		return
	for start: float in [0.0, 10.0, 37.5, 100.0, 359.5]:
		for direction: int in [1, -1]:
			var angle: float = start
			for index: int in 24:
				angle = Api.step(angle, direction, false)
			var gap: float = absf(wrapf(angle - start, -180.0, 180.0))
			(
				assert_float(gap)
				. override_failure_message("24 steps from %s ended at %s" % [start, angle])
				. is_less(0.001)
			)


func test_ac12_fine_steps_move_by_exactly_one_degree() -> void:
	if not _have():
		return
	var fine: float = Api.tuning("FINE_STEP_DEG")
	assert_float(_left(0.0, true)).is_equal_approx(fine, 0.0001)
	assert_float(_right(0.0, true)).is_equal_approx(360.0 - fine, 0.0001)
	assert_float(_left(37.0, true)).is_equal_approx(38.0, 0.0001)
	assert_float(_right(37.0, true)).is_equal_approx(36.0, 0.0001)
	assert_float(_left(37.5, true)).is_equal_approx(38.5, 0.0001)
	assert_float(_left(359.0, true)).is_equal_approx(0.0, 0.0001)
	assert_float(_right(0.5, true)).is_equal_approx(359.5, 0.0001)


func test_ac12_large_and_negative_stored_angles_are_normalised_first() -> void:
	if not _have():
		return
	assert_float(_left(-30.0)).is_equal_approx(345.0, 0.0001)
	assert_float(_right(-10.0)).is_equal_approx(335.0, 0.0001)
	assert_float(_left(750.0)).is_equal_approx(45.0, 0.0001)
	assert_float(_right(370.0)).is_equal_approx(355.0, 0.0001)
	assert_float(_left(-90.0, true)).is_equal_approx(271.0, 0.0001)
	assert_float(_right(720.0, true)).is_equal_approx(359.0, 0.0001)


func test_ac12_normalise_gives_zero_up_to_below_360() -> void:
	if not _have():
		return
	assert_float(Api.normalise(0.0)).is_equal_approx(0.0, 0.0001)
	assert_float(Api.normalise(360.0)).is_equal_approx(0.0, 0.0001)
	assert_float(Api.normalise(720.0)).is_equal_approx(0.0, 0.0001)
	assert_float(Api.normalise(-360.0)).is_equal_approx(0.0, 0.0001)
	assert_float(Api.normalise(-1.0)).is_equal_approx(359.0, 0.0001)
	assert_float(Api.normalise(361.5)).is_equal_approx(1.5, 0.0001)
	assert_float(Api.normalise(359.99)).is_equal_approx(359.99, 0.0001)


func test_ac12_every_result_is_in_range_for_a_sweep_of_inputs() -> void:
	if not _have():
		return
	for angle: float in [
		-1000.0, -360.0, -0.001, 0.0, 0.001, 14.999, 15.0, 179.5, 359.999, 360.0, 1e6
	]:
		for direction: int in [1, -1]:
			for fine: bool in [false, true]:
				var result: float = Api.step(angle, direction, fine)
				(
					assert_bool(result >= 0.0 and result < 360.0)
					. override_failure_message(
						(
							"step(%s, %d, %s) = %s is outside [0, 360)"
							% [angle, direction, fine, result]
						)
					)
					. is_true()
				)


func test_ac12_non_finite_input_gives_a_finite_angle_in_range_and_no_error() -> void:
	if not _have():
		return
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void:
			for bad: float in [NAN, INF, -INF]:
				var normalised: float = Api.normalise(bad)
				(
					assert_bool(is_finite(normalised) and normalised >= 0.0 and normalised < 360.0)
					. is_true()
				)
				for direction: int in [1, -1]:
					for fine: bool in [false, true]:
						var stepped: float = Api.step(bad, direction, fine)
						(
							assert_bool(is_finite(stepped) and stepped >= 0.0 and stepped < 360.0)
							. is_true()
						)
	)
	assert_dict(seen["errors"]).is_empty()
	assert_dict(seen["warnings"]).is_empty()
	assert_dict(seen["script_errors"]).is_empty()
