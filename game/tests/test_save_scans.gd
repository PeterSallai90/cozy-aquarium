extends GdUnitTestSuite

const SourceScan := preload("res://tests/helpers/source_scan.gd")

const EXCLUDED := ["res://model/", "res://tests/", "res://addons/", "res://.godot/"]
const STORE := "res://systems/save_store.gd"

const CODEC_FILES := [
	"res://model/save_codec.gd",
	"res://model/save_rules.gd",
	"res://model/save_migrations.gd",
	"res://model/save_result.gd",
]
const CODEC_FORBIDDEN := [
	"FileAccess",
	"DirAccess",
	"get_datetime_string_from_system",
	"get_unix_time_from_system",
	"get_ticks_",
]
const PHOTO_AND_CATALOG_FILES := [
	"res://model/save_codec.gd",
	"res://model/save_rules.gd",
	"res://systems/save_store.gd",
]
const PHOTO_AND_CATALOG_FORBIDDEN := ["get_system_dir", "SYSTEM_DIR_PICTURES", "res://catalog"]


func _set_save_times_pattern() -> Array[RegEx]:
	return SourceScan.compile(PackedStringArray(["\\bset_save_times\\s*\\("]))


func _tokens(tokens: Array) -> Array[RegEx]:
	var expressions: PackedStringArray = PackedStringArray()
	for token: String in tokens:
		expressions.append("\\b" + token)
	return SourceScan.compile(expressions)


func _hits_in(path: String, patterns: Array[RegEx]) -> PackedStringArray:
	var hits: PackedStringArray = PackedStringArray()
	var lines: PackedStringArray = SourceScan.strip_comments(SourceScan.read(path)).split("\n")
	for index: int in range(lines.size()):
		for hit: String in SourceScan.find_matches(lines[index], patterns):
			hits.append("%s:%d %s" % [path, index + 1, hit])
	return hits


# --- set_save_times callers ------------------------------------------------------------------


func test_set_save_times_only_called_from_save_store() -> void:
	var patterns: Array[RegEx] = _set_save_times_pattern()
	var scripts: PackedStringArray = SourceScan.list_scripts("res://", PackedStringArray(EXCLUDED))
	var offences: PackedStringArray = PackedStringArray()
	for path: String in scripts:
		if path == STORE:
			continue
		offences.append_array(_hits_in(path, patterns))
	(
		assert_array(offences)
		. override_failure_message("set_save_times called outside the save store: %s" % [offences])
		. is_empty()
	)


func test_save_store_calls_set_save_times() -> void:
	var scripts: PackedStringArray = SourceScan.list_scripts("res://", PackedStringArray(EXCLUDED))
	assert_bool(scripts.has(STORE)).is_true()
	assert_array(_hits_in(STORE, _set_save_times_pattern())).is_not_empty()


func test_save_store_never_calls_apply_methods() -> void:
	var names: PackedStringArray = PackedStringArray()
	var script: GDScript = load("res://model/aquarium_model.gd") as GDScript
	for method: Dictionary in script.get_script_method_list():
		var method_name: String = method["name"]
		if method_name.begins_with("apply_") and not names.has(method_name):
			names.append("\\b" + method_name + "\\s*\\(")
	assert_array(names).is_not_empty()
	var patterns: Array[RegEx] = SourceScan.compile(names)
	assert_array(_hits_in(STORE, patterns)).is_empty()
	assert_str(SourceScan.read(STORE)).contains("reset_from")


func test_scanner_flags_a_fake_set_save_times_call() -> void:
	var fake: String = 'model.set_save_times("a", "b")\n'
	assert_array(SourceScan.find_matches(fake, _set_save_times_pattern())).is_not_empty()


func test_scanner_ignores_set_save_times_in_comments() -> void:
	var fake: String = '# model.set_save_times("a", "b")\nvar a: int = 1  # set_save_times(x)\n'
	var stripped: String = SourceScan.strip_comments(fake)
	assert_array(SourceScan.find_matches(stripped, _set_save_times_pattern())).is_empty()


func test_scanner_ignores_other_methods_with_a_similar_name() -> void:
	var fake: String = "model.get_save_times()\nmodel.set_save_time_zone(1)\n"
	assert_array(SourceScan.find_matches(fake, _set_save_times_pattern())).is_empty()


# --- the codec stays pure ------------------------------------------------------------------


func test_codec_files_have_no_io_and_no_clock() -> void:
	var patterns: Array[RegEx] = _tokens(CODEC_FORBIDDEN)
	var offences: PackedStringArray = PackedStringArray()
	for path: String in CODEC_FILES:
		assert_str(SourceScan.read(path)).is_not_empty()
		offences.append_array(_hits_in(path, patterns))
	(
		assert_array(offences)
		. override_failure_message("file or clock access in the codec: %s" % [offences])
		. is_empty()
	)


func test_purity_scan_flags_fake_io_and_clock_calls() -> void:
	var patterns: Array[RegEx] = _tokens(CODEC_FORBIDDEN)
	var fake: String = "var f := FileAccess.open(p, 1)\nTime.get_unix_time_from_system()\n"
	assert_int(SourceScan.find_matches(fake, patterns).size()).is_equal(2)
	var fine: String = "Time.get_unix_time_from_datetime_string(s)\n"
	assert_array(SourceScan.find_matches(fine, patterns)).is_empty()


# --- photos and catalog are never touched ---------------------------------------------------


func test_save_code_never_reads_catalog_or_photos() -> void:
	var patterns: Array[RegEx] = SourceScan.compile(
		PackedStringArray(["get_system_dir", "SYSTEM_DIR_PICTURES", "res://catalog"])
	)
	var offences: PackedStringArray = PackedStringArray()
	for path: String in PHOTO_AND_CATALOG_FILES:
		assert_str(SourceScan.read(path)).is_not_empty()
		offences.append_array(_hits_in(path, patterns))
	(
		assert_array(offences)
		. override_failure_message("photo folder or catalog used by save code: %s" % [offences])
		. is_empty()
	)
	assert_array(PHOTO_AND_CATALOG_FORBIDDEN).has_size(3)
