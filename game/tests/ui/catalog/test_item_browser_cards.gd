# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #30 criteria 4 to 6, 9, 10, 12 and 13 (owner: developer): the category row, the card grid, the
## search, the clear button, the empty texts, the thumbnails, the tooltips and the placeholder.
## Tank controls on fixture items (item_browser_rig.gd: nine items, names from the fixture .po
## files in English); no engine error or warning output anywhere (ADR 0004 log gate).

const Ir := preload("res://tests/helpers/item_browser_rig.gd")
const Ui := preload("res://tests/helpers/tank_ui_rig.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")

const ALL_NAMES: Array[String] = [
	"Granite Boulder",
	"Slate Rock",
	"Őskő Rock",
	"Drift Wood",
	"Árvíz Root",
	"Blue Vase",
	"Bare Ornament",
	"Java Fern",
	"item.plant_missing.name",
]

var _saved_locale: String = ""
var _language_state: Dictionary = {}
var _translations: Array[Translation] = []
var _controls: Control = null


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()
	_language_state = Ui.begin_language_isolation("item_browser_cards")
	_translations = Ir.add_translations()
	TranslationServer.set_locale("en")


func after_test() -> void:
	Ir.remove_translations(_translations)
	Ui.end_language_isolation(_language_state, _saved_locale)


func _open(items: ItemCatalog = null) -> bool:
	var catalog: ItemCatalog = items if items != null else Ir.catalog()
	_controls = await Ir.open(self, AquariumModel.new(), catalog)
	auto_free(_controls)
	var ok: bool = _controls != null and Ir.open_button(_controls) != null
	assert_bool(ok).override_failure_message("TankControls has no ItemsButton").is_true()
	if not ok:
		return false
	await Ir.press_open(self, _controls)
	assert_bool(Ir.is_open(_controls)).override_failure_message("the panel did not open").is_true()
	return Ir.is_open(_controls)


# --- AC 4: the category row and the grid ---


func test_ac04_the_panel_has_the_category_row_the_search_field_and_the_grid_in_that_order() -> void:
	if not await _open():
		return
	var layout: Node = Ir.title_label(_controls).get_parent()
	var categories: Node = Ir.category(_controls, "Category_all").get_parent()
	var search_row: Node = Ir.search(_controls).get_parent()
	assert_object(Ir.scroll(_controls)).is_not_null()
	assert_object(Ir.cards_box(_controls)).is_not_null()
	assert_bool(Ir.scroll(_controls).is_ancestor_of(Ir.cards_box(_controls))).is_true()
	assert_int(categories.get_index()).is_less(search_row.get_index())
	assert_int(search_row.get_index()).is_less(Ir.scroll(_controls).get_index())
	assert_object(categories.get_parent()).is_same(layout)
	assert_object(Ir.scroll(_controls).get_parent()).is_same(layout)


func test_ac04_all_comes_first_then_each_category_with_items_in_the_fixed_order() -> void:
	if not await _open():
		return
	assert_that(Ir.visible_category_names(_controls)).is_equal(
		["Category_all", "Category_rock", "Category_wood", "Category_ornament", "Category_plant"]
	)
	assert_that(Ir.all_ids(_controls).size()).is_equal(9)


func test_ac04_the_category_texts_are_the_decided_english_names() -> void:
	if not await _open():
		return
	var expected: Array[String] = ["All", "Rocks", "Wood", "Ornaments", "Plants"]
	for index: int in Ir.CATEGORY_NAMES.size():
		assert_str(Ir.shown(Ir.category(_controls, Ir.CATEGORY_NAMES[index]))).is_equal(
			expected[index]
		)


func test_ac04_all_is_selected_and_lists_every_item_in_catalog_order() -> void:
	if not await _open():
		return
	assert_that(Ir.selected_category_names(_controls)).is_equal(["Category_all"])
	assert_that(Ir.visible_ids(_controls)).is_equal(Ir.order_ids())
	assert_that(Ir.visible_names(_controls)).is_equal(ALL_NAMES)


