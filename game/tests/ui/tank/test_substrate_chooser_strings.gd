extends GdUnitTestSuite
## #28 criterion 17 and the new visible strings (owner: developer): every new key has non-empty
## text in en.po AND hu.po and in messages.pot; the English texts are the issue's; the five
## Hungarian names are the owner-decided ones (Homok, Kavics, Folyami kavics, Fekete homok, Színes
## kavics); the open panel shows Hungarian everywhere. Hungarian descriptions are proposals, so
## they are checked to exist and to differ from English, not letter by letter. The pot and po
## consistency itself is also checked by tools/scripts/generate_pot.py --check and
## check_translations.py in CI.

const Rig := preload("res://tests/helpers/room_rig.gd")
const Ui := preload("res://tests/helpers/tank_ui_rig.gd")
const Sub := preload("res://tests/helpers/substrate_api.gd")
const Sui := preload("res://tests/helpers/substrate_ui_rig.gd")
const Table := preload("res://tests/helpers/tank_table.gd")

const LOCALIZATION_DIR := "res://localization/"
const EN: Dictionary = {
	"substrate.chooser.open": "Substrate",
	"substrate.chooser.title": "Choose your substrate",
	"substrate.chooser.current": "In use",
	"substrate.chooser.colour": "Colour",
	"substrate.sand_fine.name": "Sand",
	"substrate.sand_fine.description": "Fine, soft sand for a calm, sunny floor.",
	"substrate.gravel_natural.name": "Gravel",
	"substrate.gravel_natural.description": "Small natural stones with a lively, earthy look.",
	"substrate.pebbles_river.name": "Pebbles",
	"substrate.pebbles_river.description": "Smooth, rounded river stones, like a quiet stream bed.",
	"substrate.sand_black.name": "Black sand",
	"substrate.sand_black.description": "Dark, fine sand that makes colours glow.",
	"substrate.gravel_coloured.name": "Coloured gravel",
	"substrate.gravel_coloured.description": "Bright, playful gravel in cheerful colours.",
}
## Texts that are decided (UI strings and the owner-decided names).
const HU_FIXED: Dictionary = {
	"substrate.chooser.open": "Aljzat",
	"substrate.chooser.title": "Válaszd ki az aljzatot",
	"substrate.chooser.current": "Használatban",
	"substrate.chooser.colour": "Szín",
	"substrate.sand_fine.name": "Homok",
	"substrate.gravel_natural.name": "Kavics",
	"substrate.pebbles_river.name": "Folyami kavics",
	"substrate.sand_black.name": "Fekete homok",
	"substrate.gravel_coloured.name": "Színes kavics",
}

var _saved_locale: String = ""
var _language_state: Dictionary = {}


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()
	_language_state = Ui.begin_language_isolation("substrate_strings")


func after_test() -> void:
	Ui.end_language_isolation(_language_state, _saved_locale)


func _text(key: String, locale: String) -> String:
	TranslationServer.set_locale(locale)
	return tr(key)


## The msgstr of a msgid in a .po or .pot file, or "<missing>" when the key is not there.
func _po_value(file_name: String, key: String) -> String:
	var text: String = FileAccess.get_file_as_string(LOCALIZATION_DIR + file_name)
	var marker: String = 'msgid "%s"\nmsgstr "' % key
	var start: int = text.find(marker)
	if start < 0:
		return "<missing>"
	var from: int = start + marker.length()
	return text.substr(from, text.find('"\n', from) - from)


# --- the keys exist in all three files ---


func test_ac17_every_new_key_is_in_the_pot_and_has_text_in_en_po_and_hu_po() -> void:
	for key: String in EN:
		(
			assert_str(_po_value("messages.pot", key))
			. override_failure_message("%s is missing in messages.pot" % key)
			. is_not_equal("<missing>")
		)
		for file_name: String in ["en.po", "hu.po"]:
			var value: String = _po_value(file_name, key)
			(
				assert_str(value)
				. override_failure_message("%s is missing in %s" % [key, file_name])
				. is_not_equal("<missing>")
			)
			(
				assert_str(value)
				. override_failure_message("%s is empty in %s" % [key, file_name])
				. is_not_empty()
			)


func test_ac17_the_english_texts_are_the_ones_of_the_issue() -> void:
	for key: String in EN:
		assert_str(_text(key, "en")).override_failure_message(key).is_equal(EN[key])


