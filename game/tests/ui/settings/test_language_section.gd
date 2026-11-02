extends GdUnitTestSuite
## The Language section inside the screen: AC 6 to 10, and its part in AC 8, 12, 13 and 14.
## Fresh Localization and Settings instances on a test path; the live ones are never written.

const SettingsRig := preload("res://tests/helpers/settings_rig.gd")
const SaveFixtures := preload("res://tests/helpers/save_fixtures.gd")

var _dir: String = ""
var _saved_locale: String = ""
var _loc: Node = null
var _settings: Node = null
var _languages: PackedStringArray = PackedStringArray()


func before_test() -> void:
	_dir = SaveFixtures.make_dir("language_section")
	_saved_locale = TranslationServer.get_locale()
	_languages = PackedStringArray()
	EventBus.language_changed.connect(_on_language_changed)


func after_test() -> void:
	if EventBus.language_changed.is_connected(_on_language_changed):
		EventBus.language_changed.disconnect(_on_language_changed)
	TranslationServer.set_locale(_saved_locale)
	SaveFixtures.remove_dir(_dir)
	SaveFixtures.remove_root_if_empty()


func _on_language_changed(language: String) -> void:
	_languages.append(language)


func _path() -> String:
	return _dir.path_join("settings.cfg")


func _open(os_locale: String = "en_US", list: Resource = null) -> Control:
	_loc = auto_free(SettingsRig.make_localization(self, _path(), os_locale))
	_settings = auto_free(SettingsRig.make_settings(self, _path()))
	var screen: Control = SettingsRig.new_screen(_settings, _loc, list)
	assert_object(screen).override_failure_message("settings_screen.tscn is missing").is_not_null()
	if screen == null:
		return null
	add_child(auto_free(screen))
	await get_tree().process_frame
	return screen


func _option(screen: Control) -> OptionButton:
	return SettingsRig.part(screen, "LanguageOption") as OptionButton


func _selected_code(option: OptionButton) -> String:
	if option.selected < 0:
		return ""
	return option.get_item_metadata(option.selected)


func _stored_language() -> Variant:
	return SettingsRig.read_config(_path()).get_value("general", "language", null)


func _two_section_list() -> Resource:
	var language_scene: PackedScene = SettingsRig.load_or_null(SettingsRig.LANGUAGE_SCENE)
	var fixture_scene: PackedScene = SettingsRig.fixture_scene()
	var scenes: Array[PackedScene] = [language_scene, fixture_scene]
	var list: Resource = SettingsRig.section_list(scenes)
	assert_object(list).override_failure_message("SettingsSectionList is missing").is_not_null()
	return list


# --- AC 6: the list ------------------------------------------------------------------------


func test_the_selector_lists_the_supported_languages_in_their_own_names() -> void:
	var screen: Control = await _open("en_US")
	if screen == null:
		return
	var option: OptionButton = _option(screen)
	assert_object(option).is_not_null()
	assert_int(option.item_count).is_equal(2)
	assert_str(option.get_item_text(0)).is_equal("English")
	assert_str(option.get_item_text(1)).is_equal("Magyar")
	assert_str(option.get_item_metadata(0)).is_equal("en")
	assert_str(option.get_item_metadata(1)).is_equal("hu")


func test_the_names_do_not_depend_on_the_ui_language() -> void:
	var screen: Control = await _open("hu_HU")
	if screen == null:
		return
	var option: OptionButton = _option(screen)
	assert_int(option.item_count).is_equal(2)
	assert_str(option.get_item_text(0)).is_equal("English")
	assert_str(option.get_item_text(1)).is_equal("Magyar")


func test_the_selector_lists_exactly_what_localization_reports() -> void:
	var screen: Control = await _open("en_US")
	if screen == null:
		return
	var option: OptionButton = _option(screen)
	var codes: Array = _loc.get_supported_languages()
	assert_int(option.item_count).is_equal(codes.size())
	for index: int in mini(option.item_count, codes.size()):
		assert_str(option.get_item_metadata(index)).is_equal(codes[index])
		assert_str(option.get_item_text(index)).is_equal(
			_loc.get_language_display_name(codes[index])
		)


func test_the_active_language_is_selected() -> void:
	var screen: Control = await _open("hu_HU")
	if screen == null:
		return
	assert_str(_selected_code(_option(screen))).is_equal("hu")


func test_the_english_entry_is_selected_for_english() -> void:
	var screen: Control = await _open("en_US")
	if screen == null:
		return
	assert_str(_selected_code(_option(screen))).is_equal("en")


# --- AC 7: choosing another language ---------------------------------------------------------


