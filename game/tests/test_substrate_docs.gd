extends GdUnitTestSuite
## #28 criterion 19 (owner: developer; the reviewer checks the PR body): the documentation edits of
## BA decision Q7 are in the diff. Backlog row 17 names the five types and stays M1 and size M,
## row 32 is kept and marked "Superseded by 17:" with milestone "M1 (in 17)", the M2 exit criterion
## no longer names substrates, the M1 exit criterion is unchanged, and the glossary has the two
## entries Substrate and Swatch. ADR 0010 is part of the diff. Pattern: test_camera_limits_docs.gd.

const ARCHITECTURE := "docs/architecture.md"
const GLOSSARY := "docs/glossary.md"
const ADR := "docs/adr/0010-substrate-catalog-defaults-and-load-normalisation.md"
const ENTRY_STARTS: Array[String] = ["#", "**", "|", "- "]


func _repo_root() -> String:
	return ProjectSettings.globalize_path("res://").path_join("..").simplify_path()


func _text(path: String) -> String:
	return FileAccess.get_file_as_string(_repo_root().path_join(path))


## The backlog table row that starts with "| <number> |", or "".
func _row(number: int) -> String:
	for line: String in _text(ARCHITECTURE).split("\n"):
		if line.begins_with("| %d |" % number):
			return line
	return ""


func _line_starting(prefix: String) -> String:
	for line: String in _text(ARCHITECTURE).split("\n"):
		if line.begins_with(prefix):
			return line
	return ""


## True when a line that looks like a glossary entry (heading, bold, row, bullet) names the term.
func _has_entry(term: String) -> bool:
	for line: String in _text(GLOSSARY).split("\n"):
		var lower: String = line.to_lower()
		if not lower.contains(term):
			continue
		for start: String in ENTRY_STARTS:
			if lower.begins_with(start):
				return true
	return false


func test_ac19_row_17_names_the_five_types_and_stays_m1_size_m() -> void:
	var row: String = _row(17)
	assert_str(row).override_failure_message("backlog row 17 not found").is_not_empty()
	assert_str(row).contains(
		"Substrate types with colour selection (sand, gravel, pebbles, black sand, coloured gravel)"
	)
	var cells: PackedStringArray = row.split("|")
	assert_str(cells[4].strip_edges()).is_equal("M1")
	assert_str(cells[6].strip_edges()).is_equal("M")


func test_ac19_row_32_is_kept_and_marked_superseded() -> void:
	var row: String = _row(32)
	assert_str(row).override_failure_message("backlog row 32 was deleted").is_not_empty()
	var cells: PackedStringArray = row.split("|")
	assert_str(cells[2].strip_edges()).starts_with("Superseded by 17:")
	assert_str(cells[4].strip_edges()).is_equal("M1 (in 17)")


func test_ac19_the_m2_exit_criterion_no_longer_names_substrates() -> void:
	var line: String = _line_starting("| M2 Content and photo mode")
	assert_str(line).override_failure_message("M2 milestone row not found").is_not_empty()
	assert_str(line).contains(
		"15 species, 10 plants, 15 decorations, photo mode with underwater shots"
	)
	assert_str(line).not_contains("5 substrates")


func test_ac19_the_m1_exit_criterion_is_unchanged() -> void:
	var line: String = _line_starting("| M1 First playable")
	assert_str(line).override_failure_message("M1 milestone row not found").is_not_empty()
	assert_str(line).contains(
		"You can arrange a tank, add 3 species, orbit the camera, save and reload"
	)


func test_ac19_the_glossary_has_the_substrate_and_swatch_entries() -> void:
	assert_bool(_has_entry("substrate")).override_failure_message("no Substrate entry").is_true()
	assert_bool(_has_entry("swatch")).override_failure_message("no Swatch entry").is_true()


func test_ac19_adr_0010_is_in_the_diff() -> void:
	assert_str(_text(ADR)).contains("ADR 0010")
