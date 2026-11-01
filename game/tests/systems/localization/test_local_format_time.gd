# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## The pure statics of LocalFormat: timestamp parser, date math and the European DST rule.

const Rig := preload("res://tests/helpers/format_rig.gd")

const JANUARY: int = Rig.CLOCK_JANUARY
const JULY: int = Rig.CLOCK_JULY
const NOVEMBER: int = Rig.CLOCK_NOVEMBER

const JULY_STAMP: String = "2026-07-01T12:00:00Z"
const JANUARY_STAMP: String = "2026-01-15T12:00:00Z"

# --- parser: accepted input --------------------------------------------------------------


func test_the_stored_form_is_parsed_to_unix_seconds() -> void:
	assert_int(LocalFormat.parse_timestamp("1970-01-01T00:00:00Z")).is_equal(0)
	assert_int(LocalFormat.parse_timestamp("2026-01-15T00:00:00Z")).is_equal(JANUARY)
	assert_int(LocalFormat.parse_timestamp("2026-07-01T00:00:00Z")).is_equal(JULY)
	assert_int(LocalFormat.parse_timestamp("2026-11-01T00:00:00Z")).is_equal(NOVEMBER)
	assert_int(LocalFormat.parse_timestamp("2026-11-01T16:37:59Z")).is_equal(NOVEMBER + 59879)


func test_the_year_limits_1970_and_9999_are_accepted() -> void:
	assert_int(LocalFormat.parse_timestamp("9999-12-31T23:59:59Z")).is_equal(LocalFormat.MAX_UNIX)
	assert_int(LocalFormat.MAX_UNIX).is_equal(253402300799)
	assert_int(LocalFormat.parse_timestamp("1970-01-01T00:00:01Z")).is_equal(1)


func test_leap_days_follow_the_gregorian_rule() -> void:
	assert_int(LocalFormat.parse_timestamp("2024-02-29T00:00:00Z")).is_greater(0)
	assert_int(LocalFormat.parse_timestamp("2000-02-29T00:00:00Z")).is_greater(0)
	assert_int(LocalFormat.parse_timestamp("2100-02-29T00:00:00Z")).is_equal(-1)
	assert_int(LocalFormat.parse_timestamp("2026-02-29T00:00:00Z")).is_equal(-1)
	assert_int(LocalFormat.parse_timestamp("2028-02-29T23:59:59Z")).is_greater(0)
	assert_int(LocalFormat.parse_timestamp("2028-02-30T00:00:00Z")).is_equal(-1)


func test_an_int_unix_time_is_accepted_from_zero_to_the_maximum() -> void:
	assert_int(LocalFormat.parse_timestamp(0)).is_equal(0)
	assert_int(LocalFormat.parse_timestamp(JULY)).is_equal(JULY)
	assert_int(LocalFormat.parse_timestamp(LocalFormat.MAX_UNIX)).is_equal(LocalFormat.MAX_UNIX)


func test_a_float_unix_time_has_its_fraction_cut_off() -> void:
	assert_int(LocalFormat.parse_timestamp(1782864000.9)).is_equal(JULY)
	assert_int(LocalFormat.parse_timestamp(1782864000.0)).is_equal(JULY)
	assert_int(LocalFormat.parse_timestamp(0.0)).is_equal(0)
	assert_int(LocalFormat.parse_timestamp(-0.0)).is_equal(0)
	assert_int(LocalFormat.parse_timestamp(0.999)).is_equal(0)
	assert_int(LocalFormat.parse_timestamp(float(LocalFormat.MAX_UNIX))).is_equal(
		LocalFormat.MAX_UNIX
	)


# --- parser: rejected input --------------------------------------------------------------


func test_malformed_strings_are_rejected() -> void:
	var bad: Array[String] = [
		"",
		"2026-11-01T16:37:00+02:00",
		"2026-11-01T16:37:00.5Z",
		"2026-11-01T16:37:00.000Z",
		"2026-11-01t16:37:00Z",
		"2026-11-01T16:37:00z",
		"2026-11-01 16:37:00Z",
		"2026-11-01T16:37:00",
		"2026-11-01",
		"2026-11-01T16:37Z",
		" 2026-11-01T16:37:00Z",
		"2026-11-01T16:37:00Z ",
		"2026-11-01T16:37:00Z\n",
		"\n2026-11-01T16:37:00Z",
		"2026-11-01T16:37:00ZZ",
		"2026/11/01T16:37:00Z",
		"2026-11-01T16.37.00Z",
		"26-11-01T16:37:00Z",
		"2026-1-1T6:7:0Z",
		"abcd-ef-ghTij:kl:mnZ",
		"2026-11-01T16:37:0 Z",
		"-026-11-01T16:37:00Z",
		"2026-11-+1T16:37:00Z",
		"0x26-11-01T16:37:00Z",
		"1782864000",
		"１２３４-11-01T16:37:00Z",
	]
	for text: String in bad:
		(
			assert_int(LocalFormat.parse_timestamp(text))
			. override_failure_message("accepted: '%s'" % text)
			. is_equal(-1)
		)


