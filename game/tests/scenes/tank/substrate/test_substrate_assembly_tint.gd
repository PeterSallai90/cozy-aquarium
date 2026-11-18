extends GdUnitTestSuite
## #28 criterion 31, the tint data of the assembled beds (owner: technical-artist for the assembler
## and the look values; the colour change itself is in test_substrate_bed_scene.gd). The custom
## data of an instance is (lightness factor, hue shift in turns, saturation plus 4 x exposure,
## random 0..1). Per type the lightness spread is within the limits of Scope 9 (sand and black sand
## +-8 %, gravel +-22 %, pebbles +-20 %, coloured gravel +-8 %), at most 5 % of the instances are
## outliers (none for coloured gravel; sand and black sand outliers are lighter), the mean stays
## within 3 % of the swatch lightness, and the hue shift stays within the degrees of Scope 9. The
## look resources carry the same numbers. The baked exposure is a separate shading term and does
## not change the tint data (it is read out of the saturation channel).

const Api := preload("res://tests/helpers/substrate_bed_api.gd")
const Fixture := preload("res://tests/helpers/substrate_bed_fixture.gd")
const Geo := preload("res://tests/helpers/substrate_geometry.gd")
const Sub := preload("res://tests/helpers/substrate_api.gd")
const Table := preload("res://tests/helpers/tank_table.gd")

const OUTLIER_SHARE_MAX := 0.05
const MEAN_TOLERANCE := 0.03
## Lightness spread (fraction) and hue spread (degrees, -1 = not decided) of Scope 9.
const SPREAD: Dictionary = {
	"sand_fine": [0.08, 3.0],
	"sand_black": [0.08, -1.0],
	"gravel_natural": [0.22, 8.0],
	"gravel_coloured": [0.08, 3.0],
	"pebbles_river": [0.20, 10.0],
}


## The custom floats (4 per instance) of the pair, empty after one failed assert while a piece is
## missing.
func _custom(tank_id: StringName, id: StringName) -> PackedFloat32Array:
	var why: String = Fixture.analysis_problem(tank_id, id)
	assert_str(why).override_failure_message("%s in %s: %s" % [id, tank_id, why]).is_empty()
	if not why.is_empty():
		return PackedFloat32Array()
	return Geo.custom_data(Geo.unique_buffers(Fixture.bed_of(tank_id, id)))


func _column(custom: PackedFloat32Array, which: int) -> PackedFloat32Array:
	var values: PackedFloat32Array = PackedFloat32Array()
	for index: int in custom.size() / 4:
		values.append(custom[index * 4 + which])
	return values


func test_ac31_every_instance_has_finite_positive_lightness_and_a_random_in_zero_to_one() -> void:
	for id: StringName in Sub.IDS:
		var custom: PackedFloat32Array = _custom(Table.LARGE, id)
		if custom.is_empty():
			return
		for value: float in _column(custom, 0):
			(
				assert_bool(is_finite(value) and value > 0.0)
				. override_failure_message("%s: lightness %s" % [id, value])
				. is_true()
			)
		for value: float in _column(custom, 3):
			assert_float(value).override_failure_message("%s: random %s" % [id, value]).is_between(
				0.0, 1.0
			)


func test_ac31_the_lightness_spread_stays_within_the_limits_of_scope_9() -> void:
	for tank_id: StringName in Table.IDS:
		for id: StringName in Sub.IDS:
			var custom: PackedFloat32Array = _custom(tank_id, id)
			if custom.is_empty():
				return
			var limit: float = float((SPREAD[String(id)] as Array)[0])
			var outliers: int = 0
			var lighter_only: bool = true
			var lightness: PackedFloat32Array = _column(custom, 0)
			for value: float in lightness:
				if absf(value - 1.0) > limit + 1e-4:
					outliers += 1
					lighter_only = lighter_only and value > 1.0
			var share: float = float(outliers) / float(lightness.size())
			var allowed: float = 0.0 if id == Sub.COLOURED else OUTLIER_SHARE_MAX
			(
				assert_float(share)
				. override_failure_message(
					(
						"%s in %s: %.3f of the instances are outside +-%.2f, at most %.2f allowed"
						% [id, tank_id, share, limit, allowed]
					)
				)
				. is_less_equal(allowed)
			)
			if Api.is_sand(id):
				(
					assert_bool(lighter_only)
					. override_failure_message(
						"%s in %s: a sand outlier is darker than the spread" % [id, tank_id]
					)
					. is_true()
				)


