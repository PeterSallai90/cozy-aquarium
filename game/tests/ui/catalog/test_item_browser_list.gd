# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #30 criteria 4 to 10 as pure logic (owner: developer), no scene and no TranslationServer: the
## helper ItemBrowserList (res://ui/catalog/item_browser_list.gd, plan 3.1) gets the translated
## names as a Dictionary[StringName, String]. Fixture items come from item_browser_rig.gd, names
## from its NAMES_EN table (written out by hand, never computed with the code under test).
## Decisions where the plan is silent: normalise_query("  Ő x ") gives "ő x"; matches() lower-cases
## the display name itself and expects a normalised query; the result of filter() for a name that
## is missing in `names` is not tested.

const Ir := preload("res://tests/helpers/item_browser_rig.gd")

const ALL := 0
const ROCK := 1
const WOOD := 2
const ORNAMENT := 3
const PLANT := 4


func _ready_check() -> bool:
	(
		assert_bool(Ir.list_exists())
		. override_failure_message("res://ui/catalog/item_browser_list.gd is missing")
		. is_true()
	)
	return Ir.list_exists()


func _names() -> Dictionary:
	return Ir.NAMES_EN


func _filter(category: int, query: String, catalog: ItemCatalog = null) -> Variant:
	var used: ItemCatalog = catalog if catalog != null else Ir.catalog()
	return Ir.filter(used, _names(), category, query)


# --- constants and normalisation ---


func test_ac04_all_is_the_unset_category_and_the_order_is_rock_wood_ornament_plant() -> void:
	if not _ready_check():
		return
	assert_int(Ir.all_value()).is_equal(ItemDefinition.Category.UNSET)
	(
		assert_array(Ir.category_order())
		. is_equal(
			[
				ItemDefinition.Category.ROCK,
				ItemDefinition.Category.WOOD,
				ItemDefinition.Category.ORNAMENT,
				ItemDefinition.Category.PLANT,
			]
		)
	)


func test_ac07_normalise_strips_the_ends_and_lower_cases() -> void:
	if not _ready_check():
		return
	assert_that(Ir.normalise("  Ro  ")).is_equal("ro")
	assert_that(Ir.normalise("Ro")).is_equal("ro")
	assert_that(Ir.normalise("")).is_equal("")


func test_ac07_normalise_keeps_spaces_inside_the_text() -> void:
	if not _ready_check():
		return
	assert_that(Ir.normalise(" Drift  Wood ")).is_equal("drift  wood")


func test_ac08_normalise_lower_cases_the_hungarian_letters() -> void:
	if not _ready_check():
		return
	assert_that(Ir.normalise("Ő")).is_equal("ő")
	assert_that(Ir.normalise("Á")).is_equal("á")
	assert_that(Ir.normalise("ŐSKŐ ÁRVÍZ")).is_equal("őskő árvíz")


func test_ac08_normalise_turns_a_text_of_only_spaces_into_the_empty_text() -> void:
	if not _ready_check():
		return
	assert_that(Ir.normalise("   ")).is_equal("")
	assert_that(Ir.normalise(" \t ")).is_equal("")


# --- matches ---


func test_ac07_the_empty_query_matches_every_name() -> void:
	if not _ready_check():
		return
	assert_that(Ir.matches("Slate Rock", "")).is_equal(true)
	assert_that(Ir.matches("", "")).is_equal(true)


func test_ac07_matches_is_a_substring_test_ignoring_the_case_of_the_name() -> void:
	if not _ready_check():
		return
	assert_that(Ir.matches("Slate Rock", "ro")).is_equal(true)
	assert_that(Ir.matches("Slate Rock", "slate")).is_equal(true)
	assert_that(Ir.matches("Slate Rock", "rock")).is_equal(true)
	assert_that(Ir.matches("Slate Rock", "ck")).is_equal(true)
	assert_that(Ir.matches("Slate Rock", "zz")).is_equal(false)
	assert_that(Ir.matches("Slate Rock", "rocks")).is_equal(false)


func test_ac07_matches_keeps_inner_spaces_significant() -> void:
	if not _ready_check():
		return
	assert_that(Ir.matches("Drift Wood", "ft w")).is_equal(true)
	assert_that(Ir.matches("Drift Wood", "iftw")).is_equal(false)
	assert_that(Ir.matches("Drift Wood", "ft  w")).is_equal(false)