func test_impossible_dates_and_times_are_rejected() -> void:
	var bad: Array[String] = [
		"2026-02-30T00:00:00Z",
		"2026-04-31T00:00:00Z",
		"2026-13-01T00:00:00Z",
		"2026-00-10T00:00:00Z",
		"2026-01-00T00:00:00Z",
		"2026-01-32T00:00:00Z",
		"2026-01-01T24:00:00Z",
		"2026-01-01T00:60:00Z",
		"2026-01-01T00:00:60Z",
		"2026-13-40T99:00:00Z",
		"1969-12-31T23:59:59Z",
		"10000-01-01T00:00:00Z",
		"0000-01-01T00:00:00Z",
	]
	for text: String in bad:
		(
			assert_int(LocalFormat.parse_timestamp(text))
			. override_failure_message("accepted: '%s'" % text)
			. is_equal(-1)
		)


func test_out_of_range_numbers_are_rejected() -> void:
	assert_int(LocalFormat.parse_timestamp(-1)).is_equal(-1)
	assert_int(LocalFormat.parse_timestamp(LocalFormat.MAX_UNIX + 1)).is_equal(-1)
	assert_int(LocalFormat.parse_timestamp(-0.5)).is_equal(-1)
	assert_int(LocalFormat.parse_timestamp(-1.0)).is_equal(-1)
	assert_int(LocalFormat.parse_timestamp(float(LocalFormat.MAX_UNIX) + 1.0)).is_equal(-1)
	assert_int(LocalFormat.parse_timestamp(253402300799.5)).is_equal(-1)
	assert_int(LocalFormat.parse_timestamp(1e20)).is_equal(-1)
	assert_int(LocalFormat.parse_timestamp(-1e20)).is_equal(-1)
	assert_int(LocalFormat.parse_timestamp(9223372036854775807)).is_equal(-1)


func test_nan_and_infinity_are_rejected() -> void:
	assert_int(LocalFormat.parse_timestamp(NAN)).is_equal(-1)
	assert_int(LocalFormat.parse_timestamp(INF)).is_equal(-1)
	assert_int(LocalFormat.parse_timestamp(-INF)).is_equal(-1)


func test_any_other_type_is_rejected() -> void:
	var bad: Array = [true, false, null, &"2026-11-01T16:37:00Z", [], {}, Vector2i.ZERO]
	for value: Variant in bad:
		(
			assert_int(LocalFormat.parse_timestamp(value))
			. override_failure_message("accepted: %s" % [value])
			. is_equal(-1)
		)


func test_the_parser_logs_nothing() -> void:
	await (assert_error(func() -> void: _parse_bad()).is_success())


# --- date math ---------------------------------------------------------------------------


func test_days_from_civil_known_days() -> void:
	assert_int(LocalFormat.days_from_civil(1970, 1, 1)).is_equal(0)
	assert_int(LocalFormat.days_from_civil(1970, 1, 2)).is_equal(1)
	assert_int(LocalFormat.days_from_civil(1969, 12, 31)).is_equal(-1)
	assert_int(LocalFormat.days_from_civil(2000, 3, 1)).is_equal(11017)
	assert_int(LocalFormat.days_from_civil(2026, 7, 1)).is_equal(JULY / 86400)
	assert_int(LocalFormat.days_from_civil(9999, 12, 31)).is_equal(2932896)
	assert_int(LocalFormat.days_from_civil(10000, 1, 1)).is_equal(2932897)


func test_civil_from_days_known_days() -> void:
	assert_vector(LocalFormat.civil_from_days(0)).is_equal(Vector3i(1970, 1, 1))
	assert_vector(LocalFormat.civil_from_days(-1)).is_equal(Vector3i(1969, 12, 31))
	assert_vector(LocalFormat.civil_from_days(11017)).is_equal(Vector3i(2000, 3, 1))
	assert_vector(LocalFormat.civil_from_days(JULY / 86400)).is_equal(Vector3i(2026, 7, 1))
	assert_vector(LocalFormat.civil_from_days(2932896)).is_equal(Vector3i(9999, 12, 31))
	assert_vector(LocalFormat.civil_from_days(2932897)).is_equal(Vector3i(10000, 1, 1))
	assert_vector(LocalFormat.civil_from_days(19782)).is_equal(Vector3i(2024, 2, 29))