func test_choosing_hungarian_switches_saves_and_updates_the_selector() -> void:
	var screen: Control = await _open("en_US")
	if screen == null:
		return
	var title: Label = SettingsRig.part(screen, "Title") as Label
	var english: String = SettingsRig.shown(title)
	_option(screen).item_selected.emit(1)
	await get_tree().process_frame
	assert_str(_loc.get_language()).is_equal("hu")
	assert_str(TranslationServer.get_locale()).starts_with("hu")
	assert_str(_stored_language()).is_equal("hu")
	assert_str(_selected_code(_option(screen))).is_equal("hu")
	assert_str(SettingsRig.shown(title)).is_equal(screen.tr("settings.title"))
	assert_str(SettingsRig.shown(title)).is_not_equal(english)
	assert_array(_languages).is_equal(["hu"])


func test_the_open_tab_the_focus_and_the_selector_stay_after_a_choice() -> void:
	var screen: Control = await _open("en_US")
	if screen == null:
		return
	var option: OptionButton = _option(screen)
	var sections: TabContainer = SettingsRig.part(screen, "Sections") as TabContainer
	option.grab_focus()
	option.item_selected.emit(1)
	await get_tree().process_frame
	assert_int(sections.current_tab).is_equal(0)
	assert_object(screen.get_viewport().gui_get_focus_owner()).is_same(option)
	assert_object(_option(screen)).is_same(option)
	assert_int(option.item_count).is_equal(2)


func test_a_change_from_outside_keeps_the_tab_the_focus_and_the_scroll_position() -> void:
	var screen: Control = await _open("en_US", _two_section_list())
	if screen == null:
		return
	var sections: TabContainer = SettingsRig.part(screen, "Sections") as TabContainer
	var fixture: Control = sections.get_child(1).get_child(0) as Control
	for index: int in 80:
		var filler: Label = Label.new()
		filler.text = "filler %d" % index
		fixture.add_child(filler)
	sections.current_tab = 1
	await get_tree().process_frame
	await get_tree().process_frame
	var scroll: ScrollContainer = sections.get_child(1) as ScrollContainer
	scroll.scroll_vertical = 120
	var button: Control = SettingsRig.part(screen, "FixtureButton") as Control
	button.grab_focus()
	assert_int(scroll.scroll_vertical).is_equal(120)
	assert_int(_loc.set_language("hu")).is_equal(OK)
	await get_tree().process_frame
	assert_int(sections.current_tab).is_equal(1)
	assert_object(screen.get_viewport().gui_get_focus_owner()).is_same(button)
	assert_int(scroll.scroll_vertical).is_equal(120)


# --- AC 8: the same language again ---------------------------------------------------------


func test_choosing_the_shown_language_again_changes_and_writes_nothing() -> void:
	var seed_text: String = '[general]\nlanguage="en"\n'
	SaveFixtures.write_text(_path(), seed_text)
	var screen: Control = await _open("hu_HU")
	if screen == null:
		return
	var before: PackedByteArray = SaveFixtures.read_bytes(_path())
	_option(screen).item_selected.emit(0)
	assert_array(_languages).is_empty()
	assert_array(SaveFixtures.read_bytes(_path())).is_equal(before)
	assert_str(_selected_code(_option(screen))).is_equal("en")


func test_choosing_english_without_a_file_writes_no_file() -> void:
	var screen: Control = await _open("en_US")
	if screen == null:
		return
	_option(screen).item_selected.emit(0)
	assert_array(_languages).is_empty()
	assert_bool(FileAccess.file_exists(_path())).is_false()


# --- AC 9: a refused code ------------------------------------------------------------------


func test_an_unsupported_code_keeps_the_active_language_without_a_dialog() -> void:
	var screen: Control = await _open("hu_HU")
	if screen == null:
		return
	var section: Node = SettingsRig.language_section(screen)
	assert_object(section).override_failure_message("no node has choose_language").is_not_null()
	if section == null:
		return
	for code: String in ["xx", "", "HU", "hu_HU"]:
		assert_int(section.choose_language(code)).override_failure_message(code).is_equal(
			ERR_INVALID_PARAMETER
		)
	assert_str(_selected_code(_option(screen))).is_equal("hu")
	assert_str(_loc.get_language()).is_equal("hu")
	assert_array(_languages).is_empty()
	assert_array(get_tree().root.find_children("*", "AcceptDialog", true, false)).is_empty()
	assert_bool(screen.visible).is_true()
	assert_bool(FileAccess.file_exists(_path())).is_false()


func test_choose_language_returns_ok_for_a_supported_code() -> void:
	var screen: Control = await _open("en_US")
	if screen == null:
		return
	var section: Node = SettingsRig.language_section(screen)
	if section == null:
		return
	assert_int(section.choose_language("hu")).is_equal(OK)
	assert_str(_selected_code(_option(screen))).is_equal("hu")


# --- AC 10: a change from elsewhere ----------------------------------------------------------


