extends GdUnitTestSuite
## Every export preset packs the OFL license texts of the bundled fonts.

const PRESETS_PATH := "res://export_presets.cfg"
const FONTS_ROOT := "res://assets/fonts"
const EXPECTED_NAMES: Array[String] = ["Windows Desktop", "Linux", "macOS"]
const EXCLUDE_FILTER := "tests/*, addons/gdUnit4/*, reports/*"


func _config() -> ConfigFile:
	var config: ConfigFile = ConfigFile.new()
	assert_int(config.load(PRESETS_PATH)).is_equal(OK)
	return config


func _preset_sections(config: ConfigFile) -> PackedStringArray:
	var sections: PackedStringArray = PackedStringArray()
	var pattern: RegEx = RegEx.create_from_string("^preset\\.\\d+$")
	for section: String in config.get_sections():
		if pattern.search(section) != null:
			sections.append(section)
	return sections


func _license_files(dir_path: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return found
	for sub: String in dir.get_directories():
		found.append_array(_license_files(dir_path.path_join(sub)))
	for file_name: String in dir.get_files():
		if file_name == "OFL.txt":
			found.append(dir_path.path_join(file_name))
	return found


## Mirrors the Godot exporter: a file is included when a filter matches the res:// path or the
## path without the prefix.
func _matches(path: String, filter_text: String) -> bool:
	var relative: String = path.trim_prefix("res://")
	for entry: String in filter_text.split(","):
		var pattern: String = entry.strip_edges()
		if pattern.is_empty():
			continue
		if relative.matchn(pattern) or path.matchn(pattern):
			return true
	return false


func test_there_are_exactly_three_presets_with_the_known_names() -> void:
	var config: ConfigFile = _config()
	var sections: PackedStringArray = _preset_sections(config)
	assert_int(sections.size()).is_equal(3)
	var names: Array[String] = []
	for section: String in sections:
		names.append(config.get_value(section, "name", "") as String)
	names.sort()
	var expected: Array[String] = EXPECTED_NAMES.duplicate()
	expected.sort()
	assert_array(names).is_equal(expected)


func test_the_walk_finds_the_ofl_files_of_both_font_families() -> void:
	var files: PackedStringArray = _license_files(FONTS_ROOT)
	(
		assert_int(files.size())
		. override_failure_message(
			"expected an OFL.txt for Nunito and Noto Sans under %s, found %s" % [FONTS_ROOT, files]
		)
		. is_greater_equal(2)
	)


func test_each_preset_include_filter_matches_every_ofl_file() -> void:
	var config: ConfigFile = _config()
	var files: PackedStringArray = _license_files(FONTS_ROOT)
	(
		assert_int(files.size())
		. override_failure_message("no OFL.txt under %s, so nothing to match" % FONTS_ROOT)
		. is_greater_equal(2)
	)
	for section: String in _preset_sections(config):
		var filter_text: String = config.get_value(section, "include_filter", "") as String
		for path: String in files:
			(
				assert_bool(_matches(path, filter_text))
				. override_failure_message(
					'%s include_filter "%s" does not match %s' % [section, filter_text, path]
				)
				. is_true()
			)


func test_the_include_filter_does_not_pack_other_text_files() -> void:
	var config: ConfigFile = _config()
	for section: String in _preset_sections(config):
		var filter_text: String = config.get_value(section, "include_filter", "") as String
		assert_bool(_matches("res://assets/fonts/nunito/notes.txt", filter_text)).is_false()
		(
			assert_bool(_matches("res://assets/fonts/nunito/nunito_variable.ttf", filter_text))
			. is_false()
		)


func test_the_export_and_exclude_filters_are_unchanged() -> void:
	var config: ConfigFile = _config()
	for section: String in _preset_sections(config):
		assert_str(config.get_value(section, "export_filter", "") as String).is_equal(
			"all_resources"
		)
		assert_str(config.get_value(section, "exclude_filter", "") as String).is_equal(
			EXCLUDE_FILTER
		)
