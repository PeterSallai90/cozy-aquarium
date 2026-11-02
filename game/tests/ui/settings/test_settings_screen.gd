# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## The settings screen shell: AC 1 to 4, and its part in AC 11, 15, 17 and 18. Every screen gets
## fresh Localization and Settings instances on a test path; nothing writes the real file.

const SettingsRig := preload("res://tests/helpers/settings_rig.gd")
const SaveFixtures := preload("res://tests/helpers/save_fixtures.gd")
const ModelState := preload("res://tests/helpers/model_state.gd")

var _dir: String = ""
var _saved_locale: String = ""
var _loc: Node = null
var _settings: Node = null
var _closed: Array = []


func before_test() -> void:
	_dir = SaveFixtures.make_dir("settings_screen")
	_saved_locale = TranslationServer.get_locale()
	_closed = []


func after_test() -> void:
	TranslationServer.set_locale(_saved_locale)
	SaveFixtures.remove_dir(_dir)
	SaveFixtures.remove_root_if_empty()


func _path() -> String:
	return _dir.path_join("settings.cfg")


func _on_closed() -> void:
	_closed.append(true)


## Creates both services and the screen and waits one frame; null while the scene is missing.
func _open(os_locale: String = "en_US", list: Resource = null) -> Control:
	_loc = auto_free(SettingsRig.make_localization(self, _path(), os_locale))
	_settings = auto_free(SettingsRig.make_settings(self, _path()))
	var screen: Control = SettingsRig.new_screen(_settings, _loc, list)
	assert_object(screen).override_failure_message("settings_screen.tscn is missing").is_not_null()
	if screen == null:
		return null
	screen.closed.connect(_on_closed)
	add_child(auto_free(screen))
	await get_tree().process_frame
	return screen


func _key_event(keycode: Key, pressed: bool, shift: bool = false) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	event.shift_pressed = shift
	return event


func _tap(screen: Control, keycode: Key, shift: bool = false) -> void:
	var viewport: Viewport = screen.get_viewport()
	viewport.push_input(_key_event(keycode, true, shift))
	viewport.push_input(_key_event(keycode, false, shift))


func _focus_owner(screen: Control) -> Control:
	return screen.get_viewport().gui_get_focus_owner()


# --- AC 1: the shell ---------------------------------------------------------------------


func test_the_screen_shows_the_title_one_section_and_a_close_button() -> void:
	var screen: Control = await _open()
	if screen == null:
		return
	assert_bool(screen.visible).is_true()
	var title: Label = SettingsRig.part(screen, "Title") as Label
	assert_object(title).is_not_null()
	assert_str(title.text).is_equal("settings.title")
	assert_str(SettingsRig.shown(title)).is_equal("Settings")
	var sections: TabContainer = SettingsRig.part(screen, "Sections") as TabContainer
	assert_object(sections).is_not_null()
	assert_int(sections.get_tab_count()).is_equal(1)
	assert_str(sections.get_tab_title(0)).is_equal(screen.tr("settings.section.language"))
	assert_str(sections.get_tab_title(0)).is_equal("Language")
	var close: Button = SettingsRig.part(screen, "Close") as Button
	assert_object(close).is_not_null()
	assert_str(close.text).is_equal("settings.close")
	assert_str(SettingsRig.shown(close)).is_equal("Close")


func test_the_message_line_is_empty_and_hidden_when_the_screen_opens() -> void:
	var screen: Control = await _open()
	if screen == null:
		return
	var message: Label = SettingsRig.part(screen, "Message") as Label
	assert_object(message).is_not_null()
	assert_bool(message.visible).is_false()


func test_the_screen_runs_on_its_own_with_the_live_services() -> void:
	var packed: PackedScene = SettingsRig.load_or_null(SettingsRig.SCREEN_SCENE) as PackedScene
	assert_object(packed).override_failure_message("settings_screen.tscn is missing").is_not_null()
	if packed == null:
		return
	var screen: Control = packed.instantiate() as Control
	add_child(auto_free(screen))
	await get_tree().process_frame
	assert_bool(screen.visible).is_true()
	assert_object(SettingsRig.part(screen, "Title")).is_not_null()
	assert_object(SettingsRig.part(screen, "Close")).is_not_null()
	assert_int((SettingsRig.part(screen, "Sections") as TabContainer).get_tab_count()).is_equal(1)


