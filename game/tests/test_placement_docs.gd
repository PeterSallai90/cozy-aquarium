extends GdUnitTestSuite
## #31 "Docs the pull request must update" (owner: developer; the architect has already written
## these lines on the branch, so this suite is a guard that passes before the implementation): the
## Placement row of docs/architecture.md (no "snapping", no "scale", still names SubstrateSurface
## and ADR 0012), the Reserved keys paragraph (Comma, Period and the Shift exception),
## backlog row 20
## (the new title and size L with the owner waiver), ADR 0012 and Amendment 1 of ADR 0008. Pattern
## of test_substrate_docs.gd.

const ARCHITECTURE := "docs/architecture.md"
const ADR_8 := "docs/adr/0008-world-input-routing-and-modal-blocking.md"
const ADR_12 := "docs/adr/0012-placement-system-drawn-items-hit-test-and-validity-seam.md"


func _read(path: String) -> String:
	var root: String = ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	return FileAccess.get_file_as_string(root.path_join(path))


func _row(prefix: String) -> String:
	for line: String in _read(ARCHITECTURE).split("\n"):
		if line.begins_with(prefix):
			return line
	return ""


func test_the_placement_row_names_the_substrate_surface_and_adr_0012() -> void:
	var row: String = _row("| Placement |")
	assert_str(row).override_failure_message("no Placement row").is_not_empty()
	assert_str(row).contains("SubstrateSurface")
	assert_str(row).contains("0012")


func test_the_placement_row_has_no_snapping_and_no_scale() -> void:
	var row: String = _row("| Placement |").to_lower()
	assert_bool(row.contains("snapping")).is_false()
	assert_bool(row.contains("scale")).is_false()


func test_the_reserved_keys_name_comma_period_and_the_shift_exception() -> void:
	var text: String = _read(ARCHITECTURE)
	var start: int = text.find("**Reserved keys:**")
	assert_int(start).override_failure_message("no Reserved keys paragraph").is_greater(-1)
	var paragraph: String = text.substr(start, 1600)
	assert_str(paragraph).contains("Comma")
	assert_str(paragraph).contains("Period")
	assert_str(paragraph).contains("Shift")
	assert_str(paragraph).contains("0008")


func test_backlog_row_20_has_the_new_title_and_size_l_with_the_waiver() -> void:
	var row: String = _row("| 20 |")
	assert_str(row).contains("Place, move and rotate items with ghost preview and rotation steps")
	assert_str(row).contains("| L ")
	assert_str(row).contains("waiver")


func test_adr_0008_has_amendment_1_with_the_shift_exception() -> void:
	var text: String = _read(ADR_8)
	assert_str(text).contains("## Amendment 1")
	assert_str(text).contains("Shift")


func test_adr_0012_exists_and_names_its_seams() -> void:
	var text: String = _read(ADR_12)
	assert_str(text).override_failure_message("ADR 0012 is missing").is_not_empty()
	for term: String in ["PlacementRules", "ItemCatalogSource", "item_pick_clear_requested"]:
		assert_str(text).contains(term)
