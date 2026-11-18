extends GdUnitTestSuite
## #28 criteria 29 and 30 (owner: technical-artist): the drawn grain sizes of the assembled beds.
## The size of an instance is the longest extent of its LOD0 mesh times the longest basis column;
## for sand, whose grain is an ellipsoid (a unit sphere under the basis), twice the longest column
## (see substrate_bed_api.gd). Sand and black sand are drawn 1.0 to 2.5 mm; gravel, coloured gravel
## and pebbles lie in their packing ranges (2 to 6, 3 to 6.5 and 12 to 32 mm) and in 0.8 x real
## minimum to 1.2 x real maximum of the Mode 2 fields; the typical sizes keep the order sand,
## gravel, pebbles with pebbles about 4 x gravel; the real sizes stay as they are.

const Api := preload("res://tests/helpers/substrate_bed_api.gd")
const Fixture := preload("res://tests/helpers/substrate_bed_fixture.gd")
const Geo := preload("res://tests/helpers/substrate_geometry.gd")
const Sub := preload("res://tests/helpers/substrate_api.gd")
const Table := preload("res://tests/helpers/tank_table.gd")

const TOLERANCE_M := 1e-5
## Packing range in mm per type (AC 29 and 30).
const PACKING_MM: Dictionary = {
	"sand_fine": [1.0, 2.5],
	"sand_black": [1.0, 2.5],
	"gravel_natural": [2.0, 6.0],
	"gravel_coloured": [3.0, 6.5],
	"pebbles_river": [12.0, 32.0],
}
## The real grain size range of the Mode 2 fields in mm (unchanged by #28).
const REAL_MM: Dictionary = {
	"sand_fine": [0.2, 1.0],
	"sand_black": [0.2, 1.0],
	"gravel_natural": [2.0, 5.0],
	"gravel_coloured": [3.0, 6.0],
	"pebbles_river": [10.0, 30.0],
}

var _catalog: RefCounted = null


func before_test() -> void:
	_catalog = Sub.catalog()


## The drawn sizes of the pair in metres, empty (after one failed assert) while a piece is missing.
func _sizes(tank_id: StringName, id: StringName) -> PackedFloat32Array:
	var why: String = Fixture.analysis_problem(tank_id, id)
	assert_str(why).override_failure_message("%s in %s: %s" % [id, tank_id, why]).is_empty()
	if not why.is_empty():
		return PackedFloat32Array()
	var grains: Dictionary = Fixture.grains_of(Api.look_of(id))
	return Geo.drawn_sizes(
		Geo.unique_buffers(Fixture.bed_of(tank_id, id)), grains["extents"], Api.is_sand(id)
	)


func _median(sizes: PackedFloat32Array) -> float:
	return Geo.percentile(sizes, 0.5)


func test_ac29_sand_and_black_sand_grains_are_drawn_1_0_to_2_5_mm_and_none_above() -> void:
	for tank_id: StringName in Table.IDS:
		for id: StringName in Api.SAND_IDS:
			var sizes: PackedFloat32Array = _sizes(tank_id, id)
			if sizes.is_empty():
				return
			var low: float = Geo.percentile(sizes, 0.0)
			var high: float = Geo.percentile(sizes, 1.0)
			(
				assert_float(low)
				. override_failure_message("%s in %s: smallest grain %.5f m" % [id, tank_id, low])
				. is_greater_equal(0.001 - TOLERANCE_M)
			)
			(
				assert_float(high)
				. override_failure_message("%s in %s: largest grain %.5f m" % [id, tank_id, high])
				. is_less_equal(0.0025 + TOLERANCE_M)
			)


func test_ac30_every_type_is_drawn_inside_its_packing_range() -> void:
	for tank_id: StringName in Table.IDS:
		for id: StringName in Sub.IDS:
			var sizes: PackedFloat32Array = _sizes(tank_id, id)
			if sizes.is_empty():
				return
			var range_mm: Array = PACKING_MM[String(id)]
			var low: float = Geo.percentile(sizes, 0.0) * 1000.0
			var high: float = Geo.percentile(sizes, 1.0) * 1000.0
			(
				assert_float(low)
				. override_failure_message(
					"%s in %s: smallest %.3f mm, packing range %s" % [id, tank_id, low, range_mm]
				)
				. is_greater_equal(float(range_mm[0]) - 0.01)
			)
			(
				assert_float(high)
				. override_failure_message(
					"%s in %s: largest %.3f mm, packing range %s" % [id, tank_id, high, range_mm]
				)
				. is_less_equal(float(range_mm[1]) + 0.01)
			)


