extends GdUnitTestSuite
## #35 global tuning resource (owner: developer): FishSwimTuning (game/catalog/fish_swim_tuning.gd)
## with game/catalog/behaviour/fish_swim_tuning.tres is the one place of the global tuning values
## (BA decisions Q3 and Q19, ADR 0015 rule 3), an input of the steering model. The file lives
## outside game/catalog/fish because FishCatalog.load_dir reads every .tres there. The steering code
## in game/systems/fish holds no species or tuning literal and no Node reference.
## Test decisions: the starting values of the plan are pinned only where a BA decision or a test cap
## fixes them (k = 3, ramps at least as long as the test caps, the stuck rule numbers, the recovery
## numbers, the substep and the hitch limit); the other numbers are owner tuning and are only
## checked for being set. The classes are reached late-bound (fish_swim_api.gd).

const Api := preload("res://tests/helpers/fish_swim_api.gd")
const FishApi := preload("res://tests/helpers/fish_api.gd")
const SourceScan := preload("res://tests/helpers/source_scan.gd")

## Every field of FishSwimTuning of the plan, each of which must be set (above 0).
const POSITIVE_FIELDS: PackedStringArray = [
	"top_speed_factor_k",
	"cruise_speed_fraction",
	"dart_speed_fraction",
	"min_dart_gap_s",
	"accel_ramp_s",
	"yaw_ramp_s",
	"yaw_deadband_fraction",
	"idle_episode_min_s",
	"idle_episode_max_s",
	"idle_drift_fraction",
	"catch_up_distance_bl",
	"separation_factor",
	"band_inset_m",
	"band_margin_m",
	"wall_margin_m",
	"recovery_speed_factor",
	"recovery_ramp_s",
	"recovery_max_s",
	"stuck_speed_fraction",
	"stuck_time_s",
	"detour_s",
	"pinned_drift_m",
	"max_substep_s",
	"max_delta_s",
]


func _tuning() -> Resource:
	var found: Resource = Api.tuning()
	(
		assert_object(found)
		. override_failure_message("FishSwimTuning or fish_swim_tuning.tres is missing")
		. is_not_null()
	)
	return found


func _style(tuning: Resource, style: int) -> Resource:
	var list: Array = tuning.get("group_styles")
	assert_int(list.size()).override_failure_message("group_styles size").is_equal(5)
	if style >= list.size():
		return null
	return list[style] as Resource


func test_35_the_tuning_resource_exists_at_its_catalog_path_with_a_load_default() -> void:
	assert_bool(ResourceLoader.exists(Api.TUNING_RES)).is_true()
	assert_bool(Api.declares(Api.TUNING_PATH, "load_default")).is_true()
	var loaded: Resource = _tuning()
	if loaded != null:
		assert_str(loaded.get_script().resource_path).is_equal(Api.TUNING_PATH)


func test_35_every_tuning_value_is_a_field_and_is_set() -> void:
	var tuning: Resource = _tuning()
	if tuning == null:
		return
	var names: PackedStringArray = PackedStringArray()
	for entry: Dictionary in tuning.get_property_list():
		names.append(str(entry["name"]))
	for field: String in POSITIVE_FIELDS:
		assert_bool(names.has(field)).override_failure_message("no field %s" % field).is_true()
		assert_float(float(tuning.get(field))).override_failure_message(field).is_greater(0.0)
	assert_bool(names.has("group_styles")).is_true()


func test_35_the_top_speed_factor_is_3_and_the_recovery_factor_is_6() -> void:
	var tuning: Resource = _tuning()
	if tuning == null:
		return
	assert_float(float(tuning.get("top_speed_factor_k"))).is_equal(3.0)
	assert_float(float(tuning.get("recovery_speed_factor"))).is_equal(6.0)


func test_35_the_ramps_are_at_least_as_long_as_the_caps_the_tests_check() -> void:
	var tuning: Resource = _tuning()
	if tuning == null:
		return
	assert_float(float(tuning.get("accel_ramp_s"))).is_greater_equal(0.3)
	assert_float(float(tuning.get("yaw_ramp_s"))).is_greater_equal(0.25)
	assert_float(float(tuning.get("recovery_ramp_s"))).is_greater_equal(0.3)


