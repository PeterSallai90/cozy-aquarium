# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## The date, time and date-time entry points of LocalFormat with injected language, offset and
## clock. Format tests never depend on the TranslationServer locale; only the placeholder tests
## set it (and restore it).

const Rig := preload("res://tests/helpers/format_rig.gd")
const ErrorContains := preload("res://tests/helpers/error_contains.gd")

const JANUARY: int = Rig.CLOCK_JANUARY
const JULY: int = Rig.CLOCK_JULY
const NOVEMBER: int = Rig.CLOCK_NOVEMBER

var _saved_locale: String = ""


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()


func after_test() -> void:
	TranslationServer.set_locale(_saved_locale)


## Local date and time of a stamp for a clock and offset, in English.
func _local(stamp: Variant, offset: Variant, now: int, language: Variant = "en") -> String:
	return Rig.new(language, offset, now).format.format_datetime(stamp)


# --- the formats -------------------------------------------------------------------------


func test_english_date_and_time() -> void:
	var rig: Rig = Rig.new("en", 0, JANUARY)
	assert_str(rig.format.format_date("2026-11-01T16:37:00Z")).is_equal("2026-11-01")
	assert_str(rig.format.format_time("2026-11-01T16:37:00Z")).is_equal("16:37")


func test_hungarian_date_and_time() -> void:
	var rig: Rig = Rig.new("hu", 0, JANUARY)
	assert_str(rig.format.format_date("2026-11-01T16:37:00Z")).is_equal("2026. 11. 01.")
	assert_str(rig.format.format_time("2026-11-01T16:37:00Z")).is_equal("16:37")


func test_date_plus_time_in_both_languages() -> void:
	var english: Rig = Rig.new("en", 0, JANUARY)
	assert_str(english.format.format_datetime("2026-11-01T16:37:00Z")).is_equal("2026-11-01 16:37")
	var hungarian: Rig = Rig.new("hu", 0, JANUARY)
	assert_str(hungarian.format.format_datetime("2026-11-01T16:37:00Z")).is_equal(
		"2026. 11. 01. 16:37"
	)


func test_the_time_is_24_hour_with_two_digit_hours_and_no_seconds() -> void:
	var rig: Rig = Rig.new("en", 0, JANUARY)
	assert_str(rig.format.format_time("2026-11-01T09:05:00Z")).is_equal("09:05")
	assert_str(rig.format.format_time("2026-11-01T00:30:00Z")).is_equal("00:30")
	assert_str(rig.format.format_time("2026-11-01T23:59:59Z")).is_equal("23:59")
	assert_str(rig.format.format_time("2026-11-01T16:37:59Z")).is_equal("16:37")
	assert_str(rig.format.format_time("2026-11-01T12:00:00Z")).is_equal("12:00")


func test_month_and_day_are_zero_padded() -> void:
	var rig: Rig = Rig.new("en", 0, JANUARY)
	assert_str(rig.format.format_date("2026-02-03T12:00:00Z")).is_equal("2026-02-03")
	rig.language = "hu"
	assert_str(rig.format.format_date("2026-02-03T12:00:00Z")).is_equal("2026. 02. 03.")


func test_the_text_is_only_digits_and_separators() -> void:
	var regex: RegEx = RegEx.new()
	regex.compile("^[0-9: .\\-]+$")
	for language: String in ["en", "hu"]:
		var rig: Rig = Rig.new(language, 60, NOVEMBER)
		var text: String = rig.format.format_datetime("2026-11-01T16:37:00Z")
		assert_bool(regex.search(text) != null).override_failure_message(text).is_true()
		assert_bool(text.contains("AM") or text.contains("PM")).is_false()


func test_a_unix_time_gives_the_same_text_as_the_stored_form() -> void:
	var rig: Rig = Rig.new("en", 60, NOVEMBER)
	var from_text: String = rig.format.format_datetime("2026-11-01T15:37:00Z")
	assert_str(from_text).is_equal("2026-11-01 16:37")
	assert_str(rig.format.format_datetime(NOVEMBER + 15 * 3600 + 37 * 60)).is_equal(from_text)
	assert_str(rig.format.format_datetime(float(NOVEMBER + 15 * 3600 + 37 * 60))).is_equal(
		from_text
	)
	assert_str(rig.format.format_datetime(NOVEMBER + 15 * 3600 + 37 * 60 + 0.9)).is_equal(from_text)


