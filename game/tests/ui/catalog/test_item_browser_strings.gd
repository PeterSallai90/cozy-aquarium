extends GdUnitTestSuite
## #30 criterion 21 and the new visible strings (owner: developer): every one of the 13 new keys
## has non-empty text in en.po AND hu.po and is in messages.pot; the English texts are the issue's;
## the owner-decided Hungarian texts (the button and the four categories, plus the other
## issue-table texts as the proposals they are) are exact where decided; the open panel shows
## Hungarian everywhere after a language switch without closing, and keeps the query, the category
## and the pick. Pattern of test_substrate_chooser_strings.gd. The pot and po consistency itself is
## also checked by tools/scripts/generate_pot.py --check and check_translations.py in CI.

const Ir := preload("res://tests/helpers/item_browser_rig.gd")
const Ui := preload("res://tests/helpers/tank_ui_rig.gd")

const LOCALIZATION_DIR := "res://localization/"
const EN: Dictionary = {
	"item.browser.open_button": "Items",
	"item.browser.title": "Items",
	"item.browser.close": "Close",
	"item.browser.search_placeholder": "Search items",
	"item.browser.search_clear": "Clear search",
	"item.browser.empty_catalog": "No items yet.",
	"item.browser.empty_search": "No items match your search.",
	"item.browser.selected": "Selected",
	"item.category.all": "All",
	"item.category.rock": "Rocks",
	"item.category.wood": "Wood",
	"item.category.ornament": "Ornaments",
	"item.category.plant": "Plants",
}
## The Hungarian texts the owner decided (Q3) and the ones of the issue table.
const HU_FIXED: Dictionary = {
	"item.browser.open_button": "Elemek",
	"item.category.rock": "Kövek",
	"item.category.wood": "Fa",
	"item.category.ornament": "Díszek",
	"item.category.plant": "Növények",
}
const HU_TABLE: Dictionary = {
	"item.browser.title": "Elemek",
	"item.browser.close": "Bezárás",
	"item.browser.search_placeholder": "Elemek keresése",
	"item.browser.search_clear": "Keresés törlése",
	"item.browser.empty_catalog": "Még nincsenek elemek.",
	"item.browser.empty_search": "Nincs a keresésnek megfelelő elem.",
	"item.browser.selected": "Kiválasztva",
	"item.category.all": "Mind",
}

var _saved_locale: String = ""
var _language_state: Dictionary = {}
var _translations: Array[Translation] = []
var _controls: Control = null


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()
	_language_state = Ui.begin_language_isolation("item_browser_strings")
	_translations = Ir.add_translations()
	TranslationServer.set_locale("en")


func after_test() -> void:
	Ir.remove_translations(_translations)
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


# --- the keys ---


func test_ac21_there_are_thirteen_new_keys() -> void:
	assert_int(EN.size()).is_equal(13)


func test_ac21_every_new_key_is_in_the_pot_and_has_text_in_en_po_and_hu_po() -> void:
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


func test_ac21_the_english_texts_are_the_ones_of_the_issue() -> void:
	for key: String in EN:
		assert_str(_text(key, "en")).override_failure_message(key).is_equal(EN[key])


func test_ac21_the_decided_hungarian_texts_are_exact() -> void:
	for key: String in HU_FIXED:
		assert_str(_text(key, "hu")).override_failure_message(key).is_equal(HU_FIXED[key])


func test_ac21_the_other_hungarian_texts_are_the_proposals_of_the_issue_table() -> void:
	for key: String in HU_TABLE:
		assert_str(_text(key, "hu")).override_failure_message(key).is_equal(HU_TABLE[key])


func test_ac21_no_hungarian_text_is_untranslated_or_the_key() -> void:
	for key: String in EN:
		var hungarian: String = _text(key, "hu")
		assert_str(hungarian).override_failure_message("%s (hu) is empty" % key).is_not_empty()
		assert_str(hungarian).override_failure_message("%s (hu) is the key" % key).is_not_equal(key)


# --- the open panel ---


func _open(items: ItemCatalog = null) -> bool:
	var catalog: ItemCatalog = items if items != null else Ir.catalog()
	_controls = await Ir.open(self, AquariumModel.new(), catalog)
	auto_free(_controls)
	var ok: bool = _controls != null and Ir.open_button(_controls) != null
	assert_bool(ok).override_failure_message("TankControls has no ItemsButton").is_true()
	if not ok:
		return false
	await Ir.press_open(self, _controls)
	return Ir.is_open(_controls)


