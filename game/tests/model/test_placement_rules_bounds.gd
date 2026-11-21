extends GdUnitTestSuite
## #33 AC 1, 2 and 3 (owner: developer): placement validity against the tank interior. The whole
## oriented footprint (footprint_cm x and z times scale, rotated by rotation_y) must lie inside the
## interior rectangle; touching the glass counts as inside, a corner more than the tolerance
## (0.1 mm) outside does not. Checked on the small, medium and large tank with the shipped decor.
## Test decisions: "flush" is the footprint edge exactly on the interior edge; the tolerance cases
## use half and one and a half tolerances; the sign of the rotation is pinned in
## test_placement_rules_overlap.gd (asymmetric fixture).

const Api := preload("res://tests/helpers/placement_api.gd")
const Fx := preload("res://tests/helpers/validity_fixtures.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")

## river_stone footprint x and z in metres.
const STONE_X: float = 0.11
const STONE_Z: float = 0.08


func _have() -> bool:
	(
		assert_bool(Api.exists(Api.RULES))
		. override_failure_message("res://model/placement_rules.gd is missing")
		. is_true()
	)
	return Api.exists(Api.RULES)


func _valid(tank: StringName, id: StringName, x: float, z: float, rotation_y: float = 0.0) -> bool:
	return Fx.ok(Api.rules(), Fx.model(tank), Fx.item("c0000001", id, x, z, rotation_y))


func _refused(
	tank: StringName, id: StringName, x: float, z: float, rotation_y: float = 0.0
) -> bool:
	return Fx.refused(Api.rules(), Fx.model(tank), Fx.item("c0000001", id, x, z, rotation_y))


func test_ac1_the_rules_are_built_with_three_catalogs() -> void:
	if not _have():
		return
	var script: GDScript = Api.script_of(Api.RULES)
	(
		assert_int(Api.init_arg_count(script))
		. override_failure_message(
			"PlacementRules._init must take (tanks, items, substrates) (ADR 0012 Amendment 2)"
		)
		. is_equal(3)
	)


func test_ac1_the_tolerance_is_a_tenth_of_a_millimetre() -> void:
	if not _have():
		return
	assert_float(Api.tolerance()).is_equal_approx(0.0001, 0.0000001)


func test_ac1_an_item_inside_the_interior_is_valid_on_every_tank() -> void:
	if not _have():
		return
	for tank: StringName in Fx.TANKS:
		for id: StringName in [Fx.STONE, Fx.AMPHORA, Fx.BRANCH]:
			(
				assert_bool(_valid(tank, id, 0.0, 0.0))
				. override_failure_message("%s %s at the centre must be valid" % [tank, id])
				. is_true()
			)


func test_ac1_a_free_inside_position_and_angle_is_valid_without_rounding() -> void:
	if not _have():
		return
	assert_bool(_valid(Fx.MEDIUM, Fx.STONE, 0.1234, -0.0567, 37.0)).is_true()


func test_ac3_flush_against_every_wall_is_valid_and_one_centimetre_further_is_not() -> void:
	if not _have():
		return
	for tank: StringName in Fx.TANKS:
		var flush_x: float = Fx.interior(tank).x / 2.0 - STONE_X / 2.0
		var flush_z: float = Fx.interior(tank).z / 2.0 - STONE_Z / 2.0
		for side: float in [-1.0, 1.0]:
			var label: String = "%s side %s" % [tank, side]
			(
				assert_bool(_valid(tank, Fx.STONE, side * flush_x, 0.0))
				. override_failure_message(label + ": flush on the x wall must be valid")
				. is_true()
			)
			(
				assert_bool(_refused(tank, Fx.STONE, side * (flush_x + 0.01), 0.0))
				. override_failure_message(label + ": 1 cm into the x glass must be refused")
				. is_true()
			)
			(
				assert_bool(_valid(tank, Fx.STONE, 0.0, side * flush_z))
				. override_failure_message(label + ": flush on the z wall must be valid")
				. is_true()
			)
			(
				assert_bool(_refused(tank, Fx.STONE, 0.0, side * (flush_z + 0.01)))
				. override_failure_message(label + ": 1 cm into the z glass must be refused")
				. is_true()
			)


func test_ac3_flush_against_a_wall_when_turned_by_90_degrees() -> void:
	if not _have():
		return
	for tank: StringName in Fx.TANKS:
		# Turned by 90 degrees the stone is 8 cm wide in x and 11 cm deep in z.
		var flush_x: float = Fx.interior(tank).x / 2.0 - STONE_Z / 2.0
		var flush_z: float = Fx.interior(tank).z / 2.0 - STONE_X / 2.0
		for angle: float in [90.0, -90.0, 270.0]:
			assert_bool(_valid(tank, Fx.STONE, flush_x, 0.0, angle)).is_true()
			assert_bool(_valid(tank, Fx.STONE, -flush_x, 0.0, angle)).is_true()
			assert_bool(_valid(tank, Fx.STONE, 0.0, flush_z, angle)).is_true()
			assert_bool(_valid(tank, Fx.STONE, 0.0, -flush_z, angle)).is_true()
			assert_bool(_refused(tank, Fx.STONE, flush_x + 0.01, 0.0, angle)).is_true()
			assert_bool(_refused(tank, Fx.STONE, 0.0, flush_z + 0.01, angle)).is_true()
		# The flush spot of the unturned stone is too far out once it is turned (11 cm in z).
		var unturned_z: float = Fx.interior(tank).z / 2.0 - STONE_Z / 2.0
		assert_bool(_refused(tank, Fx.STONE, 0.0, unturned_z, 90.0)).is_true()


