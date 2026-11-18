extends GdUnitTestSuite
## #28 criteria 35 and 38 (owner: technical-artist for project.godot): TAA is the project default
## and no other anti-aliasing mode is. The settings come from the ProjectSettings only: no scene,
## resource or script under res:// sets TAA, MSAA, or screen-space AA on a
## viewport (the measure scripts in tests/ and the addons are outside the scan). Selectable
## anti-aliasing is #81. AC 38 (the full suite stays green with no existing test edited) is the
## suite result itself and the reviewer's diff check.

const SourceScan := preload("res://tests/helpers/source_scan.gd")

const EXCLUDED: PackedStringArray = ["res://tests/", "res://addons/", "res://.godot/"]
## Property names that set anti-aliasing on a viewport or an environment.
const OVERRIDES: Array[String] = [
	"\\buse_taa\\b",
	"\\bmsaa_3d\\b",
	"\\bmsaa_2d\\b",
	"\\bscreen_space_aa\\b",
]
const MAIN_SCENE := "res://scenes/main.tscn"


func test_ac35_taa_is_on_by_default() -> void:
	(
		assert_bool(ProjectSettings.get_setting("rendering/anti_aliasing/quality/use_taa", false))
		. is_true()
	)


func test_ac35_no_other_anti_aliasing_mode_is_the_default() -> void:
	(
		assert_int(int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d", 0)))
		. is_equal(0)
	)
	(
		assert_int(int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_2d", 0)))
		. is_equal(0)
	)
	(
		assert_int(
			int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/screen_space_aa", 0))
		)
		. is_equal(0)
	)


func test_ac35_the_settings_are_written_in_project_godot() -> void:
	var text: String = FileAccess.get_file_as_string("res://project.godot")
	assert_str(text).contains("anti_aliasing/quality/use_taa=true")
	assert_str(text).not_contains("anti_aliasing/quality/msaa_3d=1")
	assert_str(text).not_contains("anti_aliasing/quality/msaa_3d=2")
	assert_str(text).not_contains("anti_aliasing/quality/msaa_3d=3")
	assert_str(text).not_contains("anti_aliasing/quality/screen_space_aa=1")


func test_ac38_no_scene_resource_or_script_sets_anti_aliasing_itself() -> void:
	var patterns: Array[RegEx] = SourceScan.compile(PackedStringArray(OVERRIDES))
	var files: PackedStringArray = SourceScan.list_files(
		"res://", EXCLUDED, PackedStringArray([".tscn", ".tres", ".gd"])
	)
	assert_array(files).is_not_empty()
	for path: String in files:
		var text: String = SourceScan.read(path)
		if path.ends_with(".gd"):
			text = SourceScan.strip_comments(text)
		var hits: PackedStringArray = SourceScan.find_matches(text, patterns)
		(
			assert_array(hits)
			. override_failure_message("%s sets an anti-aliasing property: %s" % [path, hits])
			. is_empty()
		)


func test_ac35_the_main_scene_still_instantiates_headless() -> void:
	var scene: PackedScene = load(MAIN_SCENE) as PackedScene
	assert_object(scene).is_not_null()
	var main: Node = scene.instantiate()
	assert_object(main).is_not_null()
	main.free()
