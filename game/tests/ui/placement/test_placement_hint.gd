extends GdUnitTestSuite
## #31 AC 32 and 38 (owner: developer): the hint line Hud/PlacementHint of the Main scene. One
## Label, shown while a pick or a selection exists, hidden otherwise and while the world is blocked
## (modal dialog or photo mode), ignoring the mouse, at the bottom centre of the window. The text
## is tr("placement.hint.place") or tr("placement.hint.selected") with the live labels of the two
## rotate actions (left key first, joined with a slash); it re-translates at once on
## language_changed; in Hungarian at 1152 x 648 its rectangle lies inside the window and meets no
## visible HUD button or panel, with the Items panel open and closed.
## Test decisions: the expected key labels are computed here from the live input map events (the
## architect's PlacementHint.key_labels() must agree); the texts are the default ones of the issue
## body; HUD controls for the overlap check are the visible BaseButtons, panels and every Control
## that stops the mouse; the shown text is read with atr() so either translation style passes.

const Api := preload("res://tests/helpers/placement_api.gd")
const Ui := preload("res://tests/helpers/tank_ui_rig.gd")
const Browser := preload("res://tests/helpers/item_browser_rig.gd")

const MAIN_SCENE := "res://scenes/main.tscn"
const WINDOW := Vector2i(1152, 648)
const EN_PLACE := "Click to place, %s to turn (Shift: fine), Esc to step back."
const EN_SELECTED := "Drag to move, %s to turn (Shift: fine), Esc to step back."
const HU_PLACE := "Kattints a lerakáshoz, %s: forgatás (Shift: finom), Esc: vissza."
const HU_SELECTED := "Húzással mozgathatod, %s: forgatás (Shift: finom), Esc: vissza."
const KEYS_PATH := "res://localization"

var _saved_locale: String = ""
var _language_state: Dictionary = {}
var _saved_window_size: Vector2i = Vector2i.ZERO
var _main: Node = null
var _controls: Control = null
var _hint: Label = null


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()
	_language_state = Ui.begin_language_isolation("placement_hint")
	_saved_window_size = Vector2i.ZERO


func after_test() -> void:
	if _saved_window_size != Vector2i.ZERO:
		get_tree().root.size = _saved_window_size
	Ui.end_language_isolation(_language_state, _saved_locale)


