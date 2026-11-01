extends GdUnitTestSuite
## Source scans: date and number formatting goes through LocalFormat only. Each rule is a pure
## function over (path, source), so the real scan and the self-tests with fake lines run the same
## code.

const SourceScan := preload("res://tests/helpers/source_scan.gd")

const EXCLUDED := ["res://tests/", "res://addons/", "res://.godot/"]
const LOCALIZATION_FOLDER := "res://systems/localization/"
const LOCAL_FORMAT := "res://systems/localization/local_format.gd"
const ALLOWED_STAMP_FILES := ["res://model/aquarium_model.gd", "res://systems/save_store.gd"]
const ALLOWED_STAMP_CALL := (
	"\\bTime\\s*\\.\\s*get_datetime_string_from_system" + "\\s*\\(\\s*true\\s*\\)"
)
const DATE_PATTERNS := [
	"\\bget_(datetime|date|time)_(string|dict)_from_\\w+",
	"\\bget_time_zone_from_system\\b",
	"\\bget_offset_string_from_offset_minutes\\b",
]
const NUMBER_PATTERNS := [
	"\\bString\\s*\\.\\s*num(_scientific)?\\s*\\(",
	"%[-+ 0]*[0-9]*(\\.[0-9]+)?f",
]
const LOG_LINE := "\\b(push_error|push_warning|print|prints|printerr|print_rich)\\s*\\("

# --- the rules ---------------------------------------------------------------------------


func _date_offences(path: String, source: String) -> PackedStringArray:
	if path.begins_with(LOCALIZATION_FOLDER):
		return PackedStringArray()
	var text: String = SourceScan.strip_comments(source)
	if ALLOWED_STAMP_FILES.has(path):
		var allowed: RegEx = RegEx.new()
		var error: int = allowed.compile(ALLOWED_STAMP_CALL)
		assert(error == OK)
		text = allowed.sub(text, "", true)
	var patterns: Array[RegEx] = SourceScan.compile(PackedStringArray(DATE_PATTERNS))
	return _hits(path, text, patterns, false)


func _number_offences(path: String, source: String) -> PackedStringArray:
	var patterns: Array[RegEx] = SourceScan.compile(PackedStringArray(NUMBER_PATTERNS))
	return _hits(path, SourceScan.strip_comments(source), patterns, true)


func _hits(
	path: String, text: String, patterns: Array[RegEx], skip_log_lines: bool
) -> PackedStringArray:
	var log_pattern: RegEx = SourceScan.compile(PackedStringArray([LOG_LINE]))[0]
	var result: PackedStringArray = PackedStringArray()
	var lines: PackedStringArray = text.split("\n")
	for index: int in range(lines.size()):
		if skip_log_lines and log_pattern.search(lines[index]) != null:
			continue
		for hit: String in SourceScan.find_matches(lines[index], patterns):
			result.append("%s:%d %s" % [path, index + 1, hit])
	return result


func _date_scripts() -> PackedStringArray:
	return SourceScan.list_scripts("res://", PackedStringArray(EXCLUDED))


func _number_scripts() -> PackedStringArray:
	var files: PackedStringArray = SourceScan.list_scripts("res://ui", PackedStringArray())
	files.append_array(SourceScan.list_scripts("res://scenes", PackedStringArray()))
	return files


# --- the real scans ----------------------------------------------------------------------


func test_no_date_formatting_outside_the_helper() -> void:
	var offences: PackedStringArray = PackedStringArray()
	for path: String in _date_scripts():
		offences.append_array(_date_offences(path, SourceScan.read(path)))
	(
		assert_array(offences)
		. override_failure_message("direct date or time formatting: %s" % [offences])
		. is_empty()
	)


func test_no_number_formatting_in_the_ui_and_scene_scripts() -> void:
	var offences: PackedStringArray = PackedStringArray()
	for path: String in _number_scripts():
		offences.append_array(_number_offences(path, SourceScan.read(path)))
	(
		assert_array(offences)
		. override_failure_message("direct number formatting: %s" % [offences])
		. is_empty()
	)


