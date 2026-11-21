extends GdUnitTestSuite
## #33 AC 10 and 11 (owner: developer): placement validity against the heights. Both limits are
## absolute heights above the tank floor: the top of an item is the substrate height at its origin
## plus footprint_cm.y x scale / 100 (5 cm bed plus a 10 cm item is 15 cm). Any item must stay
## under interior_size_m.y; ROCK and ORNAMENT must also stay under water_line_height_m; WOOD and
## PLANT may reach above the water up to the interior height. The tolerance (0.1 mm) applies to
## both limits.
## Tank limits (interior height, water line): small 0.27 and 0.25, medium 0.35 and 0.33, large 0.52
## and 0.50. Beds: sand_fine 0.03 (shallowest), pebbles_river 0.06 (deepest). Fixtures are
## in-memory definitions, 10 x H x 10 cm, alone on the tank so only the height rule can refuse.

const Api := preload("res://tests/helpers/placement_api.gd")
const Fx := preload("res://tests/helpers/validity_fixtures.gd")

const PROBE: StringName = &"probe"
const CATEGORIES: Array[ItemDefinition.Category] = [
	ItemDefinition.Category.ROCK,
	ItemDefinition.Category.ORNAMENT,
	ItemDefinition.Category.WOOD,
	ItemDefinition.Category.PLANT,
]


func _have() -> bool:
	(
		assert_bool(Api.exists(Api.RULES))
		. override_failure_message("res://model/placement_rules.gd is missing")
		. is_true()
	)
	return Api.exists(Api.RULES)


func _is_water_bound(category: ItemDefinition.Category) -> bool:
	return category == ItemDefinition.Category.ROCK or category == ItemDefinition.Category.ORNAMENT


## True when a probe of `category`, `height_m` tall (scale 1), is valid on the tank and bed.
func _valid(
	category: ItemDefinition.Category,
	height_m: float,
	tank: StringName,
	substrate: StringName,
	item_scale: float = 1.0
) -> bool:
	var rules: RefCounted = Fx.rules_of(
		[Fx.definition(PROBE, category, Vector3(10.0, height_m * 100.0, 10.0))]
	)
	var candidate: PlacedItem = Fx.item("c0000001", PROBE, 0.0, 0.0, 0.0, item_scale)
	return Fx.ok(rules, Fx.model(tank, substrate), candidate)


func _refused(
	category: ItemDefinition.Category, height_m: float, tank: StringName, substrate: StringName
) -> bool:
	var rules: RefCounted = Fx.rules_of(
		[Fx.definition(PROBE, category, Vector3(10.0, height_m * 100.0, 10.0))]
	)
	var candidate: PlacedItem = Fx.item("c0000001", PROBE, 0.0, 0.0)
	return Fx.refused(rules, Fx.model(tank, substrate), candidate)


func test_ac10_item_top_adds_the_surface_and_the_scaled_height() -> void:
	if not _have():
		return
	assert_float(Api.item_top(0.0, Vector3(11.0, 10.0, 8.0), 1.0)).is_equal_approx(0.10, 1.0e-9)
	assert_float(Api.item_top(0.05, Vector3(11.0, 10.0, 8.0), 1.0)).is_equal_approx(0.15, 1.0e-9)
	assert_float(Api.item_top(0.05, Vector3(11.0, 10.0, 8.0), 1.5)).is_equal_approx(0.20, 1.0e-9)
	assert_float(Api.item_top(0.03, Vector3(1.0, 24.0, 1.0), 1.0)).is_equal_approx(0.27, 1.0e-9)


func test_ac10_the_item_top_ignores_width_and_depth() -> void:
	if not _have():
		return
	assert_float(Api.item_top(0.03, Vector3(99.0, 8.0, 77.0), 2.0)).is_equal_approx(0.19, 1.0e-9)


func test_ac10_three_centimetre_bed_plus_24_centimetre_item_against_0_27_is_valid() -> void:
	if not _have():
		return
	# Float rounding case: 0.03 + 0.24 against 0.27. A WOOD or PLANT may reach the interior height.
	assert_bool(_valid(ItemDefinition.Category.WOOD, 0.24, Fx.SMALL, Fx.SAND)).is_true()
	assert_bool(_valid(ItemDefinition.Category.PLANT, 0.24, Fx.SMALL, Fx.SAND)).is_true()


