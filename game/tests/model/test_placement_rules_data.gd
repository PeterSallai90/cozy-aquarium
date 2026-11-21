extends GdUnitTestSuite
## #33 AC 9b (owner: developer): degenerate data. A candidate with an unknown catalog_id, a
## footprint component that is zero, negative or not finite, a scale that is zero, negative or not
## finite, or a position.y that is not 0 (more than the tolerance, or not finite) is refused. A very
## large scale is no special case: it fails the bounds by itself. Items already in the model with
## such data block nothing. No error and no warning is logged for any of it. Null catalogs make
## allows() false. Fixtures are in-memory definitions on the medium tank (flat 3 cm sand bed).

const Api := preload("res://tests/helpers/placement_api.gd")
const Fx := preload("res://tests/helpers/validity_fixtures.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")

const GOOD: StringName = &"good_rock"
const ROCK := ItemDefinition.Category.ROCK


func _have() -> bool:
	(
		assert_bool(Api.exists(Api.RULES))
		. override_failure_message("res://model/placement_rules.gd is missing")
		. is_true()
	)
	return Api.exists(Api.RULES)


func _definitions() -> Array[ItemDefinition]:
	var list: Array[ItemDefinition] = [Fx.definition(GOOD, ROCK, Vector3(10.0, 10.0, 10.0))]
	var broken: Dictionary = {
		&"zero_x": Vector3(0.0, 10.0, 10.0),
		&"zero_y": Vector3(10.0, 0.0, 10.0),
		&"zero_z": Vector3(10.0, 10.0, 0.0),
		&"neg_x": Vector3(-10.0, 10.0, 10.0),
		&"neg_y": Vector3(10.0, -10.0, 10.0),
		&"neg_z": Vector3(10.0, 10.0, -10.0),
		&"nan_x": Vector3(NAN, 10.0, 10.0),
		&"nan_y": Vector3(10.0, NAN, 10.0),
		&"nan_z": Vector3(10.0, 10.0, NAN),
		&"inf_x": Vector3(INF, 10.0, 10.0),
		&"inf_y": Vector3(10.0, INF, 10.0),
		&"inf_z": Vector3(10.0, 10.0, INF),
	}
	for id: StringName in broken:
		list.append(Fx.definition(id, ROCK, broken[id]))
	return list


func _broken_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for definition: ItemDefinition in _definitions():
		if definition.id != GOOD:
			ids.append(definition.id)
	return ids


func test_ac9b_the_control_candidate_is_valid() -> void:
	if not _have():
		return
	var rules: RefCounted = Fx.rules_of(_definitions())
	assert_bool(Fx.ok(rules, Fx.model(), Fx.item("c0000001", GOOD, 0.0, 0.0))).is_true()


func test_ac9b_a_candidate_with_an_unknown_catalog_id_is_refused() -> void:
	if not _have():
		return
	var rules: RefCounted = Fx.rules_of(_definitions())
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void:
			var model: AquariumModel = Fx.model()
			assert_bool(Fx.refused(rules, model, Fx.item("c0000001", &"nope", 0.0, 0.0))).is_true()
			assert_bool(Fx.refused(rules, model, Fx.item("c0000001", &"", 0.0, 0.0))).is_true()
	)
	assert_dict(seen["errors"]).is_empty()
	assert_dict(seen["warnings"]).is_empty()


func test_ac9b_a_candidate_with_a_zero_negative_or_non_finite_footprint_component_is_refused(
) -> void:
	if not _have():
		return
	var rules: RefCounted = Fx.rules_of(_definitions())
	var model: AquariumModel = Fx.model()
	for id: StringName in _broken_ids():
		(
			assert_bool(Fx.refused(rules, model, Fx.item("c0000001", id, 0.0, 0.0)))
			. override_failure_message("%s must be refused" % id)
			. is_true()
		)


func test_ac9b_a_candidate_with_a_scale_of_zero_or_less_or_not_finite_is_refused() -> void:
	if not _have():
		return
	var rules: RefCounted = Fx.rules_of(_definitions())
	var model: AquariumModel = Fx.model()
	for bad: float in [0.0, -1.0, -0.0001, NAN, INF, -INF]:
		(
			assert_bool(Fx.refused(rules, model, Fx.item("c0000001", GOOD, 0.0, 0.0, 0.0, bad)))
			. override_failure_message("scale %s must be refused" % bad)
			. is_true()
		)


func test_ac9b_a_candidate_off_the_substrate_is_refused_at_y_0_02_minus_0_02_and_nan() -> void:
	if not _have():
		return
	var rules: RefCounted = Fx.rules_of(_definitions())
	var model: AquariumModel = Fx.model()
	for bad: float in [0.02, -0.02, NAN, INF, -INF, 0.001]:
		var candidate: PlacedItem = Fx.item("c0000001", GOOD, 0.0, 0.0)
		candidate.position.y = bad
		(
			assert_bool(Fx.refused(rules, model, candidate))
			. override_failure_message("position.y %s must be refused" % bad)
			. is_true()
		)


func test_ac9b_a_y_within_the_tolerance_still_rests_on_the_substrate() -> void:
	if not _have():
		return
	var rules: RefCounted = Fx.rules_of(_definitions())
	var model: AquariumModel = Fx.model()
	for inside: float in [0.0, Fx.INSIDE_TOLERANCE_M, -Fx.INSIDE_TOLERANCE_M]:
		var candidate: PlacedItem = Fx.item("c0000001", GOOD, 0.0, 0.0)
		candidate.position.y = inside
		assert_bool(Fx.ok(rules, model, candidate)).is_true()
	var beyond: PlacedItem = Fx.item("c0000001", GOOD, 0.0, 0.0)
	beyond.position.y = Fx.BEYOND_TOLERANCE_M
	assert_bool(Fx.refused(rules, model, beyond)).is_true()


