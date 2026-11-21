extends GdUnitTestSuite
## #33 AC 15 (d) (file group: developer, pure; reads the shader and material bases only): the
## refusal cue must be clearly visible on items of any colour (owner decisions on PR #161, architect
## addendum 2). No rendering: the edge model of the addendum.
## - The lit item is stood in for by its fixture albedo, converted with srgb_to_linear().
## - At the reference facing (REFUSAL_CUE_REFERENCE_FACING) the rim is fresnel = (1 - facing)^power,
##   a = strength * fresnel, and edge = item * (1 - a) + glow_colour_lin * a + glow_lift * fresnel.
## - Luminance is get_luminance() of the linear colour; colour distance is the Euclidean RGB
##   distance after linear_to_srgb().
## Requirements: (i) cue colour vs selection colour (distance and hue), (ii) peak rim opacity over
## base rim opacity, (iii) on red, pink, orange, dark red and salmon, selected (baseline: the edge
## with the normal mark) and unselected (baseline: the bare item), over steps 0 to 5 of 0.05 s the
## largest luminance increase and the largest colour distance reach the named minimums. Bloom
## guards at every 5 ms step. Every minimum is read from PlacementTuning.

const Api := preload("res://tests/helpers/placement_api.gd")

const MATERIAL := "res://scenes/tank/items/item_selection_material.tres"
const ENVIRONMENT := "res://scenes/room/room_environment.tres"
const STEP_S: float = 0.05
const PEAK_S: float = 0.15
## The sRGB fixtures of the addendum.
const FIXTURES: Dictionary = {
	"red": Color(0.80, 0.18, 0.15),
	"pink": Color(0.95, 0.55, 0.65),
	"orange": Color(0.95, 0.50, 0.15),
	"dark_red": Color(0.60, 0.08, 0.08),
	"salmon": Color(1.0, 0.55, 0.45),
}
## The architect's numbers (selected and unselected, max luminance increase and colour distance),
## a check that the model here is the one of the plan.
const EXPECTED: Dictionary = {
	"red": [0.344, 0.454, 0.482, 0.799],
	"pink": [0.261, 0.245, 0.339, 0.325],
	"orange": [0.281, 0.386, 0.373, 0.603],
	"dark_red": [0.369, 0.487, 0.524, 0.940],
	"salmon": [0.258, 0.294, 0.335, 0.391],
}


func _have() -> bool:
	var found: bool = Api.exists(Api.CUE) and Api.exists(Api.TUNING)
	(
		assert_bool(found)
		. override_failure_message("refusal_cue.gd or placement_tuning.gd is missing")
		. is_true()
	)
	return found


func _material() -> ShaderMaterial:
	return load(MATERIAL) as ShaderMaterial


func _cream() -> Color:
	return _material().get_shader_parameter("glow_colour")


func _base_strength() -> float:
	return float(_material().get_shader_parameter("fresnel_strength"))


func _base_power() -> float:
	return float(_material().get_shader_parameter("fresnel_power"))


func _facing() -> float:
	return Api.tuning("REFUSAL_CUE_REFERENCE_FACING")


func _cue_colour() -> Color:
	return Api.constant(Api.TUNING, "REFUSAL_CUE_COLOUR", Color.BLACK) as Color


## The rim opacity at the reference facing with the cue state at time t (t < 0: the normal mark).
func _rim(t_s: float) -> float:
	var strength: float = Api.cue_strength_at(t_s, _base_strength())
	var power: float = Api.cue_power_at(t_s, _base_power())
	return strength * pow(1.0 - _facing(), power)


## The edge colour (linear) of an item (sRGB albedo) at cue time t; with_mark false is the bare
## item (an unselected item before the cue), the cue itself still adds its own glow.
func _edge(item_srgb: Color, t_s: float) -> Color:
	var item: Color = item_srgb.srgb_to_linear()
	var strength: float = Api.cue_strength_at(t_s, _base_strength())
	var power: float = Api.cue_power_at(t_s, _base_power())
	var fresnel: float = pow(1.0 - _facing(), power)
	var opacity: float = clampf(strength * fresnel, 0.0, 1.0)
	var glow: Color = Api.cue_colour_at(t_s, _cream()).srgb_to_linear()
	var lift: Vector3 = Api.cue_lift_at(t_s)
	return Color(
		item.r * (1.0 - opacity) + glow.r * opacity + lift.x * fresnel,
		item.g * (1.0 - opacity) + glow.g * opacity + lift.y * fresnel,
		item.b * (1.0 - opacity) + glow.b * opacity + lift.z * fresnel
	)


func _distance(a: Color, b: Color) -> float:
	var x: Color = a.linear_to_srgb()
	var y: Color = b.linear_to_srgb()
	return Vector3(x.r - y.r, x.g - y.g, x.b - y.b).length()


