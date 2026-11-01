# gdlint: disable=max-public-methods
extends GdUnitTestSuite

const ModelState := preload("res://tests/helpers/model_state.gd")
const SaveFixtures := preload("res://tests/helpers/save_fixtures.gd")

var _dir: String = ""
var _locale_calls: PackedStringArray = PackedStringArray()
var _timeline: PackedStringArray = PackedStringArray()
var _signals: PackedStringArray = PackedStringArray()
var _saved_locale: String = ""


func before_test() -> void:
	_dir = SaveFixtures.make_dir("language_service")
	_locale_calls = PackedStringArray()
	_timeline = PackedStringArray()
	_signals = PackedStringArray()
	_saved_locale = TranslationServer.get_locale()


func after_test() -> void:
	TranslationServer.set_locale(_saved_locale)
	SaveFixtures.remove_dir(_dir)
	SaveFixtures.remove_root_if_empty()


func _path(file_name: String = "settings.cfg") -> String:
	return _dir.path_join(file_name)


func _record_locale(code: String) -> void:
	_locale_calls.append(code)
	_timeline.append("locale:" + code)


func _record_signal(code: String) -> void:
	_signals.append(code)
	_timeline.append("signal:" + code)


## A service on the test path whose locale calls are recorded and whose signal is recorded too.
func _service(path: String = "") -> LanguageService:
	var store: SettingsStore = SettingsStore.new(path if not path.is_empty() else _path())
	var service: LanguageService = LanguageService.new(store, _record_locale)
	service.language_changed.connect(_record_signal)
	return service


func _stored_language(path: String = "") -> Variant:
	var config: ConfigFile = ConfigFile.new()
	var error: Error = config.load(path if not path.is_empty() else _path())
	if error != OK:
		return null
	return config.get_value("general", "language", null)


# --- start: stored value, OS locale ------------------------------------------------------


func test_a_stored_language_wins_over_the_os_locale() -> void:
	SaveFixtures.write_text(_path(), '[general]\nlanguage="hu"\n')
	var service: LanguageService = _service()
	service.start("en_US")
	assert_str(service.get_language()).is_equal("hu")
	assert_array(_locale_calls).is_equal(["hu"])


func test_a_stored_english_wins_over_a_hungarian_os_locale() -> void:
	SaveFixtures.write_text(_path(), '[general]\nlanguage="en"\n')
	var service: LanguageService = _service()
	service.start("hu_HU")
	assert_str(service.get_language()).is_equal("en")


func test_first_start_follows_the_os_locale() -> void:
	for locale: String in ["hu", "HU", "hu_HU", "hu-HU", "hu_Latn_HU"]:
		var service: LanguageService = _service()
		service.start(locale)
		assert_str(service.get_language()).override_failure_message(locale).is_equal("hu")
	for locale: String in ["en", "en_US", "de_DE", "x", ""]:
		var service: LanguageService = _service()
		service.start(locale)
		assert_str(service.get_language()).override_failure_message(locale).is_equal("en")


func test_a_bad_stored_value_behaves_like_a_first_start() -> void:
	for raw: String in ['"xx"', '""', "42", "true", '"HU"', "1.5"]:
		SaveFixtures.write_text(_path(), "[general]\nlanguage=%s\n" % raw)
		var hungarian: LanguageService = _service()
		hungarian.start("hu_HU")
		assert_str(hungarian.get_language()).override_failure_message(raw).is_equal("hu")
		var other: LanguageService = _service()
		other.start("de_DE")
		assert_str(other.get_language()).override_failure_message(raw).is_equal("en")


func test_a_bad_stored_value_stays_on_disk_and_nothing_is_written_at_startup() -> void:
	var text: String = '[audio]\nvolume=0.5\n\n[general]\nlanguage="xx"\n'
	SaveFixtures.write_text(_path(), text)
	var service: LanguageService = _service()
	service.start("hu_HU")
	assert_str(SaveFixtures.read_text(_path())).is_equal(text)
	assert_array(SaveFixtures.listing(_dir)).is_equal(["settings.cfg"])


