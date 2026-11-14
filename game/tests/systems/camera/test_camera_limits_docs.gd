extends GdUnitTestSuite
## #27 criterion 11 (owner: developer fixes the ADR line): ADR 0009 links the owner decision of #26,
## not the question comment, and no file under docs/ links the old comment. The ADR status line is
## not asserted (flipping it is out of scope, BA decision Q13).

const ADR_PATH := "docs/adr/0009-build-camera-collision-analytic-solids.md"
const ISSUE_26 := "https://github.com/PeterSallai90/cozy-aquarium/issues/26"
const DECISION_COMMENT := ISSUE_26 + "#issuecomment-6808157598"
const OLD_COMMENT_ID := "6808114113"
const HEADER_LINES: int = 12


func _repo_root() -> String:
	return ProjectSettings.globalize_path("res://").path_join("..").simplify_path()


func _files_under(directory: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	for file: String in DirAccess.get_files_at(directory):
		found.append(directory.path_join(file))
	for sub: String in DirAccess.get_directories_at(directory):
		found.append_array(_files_under(directory.path_join(sub)))
	return found


func test_the_adr_0009_amended_line_links_the_owner_decision() -> void:
	var text: String = FileAccess.get_file_as_string(_repo_root().path_join(ADR_PATH))
	assert_bool(text.is_empty()).is_false()
	var lines: PackedStringArray = text.split("\n")
	var amended: String = ""
	for index: int in mini(HEADER_LINES, lines.size()):
		if lines[index].contains("amended") or lines[index].contains("issuecomment-"):
			amended += lines[index] + "\n"
	assert_str(amended).contains(DECISION_COMMENT)
	assert_str(amended).not_contains(OLD_COMMENT_ID)


func test_no_file_under_docs_links_the_old_question_comment() -> void:
	var files: PackedStringArray = _files_under(_repo_root().path_join("docs"))
	assert_int(files.size()).is_greater(0)
	var offenders: PackedStringArray = PackedStringArray()
	for file: String in files:
		if FileAccess.get_file_as_string(file).contains(OLD_COMMENT_ID):
			offenders.append(file)
	(
		assert_bool(offenders.is_empty())
		. override_failure_message("old comment id still linked in: %s" % ", ".join(offenders))
		. is_true()
	)