func test_ac1_the_tolerance_applies_to_the_glass_at_a_tenth_of_a_millimetre() -> void:
	if not _have():
		return
	for tank: StringName in Fx.TANKS:
		var flush_x: float = Fx.interior(tank).x / 2.0 - STONE_X / 2.0
		var flush_z: float = Fx.interior(tank).z / 2.0 - STONE_Z / 2.0
		assert_bool(_valid(tank, Fx.STONE, flush_x + Fx.INSIDE_TOLERANCE_M, 0.0)).is_true()
		assert_bool(_valid(tank, Fx.STONE, -flush_x - Fx.INSIDE_TOLERANCE_M, 0.0)).is_true()
		assert_bool(_valid(tank, Fx.STONE, 0.0, flush_z + Fx.INSIDE_TOLERANCE_M)).is_true()
		assert_bool(_valid(tank, Fx.STONE, 0.0, -flush_z - Fx.INSIDE_TOLERANCE_M)).is_true()
		assert_bool(_refused(tank, Fx.STONE, flush_x + Fx.BEYOND_TOLERANCE_M, 0.0)).is_true()
		assert_bool(_refused(tank, Fx.STONE, -flush_x - Fx.BEYOND_TOLERANCE_M, 0.0)).is_true()
		assert_bool(_refused(tank, Fx.STONE, 0.0, flush_z + Fx.BEYOND_TOLERANCE_M)).is_true()
		assert_bool(_refused(tank, Fx.STONE, 0.0, -flush_z - Fx.BEYOND_TOLERANCE_M)).is_true()


func test_ac1_the_centre_inside_rule_of_31_is_gone_a_centre_on_the_edge_is_refused() -> void:
	if not _have():
		return
	for tank: StringName in Fx.TANKS:
		var half_x: float = Fx.interior(tank).x / 2.0
		var half_z: float = Fx.interior(tank).z / 2.0
		assert_bool(_refused(tank, Fx.STONE, half_x, 0.0)).is_true()
		assert_bool(_refused(tank, Fx.STONE, 0.0, half_z)).is_true()
		assert_bool(_refused(tank, Fx.STONE, half_x, half_z)).is_true()


func test_ac1_a_position_far_outside_is_refused_and_a_larger_tank_takes_it() -> void:
	if not _have():
		return
	assert_bool(_valid(Fx.LARGE, Fx.STONE, 0.4, 0.0)).is_true()
	assert_bool(_refused(Fx.SMALL, Fx.STONE, 0.4, 0.0)).is_true()
	assert_bool(_refused(Fx.MEDIUM, Fx.STONE, 0.4, 0.0)).is_true()
	assert_bool(_refused(Fx.LARGE, Fx.STONE, 5.0, 5.0)).is_true()


func test_ac1_the_tank_of_the_model_decides() -> void:
	if not _have():
		return
	var candidate: PlacedItem = Fx.item("c0000001", Fx.STONE, 0.24, 0.0)
	var rules: RefCounted = Api.rules()
	assert_bool(Fx.ok(rules, Fx.model(Fx.MEDIUM), candidate)).is_true()
	assert_bool(Fx.refused(rules, Fx.model(Fx.SMALL), candidate)).is_true()
	assert_bool(Fx.ok(rules, Fx.model(Fx.LARGE), candidate)).is_true()


func test_ac1_an_unknown_tank_is_refused_without_an_error() -> void:
	if not _have():
		return
	var other: AquariumModel = Fx.model(&"no_such_tank")
	var candidate: PlacedItem = Fx.item("c0000001", Fx.STONE, 0.0, 0.0)
	var rules: RefCounted = Api.rules()
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void: assert_bool(Fx.refused(rules, other, candidate)).is_true()
	)
	assert_dict(seen["errors"]).is_empty()
	assert_dict(seen["warnings"]).is_empty()


func test_ac2_the_driftwood_branch_on_the_small_tank_at_0_45_48_and_90_degrees() -> void:
	if not _have():
		return
	# 28 x 7 cm in the 25 cm deep tank: 7 cm, 24.7 cm, 25.5 cm and 28 cm across.
	assert_bool(_valid(Fx.SMALL, Fx.BRANCH, 0.0, 0.0, 0.0)).is_true()
	assert_bool(_valid(Fx.SMALL, Fx.BRANCH, 0.0, 0.0, 45.0)).is_true()
	assert_bool(_refused(Fx.SMALL, Fx.BRANCH, 0.0, 0.0, 48.0)).is_true()
	assert_bool(_refused(Fx.SMALL, Fx.BRANCH, 0.0, 0.0, 90.0)).is_true()


