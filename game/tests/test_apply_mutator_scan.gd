extends GdUnitTestSuite

const SourceScan := preload("res://tests/helpers/source_scan.gd")

const EXCLUDED := ["res://model/", "res://tests/", "res://addons/", "res://.godot/"]


func _apply_names() -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	var script: GDScript = load("res://model/aquarium_model.gd") as GDScript
	for method: Dictionary in script.get_script_method_list():
		var method_name: String = method["name"]
		if method_name.begins_with("apply_") and not names.has(method_name):
			names.append(method_name)
	return names


func _patterns(names: PackedStringArray) -> Array[RegEx]:
	var expressions: PackedStringArray = PackedStringArray()
	for method_name: String in names:
		expressions.append("\\b" + method_name + "\\s*\\(")
	return SourceScan.compile(expressions)


func test_apply_name_list_not_empty() -> void:
	var names: PackedStringArray = _apply_names()
	assert_bool(names.has("apply_insert_item")).is_true()
	assert_bool(names.has("apply_remove_item")).is_true()
	assert_bool(names.has("apply_set_name")).is_true()


func test_no_apply_calls_outside_model_and_tests() -> void:
	var patterns: Array[RegEx] = _patterns(_apply_names())
	var scripts: PackedStringArray = SourceScan.list_scripts("res://", PackedStringArray(EXCLUDED))
	var offences: PackedStringArray = PackedStringArray()
	for path: String in scripts:
		var lines: PackedStringArray = SourceScan.strip_comments(SourceScan.read(path)).split("\n")
		for index: int in range(lines.size()):
			for hit: String in SourceScan.find_matches(lines[index], patterns):
				offences.append("%s:%d %s" % [path, index + 1, hit])
	(
		assert_array(offences)
		. override_failure_message(
			"apply_ mutators called outside the model layer: %s" % [offences]
		)
		. is_empty()
	)


func test_scan_covers_the_event_bus_script() -> void:
	var scripts: PackedStringArray = SourceScan.list_scripts("res://", PackedStringArray(EXCLUDED))
	assert_bool(scripts.has("res://systems/event_bus.gd")).is_true()
	assert_bool(scripts.has("res://model/aquarium_model.gd")).is_false()
	assert_bool(scripts.has("res://tests/test_apply_mutator_scan.gd")).is_false()


func test_scanner_flags_model_apply_call() -> void:
	var patterns: Array[RegEx] = _patterns(_apply_names())
	var fake: String = 'model.apply_remove_item("a")\n'
	assert_array(SourceScan.find_matches(fake, patterns)).is_not_empty()


func test_scanner_ignores_engine_apply_methods() -> void:
	var patterns: Array[RegEx] = _patterns(_apply_names())
	var fake: String = "body.apply_impulse(v)\nbody.apply_central_force(f)\n"
	assert_array(SourceScan.find_matches(fake, patterns)).is_empty()


func test_scanner_ignores_apply_calls_in_comments() -> void:
	var patterns: Array[RegEx] = _patterns(_apply_names())
	var fake: String = "# model.apply_set_name(x)\nvar a: int = 1  # apply_set_name(x)\n"
	var stripped: String = SourceScan.strip_comments(fake)
	assert_array(SourceScan.find_matches(stripped, patterns)).is_empty()
