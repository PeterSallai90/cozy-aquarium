extends GdUnitTestSuite
## #126 criteria 3 and 5 (owner: developer for WaterCausticSettings and its .tres, technical-artist
## for the shader instance-uniform defaults that mirror them): the one named place for the three
## caustic values, their ranges, the single apply step and the absence of an on/off switch.
## ADR 0007 Amendment 1 rule 9 and the technical plan of #126, section 3.

const Api := preload("res://tests/helpers/late_api.gd")
const Water := preload("res://tests/helpers/water_rig.gd")
const SourceScan := preload("res://tests/helpers/source_scan.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")

const TOLERANCE := 0.0001
const ROLLOVER_STEP := 1.0 / 3600.0
const SHADER_DEFAULTS: Dictionary = {
	"caustic_intensity": 0.4,
	"caustic_speed": 0.25,
	"caustic_scale": 25.0,
}


func _number(settings: Resource, field: String) -> float:
	return Api.prop(settings, field, Api.MISSING_NUMBER)


func _constant(wanted: String) -> float:
	return Api.constant(Water.CAUSTIC_SETTINGS_SCRIPT, wanted, Api.MISSING_NUMBER)


func _apply(settings: Resource) -> Dictionary:
	return await EngineOutput.capture_all(func() -> void: Api.call_on(settings, "apply", [], null))