func test_unix_time_zero_and_the_maximum() -> void:
	var rig: Rig = Rig.new("en", 0, JANUARY)
	assert_str(rig.format.format_datetime(0)).is_equal("1970-01-01 00:00")
	assert_str(rig.format.format_datetime(LocalFormat.MAX_UNIX)).is_equal("9999-12-31 23:59")


# --- language switch, determinism, purity ------------------------------------------------


func test_the_language_switch_takes_effect_on_the_very_next_call() -> void:
	var rig: Rig = Rig.new("en", 60, NOVEMBER)
	var stamp: String = "2026-11-01T15:37:00Z"
	assert_str(rig.format.format_datetime(stamp)).is_equal("2026-11-01 16:37")
	rig.language = "hu"
	assert_str(rig.format.format_datetime(stamp)).is_equal("2026. 11. 01. 16:37")
	assert_str(rig.format.format_date(stamp)).is_equal("2026. 11. 01.")
	rig.language = "en"
	assert_str(rig.format.format_datetime(stamp)).is_equal("2026-11-01 16:37")
	assert_str(rig.format.format_date(stamp)).is_equal("2026-11-01")


func test_the_same_inputs_give_the_same_text() -> void:
	var rig: Rig = Rig.new("hu", 60, NOVEMBER)
	var first: String = rig.format.format_datetime("2026-07-01T12:00:00Z")
	for _i: int in range(5):
		assert_str(rig.format.format_datetime("2026-07-01T12:00:00Z")).is_equal(first)
	assert_str(Rig.new("hu", 60, NOVEMBER).format.format_datetime("2026-07-01T12:00:00Z")).is_equal(
		first
	)


func test_a_changed_offset_or_clock_changes_the_next_result() -> void:
	var rig: Rig = Rig.new("en", 60, NOVEMBER)
	var stamp: String = "2026-01-15T12:00:00Z"
	assert_str(rig.format.format_time(stamp)).is_equal("13:00")
	rig.offset = 120
	assert_str(rig.format.format_time(stamp)).is_equal("14:00")
	rig.offset = 120
	rig.now = JULY
	assert_str(rig.format.format_time(stamp)).is_equal("13:00")
	rig.now = NOVEMBER
	assert_str(rig.format.format_time(stamp)).is_equal("14:00")


func test_display_never_changes_the_stored_value() -> void:
	var rig: Rig = Rig.new("hu", 120, JULY)
	var text: String = "2026-11-01T16:37:00Z"
	var number: float = 1782864000.5
	var count: int = 1782864000
	rig.format.format_datetime(text)
	rig.format.format_datetime(number)
	rig.format.format_datetime(count)
	assert_str(text).is_equal("2026-11-01T16:37:00Z")
	assert_float(number).is_equal(1782864000.5)
	assert_int(count).is_equal(1782864000)


func test_a_valid_call_logs_nothing() -> void:
	var rig: Rig = Rig.new("hu", 60, NOVEMBER)
	await (assert_error(func() -> void: _format_all(rig, "2026-11-01T16:37:00Z")).is_success())


# --- the DST rule through the entry points -----------------------------------------------


func test_example_a_helsinki_in_summer() -> void:
	assert_str(_local("2026-01-15T12:00:00Z", 180, JULY)).is_equal("2026-01-15 14:00")


func test_example_b_moscow_in_winter() -> void:
	assert_str(_local("2026-07-01T12:00:00Z", 180, NOVEMBER)).is_equal("2026-07-01 15:00")


func test_example_c_negative_offset_is_never_corrected() -> void:
	assert_str(_local("2026-01-15T12:00:00Z", -60, JULY)).is_equal("2026-01-15 11:00")
	assert_str(_local("2026-01-15T12:00:00Z", -60, NOVEMBER)).is_equal("2026-01-15 11:00")
	assert_str(_local("2026-01-15T12:00:00Z", -120, JULY)).is_equal("2026-01-15 10:00")
	assert_str(_local("2026-01-15T12:00:00Z", -120, NOVEMBER)).is_equal("2026-01-15 10:00")