func test_a_damaged_file_behaves_like_a_first_start_and_is_left_alone() -> void:
	var text: String = '[general\nlanguage="en"\n'
	SaveFixtures.write_text(_path(), text)
	var hungarian: LanguageService = _service()
	hungarian.start("hu_HU")
	assert_str(hungarian.get_language()).is_equal("hu")
	var other: LanguageService = _service()
	other.start("de_DE")
	assert_str(other.get_language()).is_equal("en")
	assert_str(SaveFixtures.read_text(_path())).is_equal(text)
	assert_array(SaveFixtures.listing(_dir)).is_equal(["settings.cfg"])


func test_a_missing_file_is_not_created_at_startup() -> void:
	var service: LanguageService = _service()
	service.start("hu_HU")
	assert_bool(FileAccess.file_exists(_path())).is_false()
	assert_array(SaveFixtures.listing(_dir)).is_empty()


func test_start_applies_the_locale_once_and_emits_nothing() -> void:
	var service: LanguageService = _service()
	service.start("hu_HU")
	assert_array(_locale_calls).is_equal(["hu"])
	assert_array(_signals).is_empty()
	assert_array(_timeline).is_equal(["locale:hu"])


func test_start_without_an_injected_callable_sets_the_translation_server_locale() -> void:
	var service: LanguageService = LanguageService.new(SettingsStore.new(_path()))
	service.start("hu_HU")
	assert_str(TranslationServer.get_locale()).starts_with("hu")
	var english: LanguageService = LanguageService.new(SettingsStore.new(_path()))
	english.start("en_US")
	assert_str(TranslationServer.get_locale()).starts_with("en")


# --- set_language ------------------------------------------------------------------------


func test_set_language_switches_saves_and_emits_once_after_the_locale() -> void:
	var service: LanguageService = _service()
	service.start("en_US")
	_timeline = PackedStringArray()
	_locale_calls = PackedStringArray()
	assert_int(service.set_language("hu")).is_equal(OK)
	assert_str(service.get_language()).is_equal("hu")
	assert_array(_timeline).is_equal(["locale:hu", "signal:hu"])
	assert_array(_signals).is_equal(["hu"])
	assert_str(_stored_language()).is_equal("hu")


func test_the_choice_is_saved_in_the_general_section_under_language() -> void:
	var service: LanguageService = _service()
	service.start("en_US")
	assert_int(service.set_language("hu")).is_equal(OK)
	var config: ConfigFile = ConfigFile.new()
	assert_int(config.load(_path())).is_equal(OK)
	assert_array(config.get_sections()).is_equal(["general"])
	assert_array(config.get_section_keys("general")).is_equal(["language"])
	assert_str(config.get_value("general", "language")).is_equal("hu")


func test_a_restart_reads_the_saved_language_back() -> void:
	var first: LanguageService = _service()
	first.start("en_US")
	assert_int(first.set_language("hu")).is_equal(OK)
	var restarted: LanguageService = _service()
	restarted.start("de_DE")
	assert_str(restarted.get_language()).is_equal("hu")
	assert_int(restarted.set_language("en")).is_equal(OK)
	var third: LanguageService = _service()
	third.start("hu_HU")
	assert_str(third.get_language()).is_equal("en")


func test_every_real_change_emits_once_in_both_directions() -> void:
	var service: LanguageService = _service()
	service.start("en_US")
	assert_int(service.set_language("hu")).is_equal(OK)
	assert_int(service.set_language("en")).is_equal(OK)
	assert_int(service.set_language("hu")).is_equal(OK)
	assert_array(_signals).is_equal(["hu", "en", "hu"])
	assert_str(_stored_language()).is_equal("hu")


func test_the_same_language_again_is_ok_without_signal_locale_call_or_write() -> void:
	var service: LanguageService = _service()
	service.start("en_US")
	_locale_calls = PackedStringArray()
	assert_int(service.set_language("en")).is_equal(OK)
	assert_array(_signals).is_empty()
	assert_array(_locale_calls).is_empty()
	assert_bool(FileAccess.file_exists(_path())).is_false()
	assert_int(service.set_language("hu")).is_equal(OK)
	assert_bool(FileAccess.file_exists(_path())).is_true()
	DirAccess.remove_absolute(_path())
	_signals = PackedStringArray()
	_locale_calls = PackedStringArray()
	assert_int(service.set_language("hu")).is_equal(OK)
	assert_array(_signals).is_empty()
	assert_array(_locale_calls).is_empty()
	(
		assert_bool(FileAccess.file_exists(_path()))
		. override_failure_message("the file came back after setting the same language")
		. is_false()
	)


