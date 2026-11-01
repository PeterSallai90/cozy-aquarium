# gdlint: disable=max-public-methods
extends GdUnitTestSuite

const SaveFixtures := preload("res://tests/helpers/save_fixtures.gd")

var _dir: String = ""


func before_test() -> void:
	_dir = SaveFixtures.make_dir("settings_store")


func after_test() -> void:
	SaveFixtures.remove_dir(_dir)
	SaveFixtures.remove_root_if_empty()


func _path(file_name: String = "settings.cfg") -> String:
	return _dir.path_join(file_name)


func _config(path: String) -> ConfigFile:
	var config: ConfigFile = ConfigFile.new()
	var error: Error = config.load(path)
	assert(error == OK, "test file %s does not parse" % path)
	return config


# --- constants ---------------------------------------------------------------------------


func test_the_default_path_and_the_language_entry_names() -> void:
	assert_str(SettingsStore.DEFAULT_PATH).is_equal("user://settings.cfg")
	assert_str(SettingsStore.SECTION_GENERAL).is_equal("general")
	assert_str(SettingsStore.KEY_LANGUAGE).is_equal("language")
	assert_str(SettingsStore.BACKUP_SUFFIX).is_equal(".bak")


func test_the_injected_path_is_kept() -> void:
	assert_str(SettingsStore.new(_path("x.cfg")).get_path()).is_equal(_path("x.cfg"))
	assert_str(SettingsStore.new().get_path()).is_equal("user://settings.cfg")


# --- reading -----------------------------------------------------------------------------


func test_a_missing_file_reads_the_default_and_is_not_created() -> void:
	var store: SettingsStore = SettingsStore.new(_path())
	assert_object(store.read_value("general", "language")).is_null()
	assert_str(store.read_value("general", "language", "en")).is_equal("en")
	assert_bool(FileAccess.file_exists(_path())).is_false()
	assert_array(SaveFixtures.listing(_dir)).is_empty()


func test_reading_never_creates_folders() -> void:
	var store: SettingsStore = SettingsStore.new(_path("nested/deeper/settings.cfg"))
	assert_str(store.read_value("general", "language", "en")).is_equal("en")
	assert_bool(DirAccess.dir_exists_absolute(_path("nested"))).is_false()


func test_a_missing_section_or_key_reads_the_default() -> void:
	SaveFixtures.write_text(_path(), '[audio]\nvolume=0.5\n\n[general]\nother="x"\n')
	var store: SettingsStore = SettingsStore.new(_path())
	assert_str(store.read_value("general", "language", "en")).is_equal("en")
	assert_str(store.read_value("graphics", "quality", "mid")).is_equal("mid")
	assert_str(store.read_value("general", "other", "")).is_equal("x")


func test_values_keep_their_types() -> void:
	SaveFixtures.write_text(_path(), '[general]\nlanguage="hu"\ncount=42\nratio=0.25\nflag=true\n')
	var store: SettingsStore = SettingsStore.new(_path())
	assert_str(store.read_value("general", "language")).is_equal("hu")
	assert_int(store.read_value("general", "count")).is_equal(42)
	assert_float(store.read_value("general", "ratio")).is_equal(0.25)
	assert_bool(store.read_value("general", "flag")).is_true()


func test_every_read_loads_the_file_again() -> void:
	var store: SettingsStore = SettingsStore.new(_path())
	assert_str(store.read_value("general", "language", "none")).is_equal("none")
	SaveFixtures.write_text(_path(), '[general]\nlanguage="hu"\n')
	assert_str(store.read_value("general", "language", "none")).is_equal("hu")
	SaveFixtures.write_text(_path(), '[general]\nlanguage="en"\n')
	assert_str(store.read_value("general", "language", "none")).is_equal("en")


func test_a_damaged_file_reads_the_default_and_stays_as_it_is() -> void:
	for text: String in ['[general\nlanguage="hu"\n', "[general]\nlanguage=hu\n"]:
		SaveFixtures.write_text(_path(), text)
		var store: SettingsStore = SettingsStore.new(_path())
		assert_str(store.read_value("general", "language", "en")).is_equal("en")
		assert_str(SaveFixtures.read_text(_path())).is_equal(text)
		assert_bool(FileAccess.file_exists(_path() + ".bak")).is_false()


