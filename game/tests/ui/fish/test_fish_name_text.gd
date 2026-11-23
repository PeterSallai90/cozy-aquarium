extends GdUnitTestSuite
## #36 shown name (owner: developer): FishNameText.shown_name(fish, translator) is the nickname
## when it is not empty (unchanged, any Unicode, any length) and otherwise the translated derived
## default name of the uid. A derived name follows the game language, a nickname does not;
## duplicate names are allowed. one_line() turns every line break into one space and never touches
## the stored value.

const Edit := preload("res://tests/helpers/fish_edit_api.gd")
const Factory := preload("res://tests/helpers/factory.gd")
const Ui := preload("res://tests/helpers/tank_ui_rig.gd")

var _saved_locale: String = ""
var _language_state: Dictionary = {}


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()
	_language_state = Ui.begin_language_isolation("fish_name_text")
	TranslationServer.set_locale("en")


func after_test() -> void:
	Ui.end_language_isolation(_language_state, _saved_locale)


func _have() -> bool:
	var found: bool = Edit.exists(Edit.NAME_TEXT)
	(
		assert_bool(found)
		. override_failure_message("game/ui/fish/fish_name_text.gd is missing")
		. is_true()
	)
	return found


func test_36_an_empty_nickname_shows_the_translated_derived_name() -> void:
	if not _have():
		return
	var fish: FishInstance = Factory.fish("f1000001", &"neon_tetra", 0, "")
	var key: String = Edit.key_for("f1000001")
	var shown: String = Edit.shown_name(fish, self)
	assert_str(shown).is_not_empty()
	assert_str(shown).is_not_equal(key)
	assert_str(shown).is_equal(tr(key))


func test_36_a_nickname_is_returned_unchanged() -> void:
	if not _have():
		return
	var nicknames: Array[String] = [
		"Nemo",
		"  padded  ",
		"魚ちゃん",
		"\U0001F41F\U0001F420",
		"Árpád",
		"fish.default_name.01",
		"line\nbreak",
	]
	for nickname: String in nicknames:
		var fish: FishInstance = Factory.fish("f1000001", &"neon_tetra", 0, nickname)
		assert_str(Edit.shown_name(fish, self)).is_equal(nickname)


func test_36_a_nickname_of_ten_thousand_characters_is_returned_unchanged() -> void:
	if not _have():
		return
	var nickname: String = "x".repeat(10000)
	var fish: FishInstance = Factory.fish("f1000001", &"neon_tetra", 0, nickname)
	assert_int(Edit.shown_name(fish, self).length()).is_equal(10000)
	assert_str(fish.nickname).is_equal(nickname)


func test_36_the_derived_name_follows_the_language_and_a_nickname_does_not() -> void:
	if not _have():
		return
	var derived: FishInstance = Factory.fish("f1000001", &"neon_tetra", 0, "")
	var named: FishInstance = Factory.fish("f1000002", &"neon_tetra", 0, "Nemo")
	var english: String = Edit.shown_name(derived, self)
	await Ui.set_language(self, "hu")
	var hungarian: String = Edit.shown_name(derived, self)
	assert_str(hungarian).is_not_empty()
	assert_str(hungarian).is_equal(tr(Edit.key_for("f1000001")))
	assert_str(Edit.shown_name(named, self)).is_equal("Nemo")
	await Ui.set_language(self, "en")
	assert_str(Edit.shown_name(derived, self)).is_equal(english)
	assert_str(Edit.shown_name(named, self)).is_equal("Nemo")


func test_36_every_default_name_has_different_text_than_its_key_in_both_languages() -> void:
	if not _have():
		return
	for locale: String in ["en", "hu"]:
		TranslationServer.set_locale(locale)
		for key: String in Edit.all_keys():
			assert_str(tr(key)).override_failure_message("%s in %s" % [key, locale]).is_not_equal(
				key
			)


func test_36_duplicate_names_between_fish_are_allowed() -> void:
	if not _have():
		return
	var first: FishInstance = Factory.fish("f1000001", &"neon_tetra", 0, "Bubbles")
	var second: FishInstance = Factory.fish("f1000002", &"angelfish", 1, "Bubbles")
	assert_str(Edit.shown_name(first, self)).is_equal(Edit.shown_name(second, self))


func test_36_one_line_replaces_every_line_break_with_one_space() -> void:
	if not _have():
		return
	assert_str(Edit.one_line("a\nb")).is_equal("a b")
	assert_str(Edit.one_line("a\r\nb")).is_equal("a b")
	assert_str(Edit.one_line("a\rb")).is_equal("a b")
	assert_str(Edit.one_line("a b")).is_equal("a b")
	assert_str(Edit.one_line("a b")).is_equal("a b")
	assert_str(Edit.one_line("a\n\nb")).is_equal("a  b")


func test_36_one_line_keeps_text_without_a_break_and_does_not_trim() -> void:
	if not _have():
		return
	assert_str(Edit.one_line("")).is_empty()
	assert_str(Edit.one_line("  Nemo 魚  ")).is_equal("  Nemo 魚  ")


func test_36_shown_name_does_not_change_the_stored_nickname() -> void:
	if not _have():
		return
	var fish: FishInstance = Factory.fish("f1000001", &"neon_tetra", 0, "a\nb c")
	Edit.shown_name(fish, self)
	Edit.one_line(fish.nickname)
	assert_str(fish.nickname).is_equal("a\nb c")
