extends GdUnitTestSuite
## #34 AC 14, 15 and 28 (owner: developer), ADR 0013 rule 7 and plan section 1: the pure helper
## FishZones.origin_range(zone, surface_at, x, z, water_line_m, grain_allowance_m, extents) gives
## the vertical range of a fish origin at a tank-local (x, z), in metres.
## Column H = water_line - 0.03 - S; bands of H: BOTTOM 0 to 0.25, MIDDLE 0.25 to 0.75, TOP 0.75 to
## 1.0 (UNSET reads as MIDDLE); lower limit L = S + extent_below, for BOTTOM
## S + max(0.01, extent_below) + grain_allowance; upper limit U = water_line - extent_above; when
## L <= U the range is [clamp(band_lo, L, U), clamp(band_hi, L, U)] with BOTTOM band_lo = L; else it
## is pinned to (L + U) / 2 and reported. The surface Callable is called on every query.
## The extents are synthetic here (the plan's numbers for the three species) so this suite does not
## wait for the models; the real extents are used in test_fish_view.gd.

const Api := preload("res://tests/helpers/fish_api.gd")

const TOP_MARGIN := 0.03
const MIN_CLEARANCE := 0.01
const EPS := 1e-6
## Corydoras: extent below the origin about 0.95 cm.
const CORY_BELOW := 0.0095
const CORY_ABOVE := 0.0105
const NEON_BELOW := 0.005
const NEON_ABOVE := 0.006
## Angelfish: total height 18.6 cm at most (1.55 body units at 12 cm).
const ANGEL_BELOW := 0.095
const ANGEL_ABOVE := 0.091
const SMALL_INTERIOR := Vector3(0.40, 0.27, 0.25)
const SMALL_WATER := 0.25


func _have_zones() -> bool:
	var is_ready: bool = Api.script_of(Api.ZONES_PATH) != null
	assert_bool(is_ready).override_failure_message("FishZones is missing").is_true()
	return is_ready


func _flat(height: float) -> Callable:
	return func(_x: float, _z: float) -> float: return height


## The plan formula, written out for the expected values.
func _expected(
	zone: int, surface: float, water: float, below: float, above: float, allowance: float
) -> Dictionary:
	var column: float = water - TOP_MARGIN - surface
	var low: float = surface + below
	if zone == Api.ZONE_BOTTOM:
		low = surface + maxf(MIN_CLEARANCE, below) + allowance
	var high: float = water - above
	if low > high:
		return {"min_y": (low + high) / 2.0, "max_y": (low + high) / 2.0, "pinned": true}
	var band_lo: float = surface
	var band_hi: float = surface + column
	if zone == Api.ZONE_BOTTOM:
		band_lo = low
		band_hi = surface + 0.25 * column
	elif zone == Api.ZONE_TOP:
		band_lo = surface + 0.75 * column
	else:
		band_lo = surface + 0.25 * column
		band_hi = surface + 0.75 * column
	return {
		"min_y": clampf(band_lo, low, high),
		"max_y": clampf(band_hi, low, high),
		"pinned": false,
	}


func _range(zone: int, surface: float, below: float, above: float, allowance: float) -> Dictionary:
	return Api.origin_range(
		zone, _flat(surface), 0.0, 0.0, SMALL_WATER, allowance, Api.extents(0.02, below, above)
	)


# --- constants ---


func test_ac14_the_named_constants_have_the_plan_values() -> void:
	var path: String = Api.ZONES_PATH
	assert_float(Api.constant(path, "TOP_MARGIN_M", -1.0)).is_equal_approx(0.03, EPS)
	assert_float(Api.constant(path, "BOTTOM_CLEARANCE_MIN_M", -1.0)).is_equal_approx(0.01, EPS)
	assert_float(Api.constant(path, "BOTTOM_BAND_TOP", -1.0)).is_equal_approx(0.25, EPS)
	assert_float(Api.constant(path, "MIDDLE_BAND_TOP", -1.0)).is_equal_approx(0.75, EPS)


# --- AC 14: the plan formula for every zone ---


