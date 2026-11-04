extends GdUnitTestSuite
## The Settings autoload: project wiring, the API, and the EventBus relay (AC 16). Writes only
## through fresh instances on a test path, never through the live /root/Settings.

const EngineOutput := preload("res://tests/helpers/engine_output.gd")
const SettingsRig := preload("res://tests/helpers/settings_rig.gd")
const SaveFixtures := preload("res://tests/helpers/save_fixtures.gd")

const AUTOLOAD_VALUE := "*res://systems/settings/settings.gd"

const NOT_SAVED := "Setting fixture/volume not saved: Can't open file"
const WRONG_TYPE := "Wrong type for setting fixture/volume"

var _dir: String = ""
var _saved_locale: String = ""
var _relayed: Array = []
var _languages: PackedStringArray = PackedStringArray()


func before_test() -> void:
	_dir = SaveFixtures.make_dir("settings_autoload")
	_saved_locale = TranslationServer.get_locale()
	_relayed = []
	_languages = PackedStringArray()


func after_test() -> void:
	var bus: Node = get_tree().root.get_node_or_null("EventBus")
	if bus != null and bus.has_signal("setting_changed"):
		if bus.is_connected("setting_changed", _on_setting_changed):
			bus.disconnect("setting_changed", _on_setting_changed)
	if EventBus.language_changed.is_connected(_on_language_changed):
		EventBus.language_changed.disconnect(_on_language_changed)
	TranslationServer.set_locale(_saved_locale)
	SaveFixtures.remove_dir(_dir)
	SaveFixtures.remove_root_if_empty()


## Runs action once, asserts exactly which messages it logged (each text and its count) and
## returns what the action returned.
func _logged(action: Callable, warnings: Dictionary = {}, errors: Dictionary = {}) -> Variant:
	var seen: Dictionary = await EngineOutput.capture_result(action)
	assert_dict(seen.warnings).is_equal(warnings)
	assert_dict(seen.errors).is_equal(errors)
	return seen.result


func _path() -> String:
	return _dir.path_join("settings.cfg")


func _on_setting_changed(section: String, key: String, value: Variant) -> void:
	_relayed.append([section, key, value])


func _on_language_changed(language: String) -> void:
	_languages.append(language)


func _listen() -> void:
	var bus: Node = get_tree().root.get_node_or_null("EventBus")
	assert_bool(bus.has_signal("setting_changed")).is_true()
	if bus.has_signal("setting_changed"):
		bus.connect("setting_changed", _on_setting_changed)
	EventBus.language_changed.connect(_on_language_changed)


func _make() -> Node:
	var node: Node = SettingsRig.make_settings(self, _path())
	(
		assert_object(node)
		. override_failure_message("Settings autoload script is missing")
		. is_not_null()
	)
	if node != null:
		auto_free(node)
	return node


# --- project wiring ---------------------------------------------------------------------


func test_the_autoload_is_registered() -> void:
	var setting: String = ProjectSettings.get_setting("autoload/Settings", "")
	assert_str(setting).is_equal(AUTOLOAD_VALUE)


func test_the_live_autoload_sits_after_localization_and_the_event_bus() -> void:
	var root: Node = get_tree().root
	var settings: Node = root.get_node_or_null("Settings")
	var localization: Node = root.get_node_or_null("Localization")
	var bus: Node = root.get_node_or_null("EventBus")
	assert_object(settings).is_not_null()
	if settings == null:
		return
	assert_int(settings.get_index()).is_greater(localization.get_index())
	assert_int(localization.get_index()).is_greater(bus.get_index())
	var script: Script = settings.get_script() as Script
	assert_str(script.resource_path).is_equal("res://systems/settings/settings.gd")


func test_the_live_autoload_has_the_api() -> void:
	var settings: Node = get_tree().root.get_node_or_null("Settings")
	assert_object(settings).is_not_null()
	if settings == null:
		return
	for method: String in ["get_value", "set_value", "get_last_save_error"]:
		assert_bool(settings.has_method(method)).override_failure_message(method).is_true()


func test_the_live_localization_reports_its_last_save_error() -> void:
	var localization: Node = get_tree().root.get_node_or_null("Localization")
	assert_object(localization).is_not_null()
	assert_bool(localization.has_method("get_last_save_error")).is_true()