## Largest luminance increase and largest colour distance of the steps 0 to 5 against `baseline`.
func _change(item_srgb: Color, baseline: Color) -> Vector2:
	var best_l: float = -INF
	var best_e: float = 0.0
	for step_index: int in 6:
		var edge: Color = _edge(item_srgb, STEP_S * step_index)
		best_l = maxf(best_l, edge.get_luminance() - baseline.get_luminance())
		best_e = maxf(best_e, _distance(edge, baseline))
	return Vector2(best_l, best_e)


func test_the_visibility_minimums_exist_in_placement_tuning() -> void:
	if not _have():
		return
	for constant_name: String in [
		"REFUSAL_CUE_MIN_COLOUR_DISTANCE",
		"REFUSAL_CUE_MIN_HUE_DISTANCE_DEG",
		"REFUSAL_CUE_MIN_PEAK_FACTOR",
		"REFUSAL_CUE_MIN_EDGE_LUMINANCE_CHANGE",
		"REFUSAL_CUE_MIN_EDGE_COLOUR_DISTANCE",
	]:
		assert_float(Api.tuning(constant_name)).override_failure_message(constant_name).is_greater(
			0.0
		)
	assert_float(Api.tuning("REFUSAL_CUE_MIN_COLOUR_DISTANCE")).is_equal_approx(0.35, 0.000001)
	assert_float(Api.tuning("REFUSAL_CUE_MIN_HUE_DISTANCE_DEG")).is_equal_approx(25.0, 0.000001)
	assert_float(Api.tuning("REFUSAL_CUE_MIN_PEAK_FACTOR")).is_equal_approx(2.0, 0.000001)
	assert_float(Api.tuning("REFUSAL_CUE_MIN_EDGE_LUMINANCE_CHANGE")).is_equal_approx(
		0.15, 0.000001
	)
	assert_float(Api.tuning("REFUSAL_CUE_MIN_EDGE_COLOUR_DISTANCE")).is_equal_approx(0.20, 0.000001)


func test_i_the_cue_colour_differs_from_the_selection_colour_by_distance_and_hue() -> void:
	if not _have():
		return
	var cue: Color = _cue_colour()
	var cream: Color = _cream()
	var distance: float = Vector3(cue.r - cream.r, cue.g - cream.g, cue.b - cream.b).length()
	assert_float(distance).is_greater_equal(Api.tuning("REFUSAL_CUE_MIN_COLOUR_DISTANCE"))
	var hue_gap: float = absf(wrapf(cue.h * 360.0 - cream.h * 360.0, -180.0, 180.0))
	assert_float(hue_gap).is_greater_equal(Api.tuning("REFUSAL_CUE_MIN_HUE_DISTANCE_DEG"))


func test_ii_the_peak_rim_opacity_is_a_named_factor_above_the_normal_mark() -> void:
	if not _have():
		return
	var base: float = _rim(-1.0)
	var peak: float = 0.0
	for index: int in 61:
		peak = maxf(peak, _rim(0.005 * index))
	assert_float(base).is_greater(0.0)
	assert_float(peak / base).is_greater_equal(Api.tuning("REFUSAL_CUE_MIN_PEAK_FACTOR"))
	assert_float(Api.cue_strength_at(PEAK_S, _base_strength())).is_greater(_base_strength())
	# Plan values: 0.230914 at the base, 0.636396 at the peak.
	assert_float(base).is_equal_approx(0.230914, 0.0001)
	assert_float(_rim(PEAK_S)).is_equal_approx(0.636396, 0.0001)


func test_iii_the_edge_changes_clearly_on_every_fixture_when_selected() -> void:
	if not _have():
		return
	var min_l: float = Api.tuning("REFUSAL_CUE_MIN_EDGE_LUMINANCE_CHANGE")
	var min_e: float = Api.tuning("REFUSAL_CUE_MIN_EDGE_COLOUR_DISTANCE")
	for key: String in FIXTURES:
		var item: Color = FIXTURES[key]
		# The baseline is the edge with the normal mark (the state before the cue).
		var change: Vector2 = _change(item, _edge(item, -1.0))
		(
			assert_float(change.x)
			. override_failure_message("%s selected: luminance %s" % [key, change.x])
			. is_greater_equal(min_l)
		)
		(
			assert_float(change.y)
			. override_failure_message("%s selected: colour distance %s" % [key, change.y])
			. is_greater_equal(min_e)
		)


