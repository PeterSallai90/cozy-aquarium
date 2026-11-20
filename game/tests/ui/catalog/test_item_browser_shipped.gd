extends GdUnitTestSuite
## #30 criterion 24 and the first-open load of criterion 23 (owner: developer), extended by #157
## criteria 17 and 18 (owner: developer): the game's tank controls get no item catalog (the three-
## and four-argument setup of today), so the browser loads the shipped folders itself on the first
## open. With the three starter items of #157 (river_stone, driftwood_branch, clay_amphora) the
## panel shows the category row All, Rocks, Wood, Ornaments, the three cards in catalog order
## (River stone, Driftwood branch, Clay amphora) with thumbnail and name, the Hungarian names after
## a language switch, and the search "amf" and "ko". The empty-state test of #30 still returns
## early while the folders hold items, and the ids are compared with the shipped catalog, so a
## later content issue adds items without breaking the order and per-item checks; only the exact
## category row is then adjusted by #41 or #42 (plants).
##
## Group that makes the #157 tests pass: developer (after the technical-artist files exist: the
## catalog .tres files, the scene wrappers, the thumbnails and the translations).

const Ir := preload("res://tests/helpers/item_browser_rig.gd")
const Ui := preload("res://tests/helpers/tank_ui_rig.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")

const STARTER_IDS: Array[String] = ["river_stone", "driftwood_branch", "clay_amphora"]
const STARTER_NAMES_EN: Array[String] = ["River stone", "Driftwood branch", "Clay amphora"]
const STARTER_NAMES_HU: Array[String] = ["Folyami kő", "Uszadékfa ág", "Agyag amfora"]
const CATEGORY_OF: Dictionary[String, String] = {
	"river_stone": "Category_rock",
	"driftwood_branch": "Category_wood",
	"clay_amphora": "Category_ornament",
}

var _saved_locale: String = ""
var _language_state: Dictionary = {}
var _controls: Control = null


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()
	_language_state = Ui.begin_language_isolation("item_browser_shipped")
	TranslationServer.set_locale("en")


func after_test() -> void:
	Ui.end_language_isolation(_language_state, _saved_locale)


func _build() -> bool:
	_controls = await Ir.open_shipped(self, AquariumModel.new())
	auto_free(_controls)
	var ok: bool = _controls != null and Ir.open_button(_controls) != null
	assert_bool(ok).override_failure_message("TankControls has no ItemsButton").is_true()
	return ok


func _shipped_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: StringName in ItemCatalog.load_dirs().get_ids():
		ids.append(String(id))
	return ids


func test_ac24_the_shipped_panel_lists_exactly_the_shipped_items() -> void:
	if not await _build():
		return
	await Ir.press_open(self, _controls)
	assert_bool(Ir.is_open(_controls)).is_true()
	assert_that(Ir.visible_ids(_controls)).is_equal(_shipped_ids())
	assert_that(Ir.all_ids(_controls)).is_equal(_shipped_ids())


func test_ac24_with_the_folders_empty_the_panel_shows_all_and_no_items_yet() -> void:
	if not _shipped_ids().is_empty():
		return
	if not await _build():
		return
	await Ir.press_open(self, _controls)
	assert_that(Ir.visible_category_names(_controls)).is_equal(["Category_all"])
	assert_that(Ir.selected_category_names(_controls)).is_equal(["Category_all"])
	assert_int(Ir.visible_cards(_controls).size()).is_equal(0)
	assert_bool(Ir.empty_label(_controls).is_visible_in_tree()).is_true()
	assert_str(Ir.shown(Ir.empty_label(_controls))).is_equal("No items yet.")
	assert_str(Ir.shown(Ir.category(_controls, "Category_all"))).is_equal("All")


func test_ac24_no_card_exists_before_the_first_open() -> void:
	if not await _build():
		return
	assert_int(Ir.cards_box(_controls).get_child_count()).is_equal(0)


func test_ac24_opening_the_shipped_panel_logs_no_error_or_warning() -> void:
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void:
			if await _build():
				await Ir.press_open(self, _controls)
				Ir.type_text(_controls, "ro")
				Ir.type_text(_controls, "")
	)
	assert_dict(seen["errors"]).is_empty()
	assert_dict(seen["warnings"]).is_empty()
	assert_dict(seen["script_errors"]).is_empty()


func test_ac24_the_shipped_panel_can_be_opened_closed_and_reopened() -> void:
	if not await _build():
		return
	await Ir.press_open(self, _controls)
	Ir.close_button(_controls).pressed.emit()
	await get_tree().process_frame
	assert_bool(Ir.is_open(_controls)).is_false()
	await Ir.press_open(self, _controls)
	assert_bool(Ir.is_open(_controls)).is_true()


