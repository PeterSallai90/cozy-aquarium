# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #32 AC 1, 2, 3, 5, 8, 9, 15, 17, 18 and 22 (owner: developer) inside the real Main scene, so the
## routing is the real one: Hud/HistoryControls and Hud/ItemActions come after Hud/TankControls and
## Hud/PlacementHint, RoomCorner (with Placement) comes before Hud (ADR 0008 Amendment 2 rule 17);
## main.gd hands them the session history, model and item source (both buttons start disabled).
## The real Delete and Undo buttons and the real colour dots work end to end; a delete empties the
## hint line and the controls, an undone delete returns the item unselected; the Delete key works
## with the Items panel open and no pick; Ctrl+Z and Ctrl+Y undo and redo a tank swap through the
## real HistoryControls: the tank comes back with the items at the same positions, rotations,
## scales and colours, and the selection is cleared by tank_displayed.
## Test decisions: the ground spots of the items are found by scanning for points that are not
## over a HUD control; the tank swap is a real ChangeTankCommand on Main's history.

const Rig := preload("res://tests/helpers/placement_rig.gd")
const Session := preload("res://tests/helpers/placement_session.gd")
const Edit := preload("res://tests/helpers/edit_api.gd")
const Ui := preload("res://tests/helpers/tank_ui_rig.gd")
const Browser := preload("res://tests/helpers/item_browser_rig.gd")
const ModelState := preload("res://tests/helpers/model_state.gd")

const MAIN_SCENE := "res://scenes/main.tscn"
const STONE_UID := "a0000001"
const VASE := "a0000002"
const TEAL := Color8(0x2A, 0x7F, 0x9E)

var _saved_locale: String = ""
var _language_state: Dictionary = {}
var _saved_window_size: Vector2i = Vector2i.ZERO
var _main: Node = null
var _controls: Control = null
var _s: Session = null


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()
	_language_state = Ui.begin_language_isolation("main_history")
	_saved_window_size = Vector2i.ZERO


func after_test() -> void:
	Rig.close(_s)
	if _saved_window_size != Vector2i.ZERO:
		get_tree().root.size = _saved_window_size
	Ui.end_language_isolation(_language_state, _saved_locale)


