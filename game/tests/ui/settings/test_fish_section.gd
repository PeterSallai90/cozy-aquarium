extends GdUnitTestSuite
## #164 the Fish section of the settings screen (owner: tester; fish_section.tscn, appended to
## settings_sections.tres): tab "Fish" with a row label "Show fish names" and a CheckButton named
## ShowNames. The toggle shows [fish] show_names, writes it through Settings (one change, no loop)
## and follows a change made elsewhere. In Hungarian at the default 1152 x 648 window the tab
## "Halak", the label "Halak nevének megjelenítése" and the toggle are inside the window and the
## label is not clipped (the #165 lesson). Minimal placeholder UI by owner decision.

const SettingsRig := preload("res://tests/helpers/settings_rig.gd")
const LabelRig := preload("res://tests/helpers/fish_label_rig.gd")
const SaveFixtures := preload("res://tests/helpers/save_fixtures.gd")

const WINDOW := Vector2i(1152, 648)
const TOLERANCE := 0.5
const FISH_TAB: int = 1

var _dir: String = ""
var _saved_locale: String = ""
var _loc: Node = null
var _settings: Node = null


func before_test() -> void:
	_dir = SaveFixtures.make_dir("fish_section")
	_saved_locale = TranslationServer.get_locale()


func after_test() -> void:
	TranslationServer.set_locale(_saved_locale)
	SaveFixtures.remove_dir(_dir)
	SaveFixtures.remove_root_if_empty()


func _path() -> String:
	return _dir.path_join("settings.cfg")


## The shipped screen in a SubViewport of `size`, with the Fish tab selected; null when missing.
func _screen(os_locale: String, size: Vector2i = WINDOW) -> Control:
	_loc = auto_free(SettingsRig.make_localization(self, _path(), os_locale))
	_settings = auto_free(SettingsRig.make_settings(self, _path()))
	var screen: Control = SettingsRig.new_screen(_settings, _loc)
	assert_object(screen).override_failure_message("settings_screen.tscn is missing").is_not_null()
	if screen == null:
		return null
	var viewport: SubViewport = SubViewport.new()
	viewport.size = size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(auto_free(viewport))
	viewport.add_child(screen)
	await get_tree().process_frame
	var sections: TabContainer = SettingsRig.part(screen, "Sections") as TabContainer
	if sections.get_tab_count() > FISH_TAB:
		sections.current_tab = FISH_TAB
	await get_tree().process_frame
	await get_tree().process_frame
	return screen


func _toggle(screen: Control) -> CheckButton:
	var toggle: CheckButton = SettingsRig.part(screen, "ShowNames") as CheckButton
	assert_object(toggle).override_failure_message("no ShowNames CheckButton").is_not_null()
	return toggle


func _inside(control: Control) -> bool:
	var area: Rect2 = Rect2(Vector2.ZERO, Vector2(WINDOW)).grow(TOLERANCE)
	var rect: Rect2 = control.get_global_rect()
	return area.has_point(rect.position) and area.has_point(rect.end)


func test_the_shipped_screen_has_a_fish_tab_after_language_with_a_show_names_toggle() -> void:
	var screen: Control = await _screen("en_US")
	if screen == null:
		return
	var sections: TabContainer = SettingsRig.part(screen, "Sections") as TabContainer
	assert_int(sections.get_tab_count()).is_equal(2)
	assert_str(sections.get_tab_title(0)).is_equal("Language")
	assert_str(sections.get_tab_title(1)).is_equal("Fish")
	var toggle: CheckButton = _toggle(screen)
	if toggle == null:
		return
	assert_bool(toggle.is_visible_in_tree()).is_true()
	assert_bool(toggle.button_pressed).is_false()


func test_the_row_label_says_show_fish_names_and_can_auto_translate() -> void:
	var screen: Control = await _screen("en_US")
	if screen == null:
		return
	var toggle: CheckButton = _toggle(screen)
	if toggle == null:
		return
	var label: Label = toggle.get_parent().find_child("Label", true, false) as Label
	assert_object(label).is_not_null()
	assert_str(label.text).is_equal("settings.fish_names.label")
	assert_str(SettingsRig.shown(label)).is_equal("Show fish names")
	assert_array(SettingsRig.untranslatable(screen)).is_empty()


