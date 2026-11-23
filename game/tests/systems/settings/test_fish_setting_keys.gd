extends GdUnitTestSuite
## #164 AC "Settings" (owner: tester): FishSettingKeys.show_names() is the [fish] show_names key,
## a bool with default false (ADR 0003 rule 1). Through a Settings instance on a test path: no
## file gives false, a missing key, a wrong type or a damaged file give false, the same value
## twice emits one setting_changed, a fresh instance on the same path reads the saved value, and
## the file holds [fish] show_names. Never touches the live /root/Settings.

const SettingsRig := preload("res://tests/helpers/settings_rig.gd")
const LabelRig := preload("res://tests/helpers/fish_label_rig.gd")
const SaveFixtures := preload("res://tests/helpers/save_fixtures.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")

var _dir: String = ""
var _seen: Array = []


func before_test() -> void:
	_dir = SaveFixtures.make_dir("fish_setting_keys")
	_seen = []


func after_test() -> void:
	SaveFixtures.remove_dir(_dir)
	SaveFixtures.remove_root_if_empty()


func _path() -> String:
	return _dir.path_join("settings.cfg")


func _on_changed(section: String, key: String, value: Variant) -> void:
	if section == "fish" and key == "show_names":
		_seen.append(value)


func _key() -> SettingKey:
	var key: SettingKey = LabelRig.key() as SettingKey
	(
		assert_object(key)
		. override_failure_message("FishSettingKeys.show_names() is missing")
		. is_not_null()
	)
	return key


func test_the_key_is_fish_show_names_a_bool_defaulting_to_false() -> void:
	var key: SettingKey = _key()
	if key == null:
		return
	assert_str(key.section).is_equal("fish")
	assert_str(key.key).is_equal("show_names")
	assert_int(key.value_type).is_equal(TYPE_BOOL)
	assert_bool(key.default_value).is_false()
	assert_str(key.id()).is_equal("fish/show_names")


func test_with_no_settings_file_the_value_is_false() -> void:
	var key: SettingKey = _key()
	var settings: Node = auto_free(SettingsRig.make_settings(self, _path()))
	if key == null or settings == null:
		return
	assert_bool(settings.get_value(key)).is_false()
	assert_array(SaveFixtures.listing(_dir)).is_empty()


func test_a_missing_key_a_wrong_type_and_a_damaged_file_give_false() -> void:
	var key: SettingKey = _key()
	if key == null:
		return
	SaveFixtures.write_text(_path(), '[general]\nlanguage = "en"\n')
	var missing: Node = auto_free(SettingsRig.make_settings(self, _path()))
	assert_bool(missing.get_value(key)).is_false()
	SaveFixtures.write_text(_path(), '[fish]\nshow_names = "yes"\n')
	var wrong: Node = auto_free(SettingsRig.make_settings(self, _path()))
	assert_bool(wrong.get_value(key)).is_false()
	SaveFixtures.write_text(_path(), "this is [not valid\n==")
	var holder: Array = []
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void:
			var damaged: Node = auto_free(SettingsRig.make_settings(self, _path()))
			holder.append(damaged.get_value(key))
	)
	assert_bool(holder[0]).is_false()
	for message: String in seen["errors"]:
		assert_str(message).starts_with("ConfigFile parse error")


func test_a_value_written_survives_a_restart_and_the_file_holds_the_section() -> void:
	var key: SettingKey = _key()
	if key == null:
		return
	var first: Node = auto_free(SettingsRig.make_settings(self, _path()))
	assert_int(first.set_value(key, true)).is_equal(OK)
	var second: Node = auto_free(SettingsRig.make_settings(self, _path()))
	assert_bool(second.get_value(key)).is_true()
	var config: ConfigFile = SettingsRig.read_config(_path())
	assert_bool(config.get_value("fish", "show_names", false)).is_true()


func test_setting_the_same_value_again_emits_setting_changed_only_once() -> void:
	var key: SettingKey = _key()
	if key == null:
		return
	var settings: Node = auto_free(SettingsRig.make_settings(self, _path()))
	EventBus.setting_changed.connect(_on_changed)
	settings.set_value(key, true)
	settings.set_value(key, true)
	assert_array(_seen).is_equal([true])
	settings.set_value(key, false)
	settings.set_value(key, false)
	EventBus.setting_changed.disconnect(_on_changed)
	assert_array(_seen).is_equal([true, false])


func test_setting_the_default_on_a_fresh_install_emits_nothing() -> void:
	var key: SettingKey = _key()
	if key == null:
		return
	var settings: Node = auto_free(SettingsRig.make_settings(self, _path()))
	EventBus.setting_changed.connect(_on_changed)
	settings.set_value(key, false)
	EventBus.setting_changed.disconnect(_on_changed)
	assert_array(_seen).is_empty()
