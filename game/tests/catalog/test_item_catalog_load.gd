# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #152 criteria 4, 5, 7 and 8 (owner: developer): ItemCatalog loads item folders, orders the ids,
## answers by id and by category, keeps the first of two equal ids and ignores the folder name.
## The engine log of these cases is checked at run level (check_godot_log.py, ADR 0004).

const Items := preload("res://tests/helpers/item_api.gd")
const EMPTY_DIR := "res://tests/fixtures/items/_empty_runtime"

## Catalog order of the valid fixture folder: category, then sort_order, then id.
const VALID_ORDER: Array[String] = [
	"rock_zeta",
	"rock_a",
	"rock_b",
	"rock_minimal",
	"wood_root",
	"ornament_vase",
	"ornament_bare",
	"plant_fern",
	"plant_minimal",
]

var _catalog: RefCounted = null


func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EMPTY_DIR))


func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(EMPTY_DIR))


func _have(cat: RefCounted) -> bool:
	var ok: bool = Items.has_api(cat)
	assert_bool(ok).override_failure_message("ItemCatalog or its API is missing").is_true()
	return ok


func _paths(folders: Array[String]) -> Array[String]:
	var paths: Array[String] = []
	for folder: String in folders:
		paths.append(Items.FIXTURES.path_join(folder))
	return paths


# --- AC 4: lookup and order ---


func test_ac04_the_catalog_classes_exist() -> void:
	assert_bool(Items.script_exists(Items.DEFINITION_PATH)).is_true()
	assert_bool(Items.script_exists(Items.CATALOG_PATH)).is_true()


func test_ac04_every_valid_definition_is_found_by_id() -> void:
	_catalog = Items.fixture("valid")
	if not _have(_catalog):
		return
	for id: String in VALID_ORDER:
		var definition: Resource = Items.definition(_catalog, StringName(id))
		assert_object(definition).override_failure_message("%s not found" % id).is_not_null()
		if definition != null:
			assert_str(String(definition.get("id"))).is_equal(id)


func test_ac04_an_unknown_id_gives_null() -> void:
	_catalog = Items.fixture("valid")
	if not _have(_catalog):
		return
	assert_object(Items.definition(_catalog, &"no_such_item")).is_null()
	assert_object(Items.definition(_catalog, &"")).is_null()


func test_ac04_the_ids_come_by_category_then_sort_order_then_id() -> void:
	_catalog = Items.fixture("valid")
	if not _have(_catalog):
		return
	assert_array(Items.ids(_catalog)).is_equal(VALID_ORDER)


func test_ac04_get_ids_returns_a_copy() -> void:
	_catalog = Items.fixture("valid")
	if not _have(_catalog):
		return
	var first: Array = _catalog.call("get_ids")
	first.clear()
	assert_array(Items.ids(_catalog)).is_equal(VALID_ORDER)


func test_ac04_the_ids_of_one_category_come_by_sort_order_then_id() -> void:
	_catalog = Items.fixture("valid")
	if not _have(_catalog):
		return
	var rock: int = Items.enum_value("Category", "ROCK")
	var wood: int = Items.enum_value("Category", "WOOD")
	var ornament: int = Items.enum_value("Category", "ORNAMENT")
	var plant: int = Items.enum_value("Category", "PLANT")
	assert_array(Items.ids_in(_catalog, rock)).is_equal(
		["rock_zeta", "rock_a", "rock_b", "rock_minimal"]
	)
	assert_array(Items.ids_in(_catalog, wood)).is_equal(["wood_root"])
	assert_array(Items.ids_in(_catalog, ornament)).is_equal(["ornament_vase", "ornament_bare"])
	assert_array(Items.ids_in(_catalog, plant)).is_equal(["plant_fern", "plant_minimal"])


func test_ac04_the_unset_category_and_an_unknown_value_list_nothing() -> void:
	_catalog = Items.fixture("valid")
	if not _have(_catalog):
		return
	assert_array(Items.ids_in(_catalog, 0)).is_empty()
	assert_array(Items.ids_in(_catalog, 9)).is_empty()


func test_ac04_the_default_dirs_are_decor_then_plants() -> void:
	var dirs: Variant = Items.default_dirs()
	assert_bool(dirs != null).override_failure_message("DEFAULT_DIRS is missing").is_true()
	if dirs != null:
		assert_array(dirs).is_equal(["res://catalog/decor", "res://catalog/plants"])


