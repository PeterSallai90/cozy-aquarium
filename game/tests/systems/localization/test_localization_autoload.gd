extends GdUnitTestSuite
## Tests a fresh instance of the Localization autoload. They never call set_language on the live
## /root/Localization node, because that would write the real user://settings.cfg.

const LocalizationScript := preload("res://systems/localization/localization.gd")
const SaveFixtures := preload("res://tests/helpers/save_fixtures.gd")

var _dir: String = ""
var _saved_locale: String = ""
var _emitted: PackedStringArray = PackedStringArray()
var _locale_at_emit: PackedStringArray = PackedStringArray()


func before_test() -> void:
	_dir = SaveFixtures.make_dir("localization_autoload")
	_saved_locale = TranslationServer.get_locale()
	_emitted = PackedStringArray()
	_locale_at_emit = PackedStringArray()
	EventBus.language_changed.connect(_on_language_changed)


func after_test() -> void:
	if EventBus.language_changed.is_connected(_on_language_changed):
		EventBus.language_changed.disconnect(_on_language_changed)
	TranslationServer.set_locale(_saved_locale)
	SaveFixtures.remove_dir(_dir)
	SaveFixtures.remove_root_if_empty()


func _on_language_changed(language: String) -> void:
	_emitted.append(language)
	_locale_at_emit.append(TranslationServer.get_locale())


func _path() -> String:
	return _dir.path_join("settings.cfg")


## A fresh autoload instance on the test path with an injected OS locale, already in the tree.
func _make(os_locale: String) -> Node:
	var node: Node = LocalizationScript.new()
	node.settings_path = _path()
	node.os_locale_source = func() -> String: return os_locale
	add_child(node)
	auto_free(node)
	return node


# --- startup -----------------------------------------------------------------------------


func test_hungarian_os_locale_without_a_file_starts_in_magyar() -> void:
	var node: Node = _make("hu_HU")
	assert_str(node.get_language()).is_equal("hu")
	assert_str(TranslationServer.get_locale()).starts_with("hu")


func test_other_os_locale_without_a_file_starts_in_english() -> void:
	var node: Node = _make("de_DE")
	assert_str(node.get_language()).is_equal("en")
	assert_str(TranslationServer.get_locale()).starts_with("en")


func test_a_stored_language_wins_over_the_os_locale() -> void:
	SaveFixtures.write_text(_path(), '[general]\nlanguage="en"\n')
	var node: Node = _make("hu_HU")
	assert_str(node.get_language()).is_equal("en")
	assert_str(TranslationServer.get_locale()).starts_with("en")


func test_startup_emits_nothing_and_writes_nothing() -> void:
	var node: Node = _make("hu_HU")
	assert_str(node.get_language()).is_equal("hu")
	assert_array(_emitted).is_empty()
	assert_bool(FileAccess.file_exists(_path())).is_false()


# --- the API -----------------------------------------------------------------------------


func test_supported_languages_and_display_names() -> void:
	var node: Node = _make("en_US")
	assert_array(node.get_supported_languages()).is_equal(["en", "hu"])
	assert_str(node.get_language_display_name("en")).is_equal("English")
	assert_str(node.get_language_display_name("hu")).is_equal("Magyar")
	assert_str(node.get_language_display_name("xx")).is_empty()
	assert_str(node.get_language_display_name("")).is_empty()


func test_the_display_names_do_not_depend_on_the_language() -> void:
	var node: Node = _make("hu_HU")
	assert_str(node.get_language_display_name("en")).is_equal("English")
	assert_int(node.set_language("en")).is_equal(OK)
	assert_str(node.get_language_display_name("hu")).is_equal("Magyar")


func test_set_language_switches_the_locale_and_emits_on_the_event_bus() -> void:
	var node: Node = _make("hu_HU")
	assert_int(node.set_language("en")).is_equal(OK)
	assert_str(node.get_language()).is_equal("en")
	assert_array(_emitted).is_equal(["en"])
	assert_str(TranslationServer.get_locale()).starts_with("en")


