extends GdUnitTestSuite
## #31 AC 11 and 30 (owner: developer): the validity seam PlacementRules (game/model, pure).
## The point check is a pure function on the interior rectangle (centre origin): edges count as
## inside, outside, NaN and infinity do not. allows(model, candidate, before) adds the finite
## check of every value and the rotation-only exception (plan section 1: a change that keeps the
## position skips the position check, so items of old saves outside the interior can be turned).
## Run on the medium tank and checked on the small and large tanks too.

const Api := preload("res://tests/helpers/placement_api.gd")
const Factory := preload("res://tests/helpers/factory.gd")

const TANKS: Array[StringName] = [&"tank_small_1", &"tank_medium_1", &"tank_large_1"]
const OUTSIDE_BY_M: float = 0.0001


func _have() -> bool:
	(
		assert_bool(Api.exists(Api.RULES))
		. override_failure_message("res://model/placement_rules.gd is missing")
		. is_true()
	)
	return Api.exists(Api.RULES)


func _interior(tank_id: StringName) -> Vector3:
	return TankCatalog.load_dir().get_definition(tank_id).interior_size_m


func _inside(interior: Vector3, x: float, z: float) -> bool:
	return Api.is_point_inside(interior, x, z) == true


func _model(tank_id: StringName = &"tank_medium_1") -> AquariumModel:
	var model: AquariumModel = AquariumModel.new("2026-11-01T12:00:00Z")
	model.apply_set_tank_id(tank_id)
	return model


func _candidate(x: float, z: float, rotation_y: float = 0.0) -> PlacedItem:
	return Factory.item("c0000001", &"river_stone", Vector3(x, 0.0, z), rotation_y, 1.0)


func test_ac11_the_centre_and_the_edges_are_inside_on_every_tank() -> void:
	if not _have():
		return
	for tank_id: StringName in TANKS:
		var interior: Vector3 = _interior(tank_id)
		var half_x: float = interior.x / 2.0
		var half_z: float = interior.z / 2.0
		for point: Vector2 in [
			Vector2(0.0, 0.0),
			Vector2(half_x, 0.0),
			Vector2(-half_x, 0.0),
			Vector2(0.0, half_z),
			Vector2(0.0, -half_z),
			Vector2(half_x, half_z),
			Vector2(-half_x, -half_z),
			Vector2(half_x, -half_z),
			Vector2(-half_x, half_z),
		]:
			(
				assert_bool(_inside(interior, point.x, point.y))
				. override_failure_message("%s: %s must be inside" % [tank_id, point])
				. is_true()
			)


func test_ac11_a_point_just_outside_an_edge_is_not_inside() -> void:
	if not _have():
		return
	for tank_id: StringName in TANKS:
		var interior: Vector3 = _interior(tank_id)
		var half_x: float = interior.x / 2.0
		var half_z: float = interior.z / 2.0
		for point: Vector2 in [
			Vector2(half_x + OUTSIDE_BY_M, 0.0),
			Vector2(-half_x - OUTSIDE_BY_M, 0.0),
			Vector2(0.0, half_z + OUTSIDE_BY_M),
			Vector2(0.0, -half_z - OUTSIDE_BY_M),
			Vector2(half_x + 1.0, half_z + 1.0),
		]:
			(
				assert_bool(_inside(interior, point.x, point.y))
				. override_failure_message("%s: %s must be outside" % [tank_id, point])
				. is_false()
			)


func test_ac11_nan_and_infinity_are_not_inside_and_raise_no_error() -> void:
	if not _have():
		return
	var interior: Vector3 = _interior(&"tank_medium_1")
	for bad: float in [NAN, INF, -INF]:
		assert_bool(Api.is_point_inside(interior, bad, 0.0) == false).is_true()
		assert_bool(Api.is_point_inside(interior, 0.0, bad) == false).is_true()
		assert_bool(Api.is_point_inside(interior, bad, bad) == false).is_true()


func test_ac11_a_point_inside_a_larger_tank_is_outside_a_smaller_one() -> void:
	if not _have():
		return
	var small: Vector3 = _interior(&"tank_small_1")
	var large: Vector3 = _interior(&"tank_large_1")
	assert_bool(_inside(large, 0.45, 0.0)).is_true()
	assert_bool(_inside(small, 0.45, 0.0)).is_false()


func test_ac11_allows_a_free_inside_position_without_rounding() -> void:
	if not _have():
		return
	var rules: RefCounted = Api.rules()
	var model: AquariumModel = _model()
	assert_bool(rules.call("allows", model, _candidate(0.1234, -0.0567, 37.0), null)).is_true()


func test_ac11_allows_follows_the_tank_of_the_model() -> void:
	if not _have():
		return
	var rules: RefCounted = Api.rules()
	var candidate: PlacedItem = _candidate(0.25, 0.0)
	assert_bool(rules.call("allows", _model(&"tank_medium_1"), candidate, null)).is_true()
	assert_bool(rules.call("allows", _model(&"tank_small_1"), candidate, null)).is_false()


func test_ac30_allows_refuses_a_position_outside_the_interior() -> void:
	if not _have():
		return
	var rules: RefCounted = Api.rules()
	var model: AquariumModel = _model()
	assert_bool(rules.call("allows", model, _candidate(0.31, 0.0), null)).is_false()
	assert_bool(rules.call("allows", model, _candidate(0.0, -0.16), null)).is_false()


func test_ac30_allows_refuses_values_that_are_not_finite() -> void:
	if not _have():
		return
	var rules: RefCounted = Api.rules()
	var model: AquariumModel = _model()
	for bad: float in [NAN, INF, -INF]:
		assert_bool(rules.call("allows", model, _candidate(bad, 0.0), null)).is_false()
		assert_bool(rules.call("allows", model, _candidate(0.0, bad), null)).is_false()
		assert_bool(rules.call("allows", model, _candidate(0.0, 0.0, bad), null)).is_false()
	var tall: PlacedItem = _candidate(0.0, 0.0)
	tall.position.y = NAN
	assert_bool(rules.call("allows", model, tall, null)).is_false()
	var scaled: PlacedItem = _candidate(0.0, 0.0)
	scaled.scale = INF
	assert_bool(rules.call("allows", model, scaled, null)).is_false()


func test_ac11_a_rotation_only_change_skips_the_position_check() -> void:
	if not _have():
		return
	var rules: RefCounted = Api.rules()
	var model: AquariumModel = _model()
	var state_before: PlacedItem = _candidate(0.5, 0.0, 10.0)
	var turned: PlacedItem = _candidate(0.5, 0.0, 25.0)
	assert_bool(rules.call("allows", model, turned, state_before)).is_true()


func test_ac30_a_move_to_another_outside_position_is_refused_even_with_a_before() -> void:
	if not _have():
		return
	var rules: RefCounted = Api.rules()
	var model: AquariumModel = _model()
	var state_before: PlacedItem = _candidate(0.5, 0.0, 10.0)
	var moved: PlacedItem = _candidate(0.45, 0.0, 10.0)
	assert_bool(rules.call("allows", model, moved, state_before)).is_false()


func test_ac11_a_rotation_only_change_still_refuses_a_non_finite_angle() -> void:
	if not _have():
		return
	var rules: RefCounted = Api.rules()
	var model: AquariumModel = _model()
	var state_before: PlacedItem = _candidate(0.0, 0.0, 10.0)
	assert_bool(rules.call("allows", model, _candidate(0.0, 0.0, NAN), state_before)).is_false()
