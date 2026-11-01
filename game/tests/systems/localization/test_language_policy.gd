extends GdUnitTestSuite

var _saved_locale: String = ""


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()


func after_test() -> void:
	TranslationServer.set_locale(_saved_locale)


# --- first-start rule (detect) -------------------------------------------------------------


func test_hungarian_os_locales_give_magyar() -> void:
	for locale: String in [
		"hu", "HU", "hu_HU", "hu-HU", "hu_Latn_HU", "Hu_hu", "HU-hu", "hu_HU.UTF-8"
	]:
		assert_str(LanguagePolicy.detect(locale)).override_failure_message(locale).is_equal("hu")


func test_surrounding_whitespace_in_the_os_locale_is_ignored() -> void:
	assert_str(LanguagePolicy.detect(" hu_HU ")).is_equal("hu")
	assert_str(LanguagePolicy.detect("\thu\n")).is_equal("hu")


func test_unsupported_os_locales_give_english() -> void:
	for locale: String in ["en", "en_US", "en-GB", "de_DE", "x", "fr", "sk_SK", "zh_Hans_CN"]:
		assert_str(LanguagePolicy.detect(locale)).override_failure_message(locale).is_equal("en")


func test_empty_or_unreadable_os_locale_gives_english() -> void:
	for locale: String in ["", " ", "_", "-", "_hu", "-hu", "??", "hu?"]:
		assert_str(LanguagePolicy.detect(locale)).override_failure_message(locale).is_equal("en")


func test_only_the_language_part_counts() -> void:
	# The language part is what stands before the first "_" or "-", not a prefix match.
	for locale: String in ["hux_HU", "huh", "hun_HU", "h", "de_HU", "en_hu", "de-hu"]:
		assert_str(LanguagePolicy.detect(locale)).override_failure_message(locale).is_equal("en")


# --- supported values --------------------------------------------------------------------


func test_supported_languages_are_english_then_magyar() -> void:
	assert_array(LanguagePolicy.supported_languages()).is_equal(["en", "hu"])
	assert_str(LanguagePolicy.DEFAULT_LANGUAGE).is_equal("en")


func test_supported_languages_returns_a_fresh_copy() -> void:
	var list: PackedStringArray = LanguagePolicy.supported_languages()
	list.append("xx")
	list.remove_at(0)
	assert_array(LanguagePolicy.supported_languages()).is_equal(["en", "hu"])


func test_is_supported_accepts_only_the_two_exact_codes() -> void:
	assert_bool(LanguagePolicy.is_supported("en")).is_true()
	assert_bool(LanguagePolicy.is_supported("hu")).is_true()
	for value: Variant in [
		"xx",
		"",
		"HU",
		"EN",
		"hu_HU",
		"en_US",
		" hu",
		"hu ",
		"magyar",
		42,
		0,
		1.5,
		null,
		true,
		[],
		{}
	]:
		(
			assert_bool(LanguagePolicy.is_supported(value))
			. override_failure_message("is_supported(%s)" % [value])
			. is_false()
		)


# --- stored value versus OS locale -------------------------------------------------------


func test_a_supported_stored_value_wins_over_the_os_locale() -> void:
	assert_str(LanguagePolicy.resolve("hu", "en_US")).is_equal("hu")
	assert_str(LanguagePolicy.resolve("en", "hu_HU")).is_equal("en")
	assert_str(LanguagePolicy.resolve("hu", "")).is_equal("hu")


func test_a_missing_stored_value_uses_the_os_locale() -> void:
	assert_str(LanguagePolicy.resolve(null, "hu_HU")).is_equal("hu")
	assert_str(LanguagePolicy.resolve(null, "de_DE")).is_equal("en")
	assert_str(LanguagePolicy.resolve(null, "")).is_equal("en")


func test_a_bad_stored_value_behaves_like_a_first_start() -> void:
	for stored: Variant in ["xx", "", "HU", 42, 1.5, true, [], {}, "hu_HU"]:
		(
			assert_str(LanguagePolicy.resolve(stored, "hu_HU"))
			. override_failure_message("stored %s with OS hu_HU" % [stored])
			. is_equal("hu")
		)
		(
			assert_str(LanguagePolicy.resolve(stored, "de_DE"))
			. override_failure_message("stored %s with OS de_DE" % [stored])
			. is_equal("en")
		)


# --- display names -----------------------------------------------------------------------


func test_display_names_are_each_language_in_its_own_language() -> void:
	assert_str(LanguagePolicy.display_name("en")).is_equal("English")
	assert_str(LanguagePolicy.display_name("hu")).is_equal("Magyar")
	assert_str(LanguagePolicy.DISPLAY_NAMES["en"]).is_equal("English")
	assert_str(LanguagePolicy.DISPLAY_NAMES["hu"]).is_equal("Magyar")


func test_display_names_do_not_change_with_the_locale() -> void:
	for locale: String in ["en", "hu", "de"]:
		TranslationServer.set_locale(locale)
		assert_str(LanguagePolicy.display_name("en")).is_equal("English")
		assert_str(LanguagePolicy.display_name("hu")).is_equal("Magyar")


func test_display_name_of_an_unsupported_code_is_empty() -> void:
	for code: String in ["xx", "", "HU", "hu_HU", "English"]:
		assert_str(LanguagePolicy.display_name(code)).override_failure_message(code).is_empty()
