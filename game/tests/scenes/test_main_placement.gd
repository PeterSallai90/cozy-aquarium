extends GdUnitTestSuite
## #31 AC 17, 18, 28 (normal flow) and 33 (catalog load count) (owner: developer): placement inside
## the real Main scene, with the real TankControls and item browser, so the routing is the real one.
## The Esc order (ADR 0008 Amendment 1 rules 8 and 9: dialog, then a running drag, then a running
## rotate hold, then the open Items panel, then the pick or the selection) depends on the reverse
## tree order of _unhandled_input (Placement under RoomCorner comes before Hud); these tests pin it.
## The item catalog is loaded on first need only: zero loads at the start, one after the first
## browser open, still one after the first placement.
## Test decisions where the plan is silent: Main exposes its shared ItemCatalogSource as
## get_item_source() (the plan names the source created in main.gd but no accessor); the pointer
## spots are found by scanning the tank for a ground point that is not over a HUD control; picks
## are made by clicking the real card, because the browser owns the pick.

const Rig := preload("res://tests/helpers/placement_rig.gd")
const Session := preload("res://tests/helpers/placement_session.gd")
const Api := preload("res://tests/helpers/placement_api.gd")
const Ui := preload("res://tests/helpers/tank_ui_rig.gd")
const Browser := preload("res://tests/helpers/item_browser_rig.gd")

const MAIN_SCENE := "res://scenes/main.tscn"
const FIRST := "a0000001"

var _saved_locale: String = ""
var _language_state: Dictionary = {}
var _saved_window_size: Vector2i = Vector2i.ZERO
var _main: Node = null
var _controls: Control = null
var _s: Session = null


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()
	_language_state = Ui.begin_language_isolation("main_placement")
	_saved_window_size = Vector2i.ZERO


func after_test() -> void:
	Rig.close(_s)
	if _saved_window_size != Vector2i.ZERO:
		get_tree().root.size = _saved_window_size
	Ui.end_language_isolation(_language_state, _saved_locale)


func _open_main(with_item: bool = false) -> bool:
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
	var found: bool = _s.placement != null and _s.view != null and _s.ghost != null
	(
		assert_bool(found)
		. override_failure_message("RoomCorner has no Placement child with PlacedItems and Ghost")
		. is_true()
	)
	if found and with_item:
		Rig.add_item(_s.model, FIRST, Rig.BRANCH, 0.0, 0.0, 10.0)
		await _s.frame()
	return found


## A pointer position over the tank that is not over a HUD control (the panel may be open).
func _free_spot() -> Vector2:
	for z: float in [0.0, -0.08, 0.08]:
		for x: float in [0.0, 0.1, -0.1, 0.2, -0.2]:
			var at: Vector2 = _s.screen_of(x, z)
			if not WorldInput.is_over_stop_control(get_viewport(), at):
				return at
	return Vector2(-1.0, -1.0)


func _pick_stone_with_the_card() -> void:
	await Browser.press_open(self, _controls)
	Browser.click_card(_controls, Rig.STONE)
	await _s.frame()


func _panel_open() -> bool:
	return Browser.is_open(_controls)


func _esc() -> void:
	_s.esc()
	await _s.frame()


func test_ac33_the_catalog_loads_on_first_need_only_and_exactly_once() -> void:
	if not await _open_main():
		return
	(
		assert_bool(_main.has_method("get_item_source"))
		. override_failure_message("Main.get_item_source() is missing")
		. is_true()
	)
	if not _main.has_method("get_item_source"):
		return
	var source: RefCounted = _main.call("get_item_source") as RefCounted
	assert_object(source).is_not_null()
	assert_int(source.call("get_load_count")).is_equal(0)
	await Browser.press_open(self, _controls)
	assert_int(source.call("get_load_count")).is_equal(1)
	Browser.click_card(_controls, Rig.STONE)
	await _s.frame()
	var spot: Vector2 = _free_spot()
	_s.move(spot)
	_s.click(spot)
	await _s.frame()
	assert_int(_s.model.get_item_count()).is_equal(1)
	assert_int(source.call("get_load_count")).is_equal(1)
	assert_int(_s.drawn_count()).is_equal(1)


func test_ac33_a_start_with_an_empty_model_and_no_browser_open_loads_nothing() -> void:
	if not await _open_main():
		return
	if not _main.has_method("get_item_source"):
		assert_bool(false).override_failure_message("Main.get_item_source() is missing").is_true()
		return
	var source: RefCounted = _main.call("get_item_source") as RefCounted
	_s.move(_free_spot())
	await _s.frame()
	assert_bool(source.call("is_loaded")).is_false()
	assert_int(source.call("get_load_count")).is_equal(0)


func test_ac17_esc_closes_the_panel_first_and_clears_the_pick_second() -> void:
	if not await _open_main():
		return
	await _pick_stone_with_the_card()
	assert_bool(_panel_open()).is_true()
	assert_str(_s.picked_id()).is_equal(String(Rig.STONE))
	await _esc()
	assert_bool(_panel_open()).is_false()
	assert_str(_s.picked_id()).is_equal(String(Rig.STONE))
	assert_str(Browser.picked_id(_controls)).is_equal(String(Rig.STONE))
	await _esc()
	assert_str(Browser.picked_id(_controls)).is_equal("")
	assert_str(_s.picked_id()).is_equal("")
	assert_bool(_s.ghost_shown()).is_false()