func test_ac04_a_card_shows_the_name_and_a_thumbnail_area() -> void:
	if not await _open():
		return
	var button: Button = Ir.card(_controls, &"rock_granite")
	assert_object(button).is_not_null()
	assert_str(Ir.name_of(_controls, &"rock_granite")).is_equal("Granite Boulder")
	assert_bool(Ir.card_part(_controls, &"rock_granite", "Thumbnail") is TextureRect).is_true()
	var picture: Control = Ir.card_part(_controls, &"rock_granite", "Thumbnail")
	var label: Control = Ir.card_part(_controls, &"rock_granite", "NameLabel")
	assert_float(picture.get_global_rect().position.y).is_less(label.get_global_rect().position.y)


func test_ac04_the_cards_sit_in_a_grid_inside_a_vertical_scroll() -> void:
	if not await _open():
		return
	assert_int(Ir.cards_box(_controls).columns).is_greater_equal(2)
	var scroll: ScrollContainer = Ir.scroll(_controls)
	assert_int(scroll.vertical_scroll_mode).is_not_equal(ScrollContainer.SCROLL_MODE_DISABLED)
	assert_int(scroll.horizontal_scroll_mode).is_equal(ScrollContainer.SCROLL_MODE_DISABLED)


# --- AC 5: selecting a category ---


func test_ac05_selecting_a_category_lists_only_its_items_in_order() -> void:
	if not await _open():
		return
	var expected: Dictionary = {
		"Category_rock": ["rock_granite", "rock_slate", "rock_osko"],
		"Category_wood": ["wood_drift", "wood_root"],
		"Category_ornament": ["ornament_vase", "ornament_bare"],
		"Category_plant": ["plant_fern", "plant_missing"],
	}
	for node_name: String in expected:
		Ir.select_category(_controls, node_name)
		assert_that(Ir.visible_ids(_controls)).is_equal(expected[node_name])
	Ir.select_category(_controls, "Category_all")
	assert_that(Ir.visible_ids(_controls).size()).is_equal(9)


func test_ac05_the_selected_category_has_a_drawn_mark_and_only_that_one() -> void:
	if not await _open():
		return
	for node_name: String in Ir.CATEGORY_NAMES:
		Ir.select_category(_controls, node_name)
		assert_that(Ir.selected_category_names(_controls)).is_equal([node_name])
		var mark: Control = Ir.category(_controls, node_name).find_child(
			"SelectedMark", true, false
		)
		assert_object(mark).is_not_null()
		assert_float(mark.size.x).is_greater(0.0)
		assert_float(mark.size.y).is_greater(0.0)


func test_ac05_every_category_button_has_a_selected_mark_node() -> void:
	if not await _open():
		return
	for button: Button in Ir.categories(_controls):
		assert_object(button.find_child("SelectedMark", true, false)).is_not_null()


# --- AC 6: empty categories and the empty catalog ---


func test_ac06_a_category_without_items_has_no_entry() -> void:
	if not await _open(Ir.catalog(false, [2])):
		return
	assert_that(Ir.visible_category_names(_controls)).is_equal(
		["Category_all", "Category_rock", "Category_ornament", "Category_plant"]
	)
	assert_bool(Ir.category(_controls, "Category_wood").is_visible_in_tree()).is_false()
	assert_int(Ir.all_ids(_controls).size()).is_equal(7)


func test_ac06_two_empty_categories_are_both_left_out() -> void:
	if not await _open(Ir.catalog(false, [1, 3])):
		return
	assert_that(Ir.visible_category_names(_controls)).is_equal(
		["Category_all", "Category_wood", "Category_plant"]
	)


func test_ac06_an_empty_catalog_shows_only_all_and_the_empty_text() -> void:
	var empty: ItemCatalog = ItemCatalog.from_definitions([] as Array[ItemDefinition])
	if not await _open(empty):
		return
	assert_that(Ir.visible_category_names(_controls)).is_equal(["Category_all"])
	assert_int(Ir.visible_cards(_controls).size()).is_equal(0)
	assert_bool(Ir.empty_label(_controls).is_visible_in_tree()).is_true()
	assert_str(Ir.shown(Ir.empty_label(_controls))).is_equal("No items yet.")


