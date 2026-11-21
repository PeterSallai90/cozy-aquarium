extends GdUnitTestSuite
## #33 AC 4 to 9 (owner: developer): placement validity against the other items. Footprints are
## oriented rectangles; two overlap when the penetration depth on the four edge normals is greater
## than the tolerance (0.1 mm) on every axis. Touching along an edge or at a corner is valid. Every
## item blocks every item (also the same kind), the item being changed ignores itself through
## `before`, and an item of the model with an unknown id blocks nothing.
## Fixtures: river_stone 11 x 8 cm, clay_amphora 9 x 8 cm, driftwood_branch 28 x 7 cm on the
## medium tank (0.60 x 0.30 m), flat sand bed. Test decisions: the touching positions are exact
## (computed from the footprint), the tolerance cases sit 1e-5 m either side of the tolerance, and
## the sign of the rotation is pinned by the asymmetric fixture at the end.

const Api := preload("res://tests/helpers/placement_api.gd")
const Fx := preload("res://tests/helpers/validity_fixtures.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")

const STONE_X: float = 0.11
const STONE_Z: float = 0.08
const EPSILON: float = 0.00001


func _have() -> bool:
	(
		assert_bool(Api.exists(Api.RULES))
		. override_failure_message("res://model/placement_rules.gd is missing")
		. is_true()
	)
	return Api.exists(Api.RULES)


## A medium tank with one stone "a0000001" at the given spot.
func _with_stone(x: float, z: float, rotation_y: float = 0.0) -> AquariumModel:
	var model: AquariumModel = Fx.model()
	Fx.add(model, "a0000001", Fx.STONE, x, z, rotation_y)
	return model


func _candidate(id: StringName, x: float, z: float, rotation_y: float = 0.0) -> PlacedItem:
	return Fx.item("c0000001", id, x, z, rotation_y)


func test_ac4_an_overlap_by_a_centimetre_is_refused() -> void:
	if not _have():
		return
	var model: AquariumModel = _with_stone(0.0, 0.0)
	var rules: RefCounted = Api.rules()
	assert_bool(Fx.refused(rules, model, _candidate(Fx.STONE, STONE_X - 0.01, 0.0))).is_true()
	assert_bool(Fx.refused(rules, model, _candidate(Fx.STONE, 0.0, STONE_Z - 0.01))).is_true()
	assert_bool(Fx.refused(rules, model, _candidate(Fx.STONE, -0.05, 0.03))).is_true()


func test_ac4_every_item_blocks_every_item_whatever_the_catalog_ids() -> void:
	if not _have():
		return
	var rules: RefCounted = Api.rules()
	var model: AquariumModel = _with_stone(0.0, 0.0)
	for id: StringName in [Fx.STONE, Fx.AMPHORA, Fx.BRANCH]:
		assert_bool(Fx.refused(rules, model, _candidate(id, 0.02, 0.01))).is_true()
	var branch_model: AquariumModel = Fx.model()
	Fx.add(branch_model, "a0000001", Fx.BRANCH, 0.0, 0.0)
	for id: StringName in [Fx.STONE, Fx.AMPHORA, Fx.BRANCH]:
		assert_bool(Fx.refused(rules, branch_model, _candidate(id, 0.05, 0.0))).is_true()


func test_ac4_a_candidate_inside_a_bigger_item_is_refused() -> void:
	if not _have():
		return
	var model: AquariumModel = Fx.model()
	Fx.add(model, "a0000001", Fx.BRANCH, 0.0, 0.0)
	var small: PlacedItem = Fx.item("c0000001", Fx.STONE, 0.0, 0.0, 0.0, 0.2)
	assert_bool(Fx.refused(Api.rules(), model, small)).is_true()


