# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## decimal_text (pure) and format_number (language separator, placeholder) of LocalFormat.

const Rig := preload("res://tests/helpers/format_rig.gd")
const ErrorContains := preload("res://tests/helpers/error_contains.gd")

var _saved_locale: String = ""


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()


func after_test() -> void:
	TranslationServer.set_locale(_saved_locale)


func _text(value: float, decimals: int) -> String:
	return LocalFormat.decimal_text(value, decimals, ".")


# --- separator per language --------------------------------------------------------------


func test_english_uses_a_decimal_point() -> void:
	var rig: Rig = Rig.new("en")
	assert_str(rig.format.format_number(3.5, 1)).is_equal("3.5")


func test_hungarian_uses_a_decimal_comma() -> void:
	var rig: Rig = Rig.new("hu")
	assert_str(rig.format.format_number(3.5, 1)).is_equal("3,5")


func test_the_language_switch_takes_effect_on_the_very_next_call() -> void:
	var rig: Rig = Rig.new("en")
	assert_str(rig.format.format_number(3.5, 1)).is_equal("3.5")
	rig.language = "hu"
	assert_str(rig.format.format_number(3.5, 1)).is_equal("3,5")
	rig.language = "en"
	assert_str(rig.format.format_number(3.5, 1)).is_equal("3.5")


func test_the_separator_is_injected_into_the_pure_function() -> void:
	assert_str(LocalFormat.decimal_text(3.5, 1, "|")).is_equal("3|5")
	assert_str(LocalFormat.decimal_text(3.5, 1, ",")).is_equal("3,5")
	assert_str(LocalFormat.decimal_text(3.5, 1, "")).is_equal("35")
	assert_str(LocalFormat.decimal_text(3.5, 0, "|")).is_equal("4")


func test_an_unsupported_language_gives_the_english_separator_without_a_warning() -> void:
	for bad: Variant in ["", "de", "HU", 3, null, &"hu"]:
		var rig: Rig = Rig.new(bad)
		var result: Array[String] = []
		await (
			assert_error(func() -> void: result.append(rig.format.format_number(3.5, 1)))
			. is_success()
		)
		assert_array(result).override_failure_message("language %s" % [bad]).is_equal(["3.5"])


func test_an_invalid_language_callable_gives_the_english_separator() -> void:
	var format: LocalFormat = LocalFormat.new(
		Callable(), func() -> Variant: return 0, func() -> Variant: return 0
	)
	var result: Array[String] = []
	await assert_error(func() -> void: result.append(format.format_number(3.5, 1))).is_success()
	assert_array(result).is_equal(["3.5"])


# --- rounding ----------------------------------------------------------------------------


func test_rounding_half_away_from_zero_examples() -> void:
	assert_str(_text(2.25, 1)).is_equal("2.3")
	assert_str(_text(2.349, 1)).is_equal("2.3")
	assert_str(_text(-2.25, 1)).is_equal("-2.3")
	assert_str(_text(0.25, 1)).is_equal("0.3")


func test_rounding_is_judged_on_the_value_as_written() -> void:
	assert_str(_text(1.15, 1)).is_equal("1.2")
	assert_str(_text(-1.15, 1)).is_equal("-1.2")
	assert_str(_text(2.675, 2)).is_equal("2.68")
	assert_str(_text(1.005, 2)).is_equal("1.01")
	assert_str(_text(0.1 + 0.2, 1)).is_equal("0.3")
	assert_str(_text(0.1 + 0.2, 6)).is_equal("0.300000")


func test_a_carry_runs_through_nines() -> void:
	assert_str(_text(9.995, 2)).is_equal("10.00")
	assert_str(_text(9.95, 1)).is_equal("10.0")
	assert_str(_text(0.999, 2)).is_equal("1.00")
	assert_str(_text(99.5, 0)).is_equal("100")
	assert_str(_text(-99.5, 0)).is_equal("-100")
	assert_str(_text(0.95, 1)).is_equal("1.0")


func test_exactly_the_requested_decimals_are_always_shown() -> void:
	assert_str(_text(2.0, 1)).is_equal("2.0")
	assert_str(_text(2.0, 3)).is_equal("2.000")
	assert_str(_text(2.5, 3)).is_equal("2.500")
	assert_str(_text(0.0, 2)).is_equal("0.00")
	assert_str(LocalFormat.decimal_text(2.0, 1, ",")).is_equal("2,0")
	assert_str(Rig.new("hu").format.format_number(2.0, 1)).is_equal("2,0")
	assert_str(Rig.new("en").format.format_number(2.0, 1)).is_equal("2.0")


