extends GdUnitTestSuite
## #31 AC 33 and hand-forward 1 (owner: developer): ItemCatalogSource holds one ItemCatalog per
## session and loads it on the first get_catalog() call, never before; get_load_count() counts the
## loads. from_catalog(catalog) injects a catalog for tests and counts as no load.

const Api := preload("res://tests/helpers/placement_api.gd")


func _have() -> bool:
	(
		assert_bool(Api.exists(Api.SOURCE))
		. override_failure_message("res://catalog/item_catalog_source.gd is missing")
		. is_true()
	)
	return Api.exists(Api.SOURCE)


func test_ac33_nothing_is_loaded_before_the_first_get_catalog() -> void:
	if not _have():
		return
	var source: RefCounted = Api.new_source()
	assert_bool(source.call("is_loaded")).is_false()
	assert_int(source.call("get_load_count")).is_equal(0)


func test_ac33_the_first_get_catalog_loads_the_shipped_items_once() -> void:
	if not _have():
		return
	var source: RefCounted = Api.new_source()
	var catalog: ItemCatalog = source.call("get_catalog") as ItemCatalog
	assert_object(catalog).is_not_null()
	assert_bool(source.call("is_loaded")).is_true()
	assert_int(source.call("get_load_count")).is_equal(1)
	for id: StringName in [&"river_stone", &"driftwood_branch", &"clay_amphora"]:
		assert_object(catalog.get_definition(id)).override_failure_message(String(id)).is_not_null()


func test_ac33_any_number_of_calls_loads_exactly_once_and_returns_one_instance() -> void:
	if not _have():
		return
	var source: RefCounted = Api.new_source()
	var first: Object = source.call("get_catalog")
	for call_number: int in 5:
		(
			assert_object(source.call("get_catalog"))
			. override_failure_message("call %d" % call_number)
			. is_same(first)
		)
	assert_int(source.call("get_load_count")).is_equal(1)


func test_ac33_an_injected_catalog_is_returned_and_counts_as_no_load() -> void:
	if not _have():
		return
	var injected: ItemCatalog = ItemCatalog.from_definitions([] as Array[ItemDefinition])
	var source: RefCounted = Api.source_from(injected)
	assert_object(source).is_not_null()
	assert_object(source.call("get_catalog")).is_same(injected)
	assert_object(source.call("get_catalog")).is_same(injected)
	assert_int(source.call("get_load_count")).is_equal(0)


func test_ac33_two_sources_do_not_share_a_catalog() -> void:
	if not _have():
		return
	var first: RefCounted = Api.new_source()
	var second: RefCounted = Api.new_source()
	first.call("get_catalog")
	assert_bool(second.call("is_loaded")).is_false()
	assert_int(second.call("get_load_count")).is_equal(0)
