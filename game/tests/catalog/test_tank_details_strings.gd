extends GdUnitTestSuite
## #117 new visible strings (owner: developer): the 11 new keys have the texts of the issue in en
## and hu, are in messages.pot and in both .po files, and the reused keys are not redefined.
## The pot and po consistency itself is checked by tools/scripts/check_translations.py in CI.

const LOCALIZATION_DIR := "res://localization/"
const NEW_KEYS: Dictionary = {
	"tank.details.title": ["Tank details", "Akvárium adatai"],
	"tank.details.open": ["Tank details", "Akvárium adatai"],
	"tank.details.close": ["Close", "Bezárás"],
	"tank.details.length": ["Length", "Hosszúság"],
	"tank.details.width": ["Width", "Szélesség"],
	"tank.details.height": ["Height", "Magasság"],
	"tank.details.water_level": ["Water level", "Vízszint"],
	"tank.details.water_volume": ["Water volume", "Vízmennyiség"],
	"tank.details.glass_thickness": ["Glass thickness", "Üvegvastagság"],
	"tank.details.fallback":
	[
		"The tank in your save was not found, so the default tank is shown.",
		"A mentésben szereplő akvárium nem található, ezért az alapértelmezett akvárium látható.",
	],
	"unit.cm": ["%s cm", "%s cm"],
}
const REUSED_KEYS: Dictionary = {
	"unit.litre": ["%s L", "%s l"],
	"number.unknown": ["Unknown", "Ismeretlen"],
}

var _saved_locale: String = ""


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()


func after_test() -> void:
	TranslationServer.set_locale(_saved_locale)


func _text(key: String, locale: String) -> String:
	TranslationServer.set_locale(locale)
	return tr(key)


func _file(name: String) -> String:
	return FileAccess.get_file_as_string(LOCALIZATION_DIR + name)


func test_the_eleven_new_keys_have_the_issue_texts_in_english_and_hungarian() -> void:
	assert_int(NEW_KEYS.size()).is_equal(11)
	for key: String in NEW_KEYS:
		var texts: Array = NEW_KEYS[key]
		assert_str(_text(key, "en")).override_failure_message("%s (en)" % key).is_equal(texts[0])
		assert_str(_text(key, "hu")).override_failure_message("%s (hu)" % key).is_equal(texts[1])


func test_the_reused_keys_keep_their_texts() -> void:
	for key: String in REUSED_KEYS:
		var texts: Array = REUSED_KEYS[key]
		assert_str(_text(key, "en")).override_failure_message("%s (en)" % key).is_equal(texts[0])
		assert_str(_text(key, "hu")).override_failure_message("%s (hu)" % key).is_equal(texts[1])


func test_every_new_key_is_in_the_pot_and_both_po_files_with_non_empty_text() -> void:
	for name: String in ["messages.pot", "en.po", "hu.po"]:
		var text: String = _file(name)
		assert_str(text).override_failure_message("%s is empty or missing" % name).is_not_empty()
		for key: String in NEW_KEYS:
			(
				assert_bool(text.contains('msgid "%s"' % key))
				. override_failure_message("%s missing in %s" % [key, name])
				. is_true()
			)


func test_the_reused_keys_are_defined_once_in_each_file() -> void:
	for name: String in ["messages.pot", "en.po", "hu.po"]:
		var text: String = _file(name)
		for key: String in REUSED_KEYS:
			(
				assert_int(text.count('msgid "%s"' % key))
				. override_failure_message("%s is defined more than once in %s" % [key, name])
				. is_less_equal(1)
			)


func test_the_key_follows_the_label_water_volume_not_volume() -> void:
	var pot: String = _file("messages.pot")
	assert_bool(pot.contains('msgid "tank.details.volume"')).is_false()
	assert_bool(pot.contains('msgid "tank.details.depth"')).is_false()