func test_ac06_a_catalog_with_items_does_not_show_the_empty_text() -> void:
	if not await _open():
		return
	assert_bool(Ir.empty_label(_controls).is_visible_in_tree()).is_false()


# --- AC 7 to 10: search ---


func test_ac07_typing_narrows_the_list_live_with_all_selected() -> void:
	if not await _open():
		return
	Ir.type_text(_controls, "ro")
	assert_that(Ir.visible_ids(_controls)).is_equal(["rock_slate", "rock_osko", "wood_root"])
	Ir.type_text(_controls, "roo")
	assert_that(Ir.visible_ids(_controls)).is_equal(["wood_root"])


func test_ac07_the_search_works_within_the_selected_category() -> void:
	if not await _open():
		return
	Ir.select_category(_controls, "Category_rock")
	Ir.type_text(_controls, "ro")
	assert_that(Ir.visible_ids(_controls)).is_equal(["rock_slate", "rock_osko"])
	Ir.select_category(_controls, "Category_wood")
	assert_that(Ir.visible_ids(_controls)).is_equal(["wood_root"])


func test_ac07_the_letter_case_of_the_query_does_not_matter() -> void:
	if not await _open():
		return
	Ir.type_text(_controls, "SLATE")
	assert_that(Ir.visible_ids(_controls)).is_equal(["rock_slate"])
	Ir.type_text(_controls, "sLaTe")
	assert_that(Ir.visible_ids(_controls)).is_equal(["rock_slate"])


func test_ac07_leading_and_trailing_spaces_are_ignored_and_inner_spaces_are_kept() -> void:
	if not await _open():
		return
	Ir.type_text(_controls, "  drift  ")
	assert_that(Ir.visible_ids(_controls)).is_equal(["wood_drift"])
	Ir.type_text(_controls, "drift w")
	assert_that(Ir.visible_ids(_controls)).is_equal(["wood_drift"])
	Ir.type_text(_controls, "driftw")
	assert_that(Ir.visible_ids(_controls)).is_equal([])


func test_ac07_the_search_uses_the_name_in_the_current_language_not_the_key_or_the_id() -> void:
	if not await _open():
		return
	Ir.type_text(_controls, "item.")
	assert_that(Ir.visible_ids(_controls)).is_equal(["plant_missing"])
	Ir.type_text(_controls, "rock_")
	assert_that(Ir.visible_ids(_controls)).is_equal([])


func test_ac07_accents_are_not_folded() -> void:
	if not await _open():
		return
	Ir.type_text(_controls, "ko")
	assert_that(Ir.visible_ids(_controls)).is_equal([])
	Ir.type_text(_controls, "osko")
	assert_that(Ir.visible_ids(_controls)).is_equal([])
	Ir.type_text(_controls, "arviz")
	assert_that(Ir.visible_ids(_controls)).is_equal([])


func test_ac08_the_capital_and_the_small_hungarian_letter_find_the_same_item() -> void:
	if not await _open():
		return
	for query: String in ["Ő", "ő"]:
		Ir.type_text(_controls, query)
		assert_that(Ir.visible_ids(_controls)).is_equal(["rock_osko"])
	for query: String in ["Á", "á"]:
		Ir.type_text(_controls, query)
		assert_that(Ir.visible_ids(_controls)).is_equal(["wood_root"])


func test_ac08_a_search_of_only_spaces_shows_the_full_list() -> void:
	if not await _open():
		return
	Ir.type_text(_controls, "ro")
	Ir.type_text(_controls, "     ")
	assert_that(Ir.visible_ids(_controls).size()).is_equal(9)
	assert_bool(Ir.empty_label(_controls).is_visible_in_tree()).is_false()
	Ir.select_category(_controls, "Category_wood")
	assert_that(Ir.visible_ids(_controls)).is_equal(["wood_drift", "wood_root"])


