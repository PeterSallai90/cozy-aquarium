extends GdUnitTestSuite
## The project wiring of the localization pipeline: translation settings, the autoload and the
## EventBus signal. Every check here only reads the live project; none calls set_language.

const TRANSLATIONS := ["res://localization/en.po", "res://localization/hu.po"]
const AUTOLOAD_VALUE := "*res://systems/localization/localization.gd"


func _project_file() -> ConfigFile:
	var config: ConfigFile = ConfigFile.new()
	var error: Error = config.load("res://project.godot")
	assert(error == OK, "project.godot does not parse")
	return config


func test_both_po_files_are_registered_in_this_order() -> void:
	var setting: PackedStringArray = ProjectSettings.get_setting(
		"internationalization/locale/translations", PackedStringArray()
	)
	assert_array(setting).is_equal(TRANSLATIONS)


func test_the_fallback_locale_is_en() -> void:
	var setting: String = ProjectSettings.get_setting("internationalization/locale/fallback", "")
	assert_str(setting).is_equal("en")


func test_the_fallback_is_written_explicitly_in_project_godot() -> void:
	# Godot's own default is also "en", so the runtime setting alone cannot show that it was set.
	var config: ConfigFile = _project_file()
	assert_bool(config.has_section_key("internationalization", "locale/fallback")).is_true()
	assert_str(config.get_value("internationalization", "locale/fallback")).is_equal("en")


func test_the_translations_are_written_in_project_godot() -> void:
	var config: ConfigFile = _project_file()
	var value: PackedStringArray = config.get_value(
		"internationalization", "locale/translations", PackedStringArray()
	)
	assert_array(value).is_equal(TRANSLATIONS)


func test_no_locale_override_and_no_editor_pot_generation() -> void:
	var test_locale: String = ProjectSettings.get_setting("internationalization/locale/test", "")
	assert_str(test_locale).is_empty()
	var pot_files: PackedStringArray = ProjectSettings.get_setting(
		"internationalization/locale/translations_pot_files", PackedStringArray()
	)
	assert_array(pot_files).is_empty()


func test_the_translation_files_exist() -> void:
	for path: String in TRANSLATIONS:
		assert_bool(FileAccess.file_exists(path)).override_failure_message(path).is_true()
	assert_bool(FileAccess.file_exists("res://localization/messages.pot")).is_true()
	assert_bool(FileAccess.file_exists("res://localization/extra_keys.txt")).is_true()


func test_english_and_hungarian_are_loaded() -> void:
	var locales: PackedStringArray = TranslationServer.get_loaded_locales()
	assert_array(locales).contains(["en", "hu"])


func test_the_autoload_is_registered() -> void:
	var setting: String = ProjectSettings.get_setting("autoload/Localization", "")
	assert_str(setting).is_equal(AUTOLOAD_VALUE)


func test_the_live_autoload_sits_after_the_event_bus() -> void:
	var root: Node = get_tree().root
	var localization: Node = root.get_node_or_null("Localization")
	var bus: Node = root.get_node_or_null("EventBus")
	assert_object(localization).is_not_null()
	assert_object(bus).is_not_null()
	assert_int(localization.get_index()).is_greater(bus.get_index())
	var script: Script = localization.get_script() as Script
	assert_str(script.resource_path).is_equal("res://systems/localization/localization.gd")


func test_the_live_autoload_has_the_four_api_methods() -> void:
	var localization: Node = get_tree().root.get_node_or_null("Localization")
	assert_object(localization).is_not_null()
	for method: String in [
		"get_supported_languages", "get_language_display_name", "get_language", "set_language"
	]:
		assert_bool(localization.has_method(method)).override_failure_message(method).is_true()


func test_the_live_autoload_reports_a_supported_language() -> void:
	var localization: Node = get_tree().root.get_node_or_null("Localization")
	assert_object(localization).is_not_null()
	assert_array(["en", "hu"]).contains([localization.get_language()])
	assert_array(localization.get_supported_languages()).is_equal(["en", "hu"])


func test_the_event_bus_has_the_language_changed_signal() -> void:
	var bus: Node = get_tree().root.get_node_or_null("EventBus")
	assert_object(bus).is_not_null()
	assert_bool(bus.has_signal("language_changed")).is_true()
	var parameters: Array = []
	for info: Dictionary in bus.get_signal_list():
		if info["name"] == "language_changed":
			parameters = info["args"]
	assert_array(parameters).has_size(1)
	var first: Dictionary = parameters[0]
	assert_str(first["name"]).is_equal("language")
	assert_int(first["type"]).is_equal(TYPE_STRING)