func test_the_two_conversions_are_inverse_for_every_day() -> void:
	var mismatches: PackedInt32Array = PackedInt32Array()
	for days: int in range(-1, 2932898):
		var civil: Vector3i = LocalFormat.civil_from_days(days)
		if LocalFormat.days_from_civil(civil.x, civil.y, civil.z) != days:
			mismatches.append(days)
			if mismatches.size() > 5:
				break
	assert_array(mismatches).is_empty()


func test_the_last_sunday_is_computed_for_the_two_change_over_months() -> void:
	assert_int(LocalFormat.last_sunday(2025, 3)).is_equal(30)
	assert_int(LocalFormat.last_sunday(2025, 10)).is_equal(26)
	assert_int(LocalFormat.last_sunday(2026, 3)).is_equal(29)
	assert_int(LocalFormat.last_sunday(2026, 10)).is_equal(25)
	assert_int(LocalFormat.last_sunday(2027, 3)).is_equal(28)
	assert_int(LocalFormat.last_sunday(2027, 10)).is_equal(31)
	assert_int(LocalFormat.last_sunday(2024, 3)).is_equal(31)
	assert_int(LocalFormat.last_sunday(2024, 10)).is_equal(27)
	assert_int(LocalFormat.last_sunday(2000, 3)).is_equal(26)
	assert_int(LocalFormat.last_sunday(2100, 10)).is_equal(31)


# --- the DST period ----------------------------------------------------------------------


func test_the_dst_period_edges_for_2025_2026_and_2027() -> void:
	# Per year: last second of winter time, first second of summer time, last second of
	# summer time, first second of winter time.
	var edges: Array[Array] = [
		[
			"2025-03-30T00:59:59Z",
			"2025-03-30T01:00:00Z",
			"2025-10-26T00:59:59Z",
			"2025-10-26T01:00:00Z"
		],
		[
			"2026-03-29T00:59:59Z",
			"2026-03-29T01:00:00Z",
			"2026-10-25T00:59:59Z",
			"2026-10-25T01:00:00Z"
		],
		[
			"2027-03-28T00:59:59Z",
			"2027-03-28T01:00:00Z",
			"2027-10-31T00:59:59Z",
			"2027-10-31T01:00:00Z"
		],
	]
	var expected: Array[bool] = [false, true, true, false]
	for year_edges: Array in edges:
		for index: int in range(4):
			var text: String = year_edges[index]
			(
				assert_bool(LocalFormat.is_eu_dst(LocalFormat.parse_timestamp(text)))
				. override_failure_message(text)
				. is_equal(expected[index])
			)


func test_dst_is_off_in_winter_and_on_in_summer() -> void:
	assert_bool(LocalFormat.is_eu_dst(JANUARY)).is_false()
	assert_bool(LocalFormat.is_eu_dst(JULY)).is_true()
	assert_bool(LocalFormat.is_eu_dst(NOVEMBER)).is_false()
	assert_bool(LocalFormat.is_eu_dst(0)).is_false()
	assert_bool(LocalFormat.is_eu_dst(LocalFormat.MAX_UNIX)).is_false()


# --- the standard offset -----------------------------------------------------------------


func test_the_standard_offset_outside_the_period_is_the_offset_itself() -> void:
	assert_int(LocalFormat.standard_offset(60, NOVEMBER)).is_equal(60)
	assert_int(LocalFormat.standard_offset(60, JANUARY)).is_equal(60)
	assert_int(LocalFormat.standard_offset(180, NOVEMBER)).is_equal(180)


func test_the_standard_offset_inside_the_period_is_one_hour_less() -> void:
	assert_int(LocalFormat.standard_offset(120, JULY)).is_equal(60)
	assert_int(LocalFormat.standard_offset(180, JULY)).is_equal(120)
	assert_int(LocalFormat.standard_offset(-60, JULY)).is_equal(-120)


# --- the full rule: offset_at(timestamp, current offset, clock) --------------------------