func test_ac09_a_search_without_a_match_shows_the_text_and_no_card() -> void:
	if not await _open():
		return
	Ir.type_text(_controls, "zzz")
	assert_int(Ir.visible_cards(_controls).size()).is_equal(0)
	assert_bool(Ir.empty_label(_controls).is_visible_in_tree()).is_true()
	assert_str(Ir.shown(Ir.empty_label(_controls))).is_equal("No items match your search.")


func test_ac09_the_category_row_and_the_search_field_stay_usable_after_no_match() -> void:
	if not await _open():
		return
	Ir.type_text(_controls, "zzz")
	for button: Button in Ir.categories(_controls):
		assert_bool(button.is_visible_in_tree()).is_true()
		assert_bool(button.disabled).is_false()
	var field: LineEdit = Ir.search(_controls)
	assert_bool(field.is_visible_in_tree()).is_true()
	assert_bool(field.editable).is_true()
	Ir.select_category(_controls, "Category_rock")
	assert_str(Ir.search(_controls).text).is_equal("zzz")
	assert_int(Ir.visible_cards(_controls).size()).is_equal(0)
	Ir.type_text(_controls, "slate")
	assert_that(Ir.visible_ids(_controls)).is_equal(["rock_slate"])
	assert_bool(Ir.empty_label(_controls).is_visible_in_tree()).is_false()


func test_ac10_the_clear_button_empties_the_field_and_restores_the_list() -> void:
	if not await _open():
		return
	Ir.select_category(_controls, "Category_rock")
	Ir.type_text(_controls, "slate")
	assert_that(Ir.visible_ids(_controls)).is_equal(["rock_slate"])
	Ir.clear_button(_controls).pressed.emit()
	assert_str(Ir.search(_controls).text).is_equal("")
	assert_that(Ir.visible_ids(_controls)).is_equal(["rock_granite", "rock_slate", "rock_osko"])


func test_ac10_the_clear_button_after_no_match_restores_the_list_and_hides_the_text() -> void:
	if not await _open():
		return
	Ir.type_text(_controls, "zzz")
	Ir.clear_button(_controls).pressed.emit()
	assert_that(Ir.visible_ids(_controls).size()).is_equal(9)
	assert_bool(Ir.empty_label(_controls).is_visible_in_tree()).is_false()


func test_ac10_emptying_the_field_by_hand_restores_the_list() -> void:
	if not await _open():
		return
	Ir.type_text(_controls, "ro")
	Ir.type_text(_controls, "")
	assert_that(Ir.visible_ids(_controls).size()).is_equal(9)


func test_ac10_the_clear_button_has_the_clear_tooltip_and_an_icon() -> void:
	if not await _open():
		return
	var button: Button = Ir.clear_button(_controls)
	assert_str(button.atr(button.tooltip_text)).is_equal("Clear search")
	assert_object(button.icon).is_not_null()


func test_ac10_the_search_field_has_the_placeholder_text() -> void:
	if not await _open():
		return
	var field: LineEdit = Ir.search(_controls)
	assert_str(field.atr(field.placeholder_text)).is_equal("Search items")


func test_ac10_changing_the_category_keeps_the_search_text_and_applies_it() -> void:
	if not await _open():
		return
	Ir.type_text(_controls, "ro")
	Ir.select_category(_controls, "Category_wood")
	assert_str(Ir.search(_controls).text).is_equal("ro")
	assert_that(Ir.visible_ids(_controls)).is_equal(["wood_root"])
	Ir.select_category(_controls, "Category_rock")
	assert_str(Ir.search(_controls).text).is_equal("ro")
	assert_that(Ir.visible_ids(_controls)).is_equal(["rock_slate", "rock_osko"])


# --- AC 12: thumbnails and tooltips ---