func test_ac14_every_zone_matches_the_plan_formula_over_surfaces_and_extents() -> void:
	if not _have_zones():
		return
	var extents_list: Array = [
		[NEON_BELOW, NEON_ABOVE], [CORY_BELOW, CORY_ABOVE], [0.0, 0.0], [0.05, 0.05]
	]
	for zone: int in [Api.ZONE_UNSET, Api.ZONE_TOP, Api.ZONE_MIDDLE, Api.ZONE_BOTTOM]:
		for surface: float in [0.03, 0.04, 0.06]:
			for pair: Array in extents_list:
				var allowance: float = 0.003
				var got: Dictionary = _range(zone, surface, pair[0], pair[1], allowance)
				var want: Dictionary = _expected(
					Api.ZONE_MIDDLE if zone == Api.ZONE_UNSET else zone,
					surface,
					SMALL_WATER,
					pair[0],
					pair[1],
					allowance
				)
				var label: String = "zone %d surface %.2f extents %s" % [zone, surface, pair]
				(
					assert_bool(got.is_empty())
					. override_failure_message(label + ": no result")
					. is_false()
				)
				if got.is_empty():
					continue
				(
					assert_float(got["min_y"])
					. override_failure_message(label + " min_y")
					. is_equal_approx(want["min_y"], EPS)
				)
				(
					assert_float(got["max_y"])
					. override_failure_message(label + " max_y")
					. is_equal_approx(want["max_y"], EPS)
				)
				assert_bool(got["pinned"]).override_failure_message(label + " pinned").is_equal(
					want["pinned"]
				)


func test_ac14_hand_computed_top_zone_in_the_small_tank_with_pebbles() -> void:
	if not _have_zones():
		return
	# S 0.06, column 0.25 - 0.03 - 0.06 = 0.16: TOP is S + 0.75 * 0.16 to S + 0.16.
	var got: Dictionary = _range(Api.ZONE_TOP, 0.06, NEON_BELOW, NEON_ABOVE, 0.016)
	assert_float(got.get("min_y", -1.0)).is_equal_approx(0.18, EPS)
	assert_float(got.get("max_y", -1.0)).is_equal_approx(0.22, EPS)


func test_ac14_unset_reads_as_middle() -> void:
	if not _have_zones():
		return
	var unset: Dictionary = _range(Api.ZONE_UNSET, 0.04, NEON_BELOW, NEON_ABOVE, 0.0)
	var middle: Dictionary = _range(Api.ZONE_MIDDLE, 0.04, NEON_BELOW, NEON_ABOVE, 0.0)
	assert_dict(unset).is_equal(middle)
	assert_bool(unset.is_empty()).is_false()


func test_ac14_the_bottom_clearance_is_never_below_one_centimetre() -> void:
	if not _have_zones():
		return
	var got: Dictionary = _range(Api.ZONE_BOTTOM, 0.03, 0.0, 0.0, 0.0)
	assert_float(got.get("min_y", -1.0)).is_equal_approx(0.04, EPS)
	assert_bool(got.get("min_y", 0.0) > 0.03).is_true()


func test_ac14_a_bottom_fish_rests_at_the_lower_limit() -> void:
	if not _have_zones():
		return
	var got: Dictionary = _range(Api.ZONE_BOTTOM, 0.04, CORY_BELOW, CORY_ABOVE, 0.003)
	assert_float(got.get("min_y", -1.0)).is_equal_approx(
		0.04 + maxf(MIN_CLEARANCE, CORY_BELOW) + 0.003, EPS
	)
	assert_bool(got.get("max_y", -1.0) >= got.get("min_y", 0.0)).is_true()


# --- AC 14: the surface is read on every call, at the asked point ---


