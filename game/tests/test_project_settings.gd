extends GdUnitTestSuite

# These constants mirror REQUIRED_SETTINGS in tools/scripts/check_project_settings.py.
const PROJECT_FILE := "res://project.godot"
const RENDERER_SECTION := "rendering"
const RENDERER_KEY := "renderer/rendering_method"
const RENDERER_VALUE := "forward_plus"


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
