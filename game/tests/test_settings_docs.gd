extends GdUnitTestSuite
## #164 docs (owner: tester): the Settings row of docs/architecture.md lists the [fish] section
## with show_names, and the Fish animation row names FishLabelView as part of the fish
## presentation reading FishView through read-only queries. Pattern of test_history_docs.gd.

const ARCHITECTURE := "docs/architecture.md"


func _row(prefix: String) -> String:
	var root: String = ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	var text: String = FileAccess.get_file_as_string(root.path_join(ARCHITECTURE))
	assert_str(text).override_failure_message("architecture.md was not read").is_not_empty()
	for line: String in text.split("\n"):
		if line.begins_with(prefix):
			return line
	return ""


func test_the_settings_row_lists_the_fish_section_and_show_names() -> void:
	var row: String = _row("| Settings |")
	assert_str(row).is_not_empty()
	assert_str(row).contains("[fish]")
	assert_str(row).contains("show_names")
	assert_str(row).contains("[general]")


func test_the_fish_animation_row_names_the_label_view() -> void:
	var row: String = _row("| Fish animation |")
	assert_str(row).is_not_empty()
	assert_str(row).contains("FishLabelView")
	assert_str(row).contains("part of the fish presentation")
	assert_str(row).contains("read-only queries")