func test_an_unsupported_code_is_refused_and_changes_nothing() -> void:
	var service: LanguageService = _service()
	service.start("hu_HU")
	_locale_calls = PackedStringArray()
	for code: String in ["xx", "", "HU", "EN", "hu_HU", " hu", "magyar"]:
		(
			assert_int(service.set_language(code))
			. override_failure_message("set_language(%s)" % code)
			. is_equal(ERR_INVALID_PARAMETER)
		)
	assert_str(service.get_language()).is_equal("hu")
	assert_array(_locale_calls).is_empty()
	assert_array(_signals).is_empty()
	assert_bool(FileAccess.file_exists(_path())).is_false()


func test_an_unsupported_code_does_not_touch_an_existing_file() -> void:
	var text: String = '[general]\nlanguage="en"\n'
	SaveFixtures.write_text(_path(), text)
	var service: LanguageService = _service()
	service.start("de_DE")
	assert_int(service.set_language("xx")).is_equal(ERR_INVALID_PARAMETER)
	assert_str(SaveFixtures.read_text(_path())).is_equal(text)


func test_other_sections_survive_a_language_change() -> void:
	SaveFixtures.write_text(_path(), "[audio]\nvolume=0.5\n")
	var service: LanguageService = _service()
	service.start("en_US")
	assert_int(service.set_language("hu")).is_equal(OK)
	var config: ConfigFile = ConfigFile.new()
	assert_int(config.load(_path())).is_equal(OK)
	assert_float(config.get_value("audio", "volume")).is_equal(0.5)
	assert_str(config.get_value("general", "language")).is_equal("hu")


func test_a_damaged_file_is_backed_up_when_the_player_sets_a_language() -> void:
	var text: String = '[general\nlanguage="en"\n'
	SaveFixtures.write_text(_path(), text)
	var service: LanguageService = _service()
	service.start("de_DE")
	assert_int(service.set_language("hu")).is_equal(OK)
	assert_str(SaveFixtures.read_text(_path() + ".bak")).is_equal(text)
	assert_str(_stored_language()).is_equal("hu")


# --- a failing write ---------------------------------------------------------------------


func test_a_failed_write_still_switches_returns_ok_and_emits() -> void:
	DirAccess.make_dir_recursive_absolute(_path())
	var service: LanguageService = _service()
	service.start("en_US")
	_timeline = PackedStringArray()
	assert_int(service.set_language("hu")).is_equal(OK)
	assert_str(service.get_language()).is_equal("hu")
	assert_array(_timeline).is_equal(["locale:hu", "signal:hu"])
	assert_bool(DirAccess.dir_exists_absolute(_path())).is_true()


func test_a_failed_write_does_not_stop_later_changes() -> void:
	DirAccess.make_dir_recursive_absolute(_path())
	var service: LanguageService = _service()
	service.start("en_US")
	assert_int(service.set_language("hu")).is_equal(OK)
	assert_int(service.set_language("en")).is_equal(OK)
	assert_str(service.get_language()).is_equal("en")
	assert_array(_signals).is_equal(["hu", "en"])


# --- saving never touches save files or the model ----------------------------------------


func test_a_language_change_leaves_save_files_and_the_model_alone() -> void:
	var model: AquariumModel = SaveFixtures.populated_model()
	var history: CommandHistory = CommandHistory.new()
	var clock: Callable = func() -> String: return SaveFixtures.NOW
	var save_path: String = _path("tank.json")
	assert_int(SaveStore.new(clock).save(model, save_path).kind).is_equal(SaveResult.Kind.OK)
	var saved_bytes: PackedByteArray = SaveFixtures.read_bytes(save_path)
	# Saving stamps the model, so the snapshot is taken after it.
	var before: Dictionary = ModelState.snapshot(model)
	var service: LanguageService = _service()
	service.start("en_US")
	assert_int(service.set_language("hu")).is_equal(OK)
	assert_int(service.set_language("en")).is_equal(OK)
	assert_array(SaveFixtures.read_bytes(save_path)).is_equal(saved_bytes)
	assert_dict(ModelState.snapshot(model)).is_equal(before)
	assert_int(history.get_undo_count()).is_equal(0)
	assert_array(SaveFixtures.listing(_dir)).is_equal(["settings.cfg", "tank.json"])
