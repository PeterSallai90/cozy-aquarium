extends GdUnitTestSuite
## #34 AC 1, 2, 33 and the catalog API (owner: developer): the FishSpecies schema and the
## FishCatalog loader with the three shipped species, their Mode 2 data and the variant order.
## FishSpecies and FishCatalog are reached by path (FishApi), so the suite runs and fails with a
## readable message while the classes are missing.
## Test decisions where the plan is silent: the Mode 2 values of the issue table are pinned as
## the domain BA data; a duplicate id in from_definitions is skipped and reported in get_skipped
## (as ItemCatalog does); the variant colours themselves are a look judgment (preview, AC 33) and
## are guarded by the snapshot test, so only count, alpha and uniqueness are checked here.

const Api := preload("res://tests/helpers/fish_api.gd")

const MODE_2_FIELDS: PackedStringArray = [
	"temp_min_c",
	"temp_max_c",
	"ph_min",
	"ph_max",
	"min_group_size",
	"min_tank_litres",
	"bioload",
	"temperament",
	"diet",
	"light_preference",
	"needs_hiding_places",
	"incompatible_with",
]
const MODE_1_FIELDS: PackedStringArray = [
	"id",
	"name_key",
	"description_key",
	"scientific_name",
	"scene",
	"colour_variants",
	"adult_length_cm",
	"preferred_zone",
	"schooling",
	"swim_speed",
]
const ZONE_MIDDLE := 2
const ZONE_BOTTOM := 3
const PEACEFUL := 1
const SEMI_AGGRESSIVE := 2
const LIGHT_LOW := 1
const LIGHT_MODERATE := 2
## Species id to [zone, schooling, swim_speed].
const MODE_1: Dictionary[StringName, Array] = {
	&"neon_tetra": [ZONE_MIDDLE, true, 1.3],
	&"angelfish": [ZONE_MIDDLE, false, 0.5],
	&"bronze_corydoras": [ZONE_BOTTOM, true, 0.8],
}
## Species id to [temp_min, temp_max, ph_min, ph_max, group, litres, bioload, temperament, light,
## hiding places, incompatible_with].
const MODE_2: Dictionary[StringName, Array] = {
	&"neon_tetra": [20.0, 26.0, 5.5, 7.5, 6, 40, 0.2, PEACEFUL, LIGHT_LOW, false, [&"angelfish"]],
	&"angelfish":
	[24.0, 30.0, 6.0, 7.5, 1, 150, 2.5, SEMI_AGGRESSIVE, LIGHT_MODERATE, true, [&"neon_tetra"]],
	&"bronze_corydoras": [22.0, 26.0, 6.0, 8.0, 6, 72, 1.0, PEACEFUL, LIGHT_MODERATE, true, []],
}
const DIETS: Dictionary[StringName, Array] = {
	&"neon_tetra": [&"flakes", &"pellets", &"live"],
	&"angelfish": [&"flakes", &"pellets", &"live", &"frozen"],
	&"bronze_corydoras": [&"sinking_pellets", &"live", &"frozen"],
}
## AC 33: the variant count per species (the order is the saved index).
const VARIANT_COUNTS: Dictionary[StringName, int] = {
	&"neon_tetra": 2,
	&"angelfish": 3,
	&"bronze_corydoras": 2,
}


func _have_catalog() -> bool:
	var ready: bool = (
		Api.script_of(Api.CATALOG_PATH) != null and Api.script_of(Api.SPECIES_PATH) != null
	)
	(
		assert_bool(ready)
		. override_failure_message("FishSpecies and FishCatalog scripts are missing")
		. is_true()
	)
	return ready and Api.shipped() != null


func _species_or_fail(id: StringName) -> Resource:
	var species: Resource = Api.species(id)
	assert_object(species).override_failure_message("no species %s" % id).is_not_null()
	return species


## Failures of the Mode 2 rules of AC 2 for one definition (empty when it passes).
func _mode2_failures(definition: Resource) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	if int(definition.get("temperament")) == 0:
		failures.append("temperament is UNSET")
	if int(definition.get("light_preference")) == 0:
		failures.append("light_preference is UNSET")
	if float(definition.get("temp_min_c")) >= float(definition.get("temp_max_c")):
		failures.append("temp_min_c is not below temp_max_c")
	if float(definition.get("ph_min")) >= float(definition.get("ph_max")):
		failures.append("ph_min is not below ph_max")
	if int(definition.get("min_group_size")) < 1:
		failures.append("min_group_size is below 1")
	if int(definition.get("min_tank_litres")) <= 0:
		failures.append("min_tank_litres is not above 0")
	if float(definition.get("bioload")) <= 0.0:
		failures.append("bioload is not above 0")
	if (definition.get("diet") as Array).is_empty():
		failures.append("diet is empty")
	return failures


# --- AC 1 ---


