extends GdUnitTestSuite
## #36 strings (owner: developer): every key of the issue table has the issue's text in en and hu
## (the Hungarian count is "%d hal" in both plural forms), scientific names stay out of the files,
## and the open panel shows the right language after a switch. The pot and po consistency itself is
## checked by generate_pot.py --check and check_translations.py.
## Test decision: the texts are read from the .po files with Translation.get_message, so the test
## does not depend on the active locale.

const Fp := preload("res://tests/helpers/fish_panel_rig.gd")
const Ui := preload("res://tests/helpers/tank_ui_rig.gd")

const EN: Dictionary[String, String] = {
	"fish.browser.open_button": "Fish",
	"fish.browser.title": "Fish",
	"fish.browser.close": "Close",
	"fish.browser.species_heading": "Species",
	"fish.browser.in_tank_heading": "In your tank",
	"fish.browser.add": "Add to tank",
	"fish.browser.remove": "Remove",
	"fish.browser.remove.tooltip": "Remove %s",
	"fish.browser.empty_tank": "No fish yet. Pick a species and add one.",
	"fish.card.length": "Adult length",
	"fish.card.zone": "Swims in",
	"fish.card.unknown_species": "Unknown species",
	"fish.zone.top": "Upper water",
	"fish.zone.middle": "Middle water",
	"fish.zone.bottom": "Near the bottom",
}
const HU: Dictionary[String, String] = {
	"fish.browser.open_button": "Halak",
	"fish.browser.title": "Halak",
	"fish.browser.close": "Bezárás",
	"fish.browser.species_heading": "Fajok",
	"fish.browser.in_tank_heading": "A tartályodban",
	"fish.browser.add": "Hozzáadás a tartályhoz",
	"fish.browser.remove": "Eltávolítás",
	"fish.browser.remove.tooltip": "%s eltávolítása",
	"fish.browser.empty_tank": "Még nincs hal. Válassz egy fajt, és adj hozzá egyet.",
	"fish.card.length": "Kifejlett hossz",
	"fish.card.zone": "Itt úszik",
	"fish.card.unknown_species": "Ismeretlen faj",
	"fish.zone.top": "Felső vízréteg",
	"fish.zone.middle": "Középső vízréteg",
	"fish.zone.bottom": "A fenék közelében",
}
## The proposed default names, key 01 to 30 (the owner may edit them before the freeze).
const NAMES_EN: PackedStringArray = [
	"Bubbles",
	"Pebble",
	"Sunny",
	"Pip",
	"Coral",
	"Biscuit",
	"Splash",
	"Maple",
	"Ziggy",
	"Pearl",
	"Mochi",
	"Ripple",
	"Peanut",
	"Dot",
	"Fin",
	"Marble",
	"Willow",
	"Sparkle",
	"Noodle",
	"Clover",
	"Misty",
	"Pepper",
	"Daisy",
	"Waffle",
	"Drift",
	"Tango",
	"Pixel",
	"Olive",
	"Twinkle",
	"Jelly",
]
const NAMES_HU: PackedStringArray = [
	"Buborék",
	"Kavics",
	"Napocska",
	"Csipet",
	"Korall",
	"Keksz",
	"Csobbi",
	"Juhar",
	"Cikkcakk",
	"Gyöngy",
	"Mókus",
	"Hullám",
	"Mogyoró",
	"Pötty",
	"Uszonyka",
	"Gombóc",
	"Fűzike",
	"Szikra",
	"Tészta",
	"Lóhere",
	"Ködös",
	"Borsika",
	"Százszorszép",
	"Gofri",
	"Sodródó",
	"Tangó",
	"Pixel",
	"Olívia",
	"Csillám",
	"Zselé",
]

var _saved_locale: String = ""
var _language_state: Dictionary = {}


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()
	_language_state = Ui.begin_language_isolation("fish_panel_strings")
	TranslationServer.set_locale("en")


func after_test() -> void:
	Ui.end_language_isolation(_language_state, _saved_locale)


func _message(language: String, key: String) -> String:
	var translation: Translation = load("res://localization/%s.po" % language) as Translation
	return str(translation.get_message(key))


func test_36_every_key_has_the_issue_text_in_english() -> void:
	for key: String in EN:
		assert_str(_message("en", key)).override_failure_message(key).is_equal(EN[key])


func test_36_every_key_has_the_issue_text_in_hungarian() -> void:
	for key: String in HU:
		assert_str(_message("hu", key)).override_failure_message(key).is_equal(HU[key])


func test_36_the_count_has_both_plural_forms_filled_in_both_languages() -> void:
	var en: Translation = load("res://localization/en.po") as Translation
	var hu: Translation = load("res://localization/hu.po") as Translation
	(
		assert_str(str(en.get_plural_message("fish.browser.count", "fish.browser.count.plural", 1)))
		. is_equal("%d fish")
	)
	(
		assert_str(str(en.get_plural_message("fish.browser.count", "fish.browser.count.plural", 2)))
		. is_equal("%d fish")
	)
	for n: int in [0, 1, 2, 5]:
		(
			assert_str(
				str(hu.get_plural_message("fish.browser.count", "fish.browser.count.plural", n))
			)
			. is_equal("%d hal")
		)


func test_36_the_default_names_have_the_proposed_texts_in_both_languages() -> void:
	assert_int(NAMES_EN.size()).is_equal(30)
	assert_int(NAMES_HU.size()).is_equal(30)
	for index: int in 30:
		var key: String = "fish.default_name.%02d" % (index + 1)
		assert_str(_message("en", key)).override_failure_message("en %s" % key).is_equal(
			NAMES_EN[index]
		)
		assert_str(_message("hu", key)).override_failure_message("hu %s" % key).is_equal(
			NAMES_HU[index]
		)


func test_36_the_pot_lists_every_new_key_and_no_scientific_name() -> void:
	var text: String = FileAccess.get_file_as_string("res://localization/messages.pot")
	for key: String in EN:
		assert_bool(text.contains('msgid "%s"' % key)).override_failure_message(key).is_true()
	assert_bool(text.contains('msgid "fish.browser.count"')).is_true()
	assert_bool(text.contains('msgid_plural "fish.browser.count.plural"')).is_true()
	for number: int in range(1, 31):
		var key: String = 'msgid "fish.default_name.%02d"' % number
		assert_bool(text.contains(key)).override_failure_message(key).is_true()


func test_36_the_open_panel_switches_language_without_reopening() -> void:
	var controls: Control = await Fp.open_controls(self, Fp.model_with_tank())
	if controls == null or Fp.button_of(controls) == null:
		assert_bool(false).override_failure_message("TankControls has no FishButton").is_true()
		return
	auto_free(controls)
	await Fp.press_open(self, controls)
	assert_str(Fp.shown(Fp.label(controls, "TitleLabel"))).is_equal("Fish")
	assert_str(Fp.shown(Fp.label(controls, "InTankHeading"))).is_equal("In your tank")
	assert_str(Fp.shown(Fp.add_button(controls))).is_equal("Add to tank")
	await Ui.set_language(self, "hu")
	assert_str(Fp.shown(Fp.label(controls, "TitleLabel"))).is_equal("Halak")
	assert_str(Fp.shown(Fp.label(controls, "InTankHeading"))).is_equal("A tartályodban")
	assert_str(Fp.shown(Fp.add_button(controls))).is_equal("Hozzáadás a tartályhoz")
	assert_str(Fp.count_text(controls)).is_equal("0 hal")
	assert_bool(Fp.visible_in_tree(Fp.label(controls, "EmptyTankLabel"))).is_true()
