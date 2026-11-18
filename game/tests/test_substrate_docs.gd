# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #28 criterion 19 (owner: developer; the reviewer checks the PR body): the documentation edits of
## BA decision Q7 are in the diff. Backlog row 17 names the five types and stays M1 and size M,
## row 32 is kept and marked "Superseded by 17:" with milestone "M1 (in 17)", the M2 exit criterion
## no longer names substrates, the M1 exit criterion is unchanged, and the glossary has the two
## entries Substrate and Swatch. ADR 0010 is part of the diff. Pattern: test_camera_limits_docs.gd.
## Real 3D substrate (technical plan v3, section 6, AC 19, 26): ADR 0011 is new with status Proposed
## and records H1, the shell and core, the bake format, the budget and the mid-range factor F = 3
## (added GPU time on the RX 6800 XT at most 0.5 ms); architecture.md states H1 in the model
## conventions and the save-format Units line and names the bed in the Substrate and Placement rows
## and the photo mode margin; art-style.md has the one Triangle budgets line and the sand note.

const ARCHITECTURE := "docs/architecture.md"
const GLOSSARY := "docs/glossary.md"
const ADR := "docs/adr/0010-substrate-catalog-defaults-and-load-normalisation.md"
const ADR_11 := "docs/adr/0011-substrate-bed-surface-height-and-grain-instancing.md"
const RESEARCH := "docs/research/substrate-rendering.md"
const ART_STYLE := "docs/art-style.md"
const ENTRY_STARTS: Array[String] = ["#", "**", "|", "- "]
const EXTRA_ROW_START := "| Added GPU, extra cases of other tanks |"


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


# --- the real 3D substrate (ADR 0011, AC 19 and 26) ---


func test_ac19_adr_0011_is_new_proposed_and_records_the_decisions() -> void:
	var text: String = _text(ADR_11)
	assert_str(text).override_failure_message("%s is missing" % ADR_11).is_not_empty()
	assert_str(text).contains("# ADR 0011")
	assert_str(text).contains("Status: Proposed")
	for needle: String in [
		"H1",
		"SubstrateSurface",
		"fill_depth_m",
		"CASB",
		"Blender",
		"WorkerThreadPool",
		"substrate_sand_grain",
		"VERTEX",
		"Measured results",
	]:
		assert_str(text).override_failure_message("ADR 0011 does not mention %s" % needle).contains(
			needle
		)


func test_ac19_adr_0011_has_the_budget_and_the_mid_range_factor_of_3() -> void:
	var text: String = _text(ADR_11)
	for needle: String in [
		"0.6 M triangles",
		"1.0 M",
		"100,000 unique stones",
		"1.5 ms",
		"F = 3",
		"0.5 ms",
		"RX 6800 XT",
		"RTX 3060",
	]:
		assert_str(text).override_failure_message("ADR 0011 does not mention %s" % needle).contains(
			needle
		)
	assert_str(text).override_failure_message("F = 4.0 is the retired proposal").not_contains(
		"**F = 4.0**"
	)


func test_ac19_the_research_report_is_in_the_diff() -> void:
	assert_str(_text(RESEARCH)).override_failure_message("%s is missing" % RESEARCH).is_not_empty()


func test_ac26_the_model_conventions_state_h1_and_the_flat_heightmap_meaning() -> void:
	var line: String = _line_starting("Model conventions (issue #16)")
	assert_str(line).override_failure_message("model conventions line not found").is_not_empty()
	assert_str(line).contains("above the substrate surface")
	assert_str(line).contains("fill depth")
	assert_str(line).contains("ADR 0011")


func test_ac26_the_save_format_units_line_states_that_item_y_is_above_the_substrate() -> void:
	var units: String = ""
	for line: String in _text(ARCHITECTURE).split("\n"):
		if line.contains("Units:") and line.contains("Contents."):
			units = line
	assert_str(units).override_failure_message("save-format Units line not found").is_not_empty()
	assert_str(units).contains("substrate surface")


func test_ac19_the_core_systems_rows_name_the_bed_and_the_surface_helper() -> void:
	var substrate: String = _line_starting("| Substrate |")
	assert_str(substrate).override_failure_message("Substrate row not found").is_not_empty()
	assert_str(substrate).contains("ADR 0011")
	assert_str(substrate).contains("3D bed")
	var placement: String = _line_starting("| Placement |")
	assert_str(placement).override_failure_message("Placement row not found").is_not_empty()
	assert_str(placement).contains("SubstrateSurface")


func test_ac19_photo_mode_keeps_2_cm_above_the_substrate_surface() -> void:
	var found: bool = false
	for line: String in _text(ARCHITECTURE).split("\n"):
		if line.contains("2 cm above the substrate surface"):
			found = true
	(
		assert_bool(found)
		. override_failure_message(
			'the photo mode line says "2 cm above the substrate", not "2 cm above the substrate surface"'
		)
		. is_true()
	)