func test_ac14_the_helper_calls_the_surface_on_every_query_and_never_caches() -> void:
	if not _have_zones():
		return
	var calls: Array[int] = [0]
	var surface: Callable = func(_x: float, _z: float) -> float:
		calls[0] += 1
		return 0.04
	var fish_extents: Object = Api.extents(0.02, CORY_BELOW, CORY_ABOVE)
	Api.origin_range(Api.ZONE_BOTTOM, surface, 0.0, 0.0, SMALL_WATER, 0.0, fish_extents)
	var after_one: int = calls[0]
	assert_int(after_one).is_greater_equal(1)
	Api.origin_range(Api.ZONE_BOTTOM, surface, 0.0, 0.0, SMALL_WATER, 0.0, fish_extents)
	var after_two: int = calls[0]
	assert_int(after_two).is_greater(after_one)
	Api.origin_range(Api.ZONE_BOTTOM, surface, 0.1, 0.05, SMALL_WATER, 0.0, fish_extents)
	assert_int(calls[0]).is_greater(after_two)


func test_ac15_edge_a_stand_in_with_two_heights_gives_two_lower_limits() -> void:
	if not _have_zones():
		return
	var uneven: Callable = func(x: float, _z: float) -> float: return 0.03 if x < 0.0 else 0.06
	var fish_extents: Object = Api.extents(0.02, CORY_BELOW, CORY_ABOVE)
	var left: Dictionary = Api.origin_range(
		Api.ZONE_BOTTOM, uneven, -0.1, 0.0, SMALL_WATER, 0.0015, fish_extents
	)
	var right: Dictionary = Api.origin_range(
		Api.ZONE_BOTTOM, uneven, 0.1, 0.0, SMALL_WATER, 0.0015, fish_extents
	)
	assert_float(left.get("min_y", -1.0)).is_equal_approx(0.0415, EPS)
	assert_float(right.get("min_y", -1.0)).is_equal_approx(0.0715, EPS)
	assert_float(right.get("min_y", 0.0) - left.get("min_y", 0.0)).is_equal_approx(0.03, EPS)


func test_ac15_the_surface_receives_the_asked_x_and_z() -> void:
	if not _have_zones():
		return
	var seen: Array[Vector2] = []
	var surface: Callable = func(x: float, z: float) -> float:
		seen.append(Vector2(x, z))
		return 0.03
	Api.origin_range(
		Api.ZONE_MIDDLE, surface, 0.12, -0.07, SMALL_WATER, 0.0, Api.extents(0.02, 0.005, 0.005)
	)
	assert_bool(seen.has(Vector2(0.12, -0.07))).is_true()


# --- AC 15: the corydoras over the real substrates ---


func test_ac15_corydoras_rests_on_the_stone_tops_for_every_shipped_substrate() -> void:
	if not _have_zones():
		return
	var substrates: SubstrateCatalog = SubstrateCatalog.load_dir()
	# substrate id: [depth, expected resting height with e = 0.95 cm, 1 mm tolerance]
	var cases: Dictionary = {
		&"sand_fine": [0.03, 0.0415],
		&"gravel_natural": [0.04, 0.053],
		&"gravel_coloured": [0.04, 0.0533],
		&"pebbles_river": [0.06, 0.086],
	}
	for id: StringName in cases:
		var definition: SubstrateDefinition = substrates.get_definition(id)
		var surface: Callable = Api.surface_source(
			definition, PackedFloat32Array(), Vector2i.ZERO, SMALL_INTERIOR
		)
		(
			assert_bool(surface.is_valid())
			. override_failure_message("FishZones.surface_source gives no Callable for %s" % id)
			. is_true()
		)
		if not surface.is_valid():
			continue
		var allowance: float = Api.top_allowance(definition)
		var got: Dictionary = Api.origin_range(
			Api.ZONE_BOTTOM,
			surface,
			0.05,
			0.02,
			SMALL_WATER,
			allowance,
			Api.extents(0.04, CORY_BELOW, CORY_ABOVE)
		)
		var depth: float = (cases[id] as Array)[0]
		var resting: float = (cases[id] as Array)[1]
		(
			assert_float(got.get("min_y", -1.0))
			. override_failure_message("corydoras on %s" % id)
			. is_equal_approx(resting, 0.001)
		)
		assert_float(got.get("min_y", -1.0)).is_equal_approx(
			depth + maxf(MIN_CLEARANCE, CORY_BELOW) + allowance, EPS
		)
		assert_bool(got.get("min_y", 0.0) > depth + allowance).is_true()


