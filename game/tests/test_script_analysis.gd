extends GdUnitTestSuite
## Load-every-script census and its failure cases (#92, ADR 0004).
##
## The helpers are loaded by path, so a missing script fails these tests and not the whole run.
## The broken scripts are written under user://, never under res://, and removed after each test.

const ANALYSIS_PATH := "res://tests/helpers/script_analysis.gd"
const OUTPUT_PATH := "res://tests/helpers/engine_output.gd"
const TEMP_DIR := "user://tests/script_analysis"
const SELF_PATH := "res://tests/test_script_analysis.gd"
const MODEL_PATH := "res://model/aquarium_model.gd"
const MIN_SCRIPT_COUNT := 100
const WARNING_SUFFIX := " (Warning treated as error.)"
const UNUSED_HINT := (
	"is declared but never used in the block. "
	+ 'If this is intended, prefix it with an underscore: "_%s".'
)

var _temp_paths: PackedStringArray = PackedStringArray()


func after_test() -> void:
	for path: String in _temp_paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_temp_paths.clear()
	if DirAccess.dir_exists_absolute(TEMP_DIR):
		DirAccess.remove_absolute(TEMP_DIR)


func _load_helper(path: String) -> GDScript:
	var script: GDScript = null
	if ResourceLoader.exists(path):
		script = load(path) as GDScript
	assert_object(script).override_failure_message("%s does not exist yet" % path).is_not_null()
	return script


func _project_scripts() -> PackedStringArray:
	var analysis: GDScript = _load_helper(ANALYSIS_PATH)
	if analysis == null:
		return PackedStringArray()
	var paths: PackedStringArray = analysis.call("project_scripts")
	return paths


func _write_temp_script(file_name: String, function_body: String) -> String:
	DirAccess.make_dir_recursive_absolute(TEMP_DIR)
	var path: String = TEMP_DIR.path_join(file_name)
	_temp_paths.append(path)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "cannot write %s" % path)
	file.store_string("extends RefCounted\n\n\nfunc f() -> void:\n%s\n" % function_body)
	file.close()
	return path


func _expected_load_error(path: String) -> Dictionary:
	return {'Failed to load script "%s" with error "Parse error".' % path: 1}


## Runs failing_scripts over one broken script and returns {"failing": Array, "seen": Dictionary}.
func _run_failing(path: String) -> Dictionary:
	var analysis: GDScript = _load_helper(ANALYSIS_PATH)
	var output: GDScript = _load_helper(OUTPUT_PATH)
	if analysis == null or output == null:
		return {"failing": ["missing helper"], "seen": {}}
	var failing: Array = []
	var seen: Dictionary = await output.call(
		"capture_all",
		func() -> void:
			var found: PackedStringArray = analysis.call(
				"failing_scripts", PackedStringArray([path])
			)
			failing.append_array(found)
	)
	return {"failing": failing, "seen": seen}


func _assert_removed(path: String) -> void:
	DirAccess.remove_absolute(path)
	assert_bool(FileAccess.file_exists(path)).is_false()


# --- AC3: every project script loads -----------------------------------------------------------


func test_ac3_project_scripts_has_at_least_the_minimum_count() -> void:
	var paths: PackedStringArray = _project_scripts()
	(
		assert_bool(paths.size() >= MIN_SCRIPT_COUNT)
		. override_failure_message(
			"found only %d scripts, need %d" % [paths.size(), MIN_SCRIPT_COUNT]
		)
		. is_true()
	)


func test_ac3_project_scripts_contains_the_model_and_this_test_file() -> void:
	var paths: PackedStringArray = _project_scripts()
	assert_bool(paths.has(MODEL_PATH)).is_true()
	assert_bool(paths.has(SELF_PATH)).is_true()


func test_ac3_project_scripts_skips_addons_and_the_import_cache() -> void:
	var paths: PackedStringArray = _project_scripts()
	assert_bool(paths.is_empty()).is_false()
	for path: String in paths:
		assert_bool(path.begins_with("res://addons/")).is_false()
		assert_bool(path.begins_with("res://.godot/")).is_false()
		assert_bool(path.ends_with(".gd")).is_true()


func test_ac3_project_scripts_is_sorted() -> void:
	var paths: PackedStringArray = _project_scripts()
	var sorted_paths: PackedStringArray = paths.duplicate()
	sorted_paths.sort()
	assert_array(Array(paths)).is_equal(Array(sorted_paths))


func test_ac3_every_project_script_loads_and_can_instantiate() -> void:
	var analysis: GDScript = _load_helper(ANALYSIS_PATH)
	if analysis == null:
		return
	var paths: PackedStringArray = _project_scripts()
	var failing: PackedStringArray = analysis.call("failing_scripts", paths)
	(
		assert_bool(failing.is_empty())
		. override_failure_message(
			"%d script(s) do not load or instantiate:\n%s" % [failing.size(), "\n".join(failing)]
		)
		. is_true()
	)


func test_ac3_failing_scripts_of_no_paths_is_empty() -> void:
	var analysis: GDScript = _load_helper(ANALYSIS_PATH)
	if analysis == null:
		return
	var failing: PackedStringArray = analysis.call("failing_scripts", PackedStringArray())
	assert_array(Array(failing)).is_empty()


