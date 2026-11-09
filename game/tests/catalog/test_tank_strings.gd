extends GdUnitTestSuite
## #24 criterion 3 and the new visible strings (owner: developer): every tank name and description
## key has non-empty en and hu text, no description holds a digit, the renamed medium keys replace
## the old ones, and the chooser, dialog and litre strings exist with the texts of the issue.
## The pot and po consistency itself is checked by tools/scripts/check_translations.py in CI.

const Table := preload("res://tests/helpers/tank_table.gd")

const LOCALIZATION_DIR := "res://localization/"
const NEW_KEYS: Dictionary = {
	"tank.chooser.open": ["Change tank", "Akvárium cseréje"],
	"tank.chooser.title": ["Choose your tank", "Válaszd ki az akváriumot"],
	"tank.chooser.current": ["In use", "Használatban"],
	"tank.change.title": ["Change tank?", "Akvárium cseréje?"],
	"tank.change.confirm": ["Change tank", "Csere"],
	"tank.change.cancel": ["Cancel", "Mégse"],
	"unit.litre": ["%s L", "%s l"],
	"settings.close": ["Close", "Bezárás"],
}
const BODY_EN := (
	"Changing to the %s will clear everything in this tank: "
	+ "decor, plants, fish and the sand shape."
)
const BODY_HU := (
	"A(z) %s akváriumra váltás mindent kiüríti ebből az akváriumból: "
	+ "dekorációt, növényeket, halakat és a homok formáját."
)

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


func _has_digit(text: String) -> bool:
	return RegEx.create_from_string("\\d").search(text) != null


# --- AC 3: names and descriptions ---


func test_ac03_every_name_and_description_key_has_text_in_english_and_hungarian() -> void:
	for id: StringName in Table.IDS:
		for kind: String in ["name", "description"]:
			var key: String = "tank.%s.%s" % [Table.suffix(id), kind]
			for locale: String in ["en", "hu"]:
				var text: String = _text(key, locale)
				(
					assert_str(text)
					. override_failure_message("%s (%s) is empty" % [key, locale])
					. is_not_empty()
				)
				(
					assert_str(text)
					. override_failure_message("%s (%s) is untranslated" % [key, locale])
					. is_not_equal(key)
				)


func test_ac03_names_are_the_owner_confirmed_texts() -> void:
	for id: StringName in Table.IDS:
		var key: String = "tank.%s.name" % Table.suffix(id)
		assert_str(_text(key, "en")).is_equal(Table.row(id)["name_en"])
		assert_str(_text(key, "hu")).is_equal(Table.row(id)["name_hu"])


func test_ac03_descriptions_are_the_texts_of_the_issue() -> void:
	for id: StringName in Table.IDS:
		var key: String = "tank.%s.description" % Table.suffix(id)
		assert_str(_text(key, "en")).is_equal(Table.row(id)["description_en"])
		assert_str(_text(key, "hu")).is_equal(Table.row(id)["description_hu"])


func test_ac03_no_description_text_contains_a_digit() -> void:
	for id: StringName in Table.IDS:
		var key: String = "tank.%s.description" % Table.suffix(id)
		for locale: String in ["en", "hu"]:
			var text: String = _text(key, locale)
			(
				assert_bool(_has_digit(text))
				. override_failure_message("%s (%s) holds a digit: %s" % [key, locale, text])
				. is_false()
			)


func test_ac03_no_tank_medium_60l_key_remains_in_the_translation_files() -> void:
	for name: String in ["en.po", "hu.po", "messages.pot"]:
		var text: String = _file(name)
		assert_str(text).override_failure_message("%s is empty or missing" % name).is_not_empty()
		(
			assert_bool(text.contains("tank.medium_60l"))
			. override_failure_message("%s still holds a tank.medium_60l key" % name)
			. is_false()
		)


func test_ac03_the_pot_lists_every_tank_key() -> void:
	var pot: String = _file("messages.pot")
	for id: StringName in Table.IDS:
		for kind: String in ["name", "description"]:
			var key: String = "tank.%s.%s" % [Table.suffix(id), kind]
			(
				assert_bool(pot.contains('msgid "%s"' % key))
				. override_failure_message("%s missing in messages.pot" % key)
				. is_true()
			)


func test_ac03_the_old_medium_litre_wording_is_gone() -> void:
	for locale: String in ["en", "hu"]:
		var text: String = _text("tank.medium_1.description", locale)
		assert_bool(text.to_lower().contains("litre")).is_false()
		assert_bool(text.to_lower().contains(" l ")).is_false()


# --- the new chooser, dialog and litre strings ---


func test_new_keys_have_the_issue_texts_in_english_and_hungarian() -> void:
	for key: String in NEW_KEYS:
		var texts: Array = NEW_KEYS[key]
		assert_str(_text(key, "en")).override_failure_message("%s (en)" % key).is_equal(texts[0])
		assert_str(_text(key, "hu")).override_failure_message("%s (hu)" % key).is_equal(texts[1])


func test_the_dialog_body_has_one_placeholder_for_the_tank_name_in_both_languages() -> void:
	assert_str(_text("tank.change.body", "en")).is_equal(BODY_EN)
	assert_str(_text("tank.change.body", "hu")).is_equal(BODY_HU)


func test_the_new_keys_are_in_the_pot_and_the_dropped_close_key_is_not() -> void:
	var pot: String = _file("messages.pot")
	for key: String in NEW_KEYS:
		(
			assert_bool(pot.contains('msgid "%s"' % key))
			. override_failure_message("%s missing in messages.pot" % key)
			. is_true()
		)
	assert_bool(pot.contains('msgid "tank.change.body"')).is_true()
	assert_bool(pot.contains("tank.chooser.close")).is_false()