# --- AC 2: Esc and Close -----------------------------------------------------------------


func test_escape_closes_the_screen_and_emits_closed_once() -> void:
	var screen: Control = await _open()
	if screen == null:
		return
	_tap(screen, KEY_ESCAPE)
	assert_bool(screen.visible).is_false()
	assert_int(_closed.size()).is_equal(1)
	_tap(screen, KEY_ESCAPE)
	assert_int(_closed.size()).is_equal(1)
	screen.close()
	assert_int(_closed.size()).is_equal(1)


func test_the_close_button_closes_the_screen_and_emits_closed_once() -> void:
	var screen: Control = await _open()
	if screen == null:
		return
	(SettingsRig.part(screen, "Close") as Button).pressed.emit()
	assert_bool(screen.visible).is_false()
	assert_int(_closed.size()).is_equal(1)


func test_closing_leaves_the_scene_behind_it_unchanged() -> void:
	var model: AquariumModel = SaveFixtures.populated_model()
	var history: CommandHistory = CommandHistory.new()
	var before: Dictionary = ModelState.snapshot(model)
	var marker: Node2D = auto_free(Node2D.new())
	marker.position = Vector2(3, 4)
	add_child(marker)
	var screen: Control = await _open()
	if screen == null:
		return
	var parent: Node = screen.get_parent()
	_tap(screen, KEY_ESCAPE)
	assert_bool(is_instance_valid(screen)).is_true()
	assert_object(screen.get_parent()).is_same(parent)
	assert_bool(get_tree().paused).is_false()
	assert_bool(marker.visible).is_true()
	assert_vector(marker.position).is_equal(Vector2(3, 4))
	assert_dict(ModelState.snapshot(model)).is_equal(before)
	assert_int(history.get_undo_count()).is_equal(0)


func test_the_screen_can_be_opened_again_after_closing() -> void:
	var screen: Control = await _open()
	if screen == null:
		return
	screen.close()
	screen.open()
	assert_bool(screen.visible).is_true()
	screen.close()
	assert_int(_closed.size()).is_equal(2)


# --- AC 3: the keyboard ------------------------------------------------------------------


func test_tab_reaches_the_tab_bar_the_selector_and_close() -> void:
	var screen: Control = await _open()
	if screen == null:
		return
	var option: Control = SettingsRig.part(screen, "LanguageOption") as Control
	var close: Control = SettingsRig.part(screen, "Close") as Control
	var visited: Array[Control] = []
	var first: Control = _focus_owner(screen)
	assert_object(first).override_failure_message("nothing has focus after open()").is_not_null()
	if first != null:
		visited.append(first)
	for step: int in 8:
		_tap(screen, KEY_TAB)
		var focused: Control = _focus_owner(screen)
		if focused != null:
			visited.append(focused)
	assert_bool(visited.has(option)).override_failure_message("selector not reached").is_true()
	assert_bool(visited.has(close)).override_failure_message("Close not reached").is_true()
	var found_tab_bar: bool = false
	for control: Control in visited:
		found_tab_bar = found_tab_bar or control is TabBar
	assert_bool(found_tab_bar).override_failure_message("tab bar not reached").is_true()


func test_shift_tab_walks_backwards_from_close_to_the_selector() -> void:
	var screen: Control = await _open()
	if screen == null:
		return
	var option: Control = SettingsRig.part(screen, "LanguageOption") as Control
	var close: Control = SettingsRig.part(screen, "Close") as Control
	close.grab_focus()
	assert_object(_focus_owner(screen)).is_same(close)
	_tap(screen, KEY_TAB, true)
	assert_object(_focus_owner(screen)).is_same(option)


func test_enter_opens_the_selector_and_presses_close() -> void:
	var screen: Control = await _open()
	if screen == null:
		return
	var option: OptionButton = SettingsRig.part(screen, "LanguageOption") as OptionButton
	option.grab_focus()
	_tap(screen, KEY_ENTER)
	assert_bool(option.get_popup().visible).is_true()
	option.get_popup().hide()
	var close: Button = SettingsRig.part(screen, "Close") as Button
	close.grab_focus()
	_tap(screen, KEY_SPACE)
	assert_int(_closed.size()).is_equal(1)
	assert_bool(screen.visible).is_false()