# --- AC4: an unused local is reported, once, with its engine lines -----------------------------


func test_ac4_a_script_with_an_unused_local_is_reported_with_one_script_error() -> void:
	var path: String = _write_temp_script("unused_local.gd", "\tvar y: int = 1")
	var run: Dictionary = await _run_failing(path)
	var seen: Dictionary = run["seen"]
	assert_array(run["failing"]).is_equal([path])
	var expected_script_errors: Dictionary = {
		'Parse Error: The local variable "y" %s%s' % [UNUSED_HINT % "y", WARNING_SUFFIX]: 1
	}
	assert_dict(seen.get("script_errors", {"unset": 1})).is_equal(expected_script_errors)
	assert_dict(seen.get("errors", {"unset": 1})).is_equal(_expected_load_error(path))
	assert_dict(seen.get("warnings", {"unset": 1})).is_empty()
	_assert_removed(path)


func test_ac4_two_unused_locals_give_one_script_error_each() -> void:
	var path: String = _write_temp_script(
		"two_unused_locals.gd", "\tvar y: int = 1\n\tvar w: int = 2"
	)
	var run: Dictionary = await _run_failing(path)
	var seen: Dictionary = run["seen"]
	assert_array(run["failing"]).is_equal([path])
	var expected_script_errors: Dictionary = {
		'Parse Error: The local variable "y" %s%s' % [UNUSED_HINT % "y", WARNING_SUFFIX]: 1,
		'Parse Error: The local variable "w" %s%s' % [UNUSED_HINT % "w", WARNING_SUFFIX]: 1,
	}
	assert_dict(seen.get("script_errors", {"unset": 1})).is_equal(expected_script_errors)
	assert_dict(seen.get("errors", {"unset": 1})).is_equal(_expected_load_error(path))
	assert_dict(seen.get("warnings", {"unset": 1})).is_empty()
	_assert_removed(path)


func test_ac4_a_clean_script_is_not_reported_and_logs_nothing() -> void:
	var path: String = _write_temp_script("clean.gd", "\tpass")
	var run: Dictionary = await _run_failing(path)
	var seen: Dictionary = run["seen"]
	assert_array(run["failing"]).is_empty()
	assert_dict(seen.get("script_errors", {"unset": 1})).is_empty()
	assert_dict(seen.get("errors", {"unset": 1})).is_empty()
	assert_dict(seen.get("warnings", {"unset": 1})).is_empty()
	_assert_removed(path)


func test_ac4_a_missing_script_path_is_reported() -> void:
	var analysis: GDScript = _load_helper(ANALYSIS_PATH)
	var output: GDScript = _load_helper(OUTPUT_PATH)
	if analysis == null or output == null:
		return
	var path: String = TEMP_DIR.path_join("does_not_exist.gd")
	var failing: Array = []
	await output.call(
		"capture_all",
		func() -> void:
			var found: PackedStringArray = analysis.call(
				"failing_scripts", PackedStringArray([path])
			)
			failing.append_array(found)
	)
	assert_array(failing).is_equal([path])


# --- AC5: untyped declaration and syntax error are reported ------------------------------------


func test_ac5_a_script_with_an_untyped_declaration_is_reported() -> void:
	var path: String = _write_temp_script("untyped_declaration.gd", "\tvar x = 1\n\tprint(x)")
	var run: Dictionary = await _run_failing(path)
	var seen: Dictionary = run["seen"]
	assert_array(run["failing"]).is_equal([path])
	var expected_script_errors: Dictionary = {
		'Parse Error: Variable "x" has no static type.%s' % WARNING_SUFFIX: 1
	}
	assert_dict(seen.get("script_errors", {"unset": 1})).is_equal(expected_script_errors)
	assert_dict(seen.get("errors", {"unset": 1})).is_equal(_expected_load_error(path))
	assert_dict(seen.get("warnings", {"unset": 1})).is_empty()
	_assert_removed(path)


func test_ac5_a_script_with_a_syntax_error_is_reported() -> void:
	# Recorded on Godot 4.7.2 for the body "func f( -> void:" (the file starts with "func f(").
	var path: String = _write_syntax_error_script("syntax_error.gd")
	var run: Dictionary = await _run_failing(path)
	var seen: Dictionary = run["seen"]
	assert_array(run["failing"]).is_equal([path])
	assert_dict(seen.get("script_errors", {"unset": 1})).is_equal(
		{"Parse Error: Expected parameter name.": 1}
	)
	assert_dict(seen.get("errors", {"unset": 1})).is_equal(_expected_load_error(path))
	assert_dict(seen.get("warnings", {"unset": 1})).is_empty()
	_assert_removed(path)


func _write_syntax_error_script(file_name: String) -> String:
	DirAccess.make_dir_recursive_absolute(TEMP_DIR)
	var path: String = TEMP_DIR.path_join(file_name)
	_temp_paths.append(path)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "cannot write %s" % path)
	file.store_string("extends RefCounted\n\n\nfunc f( -> void:\n\tpass\n")
	file.close()
	return path