func test_ac31_the_lightness_varies_around_the_swatch_and_its_mean_stays_within_3_percent() -> void:
	for id: StringName in Sub.IDS:
		var custom: PackedFloat32Array = _custom(Table.LARGE, id)
		if custom.is_empty():
			return
		var lightness: PackedFloat32Array = _column(custom, 0)
		var mean: float = Geo.mean_of(lightness)
		(
			assert_float(mean)
			. override_failure_message("%s: mean lightness factor %.4f" % [id, mean])
			. is_equal_approx(1.0, MEAN_TOLERANCE)
		)
		var variance: float = 0.0
		for value: float in lightness:
			variance += (value - mean) * (value - mean)
		var deviation: float = sqrt(variance / float(lightness.size()))
		var limit: float = float((SPREAD[String(id)] as Array)[0])
		(
			assert_float(deviation)
			. override_failure_message(
				"%s: the tone does not vary (standard deviation %.4f)" % [id, deviation]
			)
			. is_greater_equal(0.25 * limit)
		)


func test_ac31_the_hue_shift_stays_within_the_degrees_of_scope_9() -> void:
	for id: StringName in Sub.IDS:
		var custom: PackedFloat32Array = _custom(Table.LARGE, id)
		if custom.is_empty():
			return
		var degrees: float = float((SPREAD[String(id)] as Array)[1])
		for value: float in _column(custom, 1):
			assert_bool(is_finite(value)).is_true()
			if degrees >= 0.0:
				(
					assert_float(absf(value) * 360.0)
					. override_failure_message(
						"%s: hue shift %.3f degrees, limit %.1f" % [id, value * 360.0, degrees]
					)
					. is_less_equal(degrees + 0.01)
				)


func test_ac31_the_saturation_channel_keeps_the_exposure_apart_from_the_saturation() -> void:
	# custom.z = saturation + 4 x exposure with a whole exposure: the saturation part must be a sane
	# factor so the exposure can be told apart.
	for id: StringName in Sub.IDS:
		var custom: PackedFloat32Array = _custom(Table.LARGE, id)
		if custom.is_empty():
			return
		for value: float in _column(custom, 2):
			var saturation: float = Geo.saturation_of(value)
			(
				assert_float(saturation)
				. override_failure_message(
					"%s: saturation part %.3f of %.3f" % [id, saturation, value]
				)
				. is_between(0.0, 2.0)
			)


func test_ac31_the_looks_carry_the_spreads_of_scope_9() -> void:
	for id: StringName in Sub.IDS:
		var look: Resource = Api.look_of(id)
		assert_object(look).override_failure_message("no look for %s" % id).is_not_null()
		if look == null:
			continue
		var wanted: Array = SPREAD[String(id)]
		(
			assert_float(float(look.get("tone_lightness")))
			. override_failure_message("%s: tone_lightness" % id)
			. is_equal_approx(float(wanted[0]), 1e-6)
		)
		if float(wanted[1]) >= 0.0:
			(
				assert_float(float(look.get("tone_hue_deg")))
				. override_failure_message("%s: tone_hue_deg" % id)
				. is_equal_approx(float(wanted[1]), 1e-6)
			)
		assert_float(float(look.get("tone_outlier_share"))).is_between(0.0, OUTLIER_SHARE_MAX)
		assert_float(float(look.get("tone_glint_share"))).is_between(0.0, OUTLIER_SHARE_MAX)
	var coloured: Resource = Api.look_of(Sub.COLOURED)
	if coloured != null:
		assert_float(float(coloured.get("tone_outlier_share"))).is_equal(0.0)
		assert_float(float(coloured.get("tone_glint_share"))).is_equal(0.0)