func test_iii_the_edge_changes_clearly_on_every_fixture_when_unselected() -> void:
	if not _have():
		return
	var min_l: float = Api.tuning("REFUSAL_CUE_MIN_EDGE_LUMINANCE_CHANGE")
	var min_e: float = Api.tuning("REFUSAL_CUE_MIN_EDGE_COLOUR_DISTANCE")
	for key: String in FIXTURES:
		var item: Color = FIXTURES[key]
		# The baseline is the bare item: an unselected dragged item has no mark before the cue.
		var change: Vector2 = _change(item, item.srgb_to_linear())
		(
			assert_float(change.x)
			. override_failure_message("%s unselected: luminance %s" % [key, change.x])
			. is_greater_equal(min_l)
		)
		(
			assert_float(change.y)
			. override_failure_message("%s unselected: colour distance %s" % [key, change.y])
			. is_greater_equal(min_e)
		)


func test_iii_the_model_here_gives_the_numbers_of_the_plan() -> void:
	if not _have():
		return
	for key: String in FIXTURES:
		var item: Color = FIXTURES[key]
		var selected: Vector2 = _change(item, _edge(item, -1.0))
		var bare: Vector2 = _change(item, item.srgb_to_linear())
		var expected: Array = EXPECTED[key]
		assert_float(selected.x).override_failure_message(key).is_equal_approx(expected[0], 0.002)
		assert_float(selected.y).override_failure_message(key).is_equal_approx(expected[1], 0.002)
		assert_float(bare.x).override_failure_message(key).is_equal_approx(expected[2], 0.002)
		assert_float(bare.y).override_failure_message(key).is_equal_approx(expected[3], 0.002)


func test_iii_the_luminance_change_is_an_increase_the_brightness_peak() -> void:
	if not _have():
		return
	for key: String in FIXTURES:
		var item: Color = FIXTURES[key]
		var baseline: float = _edge(item, -1.0).get_luminance()
		var best: float = -INF
		for step_index: int in 6:
			best = maxf(best, _edge(item, STEP_S * step_index).get_luminance() - baseline)
		assert_float(best).override_failure_message(key).is_greater(0.0)


# --- bloom guards (every 5 ms step of the cue) ---


func _threshold() -> float:
	return (load(ENVIRONMENT) as Environment).glow_hdr_threshold


func test_bloom_proxy_glow_times_strength_plus_lift_stays_below_the_threshold() -> void:
	if not _have():
		return
	var worst: float = 0.0
	for index: int in 61:
		var t_s: float = 0.005 * index
		var glow: Color = Api.cue_colour_at(t_s, _cream()).srgb_to_linear()
		var lift: Vector3 = Api.cue_lift_at(t_s)
		var strength: float = Api.cue_strength_at(t_s, _base_strength())
		var reach: float = maxf(
			glow.r * strength + lift.x, maxf(glow.g * strength + lift.y, glow.b * strength + lift.z)
		)
		worst = maxf(worst, reach)
	assert_float(worst).is_less(_threshold())
	assert_float(worst).is_equal_approx(0.921, 0.01)


func test_bloom_item_aware_silhouette_stays_below_the_threshold_on_every_fixture() -> void:
	if not _have():
		return
	var lit_edge: float = Api.tuning("REFUSAL_CUE_GUARD_LIT_EDGE")
	var worst: float = 0.0
	for key: String in FIXTURES:
		var item: Color = (FIXTURES[key] as Color).srgb_to_linear()
		for index: int in 61:
			var t_s: float = 0.005 * index
			var strength: float = Api.cue_strength_at(t_s, _base_strength())
			# At the silhouette the fresnel term is 1.
			var opacity: float = clampf(strength, 0.0, 1.0)
			var glow: Color = Api.cue_colour_at(t_s, _cream()).srgb_to_linear()
			var lift: Vector3 = Api.cue_lift_at(t_s)
			var bright: float = maxf(
				item.r * lit_edge * (1.0 - opacity) + glow.r * opacity + lift.x,
				maxf(
					item.g * lit_edge * (1.0 - opacity) + glow.g * opacity + lift.y,
					item.b * lit_edge * (1.0 - opacity) + glow.b * opacity + lift.z
				)
			)
			(
				assert_float(bright)
				. override_failure_message("%s at %s s: %s" % [key, t_s, bright])
				. is_less(_threshold())
			)
			worst = maxf(worst, bright)
	assert_float(worst).is_equal_approx(0.980, 0.01)


func test_the_cue_never_leaves_the_unit_range() -> void:
	if not _have():
		return
	for index: int in 61:
		var t_s: float = 0.005 * index
		var strength: float = Api.cue_strength_at(t_s, _base_strength())
		assert_float(strength).is_between(0.0, 1.0)
		assert_float(Api.cue_power_at(t_s, _base_power())).is_greater_equal(0.5)
		var lift: Vector3 = Api.cue_lift_at(t_s)
		for channel: float in [lift.x, lift.y, lift.z]:
			assert_float(channel).is_between(0.0, 1.0)