func test_ac04_load_dirs_without_an_argument_reads_the_default_dirs() -> void:
	var by_default: RefCounted = Items.load_default_dirs()
	if not _have(by_default):
		return
	var explicit: Array[String] = ["res://catalog/decor", "res://catalog/plants"]
	var by_paths: RefCounted = Items.load_dirs(explicit)
	assert_array(Items.ids(by_default)).is_equal(Items.ids(by_paths))
	assert_array(Items.skipped_sources(by_default)).is_equal(Items.skipped_sources(by_paths))


func test_ac04_several_directories_are_merged_in_one_catalog() -> void:
	var cat: RefCounted = Items.load_dirs(_paths(["valid", "dup_second"]))
	if not _have(cat):
		return
	assert_int(Items.ids(cat).size()).is_equal(VALID_ORDER.size() + 2)


func test_ac04_from_definitions_orders_and_finds_like_load_dirs() -> void:
	var rock: int = Items.enum_value("Category", "ROCK")
	var plant: int = Items.enum_value("Category", "PLANT")
	var wood: int = Items.enum_value("Category", "WOOD")
	var cat: RefCounted = (
		Items
		. from_definitions(
			[
				Items.make("plant_x", plant, "", 1),
				Items.make("wood_x", wood, "", 1),
				Items.make("rock_y", rock, "", 2),
				Items.make("rock_x", rock, "", 2),
				Items.make("rock_z", rock, "", 1),
			]
		)
	)
	if not _have(cat):
		return
	assert_array(Items.ids(cat)).is_equal(["rock_z", "rock_x", "rock_y", "wood_x", "plant_x"])
	assert_object(Items.definition(cat, &"wood_x")).is_not_null()


func test_ac04_from_definitions_with_no_definitions_is_empty() -> void:
	var cat: RefCounted = Items.from_definitions([])
	if not _have(cat):
		return
	assert_array(Items.ids(cat)).is_empty()
	assert_array(Items.skipped(cat)).is_empty()


func test_ac04_an_explicit_empty_path_list_gives_an_empty_catalog() -> void:
	var none: Array[String] = []
	var cat: RefCounted = Items.load_dirs(none)
	if not _have(cat):
		return
	assert_array(Items.ids(cat)).is_empty()
	assert_array(Items.skipped(cat)).is_empty()


func test_ac04_the_kept_cases_stay_in_the_catalog() -> void:
	_catalog = Items.fixture("valid")
	if not _have(_catalog):
		return
	var bare: Resource = Items.definition(_catalog, &"ornament_bare")
	assert_object(bare).is_not_null()
	if bare == null:
		return
	assert_str(String(bare.get("description_key"))).is_empty()
	assert_object(bare.get("scene")).is_null()
	assert_object(bare.get("thumbnail")).is_null()
	assert_array(Items.skipped(_catalog)).is_empty()


# --- AC 5: empty, missing and non-.tres directories ---


func test_ac05_an_empty_directory_gives_an_empty_catalog() -> void:
	var paths: Array[String] = [EMPTY_DIR]
	var cat: RefCounted = Items.load_dirs(paths)
	if not _have(cat):
		return
	assert_array(Items.ids(cat)).is_empty()
	assert_array(Items.skipped(cat)).is_empty()


func test_ac05_a_missing_directory_gives_an_empty_catalog() -> void:
	var paths: Array[String] = [Items.MISSING_DIR]
	var cat: RefCounted = Items.load_dirs(paths)
	if not _have(cat):
		return
	assert_array(Items.ids(cat)).is_empty()
	assert_array(Items.skipped(cat)).is_empty()


func test_ac05_a_missing_directory_next_to_a_valid_one_changes_nothing() -> void:
	var cat: RefCounted = Items.load_dirs(_paths(["does_not_exist", "valid", "does_not_exist"]))
	if not _have(cat):
		return
	assert_array(Items.ids(cat)).is_equal(VALID_ORDER)


func test_ac05_only_non_tres_files_and_a_subfolder_give_an_empty_catalog() -> void:
	var cat: RefCounted = Items.fixture("non_tres")
	if not _have(cat):
		return
	assert_array(Items.ids(cat)).is_empty()
	assert_array(Items.skipped(cat)).is_empty()
	assert_object(Items.definition(cat, &"hidden_rock")).is_null()


func test_ac05_the_shipped_folders_load_without_an_error() -> void:
	var cat: RefCounted = Items.load_default_dirs()
	if not _have(cat):
		return
	assert_array(Items.skipped(cat)).is_empty()


# --- AC 7: duplicate ids ---