func test_a_path_that_is_a_folder_reads_the_default() -> void:
	DirAccess.make_dir_recursive_absolute(_path())
	var store: SettingsStore = SettingsStore.new(_path())
	assert_str(store.read_value("general", "language", "en")).is_equal("en")


# --- writing -----------------------------------------------------------------------------


func test_the_first_write_creates_exactly_the_language_entry() -> void:
	var store: SettingsStore = SettingsStore.new(_path())
	assert_int(store.write_value("general", "language", "hu")).is_equal(OK)
	var config: ConfigFile = _config(_path())
	assert_array(config.get_sections()).is_equal(["general"])
	assert_array(config.get_section_keys("general")).is_equal(["language"])
	assert_str(config.get_value("general", "language")).is_equal("hu")
	assert_str(store.read_value("general", "language")).is_equal("hu")


func test_the_file_is_utf8_with_lf_endings_and_no_bom() -> void:
	var store: SettingsStore = SettingsStore.new(_path())
	assert_int(store.write_value("general", "language", "hu")).is_equal(OK)
	var bytes: PackedByteArray = SaveFixtures.read_bytes(_path())
	var bom: PackedByteArray = PackedByteArray([0xEF, 0xBB, 0xBF])
	assert_bool(bytes.slice(0, 3) == bom).is_false()
	assert_bool(bytes.has(13)).is_false()
	assert_str(SaveFixtures.read_text(_path())).contains('language="hu"')


func test_other_sections_and_keys_survive_a_write() -> void:
	SaveFixtures.write_text(
		_path(), '[audio]\nvolume=0.5\nmuted=false\n\n[general]\nother="x"\nlanguage="en"\n'
	)
	var store: SettingsStore = SettingsStore.new(_path())
	assert_int(store.write_value("general", "language", "hu")).is_equal(OK)
	var config: ConfigFile = _config(_path())
	assert_array(config.get_sections()).contains_exactly_in_any_order(["audio", "general"])
	assert_float(config.get_value("audio", "volume")).is_equal(0.5)
	assert_bool(config.get_value("audio", "muted")).is_false()
	assert_str(config.get_value("general", "other")).is_equal("x")
	assert_str(config.get_value("general", "language")).is_equal("hu")
	assert_array(config.get_section_keys("general")).contains_exactly_in_any_order(
		["other", "language"]
	)


func test_exactly_one_key_changes_per_write() -> void:
	SaveFixtures.write_text(_path(), '[general]\nlanguage="en"\nother=7\n\n[audio]\nvolume=0.5\n')
	var before: ConfigFile = _config(_path())
	var store: SettingsStore = SettingsStore.new(_path())
	assert_int(store.write_value("general", "language", "hu")).is_equal(OK)
	var after: ConfigFile = _config(_path())
	for section: String in before.get_sections():
		for key: String in before.get_section_keys(section):
			if section == "general" and key == "language":
				continue
			assert_bool(after.get_value(section, key) == before.get_value(section, key)).is_true()
	assert_str(after.get_value("general", "language")).is_equal("hu")


func test_a_key_added_to_the_file_between_two_writes_survives() -> void:
	var store: SettingsStore = SettingsStore.new(_path())
	assert_int(store.write_value("general", "language", "hu")).is_equal(OK)
	var edited: ConfigFile = _config(_path())
	edited.set_value("audio", "volume", 0.25)
	assert_int(edited.save(_path())).is_equal(OK)
	assert_int(store.write_value("general", "language", "en")).is_equal(OK)
	var config: ConfigFile = _config(_path())
	assert_float(config.get_value("audio", "volume")).is_equal(0.25)
	assert_str(config.get_value("general", "language")).is_equal("en")


func test_values_of_other_types_can_be_written() -> void:
	var store: SettingsStore = SettingsStore.new(_path())
	assert_int(store.write_value("audio", "volume", 0.75)).is_equal(OK)
	assert_int(store.write_value("audio", "steps", 3)).is_equal(OK)
	assert_int(store.write_value("audio", "muted", true)).is_equal(OK)
	assert_float(store.read_value("audio", "volume")).is_equal(0.75)
	assert_int(store.read_value("audio", "steps")).is_equal(3)
	assert_bool(store.read_value("audio", "muted")).is_true()