func test_ac01_catalog_has_exactly_the_three_species() -> void:
	if not _have_catalog():
		return
	var ids: Array = Api.shipped().call("get_ids")
	var sorted_ids: Array = ids.duplicate()
	sorted_ids.sort()
	assert_array(sorted_ids).is_equal([&"angelfish", &"bronze_corydoras", &"neon_tetra"])
	var skipped: Array = Api.shipped().call("get_skipped")
	assert_int(skipped.size()).is_equal(0)


func test_ac01_every_species_has_its_keys_name_scene_and_positive_numbers() -> void:
	if not _have_catalog():
		return
	for id: StringName in Api.IDS:
		var species: Resource = _species_or_fail(id)
		if species == null:
			continue
		assert_str(str(species.get("id"))).is_equal(str(id))
		assert_str(species.get("name_key")).is_equal("fish.%s.name" % id)
		assert_str(species.get("description_key")).is_equal("fish.%s.description" % id)
		assert_str(species.get("scientific_name")).is_not_empty()
		assert_object(species.get("scene")).is_not_null()
		assert_float(species.get("adult_length_cm")).is_greater(0.0)
		assert_float(species.get("swim_speed")).is_greater(0.0)


func test_ac01_adult_lengths_zones_and_swim_speeds_are_the_issue_values() -> void:
	if not _have_catalog():
		return
	for id: StringName in Api.IDS:
		var species: Resource = _species_or_fail(id)
		if species == null:
			continue
		var expected: Array = MODE_1[id]
		assert_int(species.get("preferred_zone")).is_equal(expected[0])
		assert_bool(species.get("schooling")).is_equal(expected[1])
		assert_float(species.get("swim_speed")).is_equal_approx(expected[2], 1e-6)
	assert_float(Api.field(&"neon_tetra", "adult_length_cm", -1.0)).is_equal_approx(3.0, 1e-6)
	assert_float(Api.field(&"angelfish", "adult_length_cm", -1.0)).is_equal_approx(12.0, 1e-6)
	assert_float(Api.field(&"bronze_corydoras", "adult_length_cm", -1.0)).is_equal_approx(5.5, 1e-6)


func test_ac01_scientific_names_are_the_latin_binomials() -> void:
	if not _have_catalog():
		return
	assert_str(Api.field(&"neon_tetra", "scientific_name", "")).is_equal("Paracheirodon innesi")
	assert_str(Api.field(&"angelfish", "scientific_name", "")).is_equal("Pterophyllum scalare")
	assert_str(Api.field(&"bronze_corydoras", "scientific_name", "")).is_equal("Corydoras aeneus")


func test_ac01_variants_are_opaque_and_distinct_within_a_species() -> void:
	if not _have_catalog():
		return
	for id: StringName in Api.IDS:
		var variants: Array = Api.field(id, "colour_variants", [])
		assert_int(variants.size()).is_greater_equal(1)
		var seen: Dictionary = {}
		for index: int in variants.size():
			var colour: Color = variants[index]
			(
				assert_float(colour.a)
				. override_failure_message("%s variant %d: alpha is not 1.0" % [id, index])
				. is_equal(1.0)
			)
			var key: int = colour.to_rgba32()
			(
				assert_bool(seen.has(key))
				. override_failure_message("%s variant %d repeats an earlier colour" % [id, index])
				. is_false()
			)
			seen[key] = true


# --- AC 33 ---


func test_ac33_variant_counts_follow_the_issue_order_neon_2_angelfish_3_corydoras_2() -> void:
	if not _have_catalog():
		return
	for id: StringName in Api.IDS:
		var variants: Array = Api.field(id, "colour_variants", [])
		(
			assert_int(variants.size())
			. override_failure_message(
				"%s has %d variants, expected %d" % [id, variants.size(), VARIANT_COUNTS[id]]
			)
			. is_equal(VARIANT_COUNTS[id])
		)


# --- AC 2 ---


func test_ac02_every_mode_2_field_is_filled_and_in_range() -> void:
	if not _have_catalog():
		return
	for id: StringName in Api.IDS:
		var species: Resource = _species_or_fail(id)
		if species == null:
			continue
		(
			assert_str("\n".join(_mode2_failures(species)))
			. override_failure_message("%s breaks a Mode 2 rule" % id)
			. is_empty()
		)


func test_ac02_mode_2_values_are_the_domain_ba_data() -> void:
	if not _have_catalog():
		return
	for id: StringName in Api.IDS:
		var species: Resource = _species_or_fail(id)
		if species == null:
			continue
		var values: Array = MODE_2[id]
		assert_float(species.get("temp_min_c")).is_equal_approx(values[0], 1e-6)
		assert_float(species.get("temp_max_c")).is_equal_approx(values[1], 1e-6)
		assert_float(species.get("ph_min")).is_equal_approx(values[2], 1e-6)
		assert_float(species.get("ph_max")).is_equal_approx(values[3], 1e-6)
		assert_int(species.get("min_group_size")).is_equal(values[4])
		assert_int(species.get("min_tank_litres")).is_equal(values[5])
		assert_float(species.get("bioload")).is_equal_approx(values[6], 1e-6)
		assert_int(species.get("temperament")).is_equal(values[7])
		assert_int(species.get("light_preference")).is_equal(values[8])
		assert_bool(species.get("needs_hiding_places")).is_equal(values[9])
		assert_array(Array(species.get("incompatible_with"))).is_equal(values[10])
		assert_array(Array(species.get("diet"))).is_equal(DIETS[id])


