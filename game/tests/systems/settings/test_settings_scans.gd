extends GdUnitTestSuite
## AC 18, static part: the settings code refers to no save file, no model and no history.
## The runtime part is in test_settings_screen.gd and test_language_section.gd.

const SourceScan := preload("res://tests/helpers/source_scan.gd")

const FOLDERS: PackedStringArray = ["res://systems/settings/", "res://ui/settings/"]
const EXPECTED: PackedStringArray = [
	"res://systems/settings/setting_key.gd",
	"res://systems/settings/settings_service.gd",
	"res://systems/settings/settings.gd",
	"res://ui/settings/settings_section.gd",
	"res://ui/settings/settings_screen.gd",
	"res://ui/settings/language_section.gd",
]
const AUTOLOAD := "res://systems/settings/settings.gd"
const SHELL_FILES: PackedStringArray = [
	"res://ui/settings/settings_screen.gd",
	"res://ui/settings/settings_screen.tscn",
	"res://ui/settings/settings_section.gd",
	"res://ui/settings/settings_sections.tres",
]


func _files() -> PackedStringArray:
	var files: PackedStringArray = PackedStringArray()
	for folder: String in FOLDERS:
		files.append_array(SourceScan.list_scripts(folder.trim_suffix("/"), PackedStringArray()))
	return files


func test_the_settings_code_exists() -> void:
	var files: PackedStringArray = _files()
	for path: String in EXPECTED:
		assert_bool(files.has(path)).override_failure_message("missing " + path).is_true()


func test_the_settings_code_does_not_touch_the_model_a_save_file_or_the_history() -> void:
	var patterns: Array[RegEx] = (
		SourceScan
		. compile(
			PackedStringArray(
				[
					"\\bAquariumModel\\b",
					"\\bCommandHistory\\b",
					"\\bSaveCodec\\b",
					"\\bSaveStore\\b",
					"\\bCommand\\b",
					"\\bbind_history\\b",
					"\\.json\\b",
				]
			)
		)
	)
	var files: PackedStringArray = _files()
	assert_array(files).is_not_empty()
	var offences: PackedStringArray = PackedStringArray()
	for path: String in files:
		var source: String = SourceScan.strip_comments(SourceScan.read(path))
		for hit: String in SourceScan.find_matches(source, patterns):
			offences.append("%s %s" % [path, hit])
	(
		assert_array(offences)
		. override_failure_message("settings code touches saves or the model: %s" % [offences])
		. is_empty()
	)


func test_the_autoload_script_has_no_class_name() -> void:
	var source: String = SourceScan.strip_comments(SourceScan.read(AUTOLOAD))
	assert_str(source).is_not_empty()
	assert_bool(source.contains("class_name")).is_false()


func test_the_shell_does_not_name_the_fixture_section() -> void:
	for path: String in SHELL_FILES:
		var source: String = SourceScan.read(path)
		assert_str(source).override_failure_message("missing " + path).is_not_empty()
		(
			assert_bool(source.to_lower().contains("fixture"))
			. override_failure_message("%s names the fixture" % path)
			. is_false()
		)


func test_the_shipped_section_list_holds_only_the_language_section() -> void:
	var list: Resource = load("res://ui/settings/settings_sections.tres") as Resource
	assert_object(list).override_failure_message("settings_sections.tres is missing").is_not_null()
	if list == null:
		return
	var sections: Array = list.get("sections")
	assert_array(sections).has_size(1)
	if sections.size() == 1:
		assert_str((sections[0] as PackedScene).resource_path).is_equal(
			"res://ui/settings/language_section.tscn"
		)
