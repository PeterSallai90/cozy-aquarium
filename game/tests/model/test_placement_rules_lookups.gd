extends GdUnitTestSuite
## #33 AC 17, the model part (owner: developer): with 100 placed items one validity check makes one
## catalog lookup per model item (a counting fake catalog asserts it), plus one for the candidate.
## A valid placement makes 1 + 100 lookups, a valid move of one of the items 1 + 99 (the item
## changed is not looked up against itself). No wall-clock and no allocation assertion (the 60 FPS
## check is #49). The scene part (pointer moves create no drawn node, no command, no history entry)
## is in test_placement_validity.gd.
## Fixture: 100 items of 4 x 4 x 4 cm in a grid of 20 x 5 at 5 cm spacing on the large tank.

const Api := preload("res://tests/helpers/placement_api.gd")
const Fx := preload("res://tests/helpers/validity_fixtures.gd")
const Counting := preload("res://tests/helpers/counting_item_catalog.gd")

const DOT: StringName = &"dot"
const COLUMNS: int = 20
const ROWS: int = 5
const SPACING_M: float = 0.05


func _have() -> bool:
	(
		assert_bool(Api.exists(Api.RULES))
		. override_failure_message("res://model/placement_rules.gd is missing")
		. is_true()
	)
	return Api.exists(Api.RULES)


func _definitions() -> Array[ItemDefinition]:
	return [Fx.definition(DOT, ItemDefinition.Category.ROCK, Vector3(4.0, 4.0, 4.0))]


func _grid_model() -> AquariumModel:
	var model: AquariumModel = Fx.model(Fx.LARGE)
	for index: int in COLUMNS * ROWS:
		var column: int = index % COLUMNS
		var row: int = floori(index / float(COLUMNS))
		var x: float = (column - (COLUMNS - 1) / 2.0) * SPACING_M
		var z: float = (row - (ROWS - 1) / 2.0) * SPACING_M
		Fx.add(model, "d%07d" % index, DOT, x, z)
	return model


func _rules(counting: Counting) -> RefCounted:
	counting.inner = ItemCatalog.from_definitions(_definitions())
	return Api.rules(Api.source_from(counting))


func test_ac17_the_fixture_has_100_valid_items() -> void:
	if not _have():
		return
	var model: AquariumModel = _grid_model()
	assert_int(model.get_item_count()).is_equal(100)
	var counting: Counting = Counting.new()
	var rules: RefCounted = _rules(counting)
	# Every grid item is valid where it is (moved onto itself, ignoring itself).
	for item: PlacedItem in model.get_items():
		assert_bool(Fx.ok(rules, model, item.copy(), item)).is_true()


func test_ac17_a_valid_placement_makes_one_lookup_per_model_item_and_one_for_the_candidate(
) -> void:
	if not _have():
		return
	var model: AquariumModel = _grid_model()
	var counting: Counting = Counting.new()
	var rules: RefCounted = _rules(counting)
	var candidate: PlacedItem = Fx.item("c0000001", DOT, 0.0, 0.16)
	counting.lookups = 0
	assert_bool(Fx.ok(rules, model, candidate)).is_true()
	assert_int(counting.lookups).is_equal(101)


func test_ac17_a_valid_move_makes_one_lookup_per_other_item_and_one_for_the_candidate() -> void:
	if not _have():
		return
	var model: AquariumModel = _grid_model()
	var counting: Counting = Counting.new()
	var rules: RefCounted = _rules(counting)
	var previous: PlacedItem = model.get_item("d0000000")
	var moved: PlacedItem = previous.copy()
	moved.position = Vector3(0.0, 0.0, 0.16)
	counting.lookups = 0
	assert_bool(Fx.ok(rules, model, moved, previous)).is_true()
	assert_int(counting.lookups).is_equal(100)


func test_ac17_the_lookups_do_not_grow_with_repeated_checks() -> void:
	if not _have():
		return
	var model: AquariumModel = _grid_model()
	var counting: Counting = Counting.new()
	var rules: RefCounted = _rules(counting)
	var candidate: PlacedItem = Fx.item("c0000001", DOT, 0.0, 0.16)
	counting.lookups = 0
	for run: int in 5:
		assert_bool(Fx.ok(rules, model, candidate)).is_true()
	assert_int(counting.lookups).is_equal(505)


func test_ac17_a_refusal_never_makes_more_lookups_than_a_valid_check() -> void:
	if not _have():
		return
	var model: AquariumModel = _grid_model()
	var counting: Counting = Counting.new()
	var rules: RefCounted = _rules(counting)
	counting.lookups = 0
	assert_bool(Fx.refused(rules, model, Fx.item("c0000001", DOT, 0.0, 0.0))).is_true()
	assert_int(counting.lookups).is_less_equal(101)
	counting.lookups = 0
	assert_bool(Fx.refused(rules, model, Fx.item("c0000001", DOT, 5.0, 0.0))).is_true()
	assert_int(counting.lookups).is_less_equal(101)


func test_ac17_checking_changes_neither_the_model_nor_the_catalog() -> void:
	if not _have():
		return
	var model: AquariumModel = _grid_model()
	var counting: Counting = Counting.new()
	var rules: RefCounted = _rules(counting)
	var count_before: int = model.get_item_count()
	Fx.ok(rules, model, Fx.item("c0000001", DOT, 0.0, 0.16))
	assert_int(model.get_item_count()).is_equal(count_before)
	assert_int(counting.inner.get_ids().size()).is_equal(1)