func test_ac24_main_shows_the_panel_without_an_item_catalog_injected() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	auto_free(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var controls: Control = main.get_node("Hud/TankControls") as Control
	(
		assert_object(Ir.open_button(controls))
		. override_failure_message("no Items button")
		. is_not_null()
	)
	if Ir.open_button(controls) == null:
		return
	assert_int(Ir.cards_box(controls).get_child_count()).is_equal(0)
	await Ir.press_open(self, controls)
	assert_bool(Ir.is_open(controls)).is_true()
	assert_that(Ir.visible_ids(controls)).is_equal(_shipped_ids())


# --- #157 criteria 17 and 18: the three starter items ---


func _open_panel() -> bool:
	if not await _build():
		return false
	await Ir.press_open(self, _controls)
	assert_bool(Ir.is_open(_controls)).is_true()
	return Ir.is_open(_controls)


func test_ac17_the_empty_state_no_longer_shows_with_the_starter_items() -> void:
	if not await _open_panel():
		return
	assert_bool(Ir.empty_label(_controls).is_visible_in_tree()).is_false()
	assert_int(Ir.visible_cards(_controls).size()).is_greater_equal(STARTER_IDS.size())


func test_ac17_the_category_row_is_all_rocks_wood_ornaments_and_no_plants() -> void:
	if not await _open_panel():
		return
	assert_that(Ir.visible_category_names(_controls)).is_equal(
		["Category_all", "Category_rock", "Category_wood", "Category_ornament"]
	)
	assert_str(Ir.shown(Ir.category(_controls, "Category_all"))).is_equal("All")
	assert_str(Ir.shown(Ir.category(_controls, "Category_rock"))).is_equal("Rocks")
	assert_str(Ir.shown(Ir.category(_controls, "Category_wood"))).is_equal("Wood")
	assert_str(Ir.shown(Ir.category(_controls, "Category_ornament"))).is_equal("Ornaments")


func test_ac17_all_lists_river_stone_driftwood_branch_and_clay_amphora_in_that_order() -> void:
	if not await _open_panel():
		return
	var shown: Array[String] = []
	for id: String in Ir.visible_ids(_controls):
		if STARTER_IDS.has(id):
			shown.append(id)
	assert_that(shown).is_equal(STARTER_IDS)
	(
		assert_that(
			Ir.visible_names(_controls).filter(
				func(n: String) -> bool: return STARTER_NAMES_EN.has(n)
			)
		)
		. is_equal(STARTER_NAMES_EN)
	)


func test_ac17_each_card_shows_a_thumbnail_and_its_english_name() -> void:
	if not await _open_panel():
		return
	for index: int in STARTER_IDS.size():
		var id: StringName = StringName(STARTER_IDS[index])
		assert_str(Ir.name_of(_controls, id)).is_equal(STARTER_NAMES_EN[index])
		(
			assert_bool(Ir.thumbnail_shown(_controls, id))
			. override_failure_message("%s: no thumbnail shown" % id)
			. is_true()
		)
		assert_bool(Ir.placeholder_shown(_controls, id)).is_false()


func test_ac17_each_category_lists_its_item_with_thumbnail_and_name() -> void:
	if not await _open_panel():
		return
	for index: int in STARTER_IDS.size():
		var id: String = STARTER_IDS[index]
		Ir.select_category(_controls, CATEGORY_OF[id])
		await get_tree().process_frame
		assert_array(Ir.visible_ids(_controls)).override_failure_message(id).contains([id])
		assert_str(Ir.name_of(_controls, StringName(id))).is_equal(STARTER_NAMES_EN[index])
		assert_bool(Ir.thumbnail_shown(_controls, StringName(id))).is_true()
		for other: String in STARTER_IDS:
			if other != id and CATEGORY_OF[other] != CATEGORY_OF[id]:
				assert_array(Ir.visible_ids(_controls)).not_contains([other])


func test_ac18_in_hungarian_the_cards_show_the_hungarian_names() -> void:
	if not await _open_panel():
		return
	await Ui.set_language(self, "hu")
	for index: int in STARTER_IDS.size():
		assert_str(Ir.name_of(_controls, StringName(STARTER_IDS[index]))).is_equal(
			STARTER_NAMES_HU[index]
		)


func test_ac18_in_hungarian_the_search_amf_finds_the_amphora() -> void:
	if not await _open_panel():
		return
	await Ui.set_language(self, "hu")
	Ir.type_text(_controls, "amf")
	assert_array(Ir.visible_ids(_controls)).contains(["clay_amphora"])
	assert_array(Ir.visible_ids(_controls)).not_contains(["river_stone"])
	assert_array(Ir.visible_ids(_controls)).not_contains(["driftwood_branch"])


func test_ac18_in_hungarian_the_search_ko_without_the_accent_does_not_find_folyami_ko() -> void:
	if not await _open_panel():
		return
	await Ui.set_language(self, "hu")
	# The card exists and is named "Folyami kő" (with the accent), so the search below can bite.
	assert_str(Ir.name_of(_controls, &"river_stone")).is_equal("Folyami kő")
	Ir.type_text(_controls, "ko")
	assert_array(Ir.visible_ids(_controls)).not_contains(["river_stone"])


func test_ac18_in_hungarian_the_search_ko_with_the_accent_finds_folyami_ko() -> void:
	if not await _open_panel():
		return
	await Ui.set_language(self, "hu")
	Ir.type_text(_controls, "kő")
	assert_array(Ir.visible_ids(_controls)).contains(["river_stone"])
