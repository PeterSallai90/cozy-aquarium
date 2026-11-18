extends GdUnitTestSuite
## #152 criterion 6 (owner: developer): a definition that breaks a loader rule is skipped and
## reported, every other definition still loads. Reasons are developer text, never logged. The
## engine log of these cases is checked at run level (check_godot_log.py, ADR 0004).

const Items := preload("res://tests/helpers/item_api.gd")

const BAD_FIELD_FILES: Array[String] = [
	"bad_id.tres",
	"category_nine.tres",
	"category_unset.tres",
	"empty_id.tres",
	"empty_name_key.tres",
	"unsafe.tres",
]


func _have(cat: RefCounted) -> bool:
	var ok: bool = Items.has_api(cat)
	assert_bool(ok).override_failure_message("ItemCatalog or its API is missing").is_true()
	return ok


func _rock() -> int:
	return Items.enum_value("Category", "ROCK")


## One skipped entry per bad file, each with the file as source and a reason.
func _check_entries(cat: RefCounted, files: Array[String], folder: String) -> void:
	var skipped: Array[Dictionary] = Items.skipped(cat)
	assert_int(skipped.size()).override_failure_message("skipped count").is_equal(files.size())
	var sources: Array[String] = Items.skipped_sources(cat)
	for file: String in files:
		var expected: String = Items.FIXTURES.path_join(folder).path_join(file)
		(
			assert_bool(sources.has(expected))
			. override_failure_message("%s not reported" % file)
			. is_true()
		)
	for entry: Dictionary in skipped:
		(
			assert_str(entry["reason"])
			. override_failure_message("empty reason for %s" % entry["source"])
			. is_not_empty()
		)


# --- files ---


func test_ac06_each_bad_fixture_is_skipped_and_reported_with_a_reason() -> void:
	var cat: RefCounted = Items.fixture("bad_fields")
	if not _have(cat):
		return
	_check_entries(cat, BAD_FIELD_FILES, "bad_fields")


func test_ac06_the_good_item_next_to_the_bad_ones_still_loads() -> void:
	var cat: RefCounted = Items.fixture("bad_fields")
	if not _have(cat):
		return
	assert_array(Items.ids(cat)).is_equal(["good_item"])
	assert_object(Items.definition(cat, &"good_item")).is_not_null()


func test_ac06_a_skipped_id_is_not_in_the_catalog() -> void:
	var cat: RefCounted = Items.fixture("bad_fields")
	if not _have(cat):
		return
	for id: StringName in [
		&"Rock", &"category_nine", &"category_unset", &"empty_name_key", &"unsafe"
	]:
		(
			assert_object(Items.definition(cat, id))
			. override_failure_message("%s should be skipped" % id)
			. is_null()
		)


func test_ac06_a_resource_that_is_not_an_item_definition_is_skipped() -> void:
	var cat: RefCounted = Items.fixture("wrong_class")
	if not _have(cat):
		return
	_check_entries(cat, ["plain_resource.tres"], "wrong_class")
	assert_array(Items.ids(cat)).is_equal(["good_rock"])


func test_ac06_a_clean_folder_reports_nothing() -> void:
	var cat: RefCounted = Items.fixture("valid")
	if not _have(cat):
		return
	assert_array(Items.skipped(cat)).is_empty()


func test_ac06_get_skipped_returns_a_copy() -> void:
	var cat: RefCounted = Items.fixture("bad_fields")
	if not _have(cat):
		return
	var first: Array = cat.call("get_skipped")
	first.clear()
	assert_int(Items.skipped(cat).size()).is_equal(BAD_FIELD_FILES.size())


# --- definitions built in code (from_definitions) ---