func test_ac08_matches_the_capital_and_the_small_hungarian_letter_alike() -> void:
	if not _ready_check():
		return
	assert_that(Ir.matches("Őskő Rock", "ő")).is_equal(true)
	assert_that(Ir.matches("őskő rock", "ő")).is_equal(true)
	assert_that(Ir.matches("Árvíz Root", "á")).is_equal(true)
	assert_that(Ir.matches("árvíz root", "á")).is_equal(true)


func test_ac07_matches_does_not_fold_accents() -> void:
	if not _ready_check():
		return
	assert_that(Ir.matches("Pala kő", "ko")).is_equal(false)
	assert_that(Ir.matches("Őskő", "osko")).is_equal(false)
	assert_that(Ir.matches("Árvíz", "arviz")).is_equal(false)
	assert_that(Ir.matches("Pala ko", "kő")).is_equal(false)


# --- visible_categories ---


func test_ac04_all_comes_first_then_every_category_with_items_in_the_fixed_order() -> void:
	if not _ready_check():
		return
	assert_that(Ir.visible_categories(Ir.catalog())).is_equal([ALL, ROCK, WOOD, ORNAMENT, PLANT])


func test_ac06_a_category_without_items_is_left_out() -> void:
	if not _ready_check():
		return
	assert_that(Ir.visible_categories(Ir.catalog(false, [WOOD]))).is_equal(
		[ALL, ROCK, ORNAMENT, PLANT]
	)
	assert_that(Ir.visible_categories(Ir.catalog(false, [ROCK, ORNAMENT]))).is_equal(
		[ALL, WOOD, PLANT]
	)


func test_ac06_an_empty_catalog_has_only_all() -> void:
	if not _ready_check():
		return
	var empty: ItemCatalog = ItemCatalog.from_definitions([] as Array[ItemDefinition])
	assert_that(Ir.visible_categories(empty)).is_equal([ALL])


# --- filter: order and categories ---


func test_ac05_all_lists_every_item_in_catalog_order() -> void:
	if not _ready_check():
		return
	var expected: Array[String] = [
		"rock_granite",
		"rock_slate",
		"rock_osko",
		"wood_drift",
		"wood_root",
		"ornament_vase",
		"ornament_bare",
		"plant_fern",
		"plant_missing",
	]
	assert_that(_filter(ALL, "")).is_equal(expected)


func test_ac05_a_category_lists_its_items_by_sort_order_then_id() -> void:
	if not _ready_check():
		return
	assert_that(_filter(ROCK, "")).is_equal(["rock_granite", "rock_slate", "rock_osko"])
	assert_that(_filter(WOOD, "")).is_equal(["wood_drift", "wood_root"])
	assert_that(_filter(ORNAMENT, "")).is_equal(["ornament_vase", "ornament_bare"])
	assert_that(_filter(PLANT, "")).is_equal(["plant_fern", "plant_missing"])


func test_ac05_the_order_does_not_depend_on_the_input_order() -> void:
	if not _ready_check():
		return
	var reversed: Array[ItemDefinition] = Ir.definitions()
	reversed.reverse()
	var catalog: ItemCatalog = ItemCatalog.from_definitions(reversed)
	assert_that(_filter(ALL, "", catalog)).is_equal(_filter(ALL, ""))


# --- filter: search ---


func test_ac07_a_query_narrows_the_list_in_catalog_order() -> void:
	if not _ready_check():
		return
	assert_that(_filter(ALL, "ro")).is_equal(["rock_slate", "rock_osko", "wood_root"])
	assert_that(_filter(ALL, "RO")).is_equal(["rock_slate", "rock_osko", "wood_root"])
	assert_that(_filter(ALL, "va")).is_equal(["ornament_vase", "plant_fern"])


func test_ac07_a_query_works_within_the_selected_category() -> void:
	if not _ready_check():
		return
	assert_that(_filter(ROCK, "ro")).is_equal(["rock_slate", "rock_osko"])
	assert_that(_filter(WOOD, "ro")).is_equal(["wood_root"])
	assert_that(_filter(ORNAMENT, "ro")).is_equal([])
	assert_that(_filter(PLANT, "va")).is_equal(["plant_fern"])


func test_ac07_leading_and_trailing_spaces_are_ignored_and_inner_spaces_kept() -> void:
	if not _ready_check():
		return
	assert_that(_filter(ALL, "  rock  ")).is_equal(["rock_slate", "rock_osko"])
	assert_that(_filter(ALL, "drift w")).is_equal(["wood_drift"])
	assert_that(_filter(ALL, " ft W ")).is_equal(["wood_drift"])
	assert_that(_filter(ALL, "iftw")).is_equal([])


