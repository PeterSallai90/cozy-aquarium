extends GdUnitTestSuite
## #33 AC 16 (owner: developer): rotation in place and items that are already invalid.
## allows(model, candidate, before) with the position unchanged (exact): when the item is valid now
## the full check runs on the new footprint (a turn into a neighbour or the glass is refused);
## when the item is already invalid now (bounds, overlap, height or water line) any finite angle
## is allowed, even a worse one. Any change of position gets the full check, a drop that also
## rotates included. A non-finite angle is always refused. This replaces the #31 `_same_spot`
## shortcut. Medium tank (0.60 x 0.30 m) unless said otherwise, flat sand bed (3 cm).

const Api := preload("res://tests/helpers/placement_api.gd")
const Fx := preload("res://tests/helpers/validity_fixtures.gd")

const ANY_ANGLES: Array[float] = [0.0, 1.0, 37.0, 45.0, 90.0, 123.4, 180.0, -40.0, 400.0]


func _have() -> bool:
	(
		assert_bool(Api.exists(Api.RULES))
		. override_failure_message("res://model/placement_rules.gd is missing")
		. is_true()
	)
	return Api.exists(Api.RULES)


func _turned(model: AquariumModel, uid: String, angle: float) -> PlacedItem:
	var copy: PlacedItem = model.get_item(uid).copy()
	copy.rotation_y = angle
	return copy


func _moved(model: AquariumModel, uid: String, x: float, z: float, angle: float) -> PlacedItem:
	var copy: PlacedItem = model.get_item(uid).copy()
	copy.position = Vector3(x, 0.0, z)
	copy.rotation_y = angle
	return copy


func test_ac16_a_valid_item_turned_to_a_valid_angle_is_allowed() -> void:
	if not _have():
		return
	var rules: RefCounted = Api.rules()
	var model: AquariumModel = Fx.model()
	Fx.add(model, "a0000001", Fx.STONE, 0.0, 0.0)
	Fx.add(model, "a0000002", Fx.BRANCH, 0.0, 0.08)
	var previous: PlacedItem = model.get_item("a0000002")
	assert_bool(Fx.ok(rules, model, _turned(model, "a0000002", 1.0), previous)).is_true()
	assert_bool(Fx.ok(rules, model, _turned(model, "a0000002", 180.0), previous)).is_true()
	assert_bool(Fx.ok(rules, model, _turned(model, "a0000002", 0.0), previous)).is_true()


func test_ac16_a_valid_item_turned_into_a_neighbour_is_refused() -> void:
	if not _have():
		return
	var rules: RefCounted = Api.rules()
	var model: AquariumModel = Fx.model()
	Fx.add(model, "a0000001", Fx.STONE, 0.0, 0.0)
	Fx.add(model, "a0000002", Fx.BRANCH, 0.0, 0.08)
	var previous: PlacedItem = model.get_item("a0000002")
	# The branch lies 5 mm from the stone; turned by 10 degrees or more its end swings into the
	# stone (at 15 degrees the lower edge is 1.1 cm inside the stone).
	for angle: float in [10.0, 15.0, 45.0, 90.0, -15.0]:
		(
			assert_bool(Fx.refused(rules, model, _turned(model, "a0000002", angle), previous))
			. override_failure_message("a turn to %s degrees must be refused" % angle)
			. is_true()
		)


func test_ac16_a_valid_item_turned_through_the_glass_is_refused() -> void:
	if not _have():
		return
	var rules: RefCounted = Api.rules()
	var model: AquariumModel = Fx.model()
	Fx.add(model, "a0000001", Fx.BRANCH, 0.0, 0.11)
	var previous: PlacedItem = model.get_item("a0000001")
	assert_bool(Fx.ok(rules, model, _turned(model, "a0000001", 1.0), previous)).is_true()
	assert_bool(Fx.ok(rules, model, _turned(model, "a0000001", 180.0), previous)).is_true()
	for angle: float in [10.0, 45.0, 90.0]:
		assert_bool(Fx.refused(rules, model, _turned(model, "a0000001", angle), previous)).is_true()


func test_ac16_a_valid_item_does_not_become_free_through_a_non_finite_angle() -> void:
	if not _have():
		return
	var rules: RefCounted = Api.rules()
	var model: AquariumModel = Fx.model()
	Fx.add(model, "a0000001", Fx.STONE, 0.0, 0.0)
	var previous: PlacedItem = model.get_item("a0000001")
	for bad: float in [NAN, INF, -INF]:
		assert_bool(Fx.refused(rules, model, _turned(model, "a0000001", bad), previous)).is_true()