func test_the_helper_reads_the_time_zone_so_the_scan_has_something_to_exempt() -> void:
	var source: String = SourceScan.strip_comments(SourceScan.read(LOCAL_FORMAT))
	assert_str(source).is_not_empty()
	assert_bool(source.contains("get_time_zone_from_system")).is_true()


func test_the_allow_list_is_not_stale() -> void:
	var allowed: RegEx = RegEx.new()
	assert_int(allowed.compile(ALLOWED_STAMP_CALL)).is_equal(OK)
	for path: String in ALLOWED_STAMP_FILES:
		var source: String = SourceScan.strip_comments(SourceScan.read(path))
		(
			assert_bool(allowed.search(source) != null)
			. override_failure_message("%s no longer has the allowed call" % path)
			. is_true()
		)


func test_the_allow_listed_files_have_no_other_forbidden_call() -> void:
	for path: String in ALLOWED_STAMP_FILES:
		assert_array(_date_offences(path, SourceScan.read(path))).is_empty()


# --- self-tests of the date rule ---------------------------------------------------------


func test_every_forbidden_family_is_flagged_outside_the_helper() -> void:
	var calls: Array[String] = [
		"var a := Time.get_datetime_string_from_system()",
		"var a := Time.get_datetime_string_from_unix_time(t)",
		"var a := Time.get_date_string_from_system()",
		"var a := Time.get_date_string_from_unix_time(t)",
		"var a := Time.get_time_string_from_system()",
		"var a := Time.get_time_string_from_unix_time(t)",
		"var a := Time.get_datetime_dict_from_system()",
		"var a := Time.get_datetime_dict_from_unix_time(t)",
		"var a := Time.get_date_dict_from_system()",
		"var a := Time.get_date_dict_from_unix_time(t)",
		"var a := Time.get_time_dict_from_system()",
		"var a := Time.get_time_dict_from_unix_time(t)",
		"var a := Time.get_time_zone_from_system()",
		"var a := Time.get_offset_string_from_offset_minutes(60)",
		"var a := get_date_string_from_system()",
	]
	for line: String in calls:
		(
			assert_array(_date_offences("res://ui/x.gd", line))
			. override_failure_message("not flagged: %s" % line)
			. has_size(1)
		)


func test_the_exact_stamp_call_is_ignored_on_the_two_allow_listed_paths() -> void:
	var line: String = 'stamp = Time.get_datetime_string_from_system(true) + "Z"'
	for path: String in ALLOWED_STAMP_FILES:
		assert_array(_date_offences(path, line)).is_empty()
	(
		assert_array(
			_date_offences(
				"res://model/aquarium_model.gd",
				"x = Time . get_datetime_string_from_system( true )"
			)
		)
		. is_empty()
	)


func test_the_stamp_call_is_flagged_on_every_other_path() -> void:
	var line: String = 'stamp = Time.get_datetime_string_from_system(true) + "Z"'
	assert_array(_date_offences("res://ui/x.gd", line)).has_size(1)
	assert_array(_date_offences("res://model/save_codec.gd", line)).has_size(1)
	assert_array(_date_offences("res://systems/settings_store.gd", line)).has_size(1)
	assert_array(_date_offences("res://scenes/main.gd", line)).has_size(1)


func test_other_arguments_of_the_stamp_call_are_flagged_on_an_allow_listed_path() -> void:
	for path: String in ALLOWED_STAMP_FILES:
		for line: String in [
			"x = Time.get_datetime_string_from_system(true, true)",
			"x = Time.get_datetime_string_from_system(false)",
			"x = Time.get_datetime_string_from_system()",
			"x = Time.get_datetime_string_from_system(utc)",
		]:
			(
				assert_array(_date_offences(path, line))
				. override_failure_message("%s: %s" % [path, line])
				. has_size(1)
			)