func test_zero_decimals_show_no_separator() -> void:
	assert_str(_text(3.5, 0)).is_equal("4")
	assert_str(_text(2.4, 0)).is_equal("2")
	assert_str(_text(2.5, 0)).is_equal("3")
	assert_str(_text(0.4, 0)).is_equal("0")
	assert_str(Rig.new("hu").format.format_number(3.5, 0)).is_equal("4")


func test_small_values_round_and_pad() -> void:
	assert_str(_text(0.25, 6)).is_equal("0.250000")
	assert_str(_text(1e-7, 6)).is_equal("0.000000")
	assert_str(_text(5e-7, 6)).is_equal("0.000001")
	assert_str(_text(0.000001, 6)).is_equal("0.000001")
	assert_str(_text(0.05, 1)).is_equal("0.1")
	assert_str(_text(0.04, 1)).is_equal("0.0")


func test_an_int_input_is_accepted() -> void:
	var english: Rig = Rig.new("en")
	assert_str(english.format.format_number(12, 0)).is_equal("12")
	assert_str(english.format.format_number(12, 1)).is_equal("12.0")
	var hungarian: Rig = Rig.new("hu")
	assert_str(hungarian.format.format_number(12, 0)).is_equal("12")
	assert_str(hungarian.format.format_number(12, 1)).is_equal("12,0")
	assert_str(hungarian.format.format_number(-12, 1)).is_equal("-12,0")
	assert_str(hungarian.format.format_number(0, 2)).is_equal("0,00")


# --- sign --------------------------------------------------------------------------------


func test_a_negative_number_has_a_leading_hyphen_minus() -> void:
	assert_str(Rig.new("hu").format.format_number(-3.5, 1)).is_equal("-3,5")
	assert_str(Rig.new("en").format.format_number(-3.5, 1)).is_equal("-3.5")
	assert_str(_text(-3.5, 0)).is_equal("-4")
	assert_str(_text(-0.5, 0)).is_equal("-1")
	assert_bool(_text(-3.5, 1).begins_with("-")).is_true()
	assert_int(_text(-3.5, 1).unicode_at(0)).is_equal(45)


func test_a_value_that_rounds_to_zero_is_never_negative_zero() -> void:
	assert_str(_text(-0.04, 1)).is_equal("0.0")
	assert_str(_text(-0.0, 1)).is_equal("0.0")
	assert_str(_text(-0.4, 0)).is_equal("0")
	assert_str(_text(-0.0000001, 6)).is_equal("0.000000")
	assert_str(Rig.new("hu").format.format_number(-0.04, 1)).is_equal("0,0")
	assert_str(Rig.new("hu").format.format_number(-0.0, 1)).is_equal("0,0")
	assert_str(Rig.new("en").format.format_number(-0.04, 1)).is_equal("0.0")


# --- size --------------------------------------------------------------------------------


func test_no_digit_grouping() -> void:
	assert_str(Rig.new("en").format.format_number(1234567.5, 1)).is_equal("1234567.5")
	assert_str(Rig.new("hu").format.format_number(1234567.5, 1)).is_equal("1234567,5")
	assert_str(_text(1000.0, 0)).is_equal("1000")


func test_a_huge_value_is_printed_in_full_digits() -> void:
	assert_str(_text(1e20, 0)).is_equal("100000000000000000000")
	assert_str(_text(1e20, 2)).is_equal("100000000000000000000.00")
	assert_str(_text(-1e20, 0)).is_equal("-100000000000000000000")
	assert_str(_text(1e15, 0)).is_equal("1000000000000000")
	assert_str(_text(1.2345678901234568e17, 0)).is_equal("123456789012345680")
	assert_str(_text(1e22, 0)).is_equal("10000000000000000000000")
	assert_str(Rig.new("en").format.format_number(1e20, 0)).is_equal("100000000000000000000")
	assert_bool(_text(1e300, 0).contains("e")).is_false()
	assert_int(_text(1e300, 0).length()).is_equal(301)


func test_a_huge_int_is_printed_in_full_digits() -> void:
	assert_str(Rig.new("en").format.format_number(int(1e18), 0)).is_equal("1000000000000000000")
	assert_str(Rig.new("hu").format.format_number(int(1e18), 1)).is_equal("1000000000000000000,0")


