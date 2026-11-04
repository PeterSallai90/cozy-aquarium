extends GdUnitTestSuite

# These constants mirror REQUIRED_SETTINGS in tools/scripts/check_project_settings.py.
const PROJECT_FILE := "res://project.godot"
const RENDERER_SECTION := "rendering"
const RENDERER_KEY := "renderer/rendering_method"
const RENDERER_VALUE := "forward_plus"
const GDUNIT_SECTION := "gdunit4"
const PUSH_ERROR_KEY := "report/godot/push_error"
const SCRIPT_ERROR_KEY := "report/godot/script_error"


static func missing_line_message(section: String, key: String, value: String) -> String:
	return (
		'game/project.godot is missing %s under [%s]; add the line %s="%s" (see docs/dev-setup.md)'
		% [key, section, key, value]
	)


func _project_file() -> ConfigFile:
	var config: ConfigFile = ConfigFile.new()
	var error: Error = config.load(PROJECT_FILE)
	assert(error == OK, "project.godot does not parse")
	return config


func test_rendering_method_is_forward_plus() -> void:
	var method: String = ProjectSettings.get_setting("rendering/renderer/rendering_method", "")
	assert_str(method).is_equal("forward_plus")


func test_rendering_method_is_written_explicitly_in_project_godot() -> void:
	# Godot's own default is also forward_plus, so the runtime setting cannot show the line exists.
	var config: ConfigFile = _project_file()
	var message: String = missing_line_message(RENDERER_SECTION, RENDERER_KEY, RENDERER_VALUE)
	(
		assert_bool(config.has_section_key(RENDERER_SECTION, RENDERER_KEY))
		. override_failure_message(message)
		. is_true()
	)
	(
		assert_str(config.get_value(RENDERER_SECTION, RENDERER_KEY, ""))
		. override_failure_message(message)
		. is_equal(RENDERER_VALUE)
	)


func test_missing_line_message_wording() -> void:
	var message: String = missing_line_message(RENDERER_SECTION, RENDERER_KEY, RENDERER_VALUE)
	assert_str(message).is_equal(
		(
			"game/project.godot is missing renderer/rendering_method under [rendering]; "
			+ 'add the line renderer/rendering_method="forward_plus" (see docs/dev-setup.md)'
		)
	)


# --- GdUnit4 reporting (#91, AC1) -----------------------------------------------------------


func test_gdunit_push_error_reporting_is_written_as_true_in_project_godot() -> void:
	var config: ConfigFile = _project_file()
	var message: String = (
		(
			"game/project.godot must contain [%s] %s=true so that an unasserted push_error, "
			+ "push_warning or engine error fails the test (see docs/adr/0004-engine-output-policy.md)"
		)
		% [GDUNIT_SECTION, PUSH_ERROR_KEY]
	)
	(
		assert_bool(config.has_section_key(GDUNIT_SECTION, PUSH_ERROR_KEY))
		. override_failure_message(message)
		. is_true()
	)
	(
		assert_bool(config.get_value(GDUNIT_SECTION, PUSH_ERROR_KEY, false) == true)
		. override_failure_message(message)
		. is_true()
	)


func test_gdunit_push_error_reporting_is_active_in_the_running_session() -> void:
	assert_bool(GdUnitSettings.is_report_push_errors()).is_true()


func test_gdunit_script_error_reporting_stays_at_its_default() -> void:
	assert_bool(GdUnitSettings.is_report_script_errors()).is_true()
	var config: ConfigFile = _project_file()
	assert_bool(config.has_section_key(GDUNIT_SECTION, SCRIPT_ERROR_KEY)).is_false()


func test_gdunit_section_holds_exactly_the_push_error_key() -> void:
	# The diff for AC1 adds one key; opening the editor must not write other gdunit4 defaults.
	var config: ConfigFile = _project_file()
	var keys: PackedStringArray = PackedStringArray()
	if config.has_section(GDUNIT_SECTION):
		keys = config.get_section_keys(GDUNIT_SECTION)
	assert_array(Array(keys)).is_equal([PUSH_ERROR_KEY])
