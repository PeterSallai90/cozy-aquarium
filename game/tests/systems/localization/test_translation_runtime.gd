extends GdUnitTestSuite
## Missing keys, fallback and plurals through the TranslationServer, with the test-only fixture
## translations (never shipped). The fixtures are loaded in before_test and removed in after_test.

const FIXTURE_EN := "res://tests/fixtures/localization/fixture_en.po"
const FIXTURE_HU := "res://tests/fixtures/localization/fixture_hu.po"
const APPLES := "ui.fixture.apples"
const APPLES_PLURAL := "ui.fixture.apples.plural"

var _saved_locale: String = ""
var _english: Translation
var _hungarian: Translation


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()
	_english = load(FIXTURE_EN) as Translation
	_hungarian = load(FIXTURE_HU) as Translation
	assert(_english != null and _hungarian != null, "fixture translations did not load")
	TranslationServer.add_translation(_english)
	TranslationServer.add_translation(_hungarian)


func after_test() -> void:
	TranslationServer.remove_translation(_english)
	TranslationServer.remove_translation(_hungarian)
	TranslationServer.set_locale(_saved_locale)


func _apples(count: int) -> String:
	return tr_n(APPLES, APPLES_PLURAL, count) % count


# --- missing keys ------------------------------------------------------------------------


func test_a_key_in_neither_file_returns_the_key_in_english() -> void:
	TranslationServer.set_locale("en")
	assert_str(tr("ui.fixture.nowhere")).is_equal("ui.fixture.nowhere")


func test_a_key_in_neither_file_returns_the_key_in_hungarian() -> void:
	TranslationServer.set_locale("hu")
	assert_str(tr("ui.fixture.nowhere")).is_equal("ui.fixture.nowhere")


func test_the_fixture_translations_are_found_per_language() -> void:
	TranslationServer.set_locale("en")
	assert_str(tr("ui.fixture.title")).is_equal("English title")
	TranslationServer.set_locale("hu")
	assert_str(tr("ui.fixture.title")).is_equal("Magyar cim")


func test_a_key_missing_in_hungarian_shows_the_english_text() -> void:
	TranslationServer.set_locale("hu")
	assert_str(tr("ui.fixture.only_en")).is_equal("Only in English")


func test_a_key_with_an_empty_hungarian_text_shows_the_english_text() -> void:
	TranslationServer.set_locale("hu")
	assert_str(tr("ui.fixture.empty_hu")).is_equal("English fallback text")


func test_the_english_text_of_the_fallback_keys_is_shown_in_english_too() -> void:
	TranslationServer.set_locale("en")
	assert_str(tr("ui.fixture.only_en")).is_equal("Only in English")
	assert_str(tr("ui.fixture.empty_hu")).is_equal("English fallback text")


func test_the_fixture_keys_are_not_in_the_shipped_translations() -> void:
	TranslationServer.remove_translation(_english)
	TranslationServer.remove_translation(_hungarian)
	for locale: String in ["en", "hu"]:
		TranslationServer.set_locale(locale)
		assert_str(tr("ui.fixture.title")).is_equal("ui.fixture.title")
		assert_str(tr("ui.fixture.only_en")).is_equal("ui.fixture.only_en")
	TranslationServer.add_translation(_english)
	TranslationServer.add_translation(_hungarian)


# --- plurals -----------------------------------------------------------------------------


func test_english_plurals_use_the_singular_for_one_only() -> void:
	TranslationServer.set_locale("en")
	assert_str(_apples(1)).is_equal("1 apple")
	for count: int in [0, 2, 5, 21]:
		assert_str(_apples(count)).override_failure_message("n = %d" % count).is_equal(
			"%d apples" % count
		)


func test_hungarian_plurals_follow_the_plural_forms_header() -> void:
	TranslationServer.set_locale("hu")
	# nplurals=2; plural=(n != 1): form 0 for 1 only, form 1 for everything else.
	assert_str(_apples(1)).is_equal("1 alma (egy)")
	for count: int in [0, 2, 5, 21]:
		assert_str(_apples(count)).override_failure_message("n = %d" % count).is_equal(
			"%d alma (sok)" % count
		)


func test_a_plural_key_in_neither_file_returns_the_keys() -> void:
	TranslationServer.set_locale("en")
	assert_str(tr_n("ui.fixture.gone", "ui.fixture.gone.plural", 1)).is_equal("ui.fixture.gone")
	assert_str(tr_n("ui.fixture.gone", "ui.fixture.gone.plural", 2)).is_equal(
		"ui.fixture.gone.plural"
	)
