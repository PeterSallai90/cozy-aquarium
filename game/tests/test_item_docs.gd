extends GdUnitTestSuite
## #152 criterion 13 (owner: developer): docs/glossary.md has the entries "Item" and "Category",
## and the Item entry says that `decor` is only a folder name. Pattern: test_substrate_docs.gd.

const GLOSSARY := "docs/glossary.md"
const ENTRY_STARTS: Array[String] = ["#", "**", "|", "- "]


func _lines() -> PackedStringArray:
	var root: String = ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	return FileAccess.get_file_as_string(root.path_join(GLOSSARY)).split("\n")


## The glossary line that is an entry for `term` (heading, bold, row or bullet), or "".
func _entry(term: String) -> String:
	for line: String in _lines():
		var lower: String = line.to_lower()
		for start: String in ENTRY_STARTS:
			var rest: String = lower.trim_prefix(start).strip_edges().trim_prefix("*").strip_edges()
			if lower.begins_with(start) and rest.begins_with(term):
				return line
	return ""


func test_ac13_the_glossary_has_the_item_entry() -> void:
	assert_str(_entry("item")).override_failure_message("no Item entry").is_not_empty()


func test_ac13_the_glossary_has_the_category_entry() -> void:
	assert_str(_entry("category")).override_failure_message("no Category entry").is_not_empty()


func test_ac13_the_item_entry_contains_the_word_decor() -> void:
	assert_str(_entry("item")).override_failure_message("Item entry lacks decor").contains("decor")


func test_ac13_the_item_entry_says_there_is_no_category_called_decoration() -> void:
	assert_str(_entry("item")).contains("no category called Decoration")


func test_ac13_the_category_entry_names_the_four_categories() -> void:
	var entry: String = _entry("category")
	for word: String in ["Rocks", "Wood", "Ornaments", "Plants"]:
		assert_str(entry).override_failure_message("Category entry lacks %s" % word).contains(word)


func test_ac13_the_existing_entries_are_still_there() -> void:
	assert_str(_entry("substrate")).is_not_empty()
	assert_str(_entry("swatch")).is_not_empty()
