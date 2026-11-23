extends GdUnitTestSuite
## #164 AC "Off: panel and card still show names" (owner: tester): with [fish] show_names off (the
## default; the setting is never read by the panel) the fish panel row shows the shown name and
## the info card of the selected fish shows it too. The names are not tied to the labels.

const Fp := preload("res://tests/helpers/fish_panel_rig.gd")
const Ui := preload("res://tests/helpers/tank_ui_rig.gd")
const Api := preload("res://tests/helpers/fish_api.gd")
const LabelRig := preload("res://tests/helpers/fish_label_rig.gd")

var _saved_locale: String = ""
var _language_state: Dictionary = {}


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()
	_language_state = Ui.begin_language_isolation("fish_panel_names_off")
	TranslationServer.set_locale("en")


func after_test() -> void:
	Ui.end_language_isolation(_language_state, _saved_locale)


func test_164_the_panel_row_and_the_card_show_the_name_while_the_labels_are_off() -> void:
	var model: AquariumModel = Fp.model_with_tank()
	Fp.fill(model, 2)
	model.get_fish_list()[0].nickname = "Goldie"
	var key: SettingKey = LabelRig.key() as SettingKey
	(
		assert_object(key)
		. override_failure_message("FishSettingKeys.show_names() is missing")
		. is_not_null()
	)
	if key == null:
		return
	assert_bool(key.default_value).is_false()
	var controls: Control = await Fp.open_controls(self, model, Api.shipped())
	if controls == null or Fp.button_of(controls) == null:
		assert_bool(false).override_failure_message("no TankControls or Fish button").is_true()
		return
	auto_free(controls)
	await Fp.press_open(self, controls)
	var uids: Array[String] = Fp.row_uids(controls)
	assert_int(uids.size()).is_equal(2)
	var first: Button = Fp.name_button(controls, uids[0])
	assert_str(Fp.shown(first)).is_equal("Goldie")
	await Fp.click(self, first)
	assert_str(Fp.shown(Fp.label(controls, "FishNameLabel"))).is_equal("Goldie")
	var second: FishInstance = model.get_fish(uids[1])
	var expected: String = LabelRig.shown_text(second, self)
	assert_str(Fp.shown(Fp.name_button(controls, uids[1]))).is_equal(expected)