func test_example_a_helsinki_in_summer() -> void:
	assert_int(_offset_at(JANUARY_STAMP, 180, JULY)).is_equal(120)
	assert_int(_offset_at(JULY_STAMP, 180, JULY)).is_equal(180)


func test_example_b_moscow_in_winter_gets_no_correction() -> void:
	assert_int(_offset_at(JULY_STAMP, 180, NOVEMBER)).is_equal(180)
	assert_int(_offset_at(JANUARY_STAMP, 180, NOVEMBER)).is_equal(180)


func test_example_c_negative_offsets_are_never_corrected() -> void:
	for now: int in [JULY, NOVEMBER]:
		for current: int in [-60, -120, -300, -720]:
			assert_int(_offset_at(JANUARY_STAMP, current, now)).is_equal(current)
			assert_int(_offset_at(JULY_STAMP, current, now)).is_equal(current)


func test_example_d_lisbon_in_winter_gets_the_rule() -> void:
	assert_int(_offset_at(JULY_STAMP, 0, JANUARY)).is_equal(60)
	assert_int(_offset_at(JANUARY_STAMP, 0, JANUARY)).is_equal(0)


func test_example_e_the_azores_in_summer_get_no_correction() -> void:
	assert_int(_offset_at(JANUARY_STAMP, 0, JULY)).is_equal(0)
	assert_int(_offset_at(JULY_STAMP, 0, JULY)).is_equal(0)


func test_central_europe_in_winter_and_summer_corrects_both_seasons() -> void:
	assert_int(_offset_at(JULY_STAMP, 60, NOVEMBER)).is_equal(120)
	assert_int(_offset_at(JANUARY_STAMP, 60, NOVEMBER)).is_equal(60)
	assert_int(_offset_at(JANUARY_STAMP, 120, JULY)).is_equal(60)
	assert_int(_offset_at(JULY_STAMP, 120, JULY)).is_equal(120)


func test_the_clock_first_table_gives_the_same_classification() -> void:
	# Inside the period only +60, +120 and +180 are EU; outside it only 0, +60 and +120.
	for current: int in [-60, 0, 60, 120, 180, 240]:
		var is_eu_in_summer: bool = [60, 120, 180].has(current)
		var expected_winter_stamp: int = current - 60 if is_eu_in_summer else current
		(
			assert_int(_offset_at(JANUARY_STAMP, current, JULY))
			. override_failure_message("summer %d" % current)
			. is_equal(expected_winter_stamp)
		)
		var is_eu_in_winter: bool = [0, 60, 120].has(current)
		var expected_summer_stamp: int = current + 60 if is_eu_in_winter else current
		(
			assert_int(_offset_at(JULY_STAMP, current, JANUARY))
			. override_failure_message("winter %d" % current)
			. is_equal(expected_summer_stamp)
		)


func test_non_eu_offsets_use_the_current_offset_for_every_stamp() -> void:
	for current: int in [-300, 330, 540, 90, 150, 45, 525, 840, -720]:
		for now: int in [JANUARY, JULY, NOVEMBER]:
			var label: String = "%d at %d" % [current, now]
			(
				assert_int(_offset_at(JANUARY_STAMP, current, now))
				. override_failure_message(label)
				. is_equal(current)
			)
			(
				assert_int(_offset_at(JULY_STAMP, current, now))
				. override_failure_message(label)
				. is_equal(current)
			)


func test_offsets_that_are_not_a_whole_hour_never_match() -> void:
	assert_int(_offset_at(JANUARY_STAMP, 30, JANUARY)).is_equal(30)
	assert_int(_offset_at(JULY_STAMP, 30, JANUARY)).is_equal(30)
	assert_int(_offset_at(JULY_STAMP, 90, JULY)).is_equal(90)
	assert_int(_offset_at(JANUARY_STAMP, 90, JULY)).is_equal(90)


func test_the_change_over_instant_picks_the_offset_of_its_own_year() -> void:
	var before: int = LocalFormat.parse_timestamp("2026-03-29T00:59:59Z")
	var after: int = LocalFormat.parse_timestamp("2026-03-29T01:00:00Z")
	assert_int(LocalFormat.offset_at(before, 60, NOVEMBER)).is_equal(60)
	assert_int(LocalFormat.offset_at(after, 60, NOVEMBER)).is_equal(120)
	var autumn_before: int = LocalFormat.parse_timestamp("2026-10-25T00:59:59Z")
	var autumn_after: int = LocalFormat.parse_timestamp("2026-10-25T01:00:00Z")
	assert_int(LocalFormat.offset_at(autumn_before, 60, NOVEMBER)).is_equal(120)
	assert_int(LocalFormat.offset_at(autumn_after, 60, NOVEMBER)).is_equal(60)


