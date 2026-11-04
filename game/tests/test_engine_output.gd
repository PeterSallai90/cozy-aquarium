extends GdUnitTestSuite
## Contract of tests/helpers/engine_output.gd (counting helper, #91) and of ErrorContains.
##
## The helper is loaded by path, so a missing script fails these tests and not the whole run.

const ErrorContains := preload("res://tests/helpers/error_contains.gd")
const HELPER_PATH := "res://tests/helpers/engine_output.gd"
const PARSE_ERROR := (
	"ConfigFile parse error at <string>:0: " + "Unexpected EOF while parsing simple tag."
)


func _capture(action: Callable) -> Dictionary:
	var script: GDScript = null
	if ResourceLoader.exists(HELPER_PATH):
		script = load(HELPER_PATH) as GDScript
	(
		assert_object(script)
		. override_failure_message("%s does not exist yet" % HELPER_PATH)
		. is_not_null()
	)
	if script == null:
		return {"errors": {"missing helper": 1}, "warnings": {"missing helper": 1}}
	var seen: Dictionary = await script.call("capture", action)
	return seen


# --- ErrorContains -----------------------------------------------------------------------------


func test_error_contains_with_an_empty_needle_matches_no_text() -> void:
	var matcher: ErrorContains = ErrorContains.new("")
	assert_bool(matcher.is_match("")).is_false()
	assert_bool(matcher.is_match("anything at all")).is_false()
	assert_bool(matcher.is_match("LocalFormat: offset clamped: 99")).is_false()


func test_error_contains_with_a_needle_still_matches_by_substring() -> void:
	var matcher: ErrorContains = ErrorContains.new("offset")
	assert_bool(matcher.is_match("LocalFormat: offset clamped: 99")).is_true()
	assert_bool(matcher.is_match("LocalFormat: clock")).is_false()


func test_error_contains_stays_usable_for_push_warning() -> void:
	await (
		assert_error(func() -> void: push_warning("probe: warning text"))
		. is_push_warning(ErrorContains.new("warning text"))
	)


# --- EngineOutput.capture ----------------------------------------------------------------------


func test_capture_counts_each_warning_text_and_its_exact_count() -> void:
	var seen: Dictionary = await _capture(
		func() -> void:
			push_warning("a")
			push_warning("b")
			push_warning("a")
	)
	assert_dict(seen.get("warnings", {})).is_equal({"a": 2, "b": 1})
	assert_dict(seen.get("errors", {})).is_empty()


func test_capture_files_a_push_error_under_errors_only() -> void:
	var seen: Dictionary = await _capture(func() -> void: push_error("boom"))
	assert_dict(seen.get("errors", {})).is_equal({"boom": 1})
	assert_dict(seen.get("warnings", {})).is_empty()


func test_capture_files_a_push_warning_under_warnings_only() -> void:
	var seen: Dictionary = await _capture(func() -> void: push_warning("careful"))
	assert_dict(seen.get("warnings", {})).is_equal({"careful": 1})
	assert_dict(seen.get("errors", {})).is_empty()


func test_capture_files_a_config_file_parse_error_under_errors_by_its_visible_text() -> void:
	var seen: Dictionary = await _capture(func() -> void: ConfigFile.new().parse("[a"))
	assert_dict(seen.get("errors", {})).is_equal({PARSE_ERROR: 1})
	assert_dict(seen.get("warnings", {})).is_empty()


func test_capture_counts_errors_and_warnings_of_one_call_together() -> void:
	var seen: Dictionary = await _capture(
		func() -> void:
			push_error("e")
			push_warning("w")
			push_error("e")
			ConfigFile.new().parse("[a")
	)
	assert_dict(seen.get("errors", {})).is_equal({"e": 2, PARSE_ERROR: 1})
	assert_dict(seen.get("warnings", {})).is_equal({"w": 1})


func test_capture_of_a_silent_action_returns_two_empty_maps() -> void:
	var seen: Dictionary = await _capture(func() -> void: pass)
	assert_array(seen.keys()).contains_exactly_in_any_order(["errors", "warnings"])
	assert_dict(seen.get("errors", {"unset": 1})).is_empty()
	assert_dict(seen.get("warnings", {"unset": 1})).is_empty()


func test_capture_does_not_count_entries_logged_before_it_started() -> void:
	await assert_error(func() -> void: push_warning("before")).is_push_warning("before")
	var seen: Dictionary = await _capture(func() -> void: push_warning("inside"))
	assert_dict(seen.get("warnings", {})).is_equal({"inside": 1})


func test_capture_consumes_what_it_captured_so_the_test_still_passes() -> void:
	# Under report/godot/push_error=true an unconsumed entry would fail this test at its end.
	var seen: Dictionary = await _capture(
		func() -> void:
			push_error("consumed error")
			push_warning("consumed warning")
	)
	assert_dict(seen.get("errors", {})).is_equal({"consumed error": 1})
	assert_dict(seen.get("warnings", {})).is_equal({"consumed warning": 1})


func test_capture_sees_a_message_logged_after_a_frame_inside_the_action() -> void:
	var seen: Dictionary = await _capture(
		func() -> void:
			await get_tree().process_frame
			push_warning("late")
	)
	assert_dict(seen.get("warnings", {})).is_equal({"late": 1})


func test_capture_can_run_twice_in_one_test_and_each_call_reports_only_its_own() -> void:
	var first: Dictionary = await _capture(func() -> void: push_warning("one"))
	var second: Dictionary = await _capture(func() -> void: push_warning("two"))
	assert_dict(first.get("warnings", {})).is_equal({"one": 1})
	assert_dict(second.get("warnings", {})).is_equal({"two": 1})