func test_ac12_a_card_with_a_thumbnail_shows_it_in_a_mipmap_filtered_texture_rect() -> void:
	if not await _open():
		return
	var definition: ItemDefinition = Ir.catalog().get_definition(&"rock_granite")
	assert_object(definition.thumbnail).is_not_null()
	for id: StringName in [&"rock_granite", &"rock_osko", &"wood_drift", &"plant_fern"]:
		var picture: TextureRect = Ir.card_part(_controls, id, "Thumbnail") as TextureRect
		assert_object(picture).override_failure_message("%s has no Thumbnail" % id).is_not_null()
		assert_bool(Ir.thumbnail_shown(_controls, id)).is_true()
		assert_object(picture.texture).is_not_null()
		assert_int(picture.texture.get_width()).is_equal(256)
		assert_int(picture.texture.get_height()).is_equal(256)
		assert_int(picture.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS)


func test_ac12_the_thumbnail_is_scaled_into_the_card_and_keeps_its_aspect() -> void:
	if not await _open():
		return
	var picture: TextureRect = Ir.card_part(_controls, &"rock_granite", "Thumbnail") as TextureRect
	assert_int(picture.expand_mode).is_equal(TextureRect.EXPAND_IGNORE_SIZE)
	assert_int(picture.stretch_mode).is_equal(TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	assert_float(picture.custom_minimum_size.x).is_greater(0.0)
	assert_float(picture.custom_minimum_size.x).is_less(256.0)


func test_ac12_the_card_shows_the_translated_name() -> void:
	if not await _open():
		return
	for id: String in Ir.NAMES_EN:
		assert_str(Ir.name_of(_controls, StringName(id))).is_equal(Ir.NAMES_EN[id])


func test_ac12_hovering_or_focusing_the_card_shows_the_description_as_tooltip() -> void:
	if not await _open():
		return
	assert_str(Ir.tooltip_of(_controls, &"ornament_vase")).is_equal(Ir.DESCRIPTION_EN)
	assert_str(Ir.tooltip_of(_controls, &"plant_fern")).is_equal("A fern for testing.")


func test_ac12_a_card_without_a_description_key_has_no_tooltip() -> void:
	if not await _open():
		return
	for id: StringName in [&"ornament_bare", &"rock_granite", &"plant_missing", &"wood_drift"]:
		(
			assert_str(Ir.card(_controls, id).tooltip_text)
			. override_failure_message(String(id))
			. is_empty()
		)


func test_ac12_the_tooltip_follows_the_language() -> void:
	if not await _open():
		return
	await Ui.set_language(self, "hu")
	assert_str(Ir.tooltip_of(_controls, &"ornament_vase")).is_equal(Ir.DESCRIPTION_HU)


func test_ac12_a_fixture_with_mode_2_values_gives_the_same_cards_as_one_with_defaults() -> void:
	if not await _open(Ir.catalog(true)):
		return
	assert_that(Ir.visible_ids(_controls)).is_equal(Ir.order_ids())
	assert_that(Ir.visible_names(_controls)).is_equal(ALL_NAMES)
	assert_that(Ir.visible_category_names(_controls)).is_equal(
		["Category_all", "Category_rock", "Category_wood", "Category_ornament", "Category_plant"]
	)
	assert_str(Ir.tooltip_of(_controls, &"ornament_vase")).is_equal(Ir.DESCRIPTION_EN)
	assert_bool(Ir.thumbnail_shown(_controls, &"rock_granite")).is_true()
	assert_bool(Ir.placeholder_shown(_controls, &"rock_slate")).is_true()
	Ir.type_text(_controls, "ro")
	assert_that(Ir.visible_ids(_controls)).is_equal(["rock_slate", "rock_osko", "wood_root"])


# --- AC 13: placeholders and the missing name ---


func test_ac13_a_card_without_a_thumbnail_shows_the_placeholder() -> void:
	if not await _open():
		return
	assert_bool(Ir.placeholder_shown(_controls, &"rock_slate")).is_true()
	assert_bool(Ir.thumbnail_shown(_controls, &"rock_slate")).is_false()
	assert_str(Ir.name_of(_controls, &"rock_slate")).is_equal("Slate Rock")


func test_ac13_a_card_with_an_unusable_zero_size_thumbnail_shows_the_placeholder() -> void:
	if not await _open():
		return
	assert_bool(Ir.placeholder_shown(_controls, &"wood_root")).is_true()
	assert_bool(Ir.thumbnail_shown(_controls, &"wood_root")).is_false()
	assert_str(Ir.name_of(_controls, &"wood_root")).is_equal("Árvíz Root")


func test_ac13_the_placeholder_is_a_drawn_style_box_and_a_card_with_a_thumbnail_has_none() -> void:
	if not await _open():
		return
	for id: StringName in [&"rock_slate", &"wood_root"]:
		var stand_in: Control = Ir.card_part(_controls, id, "Placeholder")
		assert_bool(stand_in is Panel).override_failure_message("%s Placeholder" % id).is_true()
		assert_bool(stand_in.get_theme_stylebox("panel") is StyleBoxFlat).is_true()
		assert_int(stand_in.mouse_filter).is_not_equal(Control.MOUSE_FILTER_STOP)
	assert_bool(Ir.placeholder_shown(_controls, &"rock_granite")).is_false()


func test_ac13_a_missing_name_translation_shows_the_key_itself() -> void:
	if not await _open():
		return
	assert_str(Ir.name_of(_controls, &"plant_missing")).is_equal("item.plant_missing.name")
	await Ui.set_language(self, "hu")
	assert_str(Ir.name_of(_controls, &"plant_missing")).is_equal("item.plant_missing.name")


func test_ac13_a_missing_thumbnail_and_a_missing_name_log_no_error_or_warning() -> void:
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void:
			var opened: bool = await _open()
			if opened:
				Ir.type_text(_controls, "ro")
				Ir.type_text(_controls, "")
				Ir.select_category(_controls, "Category_plant")
				Ir.click_card(_controls, &"plant_missing")
				await Ui.set_language(self, "hu")
	)
	assert_dict(seen["errors"]).is_empty()
	assert_dict(seen["warnings"]).is_empty()
	assert_dict(seen["script_errors"]).is_empty()