func test_the_clock_at_a_change_over_instant_counts_by_the_period_edges() -> void:
	var spring: int = LocalFormat.parse_timestamp("2026-03-29T01:00:00Z")
	assert_int(LocalFormat.standard_offset(120, spring)).is_equal(60)
	var last_summer_second: int = LocalFormat.parse_timestamp("2026-10-25T00:59:59Z")
	assert_int(LocalFormat.standard_offset(120, last_summer_second)).is_equal(60)
	var winter: int = LocalFormat.parse_timestamp("2026-10-25T01:00:00Z")
	assert_int(LocalFormat.standard_offset(60, winter)).is_equal(60)
	var last_winter_second: int = LocalFormat.parse_timestamp("2026-03-29T00:59:59Z")
	assert_int(LocalFormat.standard_offset(60, last_winter_second)).is_equal(60)


# --- texts and the system offset ---------------------------------------------------------


func test_date_text_per_language() -> void:
	assert_str(LocalFormat.date_text(2026, 11, 1, "en")).is_equal("2026-11-01")
	assert_str(LocalFormat.date_text(2026, 11, 1, "hu")).is_equal("2026. 11. 01.")
	assert_str(LocalFormat.date_text(1969, 12, 31, "en")).is_equal("1969-12-31")
	assert_str(LocalFormat.date_text(1969, 12, 31, "hu")).is_equal("1969. 12. 31.")
	assert_str(LocalFormat.date_text(10000, 1, 1, "en")).is_equal("10000-01-01")
	assert_str(LocalFormat.date_text(10000, 1, 1, "hu")).is_equal("10000. 01. 01.")
	assert_str(LocalFormat.date_text(2026, 1, 1, "de")).is_equal("2026-01-01")


func test_time_text_is_24_hour_with_two_digits() -> void:
	assert_str(LocalFormat.time_text(16, 37)).is_equal("16:37")
	assert_str(LocalFormat.time_text(9, 5)).is_equal("09:05")
	assert_str(LocalFormat.time_text(0, 30)).is_equal("00:30")
	assert_str(LocalFormat.time_text(0, 0)).is_equal("00:00")
	assert_str(LocalFormat.time_text(23, 59)).is_equal("23:59")


func test_decimal_separator_per_language() -> void:
	assert_str(LocalFormat.decimal_separator("en")).is_equal(".")
	assert_str(LocalFormat.decimal_separator("hu")).is_equal(",")
	assert_str(LocalFormat.decimal_separator("de")).is_equal(".")
	assert_str(LocalFormat.decimal_separator("")).is_equal(".")
	assert_str(LocalFormat.decimal_separator("HU")).is_equal(".")


func test_every_supported_language_has_a_date_pattern_and_a_separator() -> void:
	for language: String in LanguagePolicy.SUPPORTED_LANGUAGES:
		(
			assert_bool(LocalFormat._DATE_PATTERNS.has(language))
			. override_failure_message("no date pattern for %s" % language)
			. is_true()
		)
		(
			assert_bool(LocalFormat._DECIMAL_SEPARATORS.has(language))
			. override_failure_message("no separator for %s" % language)
			. is_true()
		)


func test_the_system_offset_is_a_whole_number_in_the_valid_range() -> void:
	var minutes: int = LocalFormat.system_offset_minutes()
	assert_int(minutes).is_between(LocalFormat.MIN_OFFSET_MINUTES, LocalFormat.MAX_OFFSET_MINUTES)


func test_the_limits_are_the_ones_of_the_body() -> void:
	assert_int(LocalFormat.MIN_OFFSET_MINUTES).is_equal(-720)
	assert_int(LocalFormat.MAX_OFFSET_MINUTES).is_equal(840)
	assert_int(LocalFormat.MAX_DECIMALS).is_equal(6)
	assert_array(LocalFormat.EU_STANDARD_OFFSETS).is_equal([0, 60, 120])


func _offset_at(stamp: String, current: int, now: int) -> int:
	return LocalFormat.offset_at(LocalFormat.parse_timestamp(stamp), current, now)


func _parse_bad() -> Array[int]:
	return [
		LocalFormat.parse_timestamp("2026-13-40T99:00:00Z"),
		LocalFormat.parse_timestamp(1e20),
		LocalFormat.parse_timestamp(NAN),
		LocalFormat.parse_timestamp(null),
	]