func test_ac16_an_item_invalid_by_the_bounds_turns_to_any_finite_angle() -> void:
	if not _have():
		return
	var rules: RefCounted = Api.rules()
	var model: AquariumModel = Fx.model()
	Fx.add(model, "a0000001", Fx.STONE, 0.29, 0.0)
	Fx.add(model, "a0000002", Fx.BRANCH, 0.5, 0.0)
	for uid: String in ["a0000001", "a0000002"]:
		var previous: PlacedItem = model.get_item(uid)
		for angle: float in ANY_ANGLES:
			(
				assert_bool(Fx.ok(rules, model, _turned(model, uid, angle), previous))
				. override_failure_message("%s turned to %s must be allowed" % [uid, angle])
				. is_true()
			)


func test_ac16_an_item_invalid_by_an_overlap_turns_to_any_finite_angle_even_a_worse_one() -> void:
	if not _have():
		return
	var rules: RefCounted = Api.rules()
	var model: AquariumModel = Fx.model()
	Fx.add(model, "a0000001", Fx.STONE, 0.0, 0.0)
	Fx.add(model, "a0000002", Fx.STONE, 0.05, 0.0)
	for uid: String in ["a0000001", "a0000002"]:
		var previous: PlacedItem = model.get_item(uid)
		for angle: float in ANY_ANGLES:
			assert_bool(Fx.ok(rules, model, _turned(model, uid, angle), previous)).is_true()
	# Worse: the stone at 0.05 overlaps the first one; a third stone 5 mm from its right edge is
	# hit as well once it is turned by 45 degrees (it reaches 6.7 cm to the right).
	Fx.add(model, "a0000003", Fx.STONE, 0.165, 0.0)
	var worse: PlacedItem = model.get_item("a0000002")
	assert_bool(Fx.ok(rules, model, _turned(model, "a0000002", 45.0), worse)).is_true()


## A fresh placement of `id` at the centre of an empty model of the same tank and substrate.
func _placeable(rules: RefCounted, tank: StringName, substrate: StringName, id: StringName) -> bool:
	return Fx.ok(rules, Fx.model(tank, substrate), Fx.item("c0000001", id, 0.0, 0.0))


func test_ac16_an_item_invalid_by_the_height_alone_turns_freely() -> void:
	if not _have():
		return
	# A 24 cm wood on a 3 cm bed fits the small tank (0.27); a deeper bed (pebbles, 6 cm) set on
	# the model afterwards makes it invalid by height alone. Items stay where they are.
	var wood: ItemDefinition = Fx.definition(
		&"tall_wood", ItemDefinition.Category.WOOD, Vector3(10.0, 24.0, 10.0)
	)
	var rules: RefCounted = Fx.rules_of([wood])
	var model: AquariumModel = Fx.model(Fx.SMALL, Fx.SAND)
	Fx.add(model, "a0000001", &"tall_wood", 0.0, 0.0)
	var previous: PlacedItem = model.get_item("a0000001")
	assert_bool(_placeable(rules, Fx.SMALL, Fx.SAND, &"tall_wood")).is_true()
	assert_bool(Fx.ok(rules, model, _turned(model, "a0000001", 30.0), previous)).is_true()
	model.apply_set_substrate(Fx.PEBBLES, Fx.CREAM)
	assert_bool(_placeable(rules, Fx.SMALL, Fx.PEBBLES, &"tall_wood")).is_false()
	for angle: float in ANY_ANGLES:
		(
			assert_bool(Fx.ok(rules, model, _turned(model, "a0000001", angle), previous))
			. override_failure_message("a turn to %s degrees must be allowed" % angle)
			. is_true()
		)
	assert_vector(model.get_item("a0000001").position).is_equal(Vector3.ZERO)


func test_ac16_an_item_invalid_by_the_water_line_alone_turns_freely() -> void:
	if not _have():
		return
	var rock: ItemDefinition = Fx.definition(
		&"tall_rock", ItemDefinition.Category.ROCK, Vector3(10.0, 22.0, 10.0)
	)
	var rules: RefCounted = Fx.rules_of([rock])
	var model: AquariumModel = Fx.model(Fx.SMALL, Fx.SAND)
	Fx.add(model, "a0000001", &"tall_rock", 0.0, 0.0)
	var previous: PlacedItem = model.get_item("a0000001")
	assert_bool(_placeable(rules, Fx.SMALL, Fx.SAND, &"tall_rock")).is_true()
	model.apply_set_substrate(Fx.PEBBLES, Fx.CREAM)
	assert_bool(_placeable(rules, Fx.SMALL, Fx.PEBBLES, &"tall_rock")).is_false()
	assert_bool(Fx.ok(rules, model, _turned(model, "a0000001", 77.0), previous)).is_true()