func test_35_the_recovery_stuck_and_step_numbers_follow_the_ba_decisions() -> void:
	var tuning: Resource = _tuning()
	if tuning == null:
		return
	assert_float(float(tuning.get("recovery_max_s"))).is_less_equal(2.0)
	assert_float(float(tuning.get("stuck_speed_fraction"))).is_equal_approx(0.05, 1e-9)
	assert_float(float(tuning.get("stuck_time_s"))).is_equal_approx(5.0, 1e-9)
	assert_float(float(tuning.get("min_dart_gap_s"))).is_greater_equal(5.0)
	assert_float(float(tuning.get("max_substep_s"))).is_equal_approx(1.0 / 60.0, 1e-9)
	assert_float(float(tuning.get("max_delta_s"))).is_equal_approx(0.5, 1e-9)
	assert_float(float(tuning.get("band_margin_m"))).is_less_equal(0.01)


func test_35_there_is_one_group_style_entry_per_enum_value_and_unset_equals_solitary() -> void:
	var tuning: Resource = _tuning()
	if tuning == null:
		return
	var list: Array = tuning.get("group_styles")
	assert_int(list.size()).is_equal(5)
	if list.size() != 5:
		return
	for entry: Variant in list:
		assert_object(entry).is_not_null()
		assert_str((entry as Resource).get_script().resource_path).is_equal(Api.STYLE_PATH)
	for index: int in [Api.STYLE_UNSET, Api.STYLE_SOLITARY]:
		var style: Resource = list[index]
		assert_float(float(style.get("cohesion"))).override_failure_message("cohesion").is_equal(
			0.0
		)
		assert_float(float(style.get("alignment"))).override_failure_message("alignment").is_equal(
			0.0
		)
		assert_float(float(style.get("spacing_bl"))).override_failure_message("spacing").is_equal(
			0.0
		)


func test_35_the_school_styles_order_tight_above_foraging_above_loose_in_cohesion() -> void:
	var tuning: Resource = _tuning()
	if tuning == null:
		return
	var tight: Resource = _style(tuning, Api.STYLE_TIGHT_SCHOOL)
	var loose: Resource = _style(tuning, Api.STYLE_LOOSE_GROUP)
	var foraging: Resource = _style(tuning, Api.STYLE_FORAGING_GROUP)
	if tight == null or loose == null or foraging == null:
		return
	var cohesion_tight: float = float(tight.get("cohesion"))
	var cohesion_foraging: float = float(foraging.get("cohesion"))
	var cohesion_loose: float = float(loose.get("cohesion"))
	assert_bool(cohesion_tight > cohesion_foraging and cohesion_foraging > cohesion_loose).is_true()
	assert_bool(cohesion_loose > 0.0).is_true()
	assert_float(float(tight.get("spacing_bl"))).is_less(float(loose.get("spacing_bl")))
	for style: Resource in [tight, loose, foraging]:
		assert_float(float(style.get("view_radius_bl"))).is_greater(0.0)
		assert_float(float(style.get("alignment"))).is_greater(0.0)


func test_35_the_fish_catalog_still_loads_exactly_the_three_species() -> void:
	var catalog: RefCounted = FishApi.shipped()
	if catalog == null:
		assert_bool(false).override_failure_message("FishCatalog is missing").is_true()
		return
	assert_int((catalog.call("get_ids") as Array).size()).is_equal(3)
	assert_array(catalog.call("get_skipped") as Array).is_empty()
	assert_bool(ResourceLoader.exists("res://catalog/fish/fish_swim_tuning.tres")).is_false()


func test_35_the_steering_code_has_no_species_literal_and_no_node_reference() -> void:
	var paths: PackedStringArray = SourceScan.list_scripts(Api.SYSTEMS_DIR, PackedStringArray())
	(
		assert_bool(paths.is_empty())
		. override_failure_message("no script in game/systems/fish")
		. is_false()
	)
	var banned: Array[RegEx] = (
		SourceScan
		. compile(
			[
				"neon_tetra",
				"angelfish",
				"bronze_corydoras",
				"extends\\s+Node",
				"get_node\\s*\\(",
				"get_tree\\s*\\(",
				"\\bEventBus\\b",
				"\\bNode3D\\b",
				'\\$["A-Za-z_%/]',
			]
		)
	)
	for path: String in paths:
		var found: PackedStringArray = SourceScan.find_matches(
			SourceScan.strip_comments(SourceScan.read(path)), banned
		)
		(
			assert_array(Array(found))
			. override_failure_message("%s has a species literal or a Node reference" % path)
			. is_empty()
		)


func test_35_the_steering_classes_exist_and_are_ref_counted() -> void:
	for path: String in [
		Api.SIM_PATH, Api.PARAMS_PATH, Api.WORLD_PATH, Api.LIMITS_PATH, Api.STATE_PATH
	]:
		var script: GDScript = Api.script_of(path)
		assert_object(script).override_failure_message("%s is missing" % path).is_not_null()
		if script != null:
			assert_str(String(script.get_instance_base_type())).is_equal("RefCounted")