func _open_main(with_items: bool = true) -> bool:
	_saved_window_size = get_tree().root.size
	get_tree().root.size = Rig.WINDOW
	var scene: PackedScene = load(MAIN_SCENE) as PackedScene
	_main = scene.instantiate()
	add_child(_main)
	auto_free(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	_controls = _main.get_node("Hud/TankControls") as Control
	_s = Rig.attach(_main)
	var found: bool = _s.placement != null and _s.view != null
	(
		assert_bool(found)
		. override_failure_message("RoomCorner has no Placement child with PlacedItems")
		. is_true()
	)
	var hud_ok: bool = (
		_main.get_node_or_null("Hud/HistoryControls") != null
		and _main.get_node_or_null("Hud/ItemActions") != null
	)
	(
		assert_bool(hud_ok)
		. override_failure_message("Main needs Hud/HistoryControls and Hud/ItemActions")
		. is_true()
	)
	if not (found and hud_ok):
		return false
	if with_items:
		var spots: Array[Vector2] = _free_ground_points()
		Rig.add_item(_s.model, STONE_UID, Rig.STONE, spots[0].x, spots[0].y, 10.0)
		Rig.add_item(_s.model, VASE, Rig.AMPHORA, spots[1].x, spots[1].y, 37.5)
		await _s.frame()
		await _s.frame()
	return true


## Two ground points (x, z) of the tank whose screen spot is not over a HUD control.
func _free_ground_points() -> Array[Vector2]:
	var found: Array[Vector2] = []
	for z: float in [0.0, -0.08, 0.08]:
		for x: float in [-0.15, 0.15, -0.1, 0.1, 0.2, -0.2]:
			var at: Vector2 = _s.screen_of(x, z)
			if not WorldInput.is_over_stop_control(get_viewport(), at):
				found.append(Vector2(x, z))
	assert_int(found.size()).is_greater(1)
	return found.slice(0, 2) if found.size() > 1 else [Vector2(0.0, 0.0), Vector2(0.1, 0.0)]


func _part(path: String) -> Control:
	return _main.get_node_or_null(path) as Control


func _history() -> CommandHistory:
	return _s.history


func _select(uid: String) -> void:
	_s.click(_s.screen_of_item(uid))
	await _s.frame()
	assert_str(_s.selected_uid()).is_equal(uid)


func _click_control(control: Control) -> void:
	_s.click(control.get_global_rect().get_center())
	await _s.frame()
	await _s.frame()


func _ctrl_chord(keycode: Key, extra: int = 0) -> void:
	_s.key(keycode, true, KEY_MASK_CTRL | extra)
	_s.key(keycode, false, KEY_MASK_CTRL | extra)
	await _s.frame()
	await _s.frame()


func _dots() -> Array[Button]:
	var found: Array[Button] = []
	var box: Control = (_part("Hud/ItemActions") as Control).find_child("Swatches", true, false)
	for child: Node in box.get_children():
		if child is Button:
			found.append(child as Button)
	return found


func _tint_of(uid: String) -> Variant:
	var node: Node3D = _s.node_for(uid)
	for found: Node in node.find_children("*", "GeometryInstance3D", true, false):
		return (found as GeometryInstance3D).get_instance_shader_parameter("item_tint")
	return null


# --- structure (ADR 0008 Amendment 2 rule 17) ---


func test_rule17_the_room_with_placement_comes_before_the_hud() -> void:
	if not await _open_main(false):
		return
	(
		assert_bool(_main.get_node("RoomCorner").get_index() < _main.get_node("Hud").get_index())
		. is_true()
	)
	assert_object(_main.get_node("RoomCorner/Placement").get_parent()).is_same(
		_main.get_node("RoomCorner")
	)


func test_rule17_history_controls_and_item_actions_come_after_tank_controls_and_the_hint() -> void:
	if not await _open_main(false):
		return
	var hud: Node = _main.get_node("Hud")
	var tank_controls: int = hud.get_node("TankControls").get_index()
	var hint: int = hud.get_node("PlacementHint").get_index()
	var history: int = hud.get_node("HistoryControls").get_index()
	var actions: int = hud.get_node("ItemActions").get_index()
	assert_bool(history > tank_controls and history > hint).is_true()
	assert_bool(actions > tank_controls and actions > hint).is_true()
	assert_object(hud.get_node("HistoryControls").get_script()).is_not_null()
	assert_that(hud.get_node("HistoryControls").get_script().get_global_name()).is_equal(
		&"HistoryControls"
	)
	assert_that(hud.get_node("ItemActions").get_script().get_global_name()).is_equal(&"ItemActions")


# --- AC 15: both buttons start disabled ---


func test_ac15_at_the_start_both_buttons_are_disabled() -> void:
	if not await _open_main(false):
		return
	var undo: Button = _part("Hud/HistoryControls").find_child("UndoButton", true, false) as Button
	var redo: Button = _part("Hud/HistoryControls").find_child("RedoButton", true, false) as Button
	assert_bool(undo.disabled).is_true()
	assert_bool(redo.disabled).is_true()


func test_ac15_the_buttons_follow_the_session_history_and_a_clear_disables_them() -> void:
	if not await _open_main(false):
		return
	var undo: Button = _part("Hud/HistoryControls").find_child("UndoButton", true, false) as Button
	var redo: Button = _part("Hud/HistoryControls").find_child("RedoButton", true, false) as Button
	var spots: Array[Vector2] = _free_ground_points()
	# The stone already there stands 0.2 m from the spot to place on (the footprint rule, #33).
	var side: float = -1.0 if spots[0].x > 0.0 else 1.0
	Rig.add_item(_s.model, STONE_UID, Rig.STONE, spots[0].x + 0.2 * side, spots[0].y)
	assert_bool(undo.disabled).is_true()
	_s.pick(Rig.STONE)
	var at: Vector2 = _s.screen_of(spots[0].x, spots[0].y)
	_s.move(at)
	_s.click(at)
	await _s.frame()
	assert_bool(undo.disabled).is_false()
	assert_bool(redo.disabled).is_true()
	_history().clear()
	assert_bool(undo.disabled).is_true()
	assert_bool(redo.disabled).is_true()


# --- AC 1, 2, 3, 17: the real buttons ---


func test_ac01_the_delete_button_deletes_and_the_controls_and_the_hint_disappear() -> void:
	if not await _open_main():
		return
	var actions: Control = _part("Hud/ItemActions")
	var hint: Control = _part("Hud/PlacementHint")
	await _select(STONE_UID)
	var delete_button: Button = actions.find_child("DeleteButton", true, false) as Button
	assert_bool(delete_button.is_visible_in_tree()).is_true()
	assert_bool(hint.is_visible_in_tree()).is_true()
	await _click_control(delete_button)
	assert_bool(_s.model.has_uid(STONE_UID)).is_false()
	assert_int(_history().get_undo_count()).is_equal(1)
	assert_str(_s.selected_uid()).is_equal("")
	assert_int(_s.selection_timeline.count("cleared")).is_equal(1)
	assert_bool(delete_button.is_visible_in_tree()).is_false()
	assert_bool(hint.is_visible_in_tree()).is_false()
	(
		assert_bool((actions.find_child("ColourRow", true, false) as Control).is_visible_in_tree())
		. is_false()
	)
	assert_object(get_viewport().gui_get_focus_owner()).is_null()


func test_ac02_the_undo_button_brings_the_item_back_unselected_and_the_redo_button_deletes_it(
) -> void:
	if not await _open_main():
		return
	var before_state: Dictionary = ModelState.snapshot(_s.model)
	before_state.erase("modified")
	await _select(STONE_UID)
	_s.tap(KEY_DELETE)
	await _s.frame()
	var undo: Button = _part("Hud/HistoryControls").find_child("UndoButton", true, false) as Button
	var redo: Button = _part("Hud/HistoryControls").find_child("RedoButton", true, false) as Button
	assert_bool(undo.disabled).is_false()
	await _click_control(undo)
	var after_state: Dictionary = ModelState.snapshot(_s.model)
	after_state.erase("modified")
	assert_dict(after_state).is_equal(before_state)
	assert_int(_s.drawn_count()).is_equal(2)
	assert_str(_s.selected_uid()).is_equal("")
	assert_bool((_part("Hud/PlacementHint") as Control).is_visible_in_tree()).is_false()
	assert_bool(redo.disabled).is_false()
	await _click_control(redo)
	assert_bool(_s.model.has_uid(STONE_UID)).is_false()
	assert_int(_s.drawn_count()).is_equal(1)


func test_ac01_the_delete_key_deletes_the_selected_item_in_main() -> void:
	if not await _open_main():
		return
	await _select(VASE)
	_s.tap(KEY_DELETE)
	await _s.frame()
	assert_bool(_s.model.has_uid(VASE)).is_false()
	assert_str(_s.selected_uid()).is_equal("")


# --- AC 5: the Items panel is open with no pick ---


func test_ac05_the_delete_key_works_with_the_items_panel_open_and_no_pick() -> void:
	if not await _open_main():
		return
	await _select(STONE_UID)
	await Browser.press_open(self, _controls)
	assert_bool(Browser.is_open(_controls)).is_true()
	assert_str(_s.picked_id()).is_equal("")
	assert_str(_s.selected_uid()).is_equal(STONE_UID)
	_s.tap(KEY_DELETE)
	await _s.frame()
	assert_bool(_s.model.has_uid(STONE_UID)).is_false()
	assert_bool(Browser.is_open(_controls)).is_true()


func test_ac05_ctrl_z_works_with_the_items_panel_open_and_no_pick() -> void:
	if not await _open_main():
		return
	await _select(STONE_UID)
	_s.tap(KEY_DELETE)
	await _s.frame()
	await Browser.press_open(self, _controls)
	await _ctrl_chord(KEY_Z)
	assert_bool(_s.model.has_uid(STONE_UID)).is_true()


# --- AC 8, 9: the real colour dots ---


func test_ac08_a_dot_recolours_the_amphora_and_original_colour_undoes_it_in_one_step() -> void:
	if not await _open_main():
		return
	await _select(VASE)
	var dots: Array[Button] = _dots()
	assert_int(dots.size()).is_greater(1)
	var swatch: Color = (dots[1].get_theme_stylebox("normal") as StyleBoxFlat).bg_color
	await _click_control(dots[1])
	assert_bool(_s.model.get_item(VASE).has_colour).is_true()
	assert_int(_s.model.get_item(VASE).colour.to_rgba32()).is_equal(swatch.to_rgba32())
	assert_int(_history().get_undo_count()).is_equal(1)
	assert_str(_s.selected_uid()).is_equal(VASE)
	var tint: Variant = _tint_of(VASE)
	assert_bool(tint is Color).is_true()
	if tint is Color:
		(
			assert_bool((tint as Color).is_equal_approx(Color(swatch.r, swatch.g, swatch.b, 1.0)))
			. is_true()
		)
	var original: Button = (
		(_part("Hud/ItemActions") as Control).find_child("OriginalButton", true, false) as Button
	)
	await _click_control(original)
	assert_bool(_s.model.get_item(VASE).has_colour).is_false()
	assert_int(_history().get_undo_count()).is_equal(2)
	await _ctrl_chord(KEY_Z)
	assert_bool(_s.model.get_item(VASE).has_colour).is_true()
	assert_str(_s.selected_uid()).is_equal(VASE)
	await _ctrl_chord(KEY_Z)
	assert_bool(_s.model.get_item(VASE).has_colour).is_false()
	await _ctrl_chord(KEY_Y)
	assert_int(_s.model.get_item(VASE).colour.to_rgba32()).is_equal(swatch.to_rgba32())


func test_ac08_the_stone_has_no_colour_row_in_main() -> void:
	if not await _open_main():
		return
	await _select(STONE_UID)
	var row: Control = (_part("Hud/ItemActions") as Control).find_child("ColourRow", true, false)
	assert_bool(row.is_visible_in_tree()).is_false()


# --- AC 18 and 22: a tank swap through the shortcuts ---


func _swap_tank() -> void:
	var tanks: TankCatalog = TankCatalog.load_dir()
	var other: StringName = &"tank_large_1"
	if _s.model.get_tank_id() == other:
		other = &"tank_small_1"
	assert_bool(_history().execute(ChangeTankCommand.new(_s.model, tanks, other))).is_true()
	await _s.frame()
	await _s.frame()


func test_ac22_undo_and_redo_of_a_tank_swap_through_the_shortcuts() -> void:
	if not await _open_main():
		return
	var recoloured: PlacedItem = _s.model.get_item(VASE).copy()
	recoloured.has_colour = true
	recoloured.colour = TEAL
	assert_bool(_s.model.apply_replace_item(recoloured)).is_true()
	await _s.frame()
	var old_tank: StringName = _s.model.get_tank_id()
	var before_state: Dictionary = ModelState.snapshot_8bit(_s.model)
	before_state.erase("modified")
	await _swap_tank()
	assert_int(_s.model.get_item_count()).is_equal(0)
	assert_bool(_s.model.get_tank_id() != old_tank).is_true()
	await _ctrl_chord(KEY_Z)
	await _s.frame()
	assert_that(_s.model.get_tank_id()).is_equal(old_tank)
	var after_state: Dictionary = ModelState.snapshot_8bit(_s.model)
	after_state.erase("modified")
	assert_dict(after_state).is_equal(before_state)
	assert_int(_s.drawn_count()).is_equal(2)
	assert_str(_s.selected_uid()).is_equal("")
	var tint: Variant = _tint_of(VASE)
	assert_bool(tint is Color and (tint as Color).a == 1.0).is_true()
	await _ctrl_chord(KEY_Y)
	assert_int(_s.model.get_item_count()).is_equal(0)
	assert_bool(_s.model.get_tank_id() != old_tank).is_true()
	await _ctrl_chord(KEY_Z)
	assert_that(_s.model.get_tank_id()).is_equal(old_tank)
	assert_int(_s.model.get_item_count()).is_equal(2)


func test_ac22_the_selection_is_cleared_by_tank_displayed_on_undo_and_on_redo() -> void:
	if not await _open_main():
		return
	await _swap_tank()
	await _ctrl_chord(KEY_Z)
	await _s.frame()
	assert_int(_s.model.get_item_count()).is_equal(2)
	await _select(STONE_UID)
	_s.selection_timeline.clear()
	await _ctrl_chord(KEY_Y)
	await _s.frame()
	assert_str(_s.selected_uid()).is_equal("")
	assert_array(_s.selection_timeline).is_equal(["cleared"])
	assert_bool((_part("Hud/PlacementHint") as Control).is_visible_in_tree()).is_false()


func test_ac22_the_buttons_follow_a_tank_swap_in_the_history() -> void:
	if not await _open_main():
		return
	await _swap_tank()
	var undo: Button = _part("Hud/HistoryControls").find_child("UndoButton", true, false) as Button
	var redo: Button = _part("Hud/HistoryControls").find_child("RedoButton", true, false) as Button
	assert_bool(undo.disabled).is_false()
	await _click_control(undo)
	assert_bool(undo.disabled).is_true()
	assert_bool(redo.disabled).is_false()
	assert_int(_s.model.get_item_count()).is_equal(2)
	await _click_control(redo)
	assert_int(_s.model.get_item_count()).is_equal(0)


func test_ac18_undoing_a_delete_updates_drawn_items_selection_and_hint_without_special_cases(
) -> void:
	if not await _open_main():
		return
	await _select(VASE)
	_s.tap(KEY_DELETE)
	await _s.frame()
	assert_int(_s.drawn_count()).is_equal(1)
	await _ctrl_chord(KEY_Z)
	assert_int(_s.drawn_count()).is_equal(2)
	assert_str(_s.selected_uid()).is_equal("")
	assert_bool((_part("Hud/PlacementHint") as Control).is_visible_in_tree()).is_false()
	(
		assert_bool(
			(
				(_part("Hud/ItemActions").find_child("DeleteButton", true, false) as Control)
				. is_visible_in_tree()
			)
		)
		. is_false()
	)
