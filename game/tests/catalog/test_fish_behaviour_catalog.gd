extends GdUnitTestSuite
## #35 catalog part (owner: developer): FishSpecies.group_style (append-only enum, BA decisions Q1
## and Q2), the schooling consistency rule, the new Mode 1 behaviour fields on FishSpecies (Q3) and
## that no Mode 2 field is dropped (Q19). UNSET is rejected for every shipped species. The species
## values are the plan table, inside the bounds of the domain BA table. FishSpecies is reached by
## path (FishApi), so the suite fails with a readable message while the class is missing.
## Test decisions: the schooling rule is also run over a synthetic table covering all five enum
## values, on copies of a shipped species; a forgotten (0) value is caught by the rule below.

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
const STYLE_UNSET := 0
const STYLE_SOLITARY := 1
const STYLE_TIGHT := 2
const STYLE_LOOSE := 3
const STYLE_FORAGING := 4
## Species id to the group_style value of the BA decision.
const GROUP_STYLE: Dictionary[StringName, int] = {
	&"neon_tetra": STYLE_TIGHT,
	&"angelfish": STYLE_LOOSE,
	&"bronze_corydoras": STYLE_FORAGING,
}
## The rule of the BA decision Q2 as a table over all five enum values (synthetic).
const SCHOOLING_OF_STYLE: Dictionary[int, bool] = {
	STYLE_UNSET: false,
	STYLE_SOLITARY: false,
	STYLE_TIGHT: true,
	STYLE_LOOSE: false,
	STYLE_FORAGING: true,
}
const BEHAVIOUR_FIELDS: PackedStringArray = [
	"group_style",
	"idle_share",
	"dart_interval_min_s",
	"dart_interval_max_s",
	"dart_duration_min_s",
	"dart_duration_max_s",
	"turn_rate_max_deg_s",
	"pitch_limit_deg",
	"nose_down_bias_deg",
]
## The fields that must be above 0 (nose_down_bias_deg may be 0), in the order of BEHAVIOUR rows.
const BEHAVIOUR_VALUE_FIELDS: PackedStringArray = [
	"idle_share",
	"dart_interval_min_s",
	"dart_interval_max_s",
	"dart_duration_min_s",
	"dart_duration_max_s",
	"turn_rate_max_deg_s",
	"pitch_limit_deg",
]
## Species id to [idle_share, dart_interval_min_s, dart_interval_max_s, dart_duration_min_s,
## dart_duration_max_s, turn_rate_max_deg_s, pitch_limit_deg, nose_down_bias_deg] (plan table).
const BEHAVIOUR: Dictionary[StringName, Array] = {
	&"neon_tetra": [0.20, 20.0, 40.0, 0.5, 1.0, 180.0, 25.0, 0.0],
	&"bronze_corydoras": [0.40, 25.0, 50.0, 0.5, 1.0, 140.0, 30.0, 10.0],
	&"angelfish": [0.30, 40.0, 60.0, 0.8, 1.5, 90.0, 20.0, 0.0],
}
## Species id to the allowed [lowest, highest] mean idle share of the domain BA table.
const IDLE_BOUNDS: Dictionary[StringName, Array] = {
	&"neon_tetra": [0.15, 0.25],
	&"bronze_corydoras": [0.35, 0.45],
	&"angelfish": [0.25, 0.35],
}


func _have_catalog() -> bool:
	var is_ready: bool = (
		Api.script_of(Api.CATALOG_PATH) != null and Api.script_of(Api.SPECIES_PATH) != null
	)
	(
		assert_bool(is_ready)
		. override_failure_message("FishSpecies and FishCatalog scripts are missing")
		. is_true()
	)
	return is_ready and Api.shipped() != null


func _species_or_fail(id: StringName) -> Resource:
	var species: Resource = Api.species(id)
	assert_object(species).override_failure_message("no species %s" % id).is_not_null()
	return species


## A numeric field of a definition, -1 while the field does not exist (never a script error).
func _number(definition: Resource, field: String) -> float:
	var value: Variant = definition.get(field)
	return -1.0 if value == null else float(value)