func test_example_d_lisbon_in_winter() -> void:
	assert_str(_local("2026-07-01T12:00:00Z", 0, JANUARY)).is_equal("2026-07-01 13:00")


func test_example_e_the_azores_in_summer() -> void:
	assert_str(_local("2026-01-15T12:00:00Z", 0, JULY)).is_equal("2026-01-15 12:00")


func test_a_summer_stamp_viewed_in_winter_shows_summer_time() -> void:
	assert_str(_local("2026-07-01T12:00:00Z", 60, NOVEMBER)).is_equal("2026-07-01 14:00")


func test_a_winter_stamp_viewed_in_summer_shows_winter_time() -> void:
	assert_str(_local("2026-01-15T12:00:00Z", 120, JULY)).is_equal("2026-01-15 13:00")


func test_the_change_over_edges_of_2026() -> void:
	assert_str(_local("2026-03-29T00:59:59Z", 60, NOVEMBER)).is_equal("2026-03-29 01:59")
	assert_str(_local("2026-03-29T01:00:00Z", 60, NOVEMBER)).is_equal("2026-03-29 03:00")
	assert_str(_local("2026-10-25T00:59:59Z", 60, NOVEMBER)).is_equal("2026-10-25 02:59")
	assert_str(_local("2026-10-25T01:00:00Z", 60, NOVEMBER)).is_equal("2026-10-25 02:00")


func test_the_change_over_edges_of_2025() -> void:
	assert_str(_local("2025-03-30T00:59:59Z", 60, NOVEMBER)).is_equal("2025-03-30 01:59")
	assert_str(_local("2025-03-30T01:00:00Z", 60, NOVEMBER)).is_equal("2025-03-30 03:00")
	assert_str(_local("2025-10-26T00:59:59Z", 60, NOVEMBER)).is_equal("2025-10-26 02:59")
	assert_str(_local("2025-10-26T01:00:00Z", 60, NOVEMBER)).is_equal("2025-10-26 02:00")


func test_the_change_over_edges_of_2027() -> void:
	assert_str(_local("2027-03-28T00:59:59Z", 60, NOVEMBER)).is_equal("2027-03-28 01:59")
	assert_str(_local("2027-03-28T01:00:00Z", 60, NOVEMBER)).is_equal("2027-03-28 03:00")
	assert_str(_local("2027-10-31T00:59:59Z", 60, NOVEMBER)).is_equal("2027-10-31 02:59")
	assert_str(_local("2027-10-31T01:00:00Z", 60, NOVEMBER)).is_equal("2027-10-31 02:00")


func test_the_local_hour_02_never_appears_in_spring_and_appears_twice_in_autumn() -> void:
	var rig: Rig = Rig.new("en", 60, NOVEMBER)
	var spring_start: int = LocalFormat.parse_timestamp("2026-03-29T00:00:00Z")
	var spring_hours: Array[String] = []
	for step: int in range(0, 4 * 3600, 600):
		spring_hours.append(rig.format.format_time(spring_start + step).substr(0, 2))
	assert_array(spring_hours).not_contains(["02"])
	var autumn_start: int = LocalFormat.parse_timestamp("2026-10-24T23:00:00Z")
	var count: int = 0
	for step: int in range(0, 4 * 3600, 600):
		if rig.format.format_time(autumn_start + step).begins_with("02:"):
			count += 1
	assert_int(count).is_equal(12)


func test_midnight_rollover_to_the_next_day() -> void:
	var rig: Rig = Rig.new("en", 120, JULY)
	assert_str(rig.format.format_date("2026-06-30T22:30:00Z")).is_equal("2026-07-01")
	assert_str(rig.format.format_time("2026-06-30T22:30:00Z")).is_equal("00:30")


