extends GdUnitTestSuite
## #33 (owner: developer): SubstrateCatalog.resolve(id) -> SubstrateDefinition, the one lookup the
## validity rules and the room share so that the rules always judge the bed that is shown: the
## definition of the id, else the default (sand_fine, ADR 0010), else null. Late-bound because the
## method does not exist before the implementation.

const KNOWN: StringName = &"pebbles_river"
const MISSING := "<missing>"


func _resolve(catalog: SubstrateCatalog, id: StringName) -> Variant:
	if not catalog.has_method("resolve"):
		(
			assert_bool(false)
			. override_failure_message("SubstrateCatalog.resolve() is missing")
			. is_true()
		)
		return MISSING
	return catalog.call("resolve", id)


func _definition(id: StringName, depth_m: float) -> SubstrateDefinition:
	var definition: SubstrateDefinition = SubstrateDefinition.new()
	definition.id = id
	definition.name_key = "substrate.%s.name" % id
	definition.fill_depth_m = depth_m
	return definition


func test_resolve_gives_the_definition_of_a_known_id() -> void:
	var catalog: SubstrateCatalog = SubstrateCatalog.load_dir()
	var found: Variant = _resolve(catalog, KNOWN)
	assert_object(found).is_same(catalog.get_definition(KNOWN))


func test_resolve_falls_back_to_the_default_for_an_unknown_or_empty_id() -> void:
	var catalog: SubstrateCatalog = SubstrateCatalog.load_dir()
	assert_object(_resolve(catalog, &"no_such_bed")).is_same(catalog.get_default())
	assert_object(_resolve(catalog, &"")).is_same(catalog.get_default())
	var fallback: SubstrateDefinition = _resolve(catalog, &"no_such_bed") as SubstrateDefinition
	assert_object(fallback).is_not_null()
	if fallback != null:
		assert_str(String(fallback.id)).is_equal(String(SubstrateCatalog.DEFAULT_ID))


func test_resolve_gives_null_when_there_is_no_default_and_the_id_is_unknown() -> void:
	var catalog: SubstrateCatalog = SubstrateCatalog.from_definitions([_definition(&"only", 0.05)])
	assert_object(_resolve(catalog, &"other")).is_null()
	assert_object(_resolve(catalog, &"only")).is_same(catalog.get_definition(&"only"))


func test_resolve_gives_null_for_an_empty_catalog() -> void:
	var catalog: SubstrateCatalog = SubstrateCatalog.from_definitions([])
	assert_object(_resolve(catalog, &"sand_fine")).is_null()