## Failures of the #35 behaviour rules for one definition (empty when it passes): UNSET group_style,
## a schooling flag that disagrees with the style, a forgotten (0) value or an inverted range.
func _behaviour_failures(definition: Resource) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	var style: int = int(_number(definition, "group_style"))
	if style <= STYLE_UNSET:
		failures.append("group_style is UNSET")
	if bool(definition.get("schooling")) != SCHOOLING_OF_STYLE.get(style, false):
		failures.append("schooling does not match group_style")
	for field: String in BEHAVIOUR_VALUE_FIELDS:
		if _number(definition, field) <= 0.0:
			failures.append("%s is not above 0" % field)
	if _number(definition, "dart_interval_min_s") > _number(definition, "dart_interval_max_s"):
		failures.append("dart interval is inverted")
	if _number(definition, "dart_duration_min_s") > _number(definition, "dart_duration_max_s"):
		failures.append("dart duration is inverted")
	if _number(definition, "idle_share") >= 1.0:
		failures.append("idle_share is not below 1")
	var bias: float = _number(definition, "nose_down_bias_deg")
	if bias < 0.0 or bias >= _number(definition, "pitch_limit_deg"):
		failures.append("nose_down_bias_deg is outside 0 to the pitch limit")
	return failures


func test_35_group_style_is_an_append_only_enum_with_unset_zero() -> void:
	var script: GDScript = Api.script_of(Api.SPECIES_PATH)
	assert_object(script).override_failure_message("FishSpecies is missing").is_not_null()
	if script == null:
		return
	var constants: Dictionary = script.get_script_constant_map()
	(
		assert_bool(constants.has("GroupStyle"))
		. override_failure_message("no enum GroupStyle")
		. is_true()
	)
	if constants.has("GroupStyle"):
		(
			assert_dict(constants["GroupStyle"])
			. is_equal(
				{
					"UNSET": 0,
					"SOLITARY": 1,
					"TIGHT_SCHOOL": 2,
					"LOOSE_GROUP": 3,
					"FORAGING_GROUP": 4,
				}
			)
		)


func test_35_a_new_species_has_every_behaviour_field_empty() -> void:
	var empty: Resource = Api.new_species()
	assert_object(empty).override_failure_message("FishSpecies is missing").is_not_null()
	if empty == null:
		return
	var names: PackedStringArray = PackedStringArray()
	for entry: Dictionary in empty.get_property_list():
		names.append(str(entry["name"]))
	for field: String in BEHAVIOUR_FIELDS:
		(
			assert_bool(names.has(field))
			. override_failure_message("FishSpecies has no field %s" % field)
			. is_true()
		)
	assert_int(int(_number(empty, "group_style"))).is_equal(STYLE_UNSET)
	for field: String in BEHAVIOUR_FIELDS:
		if field != "group_style":
			assert_float(_number(empty, field)).override_failure_message(field).is_equal(0.0)


func test_35_the_three_species_have_the_group_style_of_the_ba_decision() -> void:
	if not _have_catalog():
		return
	for id: StringName in Api.IDS:
		(
			assert_int(int(Api.field(id, "group_style", -1)))
			. override_failure_message("group_style of %s" % id)
			. is_equal(GROUP_STYLE[id])
		)


func test_35_unset_is_rejected_for_every_shipped_species() -> void:
	if not _have_catalog():
		return
	for id: String in Api.shipped().call("get_ids"):
		(
			assert_int(int(Api.field(StringName(id), "group_style", 0)))
			. override_failure_message("%s has no group_style" % id)
			. is_not_equal(STYLE_UNSET)
		)
	var forgotten: Resource = Api.variant_of(&"neon_tetra", {"group_style": STYLE_UNSET})
	if forgotten != null:
		assert_bool(_behaviour_failures(forgotten).has("group_style is UNSET")).is_true()


func test_35_schooling_is_true_exactly_for_tight_school_and_foraging_group() -> void:
	if not _have_catalog():
		return
	for id: StringName in Api.IDS:
		var style: int = int(Api.field(id, "group_style", -1))
		(
			assert_bool(bool(Api.field(id, "schooling", null)))
			. override_failure_message("schooling of %s with style %d" % [id, style])
			. is_equal(style == STYLE_TIGHT or style == STYLE_FORAGING)
		)


