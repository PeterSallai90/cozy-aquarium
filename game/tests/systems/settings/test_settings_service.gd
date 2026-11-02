# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## AC 11, 12, 14, 15, 16, 17 at the service level: fixture keys on a test path.

const SettingsRig := preload("res://tests/helpers/settings_rig.gd")
const SaveFixtures := preload("res://tests/helpers/save_fixtures.gd")

var _dir: String = ""
var _changes: Array = []


## A store that counts its writes.
class CountingStore:
	extends SettingsStore
	var writes: int = 0

	func write_value(section: String, key: String, value: Variant) -> Error:
		writes += 1
		return super.write_value(section, key, value)


func before_test() -> void:
	_dir = SaveFixtures.make_dir("settings_service")
	_changes = []


func after_test() -> void:
	SaveFixtures.remove_dir(_dir)
	SaveFixtures.remove_root_if_empty()


func _path() -> String:
	return _dir.path_join("settings.cfg")


func _on_changed(section: String, key: String, value: Variant) -> void:
	_changes.append([section, key, value])


func _make(store: SettingsStore = null) -> RefCounted:
	var service: RefCounted = SettingsRig.service(_path(), store)
	assert_object(service).override_failure_message("SettingsService is missing").is_not_null()
	if service != null:
		service.changed.connect(_on_changed)
	return service


# --- reading ----------------------------------------------------------------------------


func test_a_missing_file_gives_the_default_and_writes_nothing() -> void:
	var service: RefCounted = _make()
	if service == null:
		return
	assert_float(service.get_value(SettingsRig.volume_key())).is_equal(0.5)
	assert_bool(FileAccess.file_exists(_path())).is_false()
	assert_array(_changes).is_empty()
	assert_int(service.get_last_save_error()).is_equal(OK)


func test_a_stored_value_is_read() -> void:
	SaveFixtures.write_text(_path(), "[fixture]\nvolume=0.25\n")
	var service: RefCounted = _make()
	if service == null:
		return
	assert_float(service.get_value(SettingsRig.volume_key())).is_equal(0.25)


func test_a_wrong_type_reads_as_the_default_and_the_other_key_still_loads() -> void:
	var text: String = '[fixture]\nvolume="loud"\npan=0.25\n'
	SaveFixtures.write_text(_path(), text)
	var service: RefCounted = _make()
	if service == null:
		return
	assert_float(service.get_value(SettingsRig.volume_key())).is_equal(0.5)
	assert_float(service.get_value(SettingsRig.pan_key())).is_equal(0.25)
	assert_str(SaveFixtures.read_text(_path())).is_equal(text)
	assert_array(_changes).is_empty()


func test_an_out_of_range_value_reads_clamped_and_stays_on_disk() -> void:
	var text: String = "[fixture]\nvolume=7.5\npan=-4.0\n"
	SaveFixtures.write_text(_path(), text)
	var service: RefCounted = _make()
	if service == null:
		return
	assert_float(service.get_value(SettingsRig.volume_key())).is_equal(1.0)
	assert_float(service.get_value(SettingsRig.pan_key())).is_equal(-1.0)
	assert_str(SaveFixtures.read_text(_path())).is_equal(text)


func test_the_bad_value_stays_on_disk_until_the_key_next_changes() -> void:
	var text: String = '[fixture]\nvolume="loud"\npan=0.25\n'
	SaveFixtures.write_text(_path(), text)
	var service: RefCounted = _make()
	if service == null:
		return
	service.get_value(SettingsRig.volume_key())
	assert_str(SaveFixtures.read_text(_path())).is_equal(text)
	assert_int(service.set_value(SettingsRig.volume_key(), 0.8)).is_equal(OK)
	var config: ConfigFile = SettingsRig.read_config(_path())
	assert_float(config.get_value("fixture", "volume")).is_equal(0.8)
	assert_float(config.get_value("fixture", "pan")).is_equal(0.25)