func test_every_focusable_control_has_a_visible_focus_style() -> void:
	var screen: Control = await _open()
	if screen == null:
		return
	var checked: int = 0
	for control: Control in SettingsRig.focusable(screen):
		if control is TabBar:
			continue
		var style: StyleBox = control.get_theme_stylebox("focus")
		(
			assert_bool(style != null and not style is StyleBoxEmpty)
			. override_failure_message("%s has no visible focus style" % control.name)
			. is_true()
		)
		checked += 1
	assert_int(checked).is_greater_equal(2)


func test_open_puts_focus_on_a_control_of_the_screen() -> void:
	var screen: Control = await _open()
	if screen == null:
		return
	var focused: Control = _focus_owner(screen)
	assert_object(focused).is_not_null()
	if focused != null:
		assert_bool(screen.is_ancestor_of(focused)).is_true()


# --- AC 4: the extension contract --------------------------------------------------------


func test_a_section_added_after_ready_appears_next_to_language() -> void:
	var screen: Control = await _open()
	var fixture: Control = SettingsRig.make_fixture()
	assert_object(fixture).override_failure_message("fixture section is missing").is_not_null()
	if screen == null or fixture == null:
		return
	screen.add_section(fixture)
	await get_tree().process_frame
	var sections: TabContainer = SettingsRig.part(screen, "Sections") as TabContainer
	assert_int(sections.get_tab_count()).is_equal(2)
	assert_str(sections.get_tab_title(0)).is_equal("Language")
	assert_str(sections.get_tab_title(1)).is_equal(SettingsRig.FIXTURE_TITLE)
	assert_bool(screen.is_ancestor_of(fixture)).is_true()
	assert_object(fixture.get("localization")).is_same(_loc)
	assert_object(fixture.get("settings")).is_same(_settings)


func test_every_label_and_button_of_the_shipped_screen_can_auto_translate() -> void:
	var screen: Control = await _open()
	if screen == null:
		return
	var offences: PackedStringArray = SettingsRig.untranslatable(screen)
	assert_array(offences).override_failure_message("raw keys: %s" % [offences]).is_empty()
	var row_label: Label = SettingsRig.part(screen, "Label") as Label
	assert_object(row_label).is_not_null()
	assert_str(SettingsRig.shown(row_label)).is_equal("Language")


func test_a_fixture_section_label_and_button_can_auto_translate() -> void:
	var screen: Control = await _open()
	var fixture: Control = SettingsRig.make_fixture()
	assert_object(fixture).override_failure_message("fixture section is missing").is_not_null()
	if screen == null or fixture == null:
		return
	screen.add_section(fixture)
	await get_tree().process_frame
	var info: Label = fixture.find_child("Info", true, false) as Label
	var button: Button = fixture.find_child("FixtureButton", true, false) as Button
	info.text = "settings.close"
	button.text = "settings.close"
	assert_bool(info.can_auto_translate()).is_true()
	assert_bool(button.can_auto_translate()).is_true()
	assert_str(SettingsRig.shown(info)).is_equal("Close")
	assert_str(SettingsRig.shown(button)).is_equal("Close")
	assert_array(SettingsRig.untranslatable(screen)).is_empty()


func test_a_section_added_before_ready_appears_after_the_listed_ones() -> void:
	_loc = auto_free(SettingsRig.make_localization(self, _path(), "en_US"))
	_settings = auto_free(SettingsRig.make_settings(self, _path()))
	var screen: Control = SettingsRig.new_screen(_settings, _loc)
	var fixture: Control = SettingsRig.make_fixture()
	assert_object(screen).override_failure_message("settings_screen.tscn is missing").is_not_null()
	assert_object(fixture).override_failure_message("fixture section is missing").is_not_null()
	if screen == null or fixture == null:
		return
	screen.add_section(fixture)
	add_child(auto_free(screen))
	await get_tree().process_frame
	var sections: TabContainer = SettingsRig.part(screen, "Sections") as TabContainer
	assert_int(sections.get_tab_count()).is_equal(2)
	assert_str(sections.get_tab_title(0)).is_equal("Language")
	assert_str(sections.get_tab_title(1)).is_equal(SettingsRig.FIXTURE_TITLE)