func test_year_rollover_to_the_next_year() -> void:
	var rig: Rig = Rig.new("en", 60, NOVEMBER)
	assert_str(rig.format.format_date("2026-12-31T23:30:00Z")).is_equal("2027-01-01")
	assert_str(rig.format.format_time("2026-12-31T23:30:00Z")).is_equal("00:30")
	rig.language = "hu"
	assert_str(rig.format.format_date("2026-12-31T23:30:00Z")).is_equal("2027. 01. 01.")


func test_a_rollover_back_to_the_previous_day() -> void:
	var rig: Rig = Rig.new("en", -300, NOVEMBER)
	assert_str(rig.format.format_datetime("2027-01-01T02:00:00Z")).is_equal("2026-12-31 21:00")


func test_leap_day_rollover() -> void:
	var rig: Rig = Rig.new("en", 60, NOVEMBER)
	assert_str(rig.format.format_date("2028-02-28T23:30:00Z")).is_equal("2028-02-29")
	assert_str(rig.format.format_date("2028-02-29T23:30:00Z")).is_equal("2028-03-01")
	assert_str(rig.format.format_date("2027-02-28T23:30:00Z")).is_equal("2027-03-01")


func test_non_eu_offsets_get_no_correction_in_either_season() -> void:
	for offset: int in [-300, 330, 540]:
		for now: int in [JANUARY, JULY, NOVEMBER]:
			var winter: String = _local("2026-01-15T12:00:00Z", offset, now)
			var summer: String = _local("2026-07-01T12:00:00Z", offset, now)
			var shift: int = offset * 60
			var winter_expected: String = Time.get_datetime_string_from_unix_time(
				JANUARY + 12 * 3600 + shift
			)
			var summer_expected: String = Time.get_datetime_string_from_unix_time(
				JULY + 12 * 3600 + shift
			)
			assert_str(winter).is_equal(_expected_text(winter_expected))
			assert_str(summer).is_equal(_expected_text(summer_expected))


func _expected_text(iso: String) -> String:
	return iso.substr(0, 16).replace("T", " ")


# --- years outside 1970 to 9999 ----------------------------------------------------------


func test_a_local_year_before_1970_is_shown_as_it_is() -> void:
	var rig: Rig = Rig.new("en", -720, NOVEMBER)
	assert_str(rig.format.format_date("1970-01-01T00:00:00Z")).is_equal("1969-12-31")
	assert_str(rig.format.format_time("1970-01-01T00:00:00Z")).is_equal("12:00")
	rig.language = "hu"
	assert_str(rig.format.format_date("1970-01-01T00:00:00Z")).is_equal("1969. 12. 31.")


func test_a_local_year_after_9999_is_shown_with_five_digits() -> void:
	var rig: Rig = Rig.new("en", 840, NOVEMBER)
	assert_str(rig.format.format_date("9999-12-31T23:30:00Z")).is_equal("10000-01-01")
	assert_str(rig.format.format_time("9999-12-31T23:30:00Z")).is_equal("13:30")
	rig.language = "hu"
	assert_str(rig.format.format_date("9999-12-31T23:30:00Z")).is_equal("10000. 01. 01.")


func test_the_out_of_range_years_never_give_the_unknown_text() -> void:
	TranslationServer.set_locale("en")
	var rig: Rig = Rig.new("en", -720, NOVEMBER)
	assert_str(rig.format.format_datetime(0)).is_not_equal(tr("datetime.unknown"))
	assert_str(rig.format.format_datetime(0)).is_equal("1969-12-31 12:00")


# --- offset range ------------------------------------------------------------------------


func test_every_offset_in_the_valid_range_works_for_every_sample_stamp() -> void:
	var stamps: Array = [
		"1970-01-01T00:00:00Z",
		"2026-03-29T01:00:00Z",
		"2026-10-25T00:59:59Z",
		"2026-12-31T23:59:59Z",
		"9999-12-31T23:59:59Z",
		0,
		LocalFormat.MAX_UNIX,
	]
	var regex: RegEx = RegEx.new()
	regex.compile("^[0-9]{4,5}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}$")
	var rig: Rig = Rig.new("en", 0, NOVEMBER)
	for now: int in [JANUARY, JULY, NOVEMBER]:
		rig.now = now
		for offset: int in range(-720, 841, 15):
			rig.offset = offset
			for stamp: Variant in stamps:
				var text: String = rig.format.format_datetime(stamp)
				(
					assert_bool(regex.search(text) != null)
					. override_failure_message("%d %d %s: '%s'" % [now, offset, stamp, text])
					. is_true()
				)