## The text of art-style.md with every run of white space collapsed to one space, so a line the
## writer wrapped is still one sentence here.
func _art_style_flat() -> String:
	return RegEx.create_from_string("\\s+").sub(_text(ART_STYLE), " ", true)


func test_ac19_the_triangle_budget_section_names_the_substrate_bed_budget() -> void:
	var text: String = _art_style_flat()
	var at: int = text.find("Substrate bed")
	(
		assert_int(at)
		. override_failure_message("no Substrate bed line in art-style.md")
		. is_greater_equal(0)
	)
	if at < 0:
		return
	var line: String = text.substr(at, 260)
	for needle: String in [
		"0.6 M triangles", "default camera", "1.0 M", "100 k unique stones", "1.5 ms", "ADR 0011"
	]:
		assert_str(line).override_failure_message("the budget line lacks %s" % needle).contains(
			needle
		)


func test_ac19_art_style_says_sand_grains_may_be_drawn_larger_than_real() -> void:
	assert_str(_art_style_flat()).contains("sand grains may be drawn larger than real")


# --- ADR 0011 line wrap and extra-case row (issue #140) ---


## The ADR 0011 lines that start with the extra-cases row prefix.
func _extra_rows() -> Array[String]:
	var rows: Array[String] = []
	var lines: PackedStringArray = _text(ADR_11).split("\n")
	for line: String in lines:
		if line.begins_with(EXTRA_ROW_START):
			rows.append(line)
	return rows


func _extra_row() -> String:
	var rows: Array[String] = _extra_rows()
	(
		assert_int(rows.size())
		. override_failure_message("expected exactly one extra-cases row")
		. is_equal(1)
	)
	return "" if rows.is_empty() else rows[0]


func test_ac1_adr_0011_prose_lines_are_at_most_100_characters() -> void:
	var lines: PackedStringArray = _text(ADR_11).split("\n")
	var too_long: Array[String] = []
	for i: int in lines.size():
		var line: String = lines[i]
		if not line.begins_with("|") and line.length() > 100:
			too_long.append("line %d has %d characters" % [i + 1, line.length()])
	(
		assert_array(too_long)
		. override_failure_message("prose lines over 100 characters: %s" % ", ".join(too_long))
		. is_empty()
	)


func test_ac1_the_extra_cases_sentence_is_only_wrapped() -> void:
	var flat: String = RegEx.create_from_string("\\s+").sub(_text(ADR_11), " ", true)
	assert_str(flat).contains(
		(
			"The extra cases of the small and medium tanks (rule 15: the heaviest default-camera"
			+ " estimate and each other-tank view above the large tank's estimate) used the"
			+ " stand-in load scaled to the floor area (small 15 fish and 25 decor, medium 27 fish"
			+ " and 45 decor). Every check passed."
		)
	)


func test_ac2_the_extra_cases_row_lists_the_13_cases() -> void:
	var row: String = _extra_row()
	for needle: String in [
		"13 cases measured",
		"12 of them above the large tank's estimate",
		"medium gravel_coloured top_35 (256,104 triangles",
		"303,768",
		"measured anyway",
		(
			"Medium: sand_fine default, sand_fine top_35, sand_black default, sand_black top_35,"
			+ " gravel_natural top_35, gravel_coloured top_35, gravel_coloured top_12."
		),
		(
			"Small: sand_fine default, sand_fine top_12, sand_black default, sand_black top_12,"
			+ " gravel_natural top_12, gravel_coloured top_12."
		),
	]:
		assert_str(row).override_failure_message("the row lacks: %s" % needle).contains(needle)


func test_ac3_the_extra_cases_row_separates_heaviest_estimate_and_highest_measured() -> void:
	var row: String = _extra_row()
	for needle: String in [
		(
			"medium sand_fine default, 298,206 triangles, 0.218 ms (technical-artist run;"
			+ " tester run 0.224 ms)"
		),
		"0.266 ms, small sand_fine default (technical-artist run)",
		"tester run maximum 0.262 ms, small sand_black default",
		"different cases",
	]:
		assert_str(row).override_failure_message("the row lacks: %s" % needle).contains(needle)


func test_ac4_the_extra_cases_row_is_one_table_line() -> void:
	var lines: PackedStringArray = _text(ADR_11).split("\n")
	var at: int = -1
	for i: int in lines.size():
		if lines[i].begins_with(EXTRA_ROW_START):
			at = i
	assert_int(at).override_failure_message("extra-cases row not found").is_greater_equal(0)
	if at < 0:
		return
	var row: String = lines[at].strip_edges()
	assert_bool(row.begins_with("|") and row.ends_with("|")).is_true()
	assert_int(row.count("|")).override_failure_message("row must have 3 cells").is_equal(4)
	assert_bool(at + 1 < lines.size() and lines[at + 1].begins_with("| MultiMesh nodes")).is_true()


func test_ac5_the_old_extra_case_numbers_are_gone() -> void:
	var row: String = _extra_row()
	assert_str(row).not_contains("0.27 ms")
	assert_str(row).not_contains("0.263")