func test_an_unparsable_file_gives_defaults_and_writes_nothing() -> void:
	var text: String = "this is [not valid\n=="
	SaveFixtures.write_text(_path(), text)
	var service: RefCounted = _make()
	if service == null:
		return
	assert_float(service.get_value(SettingsRig.volume_key())).is_equal(0.5)
	assert_str(SaveFixtures.read_text(_path())).is_equal(text)
	assert_array(SaveFixtures.listing(_dir)).is_equal(["settings.cfg"])


func test_the_first_change_after_an_unparsable_file_keeps_a_backup() -> void:
	var text: String = "this is [not valid\n=="
	SaveFixtures.write_text(_path(), text)
	var service: RefCounted = _make()
	if service == null:
		return
	assert_int(service.set_value(SettingsRig.volume_key(), 0.8)).is_equal(OK)
	assert_str(SaveFixtures.read_text(_path() + ".bak")).is_equal(text)
	var config: ConfigFile = SettingsRig.read_config(_path())
	assert_float(config.get_value("fixture", "volume")).is_equal(0.8)


# --- writing ----------------------------------------------------------------------------


func test_a_change_writes_only_its_key_and_keeps_everything_else() -> void:
	var seed_text: String = '[general]\nlanguage="hu"\nmystery="keep"\n\n[audio]\nmaster=0.5\n\n'
	seed_text += "[unknown]\nx=1\n"
	SaveFixtures.write_text(_path(), seed_text)
	var service: RefCounted = _make()
	if service == null:
		return
	assert_int(service.set_value(SettingsRig.volume_key(), 0.8)).is_equal(OK)
	var config: ConfigFile = SettingsRig.read_config(_path())
	assert_float(config.get_value("fixture", "volume")).is_equal(0.8)
	assert_str(config.get_value("general", "language")).is_equal("hu")
	assert_str(config.get_value("general", "mystery")).is_equal("keep")
	assert_float(config.get_value("audio", "master")).is_equal(0.5)
	assert_int(config.get_value("unknown", "x")).is_equal(1)
	assert_array(config.get_sections()).has_size(4)


func test_one_write_per_real_change_and_none_for_the_same_value() -> void:
	var store: CountingStore = CountingStore.new(_path())
	var service: RefCounted = _make(store)
	if service == null:
		return
	assert_int(service.set_value(SettingsRig.volume_key(), 0.8)).is_equal(OK)
	assert_int(store.writes).is_equal(1)
	assert_int(service.set_value(SettingsRig.volume_key(), 0.8)).is_equal(OK)
	assert_int(store.writes).is_equal(1)
	assert_int(service.set_value(SettingsRig.volume_key(), 0.3)).is_equal(OK)
	assert_int(store.writes).is_equal(2)


func test_reading_never_writes() -> void:
	var store: CountingStore = CountingStore.new(_path())
	var service: RefCounted = _make(store)
	if service == null:
		return
	service.get_value(SettingsRig.volume_key())
	service.get_value(SettingsRig.pan_key())
	assert_int(store.writes).is_equal(0)
	assert_bool(FileAccess.file_exists(_path())).is_false()


func test_a_value_set_is_served_back() -> void:
	var service: RefCounted = _make()
	if service == null:
		return
	service.set_value(SettingsRig.volume_key(), 0.8)
	assert_float(service.get_value(SettingsRig.volume_key())).is_equal(0.8)


func test_an_out_of_range_value_is_clamped_when_set() -> void:
	var service: RefCounted = _make()
	if service == null:
		return
	assert_int(service.set_value(SettingsRig.volume_key(), 5.0)).is_equal(OK)
	assert_float(service.get_value(SettingsRig.volume_key())).is_equal(1.0)
	var config: ConfigFile = SettingsRig.read_config(_path())
	assert_float(config.get_value("fixture", "volume")).is_equal(1.0)
	assert_array(_changes).is_equal([["fixture", "volume", 1.0]])