func test_ac21_the_open_panel_shows_hungarian_everywhere_after_a_switch() -> void:
	if not await _open():
		return
	Ir.click_card(_controls, &"ornament_vase")
	await Ui.set_language(self, "hu")
	assert_bool(Ir.is_open(_controls)).is_true()
	assert_str(Ir.shown(Ir.open_button(_controls))).is_equal("Elemek")
	assert_str(Ir.shown(Ir.title_label(_controls))).is_equal("Elemek")
	assert_str(Ir.shown(Ir.close_button(_controls))).is_equal("Bezárás")
	var field: LineEdit = Ir.search(_controls)
	assert_str(field.atr(field.placeholder_text)).is_equal("Elemek keresése")
	var clear: Button = Ir.clear_button(_controls)
	assert_str(clear.atr(clear.tooltip_text)).is_equal("Keresés törlése")
	var expected: Array[String] = ["Mind", "Kövek", "Fa", "Díszek", "Növények"]
	for index: int in Ir.CATEGORY_NAMES.size():
		assert_str(Ir.shown(Ir.category(_controls, Ir.CATEGORY_NAMES[index]))).is_equal(
			expected[index]
		)
	for id: String in Ir.NAMES_HU:
		assert_str(Ir.name_of(_controls, StringName(id))).is_equal(Ir.NAMES_HU[id])
	assert_str(Ir.shown(Ir.card_part(_controls, &"ornament_vase", "SelectedLabel"))).is_equal(
		"Kiválasztva"
	)
	assert_str(Ir.tooltip_of(_controls, &"ornament_vase")).is_equal(Ir.DESCRIPTION_HU)


func test_ac21_a_switch_keeps_the_query_the_category_and_the_pick() -> void:
	if not await _open():
		return
	Ir.select_category(_controls, "Category_rock")
	Ir.type_text(_controls, "ő")
	Ir.click_card(_controls, &"rock_osko")
	assert_that(Ir.visible_ids(_controls)).is_equal(["rock_osko"])
	await Ui.set_language(self, "hu")
	assert_str(Ir.search(_controls).text).is_equal("ő")
	assert_that(Ir.selected_category_names(_controls)).is_equal(["Category_rock"])
	assert_str(Ir.picked_id(_controls)).is_equal("rock_osko")
	assert_that(Ir.marked_ids(_controls)).is_equal(["rock_osko"])


func test_ac21_a_switch_filters_the_list_again_with_the_names_of_the_new_language() -> void:
	if not await _open():
		return
	Ir.select_category(_controls, "Category_rock")
	Ir.type_text(_controls, "ő")
	assert_that(Ir.visible_names(_controls)).is_equal(["Őskő Rock"])
	await Ui.set_language(self, "hu")
	assert_that(Ir.visible_ids(_controls)).is_equal(["rock_slate", "rock_osko"])
	assert_that(Ir.visible_names(_controls)).is_equal(["Pala kő", "Őskő"])
	await Ui.set_language(self, "en")
	assert_that(Ir.visible_ids(_controls)).is_equal(["rock_osko"])
	assert_that(Ir.visible_names(_controls)).is_equal(["Őskő Rock"])


func test_ac21_a_switch_keeps_the_pick_events_quiet() -> void:
	if not await _open():
		return
	var listener: Ir.Listener = Ir.listen()
	Ir.click_card(_controls, &"wood_drift")
	await Ui.set_language(self, "hu")
	await Ui.set_language(self, "en")
	assert_that(listener.timeline).is_equal(["picked:wood_drift"])
	Ir.unlisten(listener)


func test_ac21_the_empty_texts_follow_the_language() -> void:
	var empty: ItemCatalog = ItemCatalog.from_definitions([] as Array[ItemDefinition])
	if not await _open(empty):
		return
	assert_str(Ir.shown(Ir.empty_label(_controls))).is_equal("No items yet.")
	await Ui.set_language(self, "hu")
	assert_str(Ir.shown(Ir.empty_label(_controls))).is_equal("Még nincsenek elemek.")
	await Ui.set_language(self, "en")
	assert_str(Ir.shown(Ir.empty_label(_controls))).is_equal("No items yet.")


func test_ac21_the_no_match_text_follows_the_language() -> void:
	if not await _open():
		return
	Ir.type_text(_controls, "zzz")
	assert_str(Ir.shown(Ir.empty_label(_controls))).is_equal("No items match your search.")
	await Ui.set_language(self, "hu")
	assert_str(Ir.shown(Ir.empty_label(_controls))).is_equal("Nincs a keresésnek megfelelő elem.")
	assert_int(Ir.visible_cards(_controls).size()).is_equal(0)


func test_ac21_switching_back_to_english_restores_the_english_panel_texts() -> void:
	if not await _open():
		return
	await Ui.set_language(self, "hu")
	await Ui.set_language(self, "en")
	assert_str(Ir.shown(Ir.title_label(_controls))).is_equal("Items")
	assert_str(Ir.shown(Ir.category(_controls, "Category_ornament"))).is_equal("Ornaments")
	assert_str(Ir.name_of(_controls, &"rock_osko")).is_equal("Őskő Rock")
	assert_str(Ir.shown(Ir.close_button(_controls))).is_equal("Close")


func test_ac21_a_switch_while_the_panel_is_closed_shows_the_new_language_on_the_next_open() -> void:
	if not await _open():
		return
	Ir.close_button(_controls).pressed.emit()
	await get_tree().process_frame
	await Ui.set_language(self, "hu")
	await Ir.press_open(self, _controls)
	assert_str(Ir.name_of(_controls, &"wood_drift")).is_equal("Uszadékfa")
	assert_str(Ir.shown(Ir.title_label(_controls))).is_equal("Elemek")
