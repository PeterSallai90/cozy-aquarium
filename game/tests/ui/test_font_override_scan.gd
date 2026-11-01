extends GdUnitTestSuite
## No control sets its own font: the fallback chain lives in the global theme only. The scan
## also reads planted fixtures, so an empty or broken scan cannot pass.

const SourceScan := preload("res://tests/helpers/source_scan.gd")

const SUFFIXES: PackedStringArray = [".gd", ".tscn", ".tres"]
const EXCLUDED: PackedStringArray = [
	"res://addons/",
	"res://tests/",
	"res://assets/fonts/",
	"res://.godot/",
	"res://reports/",
	"res://ui/theme/cozy_theme.tres",
	"res://ui/dev/glyph_test.tscn",
	"res://ui/dev/glyph_test.gd",
]
const FIXTURES := "res://tests/fixtures/fonts/"
const FIXTURE_FILES: PackedStringArray = [
	"res://tests/fixtures/fonts/planted_font.tres",
	"res://tests/fixtures/fonts/planted_override.gd",
	"res://tests/fixtures/fonts/planted_override.tscn",
]
const REAL_SAMPLES: PackedStringArray = [
	"res://scenes/main.tscn",
	"res://ui/fonts/font_layers.gd",
]
const NOT_SCANNED: PackedStringArray = [
	"res://ui/theme/cozy_theme.tres",
	"res://ui/dev/glyph_test.tscn",
	"res://ui/dev/glyph_test.gd",
]

## id, regular expression, suffixes it applies to.
const RULES: Array[Dictionary] = [
	{
		"id": "scene_override",
		"regex": "theme_override_fonts/",
		"suffixes": [".gd", ".tscn", ".tres"]
	},
	{
		"id": "script_override",
		"regex": "\\badd_theme_font_override\\s*\\(",
		"suffixes": [".gd", ".tscn", ".tres"],
	},
	{
		"id": "font_new",
		"regex": "\\b(FontFile|FontVariation|SystemFont)\\s*\\.\\s*new\\s*\\(",
		"suffixes": [".gd"],
	},
	{"id": "load_font_data", "regex": "\\bload_(dynamic|bitmap)_font\\s*\\(", "suffixes": [".gd"]},
	{
		"id": "font_resource_type",
		"regex": 'type="(FontFile|FontVariation|SystemFont)"',
		"suffixes": [".tscn", ".tres"],
	},
]


## One entry per offence: "path:line match". The rule ids that fired go into hit_rules.
func _scan(files: PackedStringArray, hit_rules: Array[String]) -> PackedStringArray:
	var offences: PackedStringArray = PackedStringArray()
	for path: String in files:
		var source: String = SourceScan.read(path)
		if path.ends_with(".gd"):
			source = SourceScan.strip_comments(source)
		var lines: PackedStringArray = source.split("\n")
		for rule: Dictionary in RULES:
			if not _applies(path, rule["suffixes"] as Array):
				continue
			var pattern: RegEx = SourceScan.compile(PackedStringArray([rule["regex"]]))[0]
			for index: int in lines.size():
				var hit: RegExMatch = pattern.search(lines[index])
				if hit != null:
					offences.append("%s:%d %s" % [path, index + 1, hit.get_string()])
					if not hit_rules.has(rule["id"] as String):
						hit_rules.append(rule["id"] as String)
	return offences


func _applies(path: String, suffixes: Array) -> bool:
	for suffix: String in suffixes:
		if path.ends_with(suffix as String):
			return true
	return false


func test_no_scene_script_or_resource_sets_its_own_font() -> void:
	var files: PackedStringArray = SourceScan.list_files("res://", EXCLUDED, SUFFIXES)
	var rules: Array[String] = []
	var offences: PackedStringArray = _scan(files, rules)
	(
		assert_array(Array(offences))
		. override_failure_message("font overrides outside the theme:\n" + "\n".join(offences))
		. is_empty()
	)


func test_the_real_scan_is_not_empty_and_skips_the_excepted_files() -> void:
	var files: PackedStringArray = SourceScan.list_files("res://", EXCLUDED, SUFFIXES)
	assert_int(files.size()).is_greater(0)
	for path: String in REAL_SAMPLES:
		(
			assert_bool(files.has(path))
			. override_failure_message("the scan does not list " + path)
			. is_true()
		)
	for path: String in NOT_SCANNED:
		(
			assert_bool(files.has(path))
			. override_failure_message("the scan must skip " + path)
			. is_false()
		)
	for path: String in files:
		(
			assert_bool(path.begins_with("res://tests/") or path.begins_with("res://addons/"))
			. is_false()
		)


func test_the_scan_catches_every_planted_fixture() -> void:
	var files: PackedStringArray = SourceScan.list_files(FIXTURES, PackedStringArray(), SUFFIXES)
	assert_array(Array(files)).is_equal(Array(FIXTURE_FILES))
	for path: String in files:
		var rules: Array[String] = []
		var offences: PackedStringArray = _scan(PackedStringArray([path]), rules)
		(
			assert_array(Array(offences))
			. override_failure_message("the scan missed the planted fixture " + path)
			. is_not_empty()
		)


func test_the_scan_fires_every_forbidden_pattern_on_the_fixtures() -> void:
	var files: PackedStringArray = SourceScan.list_files(FIXTURES, PackedStringArray(), SUFFIXES)
	var rules: Array[String] = []
	var offences: PackedStringArray = _scan(files, rules)
	assert_int(offences.size()).is_greater(0)
	for rule: Dictionary in RULES:
		(
			assert_bool(rules.has(rule["id"] as String))
			. override_failure_message("no fixture triggers the pattern " + (rule["id"] as String))
			. is_true()
		)


func test_a_size_override_is_not_a_font_override() -> void:
	var pattern: RegEx = SourceScan.compile(PackedStringArray([RULES[1]["regex"]]))[0]
	assert_object(pattern.search('add_theme_font_size_override("font_size", 12)')).is_null()
	assert_object(pattern.search('add_theme_font_override("font", f)')).is_not_null()
