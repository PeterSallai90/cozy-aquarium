extends GdUnitTestSuite
## The live switch: a running scene changes language without a restart, a reload or a model change.

const ModelState := preload("res://tests/helpers/model_state.gd")
const SaveFixtures := preload("res://tests/helpers/save_fixtures.gd")

const FIXTURE_EN := "res://tests/fixtures/localization/fixture_en.po"
const FIXTURE_HU := "res://tests/fixtures/localization/fixture_hu.po"
const PROBE := "res://tests/fixtures/localization/live_switch_probe.tscn"

const EN_TITLE := "English title"
const HU_TITLE := "Magyar cim"
const EN_COUNT := "3 apples"
const HU_COUNT := "3 alma (sok)"

var _dir: String = ""
var _saved_locale: String = ""
var _english: Translation
var _hungarian: Translation
var _signals: PackedStringArray = PackedStringArray()
var _probe_node: Control


func before_test() -> void:
	_dir = SaveFixtures.make_dir("live_switch")
	_saved_locale = TranslationServer.get_locale()
	_english = load(FIXTURE_EN) as Translation
	_hungarian = load(FIXTURE_HU) as Translation
	assert(_english != null and _hungarian != null, "fixture translations did not load")
	TranslationServer.add_translation(_english)
	TranslationServer.add_translation(_hungarian)
	_signals = PackedStringArray()


func after_test() -> void:
	# Free the probe first: with its labels still in the tree, removing the translations or
	# the locale change makes them re-translate and log "String formatting error".
	if is_instance_valid(_probe_node):
		if _probe_node.get_parent() != null:
			_probe_node.get_parent().remove_child(_probe_node)
		_probe_node.free()
	_probe_node = null
	TranslationServer.remove_translation(_english)
	TranslationServer.remove_translation(_hungarian)
	TranslationServer.set_locale(_saved_locale)
	SaveFixtures.remove_dir(_dir)
	SaveFixtures.remove_root_if_empty()


func _on_language_changed(language: String) -> void:
	_signals.append(language)


## A service on a temporary settings path that really switches the TranslationServer locale.
func _service() -> LanguageService:
	var store: SettingsStore = SettingsStore.new(_dir.path_join("settings.cfg"))
	var service: LanguageService = LanguageService.new(store)
	service.language_changed.connect(_on_language_changed)
	return service


func _probe() -> Control:
	var scene: PackedScene = load(PROBE) as PackedScene
	var probe: Control = scene.instantiate() as Control
	add_child(probe)
	_probe_node = probe
	return probe


func _title(probe: Control) -> Label:
	return probe.get_node("Title") as Label


func _count(probe: Control) -> Label:
	return probe.get_node("Count") as Label


func test_a_label_with_a_key_changes_language_in_the_same_session() -> void:
	var service: LanguageService = _service()
	service.start("en_US")
	var probe: Control = _probe()
	await get_tree().process_frame
	var title: Label = _title(probe)
	assert_str(title.text).is_equal("ui.fixture.title")
	assert_int(title.get_total_character_count()).is_equal(EN_TITLE.length())
	assert_str(title.atr(title.text)).is_equal(EN_TITLE)
	assert_int(service.set_language("hu")).is_equal(OK)
	await get_tree().process_frame
	assert_int(title.get_total_character_count()).is_equal(HU_TITLE.length())
	assert_str(title.atr(title.text)).is_equal(HU_TITLE)
	assert_str(title.text).override_failure_message("the key must stay in text").is_equal(
		"ui.fixture.title"
	)


func test_the_reverse_switch_works_too() -> void:
	var service: LanguageService = _service()
	service.start("hu_HU")
	var probe: Control = _probe()
	await get_tree().process_frame
	var title: Label = _title(probe)
	assert_int(title.get_total_character_count()).is_equal(HU_TITLE.length())
	assert_int(service.set_language("en")).is_equal(OK)
	await get_tree().process_frame
	assert_int(title.get_total_character_count()).is_equal(EN_TITLE.length())
	assert_str(title.atr(title.text)).is_equal(EN_TITLE)
	assert_int(service.set_language("hu")).is_equal(OK)
	await get_tree().process_frame
	assert_int(title.get_total_character_count()).is_equal(HU_TITLE.length())


func test_text_built_in_code_is_rebuilt_in_the_new_language() -> void:
	var service: LanguageService = _service()
	service.start("en_US")
	var probe: Control = _probe()
	await get_tree().process_frame
	var count: Label = _count(probe)
	assert_str(count.text).is_equal(EN_COUNT)
	var before: int = probe.refresh_count
	assert_int(service.set_language("hu")).is_equal(OK)
	await get_tree().process_frame
	assert_str(count.text).is_equal(HU_COUNT)
	assert_int(probe.refresh_count).is_greater(before)
	assert_int(service.set_language("en")).is_equal(OK)
	await get_tree().process_frame
	assert_str(count.text).is_equal(EN_COUNT)


func test_the_scene_and_the_model_are_kept_across_a_switch() -> void:
	var model: AquariumModel = SaveFixtures.populated_model()
	var before: Dictionary = ModelState.snapshot(model)
	var service: LanguageService = _service()
	service.start("en_US")
	var probe: Control = _probe()
	await get_tree().process_frame
	var probe_id: int = probe.get_instance_id()
	var title_id: int = _title(probe).get_instance_id()
	assert_int(service.set_language("hu")).is_equal(OK)
	await get_tree().process_frame
	assert_bool(probe.is_inside_tree()).is_true()
	assert_int(probe.get_instance_id()).is_equal(probe_id)
	assert_int(_title(probe).get_instance_id()).is_equal(title_id)
	assert_dict(ModelState.snapshot(model)).is_equal(before)


func test_the_signal_is_emitted_once_per_real_change() -> void:
	var service: LanguageService = _service()
	service.start("en_US")
	var probe: Control = _probe()
	await get_tree().process_frame
	assert_int(service.set_language("hu")).is_equal(OK)
	assert_int(service.set_language("hu")).is_equal(OK)
	await get_tree().process_frame
	assert_array(_signals).is_equal(["hu"])
	assert_str(_count(probe).text).is_equal(HU_COUNT)


func test_a_scene_added_after_the_switch_starts_in_the_new_language() -> void:
	var service: LanguageService = _service()
	service.start("en_US")
	assert_int(service.set_language("hu")).is_equal(OK)
	var probe: Control = _probe()
	await get_tree().process_frame
	assert_int(_title(probe).get_total_character_count()).is_equal(HU_TITLE.length())
	assert_str(_count(probe).text).is_equal(HU_COUNT)
