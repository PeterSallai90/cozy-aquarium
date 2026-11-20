extends GdUnitTestSuite
## #32 "Assets and docs" (owner: developer; the ADR amendments are the architect's and are already
## on the branch): docs/architecture.md lists Delete, Ctrl+Y and Ctrl+Shift+Z in the Reserved keys
## and no longer calls undo "a later issue"; backlog row 21 is size M (owner decision); the Systems
## layer names the two new EventBus requests; the Placement row names delete, recolour and the
## instance-parameter tint with ADR 0012; the Camera row links Amendments 1 and 2 of ADR 0008;
## docs/glossary.md rewrites Swatch and adds Original colour with the BA text; both ADRs carry the
## amendments. Pattern of test_placement_docs.gd.

const ARCHITECTURE := "docs/architecture.md"
const GLOSSARY := "docs/glossary.md"
const ADR_8 := "docs/adr/0008-world-input-routing-and-modal-blocking.md"
const ADR_12 := "docs/adr/0012-placement-system-drawn-items-hit-test-and-validity-seam.md"


func _read(path: String) -> String:
	var root: String = ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	return FileAccess.get_file_as_string(root.path_join(path))


func _row(text: String, prefix: String) -> String:
	for line: String in text.split("\n"):
		if line.begins_with(prefix):
			return line
	return ""


func _reserved_keys() -> String:
	var text: String = _read(ARCHITECTURE)
	var start: int = text.find("**Reserved keys:**")
	assert_int(start).override_failure_message("no Reserved keys paragraph").is_greater(-1)
	var end: int = text.find("\n\n", start)
	return text.substr(start, end - start)


func test_the_reserved_keys_list_delete_ctrl_y_and_ctrl_shift_z() -> void:
	var paragraph: String = _reserved_keys()
	assert_str(paragraph).contains("`Delete`")
	assert_str(paragraph).contains("`Ctrl+Z`")
	assert_str(paragraph).contains("`Ctrl+Y`")
	assert_str(paragraph).contains("`Ctrl+Shift+Z`")
	assert_str(paragraph).contains("0008")


func test_the_reserved_keys_no_longer_call_undo_a_later_issue() -> void:
	assert_str(_reserved_keys()).not_contains("a later")


func test_the_reserved_keys_name_the_comma_period_rule_of_31_unchanged() -> void:
	var paragraph: String = _reserved_keys()
	assert_str(paragraph).contains("Comma")
	assert_str(paragraph).contains("Period")


func test_backlog_row_21_is_size_m() -> void:
	var row: String = _row(_read(ARCHITECTURE), "| 21 |")
	assert_str(row).override_failure_message("no backlog row 21").is_not_empty()
	assert_str(row).contains("Delete and recolour items; undo/redo in UI")
	var cells: PackedStringArray = row.split("|")
	var cleaned: Array[String] = []
	for cell: String in cells:
		cleaned.append(cell.strip_edges())
	(
		assert_bool(cleaned.has("M"))
		. override_failure_message("row 21 is not size M: %s" % row)
		. is_true()
	)
	assert_bool(cleaned.has("S")).override_failure_message("row 21 still says S").is_false()


func test_the_systems_layer_names_the_two_new_eventbus_requests() -> void:
	var text: String = _read(ARCHITECTURE)
	assert_str(text).contains("item_delete_requested")
	assert_str(text).contains("item_colour_requested")


func test_the_placement_row_names_delete_recolour_and_the_tint_parameter() -> void:
	var row: String = _row(_read(ARCHITECTURE), "| Placement |").to_lower()
	assert_str(row).override_failure_message("no Placement row").is_not_empty()
	assert_str(row).contains("delete")
	assert_str(row).contains("recolour")
	assert_str(row).contains("instance")
	assert_str(row).contains("0012")


func test_the_camera_row_links_amendments_1_and_2_of_adr_0008() -> void:
	var row: String = _row(_read(ARCHITECTURE), "| Camera |")
	assert_str(row).contains("ADR 0008 (Amendments 1 and 2)")


func test_the_glossary_rewrites_swatch_for_substrates_and_colourable_items() -> void:
	var text: String = _read(GLOSSARY)
	var swatch: String = ""
	for line: String in text.split("\n"):
		if line.begins_with("**Swatch**"):
			swatch = line
	assert_str(swatch).override_failure_message("no Swatch entry").is_not_empty()
	assert_str(swatch).contains(
		"one catalog colour choice of a substrate type or a colourable item"
	)
	assert_str(swatch).contains("first swatch is its default colour")
	assert_str(swatch).contains("alternatives to its original colour")


func test_the_glossary_has_an_original_colour_entry() -> void:
	var entry: String = ""
	for line: String in _read(GLOSSARY).split("\n"):
		if line.begins_with("**Original colour**"):
			entry = line
	assert_str(entry).override_failure_message("no Original colour entry").is_not_empty()
	assert_str(entry).contains("the colour of the item's own model")
	assert_str(entry).contains("never listed as a swatch")


func test_the_two_adrs_carry_the_amendments_of_32() -> void:
	var adr_8: String = _read(ADR_8)
	assert_str(adr_8).contains("## Amendment 2 (#32")
	assert_str(adr_8).contains("world_gesture_sources")
	var adr_12: String = _read(ADR_12)
	assert_str(adr_12).contains("## Amendment 1 (#32")
	assert_str(adr_12).contains("item_tint")