func test_the_range_limits_are_used_as_they_are() -> void:
	assert_str(_local("2026-01-15T12:00:00Z", -720, NOVEMBER)).is_equal("2026-01-15 00:00")
	assert_str(_local("2026-01-15T12:00:00Z", 840, NOVEMBER)).is_equal("2026-01-16 02:00")


func test_an_offset_below_the_range_is_clamped_with_a_warning() -> void:
	var rig: Rig = Rig.new("en", -1000, NOVEMBER)
	var result: Array[String] = []
	await (
		assert_error(
			func() -> void: result.append(rig.format.format_datetime("2026-01-15T12:00:00Z"))
		)
		. is_push_warning(ErrorContains.new("LocalFormat: offset"))
	)
	assert_array(result).is_equal(["2026-01-15 00:00"])


func test_an_offset_above_the_range_is_clamped_with_a_warning() -> void:
	var rig: Rig = Rig.new("en", 2000, NOVEMBER)
	var result: Array[String] = []
	await (
		assert_error(
			func() -> void: result.append(rig.format.format_datetime("2026-01-15T12:00:00Z"))
		)
		. is_push_warning(ErrorContains.new("LocalFormat: offset"))
	)
	assert_array(result).is_equal(["2026-01-16 02:00"])


func test_a_non_int_offset_becomes_zero_with_a_warning() -> void:
	# Offset 0 in the winter clock is the "Lisbon in winter" case, so a January stamp shows 12:00.
	for bad: Variant in [90.0, "x", null, [], 60.5]:
		var rig: Rig = Rig.new("en", bad, JANUARY)
		var result: Array[String] = []
		await (
			assert_error(
				func() -> void: result.append(rig.format.format_time("2026-01-15T12:00:00Z"))
			)
			. is_push_warning(ErrorContains.new("LocalFormat: offset"))
		)
		assert_array(result).is_equal(["12:00"])


func test_an_invalid_offset_callable_becomes_zero_with_a_warning() -> void:
	var format: LocalFormat = LocalFormat.new(
		func() -> Variant: return "en", Callable(), func() -> Variant: return JANUARY
	)
	var result: Array[String] = []
	await (
		assert_error(func() -> void: result.append(format.format_time("2026-01-15T12:00:00Z")))
		. is_push_warning(ErrorContains.new("LocalFormat: offset"))
	)
	assert_array(result).is_equal(["12:00"])


func test_the_clamped_offset_goes_through_the_rule() -> void:
	# -1000 clamps to -720, which is never corrected, in summer and in winter.
	var rig: Rig = Rig.new("en", -1000, JULY)
	var result: Array[String] = []
	await (
		assert_error(func() -> void: result.append(rig.format.format_time("2026-07-01T12:00:00Z")))
		. is_push_warning(ErrorContains.new("LocalFormat: offset"))
	)
	assert_array(result).is_equal(["00:00"])


func test_an_offset_inside_the_range_logs_no_warning() -> void:
	var rig: Rig = Rig.new("en", 840, NOVEMBER)
	await (assert_error(func() -> void: _format_all(rig, "2026-01-15T12:00:00Z")).is_success())


# --- unsupported language: English, no warning -------------------------------------------


func test_an_unsupported_language_gives_the_english_format_without_a_warning() -> void:
	var bad_values: Array = ["", "de", "HU", "En", "hu ", "hu_HU", 3, null, &"hu", ["hu"], 1.5]
	for bad: Variant in bad_values:
		var rig: Rig = Rig.new(bad, 60, NOVEMBER)
		var result: Array[String] = []
		await (
			assert_error(
				func() -> void: result.append_array(_format_all(rig, "2026-11-01T15:37:00Z"))
			)
			. is_success()
		)
		assert_array(result).override_failure_message("language %s" % [bad]).is_equal(
			["2026-11-01", "16:37", "2026-11-01 16:37"]
		)