func test_the_event_bus_signal_has_section_key_and_value() -> void:
	var bus: Node = get_tree().root.get_node_or_null("EventBus")
	assert_bool(bus.has_signal("setting_changed")).is_true()
	var parameters: Array = []
	for info: Dictionary in bus.get_signal_list():
		if info["name"] == "setting_changed":
			parameters = info["args"]
	assert_array(parameters).has_size(3)
	if parameters.size() != 3:
		return
	assert_str(parameters[0]["name"]).is_equal("section")
	assert_int(parameters[0]["type"]).is_equal(TYPE_STRING)
	assert_str(parameters[1]["name"]).is_equal("key")
	assert_int(parameters[1]["type"]).is_equal(TYPE_STRING)
	assert_str(parameters[2]["name"]).is_equal("value")
	assert_int(parameters[2]["type"]).is_equal(TYPE_NIL)


# --- startup ----------------------------------------------------------------------------


func test_startup_emits_nothing_and_writes_nothing() -> void:
	_listen()
	var node: Node = _make()
	if node == null:
		return
	assert_array(_relayed).is_empty()
	assert_bool(FileAccess.file_exists(_path())).is_false()
	assert_float(node.get_value(SettingsRig.volume_key())).is_equal(0.5)
	assert_bool(FileAccess.file_exists(_path())).is_false()
	assert_int(node.get_last_save_error()).is_equal(OK)


func test_a_stored_value_is_read_back() -> void:
	SaveFixtures.write_text(_path(), "[fixture]\nvolume=0.25\n")
	var node: Node = _make()
	if node == null:
		return
	assert_float(node.get_value(SettingsRig.volume_key())).is_equal(0.25)


# --- the relay --------------------------------------------------------------------------


func test_a_real_change_is_relayed_once_to_the_event_bus() -> void:
	_listen()
	var node: Node = _make()
	if node == null:
		return
	assert_int(node.set_value(SettingsRig.volume_key(), 0.8)).is_equal(OK)
	assert_array(_relayed).is_equal([["fixture", "volume", 0.8]])
	var config: ConfigFile = SettingsRig.read_config(_path())
	assert_float(config.get_value("fixture", "volume")).is_equal(0.8)


func test_the_same_value_again_is_not_relayed() -> void:
	_listen()
	var node: Node = _make()
	if node == null:
		return
	node.set_value(SettingsRig.volume_key(), 0.8)
	node.set_value(SettingsRig.volume_key(), 0.8)
	assert_array(_relayed).has_size(1)


func test_one_and_one_point_zero_are_the_same_value() -> void:
	_listen()
	var node: Node = _make()
	if node == null:
		return
	node.set_value(SettingsRig.volume_key(), 1.0)
	node.set_value(SettingsRig.volume_key(), 1)
	assert_array(_relayed).has_size(1)


func test_a_refused_value_is_not_relayed() -> void:
	_listen()
	var node: Node = _make()
	if node == null:
		return
	var result: Variant = await _logged(
		func() -> Variant: return node.set_value(SettingsRig.volume_key(), "loud"), {WRONG_TYPE: 1}
	)
	assert_int(result).is_equal(ERR_INVALID_PARAMETER)
	assert_array(_relayed).is_empty()


func test_a_language_change_does_not_use_the_setting_signal() -> void:
	_listen()
	var settings: Node = _make()
	var localization: Node = auto_free(SettingsRig.make_localization(self, _path(), "en_US"))
	if settings == null:
		return
	assert_int(localization.set_language("hu")).is_equal(OK)
	assert_array(_languages).is_equal(["hu"])
	assert_array(_relayed).is_empty()


func test_a_setting_change_does_not_emit_language_changed() -> void:
	_listen()
	var node: Node = _make()
	if node == null:
		return
	node.set_value(SettingsRig.volume_key(), 0.8)
	assert_array(_languages).is_empty()


func test_a_failed_write_still_applies_and_reports() -> void:
	DirAccess.make_dir_recursive_absolute(_path())
	_listen()
	var node: Node = _make()
	if node == null:
		return
	var result: Variant = await _logged(
		func() -> Variant: return node.set_value(SettingsRig.volume_key(), 0.8), {NOT_SAVED: 1}
	)
	assert_int(result).is_equal(OK)
	assert_float(node.get_value(SettingsRig.volume_key())).is_equal(0.8)
	assert_int(node.get_last_save_error()).is_not_equal(OK)
	assert_array(_relayed).is_equal([["fixture", "volume", 0.8]])
