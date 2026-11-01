extends GdUnitTestSuite

const SourceScan := preload("res://tests/helpers/source_scan.gd")

const EXCLUDED := ["res://tests/", "res://addons/", "res://.godot/"]
const LOCALIZATION_FOLDER := "res://systems/localization/"
const AUTOLOAD := "res://systems/localization/localization.gd"
const SETTINGS_STORE := "res://systems/settings_store.gd"
const PROCESS_AND_REGISTRY_TOKENS := [
	"OS\\s*\\.\\s*execute",
	"OS\\s*\\.\\s*create_process",
	"OS\\s*\\.\\s*create_instance",
	"OS\\s*\\.\\s*shell_open",
	"reg\\.exe",
	"powershell",
	"HKEY_",
]


func _all_scripts() -> PackedStringArray:
	return SourceScan.list_scripts("res://", PackedStringArray(EXCLUDED))


func _hits_in(path: String, patterns: Array[RegEx]) -> PackedStringArray:
	var hits: PackedStringArray = PackedStringArray()
	var lines: PackedStringArray = SourceScan.strip_comments(SourceScan.read(path)).split("\n")
	for index: int in range(lines.size()):
		for hit: String in SourceScan.find_matches(lines[index], patterns):
			hits.append("%s:%d %s" % [path, index + 1, hit])
	return hits


func _language_code_files() -> PackedStringArray:
	var files: PackedStringArray = PackedStringArray()
	for path: String in _all_scripts():
		if path.begins_with(LOCALIZATION_FOLDER) or path == SETTINGS_STORE:
			files.append(path)
	return files


func test_the_locale_is_set_only_inside_the_localization_folder() -> void:
	var patterns: Array[RegEx] = SourceScan.compile(
		PackedStringArray(["\\bTranslationServer\\s*\\.\\s*set_locale\\b"])
	)
	var offences: PackedStringArray = PackedStringArray()
	var found_inside: bool = false
	for path: String in _all_scripts():
		var hits: PackedStringArray = _hits_in(path, patterns)
		if path.begins_with(LOCALIZATION_FOLDER):
			found_inside = found_inside or not hits.is_empty()
		else:
			offences.append_array(hits)
	(
		assert_array(offences)
		. override_failure_message("set_locale outside the localization folder: %s" % [offences])
		. is_empty()
	)
	(
		assert_bool(found_inside)
		. override_failure_message("the localization folder never calls set_locale")
		. is_true()
	)


func test_only_the_autoload_reads_the_os_locale() -> void:
	var patterns: Array[RegEx] = SourceScan.compile(
		PackedStringArray(["\\bOS\\s*\\.\\s*get_locale"])
	)
	var offences: PackedStringArray = PackedStringArray()
	for path: String in _all_scripts():
		if path != AUTOLOAD:
			offences.append_array(_hits_in(path, patterns))
	(
		assert_array(offences)
		. override_failure_message("OS locale read outside the autoload: %s" % [offences])
		. is_empty()
	)
	assert_array(_hits_in(AUTOLOAD, patterns)).is_not_empty()


func test_no_registry_process_or_shell_call_in_the_language_code() -> void:
	var patterns: Array[RegEx] = SourceScan.compile(PackedStringArray(PROCESS_AND_REGISTRY_TOKENS))
	var files: PackedStringArray = _language_code_files()
	assert_bool(files.has(AUTOLOAD)).is_true()
	assert_bool(files.has(SETTINGS_STORE)).is_true()
	var offences: PackedStringArray = PackedStringArray()
	for path: String in files:
		offences.append_array(_hits_in(path, patterns))
	(
		assert_array(offences)
		. override_failure_message("registry, process or shell call: %s" % [offences])
		. is_empty()
	)


func test_the_language_code_does_not_touch_the_model_or_the_save_codec() -> void:
	var files: PackedStringArray = _language_code_files()
	assert_bool(files.has(AUTOLOAD)).is_true()
	assert_bool(files.has(SETTINGS_STORE)).is_true()
	var patterns: Array[RegEx] = SourceScan.compile(
		PackedStringArray(["\\bAquariumModel\\b", "\\bCommandHistory\\b", "\\bSaveCodec\\b"])
	)
	var offences: PackedStringArray = PackedStringArray()
	for path: String in files:
		offences.append_array(_hits_in(path, patterns))
	(
		assert_array(offences)
		. override_failure_message("language code refers to the model: %s" % [offences])
		. is_empty()
	)


func test_the_autoload_script_has_no_class_name() -> void:
	var source: String = SourceScan.strip_comments(SourceScan.read(AUTOLOAD))
	assert_str(source).is_not_empty()
	assert_bool(source.contains("class_name")).is_false()


func test_no_datetime_or_number_helper_ships_in_this_issue() -> void:
	# Date, time and number display is #72 (B07b).
	assert_bool(FileAccess.file_exists("res://systems/localization/local_format.gd")).is_false()