func test_ac10_a_top_exactly_at_the_interior_height_is_valid_on_every_tank_and_bed() -> void:
	if not _have():
		return
	for tank: StringName in Fx.TANKS:
		for bed: StringName in [Fx.SAND, Fx.PEBBLES]:
			var height: float = Fx.interior(tank).y - Fx.bed(bed)
			for category: ItemDefinition.Category in [
				ItemDefinition.Category.WOOD, ItemDefinition.Category.PLANT
			]:
				(
					assert_bool(_valid(category, height, tank, bed))
					. override_failure_message(
						(
							"%s %s %s: a top at the interior height must be valid"
							% [tank, bed, category]
						)
					)
					. is_true()
				)


func test_ac10_the_tolerance_applies_to_the_interior_height() -> void:
	if not _have():
		return
	for tank: StringName in Fx.TANKS:
		for bed: StringName in [Fx.SAND, Fx.PEBBLES]:
			var height: float = Fx.interior(tank).y - Fx.bed(bed)
			var wood: ItemDefinition.Category = ItemDefinition.Category.WOOD
			assert_bool(_valid(wood, height + Fx.INSIDE_TOLERANCE_M, tank, bed)).is_true()
			assert_bool(_refused(wood, height + Fx.BEYOND_TOLERANCE_M, tank, bed)).is_true()
			assert_bool(_valid(wood, height - Fx.BEYOND_TOLERANCE_M, tank, bed)).is_true()


func test_ac10_an_item_above_the_interior_height_is_refused_whatever_the_category() -> void:
	if not _have():
		return
	for tank: StringName in Fx.TANKS:
		for bed: StringName in [Fx.SAND, Fx.PEBBLES]:
			var height: float = Fx.interior(tank).y - Fx.bed(bed) + 0.01
			for category: ItemDefinition.Category in CATEGORIES:
				assert_bool(_refused(category, height, tank, bed)).is_true()


func test_ac10_a_deeper_bed_leaves_less_room_the_same_item_fits_sand_not_pebbles() -> void:
	if not _have():
		return
	# Small tank: 0.27 - 0.03 = 0.24 of room over sand, 0.21 over pebbles.
	var wood: ItemDefinition.Category = ItemDefinition.Category.WOOD
	assert_bool(_valid(wood, 0.23, Fx.SMALL, Fx.SAND)).is_true()
	assert_bool(_refused(wood, 0.23, Fx.SMALL, Fx.PEBBLES)).is_true()
	assert_bool(_valid(wood, 0.20, Fx.SMALL, Fx.PEBBLES)).is_true()


func test_ac10_the_scale_multiplies_the_height() -> void:
	if not _have():
		return
	var wood: ItemDefinition.Category = ItemDefinition.Category.WOOD
	# 12 cm at scale 2 is 24 cm: 0.03 + 0.24 = 0.27 fits the small tank; scale 2.1 does not.
	assert_bool(_valid(wood, 0.12, Fx.SMALL, Fx.SAND, 2.0)).is_true()
	assert_bool(_valid(wood, 0.12, Fx.SMALL, Fx.SAND, 2.1)).is_false()


func test_ac10_the_surface_is_the_one_of_the_model_substrate_with_a_five_centimetre_bed() -> void:
	if not _have():
		return
	# A fixture bed of 5 cm (the shipped beds are 3, 4 and 6 cm): 5 cm bed plus a 10 cm item is a
	# top of 15 cm.
	var bed: SubstrateDefinition = SubstrateDefinition.new()
	bed.id = &"bed_5cm"
	bed.name_key = "substrate.bed_5cm.name"
	bed.fill_depth_m = 0.05
	var substrates: SubstrateCatalog = SubstrateCatalog.from_definitions([bed])
	var wood: ItemDefinition.Category = ItemDefinition.Category.WOOD
	var source: RefCounted = (
		Fx
		. source_of(
			[
				Fx.definition(&"h_fits", wood, Vector3(10.0, 22.0, 10.0)),
				Fx.definition(&"h_over", wood, Vector3(10.0, 22.5, 10.0)),
			]
		)
	)
	var rules: RefCounted = Api.rules(source, substrates)
	var model: AquariumModel = Fx.model(Fx.SMALL, &"bed_5cm")
	# 0.05 + 0.22 = 0.27 reaches the interior height exactly; 0.05 + 0.225 is 5 mm over.
	assert_bool(Fx.ok(rules, model, Fx.item("c0000001", &"h_fits", 0.0, 0.0))).is_true()
	assert_bool(Fx.refused(rules, model, Fx.item("c0000001", &"h_over", 0.0, 0.0))).is_true()