func test_a_change_from_outside_updates_the_selector_and_every_text() -> void:
	DirAccess.make_dir_recursive_absolute(_path())
	var screen: Control = await _open("en_US")
	if screen == null:
		return
	_settings.set_value(SettingsRig.volume_key(), 0.8)
	var sections: TabContainer = SettingsRig.part(screen, "Sections") as TabContainer
	var title: Label = SettingsRig.part(screen, "Title") as Label
	var close: Button = SettingsRig.part(screen, "Close") as Button
	var message: Label = SettingsRig.part(screen, "Message") as Label
	var row_label: Label = SettingsRig.part(screen, "Label") as Label
	assert_object(row_label).override_failure_message("language row has no Label").is_not_null()
	var english: Dictionary = {
		"title": SettingsRig.shown(title),
		"close": SettingsRig.shown(close),
		"message": SettingsRig.shown(message),
		"row": SettingsRig.shown(row_label),
		"tab": sections.get_tab_title(0),
	}
	assert_int(_loc.set_language("hu")).is_equal(OK)
	await get_tree().process_frame
	assert_str(_selected_code(_option(screen))).is_equal("hu")
	assert_str(SettingsRig.shown(title)).is_equal(screen.tr("settings.title"))
	assert_str(SettingsRig.shown(close)).is_equal(screen.tr("settings.close"))
	assert_str(SettingsRig.shown(row_label)).is_equal(screen.tr("settings.language.label"))
	assert_str(SettingsRig.shown(message)).is_equal(screen.tr("settings.error.not_saved"))
	assert_str(sections.get_tab_title(0)).is_equal(screen.tr("settings.section.language"))
	assert_str(SettingsRig.shown(title)).is_not_equal(english["title"])
	assert_str(SettingsRig.shown(close)).is_not_equal(english["close"])
	assert_str(SettingsRig.shown(row_label)).is_not_equal(english["row"])
	assert_str(SettingsRig.shown(message)).is_not_equal(english["message"])
	assert_str(sections.get_tab_title(0)).is_not_equal(english["tab"])


func test_a_change_back_to_english_updates_the_selector() -> void:
	var screen: Control = await _open("hu_HU")
	if screen == null:
		return
	assert_int(_loc.set_language("en")).is_equal(OK)
	assert_str(_selected_code(_option(screen))).is_equal("en")
	assert_str(SettingsRig.shown(SettingsRig.part(screen, "Title") as Label)).is_equal("Settings")


# --- AC 12: only the changed key is written ---------------------------------------------------


func test_a_language_and_a_fixture_change_each_write_only_their_key() -> void:
	var seed_text: String = '[general]\nlanguage="en"\nmystery="keep"\n\n[audio]\nmaster=0.5\n\n'
	seed_text += "[unknown]\nx=1\n"
	SaveFixtures.write_text(_path(), seed_text)
	var screen: Control = await _open("hu_HU")
	if screen == null:
		return
	_option(screen).item_selected.emit(1)
	var config: ConfigFile = SettingsRig.read_config(_path())
	assert_str(config.get_value("general", "language")).is_equal("hu")
	assert_str(config.get_value("general", "mystery")).is_equal("keep")
	assert_float(config.get_value("audio", "master")).is_equal(0.5)
	assert_int(config.get_value("unknown", "x")).is_equal(1)
	assert_bool(config.has_section("fixture")).is_false()
	assert_int(_settings.set_value(SettingsRig.volume_key(), 0.8)).is_equal(OK)
	config = SettingsRig.read_config(_path())
	assert_float(config.get_value("fixture", "volume")).is_equal(0.8)
	assert_str(config.get_value("general", "language")).is_equal("hu")
	assert_str(config.get_value("general", "mystery")).is_equal("keep")
	assert_float(config.get_value("audio", "master")).is_equal(0.5)
	assert_int(config.get_value("unknown", "x")).is_equal(1)
	assert_array(config.get_sections()).has_size(4)


# --- AC 13 and 14: what a restart shows -------------------------------------------------------


func test_a_restart_shows_the_saved_language_in_the_selector() -> void:
	var first: Node = SettingsRig.make_localization(self, _path(), "en_US")
	assert_int(first.set_language("hu")).is_equal(OK)
	first.queue_free()
	await get_tree().process_frame
	TranslationServer.set_locale("en")
	var screen: Control = await _open("en_US")
	if screen == null:
		return
	assert_str(_selected_code(_option(screen))).is_equal("hu")
	assert_str(_loc.get_language()).is_equal("hu")


func test_an_unsupported_stored_language_shows_the_os_locale_result() -> void:
	var seed_text: String = '[general]\nlanguage="fr"\n'
	SaveFixtures.write_text(_path(), seed_text)
	var screen: Control = await _open("hu_HU")
	if screen == null:
		return
	assert_str(_selected_code(_option(screen))).is_equal("hu")
	screen.close()
	assert_str(SaveFixtures.read_text(_path())).is_equal(seed_text)


func test_an_unsupported_stored_language_and_other_os_locale_shows_english() -> void:
	SaveFixtures.write_text(_path(), '[general]\nlanguage="fr"\n')
	var screen: Control = await _open("de_DE")
	if screen == null:
		return
	assert_str(_selected_code(_option(screen))).is_equal("en")
