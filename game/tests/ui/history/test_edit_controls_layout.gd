extends GdUnitTestSuite
## #32 AC 24 (layout part; owner: developer): in Hungarian at 1152 x 648 the rectangles of Undo,
## Redo, Delete, the Colour row (worst case 8 dots), the hint line, the buttons of TankControls and
## the open Items panel all lie inside the window and none overlaps another, with the panel closed
## and open (as #31 AC 38). The 8-dot worst case is made by giving the shipped amphora definition 8
## swatches in memory for the test (the original list is put back in after_test); the selection
## reaches the HUD through EventBus.item_selected like placement does.
## Test decisions: the checks are on rectangles in global coordinates; the amphora is the colourable
## selection; the pairs that must not overlap are every pair of the listed controls.

const Rig := preload("res://tests/helpers/placement_rig.gd")
const Ui := preload("res://tests/helpers/tank_ui_rig.gd")
const Browser := preload("res://tests/helpers/item_browser_rig.gd")

const MAIN_SCENE := "res://scenes/main.tscn"
const WINDOW := Vector2i(1152, 648)
const VASE := "a0000002"
const EIGHT: Array[Color] = [
	Color8(0xB5, 0x4A, 0x33),
	Color8(0xD9, 0xA4, 0x41),
	Color8(0xF1, 0xE6, 0xC8),
	Color8(0x4F, 0x6D, 0x8C),
	Color8(0x3E, 0x9E, 0x93),
	Color8(0x2B, 0x2A, 0x33),
	Color8(0x7A, 0x5C, 0x8E),
	Color8(0x8C, 0x9A, 0x4A),
]

var _saved_locale: String = ""
var _language_state: Dictionary = {}
var _saved_window_size: Vector2i = Vector2i.ZERO
var _definition: ItemDefinition = null
var _saved_swatches: Array[Color] = []
var _main: Node = null
var _controls: Control = null


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()
	_language_state = Ui.begin_language_isolation("edit_layout")
	_saved_window_size = Vector2i.ZERO
	_definition = null


func after_test() -> void:
	if _definition != null:
		var restored: Array[Color] = _saved_swatches.duplicate()
		_definition.set("colour_swatches", restored)
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
	var hud_ok: bool = (
		_main.get_node_or_null("Hud/HistoryControls") != null
		and _main.get_node_or_null("Hud/ItemActions") != null
	)
	(
		assert_bool(hud_ok)
		. override_failure_message("Main needs Hud/HistoryControls and Hud/ItemActions")
		. is_true()
	)
	if not hud_ok:
		return false
	var model: AquariumModel = _main.call("get_model") as AquariumModel
	Rig.add_item(model, VASE, Rig.AMPHORA, 0.0, 0.0)
	var source: ItemCatalogSource = _main.call("get_item_source") as ItemCatalogSource
	_definition = source.get_catalog().get_definition(Rig.AMPHORA)
	var raw: Variant = _definition.get("colour_swatches")
	if raw is Array:
		for colour: Color in raw:
			_saved_swatches.append(colour)
	var many: Array[Color] = EIGHT.duplicate()
	_definition.set("colour_swatches", many)
	return true


func _frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _select() -> void:
	EventBus.emit_signal("item_selected", VASE)
	await _frames()


func _named(path: String) -> Control:
	var node: Control = _main.get_node("Hud").find_child(path, true, false) as Control
	assert_object(node).override_failure_message("no control %s" % path).is_not_null()
	return node


func _rects() -> Dictionary:
	var rects: Dictionary = {
		"Undo": _named("UndoButton"),
		"Redo": _named("RedoButton"),
		"Delete": _named("DeleteButton"),
		"ColourRow": _named("ColourRow"),
		"Hint": _named("PlacementHint"),
	}
	for button_name: String in [
		"ChangeTankButton", "TankDetailsButton", "SubstrateButton", "ItemsButton"
	]:
		rects[button_name] = _named(button_name)
	if Browser.is_open(_controls):
		rects["ItemBrowser"] = _named("ItemBrowser")
	return rects


func _assert_layout(label: String) -> void:
	var window: Rect2 = Rect2(Vector2.ZERO, Vector2(WINDOW))
	var controls: Dictionary = _rects()
	var names: Array = controls.keys()
	for index: int in names.size():
		var first: Control = controls[names[index]]
		(
			assert_bool(first.is_visible_in_tree())
			. override_failure_message("%s: %s is not visible" % [label, names[index]])
			. is_true()
		)
		var rect: Rect2 = first.get_global_rect()
		(
			assert_bool(window.encloses(rect))
			. override_failure_message("%s: %s %s leaves the window" % [label, names[index], rect])
			. is_true()
		)
		for other_index: int in range(index + 1, names.size()):
			var second: Control = controls[names[other_index]]
			var other: Rect2 = second.get_global_rect()
			(
				assert_bool(rect.intersects(other))
				. override_failure_message(
					"%s: %s %s meets %s %s" % [label, names[index], rect, names[other_index], other]
				)
				. is_false()
			)
	var dots: Array[Rect2] = []
	var swatch_box: Node = _named("ColourRow").find_child("Swatches", true, false)
	assert_object(swatch_box).override_failure_message("no Swatches row in ColourRow").is_not_null()
	if swatch_box == null:
		return
	for child: Node in swatch_box.get_children():
		if child is Button:
			dots.append((child as Button).get_global_rect())
	assert_int(dots.size()).override_failure_message("8 dots expected").is_equal(8)
	for index: int in dots.size():
		assert_bool(_named("ColourRow").get_global_rect().encloses(dots[index])).is_true()
		for other_index: int in range(index + 1, dots.size()):
			assert_bool(dots[index].intersects(dots[other_index])).is_false()


func test_ac24_in_hungarian_the_edit_controls_fit_the_window_and_meet_no_other_control() -> void:
	if not await _open_main():
		return
	Localization.set_language("hu")
	await _select()
	_assert_layout("panel closed")
	await Browser.press_open(self, _controls)
	assert_bool(Browser.is_open(_controls)).is_true()
	await _frames()
	_assert_layout("panel open")
	_controls.call("close_panels")
	await _frames()
	_assert_layout("panel closed again")


func test_ac24_in_english_the_edit_controls_fit_too() -> void:
	if not await _open_main():
		return
	Localization.set_language("en")
	await _select()
	_assert_layout("english")


func test_ac24_undo_and_redo_sit_inside_the_window_without_a_selection() -> void:
	if not await _open_main():
		return
	Localization.set_language("hu")
	await _frames()
	var window: Rect2 = Rect2(Vector2.ZERO, Vector2(WINDOW))
	var undo: Rect2 = _named("UndoButton").get_global_rect()
	var redo: Rect2 = _named("RedoButton").get_global_rect()
	assert_bool(window.encloses(undo)).is_true()
	assert_bool(window.encloses(redo)).is_true()
	assert_bool(undo.intersects(redo)).is_false()
	for button_name: String in [
		"ChangeTankButton", "TankDetailsButton", "SubstrateButton", "ItemsButton"
	]:
		assert_bool(undo.intersects(_named(button_name).get_global_rect())).is_false()
		assert_bool(redo.intersects(_named(button_name).get_global_rect())).is_false()
