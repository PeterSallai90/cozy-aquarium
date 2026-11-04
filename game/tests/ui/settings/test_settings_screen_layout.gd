extends GdUnitTestSuite
## AC 5: at 1280x720 in Hungarian every visible control lies inside the screen, no Label is
## clipped, the section area scrolls when the content grows, and Close stays visible. The screen
## is rendered into a SubViewport so the check works headless.

const EngineOutput := preload("res://tests/helpers/engine_output.gd")
const SettingsRig := preload("res://tests/helpers/settings_rig.gd")
const SaveFixtures := preload("res://tests/helpers/save_fixtures.gd")

const WINDOW := Vector2i(1280, 720)
const TOLERANCE := 0.5

const SETTING_NOT_SAVED := "Setting fixture/volume not saved: Can't open file"

var _dir: String = ""
var _saved_locale: String = ""
var _loc: Node = null
var _settings: Node = null


func before_test() -> void:
	_dir = SaveFixtures.make_dir("settings_layout")
	_saved_locale = TranslationServer.get_locale()


func after_test() -> void:
	TranslationServer.set_locale(_saved_locale)
	SaveFixtures.remove_dir(_dir)
	SaveFixtures.remove_root_if_empty()


func _path() -> String:
	return _dir.path_join("settings.cfg")


## The screen inside a 1280x720 SubViewport, Hungarian, after two frames; null while missing.
func _screen_in_window(list: Resource = null) -> Control:
	_loc = auto_free(SettingsRig.make_localization(self, _path(), "hu_HU"))
	_settings = auto_free(SettingsRig.make_settings(self, _path()))
	var screen: Control = SettingsRig.new_screen(_settings, _loc, list)
	assert_object(screen).override_failure_message("settings_screen.tscn is missing").is_not_null()
	if screen == null:
		return null
	var viewport: SubViewport = SubViewport.new()
	viewport.size = WINDOW
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(auto_free(viewport))
	viewport.add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	return screen


func _outside(control: Control) -> bool:
	var area: Rect2 = Rect2(Vector2.ZERO, Vector2(WINDOW)).grow(TOLERANCE)
	var rect: Rect2 = control.get_global_rect()
	return not (area.has_point(rect.position) and area.has_point(rect.end))


func _tall_list() -> Resource:
	var language_scene: PackedScene = SettingsRig.load_or_null(SettingsRig.LANGUAGE_SCENE)
	var fixture_scene: PackedScene = SettingsRig.fixture_scene()
	var scenes: Array[PackedScene] = [language_scene, fixture_scene]
	var list: Resource = SettingsRig.section_list(scenes)
	assert_object(list).override_failure_message("SettingsSectionList is missing").is_not_null()
	return list


func test_the_screen_fills_the_window() -> void:
	var screen: Control = await _screen_in_window()
	if screen == null:
		return
	assert_vector(screen.size).is_equal(Vector2(WINDOW))


func test_every_visible_control_lies_inside_the_screen() -> void:
	var screen: Control = await _screen_in_window()
	if screen == null:
		return
	var checked: int = 0
	var offences: PackedStringArray = PackedStringArray()
	for node: Node in screen.find_children("*", "Control", true, false):
		var control: Control = node as Control
		if not control.is_visible_in_tree():
			continue
		checked += 1
		if _outside(control):
			offences.append("%s %s" % [control.name, control.get_global_rect()])
	assert_int(checked).is_greater(3)
	assert_array(offences).override_failure_message("outside: %s" % [offences]).is_empty()


func test_no_label_is_clipped_in_hungarian() -> void:
	var screen: Control = await _screen_in_window()
	if screen == null:
		return
	var labels: int = 0
	for node: Node in screen.find_children("*", "Label", true, false):
		var label: Label = node as Label
		if not label.is_visible_in_tree():
			continue
		labels += 1
		assert_bool(label.clip_text).override_failure_message("%s clips" % label.name).is_false()
		if label.autowrap_mode == TextServer.AUTOWRAP_OFF:
			(
				assert_float(maxf(label.get_minimum_size().x, SettingsRig.shown_width(label)))
				. override_failure_message("%s is wider than it is" % label.name)
				. is_less_equal(label.size.x + TOLERANCE)
			)
	assert_int(labels).is_greater_equal(2)


func test_every_label_and_button_text_can_auto_translate_in_hungarian() -> void:
	var screen: Control = await _screen_in_window()
	if screen == null:
		return
	var offences: PackedStringArray = SettingsRig.untranslatable(screen)
	assert_array(offences).override_failure_message("raw keys: %s" % [offences]).is_empty()


func test_the_close_button_is_inside_the_screen() -> void:
	var screen: Control = await _screen_in_window()
	if screen == null:
		return
	var close: Control = SettingsRig.part(screen, "Close") as Control
	assert_bool(close.is_visible_in_tree()).is_true()
	assert_bool(_outside(close)).is_false()


func test_a_long_message_line_fits_in_hungarian() -> void:
	DirAccess.make_dir_recursive_absolute(_path())
	var screen: Control = await _screen_in_window()
	if screen == null:
		return
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void: _settings.set_value(SettingsRig.volume_key(), 0.8)
	)
	assert_dict(seen.warnings).is_equal({SETTING_NOT_SAVED: 1})
	assert_dict(seen.errors).is_empty()
	await get_tree().process_frame
	await get_tree().process_frame
	var message: Label = SettingsRig.part(screen, "Message") as Label
	assert_bool(message.is_visible_in_tree()).is_true()
	assert_bool(_outside(message)).is_false()
	assert_bool(message.clip_text).is_false()
	if message.autowrap_mode == TextServer.AUTOWRAP_OFF:
		assert_float(SettingsRig.shown_width(message)).is_less_equal(message.size.x + TOLERANCE)
	var close: Control = SettingsRig.part(screen, "Close") as Control
	assert_bool(_outside(close)).is_false()
	assert_bool(_outside(SettingsRig.part(screen, "Sections") as Control)).is_false()


func test_tall_content_scrolls_and_close_stays_visible() -> void:
	var screen: Control = await _screen_in_window(_tall_list())
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
	var bar: VScrollBar = scroll.get_v_scroll_bar()
	assert_float(bar.max_value).is_greater(bar.page)
	assert_int(scroll.vertical_scroll_mode).is_not_equal(ScrollContainer.SCROLL_MODE_DISABLED)
	assert_bool(_outside(scroll)).is_false()
	var close: Control = SettingsRig.part(screen, "Close") as Control
	assert_bool(close.is_visible_in_tree()).is_true()
	assert_bool(_outside(close)).is_false()
	assert_bool(_outside(sections)).is_false()


func test_the_section_does_not_scroll_sideways() -> void:
	var screen: Control = await _screen_in_window(_tall_list())
	if screen == null:
		return
	var sections: TabContainer = SettingsRig.part(screen, "Sections") as TabContainer
	for index: int in sections.get_tab_count():
		var scroll: ScrollContainer = sections.get_child(index) as ScrollContainer
		assert_int(scroll.horizontal_scroll_mode).is_equal(ScrollContainer.SCROLL_MODE_DISABLED)
