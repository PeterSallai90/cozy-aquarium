extends GdUnitTestSuite
## #36 Mode 2 untouched (owner: developer): the add and remove commands and the fish panel code
## never read or write a Mode 2 catalog field (BA decision "Mode 2 untouched"). A source scan of
## game/model/add_fish_command.gd, remove_fish_command.gd and game/ui/fish/*.gd for the field names.
## Comments are not scanned. The files must exist: a missing file fails the test instead of
## passing an empty scan.

const FIELDS: PackedStringArray = [
	"temp_min_c",
	"temp_max_c",
	"ph_min",
	"ph_max",
	"min_group_size",
	"min_tank_litres",
	"bioload",
	"temperament",
	"diet",
	"light_preference",
	"needs_hiding_places",
	"incompatible_with",
]
const MODEL_FILES: PackedStringArray = [
	"res://model/add_fish_command.gd", "res://model/remove_fish_command.gd"
]
const UI_DIR := "res://ui/fish"
const REQUIRED_UI: PackedStringArray = [
	"res://ui/fish/fish_panel.gd",
	"res://ui/fish/fish_info_card.gd",
	"res://ui/fish/fish_name_text.gd"
]


func _words(path: String) -> PackedStringArray:
	var code: PackedStringArray = PackedStringArray()
	for line: String in FileAccess.get_file_as_string(path).split("\n"):
		code.append(line.get_slice("#", 0))
	var text: String = " ".join(code)
	var found: PackedStringArray = PackedStringArray()
	var pattern: RegEx = RegEx.create_from_string("[A-Za-z_][A-Za-z0-9_]*")
	for hit: RegExMatch in pattern.search_all(text):
		found.append(hit.get_string())
	return found


func _scan(path: String) -> PackedStringArray:
	var hits: PackedStringArray = PackedStringArray()
	var words: PackedStringArray = _words(path)
	for field: String in FIELDS:
		if words.has(field):
			hits.append("%s uses %s" % [path, field])
	return hits


func test_36_the_files_to_scan_exist() -> void:
	for path: String in MODEL_FILES + REQUIRED_UI:
		(
			assert_bool(FileAccess.file_exists(path))
			. override_failure_message("%s is missing" % path)
			. is_true()
		)


func test_36_the_commands_use_no_mode_2_field() -> void:
	var hits: PackedStringArray = PackedStringArray()
	for path: String in MODEL_FILES:
		if FileAccess.file_exists(path):
			hits.append_array(_scan(path))
	assert_array(Array(hits)).is_empty()


func test_36_the_fish_panel_code_uses_no_mode_2_field() -> void:
	var hits: PackedStringArray = PackedStringArray()
	for file: String in DirAccess.get_files_at(UI_DIR):
		if file.ends_with(".gd"):
			hits.append_array(_scan(UI_DIR.path_join(file)))
	assert_array(Array(hits)).is_empty()