func test_ac13_a_catalog_of_only_unusable_thumbnails_logs_nothing() -> void:
	var list: Array[ItemDefinition] = [
		Ir.make_definition(&"only_none", 1, 1, "none"),
		Ir.make_definition(&"only_empty", 1, 2, "empty"),
	]
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void: await _open(ItemCatalog.from_definitions(list))
	)
	assert_dict(seen["errors"]).is_empty()
	assert_dict(seen["warnings"]).is_empty()
	assert_dict(seen["script_errors"]).is_empty()
	assert_that(Ir.visible_ids(_controls)).is_equal(["only_none", "only_empty"])
	assert_bool(Ir.placeholder_shown(_controls, &"only_none")).is_true()
	assert_bool(Ir.placeholder_shown(_controls, &"only_empty")).is_true()


func test_ac06_an_empty_catalog_logs_no_error_or_warning() -> void:
	var empty: ItemCatalog = ItemCatalog.from_definitions([] as Array[ItemDefinition])
	var seen: Dictionary = await EngineOutput.capture_all(func() -> void: await _open(empty))
	assert_dict(seen["errors"]).is_empty()
	assert_dict(seen["warnings"]).is_empty()
	assert_dict(seen["script_errors"]).is_empty()


# --- the loader feeds the browser ---


func test_ac05_items_loaded_from_fixture_files_fill_the_browser_in_loader_order() -> void:
	var loaded: ItemCatalog = ItemCatalog.load_dirs(["res://tests/fixtures/items/valid"])
	if not await _open(loaded):
		return
	var expected: Array[String] = []
	for id: StringName in loaded.get_ids():
		expected.append(String(id))
	assert_int(expected.size()).is_greater(0)
	assert_that(Ir.visible_ids(_controls)).is_equal(expected)