func test_an_invalid_language_callable_gives_english_without_a_warning() -> void:
	var format: LocalFormat = LocalFormat.new(
		Callable(), func() -> Variant: return 60, func() -> Variant: return NOVEMBER
	)
	var result: Array[String] = []
	await (
		assert_error(func() -> void: result.append(format.format_datetime("2026-11-01T15:37:00Z")))
		. is_success()
	)
	assert_array(result).is_equal(["2026-11-01 16:37"])


# --- rejected timestamps: placeholder and warning ----------------------------------------


func test_a_rejected_timestamp_gives_unknown_in_english_and_a_warning() -> void:
	TranslationServer.set_locale("en")
	var rig: Rig = Rig.new("en", 60, NOVEMBER)
	for bad: Variant in ["", "2026-13-40T99:00:00Z", -1, 1e20, NAN, INF, null, true, "garbage"]:
		var result: Array[String] = []
		await (
			assert_error(func() -> void: result.append(rig.format.format_datetime(bad)))
			. is_push_warning(ErrorContains.new("timestamp rejected"))
		)
		assert_array(result).override_failure_message("input %s" % [bad]).is_equal(["Unknown"])


func test_a_rejected_timestamp_gives_ismeretlen_in_hungarian_and_a_warning() -> void:
	TranslationServer.set_locale("hu")
	var rig: Rig = Rig.new("hu", 60, NOVEMBER)
	for bad: Variant in ["", "2026-13-40T99:00:00Z", -1]:
		var result: Array[String] = []
		await (
			assert_error(func() -> void: result.append(rig.format.format_datetime(bad)))
			. is_push_warning(ErrorContains.new("timestamp rejected"))
		)
		assert_array(result).override_failure_message("input %s" % [bad]).is_equal(["Ismeretlen"])


func test_every_entry_point_gives_the_placeholder_and_a_warning() -> void:
	TranslationServer.set_locale("en")
	var rig: Rig = Rig.new("en", 60, NOVEMBER)
	var result: Array[String] = []
	await (
		assert_error(func() -> void: result.append(rig.format.format_date("")))
		. is_push_warning(ErrorContains.new("timestamp rejected"))
	)
	await (
		assert_error(func() -> void: result.append(rig.format.format_time("")))
		. is_push_warning(ErrorContains.new("timestamp rejected"))
	)
	await (
		assert_error(func() -> void: result.append(rig.format.format_datetime("")))
		. is_push_warning(ErrorContains.new("timestamp rejected"))
	)
	assert_array(result).is_equal(["Unknown", "Unknown", "Unknown"])


func test_the_placeholder_follows_the_locale_while_the_format_follows_the_language() -> void:
	# The two are the same in the game; here they differ on purpose to pin down which is which.
	TranslationServer.set_locale("hu")
	var rig: Rig = Rig.new("en", 60, NOVEMBER)
	var result: Array[String] = []
	await (
		assert_error(func() -> void: result.append(rig.format.format_date("")))
		. is_push_warning(ErrorContains.new("timestamp rejected"))
	)
	assert_array(result).is_equal(["Ismeretlen"])
	assert_str(rig.format.format_date("2026-11-01T15:37:00Z")).is_equal("2026-11-01")


func test_the_placeholder_is_not_empty_and_not_the_key() -> void:
	TranslationServer.set_locale("en")
	var rig: Rig = Rig.new("en", 60, NOVEMBER)
	var result: Array[String] = []
	await (
		assert_error(func() -> void: result.append(rig.format.format_time("x")))
		. is_push_warning(ErrorContains.new("timestamp rejected"))
	)
	assert_str(result[0]).is_not_empty()
	assert_str(result[0]).is_not_equal("datetime.unknown")


func _format_all(rig: Rig, stamp: Variant) -> Array[String]:
	var result: Array[String] = []
	result.append(rig.format.format_date(stamp))
	result.append(rig.format.format_time(stamp))
	result.append(rig.format.format_datetime(stamp))
	return result
