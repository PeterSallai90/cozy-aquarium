# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #28 criteria 1 and 2 (owner: developer): the substrate catalog. Five types in the order of the
## owner table, Mode 1 and Mode 2 fields filled and in range, swatches valid, looks distinct.
## Swatch values are the owner's to judge, so no colour is asserted except the Sand default. Sand
## and Black sand have the same Mode 2 values on purpose (Q12): nothing here compares them.

const Sub := preload("res://tests/helpers/substrate_api.gd")

var _catalog: RefCounted = null


func before_test() -> void:
	_catalog = Sub.catalog()


## Fails once with a readable message while the catalog class or a type is missing.
func _have(id: StringName) -> bool:
	var found: bool = Sub.definition(_catalog, id) != null
	assert_bool(found).override_failure_message("%s is not in the catalog" % id).is_true()
	return found


# --- AC 1: the five types ---


func test_ac01_the_catalog_classes_exist() -> void:
	assert_bool(Sub.script_exists(Sub.DEFINITION_PATH)).is_true()
	assert_bool(Sub.script_exists(Sub.CATALOG_PATH)).is_true()


func test_ac01_the_catalog_holds_exactly_the_five_types() -> void:
	var found: Array = Sub.ids(_catalog)
	assert_int(found.size()).is_equal(5)
	for id: StringName in Sub.IDS:
		assert_bool(found.has(id)).override_failure_message("%s is missing" % id).is_true()


func test_ac01_the_ids_come_in_the_chooser_order_not_the_file_name_order() -> void:
	assert_array(Sub.ids(_catalog)).is_equal(Sub.IDS)


func test_ac01_sort_order_runs_from_1_to_5_in_the_table_order() -> void:
	for index: int in Sub.IDS.size():
		if _have(Sub.IDS[index]):
			var order: int = Sub.prop(Sub.definition(_catalog, Sub.IDS[index]), "sort_order", -1)
			assert_int(order).is_equal(index + 1)


func test_ac01_the_default_type_is_sand() -> void:
	assert_that(Sub.default_id()).is_equal(Sub.SAND)
	var fallback: Variant = null
	if _catalog.has_method("get_default"):
		fallback = _catalog.call("get_default")
	assert_object(fallback).is_not_null()
	assert_that(Sub.prop(fallback, "id", &"")).is_equal(Sub.SAND)


func test_ac01_an_unknown_id_has_no_definition() -> void:
	assert_bool(_catalog.has_method("get_definition")).is_true()
	assert_object(Sub.definition(_catalog, Sub.UNKNOWN_ID)).is_null()
	assert_object(Sub.definition(_catalog, &"")).is_null()


func test_ac01_each_definition_has_its_own_id_and_the_text_keys_of_the_plan() -> void:
	for id: StringName in Sub.IDS:
		if not _have(id):
			continue
		var def: Resource = Sub.definition(_catalog, id)
		assert_that(Sub.prop(def, "id", &"")).is_equal(id)
		assert_str(Sub.prop(def, "name_key", "")).is_equal("substrate.%s.name" % id)
		assert_str(Sub.prop(def, "description_key", "")).is_equal("substrate.%s.description" % id)


func test_ac01_the_sand_default_colour_is_the_decided_cream() -> void:
	if _have(Sub.SAND):
		var colour: Color = Sub.default_colour(_catalog, Sub.SAND)
		assert_bool(Sub.same_colour(colour, Sub.SAND_DEFAULT)).is_true()


func test_ac01_every_default_colour_is_opaque() -> void:
	for id: StringName in Sub.IDS:
		if _have(id):
			assert_float(Sub.default_colour(_catalog, id).a).is_equal(1.0)


func test_ac01_every_type_has_at_least_two_swatches_and_the_first_is_the_default() -> void:
	for id: StringName in Sub.IDS:
		if not _have(id):
			continue
		var list: Array[Color] = Sub.swatches(_catalog, id)
		assert_int(list.size()).override_failure_message("%s: < 2 swatches" % id).is_greater(1)
		if not list.is_empty():
			(
				assert_bool(list[0] == Sub.default_colour(_catalog, id))
				. override_failure_message("%s: swatch 1 is not default_colour" % id)
				. is_true()
			)