func test_ac11_a_rock_or_ornament_stays_under_the_water_line() -> void:
	if not _have():
		return
	for tank: StringName in Fx.TANKS:
		for bed: StringName in [Fx.SAND, Fx.PEBBLES]:
			var limit: float = Fx.water_line(tank) - Fx.bed(bed)
			for category: ItemDefinition.Category in [
				ItemDefinition.Category.ROCK, ItemDefinition.Category.ORNAMENT
			]:
				var label: String = "%s %s %s" % [tank, bed, category]
				(
					assert_bool(_valid(category, limit, tank, bed))
					. override_failure_message(label + ": a top at the water line must be valid")
					. is_true()
				)
				(
					assert_bool(_valid(category, limit + Fx.INSIDE_TOLERANCE_M, tank, bed))
					. override_failure_message(label + ": the tolerance applies to the water line")
					. is_true()
				)
				(
					assert_bool(_refused(category, limit + Fx.BEYOND_TOLERANCE_M, tank, bed))
					. override_failure_message(label + ": beyond the tolerance is refused")
					. is_true()
				)
				(
					assert_bool(_refused(category, limit + 0.01, tank, bed))
					. override_failure_message(label + ": 1 cm above the water is refused")
					. is_true()
				)


func test_ac11_wood_and_plant_may_stand_above_the_water_up_to_the_interior_height() -> void:
	if not _have():
		return
	for tank: StringName in Fx.TANKS:
		for bed: StringName in [Fx.SAND, Fx.PEBBLES]:
			var above_water: float = Fx.water_line(tank) - Fx.bed(bed) + 0.01
			for category: ItemDefinition.Category in [
				ItemDefinition.Category.WOOD, ItemDefinition.Category.PLANT
			]:
				(
					assert_bool(_valid(category, above_water, tank, bed))
					. override_failure_message("%s %s %s above the water" % [tank, bed, category])
					. is_true()
				)
			for category: ItemDefinition.Category in [
				ItemDefinition.Category.ROCK, ItemDefinition.Category.ORNAMENT
			]:
				assert_bool(_refused(category, above_water, tank, bed)).is_true()


func test_ac11_the_water_line_decides_with_the_float_case_three_plus_24_against_0_25() -> void:
	if not _have():
		return
	# On the small tank 0.03 + 0.22 = 0.25 reaches the water line exactly: valid for a rock.
	assert_bool(_valid(ItemDefinition.Category.ROCK, 0.22, Fx.SMALL, Fx.SAND)).is_true()
	assert_bool(_refused(ItemDefinition.Category.ROCK, 0.24, Fx.SMALL, Fx.SAND)).is_true()
	assert_bool(_valid(ItemDefinition.Category.WOOD, 0.24, Fx.SMALL, Fx.SAND)).is_true()


func test_ac11_the_shipped_items_are_far_below_both_limits() -> void:
	if not _have():
		return
	var rules: RefCounted = Api.rules()
	for tank: StringName in Fx.TANKS:
		for bed: StringName in [Fx.SAND, Fx.PEBBLES]:
			var model: AquariumModel = Fx.model(tank, bed)
			for id: StringName in [Fx.STONE, Fx.AMPHORA, Fx.BRANCH]:
				var candidate: PlacedItem = Fx.item("c0000001", id, 0.0, 0.0)
				assert_bool(Fx.ok(rules, model, candidate)).is_true()


func test_ac10_the_height_is_judged_at_the_origin_surface_for_every_position() -> void:
	if not _have():
		return
	# The bed is flat until #29, so the same limit holds off-centre.
	var rules: RefCounted = Fx.rules_of(
		[Fx.definition(PROBE, ItemDefinition.Category.WOOD, Vector3(10.0, 25.0, 10.0))]
	)
	var model: AquariumModel = Fx.model(Fx.SMALL, Fx.SAND)
	assert_bool(Fx.refused(rules, model, Fx.item("c0000001", PROBE, 0.1, 0.05))).is_true()
	assert_bool(Fx.refused(rules, model, Fx.item("c0000001", PROBE, -0.1, -0.05))).is_true()