func test_ac5_touching_along_an_edge_is_valid_on_every_side() -> void:
	if not _have():
		return
	var rules: RefCounted = Api.rules()
	var model: AquariumModel = _with_stone(0.0, 0.0)
	assert_bool(Fx.ok(rules, model, _candidate(Fx.STONE, STONE_X, 0.0))).is_true()
	assert_bool(Fx.ok(rules, model, _candidate(Fx.STONE, -STONE_X, 0.0))).is_true()
	assert_bool(Fx.ok(rules, model, _candidate(Fx.STONE, 0.0, STONE_Z))).is_true()
	assert_bool(Fx.ok(rules, model, _candidate(Fx.STONE, 0.0, -STONE_Z))).is_true()
	# Slid along the shared edge it still touches.
	assert_bool(Fx.ok(rules, model, _candidate(Fx.STONE, STONE_X, 0.05))).is_true()
	# An amphora (9 x 8) beside the stone.
	assert_bool(Fx.ok(rules, model, _candidate(Fx.AMPHORA, (STONE_X + 0.09) / 2.0, 0.0))).is_true()


func test_ac5_touching_corner_to_corner_is_valid() -> void:
	if not _have():
		return
	var rules: RefCounted = Api.rules()
	var model: AquariumModel = _with_stone(0.0, 0.0)
	for sign_x: float in [-1.0, 1.0]:
		for sign_z: float in [-1.0, 1.0]:
			(
				assert_bool(
					Fx.ok(rules, model, _candidate(Fx.STONE, sign_x * STONE_X, sign_z * STONE_Z))
				)
				. is_true()
			)


func test_ac5_a_rotated_pair_touching_edge_to_edge_and_corner_to_corner_is_valid() -> void:
	if not _have():
		return
	var rules: RefCounted = Api.rules()
	var model: AquariumModel = _with_stone(0.0, 0.0, 45.0)
	var along: Vector2 = Vector2(cos(deg_to_rad(45.0)), -sin(deg_to_rad(45.0)))
	var across: Vector2 = Vector2(sin(deg_to_rad(45.0)), cos(deg_to_rad(45.0)))
	var edge: Vector2 = along * STONE_X
	var corner: Vector2 = along * STONE_X + across * STONE_Z
	assert_bool(Fx.ok(rules, model, _candidate(Fx.STONE, edge.x, edge.y, 45.0))).is_true()
	assert_bool(Fx.ok(rules, model, _candidate(Fx.STONE, corner.x, corner.y, 45.0))).is_true()
	assert_bool(Fx.ok(rules, model, _candidate(Fx.STONE, -corner.x, -corner.y, 45.0))).is_true()
	# One centimetre closer along the shared direction is an overlap.
	var inside: Vector2 = along * (STONE_X - 0.01)
	assert_bool(Fx.refused(rules, model, _candidate(Fx.STONE, inside.x, inside.y, 45.0))).is_true()


func test_ac5_the_tolerance_decides_touching_at_a_tenth_of_a_millimetre() -> void:
	if not _have():
		return
	var rules: RefCounted = Api.rules()
	var model: AquariumModel = _with_stone(0.0, 0.0)
	var tolerance: float = Api.tolerance()
	# Penetration just below and just above the tolerance, on x and on z.
	var shallow_x: float = STONE_X - (tolerance - EPSILON)
	var deep_x: float = STONE_X - (tolerance + EPSILON)
	assert_bool(Fx.ok(rules, model, _candidate(Fx.STONE, shallow_x, 0.0))).is_true()
	assert_bool(Fx.refused(rules, model, _candidate(Fx.STONE, deep_x, 0.0))).is_true()
	var shallow_z: float = STONE_Z - (tolerance - EPSILON)
	var deep_z: float = STONE_Z - (tolerance + EPSILON)
	assert_bool(Fx.ok(rules, model, _candidate(Fx.STONE, 0.0, shallow_z))).is_true()
	assert_bool(Fx.refused(rules, model, _candidate(Fx.STONE, 0.0, deep_z))).is_true()
	# At a corner a shallow penetration on one axis is touching whatever the other axis does.
	assert_bool(Fx.ok(rules, model, _candidate(Fx.STONE, shallow_x, 0.03))).is_true()
	assert_bool(Fx.refused(rules, model, _candidate(Fx.STONE, deep_x, 0.03))).is_true()