func test_ac2_the_same_angles_by_sign_and_by_full_turns() -> void:
	if not _have():
		return
	for angle: float in [-45.0, 315.0, 405.0, 135.0, 225.0]:
		assert_bool(_valid(Fx.SMALL, Fx.BRANCH, 0.0, 0.0, angle)).is_true()
	for angle: float in [-48.0, 312.0, 408.0, 132.0, -90.0, 270.0, 450.0]:
		assert_bool(_refused(Fx.SMALL, Fx.BRANCH, 0.0, 0.0, angle)).is_true()


func test_ac2_the_branch_fits_the_medium_and_large_tank_at_every_angle_at_the_centre() -> void:
	if not _have():
		return
	for tank: StringName in [Fx.MEDIUM, Fx.LARGE]:
		for angle: float in [0.0, 45.0, 48.0, 90.0, 135.0, 200.0]:
			assert_bool(_valid(tank, Fx.BRANCH, 0.0, 0.0, angle)).is_true()


func test_ac1_free_angles_37_minus_30_and_400_at_a_wall() -> void:
	if not _have():
		return
	# Half extent in x of the 11 x 8 stone: 37 degrees 6.7998 cm, -30 degrees 6.7631 cm, 400
	# (= 40) degrees 6.7844 cm. The medium tank half width is 0.30 m.
	assert_bool(_valid(Fx.MEDIUM, Fx.STONE, 0.2315, 0.0, 37.0)).is_true()
	assert_bool(_refused(Fx.MEDIUM, Fx.STONE, 0.2335, 0.0, 37.0)).is_true()
	assert_bool(_valid(Fx.MEDIUM, Fx.STONE, 0.2320, 0.0, -30.0)).is_true()
	assert_bool(_refused(Fx.MEDIUM, Fx.STONE, 0.2335, 0.0, -30.0)).is_true()
	assert_bool(_valid(Fx.MEDIUM, Fx.STONE, 0.2315, 0.0, 400.0)).is_true()
	assert_bool(_refused(Fx.MEDIUM, Fx.STONE, 0.2335, 0.0, 400.0)).is_true()
	assert_bool(_valid(Fx.MEDIUM, Fx.STONE, -0.2315, 0.0, 37.0)).is_true()
	assert_bool(_refused(Fx.MEDIUM, Fx.STONE, -0.2335, 0.0, 37.0)).is_true()


func test_ac1_a_rotated_item_in_a_corner_needs_the_whole_rectangle_inside() -> void:
	if not _have():
		return
	# The stone turned by 45 degrees has a half extent of (5.5 + 4) / sqrt(2) = 6.718 cm both ways.
	var reach: float = (STONE_X + STONE_Z) / 2.0 / sqrt(2.0)
	var x: float = 0.30 - reach
	var z: float = 0.15 - reach
	assert_bool(_valid(Fx.MEDIUM, Fx.STONE, x, z, 45.0)).is_true()
	assert_bool(_valid(Fx.MEDIUM, Fx.STONE, -x, -z, 45.0)).is_true()
	assert_bool(_refused(Fx.MEDIUM, Fx.STONE, x + 0.002, z, 45.0)).is_true()
	assert_bool(_refused(Fx.MEDIUM, Fx.STONE, x, z + 0.002, 45.0)).is_true()


func test_ac1_the_scale_multiplies_the_footprint() -> void:
	if not _have():
		return
	var rules: RefCounted = Api.rules()
	var model: AquariumModel = Fx.model(Fx.MEDIUM)
	# Scale 2: 22 x 16 cm, half extents 0.11 and 0.08.
	var inside_x: PlacedItem = Fx.item("c0000001", Fx.STONE, 0.19, 0.0, 0.0, 2.0)
	var outside_x: PlacedItem = Fx.item("c0000001", Fx.STONE, 0.20, 0.0, 0.0, 2.0)
	var inside_z: PlacedItem = Fx.item("c0000001", Fx.STONE, 0.0, 0.07, 0.0, 2.0)
	var outside_z: PlacedItem = Fx.item("c0000001", Fx.STONE, 0.0, 0.08, 0.0, 2.0)
	assert_bool(Fx.ok(rules, model, inside_x)).is_true()
	assert_bool(Fx.refused(rules, model, outside_x)).is_true()
	assert_bool(Fx.ok(rules, model, inside_z)).is_true()
	assert_bool(Fx.refused(rules, model, outside_z)).is_true()
	# Half scale: 5.5 x 4 cm, half extent 0.0275 in x.
	var half: PlacedItem = Fx.item("c0000001", Fx.STONE, 0.2725, 0.0, 0.0, 0.5)
	assert_bool(Fx.ok(rules, model, half)).is_true()