func test_a_tiny_value_has_no_exponent_text() -> void:
	assert_str(_text(1e-7, 6)).is_equal("0.000000")
	assert_str(_text(1e-300, 6)).is_equal("0.000000")
	assert_str(_text(5e-324, 6)).is_equal("0.000000")


func test_the_result_is_plain_text_without_a_unit() -> void:
	var text: String = Rig.new("hu").format.format_number(24.5, 1)
	assert_str(text).is_equal("24,5")
	assert_str(text + " °C").is_equal("24,5 °C")


func test_the_argument_is_not_changed() -> void:
	var value: float = 3.456
	Rig.new("en").format.format_number(value, 1)
	assert_float(value).is_equal(3.456)


# --- decimal count clamp -----------------------------------------------------------------


func test_a_negative_decimal_count_acts_as_zero_with_a_warning() -> void:
	var result: Array[String] = []
	await (
		assert_error(func() -> void: result.append(_text(3.5, -1)))
		. is_push_warning(ErrorContains.new("LocalFormat: decimals clamped"))
	)
	assert_array(result).is_equal(["4"])


func test_a_decimal_count_above_six_acts_as_six_with_a_warning() -> void:
	var result: Array[String] = []
	await (
		assert_error(func() -> void: result.append(_text(3.5, 7)))
		. is_push_warning(ErrorContains.new("LocalFormat: decimals clamped"))
	)
	assert_array(result).is_equal(["3.500000"])


func test_the_entry_point_clamps_the_decimals_with_a_warning() -> void:
	var rig: Rig = Rig.new("hu")
	var result: Array[String] = []
	await (
		assert_error(func() -> void: result.append(rig.format.format_number(3.5, 99)))
		. is_push_warning(ErrorContains.new("LocalFormat: decimals clamped"))
	)
	await (
		assert_error(func() -> void: result.append(rig.format.format_number(3.5, -5)))
		. is_push_warning(ErrorContains.new("LocalFormat: decimals clamped"))
	)
	assert_array(result).is_equal(["3,500000", "4"])


func test_the_decimal_counts_zero_and_six_log_no_warning() -> void:
	await (assert_error(func() -> void: _text_pair(Rig.new("hu"))).is_success())


# --- NaN and infinity --------------------------------------------------------------------


func test_the_pure_function_returns_an_empty_string_for_nan_and_infinity() -> void:
	assert_str(_text(NAN, 1)).is_empty()
	assert_str(_text(INF, 1)).is_empty()
	assert_str(_text(-INF, 0)).is_empty()


func test_the_entry_point_gives_the_english_placeholder_and_a_warning() -> void:
	TranslationServer.set_locale("en")
	var rig: Rig = Rig.new("en")
	for bad: float in [NAN, INF, -INF]:
		var result: Array[String] = []
		await (
			assert_error(func() -> void: result.append(rig.format.format_number(bad, 1)))
			. is_push_warning(ErrorContains.new("LocalFormat: number is not finite"))
		)
		assert_array(result).is_equal(["Unknown"])


func test_the_entry_point_gives_the_hungarian_placeholder_and_a_warning() -> void:
	TranslationServer.set_locale("hu")
	var rig: Rig = Rig.new("hu")
	for bad: float in [NAN, INF, -INF]:
		var result: Array[String] = []
		await (
			assert_error(func() -> void: result.append(rig.format.format_number(bad, 1)))
			. is_push_warning(ErrorContains.new("LocalFormat: number is not finite"))
		)
		assert_array(result).is_equal(["Ismeretlen"])


func test_the_number_placeholder_follows_the_locale_not_the_injected_language() -> void:
	TranslationServer.set_locale("hu")
	var rig: Rig = Rig.new("en")
	var result: Array[String] = []
	await (
		assert_error(func() -> void: result.append(rig.format.format_number(NAN, 1)))
		. is_push_warning(ErrorContains.new("LocalFormat: number is not finite"))
	)
	assert_array(result).is_equal(["Ismeretlen"])
	assert_str(rig.format.format_number(3.5, 1)).is_equal("3.5")


func test_deterministic_repeated_calls() -> void:
	var rig: Rig = Rig.new("hu")
	var first: String = rig.format.format_number(2.675, 2)
	assert_str(first).is_equal("2,68")
	for _i: int in range(5):
		assert_str(rig.format.format_number(2.675, 2)).is_equal(first)


func _text_pair(rig: Rig) -> Array[String]:
	return [_text(3.5, 0), _text(3.5, 6), rig.format.format_number(3.5, 6)]