func test_a_section_list_resource_decides_the_sections() -> void:
	var fixture_scene: PackedScene = SettingsRig.fixture_scene()
	var language_scene: PackedScene = SettingsRig.load_or_null(SettingsRig.LANGUAGE_SCENE)
	var scenes: Array[PackedScene] = [language_scene, fixture_scene]
	var list: Resource = SettingsRig.section_list(scenes)
	assert_object(list).override_failure_message("SettingsSectionList is missing").is_not_null()
	if list == null:
		return
	var screen: Control = await _open("en_US", list)
	if screen == null:
		return
	var sections: TabContainer = SettingsRig.part(screen, "Sections") as TabContainer
	assert_int(sections.get_tab_count()).is_equal(2)
	assert_str(sections.get_tab_title(1)).is_equal(SettingsRig.FIXTURE_TITLE)


func test_a_section_tab_title_follows_the_language() -> void:
	var screen: Control = await _open()
	if screen == null:
		return
	var sections: TabContainer = SettingsRig.part(screen, "Sections") as TabContainer
	var english: String = sections.get_tab_title(0)
	assert_int(_loc.set_language("hu")).is_equal(OK)
	await get_tree().process_frame
	assert_str(sections.get_tab_title(0)).is_equal(screen.tr("settings.section.language"))
	assert_str(sections.get_tab_title(0)).is_not_equal(english)


# --- AC 11 and 15: nothing is written by opening or closing -------------------------------


func test_opening_and_closing_without_a_change_creates_no_file() -> void:
	var screen: Control = await _open("hu_HU")
	if screen == null:
		return
	screen.close()
	screen.open()
	screen.close()
	assert_bool(FileAccess.file_exists(_path())).is_false()
	assert_array(SaveFixtures.listing(_dir)).is_empty()


func test_an_unparsable_file_gives_defaults_and_is_not_touched_by_opening() -> void:
	var text: String = "this is [not valid\n=="
	SaveFixtures.write_text(_path(), text)
	var screen: Control = await _open("en_US")
	if screen == null:
		return
	var option: OptionButton = SettingsRig.part(screen, "LanguageOption") as OptionButton
	assert_str(option.get_item_metadata(option.selected)).is_equal("en")
	assert_float(_settings.get_value(SettingsRig.volume_key())).is_equal(0.5)
	screen.close()
	assert_str(SaveFixtures.read_text(_path())).is_equal(text)
	assert_array(SaveFixtures.listing(_dir)).is_equal(["settings.cfg"])


func test_the_first_change_after_an_unparsable_file_keeps_a_backup() -> void:
	var text: String = "this is [not valid\n=="
	SaveFixtures.write_text(_path(), text)
	var screen: Control = await _open("en_US")
	if screen == null:
		return
	var option: OptionButton = SettingsRig.part(screen, "LanguageOption") as OptionButton
	option.item_selected.emit(1)
	assert_str(SaveFixtures.read_text(_path() + ".bak")).is_equal(text)
	var config: ConfigFile = SettingsRig.read_config(_path())
	assert_str(config.get_value("general", "language")).is_equal("hu")


# --- AC 17: the file cannot be written ----------------------------------------------------


func _message(screen: Control) -> Label:
	return SettingsRig.part(screen, "Message") as Label


func _message_shown(screen: Control) -> bool:
	var message: Label = _message(screen)
	return message.visible and not message.text.is_empty()


func test_a_failed_language_save_shows_the_message_and_still_switches() -> void:
	DirAccess.make_dir_recursive_absolute(_path())
	var screen: Control = await _open("en_US")
	if screen == null:
		return
	var option: OptionButton = SettingsRig.part(screen, "LanguageOption") as OptionButton
	option.item_selected.emit(1)
	assert_str(_loc.get_language()).is_equal("hu")
	assert_int(_loc.get_last_save_error()).is_not_equal(OK)
	assert_bool(_message_shown(screen)).is_true()
	assert_str(SettingsRig.shown(_message(screen))).is_equal(screen.tr("settings.error.not_saved"))
	assert_array(get_tree().root.find_children("*", "AcceptDialog", true, false)).is_empty()
	assert_bool(screen.visible).is_true()