func test_ac16_an_item_off_the_substrate_in_y_turns_freely_at_the_same_position() -> void:
	if not _have():
		return
	var rules: RefCounted = Api.rules()
	var model: AquariumModel = Fx.model()
	var floating: PlacedItem = Fx.add(model, "a0000001", Fx.STONE, 0.0, 0.0)
	floating.position.y = 0.02
	var candidate: PlacedItem = Fx.item("c0000001", Fx.STONE, 0.0, 0.0)
	candidate.position.y = 0.02
	assert_bool(Fx.refused(rules, Fx.model(), candidate)).is_true()
	assert_bool(Fx.ok(rules, model, _turned(model, "a0000001", 33.0), floating)).is_true()


func test_ac16_an_already_invalid_item_with_any_position_change_gets_the_full_check() -> void:
	if not _have():
		return
	var rules: RefCounted = Api.rules()
	var model: AquariumModel = Fx.model()
	Fx.add(model, "a0000001", Fx.STONE, 0.5, 0.0)
	Fx.add(model, "a0000002", Fx.STONE, 0.0, 0.0)
	Fx.add(model, "a0000003", Fx.STONE, 0.05, 0.0)
	var outside: PlacedItem = model.get_item("a0000001")
	# Still outside after the move, with or without a turn: refused.
	(
		assert_bool(Fx.refused(rules, model, _moved(model, "a0000001", 0.45, 0.0, 0.0), outside))
		. is_true()
	)
	(
		assert_bool(Fx.refused(rules, model, _moved(model, "a0000001", 0.45, 0.0, 40.0), outside))
		. is_true()
	)
	# One micrometre of move is still a move: the turn does not slip through.
	(
		assert_bool(
			Fx.refused(rules, model, _moved(model, "a0000001", 0.500001, 0.0, 40.0), outside)
		)
		. is_true()
	)
	# A drop onto a valid spot is allowed, with or without a turn.
	assert_bool(Fx.ok(rules, model, _moved(model, "a0000001", -0.2, 0.0, 0.0), outside)).is_true()
	assert_bool(Fx.ok(rules, model, _moved(model, "a0000001", -0.2, 0.0, 55.0), outside)).is_true()
	# An overlapping item moved to another overlapping spot is refused; to a free spot allowed.
	var overlapping: PlacedItem = model.get_item("a0000003")
	(
		assert_bool(
			Fx.refused(rules, model, _moved(model, "a0000003", 0.03, 0.0, 0.0), overlapping)
		)
		. is_true()
	)
	(
		assert_bool(Fx.ok(rules, model, _moved(model, "a0000003", 0.2, 0.0, 0.0), overlapping))
		. is_true()
	)


func test_ac16_a_move_of_a_valid_item_is_checked_as_before() -> void:
	if not _have():
		return
	var rules: RefCounted = Api.rules()
	var model: AquariumModel = Fx.model()
	Fx.add(model, "a0000001", Fx.STONE, 0.0, 0.0)
	Fx.add(model, "a0000002", Fx.STONE, 0.2, 0.0)
	var previous: PlacedItem = model.get_item("a0000002")
	assert_bool(Fx.ok(rules, model, _moved(model, "a0000002", 0.2, 0.08, 20.0), previous)).is_true()
	(
		assert_bool(Fx.refused(rules, model, _moved(model, "a0000002", 0.05, 0.0, 0.0), previous))
		. is_true()
	)
	(
		assert_bool(Fx.refused(rules, model, _moved(model, "a0000002", 0.4, 0.0, 0.0), previous))
		. is_true()
	)


func test_ac16_a_non_finite_angle_is_refused_for_an_already_invalid_item_too() -> void:
	if not _have():
		return
	var rules: RefCounted = Api.rules()
	var model: AquariumModel = Fx.model()
	Fx.add(model, "a0000001", Fx.STONE, 0.5, 0.0)
	var previous: PlacedItem = model.get_item("a0000001")
	for bad: float in [NAN, INF, -INF]:
		assert_bool(Fx.refused(rules, model, _turned(model, "a0000001", bad), previous)).is_true()


func test_ac16_the_rule_changes_nothing_in_the_model() -> void:
	if not _have():
		return
	var rules: RefCounted = Api.rules()
	var model: AquariumModel = Fx.model()
	Fx.add(model, "a0000001", Fx.STONE, 0.5, 0.0, 12.0)
	var previous: PlacedItem = model.get_item("a0000001")
	Fx.ok(rules, model, _turned(model, "a0000001", 90.0), previous)
	assert_float(model.get_item("a0000001").rotation_y).is_equal(12.0)
	assert_vector(model.get_item("a0000001").position).is_equal(Vector3(0.5, 0.0, 0.0))
	assert_int(model.get_item_count()).is_equal(1)