func test_ac01_the_look_parameters_are_filled_and_in_range() -> void:
	for id: StringName in Sub.IDS:
		if not _have(id):
			continue
		var look: Dictionary = Sub.look(_catalog, id)
		(
			assert_float(look["grain_scale"])
			. override_failure_message("%s: grain_scale must be > 0 (metres)" % id)
			. is_greater(0.0)
		)
		(
			assert_bool([0, 1, 2].has(int(look["grain_shape"])))
			. override_failure_message("%s: grain_shape is not SPECKLE, ANGULAR or ROUND" % id)
			. is_true()
		)
		assert_float(look["grain_contrast"]).is_between(0.0, 1.0)


func test_ac01_the_grain_scale_is_a_size_in_metres_not_a_pixel_count() -> void:
	# Domain targets are 1.5 to 20 mm apparent grain; anything above 5 cm is the wrong unit.
	for id: StringName in Sub.IDS:
		if _have(id):
			assert_float(Sub.look(_catalog, id)["grain_scale"]).is_less(0.05)


func test_ac01_the_grain_order_is_sand_then_gravel_then_pebbles() -> void:
	if not (_have(Sub.SAND) and _have(Sub.GRAVEL) and _have(Sub.PEBBLES)):
		return
	var sand: float = Sub.look(_catalog, Sub.SAND)["grain_scale"]
	var gravel: float = Sub.look(_catalog, Sub.GRAVEL)["grain_scale"]
	var pebbles: float = Sub.look(_catalog, Sub.PEBBLES)["grain_scale"]
	assert_float(sand).is_less(gravel)
	assert_float(gravel).is_less(pebbles)


# --- AC 1: the Mode 2 fields ---


func test_ac01_the_schema_has_the_fourteen_mode_2_fields() -> void:
	var def: Resource = Sub.new_definition()
	var names: Array = []
	for entry: Dictionary in def.get_property_list():
		names.append(entry["name"])
	for field: String in Sub.MODE_2_FLOATS + Sub.MODE_2_ENUMS:
		(
			assert_bool(names.has(field))
			. override_failure_message("SubstrateDefinition has no field %s" % field)
			. is_true()
		)
	assert_int(Sub.MODE_2_FLOATS.size() + Sub.MODE_2_ENUMS.size()).is_equal(14)


func test_ac01_compaction_risk_was_dropped() -> void:
	var def: Resource = Sub.new_definition()
	for entry: Dictionary in def.get_property_list():
		assert_str(entry["name"]).is_not_equal("compaction_risk")
	assert_bool(Sub.script_exists(Sub.DEFINITION_PATH)).is_true()


func test_ac01_the_water_effect_enum_starts_with_the_unset_sentinel() -> void:
	var water: Variant = Sub.constant(Sub.DEFINITION_PATH, "WaterEffect", {})
	assert_that(water).is_equal({"UNSET": 0, "INERT": 1, "RAISES_SLIGHTLY": 2, "RAISES": 3})


func test_ac01_the_grain_shape_enum_has_the_numbers_the_shader_uses() -> void:
	var shape: Variant = Sub.constant(Sub.DEFINITION_PATH, "GrainShape", {})
	assert_that(shape).is_equal({"SPECKLE": 0, "ANGULAR": 1, "ROUND": 2})


func test_ac01_a_fresh_definition_is_unfilled_so_the_filled_checks_mean_something() -> void:
	var def: Resource = Sub.new_definition()
	assert_bool(Sub.script_exists(Sub.DEFINITION_PATH)).is_true()
	assert_int(Sub.prop(def, "ph_effect", -1)).is_equal(0)
	assert_int(Sub.prop(def, "hardness_effect", -1)).is_equal(0)
	assert_float(Sub.prop(def, "bulk_density_kg_per_l", -1.0)).is_equal(0.0)
	assert_float(Sub.prop(def, "rooting_suitability", -1.0)).is_equal(0.0)
	assert_str(Sub.prop(def, "name_key", "<none>")).is_empty()


func test_ac01_the_water_effects_are_set_and_not_unset() -> void:
	for id: StringName in Sub.IDS:
		if not _have(id):
			continue
		for field: String in Sub.MODE_2_ENUMS:
			var value: int = Sub.prop(Sub.definition(_catalog, id), field, 0)
			assert_int(value).override_failure_message("%s.%s is UNSET" % [id, field]).is_between(
				1, 3
			)


func test_ac01_the_grain_size_range_is_positive_and_ordered() -> void:
	for id: StringName in Sub.IDS:
		if not _have(id):
			continue
		var def: Resource = Sub.definition(_catalog, id)
		var low: float = Sub.prop(def, "grain_size_min_mm", 0.0)
		var high: float = Sub.prop(def, "grain_size_max_mm", 0.0)
		assert_float(low).override_failure_message("%s: grain_size_min_mm" % id).is_greater(0.0)
		assert_float(high).override_failure_message("%s: min > max grain" % id).is_greater_equal(
			low
		)