func test_ac30_the_stone_types_stay_within_0_8_x_real_min_and_1_2_x_real_max() -> void:
	for id: StringName in [Sub.GRAVEL, Sub.COLOURED, Sub.PEBBLES]:
		var def: Resource = Sub.definition(_catalog, id)
		var real_min: float = Sub.prop(def, "grain_size_min_mm", 0.0)
		var real_max: float = Sub.prop(def, "grain_size_max_mm", 0.0)
		(
			assert_float(real_min)
			. override_failure_message("%s: no real size in the catalog" % id)
			. is_greater(0.0)
		)
		var sizes: PackedFloat32Array = _sizes(Table.LARGE, id)
		if sizes.is_empty():
			return
		(
			assert_float(Geo.percentile(sizes, 0.0) * 1000.0)
			. override_failure_message(
				"%s: smallest below 0.8 x real minimum %.2f mm" % [id, real_min]
			)
			. is_greater_equal(0.8 * real_min - 0.01)
		)
		(
			assert_float(Geo.percentile(sizes, 1.0) * 1000.0)
			. override_failure_message(
				"%s: largest above 1.2 x real maximum %.2f mm" % [id, real_max]
			)
			. is_less_equal(1.2 * real_max + 0.01)
		)


func test_ac30_the_typical_sizes_keep_the_order_sand_gravel_pebbles_with_pebbles_4x_gravel(
) -> void:
	var sand: PackedFloat32Array = _sizes(Table.LARGE, Sub.SAND)
	var gravel: PackedFloat32Array = _sizes(Table.LARGE, Sub.GRAVEL)
	var pebbles: PackedFloat32Array = _sizes(Table.LARGE, Sub.PEBBLES)
	if sand.is_empty() or gravel.is_empty() or pebbles.is_empty():
		return
	assert_float(_median(sand)).is_less(_median(gravel))
	assert_float(_median(gravel)).is_less(_median(pebbles))
	var ratio: float = _median(pebbles) / _median(gravel)
	assert_float(ratio).override_failure_message("pebbles / gravel median %.2f" % ratio).is_between(
		3.0, 6.0
	)


func test_ac30_the_real_sizes_in_the_mode_2_fields_are_unchanged() -> void:
	for id: StringName in Sub.IDS:
		var def: Resource = Sub.definition(_catalog, id)
		var real: Array = REAL_MM[String(id)]
		(
			assert_float(Sub.prop(def, "grain_size_min_mm", -1.0))
			. override_failure_message("%s: grain_size_min_mm" % id)
			. is_equal_approx(float(real[0]), 1e-6)
		)
		(
			assert_float(Sub.prop(def, "grain_size_max_mm", -1.0))
			. override_failure_message("%s: grain_size_max_mm" % id)
			. is_equal_approx(float(real[1]), 1e-6)
		)


func test_ac30_only_sand_is_drawn_larger_than_real_beyond_the_20_percent() -> void:
	for id: StringName in Sub.IDS:
		var def: Resource = Sub.definition(_catalog, id)
		var real_max: float = Sub.prop(def, "grain_size_max_mm", 0.0)
		var sizes: PackedFloat32Array = _sizes(Table.LARGE, id)
		if sizes.is_empty():
			return
		var drawn_max: float = Geo.percentile(sizes, 1.0) * 1000.0
		if Api.is_sand(id):
			(
				assert_float(drawn_max)
				. override_failure_message(
					(
						"%s: the sand is drawn larger than real (%.2f mm against %.2f mm)"
						% [id, drawn_max, real_max]
					)
				)
				. is_greater(1.2 * real_max)
			)
		else:
			(
				assert_float(drawn_max)
				. override_failure_message(
					"%s: drawn %.2f mm against real %.2f mm" % [id, drawn_max, real_max]
				)
				. is_less_equal(1.2 * real_max + 0.01)
			)


func test_ac30_the_catalog_grain_scale_is_a_drawn_size_of_the_type() -> void:
	for id: StringName in Sub.IDS:
		var scale_value: float = Sub.look(_catalog, id)["grain_scale"]
		var range_mm: Array = PACKING_MM[String(id)]
		(
			assert_float(scale_value * 1000.0)
			. override_failure_message(
				(
					"%s: grain_scale %.5f m is not inside the packing range %s mm"
					% [id, scale_value, range_mm]
				)
			)
			. is_between(float(range_mm[0]), float(range_mm[1]))
		)