func test_ac06_from_definitions_reports_each_skip_by_position() -> void:
	var broken_name: Resource = Items.make("no_name", _rock())
	broken_name.set("name_key", "")
	var definitions: Array = [
		Items.make("fine", _rock()),
		Items.make("", _rock()),
		Items.make("Bad", _rock()),
		Items.make("unset_cat", 0),
		Items.make("out_of_range", 9),
		broken_name,
		Items.make("unsafe", _rock(), "", 0, false),
		null,
		Items.make("also_fine", _rock()),
	]
	var cat: RefCounted = Items.from_definitions(definitions)
	if not _have(cat):
		return
	var expected: Array[String] = []
	for index: int in [1, 2, 3, 4, 5, 6, 7]:
		expected.append("definitions[%d]" % index)
	assert_array(Items.skipped_sources(cat)).is_equal(expected)
	for entry: Dictionary in Items.skipped(cat):
		assert_str(entry["reason"]).is_not_empty()
	assert_array(Items.ids(cat)).is_equal(["also_fine", "fine"])


func test_ac06_an_empty_description_key_scene_and_thumbnail_are_kept() -> void:
	var definition: Resource = Items.make("plain", _rock())
	var cat: RefCounted = Items.from_definitions([definition])
	if not _have(cat):
		return
	assert_str(String(definition.get("description_key"))).is_empty()
	assert_array(Items.ids(cat)).is_equal(["plain"])
	assert_array(Items.skipped(cat)).is_empty()


func test_ac06_a_reference_to_a_missing_file_is_not_checked() -> void:
	var definition: Resource = Items.make("ghost", _rock())
	definition.set("description_key", "item.ghost.description")
	var cat: RefCounted = Items.from_definitions([definition])
	if not _have(cat):
		return
	assert_array(Items.ids(cat)).is_equal(["ghost"])


# --- the shared item-id rule ---


func test_ac06_the_shared_lists_have_the_stated_lengths() -> void:
	assert_int(Items.VALID_IDS[4].length()).is_equal(48)
	var long_invalid: String = ""
	for id: String in Items.INVALID_IDS:
		if id.length() > 40:
			long_invalid = id
	assert_int(long_invalid.length()).is_equal(49)
	assert_bool(Items.INVALID_IDS.has("rock\n")).is_true()


func test_ac06_is_valid_id_accepts_every_valid_id() -> void:
	for id: String in Items.VALID_IDS:
		assert_that(Items.is_valid_id(id)).override_failure_message("'%s'" % id).is_equal(true)


func test_ac06_is_valid_id_rejects_every_invalid_id() -> void:
	for id: String in Items.INVALID_IDS:
		(
			assert_that(Items.is_valid_id(id))
			. override_failure_message("'%s'" % id.c_escape())
			. is_equal(false)
		)


func test_ac06_every_other_windows_device_name_is_rejected_too() -> void:
	var names: Array[String] = []
	for number: int in range(1, 10):
		names.append("com%d" % number)
		names.append("lpt%d" % number)
	for id: String in names:
		assert_that(Items.is_valid_id(id)).override_failure_message(id).is_equal(false)


func test_ac06_a_device_name_as_a_prefix_is_a_valid_id() -> void:
	for id: String in ["console", "nullable", "com10", "auxiliary", "prn_a", "lpt0"]:
		assert_that(Items.is_valid_id(id)).override_failure_message(id).is_equal(true)


func test_ac06_the_catalog_keeps_each_valid_id() -> void:
	var definitions: Array = []
	for id: String in Items.VALID_IDS:
		definitions.append(Items.make(id, _rock()))
	var cat: RefCounted = Items.from_definitions(definitions)
	if not _have(cat):
		return
	assert_array(Items.skipped(cat)).is_empty()
	assert_int(Items.ids(cat).size()).is_equal(Items.VALID_IDS.size())


func test_ac06_the_catalog_skips_each_invalid_id_with_a_reason() -> void:
	var definitions: Array = []
	for id: String in Items.INVALID_IDS:
		definitions.append(Items.make(id, _rock()))
	var cat: RefCounted = Items.from_definitions(definitions)
	if not _have(cat):
		return
	assert_array(Items.ids(cat)).is_empty()
	var skipped: Array[Dictionary] = Items.skipped(cat)
	assert_int(skipped.size()).is_equal(Items.INVALID_IDS.size())
	for index: int in skipped.size():
		assert_str(skipped[index]["source"]).is_equal("definitions[%d]" % index)
		assert_str(skipped[index]["reason"]).is_not_empty()
