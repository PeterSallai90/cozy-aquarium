extends GdUnitTestSuite

const SourceScan := preload("res://tests/helpers/source_scan.gd")

const FORBIDDEN := [
	"get_node\\s*\\(",
	"get_tree\\s*\\(",
	'\\$["A-Za-z_%/]',
	"\\bEventBus\\b",
	"\\.t?scn\\b",
]


func _scripts() -> PackedStringArray:
	return SourceScan.list_scripts("res://model", PackedStringArray())


func test_scan_finds_model_scripts() -> void:
	var scripts: PackedStringArray = _scripts()
	assert_bool(scripts.is_empty()).is_false()
	assert_bool(scripts.has("res://model/aquarium_model.gd")).is_true()


func test_model_scripts_are_not_nodes() -> void:
	var scripts: PackedStringArray = _scripts()
	assert_bool(scripts.is_empty()).is_false()
	for path: String in scripts:
		var script: GDScript = load(path) as GDScript
		assert_object(script).override_failure_message(path).is_not_null()
		var base: StringName = script.get_instance_base_type()
		(
			assert_bool(ClassDB.is_parent_class(base, &"Node"))
			. override_failure_message("%s extends a Node type (%s)" % [path, base])
			. is_false()
		)


func test_model_scripts_have_no_scene_tree_or_bus_references() -> void:
	var patterns: Array[RegEx] = SourceScan.compile(PackedStringArray(FORBIDDEN))
	var scripts: PackedStringArray = _scripts()
	assert_bool(scripts.is_empty()).is_false()
	for path: String in scripts:
		var source: String = SourceScan.strip_comments(SourceScan.read(path))
		var hits: PackedStringArray = SourceScan.find_matches(source, patterns)
		assert_array(hits).override_failure_message("%s: %s" % [path, hits]).is_empty()


func test_scanner_finds_forbidden_code() -> void:
	var patterns: Array[RegEx] = SourceScan.compile(PackedStringArray(FORBIDDEN))
	var fake: String = 'var a = get_node("x")\nvar b = $Foo\nEventBus.x()\nload("res://a.tscn")\n'
	var hits: PackedStringArray = SourceScan.find_matches(fake, patterns)
	assert_int(hits.size()).is_greater_equal(4)
	var joined: String = " ".join(hits)
	assert_str(joined).contains("get_node(")
	assert_str(joined).contains("$F")
	assert_str(joined).contains("EventBus")
	assert_str(joined).contains(".tscn")


func test_scanner_ignores_comments() -> void:
	var patterns: Array[RegEx] = SourceScan.compile(PackedStringArray(FORBIDDEN))
	var fake: String = '## never use get_node("x"), $Foo, EventBus.x or "res://a.tscn"\n# get_tree()\n'
	var hits: PackedStringArray = SourceScan.find_matches(SourceScan.strip_comments(fake), patterns)
	assert_array(hits).is_empty()
