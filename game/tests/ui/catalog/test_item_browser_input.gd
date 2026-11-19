# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #30 criteria 11, 19, 20 and ADR 0008 (owner: developer). Two setups:
## - the real Main scene next to the HUD (pattern of test_substrate_chooser_input.gd) for the world
##   input rules: the panel is not a world input blocker, a press on it never starts an orbit or
##   pan, and Q/E/R/F are ignored while the search field has the focus (a mouse open must not put
##   the focus in the field: the camera keys and the wheel keep working);
## - tank controls on fixture items for every other control stopping the mouse, the focus on open,
##   the Tab chain with its wrap, the arrow keys across the category row and the grid (hidden cards
##   skipped), and Enter and Space on a card.
## Keys go through the viewport like the player's; the shipped catalog is empty, so the Main
## checks use no card.

const Ir := preload("res://tests/helpers/item_browser_rig.gd")
const Ui := preload("res://tests/helpers/tank_ui_rig.gd")
const Cam := preload("res://tests/helpers/camera_rig.gd")

const MAIN_SCENE := "res://scenes/main.tscn"

var _saved_locale: String = ""
var _language_state: Dictionary = {}
var _translations: Array[Translation] = []
var _saved_window_size: Vector2i = Vector2i.ZERO
var _main: Node = null
var _controls: Control = null
var _camera: Camera3D = null
var _listener: Ir.Listener = null


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()
	_language_state = Ui.begin_language_isolation("item_browser_input")
	_translations = Ir.add_translations()
	TranslationServer.set_locale("en")
	_saved_window_size = Vector2i.ZERO
	_listener = Ir.listen()


func after_test() -> void:
	Ir.unlisten(_listener)
	if _saved_window_size != Vector2i.ZERO:
		get_tree().root.size = _saved_window_size
	Ir.remove_translations(_translations)
	Ui.end_language_isolation(_language_state, _saved_locale)


func _wait() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


# --- Main scene: ADR 0008 ---


## Main with the panel open (by keyboard or mouse); false while a part is missing.
func _open_main(by_keyboard: bool) -> bool:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_saved_window_size = get_tree().root.size
	get_tree().root.size = Cam.SIZE_16_9
	add_child(_main)
	auto_free(_main)
	await _wait()
	_controls = _main.get_node("Hud/TankControls") as Control
	_camera = Cam.camera_of(_main.get_node("RoomCorner"))
	var ok: bool = _camera != null and Ir.open_button(_controls) != null
	assert_bool(ok).override_failure_message("BuildCamera or the Items button is missing").is_true()
	if not ok:
		return false
	Cam.freeze(_main.get_node("RoomCorner"))
	await Ir.press_open(self, _controls, by_keyboard)
	assert_bool(Ir.is_open(_controls)).override_failure_message("the panel did not open").is_true()
	return Ir.is_open(_controls)


func _panel_point() -> Vector2:
	return Ir.panel(_controls).get_global_rect().get_center()


func _world_point() -> Vector2:
	var size: Vector2 = get_viewport().get_visible_rect().size
	return Vector2(size.x * 0.8, size.y * 0.7)


func test_ac02_the_panel_is_not_a_world_input_blocker_and_does_not_block() -> void:
	if not await _open_main(false):
		return
	assert_bool(Ir.panel(_controls).is_in_group(WorldInput.BLOCKER_GROUP)).is_false()
	for node: Node in Ir.panel(_controls).find_children("*", "Control", true, false):
		assert_bool(node.is_in_group(WorldInput.BLOCKER_GROUP)).is_false()
	assert_bool(WorldInput.is_blocked(get_tree())).is_false()