func test_the_signal_comes_after_the_locale_was_switched() -> void:
	var node: Node = _make("en_US")
	assert_int(node.set_language("hu")).is_equal(OK)
	assert_array(_emitted).is_equal(["hu"])
	assert_array(_locale_at_emit).has_size(1)
	assert_str(_locale_at_emit[0]).starts_with("hu")


func test_the_same_language_again_emits_nothing() -> void:
	var node: Node = _make("hu_HU")
	assert_int(node.set_language("hu")).is_equal(OK)
	assert_array(_emitted).is_empty()
	assert_int(node.set_language("en")).is_equal(OK)
	assert_int(node.set_language("en")).is_equal(OK)
	assert_array(_emitted).is_equal(["en"])


func test_an_unsupported_code_is_refused() -> void:
	var node: Node = _make("hu_HU")
	for code: String in ["xx", "", "HU", "hu_HU"]:
		assert_int(node.set_language(code)).override_failure_message(code).is_equal(
			ERR_INVALID_PARAMETER
		)
	assert_str(node.get_language()).is_equal("hu")
	assert_array(_emitted).is_empty()
	assert_bool(FileAccess.file_exists(_path())).is_false()


func test_the_choice_is_saved_and_a_restart_reads_it_back() -> void:
	var first: Node = _make("en_US")
	assert_int(first.set_language("hu")).is_equal(OK)
	var config: ConfigFile = ConfigFile.new()
	assert_int(config.load(_path())).is_equal(OK)
	assert_str(config.get_value("general", "language")).is_equal("hu")
	first.queue_free()
	await get_tree().process_frame
	var second: Node = _make("en_US")
	assert_str(second.get_language()).is_equal("hu")


func test_a_failed_write_still_switches_the_language() -> void:
	DirAccess.make_dir_recursive_absolute(_path())
	var node: Node = _make("en_US")
	assert_int(node.set_language("hu")).is_equal(OK)
	assert_str(node.get_language()).is_equal("hu")
	assert_array(_emitted).is_equal(["hu"])
	assert_str(TranslationServer.get_locale()).starts_with("hu")


func test_the_instance_without_an_injected_locale_source_still_starts() -> void:
	# The default source is the real OS locale; only the result "a supported language" is asserted.
	var node: Node = LocalizationScript.new()
	node.settings_path = _path()
	add_child(node)
	auto_free(node)
	assert_array(["en", "hu"]).contains([node.get_language()])


# --- the shared date, time and number formatter ------------------------------------------


func test_local_format_is_null_before_ready() -> void:
	var node: Node = LocalizationScript.new()
	auto_free(node)
	assert_object(node.local_format()).is_null()


func test_local_format_follows_set_language_after_ready() -> void:
	var node: Node = _make("de_DE")
	var format: LocalFormat = node.local_format()
	assert_object(format).is_not_null()
	assert_str(format.format_number(3.5, 1)).is_equal("3.5")
	assert_int(node.set_language("hu")).is_equal(OK)
	assert_str(format.format_number(3.5, 1)).is_equal("3,5")
	assert_str(node.local_format().format_number(3.5, 1)).is_equal("3,5")
	assert_int(node.set_language("en")).is_equal(OK)
	assert_str(format.format_number(3.5, 1)).is_equal("3.5")


func test_local_format_dates_follow_the_language_and_the_real_clock() -> void:
	var node: Node = _make("hu_HU")
	var stamp: int = 1782864000 + 12 * 3600
	var hungarian: String = node.local_format().format_date(stamp)
	assert_str(hungarian).is_equal("2026. 07. 01.")
	assert_int(node.set_language("en")).is_equal(OK)
	assert_str(node.local_format().format_date(stamp)).is_equal("2026-07-01")
