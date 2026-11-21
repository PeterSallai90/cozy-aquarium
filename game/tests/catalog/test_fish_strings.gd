extends GdUnitTestSuite
## #34 AC 6 and 34 (owner: developer): the six new keys have non-empty text in en and hu with the
## owner-decided names, and the six descriptions are 1 or 2 sentences of at most 160 characters,
## hold no Latin name, no digit (so no temperature, pH or other Mode 2 number) and the three of a
## language differ. The pot and po consistency itself is checked by tools/scripts/generate_pot.py
## --check and check_translations.py (AC 25, run by the tester after the implementation).
## Test decisions: "no Mode 2 number" is enforced as "no digit at all", as for the tank
## descriptions; a sentence ends with . ! or ? followed by a space or the end of the text.

const Api := preload("res://tests/helpers/fish_api.gd")

const NAMES: Dictionary[StringName, Array] = {
	&"neon_tetra": ["Neon tetra", "Neonhal"],
	&"angelfish": ["Angelfish", "Vitorláshal"],
	&"bronze_corydoras": ["Bronze corydoras", "Bronz páncélosharcsa"],
}
const LATIN: PackedStringArray = [
	"Paracheirodon", "innesi", "Pterophyllum", "scalare", "Corydoras aeneus"
]
const MAX_DESCRIPTION := 160

var _saved_locale: String = ""


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()


func after_test() -> void:
	TranslationServer.set_locale(_saved_locale)


func _text(key: String, locale: String) -> String:
	TranslationServer.set_locale(locale)
	return tr(key)


func _sentences(text: String) -> int:
	return RegEx.create_from_string("[.!?](\\s|$)").search_all(text).size()


func _has_digit(text: String) -> bool:
	return RegEx.create_from_string("\\d").search(text) != null


func _description_failures(text: String) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	var sentences: int = _sentences(text)
	if sentences < 1 or sentences > 2:
		failures.append("%d sentences, need 1 or 2" % sentences)
	if text.length() > MAX_DESCRIPTION:
		failures.append("%d characters, max %d" % [text.length(), MAX_DESCRIPTION])
	if _has_digit(text):
		failures.append("holds a digit")
	for latin: String in LATIN:
		if text.to_lower().contains(latin.to_lower()):
			failures.append("holds the Latin name part %s" % latin)
	return failures


func test_ac06_every_key_has_non_empty_text_in_english_and_hungarian() -> void:
	for id: StringName in Api.IDS:
		for kind: String in ["name", "description"]:
			var key: String = "fish.%s.%s" % [id, kind]
			for locale: String in ["en", "hu"]:
				var text: String = _text(key, locale)
				(
					assert_str(text)
					. override_failure_message("%s has no %s text" % [key, locale])
					. is_not_empty()
				)
				(
					assert_str(text)
					. override_failure_message("%s is untranslated in %s" % [key, locale])
					. is_not_equal(key)
				)


func test_ac06_the_names_are_the_owner_decided_ones() -> void:
	for id: StringName in Api.IDS:
		var expected: Array = NAMES[id]
		assert_str(_text("fish.%s.name" % id, "en")).is_equal(expected[0])
		assert_str(_text("fish.%s.name" % id, "hu")).is_equal(expected[1])


func test_ac34_descriptions_are_short_without_latin_names_or_numbers() -> void:
	for id: StringName in Api.IDS:
		for locale: String in ["en", "hu"]:
			var text: String = _text("fish.%s.description" % id, locale)
			var failures: PackedStringArray = _description_failures(text)
			(
				assert_str("\n".join(failures))
				. override_failure_message("%s description (%s): %s" % [id, locale, failures])
				. is_empty()
			)


func test_ac34_the_three_descriptions_of_a_language_differ() -> void:
	for locale: String in ["en", "hu"]:
		var seen: Dictionary = {}
		for id: StringName in Api.IDS:
			var key: String = "fish.%s.description" % id
			var text: String = _text(key, locale)
			(
				assert_str(text)
				. override_failure_message("%s is untranslated in %s" % [key, locale])
				. is_not_equal(key)
			)
			seen[text] = true
		(
			assert_int(seen.size())
			. override_failure_message("the %s descriptions are not three different texts" % locale)
			. is_equal(3)
		)


func test_ac34_edge_the_description_rules_catch_each_violation() -> void:
	assert_int(_description_failures("A calm fish. It likes a quiet corner.").size()).is_equal(0)
	assert_int(_description_failures("One. Two. Three.").size()).is_equal(1)
	assert_int(_description_failures("Lives at 24 degrees.").size()).is_equal(1)
	assert_int(_description_failures("Known as Corydoras aeneus.").size()).is_equal(1)
	assert_int(_description_failures("x".repeat(161) + ".").size()).is_equal(1)
	assert_int(_description_failures("").size()).is_equal(1)