func test_any_other_forbidden_call_is_flagged_next_to_the_allowed_call() -> void:
	var source: String = (
		'x = Time.get_datetime_string_from_system(true) + "Z"\n'
		+ "y = Time.get_date_string_from_system()\n"
	)
	for path: String in ALLOWED_STAMP_FILES:
		assert_array(_date_offences(path, source)).has_size(1)
	var same_line: String = (
		"x = Time.get_datetime_string_from_system(true) + " + "Time.get_time_string_from_system()"
	)
	assert_array(_date_offences("res://model/aquarium_model.gd", same_line)).has_size(1)


func test_the_parsing_calls_are_not_flagged() -> void:
	for line: String in [
		"var t := Time.get_unix_time_from_datetime_string(s)",
		"var t := Time.get_unix_time_from_datetime_dict(d)",
		"var t := Time.get_unix_time_from_system()",
	]:
		assert_array(_date_offences("res://ui/x.gd", line)).is_empty()


func test_a_forbidden_call_in_a_comment_is_not_flagged() -> void:
	(
		assert_array(
			_date_offences("res://ui/x.gd", "# Time.get_date_string_from_system()\nvar a := 1")
		)
		. is_empty()
	)
	(
		assert_array(
			_date_offences("res://ui/x.gd", "var a := 1  # Time.get_time_zone_from_system()")
		)
		. is_empty()
	)


func test_the_localization_folder_is_exempt() -> void:
	var line: String = "var a := Time.get_time_zone_from_system()"
	assert_array(_date_offences(LOCAL_FORMAT, line)).is_empty()
	assert_array(_date_offences("res://systems/localization/other.gd", line)).is_empty()


func test_the_model_folder_is_not_exempt() -> void:
	(
		assert_array(
			_date_offences("res://model/save_codec.gd", "x = Time.get_time_zone_from_system()")
		)
		. has_size(1)
	)
	(
		assert_array(
			_date_offences("res://systems/other.gd", "x = Time.get_date_string_from_system()")
		)
		. has_size(1)
	)


func test_an_offence_names_the_file_and_the_line() -> void:
	var offences: PackedStringArray = _date_offences(
		"res://ui/x.gd", "var a := 1\nvar b := Time.get_date_string_from_system()"
	)
	assert_array(offences).has_size(1)
	assert_str(offences[0]).starts_with("res://ui/x.gd:2 ")


# --- self-tests of the number rule -------------------------------------------------------


func test_the_number_scan_flags_the_formatting_calls() -> void:
	for line: String in [
		"label.text = String.num(x, 1)",
		"label.text = String.num_scientific(x)",
		'label.text = "%.1f" % x',
		'label.text = "%f" % x',
		'label.text = "%5.2f" % x',
		'label.text = "%+.2f" % x',
		'label.text = "%-8.3f" % x',
		'label.text = "%08.2f cm" % x',
	]:
		(
			assert_array(_number_offences("res://ui/x.gd", line))
			. override_failure_message("not flagged: %s" % line)
			. is_not_empty()
		)


func test_the_number_scan_leaves_other_formats_alone() -> void:
	for line: String in [
		'label.text = "%d" % count',
		'label.text = "%s" % name',
		'label.text = "%02d:%02d" % [h, m]',
		'label.text = "%5d items" % count',
		"var a: float = 1.5",
		'print("%.2f" % x)',
		'push_warning("%.1f" % x)',
		'push_error("%f" % x)',
		'prints("%.2f" % x)',
		"var s := String.num_int64(5)",
		"# label.text = String.num(x, 1)",
		'var a := 1  # "%.1f" % x',
	]:
		(
			assert_array(_number_offences("res://ui/x.gd", line))
			. override_failure_message("flagged: %s" % line)
			. is_empty()
		)


func test_an_offence_in_a_scene_script_is_reported_with_its_line() -> void:
	var offences: PackedStringArray = _number_offences(
		"res://scenes/main.gd", 'var a := 1\nlabel.text = "%.1f" % x'
	)
	assert_array(offences).has_size(1)
	assert_str(offences[0]).starts_with("res://scenes/main.gd:2 ")
