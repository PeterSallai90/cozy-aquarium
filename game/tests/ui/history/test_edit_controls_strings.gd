extends GdUnitTestSuite
## #32 AC 24 (strings part; owner: developer): the eight new keys exist in messages.pot, en.po and
## hu.po with non-empty text; the three tooltips carry exactly one %s for the live key label and
## the other texts none; the Undo, Redo, Delete and Original colour buttons and the Colour label
## show the text of the active language and re-translate at once on language_changed (the named
## test below); the tooltips read the first event of their action from the live input map, so a
## remapped key shows up (#81); Hungarian differs from English for every text. The dot tooltips are
## hex codes and are not translated (no key).
## Test decisions: the expected texts are read from the .po files (the owner may reword them on the
## PR without touching this test); a tooltip is checked with the label the helper computes from the
## live input map (the formula of the plan: logical label when keycode is set, else physical).

const Edit := preload("res://tests/helpers/edit_api.gd")
const Ui := preload("res://tests/helpers/tank_ui_rig.gd")

const MAIN_SCENE := "res://scenes/main.tscn"
const WINDOW := Vector2i(1152, 648)
const PO_DIR := "res://localization"
const KEYS: Array[String] = [
	"ui.history.undo",
	"ui.history.redo",
	"ui.history.undo.tooltip",
	"ui.history.redo.tooltip",
	"ui.item.delete",
	"ui.item.delete.tooltip",
	"ui.item.colour",
	"ui.item.colour_original",
]
const WITH_LABEL: Array[String] = [
	"ui.history.undo.tooltip",
	"ui.history.redo.tooltip",
	"ui.item.delete.tooltip",
]

var _saved_locale: String = ""
var _language_state: Dictionary = {}
var _saved_window_size: Vector2i = Vector2i.ZERO
var _main: Node = null


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()
	_language_state = Ui.begin_language_isolation("edit_strings")
	_saved_window_size = Vector2i.ZERO


func after_test() -> void:
	if _saved_window_size != Vector2i.ZERO:
		get_tree().root.size = _saved_window_size
	Ui.end_language_isolation(_language_state, _saved_locale)


