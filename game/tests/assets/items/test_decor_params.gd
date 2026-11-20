extends GdUnitTestSuite
## #157 criteria 5 and 22 (owner: technical-artist): drift guard in CI for tools/blender/params/
## decor.json (pattern of test_tank_params_match_catalog.gd). The Python generator tests need no
## Blender but do not run in CI, so the parameters that carry the sizes and the hollow amphora
## are guarded here as well.
##
## Group that makes this file pass: technical-artist (stage 1, decor.json).
##
## Test decisions where the plan is silent (the key names are a contract for decor.json):
## - Size keys are plain numbers in cm, named <item>_<axis>_cm: stone_width_cm, stone_height_cm,
##   stone_depth_cm, branch_width_cm, branch_height_cm, branch_depth_cm, amphora_width_cm,
##   amphora_height_cm and amphora_depth_cm (width x, height y, depth z), with the values of the
##   footprint table of the issue (written here as constants, not read from the catalog).
## - AC 22 keys as in plan section 2.3: amphora_opening_cm >= 3.5, amphora_inside_depth_cm >= 8.0
##   and amphora_wall_cm from 0.5 to 0.7.
## - The cavity fits: inside depth plus wall is at most the amphora height, and the opening plus
##   two walls is less than the amphora depth (z, the body diameter).

const PARAMS_FILE := "decor.json"
const EXACT := 1e-9
const SIZES_CM: Dictionary[String, float] = {
	"stone_width_cm": 11.0,
	"stone_height_cm": 6.0,
	"stone_depth_cm": 8.0,
	"branch_width_cm": 28.0,
	"branch_height_cm": 8.0,
	"branch_depth_cm": 7.0,
	"amphora_width_cm": 9.0,
	"amphora_height_cm": 14.0,
	"amphora_depth_cm": 8.0,
}
const OPENING_MIN_CM := 3.5
const INSIDE_DEPTH_MIN_CM := 8.0
const WALL_MIN_CM := 0.5
const WALL_MAX_CM := 0.7


func _path() -> String:
	return ProjectSettings.globalize_path("res://").path_join("../tools/blender/params").path_join(
		PARAMS_FILE
	)


func _read() -> Dictionary:
	var text: String = FileAccess.get_file_as_string(_path())
	var parsed: Variant = JSON.parse_string(text)
	(
		assert_bool(parsed is Dictionary)
		. override_failure_message("%s is missing or not a JSON object" % PARAMS_FILE)
		. is_true()
	)
	return parsed if parsed is Dictionary else {}


func _number(data: Dictionary, key: String) -> float:
	var present: bool = data.has(key) and (data[key] is float or data[key] is int)
	(
		assert_bool(present)
		. override_failure_message("%s: key %s is not a number" % [PARAMS_FILE, key])
		. is_true()
	)
	return float(data[key]) if present else NAN


func test_ac05_the_size_keys_equal_the_footprint_table_of_the_issue() -> void:
	var data: Dictionary = _read()
	for key: String in SIZES_CM:
		var value: float = _number(data, key)
		if is_nan(value):
			continue
		assert_float(value).override_failure_message(key).is_equal_approx(SIZES_CM[key], EXACT)


func test_ac22_the_amphora_opening_is_at_least_3_5_cm() -> void:
	var value: float = _number(_read(), "amphora_opening_cm")
	if is_nan(value):
		return
	assert_float(value).is_greater_equal(OPENING_MIN_CM)


func test_ac22_the_amphora_inside_depth_is_at_least_8_cm() -> void:
	var value: float = _number(_read(), "amphora_inside_depth_cm")
	if is_nan(value):
		return
	assert_float(value).is_greater_equal(INSIDE_DEPTH_MIN_CM)


func test_ac22_the_amphora_wall_is_0_5_to_0_7_cm() -> void:
	var value: float = _number(_read(), "amphora_wall_cm")
	if is_nan(value):
		return
	assert_float(value).is_between(WALL_MIN_CM, WALL_MAX_CM)


func test_ac22_the_hollow_fits_inside_the_amphora_body() -> void:
	var data: Dictionary = _read()
	var height: float = _number(data, "amphora_height_cm")
	var depth: float = _number(data, "amphora_inside_depth_cm")
	var wall: float = _number(data, "amphora_wall_cm")
	var opening: float = _number(data, "amphora_opening_cm")
	var width: float = _number(data, "amphora_depth_cm")
	if is_nan(height) or is_nan(depth) or is_nan(wall) or is_nan(opening) or is_nan(width):
		return
	assert_float(depth + wall).is_less_equal(height)
	assert_float(opening + 2.0 * wall).is_less(width)