func test_ac17_the_decided_hungarian_texts_and_owner_names_are_exact() -> void:
	for key: String in HU_FIXED:
		assert_str(_text(key, "hu")).override_failure_message(key).is_equal(HU_FIXED[key])


func test_ac17_the_hungarian_descriptions_exist_and_differ_from_english() -> void:
	for id: StringName in Sub.IDS:
		var key: String = "substrate.%s.description" % id
		var hungarian: String = _text(key, "hu")
		assert_str(hungarian).override_failure_message("%s (hu) is empty" % key).is_not_empty()
		(
			assert_str(hungarian)
			. override_failure_message("%s (hu) is untranslated" % key)
			. is_not_equal(key)
		)
		assert_str(hungarian).override_failure_message("%s (hu) is English" % key).is_not_equal(
			EN[key]
		)


func test_ac17_the_catalog_text_keys_resolve_in_both_languages() -> void:
	var catalog: RefCounted = Sub.catalog()
	assert_int(Sub.ids(catalog).size()).is_equal(5)
	for id: StringName in Sub.IDS:
		for field: String in ["name_key", "description_key"]:
			var key: String = Sub.prop(Sub.definition(catalog, id), field, "")
			for locale: String in ["en", "hu"]:
				var text: String = _text(key, locale)
				assert_str(text).override_failure_message("%s (%s)" % [key, locale]).is_not_empty()
				(
					assert_str(text)
					. override_failure_message("%s (%s) is untranslated" % [key, locale])
					. is_not_equal(key)
				)


func test_ac17_settings_close_is_reused_for_the_close_button() -> void:
	assert_str(_text("settings.close", "en")).is_equal("Close")
	assert_str(_text("settings.close", "hu")).is_equal("Bezárás")


# --- the open panel in Hungarian ---


func _open_panel() -> Control:
	var model: AquariumModel = Sub.model_with(Sub.SAND, Sub.SAND_DEFAULT, Table.MEDIUM)
	var rig: Dictionary = await Ui.open(self, model, Rig.default_catalog(), CommandHistory.new())
	auto_free(rig["room"])
	var controls: Control = rig["controls"]
	if controls == null or Sui.open_button(controls) == null:
		assert_bool(false).override_failure_message("no Substrate button in TankControls").is_true()
		return null
	auto_free(controls)
	await Sui.press_open(self, controls)
	return controls


func test_ac17_the_open_panel_shows_hungarian_everywhere() -> void:
	var controls: Control = await _open_panel()
	if controls == null:
		return
	await Ui.set_language(self, "hu")
	assert_str(Sui.shown(Sui.open_button(controls))).is_equal("Aljzat")
	assert_str(Sui.shown(Sui.title_label(controls))).is_equal("Válaszd ki az aljzatot")
	assert_str(Sui.shown(Sui.colour_label(controls))).is_equal("Szín")
	assert_str(Sui.shown(Sui.close_button(controls))).is_equal("Bezárás")
	for id: StringName in Sub.IDS:
		assert_str(Sui.shown(Sui.card_label(controls, id, "NameLabel"))).is_equal(
			HU_FIXED["substrate.%s.name" % id]
		)
		assert_str(Sui.shown(Sui.card_label(controls, id, "DescriptionLabel"))).is_equal(
			_text("substrate.%s.description" % id, "hu")
		)
	assert_str(Sui.shown(Sui.card_label(controls, Sub.SAND, "InUseLabel"))).is_equal("Használatban")


func test_ac17_no_visible_panel_text_is_a_raw_key_or_english_in_hungarian() -> void:
	var controls: Control = await _open_panel()
	if controls == null:
		return
	await Ui.set_language(self, "hu")
	var english: Array = EN.values()
	for text: String in Sui.visible_texts(controls):
		var shown: String = text.substr(text.find(": ") + 2)
		assert_str(shown).override_failure_message("raw key shown: %s" % text).not_contains(
			"substrate."
		)
		(
			assert_bool(english.has(shown))
			. override_failure_message("English text in Hungarian mode: %s" % text)
			. is_false()
		)


func test_ac17_switching_back_to_english_restores_the_english_panel_texts() -> void:
	var controls: Control = await _open_panel()
	if controls == null:
		return
	await Ui.set_language(self, "hu")
	await Ui.set_language(self, "en")
	assert_str(Sui.shown(Sui.title_label(controls))).is_equal("Choose your substrate")
	assert_str(Sui.shown(Sui.card_label(controls, Sub.BLACK, "NameLabel"))).is_equal("Black sand")