func _po_entry(path: String, key: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	var start: int = text.find('msgid "%s"\n' % key)
	if start < 0:
		return ""
	var line_start: int = text.find('msgstr "', start)
	if line_start < 0:
		return ""
	var line_end: int = text.find("\n", line_start)
	return text.substr(line_start + 8, line_end - line_start - 9)


func _open_main() -> bool:
	_saved_window_size = get_tree().root.size
	get_tree().root.size = WINDOW
	var scene: PackedScene = load(MAIN_SCENE) as PackedScene
	_main = scene.instantiate()
	add_child(_main)
	auto_free(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	var found: bool = (
		_main.get_node_or_null("Hud/HistoryControls") != null
		and _main.get_node_or_null("Hud/ItemActions") != null
	)
	(
		assert_bool(found)
		. override_failure_message("Main needs Hud/HistoryControls and Hud/ItemActions")
		. is_true()
	)
	return found


func _button(node_name: String) -> Button:
	var found: Button = _main.get_node("Hud").find_child(node_name, true, false) as Button
	assert_object(found).override_failure_message("no button %s" % node_name).is_not_null()
	return found


func _label(node_name: String) -> Label:
	var found: Label = _main.get_node("Hud").find_child(node_name, true, false) as Label
	assert_object(found).override_failure_message("no label %s" % node_name).is_not_null()
	return found


func _shown(control: Control, text: String) -> String:
	return control.atr(text)


func _expected(language: String, key: String) -> String:
	return _po_entry("%s/%s.po" % [PO_DIR, language], key)


func _tooltip_expected(language: String, key: String, action: StringName) -> String:
	return _expected(language, key) % Edit.live_label(action)


func test_ac24_every_key_is_in_the_template_and_in_both_languages_with_text() -> void:
	var template: String = FileAccess.get_file_as_string("%s/messages.pot" % PO_DIR)
	for key: String in KEYS:
		assert_str(template).override_failure_message("%s not in messages.pot" % key).contains(
			'msgid "%s"' % key
		)
		for language: String in ["en", "hu"]:
			var text: String = _expected(language, key)
			(
				assert_str(text)
				. override_failure_message("%s: %s is empty" % [language, key])
				. is_not_empty()
			)
			var placeholders: int = text.count("%s")
			var wanted: int = 1 if WITH_LABEL.has(key) else 0
			(
				assert_int(placeholders)
				. override_failure_message(
					"%s: %s has %d %%s, expected %d" % [language, key, placeholders, wanted]
				)
				. is_equal(wanted)
			)
		(
			assert_str(_expected("hu", key))
			. override_failure_message("%s: the Hungarian text equals the English one" % key)
			. is_not_equal(_expected("en", key))
		)


func test_ac24_the_dot_tooltips_have_no_translation_key() -> void:
	var template: String = FileAccess.get_file_as_string("%s/messages.pot" % PO_DIR)
	assert_bool(template.contains("ui.item.swatch")).is_false()
	assert_bool(template.contains("ui.item.colour_name")).is_false()


func test_ac24_labels_and_tooltips_retranslate_on_language_changed() -> void:
	if not await _open_main():
		return
	for language: String in ["en", "hu", "en"]:
		Localization.set_language(language)
		await get_tree().process_frame
		assert_str(_shown(_button("UndoButton"), _button("UndoButton").text)).is_equal(
			_expected(language, "ui.history.undo")
		)
		assert_str(_shown(_button("RedoButton"), _button("RedoButton").text)).is_equal(
			_expected(language, "ui.history.redo")
		)
		assert_str(_shown(_button("DeleteButton"), _button("DeleteButton").text)).is_equal(
			_expected(language, "ui.item.delete")
		)
		assert_str(_shown(_button("OriginalButton"), _button("OriginalButton").text)).is_equal(
			_expected(language, "ui.item.colour_original")
		)
		assert_str(_shown(_label("ColourLabel"), _label("ColourLabel").text)).is_equal(
			_expected(language, "ui.item.colour")
		)
		assert_str(_shown(_button("UndoButton"), _button("UndoButton").tooltip_text)).is_equal(
			_tooltip_expected(language, "ui.history.undo.tooltip", &"history_undo")
		)
		assert_str(_shown(_button("RedoButton"), _button("RedoButton").tooltip_text)).is_equal(
			_tooltip_expected(language, "ui.history.redo.tooltip", &"history_redo")
		)
		assert_str(_shown(_button("DeleteButton"), _button("DeleteButton").tooltip_text)).is_equal(
			_tooltip_expected(language, "ui.item.delete.tooltip", &"item_delete")
		)


func test_ac24_the_tooltips_show_the_first_event_of_the_live_input_map() -> void:
	if not await _open_main():
		return
	Localization.set_language("en")
	await get_tree().process_frame
	var original_undo: Array[InputEvent] = InputMap.action_get_events("history_undo")
	var original_delete: Array[InputEvent] = InputMap.action_get_events("item_delete")
	InputMap.action_erase_events("history_undo")
	var remapped: InputEventKey = InputEventKey.new()
	remapped.keycode = KEY_U
	remapped.ctrl_pressed = true
	InputMap.action_add_event("history_undo", remapped)
	InputMap.action_erase_events("item_delete")
	var backspace: InputEventKey = InputEventKey.new()
	backspace.physical_keycode = KEY_BACKSPACE
	InputMap.action_add_event("item_delete", backspace)
	Localization.set_language("hu")
	await get_tree().process_frame
	var undo_tip: String = _button("UndoButton").tooltip_text
	var delete_tip: String = _button("DeleteButton").tooltip_text
	InputMap.action_erase_events("history_undo")
	for event: InputEvent in original_undo:
		InputMap.action_add_event("history_undo", event)
	InputMap.action_erase_events("item_delete")
	for event: InputEvent in original_delete:
		InputMap.action_add_event("item_delete", event)
	assert_str(undo_tip).contains(remapped.as_text_keycode())
	assert_str(delete_tip).contains(backspace.as_text_physical_keycode())


func test_ac24_the_default_tooltip_labels_come_from_the_input_map_events() -> void:
	if not await _open_main():
		return
	Localization.set_language("en")
	await get_tree().process_frame
	assert_str(_button("UndoButton").tooltip_text).contains(Edit.live_label(&"history_undo"))
	assert_str(_button("RedoButton").tooltip_text).contains(Edit.live_label(&"history_redo"))
	assert_str(_button("DeleteButton").tooltip_text).contains(Edit.live_label(&"item_delete"))
	assert_str(Edit.primary_label(&"history_undo")).is_equal(Edit.live_label(&"history_undo"))
	assert_str(Edit.primary_label(&"history_redo")).is_equal(Edit.live_label(&"history_redo"))
	assert_str(Edit.primary_label(&"item_delete")).is_equal(Edit.live_label(&"item_delete"))
	assert_str(Edit.primary_label(&"no_such_action")).is_equal("?")