func _open_main() -> bool:
	_saved_window_size = get_tree().root.size
	get_tree().root.size = WINDOW
	var scene: PackedScene = load(MAIN_SCENE) as PackedScene
	_main = scene.instantiate()
	add_child(_main)
	auto_free(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	_controls = _main.get_node("Hud/TankControls") as Control
	_hint = _main.get_node_or_null("Hud/PlacementHint") as Label
	(
		assert_bool(_hint != null)
		. override_failure_message("Main has no Hud/PlacementHint (Label)")
		. is_true()
	)
	return _hint != null


func _labels() -> String:
	var left: InputEventKey = InputMap.action_get_events("place_rotate_left")[0] as InputEventKey
	var right: InputEventKey = InputMap.action_get_events("place_rotate_right")[0] as InputEventKey
	return "%s / %s" % [left.as_text_physical_keycode(), right.as_text_physical_keycode()]


func _shown() -> String:
	return _hint.atr(_hint.text)


func _frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _pick() -> void:
	EventBus.item_picked.emit(&"river_stone")
	await _frames()


func _select() -> void:
	EventBus.emit_signal("item_selected", "a0000001")
	await _frames()


func test_ac32_the_hint_is_hidden_without_a_pick_and_without_a_selection() -> void:
	if not await _open_main():
		return
	assert_bool(_hint.is_visible_in_tree()).is_false()


func test_ac38_the_hint_ignores_the_mouse() -> void:
	if not await _open_main():
		return
	assert_int(_hint.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


func test_ac32_a_pick_shows_the_place_text_with_the_live_key_labels() -> void:
	if not await _open_main():
		return
	await _pick()
	assert_bool(_hint.is_visible_in_tree()).is_true()
	assert_str(_shown()).is_equal(EN_PLACE % _labels())


func test_ac38_the_shown_text_contains_the_labels_of_the_two_rotate_actions() -> void:
	if not await _open_main():
		return
	await _pick()
	assert_str(Api.hint_key_labels()).is_equal(_labels())
	var left: InputEventKey = InputMap.action_get_events("place_rotate_left")[0] as InputEventKey
	var right: InputEventKey = InputMap.action_get_events("place_rotate_right")[0] as InputEventKey
	assert_str(_shown()).contains(left.as_text_physical_keycode())
	assert_str(_shown()).contains(right.as_text_physical_keycode())
	assert_int(_shown().find(left.as_text_physical_keycode())).is_less(
		_shown().find(right.as_text_physical_keycode())
	)


func test_ac38_a_remapped_key_changes_the_label() -> void:
	if not await _open_main():
		return
	var original: Array[InputEvent] = InputMap.action_get_events("place_rotate_left")
	InputMap.action_erase_events("place_rotate_left")
	var remapped: InputEventKey = InputEventKey.new()
	remapped.physical_keycode = KEY_M
	InputMap.action_add_event("place_rotate_left", remapped)
	await _pick()
	var shown: String = _shown()
	var key_text: String = Api.hint_key_labels()
	InputMap.action_erase_events("place_rotate_left")
	for event: InputEvent in original:
		InputMap.action_add_event("place_rotate_left", event)
	assert_str(key_text).begins_with(remapped.as_text_physical_keycode())
	assert_str(shown).contains(remapped.as_text_physical_keycode())


func test_ac32_a_selection_shows_the_selected_text() -> void:
	if not await _open_main():
		return
	await _select()
	assert_bool(_hint.is_visible_in_tree()).is_true()
	assert_str(_shown()).is_equal(EN_SELECTED % _labels())


func test_ac32_clearing_the_pick_or_the_selection_hides_the_hint() -> void:
	if not await _open_main():
		return
	await _pick()
	EventBus.item_pick_cleared.emit()
	await _frames()
	assert_bool(_hint.is_visible_in_tree()).is_false()
	await _select()
	EventBus.emit_signal("item_selection_cleared")
	await _frames()
	assert_bool(_hint.is_visible_in_tree()).is_false()


func test_ac32_the_hint_retranslates_at_once_on_a_language_change() -> void:
	if not await _open_main():
		return
	await _pick()
	assert_str(_shown()).is_equal(EN_PLACE % _labels())
	Localization.set_language("hu")
	assert_str(_shown()).is_equal(HU_PLACE % _labels())
	Localization.set_language("en")
	assert_str(_shown()).is_equal(EN_PLACE % _labels())
	await _select()
	Localization.set_language("hu")
	assert_str(_shown()).is_equal(HU_SELECTED % _labels())


func test_ac37_the_hint_is_hidden_while_the_world_is_blocked() -> void:
	if not await _open_main():
		return
	await _pick()
	var blocker: Control = Control.new()
	blocker.add_to_group(&"world_input_blockers")
	blocker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_main.get_node("Hud").add_child(blocker)
	await _frames()
	assert_bool(_hint.is_visible_in_tree()).is_false()
	blocker.visible = false
	await _frames()
	assert_bool(_hint.is_visible_in_tree()).is_true()
	blocker.queue_free()


func _hud_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for node: Node in _main.get_node("Hud").find_children("*", "Control", true, false):
		var control: Control = node as Control
		if control == _hint or not control.is_visible_in_tree():
			continue
		var solid: bool = (
			control is BaseButton
			or control is Panel
			or control is PanelContainer
			or control.mouse_filter == Control.MOUSE_FILTER_STOP
		)
		if solid and control.size.x > 0.0 and control.size.y > 0.0:
			rects.append(control.get_global_rect())
	return rects


func _assert_layout() -> void:
	var window: Rect2 = Rect2(Vector2.ZERO, Vector2(WINDOW))
	var rect: Rect2 = _hint.get_global_rect()
	(
		assert_bool(window.encloses(rect))
		. override_failure_message("the hint %s leaves the window" % rect)
		. is_true()
	)
	assert_float(rect.get_center().x).is_equal_approx(WINDOW.x / 2.0, WINDOW.x * 0.1)
	assert_float(rect.position.y).is_greater(WINDOW.y * 0.7)
	for other: Rect2 in _hud_rects():
		(
			assert_bool(rect.intersects(other))
			. override_failure_message("the hint %s meets the HUD rectangle %s" % [rect, other])
			. is_false()
		)


func test_ac38_in_hungarian_the_hint_fits_the_window_and_meets_no_hud_control() -> void:
	if not await _open_main():
		return
	Localization.set_language("hu")
	await _pick()
	assert_str(_shown()).is_equal(HU_PLACE % _labels())
	_assert_layout()
	await Browser.press_open(self, _controls)
	assert_bool(Browser.is_open(_controls)).is_true()
	await _frames()
	_assert_layout()
	_controls.call("close_panels")
	await _frames()
	_assert_layout()
	EventBus.item_pick_cleared.emit()
	await _select()
	assert_str(_shown()).is_equal(HU_SELECTED % _labels())
	_assert_layout()


func _po_entry(path: String, key: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	var start: int = text.find('msgid "%s"' % key)
	if start < 0:
		return ""
	var line_start: int = text.find('msgstr "', start)
	if line_start < 0:
		return ""
	var line_end: int = text.find("\n", line_start)
	return text.substr(line_start + 8, line_end - line_start - 9)


func test_ac32_both_languages_have_both_texts_with_the_key_placeholder() -> void:
	for path: String in ["%s/en.po" % KEYS_PATH, "%s/hu.po" % KEYS_PATH]:
		for key: String in ["placement.hint.place", "placement.hint.selected"]:
			var text: String = _po_entry(path, key)
			(
				assert_str(text)
				. override_failure_message("%s: %s is empty" % [path, key])
				. is_not_empty()
			)
			assert_str(text).override_failure_message("%s: %s has no %%s" % [path, key]).contains(
				"%s"
			)
	var template: String = FileAccess.get_file_as_string("%s/messages.pot" % KEYS_PATH)
	assert_str(template).contains('msgid "placement.hint.place"')
	assert_str(template).contains('msgid "placement.hint.selected"')