func test_ac01_the_layer_depth_is_positive_and_min_default_max_ordered() -> void:
	for id: StringName in Sub.IDS:
		if not _have(id):
			continue
		var def: Resource = Sub.definition(_catalog, id)
		var low: float = Sub.prop(def, "layer_depth_min_cm", 0.0)
		var mid: float = Sub.prop(def, "layer_depth_default_cm", 0.0)
		var high: float = Sub.prop(def, "layer_depth_max_cm", 0.0)
		assert_float(low).override_failure_message("%s: layer_depth_min_cm" % id).is_greater(0.0)
		assert_float(mid).override_failure_message("%s: default < min" % id).is_greater_equal(low)
		assert_float(high).override_failure_message("%s: max < default" % id).is_greater_equal(mid)


func test_ac01_the_bulk_density_is_positive() -> void:
	for id: StringName in Sub.IDS:
		if _have(id):
			var density: float = Sub.prop(
				Sub.definition(_catalog, id), "bulk_density_kg_per_l", 0.0
			)
			assert_float(density).override_failure_message("%s: density" % id).is_greater(0.0)


func test_ac01_the_six_suitability_fields_are_in_zero_exclusive_to_one() -> void:
	for id: StringName in Sub.IDS:
		if not _have(id):
			continue
		for field: String in Sub.UNIT_RANGE_FIELDS:
			var value: float = Sub.prop(Sub.definition(_catalog, id), field, 0.0)
			(
				assert_float(value)
				. override_failure_message("%s.%s = %s is not in (0, 1]" % [id, field, value])
				. is_between(0.0001, 1.0)
			)


# --- AC 2: swatches and looks ---


func test_ac02_every_swatch_is_opaque() -> void:
	for id: StringName in Sub.IDS:
		for colour: Color in Sub.swatches(_catalog, id):
			(
				assert_float(colour.a)
				. override_failure_message("%s: swatch %s is not opaque" % [id, Sub.hex(colour)])
				. is_equal(1.0)
			)
	assert_int(Sub.ids(_catalog).size()).is_equal(5)


func test_ac02_no_swatch_is_repeated_inside_a_type() -> void:
	for id: StringName in Sub.IDS:
		var seen: Dictionary = {}
		for colour: Color in Sub.swatches(_catalog, id):
			var key: int = colour.to_rgba32()
			(
				assert_bool(seen.has(key))
				. override_failure_message("%s: swatch %s appears twice" % [id, Sub.hex(colour)])
				. is_false()
			)
			seen[key] = true
	assert_int(Sub.ids(_catalog).size()).is_equal(5)


func test_ac02_every_catalog_colour_is_an_exact_8_bit_value() -> void:
	# ADR 0010 rule 7: it must survive a save (#RRGGBB) and a load unchanged.
	for id: StringName in Sub.IDS:
		var colours: Array[Color] = Sub.swatches(_catalog, id)
		colours.append(Sub.default_colour(_catalog, id))
		for colour: Color in colours:
			var round_trip: Color = Color.html(colour.to_html(false))
			(
				assert_bool(
					(
						absf(round_trip.r - colour.r) < 1e-6
						and absf(round_trip.g - colour.g) < 1e-6
						and absf(round_trip.b - colour.b) < 1e-6
					)
				)
				. override_failure_message("%s: %s is not an exact 8-bit colour" % [id, colour])
				. is_true()
			)
	assert_int(Sub.ids(_catalog).size()).is_equal(5)


func test_ac02_no_two_types_share_the_same_look_triple() -> void:
	var seen: Dictionary = {}
	for id: StringName in Sub.IDS:
		if not _have(id):
			continue
		var look: Dictionary = Sub.look(_catalog, id)
		var key: String = (
			"%s|%s|%s" % [look["grain_scale"], look["grain_shape"], look["grain_contrast"]]
		)
		(
			assert_bool(seen.has(key))
			. override_failure_message(
				(
					"%s and %s have the same (grain_scale, grain_shape, grain_contrast)"
					% [id, seen.get(key)]
				)
			)
			. is_false()
		)
		seen[key] = id


func test_ac02_the_old_placeholder_file_is_gone() -> void:
	assert_bool(FileAccess.file_exists("res://catalog/substrates/.gitkeep")).is_false()
	assert_int(Sub.ids(_catalog).size()).is_equal(5)