func test_ac17_with_the_panel_closed_one_esc_clears_the_pick() -> void:
	if not await _open_main():
		return
	await _pick_stone_with_the_card()
	await _esc()
	assert_bool(_panel_open()).is_false()
	await _esc()
	assert_str(_s.picked_id()).is_equal("")
	await _pick_stone_with_the_card()
	assert_bool(_panel_open()).is_true()
	_controls.call("close_panels")
	await _s.frame()
	await _esc()
	assert_str(_s.picked_id()).is_equal("")


func test_ac17_esc_closes_the_panel_before_the_selection_is_cleared() -> void:
	if not await _open_main(true):
		return
	var spot: Vector2 = _s.screen_of_item(FIRST)
	_s.click(spot)
	assert_str(_s.selected_uid()).is_equal(FIRST)
	await Browser.press_open(self, _controls)
	assert_bool(_panel_open()).is_true()
	await _esc()
	assert_bool(_panel_open()).is_false()
	assert_str(_s.selected_uid()).is_equal(FIRST)
	await _esc()
	assert_str(_s.selected_uid()).is_equal("")


func test_ac17_a_running_drag_ends_before_the_open_panel_closes() -> void:
	if not await _open_main(true):
		return
	await Browser.press_open(self, _controls)
	var start: Vector2 = _s.screen_of_item(FIRST)
	(
		assert_bool(WorldInput.is_over_stop_control(get_viewport(), start))
		. override_failure_message("the item is under the panel; the layout changed")
		. is_false()
	)
	_s.press(start)
	_s.move(start + Vector2(Api.tuning("DRAG_THRESHOLD_PX") + 40.0, 0.0))
	assert_bool(_s.dragging()).is_true()
	await _esc()
	assert_bool(_s.dragging()).is_false()
	assert_bool(_panel_open()).is_true()
	_s.release(start)
	assert_int(_s.history.get_undo_count()).is_equal(0)
	await _esc()
	assert_bool(_panel_open()).is_false()


func test_ac17_a_running_hold_ends_before_the_open_panel_closes() -> void:
	if not await _open_main(true):
		return
	_s.click(_s.screen_of_item(FIRST))
	await Browser.press_open(self, _controls)
	_s.key(KEY_COMMA, true)
	assert_bool(_s.holding()).is_true()
	await _esc()
	assert_bool(_s.holding()).is_false()
	assert_bool(_panel_open()).is_true()
	assert_str(_s.selected_uid()).is_equal(FIRST)
	_s.key(KEY_COMMA, false)
	assert_int(_s.history.get_undo_count()).is_equal(0)
	await _esc()
	assert_bool(_panel_open()).is_false()
	assert_str(_s.selected_uid()).is_equal(FIRST)
	await _esc()
	assert_str(_s.selected_uid()).is_equal("")


func test_ac17_an_open_dialog_cancels_first_and_the_pick_stays() -> void:
	if not await _open_main():
		return
	await _pick_stone_with_the_card()
	var dialog: Control = Ui.dialog(_controls)
	assert_object(dialog).is_not_null()
	if dialog == null:
		return
	dialog.call("ask", "tank.large_1.name")
	await _s.frame()
	await _s.frame()
	assert_bool(Ui.dialog_open(_controls)).is_true()
	await _esc()
	assert_bool(Ui.dialog_open(_controls)).is_false()
	assert_str(_s.picked_id()).is_equal(String(Rig.STONE))
	assert_str(Browser.picked_id(_controls)).is_equal(String(Rig.STONE))


func test_ac18_a_model_reset_clears_the_pick_through_the_browser_and_removes_the_ghost() -> void:
	if not await _open_main():
		return
	await _pick_stone_with_the_card()
	_s.move(_free_spot())
	assert_bool(_s.ghost_shown()).is_true()
	_s.model.reset_from(AquariumModel.new("2026-11-01T12:00:00Z"))
	await _s.frame()
	_s.step(0.0)
	assert_str(Browser.picked_id(_controls)).is_equal("")
	assert_str(_s.picked_id()).is_equal("")
	assert_bool(_s.ghost_shown()).is_false()


func test_ac28_in_the_normal_flow_the_card_keeps_the_focus_and_period_turns_the_ghost() -> void:
	if not await _open_main():
		return
	await _pick_stone_with_the_card()
	var spot: Vector2 = _free_spot()
	_s.move(spot)
	assert_bool(_s.ghost_shown()).is_true()
	_s.tap(KEY_PERIOD)
	assert_float(_s.ghost_rotation()).is_equal_approx(345.0, 0.001)
	_s.tap(KEY_COMMA)
	assert_float(_s.ghost_rotation()).is_equal_approx(0.0, 0.001)
	_s.tap(KEY_COMMA, KEY_MASK_SHIFT)
	assert_float(_s.ghost_rotation()).is_equal_approx(1.0, 0.001)