func test_ac6_two_items_on_the_same_spot_are_refused() -> void:
	if not _have():
		return
	var rules: RefCounted = Api.rules()
	var model: AquariumModel = _with_stone(0.1, 0.05, 20.0)
	assert_bool(Fx.refused(rules, model, _candidate(Fx.STONE, 0.1, 0.05, 20.0))).is_true()
	assert_bool(Fx.refused(rules, model, _candidate(Fx.STONE, 0.1, 0.05, 0.0))).is_true()
	assert_bool(Fx.refused(rules, model, _candidate(Fx.AMPHORA, 0.1, 0.05))).is_true()


func test_ac7_a_moved_or_rotated_item_never_overlaps_itself() -> void:
	if not _have():
		return
	var rules: RefCounted = Api.rules()
	var model: AquariumModel = _with_stone(0.0, 0.0)
	var current: PlacedItem = model.get_item("a0000001")
	var turned: PlacedItem = current.copy()
	turned.rotation_y = 30.0
	assert_bool(Fx.ok(rules, model, turned, current)).is_true()
	var nudged: PlacedItem = current.copy()
	nudged.position = Vector3(0.02, 0.0, 0.01)
	assert_bool(Fx.ok(rules, model, nudged, current)).is_true()
	var spun: PlacedItem = current.copy()
	spun.rotation_y = 200.0
	assert_bool(Fx.ok(rules, model, spun, current)).is_true()


func test_ac7_the_item_changed_still_collides_with_the_others() -> void:
	if not _have():
		return
	var rules: RefCounted = Api.rules()
	var model: AquariumModel = _with_stone(0.0, 0.0)
	Fx.add(model, "a0000002", Fx.STONE, 0.2, 0.0)
	var current: PlacedItem = model.get_item("a0000002")
	var moved: PlacedItem = current.copy()
	moved.position = Vector3(0.05, 0.0, 0.0)
	assert_bool(Fx.refused(rules, model, moved, current)).is_true()
	var beside: PlacedItem = current.copy()
	beside.position = Vector3(0.12, 0.0, 0.0)
	assert_bool(Fx.ok(rules, model, beside, current)).is_true()


func test_ac7_a_placement_is_not_ignored_by_uid() -> void:
	if not _have():
		return
	# before == null is a placement: a candidate on the spot of an item with the same uid is
	# still an overlap (the uid is no free pass without before).
	var rules: RefCounted = Api.rules()
	var model: AquariumModel = _with_stone(0.0, 0.0)
	var same_uid: PlacedItem = Fx.item("a0000001", Fx.STONE, 0.0, 0.0)
	assert_bool(Fx.refused(rules, model, same_uid, null)).is_true()


func test_ac8_diagonal_neighbours_whose_boxes_overlap_but_rectangles_do_not() -> void:
	if not _have():
		return
	var rules: RefCounted = Api.rules()
	# The branch turned by 45 degrees is a thin diagonal bar; its box is +-9.9 cm both ways.
	var model: AquariumModel = Fx.model()
	Fx.add(model, "a0000001", Fx.BRANCH, 0.0, 0.0, 45.0)
	# The stone box x 0.045..0.155, z 0.06..0.14 overlaps the bar box but not the bar.
	assert_bool(Fx.ok(rules, model, _candidate(Fx.STONE, 0.10, 0.10))).is_true()
	assert_bool(Fx.ok(rules, model, _candidate(Fx.STONE, -0.10, -0.10))).is_true()
	# Moved onto the bar it is an overlap.
	assert_bool(Fx.refused(rules, model, _candidate(Fx.STONE, 0.05, -0.05))).is_true()
	# The same pair with the roles swapped: the bar as candidate, the stone in the model.
	var reverse: AquariumModel = _with_stone(0.10, 0.10)
	var bar: PlacedItem = _candidate(Fx.BRANCH, 0.0, 0.0, 45.0)
	assert_bool(Fx.ok(rules, reverse, bar)).is_true()


