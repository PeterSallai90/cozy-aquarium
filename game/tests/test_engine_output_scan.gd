extends GdUnitTestSuite
## Source scans for the engine-output policy (#91, AC3 and AC9): no blanket suppression in the
## tests and no shrinking of the suite. Needles are built by concatenation so that this file does
## not match its own scan.

const SourceScan := preload("res://tests/helpers/source_scan.gd")

const TESTS_ROOT := "res://tests/"
const PROJECT_SETTINGS_SUITE := "res://tests/test_project_settings.gd"
## Snapshot of 0a81a4b/a1582c3: 749 test functions. The suite may only grow.
const BASELINE_TEST_FUNCTIONS := 749


func _empty_needle_pattern() -> Array[RegEx]:
	# Literal blank needles: "", '', &"", String(), String("") and String('').
	var blank: String = '(""|\'\'|&""|String\\(\\s*(""|\'\')?\\s*\\))'
	var expression: String = "ErrorContains" + "\\.new\\(\\s*" + blank + "\\s*\\)"
	return SourceScan.compile(PackedStringArray([expression]))


func _reporting_setting_pattern() -> Array[RegEx]:
	var expression: String = "gdunit4" + "/report/"
	return SourceScan.compile(PackedStringArray([expression]))


func _skip_pattern() -> Array[RegEx]:
	var expression: String = "do" + "_skip\\b|skip" + "_reason\\b"
	return SourceScan.compile(PackedStringArray([expression]))


func _test_function_pattern() -> RegEx:
	var regex: RegEx = RegEx.new()
	regex.compile("(?m)^[ \\t]*func " + "test_\\w+")
	return regex


func _hits(patterns: Array[RegEx], skipped_path: String = "") -> PackedStringArray:
	var hits: PackedStringArray = PackedStringArray()
	var scripts: PackedStringArray = SourceScan.list_scripts(TESTS_ROOT, PackedStringArray())
	for path: String in scripts:
		if path == skipped_path:
			continue
		for hit: String in SourceScan.find_matches(SourceScan.read(path), patterns):
			hits.append("%s: %s" % [path, hit])
	return hits


func test_no_test_uses_an_empty_error_contains_needle() -> void:
	var hits: PackedStringArray = _hits(_empty_needle_pattern())
	(
		assert_array(Array(hits))
		. override_failure_message("A blank ErrorContains needle matches everything: %s" % [hits])
		. is_empty()
	)


func test_no_test_changes_the_gdunit_report_settings() -> void:
	# Only test_project_settings.gd may mention the key, to read it; nobody may turn it off.
	var hits: PackedStringArray = _hits(_reporting_setting_pattern(), PROJECT_SETTINGS_SUITE)
	(
		assert_array(Array(hits))
		. override_failure_message("Tests must not touch GdUnit4 reporting settings: %s" % [hits])
		. is_empty()
	)


func test_test_project_settings_does_not_write_the_report_key() -> void:
	var source: String = SourceScan.read(PROJECT_SETTINGS_SUITE)
	var writers: Array[RegEx] = SourceScan.compile(
		PackedStringArray(["set" + "_setting\\s*\\(", "update" + "_property\\s*\\("])
	)
	assert_array(Array(SourceScan.find_matches(source, writers))).is_empty()


func test_no_test_is_marked_as_skipped() -> void:
	var hits: PackedStringArray = _hits(_skip_pattern())
	(
		assert_array(Array(hits))
		. override_failure_message("Skipped tests hide failures (AC9): %s" % [hits])
		. is_empty()
	)


func test_the_suite_has_at_least_the_baseline_number_of_test_functions() -> void:
	var count: int = 0
	var regex: RegEx = _test_function_pattern()
	for path: String in SourceScan.list_scripts(TESTS_ROOT, PackedStringArray()):
		count += regex.search_all(SourceScan.read(path)).size()
	var message: String = (
		"Found %d test functions, the baseline is %d (AC9: none removed)"
		% [count, BASELINE_TEST_FUNCTIONS]
	)
	assert_int(count).override_failure_message(message).is_greater_equal(BASELINE_TEST_FUNCTIONS)


func test_the_empty_needle_scan_flags_a_fake_blank_matcher() -> void:
	var head: String = "var m := ErrorContains"
	var fake: String = head + '.new("")\n' + head + ".new( '' )\n" + head + '.new(&"")\n'
	fake += (
		head + ".new(String())\n" + head + '.new(String(""))\n' + head + ".new( String( '' ) )\n"
	)
	assert_int(SourceScan.find_matches(fake, _empty_needle_pattern()).size()).is_equal(6)


func test_the_empty_needle_scan_ignores_a_needle_held_in_a_variable_or_string_call() -> void:
	var real: String = "var m := ErrorContains" + ".new(blank_needle)\n"
	real += "var n := ErrorContains" + '.new(String("offset"))\n'
	assert_int(SourceScan.find_matches(real, _empty_needle_pattern()).size()).is_equal(0)


func test_the_empty_needle_scan_ignores_a_real_needle() -> void:
	var real: String = "var m := ErrorContains" + '.new("offset")'
	assert_int(SourceScan.find_matches(real, _empty_needle_pattern()).size()).is_equal(0)


func test_the_test_function_scan_counts_a_fake_suite() -> void:
	var fake: String = "func test_a() -> void:\n\tpass\n\nfunc _helper() -> void:\n\tpass\n"
	fake += "\nfunc test_b() -> void:\n\tpass\n"
	assert_int(_test_function_pattern().search_all(fake).size()).is_equal(2)