func test_ac9b_a_moved_item_is_judged_for_y_too() -> void:
	if not _have():
		return
	var rules: RefCounted = Fx.rules_of(_definitions())
	var model: AquariumModel = Fx.model()
	Fx.add(model, "a0000001", GOOD, 0.0, 0.0)
	var current: PlacedItem = model.get_item("a0000001")
	var lifted: PlacedItem = current.copy()
	lifted.position = Vector3(0.1, 0.02, 0.0)
	assert_bool(Fx.refused(rules, model, lifted, current)).is_true()


func test_ac9b_a_very_large_scale_fails_the_bounds_by_itself() -> void:
	if not _have():
		return
	var rules: RefCounted = Fx.rules_of(_definitions())
	var model: AquariumModel = Fx.model()
	for big: float in [10.0, 100.0, 1.0e6, 1.0e30]:
		(
			assert_bool(Fx.refused(rules, model, Fx.item("c0000001", GOOD, 0.0, 0.0, 0.0, big)))
			. is_true()
		)
	# 1 m x 1 m x 1 m at scale 10 in the large tank is wider than 0.4 m deep.
	var large: AquariumModel = Fx.model(Fx.LARGE)
	assert_bool(Fx.refused(rules, large, Fx.item("c0000001", GOOD, 0.0, 0.0, 0.0, 10.0))).is_true()


func test_ac9b_items_in_the_model_with_such_data_block_nothing() -> void:
	if not _have():
		return
	var rules: RefCounted = Fx.rules_of(_definitions())
	var model: AquariumModel = Fx.model()
	var index: int = 0
	for id: StringName in _broken_ids():
		Fx.add(model, "b%07d" % index, id, 0.0, 0.0)
		index += 1
	Fx.add(model, "b0000090", &"nope", 0.0, 0.0)
	for bad: float in [0.0, -1.0, NAN, INF]:
		Fx.add(model, "b%07d" % (100 + index), GOOD, 0.0, 0.0, 0.0, bad)
		index += 1
	var nan_spot: PlacedItem = Fx.add(model, "b0000092", GOOD, NAN, 0.0)
	nan_spot.rotation_y = NAN
	var count_before: int = model.get_item_count()
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void:
			var candidate: PlacedItem = Fx.item("c0000001", GOOD, 0.0, 0.0)
			assert_bool(Fx.ok(rules, model, candidate)).is_true()
	)
	assert_dict(seen["errors"]).is_empty()
	assert_dict(seen["warnings"]).is_empty()
	assert_dict(seen["script_errors"]).is_empty()
	assert_int(model.get_item_count()).is_equal(count_before)


func test_ac9b_a_null_catalog_gives_false_without_an_error() -> void:
	if not _have():
		return
	var tanks: TankCatalog = TankCatalog.load_dir()
	var items: RefCounted = Fx.source_of(_definitions())
	var substrates: SubstrateCatalog = SubstrateCatalog.load_dir()
	var model: AquariumModel = Fx.model()
	var candidate: PlacedItem = Fx.item("c0000001", GOOD, 0.0, 0.0)
	var control: RefCounted = Api.rules_with(tanks, items, substrates)
	var no_tanks: RefCounted = Api.rules_with(null, items, substrates)
	var no_items: RefCounted = Api.rules_with(tanks, null, substrates)
	var no_substrates: RefCounted = Api.rules_with(tanks, items, null)
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void:
			assert_bool(Fx.ok(control, model, candidate)).is_true()
			assert_bool(Fx.refused(no_tanks, model, candidate)).is_true()
			assert_bool(Fx.refused(no_items, model, candidate)).is_true()
			assert_bool(Fx.refused(no_substrates, model, candidate)).is_true()
	)
	assert_dict(seen["errors"]).is_empty()
	assert_dict(seen["warnings"]).is_empty()
	assert_dict(seen["script_errors"]).is_empty()


func test_ac9b_a_null_model_or_candidate_gives_false() -> void:
	if not _have():
		return
	var rules: RefCounted = Fx.rules_of(_definitions())
	assert_bool(Fx.refused(rules, null, Fx.item("c0000001", GOOD, 0.0, 0.0))).is_true()
	assert_bool(Fx.refused(rules, Fx.model(), null)).is_true()


func test_ac9b_the_lazy_load_never_happens_in_init() -> void:
	if not _have():
		return
	# Building the rules loads no item catalog (#30 AC 23: a start with an empty model loads
	# nothing); the first allows() does, exactly once.
	var source: RefCounted = Api.new_source()
	var rules: RefCounted = Api.rules_with(
		TankCatalog.load_dir(), source, SubstrateCatalog.load_dir()
	)
	assert_object(rules).is_not_null()
	assert_int(Api.call_on(source, "get_load_count", [], -1)).is_equal(0)
	var item: PlacedItem = Fx.item("c0000001", Fx.STONE, 0.0, 0.0)
	assert_bool(Fx.ok(rules, Fx.model(), item)).is_true()
	assert_bool(Fx.ok(rules, Fx.model(), item)).is_true()
	assert_int(Api.call_on(source, "get_load_count", [], -1)).is_equal(1)