func test_toggling_writes_fish_show_names_once_and_the_file_holds_it() -> void:
	var screen: Control = await _screen("en_US")
	if screen == null:
		return
	var toggle: CheckButton = _toggle(screen)
	var key: SettingKey = LabelRig.key() as SettingKey
	if toggle == null or key == null:
		assert_bool(false).override_failure_message("toggle or FishSettingKeys missing").is_true()
		return
	toggle.button_pressed = true
	assert_bool(_settings.get_value(key)).is_true()
	var config: ConfigFile = SettingsRig.read_config(_path())
	assert_bool(config.get_value("fish", "show_names", false)).is_true()
	toggle.button_pressed = false
	assert_bool(_settings.get_value(key)).is_false()
	config = SettingsRig.read_config(_path())
	assert_bool(config.get_value("fish", "show_names", true)).is_false()


func test_the_toggle_starts_on_when_the_setting_is_saved_on() -> void:
	var first: Node = auto_free(SettingsRig.make_settings(self, _path()))
	var key: SettingKey = LabelRig.key() as SettingKey
	if first == null or key == null:
		assert_bool(false).override_failure_message("Settings or FishSettingKeys missing").is_true()
		return
	first.set_value(key, true)
	var screen: Control = await _screen("en_US")
	if screen == null:
		return
	var toggle: CheckButton = _toggle(screen)
	if toggle != null:
		assert_bool(toggle.button_pressed).is_true()


func test_a_change_made_elsewhere_moves_the_toggle_without_writing_again() -> void:
	var screen: Control = await _screen("en_US")
	var key: SettingKey = LabelRig.key() as SettingKey
	if screen == null or key == null:
		assert_bool(false).override_failure_message("screen or FishSettingKeys missing").is_true()
		return
	var toggle: CheckButton = _toggle(screen)
	if toggle == null:
		return
	var seen: Array = []
	var record: Callable = func(section: String, entry_key: String, value: Variant) -> void:
		if section == "fish" and entry_key == "show_names":
			seen.append(value)
	EventBus.setting_changed.connect(record)
	_settings.set_value(key, true)
	await get_tree().process_frame
	EventBus.setting_changed.disconnect(record)
	assert_bool(toggle.button_pressed).is_true()
	assert_array(seen).is_equal([true])


func test_in_hungarian_the_tab_the_label_and_the_toggle_fit_the_default_window() -> void:
	var screen: Control = await _screen("hu_HU")
	if screen == null:
		return
	var sections: TabContainer = SettingsRig.part(screen, "Sections") as TabContainer
	assert_int(sections.get_tab_count()).is_equal(2)
	assert_str(sections.get_tab_title(FISH_TAB)).is_equal("Halak")
	var tab_rect: Rect2 = sections.get_tab_bar().get_tab_rect(FISH_TAB)
	var tab_global: Rect2 = Rect2(
		sections.get_tab_bar().global_position + tab_rect.position, tab_rect.size
	)
	var area: Rect2 = Rect2(Vector2.ZERO, Vector2(WINDOW)).grow(TOLERANCE)
	assert_bool(area.encloses(tab_global)).override_failure_message("tab %s" % tab_global).is_true()
	var toggle: CheckButton = _toggle(screen)
	if toggle == null:
		return
	assert_bool(toggle.is_visible_in_tree()).is_true()
	(
		assert_bool(_inside(toggle))
		. override_failure_message("toggle %s" % toggle.get_global_rect())
		. is_true()
	)
	var label: Label = toggle.get_parent().find_child("Label", true, false) as Label
	assert_str(SettingsRig.shown(label)).is_equal("Halak nevének megjelenítése")
	assert_bool(_inside(label)).is_true()
	assert_bool(label.clip_text).is_false()
	if label.autowrap_mode == TextServer.AUTOWRAP_OFF:
		assert_float(SettingsRig.shown_width(label)).is_less_equal(label.size.x + TOLERANCE)
	(
		assert_bool(
			label.get_global_rect().end.x <= toggle.get_global_rect().position.x + TOLERANCE
		)
		. is_true()
	)
	var close: Control = SettingsRig.part(screen, "Close") as Control
	assert_bool(_inside(close)).is_true()