func test_ac02_bioload_keeps_the_order_neon_below_corydoras_below_angelfish() -> void:
	if not _have_catalog():
		return
	var neon: float = Api.field(&"neon_tetra", "bioload", -1.0)
	var cory: float = Api.field(&"bronze_corydoras", "bioload", -1.0)
	var angel: float = Api.field(&"angelfish", "bioload", -1.0)
	assert_bool(neon > 0.0 and neon < cory and cory < angel).is_true()


func test_ac02_no_field_is_dropped_or_renamed() -> void:
	var species: Resource = Api.new_species()
	assert_object(species).override_failure_message("FishSpecies is missing").is_not_null()
	if species == null:
		return
	var names: PackedStringArray = PackedStringArray()
	for entry: Dictionary in species.get_property_list():
		names.append(str(entry["name"]))
	for field: String in MODE_2_FIELDS + MODE_1_FIELDS:
		(
			assert_bool(names.has(field))
			. override_failure_message("FishSpecies has no field %s" % field)
			. is_true()
		)


func test_ac02_enums_start_with_unset_zero_and_fields_default_to_empty() -> void:
	var script: GDScript = Api.script_of(Api.SPECIES_PATH)
	assert_object(script).override_failure_message("FishSpecies is missing").is_not_null()
	if script == null:
		return
	var constants: Dictionary = script.get_script_constant_map()
	for enum_name: String in ["Zone", "Temperament", "Light"]:
		var present: bool = constants.has(enum_name)
		assert_bool(present).override_failure_message("enum %s is missing" % enum_name).is_true()
		if present:
			assert_int((constants[enum_name] as Dictionary).get("UNSET", -1)).is_equal(0)
	if constants.has("Zone"):
		assert_dict(constants["Zone"]).is_equal({"UNSET": 0, "TOP": 1, "MIDDLE": 2, "BOTTOM": 3})
	var empty: Resource = Api.new_species()
	assert_int(empty.get("preferred_zone")).is_equal(0)
	assert_int(empty.get("temperament")).is_equal(0)
	assert_int(empty.get("light_preference")).is_equal(0)
	assert_float(empty.get("adult_length_cm")).is_equal(0.0)
	assert_str(empty.get("scientific_name")).is_empty()


func test_ac02_edge_a_species_with_an_unset_enum_or_inverted_temperature_fails() -> void:
	var species: Resource = Api.new_species()
	assert_object(species).override_failure_message("FishSpecies is missing").is_not_null()
	if species == null:
		return
	species.set("temp_min_c", 20.0)
	species.set("temp_max_c", 26.0)
	species.set("ph_min", 6.0)
	species.set("ph_max", 7.0)
	species.set("min_group_size", 1)
	species.set("min_tank_litres", 10)
	species.set("bioload", 1.0)
	species.set("diet", [&"flakes"])
	species.set("temperament", PEACEFUL)
	species.set("light_preference", LIGHT_LOW)
	assert_int(_mode2_failures(species).size()).is_equal(0)
	species.set("temperament", 0)
	assert_int(_mode2_failures(species).size()).is_equal(1)
	species.set("temperament", PEACEFUL)
	species.set("temp_min_c", 30.0)
	assert_int(_mode2_failures(species).size()).is_equal(1)


# --- catalog API ---


func test_catalog_api_get_definition_and_get_ids_work_on_a_copy_of_the_ids() -> void:
	if not _have_catalog():
		return
	var catalog: RefCounted = Api.shipped()
	assert_object(catalog.call("get_definition", &"no_such_fish")).is_null()
	var ids: Array = catalog.call("get_ids")
	ids.clear()
	assert_int((catalog.call("get_ids") as Array).size()).is_equal(3)


func test_catalog_api_from_definitions_skips_a_duplicate_id_and_reports_it() -> void:
	if not _have_catalog():
		return
	var neon: Resource = Api.species(&"neon_tetra")
	var angel: Resource = Api.species(&"angelfish")
	var copy: Resource = Api.variant_of(&"neon_tetra", {})
	var catalog: RefCounted = Api.catalog_from([neon, angel, copy])
	assert_object(catalog).is_not_null()
	if catalog == null:
		return
	assert_int((catalog.call("get_ids") as Array).size()).is_equal(2)
	assert_int((catalog.call("get_skipped") as Array).size()).is_equal(1)
