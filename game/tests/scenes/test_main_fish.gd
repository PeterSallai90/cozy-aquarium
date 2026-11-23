extends GdUnitTestSuite
## #36 ghost cancel in the real Main scene (owner: developer): with an item picked and the ghost
## shown, opening the fish panel hides the ghost and clears the pick through the existing
## item_pick_clear_requested / item_pick_cleared pair; nothing is placed and no history entry is
## made. Adding a fish through the real panel reaches the session history (one undo removes it).
## Test decisions: the pick is made with the real card, the pointer spot is found by scanning the
## tank for a point that is not over a HUD control (pattern of test_main_placement.gd).

const Rig := preload("res://tests/helpers/placement_rig.gd")
const Session := preload("res://tests/helpers/placement_session.gd")
const Ui := preload("res://tests/helpers/tank_ui_rig.gd")
const Browser := preload("res://tests/helpers/item_browser_rig.gd")
const Fp := preload("res://tests/helpers/fish_panel_rig.gd")

const MAIN_SCENE := "res://scenes/main.tscn"

var _saved_locale: String = ""
var _language_state: Dictionary = {}
var _saved_window_size: Vector2i = Vector2i.ZERO
var _main: Node = null
var _controls: Control = null
var _s: Session = null


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()
	_language_state = Ui.begin_language_isolation("main_fish")
	_saved_window_size = Vector2i.ZERO


func after_test() -> void:
	Rig.close(_s)
	if _saved_window_size != Vector2i.ZERO:
		get_tree().root.size = _saved_window_size
	Ui.end_language_isolation(_language_state, _saved_locale)


func _open_main() -> bool:
	_saved_window_size = get_tree().root.size
	get_tree().root.size = Rig.WINDOW
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	add_child(_main)
	auto_free(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	_controls = _main.get_node("Hud/TankControls") as Control
	_s = Rig.attach(_main)
	var found: bool = _s.placement != null and _s.ghost != null and Fp.button_of(_controls) != null
	(
		assert_bool(found)
		. override_failure_message("Main has no Placement, no Ghost or no FishButton")
		. is_true()
	)
	return found


func _free_spot() -> Vector2:
	for z: float in [0.0, -0.08, 0.08]:
		for x: float in [0.0, 0.1, -0.1, 0.2, -0.2]:
			var at: Vector2 = _s.screen_of(x, z)
			if not WorldInput.is_over_stop_control(get_viewport(), at):
				return at
	return Vector2(-1.0, -1.0)


func test_36_opening_the_fish_panel_cancels_the_ghost_without_placing_anything() -> void:
	if not await _open_main():
		return
	await Browser.press_open(self, _controls)
	Browser.click_card(_controls, Rig.STONE)
	await _s.frame()
	var spot: Vector2 = _free_spot()
	_s.move(spot)
	await _s.frame()
	assert_bool(_s.ghost_shown()).is_true()
	assert_str(_s.picked_id()).is_equal(String(Rig.STONE))
	var undo_before: int = _s.history.get_undo_count()
	await Fp.press_open(self, _controls)
	assert_bool(Fp.is_open(_controls)).is_true()
	assert_bool(_s.ghost_shown()).is_false()
	assert_str(_s.picked_id()).is_empty()
	assert_int(_s.model.get_item_count()).is_equal(0)
	assert_int(_s.history.get_undo_count()).is_equal(undo_before)


func test_36_adding_a_fish_in_the_main_scene_goes_through_the_session_history() -> void:
	if not await _open_main():
		return
	await Fp.press_open(self, _controls)
	await Fp.click(self, Fp.add_button(_controls))
	assert_int(_s.model.get_fish_count()).is_equal(1)
	assert_str(_s.model.get_fish_at(0).nickname).is_empty()
	assert_bool(_s.history.can_undo()).is_true()
	assert_bool(_s.history.undo()).is_true()
	assert_int(_s.model.get_fish_count()).is_equal(0)