func test_ac02_the_panel_stops_the_mouse() -> void:
	if not await _open_main(false):
		return
	assert_int(Ir.panel(_controls).mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	assert_bool(WorldInput.is_over_stop_control(_main, _panel_point())).is_true()


func test_ac02_a_press_on_the_panel_never_starts_an_orbit_or_pan() -> void:
	if not await _open_main(false):
		return
	var az: float = Cam.t_az(_camera)
	var el: float = Cam.t_el(_camera)
	var pivot: Vector3 = Cam.t_pivot(_camera)
	var root: Viewport = get_viewport()
	Cam.right_press(root, _panel_point())
	assert_bool(Cam.dragging(_camera)).is_false()
	Cam.motion(root, Vector2(60.0, 40.0), _panel_point() + Vector2(60.0, 40.0))
	Cam.motion(root, Vector2(300.0, 200.0), _world_point())
	Cam.right_release(root, _world_point())
	assert_float(Cam.t_az(_camera)).is_equal(az)
	assert_float(Cam.t_el(_camera)).is_equal(el)
	assert_vector(Cam.t_pivot(_camera)).is_equal(pivot)


func test_ac02_a_world_drag_still_orbits_with_the_panel_open() -> void:
	if not await _open_main(false):
		return
	var elevation_before: float = Cam.t_el(_camera)
	Cam.drag(get_viewport(), Vector2(0.0, -40.0), _world_point())
	assert_float(Cam.t_el(_camera)).is_equal_approx(
		elevation_before + 10.0, Cam.ANGLE_TOLERANCE_DEG
	)


func test_ac11_a_keyboard_open_puts_the_focus_in_the_search_field() -> void:
	if not await _open_main(true):
		return
	assert_object(Ir.focus_owner(_controls)).is_same(Ir.search(_controls))
	assert_bool(WorldInput.is_text_focused(get_viewport())).is_true()


func test_ac11_camera_keys_are_ignored_while_the_search_field_has_the_focus() -> void:
	if not await _open_main(true):
		return
	var az: float = Cam.t_az(_camera)
	var el: float = Cam.t_el(_camera)
	var root: Viewport = get_viewport()
	for keycode: Key in [KEY_Q, KEY_E, KEY_R, KEY_F]:
		Cam.key(root, keycode, true, false, 0, int(keycode))
		Cam.key(root, keycode, false, false, 0, int(keycode))
	await _wait()
	assert_float(Cam.t_az(_camera)).is_equal(az)
	assert_float(Cam.t_el(_camera)).is_equal(el)
	assert_bool(Ir.is_open(_controls)).is_true()


func test_ac11_a_mouse_open_does_not_put_the_focus_in_the_search_field() -> void:
	if not await _open_main(false):
		return
	assert_bool(WorldInput.is_text_focused(get_viewport())).is_false()
	assert_object(Ir.focus_owner(_controls)).is_not_same(Ir.search(_controls))


func test_ac11_camera_keys_work_after_a_mouse_open() -> void:
	if not await _open_main(false):
		return
	var az: float = Cam.t_az(_camera)
	Cam.tap(get_viewport(), KEY_E)
	assert_float(Cam.t_az(_camera)).is_equal_approx(az - 45.0, Cam.ANGLE_TOLERANCE_DEG)
	Cam.tap(get_viewport(), KEY_Q)
	assert_float(Cam.t_az(_camera)).is_equal_approx(az, Cam.ANGLE_TOLERANCE_DEG)


func test_ac11_camera_keys_work_again_after_the_panel_is_closed() -> void:
	if not await _open_main(true):
		return
	Ir.close_button(_controls).pressed.emit()
	await _wait()
	assert_bool(WorldInput.is_text_focused(get_viewport())).is_false()
	var az: float = Cam.t_az(_camera)
	Cam.tap(get_viewport(), KEY_E)
	assert_float(Cam.t_az(_camera)).is_equal_approx(az - 45.0, Cam.ANGLE_TOLERANCE_DEG)


# --- tank controls on fixture items ---


func _open(items: ItemCatalog = null, by_keyboard: bool = false) -> bool:
	var catalog: ItemCatalog = items if items != null else Ir.catalog()
	_controls = await Ir.open(self, AquariumModel.new(), catalog)
	auto_free(_controls)
	var ok: bool = _controls != null and Ir.open_button(_controls) != null
	assert_bool(ok).override_failure_message("TankControls has no ItemsButton").is_true()
	if not ok:
		return false
	await Ir.press_open(self, _controls, by_keyboard)
	assert_bool(Ir.is_open(_controls)).override_failure_message("the panel did not open").is_true()
	return Ir.is_open(_controls)


func _tab(count: int, shift: bool = false) -> Array[Control]:
	var visited: Array[Control] = []
	for _step: int in count:
		Ui.tap(_controls, KEY_TAB, shift)
		visited.append(Ir.focus_owner(_controls))
	return visited


func _chain(controls: Node) -> Array[Control]:
	var chain: Array[Control] = [Ir.search(controls), Ir.clear_button(controls)]
	for button: Button in Ir.categories(controls):
		if button.is_visible_in_tree():
			chain.append(button)
	for card: Button in Ir.visible_cards(controls):
		chain.append(card)
	chain.append(Ir.close_button(controls))
	return chain


func test_ac02_every_interactive_control_stops_the_mouse() -> void:
	if not await _open():
		return
	var stoppers: Array[Control] = [
		Ir.panel(_controls),
		Ir.search(_controls),
		Ir.clear_button(_controls),
		Ir.close_button(_controls),
		Ir.scroll(_controls),
	]
	stoppers.append_array(Ir.categories(_controls))
	stoppers.append_array(Ir.cards(_controls))
	for control: Control in stoppers:
		(
			assert_int(control.mouse_filter)
			. override_failure_message("%s does not stop the mouse" % control.name)
			. is_equal(Control.MOUSE_FILTER_STOP)
		)


func test_ac02_the_texts_and_pictures_inside_a_card_do_not_steal_the_click() -> void:
	if not await _open():
		return
	for button: Button in Ir.cards(_controls):
		for node: Node in button.find_children("*", "Control", true, false):
			var control: Control = node as Control
			if control is Label or control is TextureRect or control is Panel:
				(
					assert_int(control.mouse_filter)
					. override_failure_message(
						"%s in %s stops the mouse" % [control.name, button.name]
					)
					. is_not_equal(Control.MOUSE_FILTER_STOP)
				)


func test_ac02_no_control_of_the_panel_joins_the_world_input_blockers() -> void:
	if not await _open():
		return
	assert_bool(Ir.panel(_controls).is_in_group(WorldInput.BLOCKER_GROUP)).is_false()
	for node: Node in Ir.panel(_controls).find_children("*", "Control", true, false):
		assert_bool(node.is_in_group(WorldInput.BLOCKER_GROUP)).is_false()
	assert_bool(WorldInput.is_blocked(get_tree())).is_false()


# --- AC 19: the focus on open ---


func test_ac19_opening_by_keyboard_puts_the_focus_on_the_search_field() -> void:
	if not await _open(null, true):
		return
	assert_object(Ir.focus_owner(_controls)).is_same(Ir.search(_controls))


func test_ac19_opening_by_mouse_puts_the_focus_on_the_selected_category_not_the_field() -> void:
	if not await _open():
		return
	assert_object(Ir.focus_owner(_controls)).is_same(Ir.category(_controls, "Category_all"))
	Ir.select_category(_controls, "Category_rock")
	Ir.close_button(_controls).pressed.emit()
	await _wait()
	await Ir.press_open(self, _controls)
	assert_object(Ir.focus_owner(_controls)).is_same(Ir.category(_controls, "Category_rock"))


func test_ac19_a_keyboard_open_after_a_mouse_open_focuses_the_field_again() -> void:
	if not await _open():
		return
	Ir.close_button(_controls).pressed.emit()
	await _wait()
	await Ir.press_open(self, _controls, true)
	assert_object(Ir.focus_owner(_controls)).is_same(Ir.search(_controls))


# --- AC 19: Tab ---


func test_ac19_tab_walks_search_clear_categories_cards_and_close_in_reading_order() -> void:
	if not await _open(null, true):
		return
	var chain: Array[Control] = _chain(_controls)
	assert_int(chain.size()).is_equal(2 + 5 + 9 + 1)
	assert_object(Ir.focus_owner(_controls)).is_same(chain[0])
	var visited: Array[Control] = _tab(chain.size() - 1)
	for index: int in visited.size():
		(
			assert_object(visited[index])
			. override_failure_message(
				"Tab step %d: expected %s" % [index + 1, chain[index + 1].name]
			)
			. is_same(chain[index + 1])
		)


func test_ac19_tab_from_close_wraps_to_the_search_field_inside_the_panel() -> void:
	if not await _open():
		return
	Ir.close_button(_controls).grab_focus()
	Ui.tap(_controls, KEY_TAB)
	assert_object(Ir.focus_owner(_controls)).is_same(Ir.search(_controls))


func test_ac19_shift_tab_from_the_search_field_wraps_to_close() -> void:
	if not await _open(null, true):
		return
	Ui.tap(_controls, KEY_TAB, true)
	assert_object(Ir.focus_owner(_controls)).is_same(Ir.close_button(_controls))


func test_ac19_shift_tab_walks_the_chain_backwards() -> void:
	if not await _open():
		return
	var chain: Array[Control] = _chain(_controls)
	Ir.close_button(_controls).grab_focus()
	var visited: Array[Control] = _tab(chain.size() - 1, true)
	for index: int in visited.size():
		assert_object(visited[index]).is_same(chain[chain.size() - 2 - index])


func test_ac19_tab_skips_the_cards_the_search_hides() -> void:
	if not await _open(null, true):
		return
	Ir.type_text(_controls, "va")
	assert_that(Ir.visible_ids(_controls)).is_equal(["ornament_vase", "plant_fern"])
	var chain: Array[Control] = _chain(_controls)
	assert_int(chain.size()).is_equal(2 + 5 + 2 + 1)
	var visited: Array[Control] = _tab(chain.size() - 1)
	for index: int in visited.size():
		assert_object(visited[index]).is_same(chain[index + 1])
	Ui.tap(_controls, KEY_TAB)
	assert_object(Ir.focus_owner(_controls)).is_same(Ir.search(_controls))


func test_ac19_tab_skips_a_hidden_category() -> void:
	if not await _open(Ir.catalog(false, [2]), true):
		return
	var chain: Array[Control] = _chain(_controls)
	assert_int(chain.size()).is_equal(2 + 4 + 7 + 1)
	var visited: Array[Control] = _tab(chain.size() - 1)
	for index: int in visited.size():
		assert_object(visited[index]).is_same(chain[index + 1])


func test_ac19_with_no_cards_tab_goes_from_the_categories_to_close() -> void:
	var empty: ItemCatalog = ItemCatalog.from_definitions([] as Array[ItemDefinition])
	if not await _open(empty, true):
		return
	var visited: Array[Control] = _tab(4)
	assert_object(visited[0]).is_same(Ir.clear_button(_controls))
	assert_object(visited[1]).is_same(Ir.category(_controls, "Category_all"))
	assert_object(visited[2]).is_same(Ir.close_button(_controls))
	assert_object(visited[3]).is_same(Ir.search(_controls))


# --- AC 19: arrows ---


func test_ac19_left_and_right_move_between_the_category_entries() -> void:
	if not await _open():
		return
	Ir.category(_controls, "Category_all").grab_focus()
	var expected: Array[String] = [
		"Category_rock", "Category_wood", "Category_ornament", "Category_plant"
	]
	for node_name: String in expected:
		Ui.tap(_controls, KEY_RIGHT)
		assert_object(Ir.focus_owner(_controls)).is_same(Ir.category(_controls, node_name))
	Ui.tap(_controls, KEY_LEFT)
	assert_object(Ir.focus_owner(_controls)).is_same(Ir.category(_controls, "Category_ornament"))


func test_ac19_the_arrows_skip_a_hidden_category() -> void:
	if not await _open(Ir.catalog(false, [2])):
		return
	Ir.category(_controls, "Category_rock").grab_focus()
	Ui.tap(_controls, KEY_RIGHT)
	assert_object(Ir.focus_owner(_controls)).is_same(Ir.category(_controls, "Category_ornament"))
	Ui.tap(_controls, KEY_LEFT)
	assert_object(Ir.focus_owner(_controls)).is_same(Ir.category(_controls, "Category_rock"))


func test_ac19_left_and_right_in_the_grid_move_between_neighbouring_cards() -> void:
	if not await _open():
		return
	var cards: Array[Button] = Ir.visible_cards(_controls)
	var columns: int = Ir.cards_box(_controls).columns
	assert_int(columns).is_greater_equal(2)
	cards[0].grab_focus()
	Ui.tap(_controls, KEY_RIGHT)
	assert_object(Ir.focus_owner(_controls)).is_same(cards[1])
	Ui.tap(_controls, KEY_LEFT)
	assert_object(Ir.focus_owner(_controls)).is_same(cards[0])


func test_ac19_up_and_down_in_the_grid_move_by_one_row() -> void:
	if not await _open():
		return
	var cards: Array[Button] = Ir.visible_cards(_controls)
	var columns: int = Ir.cards_box(_controls).columns
	assert_int(cards.size()).is_greater(columns + 1)
	cards[1].grab_focus()
	Ui.tap(_controls, KEY_DOWN)
	assert_object(Ir.focus_owner(_controls)).is_same(cards[1 + columns])
	cards[0].grab_focus()
	Ui.tap(_controls, KEY_DOWN)
	assert_object(Ir.focus_owner(_controls)).is_same(cards[columns])
	Ui.tap(_controls, KEY_UP)
	assert_object(Ir.focus_owner(_controls)).is_same(cards[0])


func test_ac19_the_grid_arrows_skip_the_cards_the_search_hides() -> void:
	if not await _open():
		return
	Ir.type_text(_controls, "va")
	var cards: Array[Button] = Ir.visible_cards(_controls)
	assert_int(cards.size()).is_equal(2)
	cards[0].grab_focus()
	Ui.tap(_controls, KEY_RIGHT)
	assert_object(Ir.focus_owner(_controls)).is_same(Ir.card(_controls, &"plant_fern"))
	Ui.tap(_controls, KEY_LEFT)
	assert_object(Ir.focus_owner(_controls)).is_same(Ir.card(_controls, &"ornament_vase"))


func test_ac19_the_arrows_follow_the_grid_after_a_category_change() -> void:
	if not await _open():
		return
	Ir.select_category(_controls, "Category_wood")
	var cards: Array[Button] = Ir.visible_cards(_controls)
	assert_int(cards.size()).is_equal(2)
	cards[0].grab_focus()
	Ui.tap(_controls, KEY_RIGHT)
	assert_object(Ir.focus_owner(_controls)).is_same(Ir.card(_controls, &"wood_root"))


func test_ac19_left_and_right_in_the_search_field_move_the_text_cursor_not_the_focus() -> void:
	if not await _open(null, true):
		return
	var field: LineEdit = Ir.search(_controls)
	Ir.type_text(_controls, "slate")
	field.caret_column = 5
	Ui.tap(_controls, KEY_LEFT)
	assert_object(Ir.focus_owner(_controls)).is_same(field)
	assert_int(field.caret_column).is_equal(4)
	Ui.tap(_controls, KEY_RIGHT)
	assert_object(Ir.focus_owner(_controls)).is_same(field)
	assert_int(field.caret_column).is_equal(5)


func test_ac19_every_control_can_take_the_focus_without_the_mouse() -> void:
	if not await _open():
		return
	var controls: Array[Control] = _chain(_controls)
	for control: Control in controls:
		(
			assert_int(control.focus_mode)
			. override_failure_message("%s is not focusable" % control.name)
			. is_not_equal(Control.FOCUS_NONE)
		)


# --- AC 20: Enter and Space ---


func test_ac20_enter_on_a_focused_card_picks_it_like_a_click() -> void:
	if not await _open():
		return
	Ir.card(_controls, &"wood_drift").grab_focus()
	Ui.tap(_controls, KEY_ENTER)
	assert_that(_listener.picked).is_equal([&"wood_drift"])
	assert_that(Ir.marked_ids(_controls)).is_equal(["wood_drift"])
	assert_int(_listener.cleared).is_equal(0)


func test_ac20_space_on_a_focused_card_picks_it_like_a_click() -> void:
	if not await _open():
		return
	Ir.card(_controls, &"plant_fern").grab_focus()
	Ui.tap(_controls, KEY_SPACE)
	assert_that(_listener.picked).is_equal([&"plant_fern"])
	assert_that(Ir.marked_ids(_controls)).is_equal(["plant_fern"])


func test_ac20_enter_on_the_marked_card_clears_the_pick() -> void:
	if not await _open():
		return
	Ir.card(_controls, &"wood_drift").grab_focus()
	Ui.tap(_controls, KEY_ENTER)
	Ui.tap(_controls, KEY_ENTER)
	assert_that(_listener.timeline).is_equal(["picked:wood_drift", "cleared"])


func test_ac20_a_pick_by_keyboard_keeps_the_panel_open() -> void:
	if not await _open():
		return
	Ir.card(_controls, &"wood_drift").grab_focus()
	Ui.tap(_controls, KEY_ENTER)
	await _wait()
	assert_bool(Ir.is_open(_controls)).is_true()


func test_ac20_enter_on_a_category_selects_it() -> void:
	if not await _open():
		return
	Ir.category(_controls, "Category_wood").grab_focus()
	Ui.tap(_controls, KEY_ENTER)
	assert_that(Ir.visible_ids(_controls)).is_equal(["wood_drift", "wood_root"])
	assert_that(Ir.selected_category_names(_controls)).is_equal(["Category_wood"])


func test_ac20_enter_on_the_clear_button_clears_the_search() -> void:
	if not await _open():
		return
	Ir.type_text(_controls, "slate")
	Ir.clear_button(_controls).grab_focus()
	Ui.tap(_controls, KEY_ENTER)
	assert_str(Ir.search(_controls).text).is_equal("")
	assert_int(Ir.visible_ids(_controls).size()).is_equal(9)