func test_a_wrong_type_is_refused_and_nothing_changes() -> void:
	var store: CountingStore = CountingStore.new(_path())
	var service: RefCounted = _make(store)
	if service == null:
		return
	for bad: Variant in ["loud", true, [0.2]]:
		(
			assert_int(service.set_value(SettingsRig.volume_key(), bad))
			. override_failure_message("for %s" % [bad])
			. is_equal(ERR_INVALID_PARAMETER)
		)
	assert_int(store.writes).is_equal(0)
	assert_array(_changes).is_empty()
	assert_float(service.get_value(SettingsRig.volume_key())).is_equal(0.5)


# --- the change signal (AC 16) ----------------------------------------------------------


func test_one_signal_per_real_change_with_section_key_and_value() -> void:
	var service: RefCounted = _make()
	if service == null:
		return
	service.set_value(SettingsRig.volume_key(), 0.8)
	assert_array(_changes).is_equal([["fixture", "volume", 0.8]])
	service.set_value(SettingsRig.volume_key(), 0.3)
	assert_array(_changes).has_size(2)
	assert_array(_changes[1]).is_equal(["fixture", "volume", 0.3])


func test_the_same_value_again_emits_nothing() -> void:
	var service: RefCounted = _make()
	if service == null:
		return
	service.set_value(SettingsRig.volume_key(), 0.8)
	service.set_value(SettingsRig.volume_key(), 0.8)
	assert_array(_changes).has_size(1)


func test_setting_the_default_value_while_unset_emits_nothing() -> void:
	var service: RefCounted = _make()
	if service == null:
		return
	service.set_value(SettingsRig.volume_key(), 0.5)
	assert_array(_changes).is_empty()
	assert_bool(FileAccess.file_exists(_path())).is_false()


func test_an_int_and_a_float_of_the_same_number_are_the_same_value() -> void:
	var service: RefCounted = _make()
	if service == null:
		return
	service.set_value(SettingsRig.volume_key(), 1.0)
	assert_array(_changes).has_size(1)
	service.set_value(SettingsRig.volume_key(), 1)
	assert_array(_changes).has_size(1)
	assert_int(typeof(service.get_value(SettingsRig.volume_key()))).is_equal(TYPE_FLOAT)


func test_reading_emits_nothing() -> void:
	SaveFixtures.write_text(_path(), '[fixture]\nvolume="loud"\n')
	var service: RefCounted = _make()
	if service == null:
		return
	service.get_value(SettingsRig.volume_key())
	assert_array(_changes).is_empty()


# --- a file that cannot be written (AC 17) ----------------------------------------------


func test_a_failed_write_keeps_the_value_for_the_session_and_reports_the_error() -> void:
	DirAccess.make_dir_recursive_absolute(_path())
	var service: RefCounted = _make()
	if service == null:
		return
	assert_int(service.set_value(SettingsRig.volume_key(), 0.8)).is_equal(OK)
	assert_float(service.get_value(SettingsRig.volume_key())).is_equal(0.8)
	assert_int(service.get_last_save_error()).is_not_equal(OK)
	assert_array(_changes).is_equal([["fixture", "volume", 0.8]])


func test_a_good_write_after_a_failed_one_clears_the_error() -> void:
	DirAccess.make_dir_recursive_absolute(_path())
	var service: RefCounted = _make()
	if service == null:
		return
	service.set_value(SettingsRig.volume_key(), 0.8)
	assert_int(service.get_last_save_error()).is_not_equal(OK)
	DirAccess.remove_absolute(_path())
	assert_int(service.set_value(SettingsRig.volume_key(), 0.3)).is_equal(OK)
	assert_int(service.get_last_save_error()).is_equal(OK)
	var config: ConfigFile = SettingsRig.read_config(_path())
	assert_float(config.get_value("fixture", "volume")).is_equal(0.3)