func _script_properties() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not ResourceLoader.exists(Water.CAUSTIC_SETTINGS_SCRIPT):
		return result
	var script: GDScript = load(Water.CAUSTIC_SETTINGS_SCRIPT) as GDScript
	for entry: Dictionary in script.get_script_property_list():
		if int(entry["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE != 0:
			result.append(entry)
	return result


# --- AC 3: the three values, defaults and ranges ---


func test_ac03_the_settings_class_and_its_default_resource_exist() -> void:
	(
		assert_bool(ResourceLoader.exists(Water.CAUSTIC_SETTINGS_SCRIPT))
		. override_failure_message("water_caustic_settings.gd missing")
		. is_true()
	)
	(
		assert_bool(ResourceLoader.exists(Water.CAUSTIC_SETTINGS_PATH))
		. override_failure_message("water_caustic_settings.tres missing")
		. is_true()
	)


func test_ac03_the_three_values_exist_by_exact_name_with_the_start_values() -> void:
	var settings: Resource = Water.caustic_settings()
	assert_float(_number(settings, "caustic_intensity")).is_equal_approx(0.4, TOLERANCE)
	assert_float(_number(settings, "caustic_speed")).is_equal_approx(0.25, TOLERANCE)
	assert_float(_number(settings, "caustic_scale")).is_equal_approx(25.0, TOLERANCE)


func test_ac03_the_range_constants_are_the_issue_ranges() -> void:
	assert_float(_constant("CAUSTIC_INTENSITY_MIN")).is_equal(0.0)
	assert_float(_constant("CAUSTIC_INTENSITY_MAX")).is_equal(2.0)
	assert_float(_constant("CAUSTIC_SPEED_MIN")).is_equal(0.05)
	assert_float(_constant("CAUSTIC_SPEED_MAX")).is_equal(0.5)
	assert_float(_constant("CAUSTIC_SCALE_MIN")).is_equal(10.0)
	assert_float(_constant("CAUSTIC_SCALE_MAX")).is_equal(60.0)


func test_ac03_each_default_lies_inside_its_range() -> void:
	var settings: Resource = Water.caustic_settings()
	for field: String in ["intensity", "speed", "scale"]:
		var value: float = _number(settings, "caustic_" + field)
		var low: float = _constant("CAUSTIC_%s_MIN" % field.to_upper())
		var high: float = _constant("CAUSTIC_%s_MAX" % field.to_upper())
		assert_float(low).override_failure_message(field + " range missing").is_not_equal(
			Api.MISSING_NUMBER
		)
		assert_float(value).override_failure_message(field).is_between(low, high)


func test_ac03_the_speed_default_gives_a_cycle_of_three_to_six_seconds() -> void:
	var speed: float = _number(Water.caustic_settings(), "caustic_speed")
	assert_float(1.0 / speed if speed > 0.0 else 0.0).is_between(3.0, 6.0)


func test_ac03_the_scale_default_gives_cells_of_two_to_six_centimetres() -> void:
	var scale_value: float = _number(Water.caustic_settings(), "caustic_scale")
	assert_float(100.0 / scale_value if scale_value > 0.0 else 0.0).is_between(2.0, 6.0)


func test_ac03_the_default_tres_stores_the_same_values_as_the_script() -> void:
	var text: String = SourceScan.read(Water.CAUSTIC_SETTINGS_PATH)
	assert_str(text).override_failure_message("water_caustic_settings.tres missing").is_not_empty()
	var fresh: Resource = null
	if ResourceLoader.exists(Water.CAUSTIC_SETTINGS_SCRIPT):
		fresh = (load(Water.CAUSTIC_SETTINGS_SCRIPT) as GDScript).new() as Resource
	for field: String in SHADER_DEFAULTS:
		(
			assert_float(_number(Water.caustic_settings(), field))
			. override_failure_message("tres " + field)
			. is_equal_approx(_number(fresh, field), TOLERANCE)
		)


func test_ac03_the_shader_instance_uniform_defaults_mirror_the_resource() -> void:
	var text: String = SourceScan.strip_comments(SourceScan.read(Water.CAUSTICS_SHADER))
	assert_str(text).override_failure_message("caustics.gdshader missing").is_not_empty()
	var settings: Resource = Water.caustic_settings()
	for field: String in SHADER_DEFAULTS:
		var pattern: RegEx = RegEx.create_from_string(
			"instance\\s+uniform\\s+float\\s+%s\\s*=\\s*(-?[0-9.]+)" % field
		)
		var found: RegExMatch = pattern.search(text)
		(
			assert_object(found)
			. override_failure_message("no float instance uniform default for " + field)
			. is_not_null()
		)
		if found != null:
			(
				assert_float(found.get_string(1).to_float())
				. override_failure_message("shader default of " + field)
				. is_equal_approx(_number(settings, field), TOLERANCE)
			)


# --- AC 3: the single apply step ---


func test_ac03_apply_emits_applied_exactly_once() -> void:
	var settings: Resource = Water.caustic_settings()
	var count: Array[int] = [0]
	if settings.has_signal("applied"):
		settings.connect("applied", func() -> void: count[0] += 1)
	else:
		fail("WaterCausticSettings has no applied signal")
	var seen: Dictionary = await _apply(settings)
	assert_int(count[0]).is_equal(1)
	assert_int(Water.count_of(seen["warnings"])).is_equal(0)
	assert_int(Water.count_of(seen["errors"])).is_equal(0)


func test_ac03_apply_with_bad_values_emits_once_and_warns_once() -> void:
	var settings: Resource = Water.caustic_settings()
	settings.set("caustic_intensity", 9.0)
	settings.set("caustic_speed", 0.01)
	settings.set("caustic_scale", 100.0)
	var count: Array[int] = [0]
	if settings.has_signal("applied"):
		settings.connect("applied", func() -> void: count[0] += 1)
	var seen: Dictionary = await _apply(settings)
	assert_int(count[0]).is_equal(1)
	assert_int(Water.count_of(seen["warnings"])).override_failure_message(str(seen)).is_equal(1)
	assert_float(_number(settings, "caustic_intensity")).is_equal(2.0)
	assert_float(_number(settings, "caustic_speed")).is_equal(0.05)
	assert_float(_number(settings, "caustic_scale")).is_equal(60.0)
	var text: String = String(seen["warnings"].keys()[0]) if not seen["warnings"].is_empty() else ""
	for field: String in SHADER_DEFAULTS:
		assert_str(text).override_failure_message("warning names " + field).contains(field)


func test_ac03_a_non_finite_value_goes_to_its_default() -> void:
	var settings: Resource = Water.caustic_settings()
	settings.set("caustic_intensity", NAN)
	settings.set("caustic_speed", INF)
	settings.set("caustic_scale", -INF)
	var seen: Dictionary = await _apply(settings)
	assert_float(_number(settings, "caustic_intensity")).is_equal_approx(0.4, TOLERANCE)
	assert_float(_number(settings, "caustic_speed")).is_equal_approx(0.25, TOLERANCE)
	assert_float(_number(settings, "caustic_scale")).is_equal_approx(25.0, TOLERANCE)
	assert_int(Water.count_of(seen["warnings"])).is_equal(1)
	assert_int(Water.count_of(seen["errors"])).is_equal(0)


func test_ac03_the_speed_is_rounded_to_a_whole_number_of_cycles_per_time_rollover() -> void:
	# Godot wraps TIME at 3600 s; a whole number of cycles per wrap keeps the loop seamless.
	for written: float in [0.123, 0.1999, 0.2501, 0.33, 0.07]:
		var settings: Resource = Water.caustic_settings()
		settings.set("caustic_speed", written)
		await _apply(settings)
		var speed: float = _number(settings, "caustic_speed")
		var cycles: float = speed * 3600.0
		(
			assert_float(absf(cycles - roundf(cycles)))
			. override_failure_message(
				"%s became %s: %s cycles per 3600 s" % [written, speed, cycles]
			)
			. is_less(0.001)
		)
		(
			assert_float(absf(speed - written))
			. override_failure_message("%s moved too far to %s" % [written, speed])
			. is_less_equal(ROLLOVER_STEP / 2.0 + 0.00001)
		)


func test_ac03_the_exact_range_ends_and_the_default_are_kept() -> void:
	for written: float in [0.05, 0.25, 0.5]:
		var settings: Resource = Water.caustic_settings()
		settings.set("caustic_speed", written)
		var seen: Dictionary = await _apply(settings)
		assert_float(_number(settings, "caustic_speed")).is_equal_approx(written, 0.000001)
		assert_int(Water.count_of(seen["warnings"])).is_equal(0)


func test_ac03_the_ends_of_the_intensity_and_scale_ranges_are_valid_and_silent() -> void:
	for pair: Array in [
		["caustic_intensity", 0.0],
		["caustic_intensity", 2.0],
		["caustic_scale", 10.0],
		["caustic_scale", 60.0],
	]:
		var settings: Resource = Water.caustic_settings()
		settings.set(pair[0], pair[1])
		var seen: Dictionary = await _apply(settings)
		assert_float(_number(settings, pair[0])).is_equal_approx(float(pair[1]), TOLERANCE)
		(
			assert_int(Water.count_of(seen["warnings"]))
			. override_failure_message("%s = %s" % pair)
			. is_equal(0)
		)


# --- AC 5: no on/off switch ---


func test_ac05_the_settings_resource_has_no_bool_property_and_no_enabled_name() -> void:
	var properties: Array[Dictionary] = _script_properties()
	(
		assert_int(properties.size())
		. override_failure_message("WaterCausticSettings has no script variables (class missing)")
		. is_greater(0)
	)
	for entry: Dictionary in properties:
		var label: String = String(entry["name"])
		(
			assert_int(int(entry["type"]))
			. override_failure_message(label + " is a bool: no on/off switch")
			. is_not_equal(TYPE_BOOL)
		)
		assert_bool(label.contains("enabled")).override_failure_message(label).is_false()


func test_ac05_the_settings_resource_holds_exactly_the_three_values() -> void:
	var names: Array[String] = []
	for entry: Dictionary in _script_properties():
		names.append(String(entry["name"]))
	names.sort()
	assert_array(names).is_equal(["caustic_intensity", "caustic_scale", "caustic_speed"])