func test_ac07_the_first_directory_wins_a_duplicate_id() -> void:
	var cat: RefCounted = Items.load_dirs(_paths(["dup_first", "dup_second"]))
	if not _have(cat):
		return
	var winner: Resource = Items.definition(cat, &"dup_item")
	assert_object(winner).is_not_null()
	if winner != null:
		assert_int(winner.get("category")).is_equal(Items.enum_value("Category", "ROCK"))
	assert_int(Items.ids(cat).count("dup_item")).is_equal(1)


func test_ac07_the_second_one_is_reported_with_the_id_and_the_winning_file() -> void:
	var cat: RefCounted = Items.load_dirs(_paths(["dup_first", "dup_second"]))
	if not _have(cat):
		return
	var skipped: Array[Dictionary] = Items.skipped(cat)
	assert_int(skipped.size()).is_equal(1)
	if skipped.is_empty():
		return
	assert_str(skipped[0]["source"]).is_equal(Items.FIXTURES + "/dup_second/dup_item.tres")
	assert_str(skipped[0]["reason"]).contains("dup_item")
	assert_str(skipped[0]["reason"]).contains(Items.FIXTURES + "/dup_first/dup_item.tres")


func test_ac07_reversing_the_directories_reverses_the_winner() -> void:
	var cat: RefCounted = Items.load_dirs(_paths(["dup_second", "dup_first"]))
	if not _have(cat):
		return
	var winner: Resource = Items.definition(cat, &"dup_item")
	assert_object(winner).is_not_null()
	if winner != null:
		assert_int(winner.get("category")).is_equal(Items.enum_value("Category", "PLANT"))
	assert_array(Items.skipped_sources(cat)).is_equal([Items.FIXTURES + "/dup_first/dup_item.tres"])


func test_ac07_from_definitions_keeps_the_first_and_reports_the_position() -> void:
	var rock: int = Items.enum_value("Category", "ROCK")
	var plant: int = Items.enum_value("Category", "PLANT")
	var cat: RefCounted = Items.from_definitions(
		[Items.make("same", rock), Items.make("other", rock), Items.make("same", plant)]
	)
	if not _have(cat):
		return
	assert_int(Items.definition(cat, &"same").get("category")).is_equal(rock)
	var skipped: Array[Dictionary] = Items.skipped(cat)
	assert_int(skipped.size()).is_equal(1)
	if not skipped.is_empty():
		assert_str(skipped[0]["source"]).is_equal("definitions[2]")
		assert_str(skipped[0]["reason"]).contains("same")
		assert_str(skipped[0]["reason"]).contains("definitions[0]")


func test_ac07_an_invalid_definition_never_wins_a_duplicate() -> void:
	var rock: int = Items.enum_value("Category", "ROCK")
	var invalid: Resource = Items.make("same", rock, "item.same.name", 0, false)
	var valid: Resource = Items.make("same", rock)
	var cat: RefCounted = Items.from_definitions([invalid, valid])
	if not _have(cat):
		return
	assert_array(Items.ids(cat)).is_equal(["same"])
	assert_bool(Items.definition(cat, &"same") == valid).is_true()
	assert_int(Items.skipped(cat).size()).is_equal(1)


# --- AC 8: the folder does not decide the category ---


func test_ac08_a_plant_in_the_first_folder_and_a_rock_in_the_second_both_load() -> void:
	var cat: RefCounted = Items.load_dirs(_paths(["dup_first", "dup_second"]))
	if not _have(cat):
		return
	var plant: Resource = Items.definition(cat, &"plant_in_first")
	var rock: Resource = Items.definition(cat, &"rock_in_second")
	assert_object(plant).is_not_null()
	assert_object(rock).is_not_null()
	if plant != null:
		assert_int(plant.get("category")).is_equal(Items.enum_value("Category", "PLANT"))
	if rock != null:
		assert_int(rock.get("category")).is_equal(Items.enum_value("Category", "ROCK"))


func test_ac08_the_category_lists_follow_the_field_not_the_folder() -> void:
	var cat: RefCounted = Items.load_dirs(_paths(["dup_first", "dup_second"]))
	if not _have(cat):
		return
	var rock_ids: Array[String] = Items.ids_in(cat, Items.enum_value("Category", "ROCK"))
	var plant_ids: Array[String] = Items.ids_in(cat, Items.enum_value("Category", "PLANT"))
	assert_array(rock_ids).is_equal(["dup_item", "rock_in_second"])
	assert_array(plant_ids).is_equal(["plant_in_first"])
