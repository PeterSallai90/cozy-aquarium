extends GdUnitTestSuite
## The placeholder Settings button of the tank controls (#164 owner request, final menu: #38):
## it opens the settings screen over the game, Close and Esc hide it, it closes the other panels
## and cancels a placement ghost. The screen gets Settings and Localization instances on a test
## path before it enters the tree, so nothing touches the real settings.cfg.

const SettingsRig := preload("res://tests/helpers/settings_rig.gd")
const SaveFixtures := preload("res://tests/helpers/save_fixtures.gd")

var _dir: String = ""
var _saved_locale: String = ""
var _controls: Control = null
var _clears: int = 0


func before_test() -> void:
	_dir = SaveFixtures.make_dir("tank_controls_settings")
	_saved_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	_clears = 0
	var settings: Node = auto_free(SettingsRig.make_settings(self, _dir.path_join("settings.cfg")))
	var loc: Node = auto_free(
		SettingsRig.make_localization(self, _dir.path_join("language.cfg"), "en")
	)
	_controls = (load("res://ui/tank/tank_controls.tscn") as PackedScene).instantiate() as Control
	var screen: Control = _controls.get_node("SettingsScreen") as Control
	screen.set("settings", settings)
	screen.set("localization", loc)
	add_child(_controls)
	auto_free(_controls)
	EventBus.item_pick_clear_requested.connect(_on_clear)
	await get_tree().process_frame


func after_test() -> void:
	if EventBus.item_pick_clear_requested.is_connected(_on_clear):
		EventBus.item_pick_clear_requested.disconnect(_on_clear)
	TranslationServer.set_locale(_saved_locale)
	SaveFixtures.remove_dir(_dir)
	SaveFixtures.remove_root_if_empty()


func _on_clear() -> void:
	_clears += 1


func _button() -> Button:
	return _controls.get_node("Group/Buttons/SettingsButton") as Button


func _screen() -> Control:
	return _controls.get_node("SettingsScreen") as Control


func test_the_button_exists_with_the_translated_label_and_the_screen_starts_hidden() -> void:
	assert_object(_button()).is_not_null()
	assert_str(_button().text).is_equal("settings.open_button")
	assert_str(_button().tr(_button().text)).is_equal("Settings")
	assert_bool(_screen().visible).is_false()


func test_pressing_the_button_opens_the_screen_and_cancels_a_placement_ghost() -> void:
	_button().pressed.emit()
	assert_bool(_screen().visible).is_true()
	assert_int(_clears).is_equal(1)


func test_the_screen_blocks_clicks_to_the_world() -> void:
	assert_int(_screen().mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)


func test_close_hides_the_screen_and_returns_the_focus_to_the_button() -> void:
	_button().pressed.emit()
	(_screen().get_node("Panel/Layout/Footer/Close") as Button).pressed.emit()
	assert_bool(_screen().visible).is_false()
	assert_bool(_button().has_focus()).is_true()


func test_esc_hides_the_screen() -> void:
	_button().pressed.emit()
	var esc: InputEventAction = InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	Input.parse_input_event(esc)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(_screen().visible).is_false()


func test_pressing_the_button_again_closes_the_screen() -> void:
	_button().pressed.emit()
	_button().pressed.emit()
	assert_bool(_screen().visible).is_false()


func test_opening_the_screen_closes_the_open_panel_and_the_reverse() -> void:
	var fish_panel: Control = _controls.get_node("Group/FishPanel") as Control
	_controls.call("open_panel", fish_panel)
	assert_bool(fish_panel.visible).is_true()
	_button().pressed.emit()
	assert_bool(_screen().visible).is_true()
	assert_bool(fish_panel.visible).is_false()
	_controls.call("open_panel", fish_panel)
	assert_bool(_screen().visible).is_false()
