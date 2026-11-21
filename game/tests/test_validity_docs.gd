extends GdUnitTestSuite
## #33 "Docs the pull request must update" (owner: developer; the architect has already written
## these lines on the branch, so this suite is a guard that passes before the implementation):
## ADR 0012 Amendment 2 (names the `_same_spot` shortcut it replaces and "AC 41" it supersedes), the
## Catalog schema paragraph (the footprint_cm exception), the Placement row, backlog row 22 (size M)
## and the glossary entries Footprint, Interior, Surface and Touching. Pattern of
## test_placement_docs.gd.

const ARCHITECTURE := "docs/architecture.md"
const GLOSSARY := "docs/glossary.md"
const ADR_12 := "docs/adr/0012-placement-system-drawn-items-hit-test-and-validity-seam.md"


func _read(path: String) -> String:
	var root: String = ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	return FileAccess.get_file_as_string(root.path_join(path))


func _row(prefix: String) -> String:
	for line: String in _read(ARCHITECTURE).split("\n"):
		if line.begins_with(prefix):
			return line
	return ""


func _amendment_2() -> String:
	var text: String = _read(ADR_12)
	var start: int = text.find("## Amendment 2")
	return text.substr(start) if start >= 0 else ""


func test_adr_12_has_amendment_2_naming_same_spot_and_ac_41() -> void:
	var amendment: String = _amendment_2()
	assert_str(amendment).override_failure_message("no ## Amendment 2 in ADR 0012").is_not_empty()
	assert_str(amendment).contains("_same_spot")
	assert_str(amendment).contains("AC 41")
	assert_str(amendment).contains("#33")


func test_the_catalog_schema_paragraph_names_the_footprint_exception() -> void:
	var found: bool = false
	for line: String in _read(ARCHITECTURE).split("\n"):
		if line.contains("Mode 1 ignores them"):
			found = true
			assert_str(line).contains("footprint_cm")
	assert_bool(found).override_failure_message("no Mode 1 ignores them line").is_true()


func test_the_placement_row_names_footprint_cm_and_amendment_2() -> void:
	var row: String = _row("| Placement |")
	assert_str(row).override_failure_message("no Placement row").is_not_empty()
	assert_str(row).contains("footprint_cm")
	assert_str(row).contains("Amendment 2")


func test_backlog_row_22_has_size_m() -> void:
	var row: String = _row("| 22 |")
	assert_str(row).override_failure_message("no backlog row 22").is_not_empty()
	assert_str(row).contains("| M |")
	assert_bool(row.contains("| S |")).is_false()


func test_the_glossary_has_footprint_interior_surface_and_touching() -> void:
	var glossary: String = _read(GLOSSARY)
	for term: String in ["Footprint", "Interior", "Surface", "Touching"]:
		assert_bool(glossary.contains("**%s**" % term)).override_failure_message(term).is_true()