func test_ac8_a_rotated_candidate_is_not_judged_as_a_circle() -> void:
	if not _have():
		return
	var rules: RefCounted = Api.rules()
	# Two bars side by side along their length: the circles of radius 14.4 cm would overlap, the
	# rectangles are 7 cm apart centre to centre across and 7 cm wide: they touch.
	var model: AquariumModel = Fx.model(Fx.LARGE)
	Fx.add(model, "a0000001", Fx.BRANCH, 0.0, 0.0, 0.0)
	assert_bool(Fx.ok(rules, model, _candidate(Fx.BRANCH, 0.0, 0.07))).is_true()
	assert_bool(Fx.refused(rules, model, _candidate(Fx.BRANCH, 0.0, 0.06))).is_true()
	assert_bool(Fx.ok(rules, model, _candidate(Fx.BRANCH, 0.28, 0.0))).is_true()


func test_ac4_the_rotation_sign_is_not_mirrored() -> void:
	if not _have():
		return
	var rules: RefCounted = Api.rules()
	# A node turned by +30 degrees about Y has its local +x axis at (cos 30, -sin 30) in (x, z), so
	# the +x end of the branch lies at negative z. A stone near (+0.11, -0.07) is hit by +30 and
	# missed by -30; a stone near (+0.11, +0.07) is the other way round.
	var model: AquariumModel = Fx.model()
	Fx.add(model, "a0000001", Fx.STONE, 0.11, -0.07)
	var plus: PlacedItem = _candidate(Fx.BRANCH, 0.0, 0.0, 30.0)
	var minus: PlacedItem = _candidate(Fx.BRANCH, 0.0, 0.0, -30.0)
	assert_bool(Fx.refused(rules, model, plus)).is_true()
	assert_bool(Fx.ok(rules, model, minus)).is_true()
	var mirrored: AquariumModel = Fx.model()
	Fx.add(mirrored, "a0000001", Fx.STONE, 0.11, 0.07)
	assert_bool(Fx.ok(rules, mirrored, plus)).is_true()
	assert_bool(Fx.refused(rules, mirrored, minus)).is_true()


func test_ac9_an_item_with_an_unknown_catalog_id_blocks_nothing() -> void:
	if not _have():
		return
	var rules: RefCounted = Api.rules()
	var model: AquariumModel = Fx.model()
	Fx.add(model, "a0000001", &"no_such_item", 0.0, 0.0)
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void:
			assert_bool(Fx.ok(rules, model, _candidate(Fx.STONE, 0.0, 0.0))).is_true()
			assert_bool(Fx.ok(rules, model, _candidate(Fx.BRANCH, 0.02, 0.0, 33.0))).is_true()
	)
	assert_dict(seen["errors"]).is_empty()
	assert_dict(seen["warnings"]).is_empty()
	assert_int(model.get_item_count()).is_equal(1)
	assert_bool(model.has_uid("a0000001")).is_true()


func test_ac9_an_unknown_item_does_not_hide_a_known_neighbour() -> void:
	if not _have():
		return
	var rules: RefCounted = Api.rules()
	var model: AquariumModel = Fx.model()
	Fx.add(model, "a0000001", &"no_such_item", 0.0, 0.0)
	Fx.add(model, "a0000002", Fx.STONE, 0.2, 0.0)
	assert_bool(Fx.refused(rules, model, _candidate(Fx.STONE, 0.2, 0.0))).is_true()
	assert_bool(Fx.ok(rules, model, _candidate(Fx.STONE, -0.2, 0.0))).is_true()


func test_ac4_a_non_finite_candidate_never_raises_an_error_and_is_refused() -> void:
	if not _have():
		return
	var rules: RefCounted = Api.rules()
	var model: AquariumModel = _with_stone(0.0, 0.0)
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void:
			for bad: float in [NAN, INF, -INF]:
				assert_bool(Fx.refused(rules, model, _candidate(Fx.STONE, bad, 0.2))).is_true()
				assert_bool(Fx.refused(rules, model, _candidate(Fx.STONE, 0.2, bad))).is_true()
				assert_bool(Fx.refused(rules, model, _candidate(Fx.STONE, 0.2, 0.0, bad))).is_true()
	)
	assert_dict(seen["errors"]).is_empty()
	assert_dict(seen["script_errors"]).is_empty()
