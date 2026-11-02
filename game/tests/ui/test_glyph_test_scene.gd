extends GdUnitTestSuite
## The developer glyph scene: one row per sample, built from data, no literal text, no keys.

const FontRig := preload("res://tests/helpers/font_rig.gd")
const SourceScan := preload("res://tests/helpers/source_scan.gd")

const SCENE_SCRIPT := "res://ui/dev/glyph_test.gd"
const FORBIDDEN_TEXT_PROPERTY := "(?m)^(text|placeholder_text|tooltip_text|title) = "
const TR_CALL := "\\btr(_n)?\\s*\\("


func _scene() -> Control:
	var packed: PackedScene = FontRig.load_or_null(FontRig.SCENE_PATH) as PackedScene
	(
		assert_object(packed)
		. override_failure_message(FontRig.missing(FontRig.SCENE_PATH))
		. is_not_null()
	)
	if packed == null:
		return null
	var scene: Control = packed.instantiate() as Control
	add_child(auto_free(scene))
	return scene


func test_the_scene_loads_headless_with_one_row_per_sample() -> void:
	var rows: Array = FontRig.rows()
	(
		assert_array(rows)
		. override_failure_message("sample table missing or empty: " + FontRig.SAMPLES_PATH)
		. is_not_empty()
	)
	var scene: Control = _scene()
	if scene == null:
		return
	await get_tree().process_frame
	var container: Node = scene.find_child("Rows", true, false)
	assert_object(container).override_failure_message("scene has no Rows node").is_not_null()
	if container == null:
		return
	assert_int(container.get_child_count()).is_equal(rows.size())
	for row: Dictionary in rows:
		var node: Node = scene.find_child("Row_" + str(row["id"]), true, false)
		(
			assert_object(node)
			. override_failure_message("scene has no Row_%s" % row["id"])
			. is_not_null()
		)
		if node != null:
			(
				assert_bool(node.get_meta("informational", null) == row["informational"])
				. override_failure_message(
					"Row_%s meta informational differs from the table" % row["id"]
				)
				. is_true()
			)


func test_each_row_shows_the_script_the_text_and_the_source() -> void:
	var scene: Control = _scene()
	if scene == null:
		return
	await get_tree().process_frame
	for row: Dictionary in FontRig.rows():
		var node: Node = scene.find_child("Row_" + str(row["id"]), true, false)
		(
			assert_object(node)
			. override_failure_message("scene has no Row_%s" % row["id"])
			. is_not_null()
		)
		if node == null or node.get_child_count() != 3:
			assert_int(node.get_child_count() if node != null else 0).is_equal(3)
			continue
		assert_str((node.get_child(0) as Label).text).is_equal(row["script"])
		assert_str((node.get_child(1) as Label).text).is_equal(row["text"])
		var source: String = (node.get_child(2) as Label).text
		assert_str(source).is_not_empty()
		(
			assert_bool(source.begins_with("informational:"))
			. override_failure_message("Row_%s source label: %s" % [row["id"], source])
			. is_equal(row["informational"])
		)


func test_the_emoji_row_is_present_and_informational() -> void:
	var scene: Control = _scene()
	if scene == null:
		return
	await get_tree().process_frame
	var node: Node = scene.find_child("Row_emoji", true, false)
	assert_object(node).override_failure_message("scene has no Row_emoji").is_not_null()
	if node != null:
		assert_bool(node.get_meta("informational", false) as bool).is_true()


func test_the_scene_has_a_line_edit_that_reports_the_source_of_typed_text() -> void:
	var scene: Control = _scene()
	if scene == null:
		return
	await get_tree().process_frame
	var input: LineEdit = scene.find_child("Input", true, false) as LineEdit
	assert_object(input).override_failure_message("scene has no Input LineEdit").is_not_null()
	var label: Label = scene.find_child("InputSource", true, false) as Label
	assert_object(label).override_failure_message("scene has no InputSource Label").is_not_null()
	if input == null or label == null or FontRig.layers() == null:
		return
	var chain: Font = scene.get_theme_font("font")
	input.text = "ő"
	input.text_changed.emit(input.text)
	assert_str(label.text).is_equal(FontRig.summarize(FontRig.glyph_sources(chain, "ő")))
	input.text = "ő鱼"
	input.text_changed.emit(input.text)
	assert_str(label.text).is_equal(FontRig.summarize(FontRig.glyph_sources(chain, "ő鱼")))


func test_the_scene_root_never_looks_samples_up_as_translation_keys() -> void:
	var scene: Control = _scene()
	if scene == null:
		return
	assert_int(scene.auto_translate_mode).is_equal(Node.AUTO_TRANSLATE_MODE_DISABLED)


func test_the_scene_file_has_no_literal_text_properties() -> void:
	var source: String = SourceScan.read(FontRig.SCENE_PATH)
	assert_str(source).override_failure_message(FontRig.missing(FontRig.SCENE_PATH)).is_not_empty()
	var pattern: Array[RegEx] = SourceScan.compile(PackedStringArray([FORBIDDEN_TEXT_PROPERTY]))
	assert_array(Array(SourceScan.find_matches(source, pattern))).is_empty()


func test_the_new_scripts_call_no_translation_function() -> void:
	var pattern: Array[RegEx] = SourceScan.compile(PackedStringArray([TR_CALL]))
	for path: String in [FontRig.LAYERS_PATH, FontRig.SAMPLES_PATH, SCENE_SCRIPT]:
		var source: String = SourceScan.read(path)
		assert_str(source).override_failure_message(FontRig.missing(path)).is_not_empty()
		var hits: PackedStringArray = SourceScan.find_matches(
			SourceScan.strip_comments(source), pattern
		)
		assert_array(Array(hits)).override_failure_message(path + " calls tr()").is_empty()