func test_ac15_surface_source_follows_the_definition_and_ignores_the_point_while_flat() -> void:
	if not _have_zones():
		return
	var substrates: SubstrateCatalog = SubstrateCatalog.load_dir()
	var sand: Callable = Api.surface_source(
		substrates.get_definition(&"sand_fine"), PackedFloat32Array(), Vector2i.ZERO, SMALL_INTERIOR
	)
	var pebbles: Callable = Api.surface_source(
		substrates.get_definition(&"pebbles_river"),
		PackedFloat32Array(),
		Vector2i.ZERO,
		SMALL_INTERIOR
	)
	assert_bool(sand.is_valid() and pebbles.is_valid()).is_true()
	if sand.is_valid() and pebbles.is_valid():
		assert_float(sand.call(0.1, 0.05)).is_equal_approx(0.03, EPS)
		assert_float(sand.call(-0.1, -0.05)).is_equal_approx(0.03, EPS)
		assert_float(pebbles.call(0.0, 0.0)).is_equal_approx(0.06, EPS)


# --- AC 28: fish height and the water column ---


func test_ac28_the_angelfish_fits_the_small_tank_column_with_pebbles_and_is_not_pinned() -> void:
	if not _have_zones():
		return
	var got: Dictionary = _range(Api.ZONE_MIDDLE, 0.06, ANGEL_BELOW, ANGEL_ABOVE, 0.016)
	assert_bool(got.is_empty()).is_false()
	assert_bool(got.get("pinned", true)).is_false()
	(
		assert_bool(got.get("min_y", 0.0) - ANGEL_BELOW >= 0.06 - EPS)
		. override_failure_message("fins below the substrate surface")
		. is_true()
	)
	(
		assert_bool(got.get("max_y", 1.0) + ANGEL_ABOVE <= SMALL_WATER + EPS)
		. override_failure_message("fins above the water line")
		. is_true()
	)


func test_ac28_other_zones_are_clamped_by_the_extents_not_by_the_clearance() -> void:
	if not _have_zones():
		return
	var got: Dictionary = _range(Api.ZONE_MIDDLE, 0.06, ANGEL_BELOW, ANGEL_ABOVE, 0.016)
	assert_float(got.get("max_y", -1.0)).is_equal_approx(SMALL_WATER - ANGEL_ABOVE, EPS)
	assert_float(got.get("min_y", -1.0)).is_equal_approx(0.06 + ANGEL_BELOW, EPS)


func test_ac28_edge_a_column_too_small_pins_the_origin_to_the_middle_and_reports_it() -> void:
	if not _have_zones():
		return
	# L = 0.03 + 0.2 = 0.23, U = 0.25 - 0.2 = 0.05: the fish is taller than the water.
	for zone: int in [Api.ZONE_TOP, Api.ZONE_MIDDLE, Api.ZONE_BOTTOM]:
		var got: Dictionary = _range(zone, 0.03, 0.2, 0.2, 0.0)
		(
			assert_bool(got.get("pinned", false))
			. override_failure_message("zone %d is not reported as pinned" % zone)
			. is_true()
		)
		var middle: float = ((0.03 + 0.2) + (0.25 - 0.2)) / 2.0
		assert_float(got.get("min_y", -1.0)).is_equal_approx(middle, EPS)
		assert_float(got.get("max_y", -1.0)).is_equal_approx(middle, EPS)


func test_ac28_the_pin_is_not_reported_when_the_fish_just_fits() -> void:
	if not _have_zones():
		return
	# L = U exactly: 0.03 + 0.1 = 0.25 - 0.12.
	var got: Dictionary = _range(Api.ZONE_MIDDLE, 0.03, 0.1, 0.12, 0.0)
	assert_bool(got.get("pinned", true)).is_false()
	assert_float(got.get("min_y", -1.0)).is_equal_approx(0.13, EPS)
	assert_float(got.get("max_y", -1.0)).is_equal_approx(0.13, EPS)