func test_a_failed_setting_save_shows_the_message_and_keeps_the_value() -> void:
	DirAccess.make_dir_recursive_absolute(_path())
	var screen: Control = await _open("en_US")
	if screen == null:
		return
	assert_int(_settings.set_value(SettingsRig.volume_key(), 0.8)).is_equal(OK)
	assert_float(_settings.get_value(SettingsRig.volume_key())).is_equal(0.8)
	assert_bool(_message_shown(screen)).is_true()
	assert_str(SettingsRig.shown(_message(screen))).is_equal(
		"Your settings could not be saved. They still work until you close the game."
	)


func test_the_message_disappears_after_the_next_successful_write() -> void:
	DirAccess.make_dir_recursive_absolute(_path())
	var screen: Control = await _open("en_US")
	if screen == null:
		return
	_settings.set_value(SettingsRig.volume_key(), 0.8)
	assert_bool(_message_shown(screen)).is_true()
	DirAccess.remove_absolute(_path())
	_settings.set_value(SettingsRig.volume_key(), 0.3)
	assert_bool(_message_shown(screen)).is_false()
	assert_bool(_message(screen).visible).is_false()


func test_a_good_language_write_after_a_failed_setting_write_clears_the_message() -> void:
	DirAccess.make_dir_recursive_absolute(_path())
	var screen: Control = await _open("en_US")
	if screen == null:
		return
	_settings.set_value(SettingsRig.volume_key(), 0.8)
	assert_bool(_message_shown(screen)).is_true()
	DirAccess.remove_absolute(_path())
	assert_int(_loc.set_language("hu")).is_equal(OK)
	assert_bool(_message_shown(screen)).is_false()


func test_a_reopened_screen_shows_no_stale_message() -> void:
	DirAccess.make_dir_recursive_absolute(_path())
	var screen: Control = await _open("en_US")
	if screen == null:
		return
	_settings.set_value(SettingsRig.volume_key(), 0.8)
	assert_bool(_message_shown(screen)).is_true()
	screen.close()
	screen.open()
	assert_bool(_message_shown(screen)).is_false()


func test_the_message_text_follows_a_language_change() -> void:
	DirAccess.make_dir_recursive_absolute(_path())
	var screen: Control = await _open("en_US")
	if screen == null:
		return
	_settings.set_value(SettingsRig.volume_key(), 0.8)
	var english: String = SettingsRig.shown(_message(screen))
	assert_int(_loc.set_language("hu")).is_equal(OK)
	await get_tree().process_frame
	assert_bool(_message_shown(screen)).is_true()
	assert_str(SettingsRig.shown(_message(screen))).is_equal(screen.tr("settings.error.not_saved"))
	assert_str(SettingsRig.shown(_message(screen))).is_not_equal(english)


# --- AC 18: no save file, no model, no history ---------------------------------------------


func test_changes_leave_save_files_the_model_and_the_history_alone() -> void:
	var model: AquariumModel = SaveFixtures.populated_model()
	var history: CommandHistory = CommandHistory.new()
	var clock: Callable = func() -> String: return SaveFixtures.NOW
	var save_path: String = _dir.path_join("tank.json")
	assert_int(SaveStore.new(clock).save(model, save_path).kind).is_equal(SaveResult.Kind.OK)
	var saved_bytes: PackedByteArray = SaveFixtures.read_bytes(save_path)
	var before: Dictionary = ModelState.snapshot(model)
	var screen: Control = await _open("en_US")
	if screen == null:
		return
	var option: OptionButton = SettingsRig.part(screen, "LanguageOption") as OptionButton
	option.item_selected.emit(1)
	_settings.set_value(SettingsRig.volume_key(), 0.8)
	screen.close()
	assert_array(SaveFixtures.read_bytes(save_path)).is_equal(saved_bytes)
	assert_dict(ModelState.snapshot(model)).is_equal(before)
	assert_int(history.get_undo_count()).is_equal(0)
	assert_array(SaveFixtures.listing(_dir)).is_equal(["settings.cfg", "tank.json"])