func test_ac08_the_capital_and_the_small_hungarian_letter_find_the_same_item() -> void:
	if not _ready_check():
		return
	assert_that(_filter(ALL, "Ő")).is_equal(["rock_osko"])
	assert_that(_filter(ALL, "ő")).is_equal(["rock_osko"])
	assert_that(_filter(ALL, "Á")).is_equal(["wood_root"])
	assert_that(_filter(ALL, "á")).is_equal(["wood_root"])
	assert_that(_filter(ALL, "ŐSKŐ")).is_equal(["rock_osko"])


func test_ac08_a_search_of_only_spaces_equals_the_empty_search() -> void:
	if not _ready_check():
		return
	assert_that(_filter(ALL, "   ")).is_equal(_filter(ALL, ""))
	assert_that(_filter(ROCK, "  ")).is_equal(_filter(ROCK, ""))


func test_ac07_accents_are_not_folded_in_the_list() -> void:
	if not _ready_check():
		return
	assert_that(_filter(ALL, "ko")).is_equal([])
	assert_that(_filter(ALL, "osko")).is_equal([])
	assert_that(_filter(ALL, "arviz")).is_equal([])
	var hungarian: Dictionary = Ir.NAMES_HU
	assert_that(Ir.filter(Ir.catalog(), hungarian, ALL, "ko")).is_equal([])
	assert_that(Ir.filter(Ir.catalog(), hungarian, ALL, "kő")).is_equal(["rock_slate", "rock_osko"])


func test_ac07_the_search_uses_the_names_it_is_given_not_the_ids() -> void:
	if not _ready_check():
		return
	# "granite" is in the id and in the name; "gránit" only in the Hungarian name.
	assert_that(_filter(ALL, "granite")).is_equal(["rock_granite"])
	assert_that(Ir.filter(Ir.catalog(), Ir.NAMES_HU, ALL, "granite")).is_equal([])
	assert_that(Ir.filter(Ir.catalog(), Ir.NAMES_HU, ALL, "gránit")).is_equal(["rock_granite"])


func test_ac13_an_item_with_a_missing_translation_is_found_by_its_key() -> void:
	if not _ready_check():
		return
	assert_that(_filter(ALL, "plant_missing")).is_equal(["plant_missing"])


func test_ac09_a_query_without_a_match_gives_an_empty_result() -> void:
	if not _ready_check():
		return
	assert_that(_filter(ALL, "zzz")).is_equal([])
	assert_that(_filter(ROCK, "fern")).is_equal([])


func test_ac06_an_empty_catalog_gives_an_empty_result() -> void:
	if not _ready_check():
		return
	var empty: ItemCatalog = ItemCatalog.from_definitions([] as Array[ItemDefinition])
	assert_that(_filter(ALL, "", empty)).is_equal([])
	assert_that(_filter(ALL, "ro", empty)).is_equal([])
	assert_that(_filter(ROCK, "", empty)).is_equal([])


func test_ac06_a_category_with_no_item_gives_an_empty_result() -> void:
	if not _ready_check():
		return
	var no_wood: ItemCatalog = Ir.catalog(false, [WOOD])
	assert_that(_filter(WOOD, "", no_wood)).is_equal([])


# --- Mode 2 fields are not read ---


func test_ac12_a_fixture_with_mode_2_values_filled_gives_the_same_result_as_the_defaults() -> void:
	if not _ready_check():
		return
	var filled: ItemCatalog = Ir.catalog(true)
	for category: int in [ALL, ROCK, WOOD, ORNAMENT, PLANT]:
		for query: String in ["", "ro", "va", "ő", "zzz"]:
			assert_that(_filter(category, query, filled)).is_equal(_filter(category, query))
	assert_that(Ir.visible_categories(filled)).is_equal(Ir.visible_categories(Ir.catalog()))


func test_ac05_the_helper_reads_the_catalog_loaded_from_fixture_files() -> void:
	if not _ready_check():
		return
	var loaded: ItemCatalog = ItemCatalog.load_dirs(["res://tests/fixtures/items/valid"])
	var names: Dictionary = {}
	for id: StringName in loaded.get_ids():
		names[String(id)] = String(id)
	var shown: Variant = Ir.filter(loaded, names, ALL, "")
	var expected: Array[String] = []
	for id: StringName in loaded.get_ids():
		expected.append(String(id))
	assert_that(shown).is_equal(expected)
	assert_int(expected.size()).is_greater(0)