func test_no_temporary_file_remains_and_no_backup_for_a_valid_file() -> void:
	var store: SettingsStore = SettingsStore.new(_path())
	assert_int(store.write_value("general", "language", "hu")).is_equal(OK)
	assert_int(store.write_value("general", "language", "en")).is_equal(OK)
	assert_array(SaveFixtures.listing(_dir)).is_equal(["settings.cfg"])


func test_a_write_only_touches_its_own_file() -> void:
	SaveFixtures.write_text(_path("tank.json"), '{"format_version": 1}\n')
	var store: SettingsStore = SettingsStore.new(_path())
	assert_int(store.write_value("general", "language", "hu")).is_equal(OK)
	assert_str(SaveFixtures.read_text(_path("tank.json"))).is_equal('{"format_version": 1}\n')
	assert_array(SaveFixtures.listing(_dir)).is_equal(["settings.cfg", "tank.json"])


# --- damaged files -----------------------------------------------------------------------


func test_writing_over_a_damaged_file_keeps_a_backup_and_writes_a_fresh_file() -> void:
	for text: String in ['[general\nlanguage="hu"\n', "[general]\nlanguage=hu\n"]:
		SaveFixtures.write_text(_path(), text)
		var store: SettingsStore = SettingsStore.new(_path())
		assert_int(store.write_value("general", "language", "en")).is_equal(OK)
		assert_str(SaveFixtures.read_text(_path() + ".bak")).is_equal(text)
		var config: ConfigFile = _config(_path())
		assert_array(config.get_sections()).is_equal(["general"])
		assert_array(config.get_section_keys("general")).is_equal(["language"])
		assert_str(config.get_value("general", "language")).is_equal("en")
		assert_array(SaveFixtures.listing(_dir)).is_equal(["settings.cfg", "settings.cfg.bak"])
		SaveFixtures.remove_dir(_dir)
		_dir = SaveFixtures.make_dir("settings_store")


func test_a_newer_damaged_file_replaces_an_older_backup() -> void:
	var store: SettingsStore = SettingsStore.new(_path())
	SaveFixtures.write_text(_path(), "[general\nfirst=1\n")
	assert_int(store.write_value("general", "language", "hu")).is_equal(OK)
	SaveFixtures.write_text(_path(), "[general\nsecond=2\n")
	assert_int(store.write_value("general", "language", "en")).is_equal(OK)
	assert_str(SaveFixtures.read_text(_path() + ".bak")).is_equal("[general\nsecond=2\n")
	assert_str(_config(_path()).get_value("general", "language")).is_equal("en")


func test_a_valid_file_never_gets_a_backup() -> void:
	SaveFixtures.write_text(_path(), '[general]\nlanguage="en"\n')
	var store: SettingsStore = SettingsStore.new(_path())
	assert_int(store.write_value("general", "language", "hu")).is_equal(OK)
	assert_bool(FileAccess.file_exists(_path() + ".bak")).is_false()


# --- failures ----------------------------------------------------------------------------


func test_a_write_to_a_path_that_is_a_folder_fails_without_a_crash() -> void:
	DirAccess.make_dir_recursive_absolute(_path())
	var store: SettingsStore = SettingsStore.new(_path())
	assert_int(store.write_value("general", "language", "hu")).is_not_equal(OK)
	assert_bool(DirAccess.dir_exists_absolute(_path())).is_true()
	assert_bool(FileAccess.file_exists(_path() + ".tmp")).is_false()


func test_a_path_outside_user_is_refused() -> void:
	var outside: String = "res://tests/fixtures/localization/never_written_settings.cfg"
	var store: SettingsStore = SettingsStore.new(outside)
	assert_int(store.write_value("general", "language", "hu")).is_equal(ERR_FILE_BAD_PATH)
	assert_bool(FileAccess.file_exists(outside)).is_false()


func test_paths_that_are_not_a_file_inside_user_are_refused() -> void:
	for path: String in ["user://a/../b.cfg", "user://", "user://folder/"]:
		var store: SettingsStore = SettingsStore.new(path)
		(
			assert_int(store.write_value("general", "language", "hu"))
			. override_failure_message(path)
			. is_equal(ERR_FILE_BAD_PATH)
		)