func test_35_the_schooling_rule_holds_over_a_synthetic_table_of_all_five_values() -> void:
	var script: GDScript = Api.script_of(Api.SPECIES_PATH)
	if script == null:
		assert_bool(false).override_failure_message("FishSpecies is missing").is_true()
		return
	var styles: Dictionary = script.get_script_constant_map().get("GroupStyle", {})
	assert_array(styles.values()).contains_exactly_in_any_order([0, 1, 2, 3, 4])
	for style: int in SCHOOLING_OF_STYLE:
		var consistent: Resource = Api.variant_of(
			&"neon_tetra", {"group_style": style, "schooling": SCHOOLING_OF_STYLE[style]}
		)
		var broken: Resource = Api.variant_of(
			&"neon_tetra", {"group_style": style, "schooling": not SCHOOLING_OF_STYLE[style]}
		)
		if consistent == null or broken == null:
			assert_bool(false).override_failure_message("no neon_tetra to copy").is_true()
			return
		(
			assert_bool(_behaviour_failures(consistent).has("schooling does not match group_style"))
			. override_failure_message("style %d with the right flag is flagged" % style)
			. is_false()
		)
		(
			assert_bool(_behaviour_failures(broken).has("schooling does not match group_style"))
			. override_failure_message("style %d with the wrong flag is not flagged" % style)
			. is_true()
		)


func test_35_the_behaviour_fields_of_the_three_species_follow_the_plan_table() -> void:
	if not _have_catalog():
		return
	for id: StringName in Api.IDS:
		var row: Array = BEHAVIOUR[id]
		for index: int in row.size():
			var field: String = BEHAVIOUR_VALUE_FIELDS[index] if index < 7 else "nose_down_bias_deg"
			(
				assert_float(float(Api.field(id, field, -1.0)))
				. override_failure_message("%s of %s" % [field, id])
				. is_equal_approx(float(row[index]), 1e-6)
			)


func test_35_every_behaviour_value_is_set_and_inside_the_domain_ba_bounds() -> void:
	if not _have_catalog():
		return
	for id: StringName in Api.IDS:
		var species: Resource = _species_or_fail(id)
		if species == null:
			continue
		(
			assert_array(Array(_behaviour_failures(species)))
			. override_failure_message("%s breaks a behaviour rule" % id)
			. is_empty()
		)
		var share: float = _number(species, "idle_share")
		assert_float(share).is_between(IDLE_BOUNDS[id][0], IDLE_BOUNDS[id][1])
		assert_float(_number(species, "dart_interval_min_s")).is_greater_equal(20.0)
		assert_float(_number(species, "dart_interval_max_s")).is_between(20.0, 60.0)
		assert_float(_number(species, "dart_duration_min_s")).is_greater_equal(0.5)
		assert_float(_number(species, "dart_duration_max_s")).is_between(0.5, 1.5)


func test_35_a_forgotten_behaviour_value_fails_the_catalog_rule() -> void:
	if not _have_catalog():
		return
	for field: String in BEHAVIOUR_VALUE_FIELDS:
		var copy: Resource = Api.variant_of(&"neon_tetra", {field: 0.0})
		if copy == null:
			assert_bool(false).override_failure_message("no neon_tetra to copy").is_true()
			return
		(
			assert_bool(_behaviour_failures(copy).is_empty())
			. override_failure_message("a missing %s is not caught" % field)
			. is_false()
		)


func test_35_nose_down_bias_zero_is_legal_and_stays_below_the_pitch_limit() -> void:
	if not _have_catalog():
		return
	for id: StringName in Api.IDS:
		var bias: float = float(Api.field(id, "nose_down_bias_deg", -1.0))
		var limit: float = float(Api.field(id, "pitch_limit_deg", 0.0))
		assert_bool(bias >= 0.0 and bias < limit).override_failure_message(str(id)).is_true()
	var legal: Resource = Api.variant_of(&"neon_tetra", {"nose_down_bias_deg": 0.0})
	if legal != null:
		assert_bool(_behaviour_failures(legal).is_empty()).is_true()


func test_35_no_mode_2_field_is_dropped_or_renamed_and_schooling_stays() -> void:
	var species: Resource = Api.new_species()
	assert_object(species).override_failure_message("FishSpecies is missing").is_not_null()
	if species == null:
		return
	var names: PackedStringArray = PackedStringArray()
	for entry: Dictionary in species.get_property_list():
		names.append(str(entry["name"]))
	for field: String in MODE_2_FIELDS + MODE_1_FIELDS:
		assert_bool(names.has(field)).override_failure_message(field).is_true()
	assert_bool(names.has("schooling")).is_true()
	assert_bool(names.has("swim_speed")).is_true()
