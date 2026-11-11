# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #25 criteria 10, 11, 12 (text field part) and the follow-up of #117 (owner: developer): the build
## camera inside the real Main scene, next to the HUD, so the GUI routing is the real one (ADR
## 0008).
## A drag that starts in the world keeps orbiting over the tank details panel and ends on the
## release anywhere; a drag that starts on the panel never orbits; a visible modal dialog (a member
## of the group world_input_blockers) blocks drag and Q/E/R/F; a focused text field keeps its
## letters. Events are pushed through the root viewport; the camera is driven by step() only.

const Cam := preload("res://tests/helpers/camera_rig.gd")
const Ui := preload("res://tests/helpers/tank_ui_rig.gd")
const Table := preload("res://tests/helpers/tank_table.gd")
const OrbitApi := preload("res://tests/helpers/orbit_api.gd")

const MAIN_SCENE := "res://scenes/main.tscn"
const HUGE := 1000000.0

var _saved_locale: String = ""
var _language_state: Dictionary = {}
var _main: Node = null
var _controls: Control = null
var _camera: Camera3D = null
var _saved_window_size: Vector2i


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()
	_language_state = Ui.begin_language_isolation("camera_routing")
	_saved_window_size = Vector2i.ZERO


func after_test() -> void:
	if _saved_window_size != Vector2i.ZERO:
		get_tree().root.size = _saved_window_size
	Ui.end_language_isolation(_language_state, _saved_locale)


func _open_main() -> bool:
	(
		assert_bool(ResourceLoader.exists(MAIN_SCENE))
		. override_failure_message("main scene missing: %s" % MAIN_SCENE)
		. is_true()
	)
	var scene: PackedScene = load(MAIN_SCENE) as PackedScene
	_main = scene.instantiate()
	# The headless root window is 64x64; the HUD layout needs the real game size.
	_saved_window_size = get_tree().root.size
	get_tree().root.size = Cam.SIZE_16_9
	(
		assert_vector(Vector2(_root().get_visible_rect().size))
		. override_failure_message("the test window is not 1280x720")
		. is_equal(Vector2(Cam.SIZE_16_9))
	)
	add_child(_main)
	auto_free(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	_controls = _main.get_node("Hud/TankControls") as Control
	_camera = Cam.camera_of(_main.get_node("RoomCorner"))
	(
		assert_bool(_camera != null)
		. override_failure_message("RoomCorner has no BuildCamera child (Camera3D)")
		. is_true()
	)
	if _camera == null:
		return false
	Cam.freeze(_main.get_node("RoomCorner"))
	return true


func _root() -> Viewport:
	return get_viewport()


func _world_point() -> Vector2:
	var size: Vector2 = _root().get_visible_rect().size
	return Vector2(size.x * 0.8, size.y * 0.7)


func _panel_point(panel: Control) -> Vector2:
	return panel.get_global_rect().get_center()


func _wait() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _unchanged(az: float, el: float) -> void:
	assert_float(Cam.t_az(_camera)).is_equal(az)
	assert_float(Cam.t_el(_camera)).is_equal(el)


# --- AC 10: the tank details panel is open (#117 follow-up) ---


func test_ac10_the_panel_is_where_the_test_expects_it_and_the_world_point_is_free() -> void:
	if not await _open_main():
		return
	await Ui.open_details(self, _controls)
	var panel: Control = Ui.details(_controls)
	assert_bool(panel != null and panel.is_visible_in_tree()).is_true()
	if panel == null:
		return
	assert_bool(panel.get_global_rect().has_point(_world_point())).is_false()
	assert_bool(panel.get_global_rect().has_point(_panel_point(panel))).is_true()
	var hud: Node = _main.get_node("Hud")
	for node: Node in hud.find_children("*", "Control", true, false):
		var control: Control = node as Control
		if control.is_visible_in_tree() and control.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			assert_bool(control.get_global_rect().has_point(_world_point())).is_false()


func test_ac10_a_world_drag_orbits_with_the_details_panel_open() -> void:
	if not await _open_main():
		return
	await Ui.open_details(self, _controls)
	Cam.drag(_root(), Vector2(0.0, HUGE), _world_point())
	assert_float(Cam.t_el(_camera)).is_less(0.0)
	Cam.drag(_root(), Vector2(0.0, -HUGE), _world_point())
	assert_float(Cam.t_el(_camera)).is_equal_approx(Cam.MAX_ELEVATION_DEG, 0.01)
	var before: float = Cam.t_az(_camera)
	Cam.drag(_root(), Vector2(80.0, 0.0), _world_point())
	assert_float(absf(Cam.t_az(_camera) - before)).is_greater(1.0)


func test_ac10_the_world_drag_down_stops_at_the_lowest_elevation_with_the_panel_open() -> void:
	if not await _open_main():
		return
	await Ui.open_details(self, _controls)
	Cam.drag(_root(), Vector2(0.0, HUGE), _world_point())
	assert_float(Cam.t_el(_camera)).is_equal_approx(
		Cam.min_el(_camera, Table.MEDIUM), Cam.ANGLE_TOLERANCE_DEG
	)


func test_ac10_a_drag_that_starts_on_the_panel_never_orbits() -> void:
	if not await _open_main():
		return
	await Ui.open_details(self, _controls)
	var panel: Control = Ui.details(_controls)
	var az: float = Cam.t_az(_camera)
	var el: float = Cam.t_el(_camera)
	Cam.right_press(_root(), _panel_point(panel))
	assert_bool(Cam.dragging(_camera)).is_false()
	Cam.motion(_root(), Vector2(60.0, 40.0), _panel_point(panel) + Vector2(60.0, 40.0))
	# The pointer leaves the panel and moves through the world.
	Cam.motion(_root(), Vector2(300.0, 200.0), _world_point())
	Cam.motion(_root(), Vector2(-100.0, 50.0), _world_point() + Vector2(-100.0, 50.0))
	assert_bool(Cam.dragging(_camera)).is_false()
	Cam.right_release(_root(), _world_point())
	_unchanged(az, el)


func test_ac10_a_drag_that_starts_in_the_world_keeps_orbiting_over_the_panel() -> void:
	if not await _open_main():
		return
	await Ui.open_details(self, _controls)
	var panel: Control = Ui.details(_controls)
	Cam.right_press(_root(), _world_point())
	assert_bool(Cam.dragging(_camera)).is_true()
	var before: float = Cam.t_az(_camera)
	Cam.motion(_root(), Vector2(-40.0, 0.0), _panel_point(panel))
	assert_float(absf(Cam.t_az(_camera) - before)).is_equal_approx(10.0, Cam.ANGLE_TOLERANCE_DEG)
	Cam.motion(_root(), Vector2(-40.0, 0.0), _panel_point(panel) + Vector2(5.0, 5.0))
	assert_float(absf(Cam.t_az(_camera) - before)).is_equal_approx(20.0, Cam.ANGLE_TOLERANCE_DEG)
	assert_bool(Cam.dragging(_camera)).is_true()


func test_ac10_a_release_over_the_panel_ends_the_world_drag() -> void:
	if not await _open_main():
		return
	await Ui.open_details(self, _controls)
	var panel: Control = Ui.details(_controls)
	Cam.right_press(_root(), _world_point())
	Cam.motion(_root(), Vector2(-40.0, 0.0), _panel_point(panel))
	Cam.right_release(_root(), _panel_point(panel))
	assert_bool(Cam.dragging(_camera)).is_false()
	var az: float = Cam.t_az(_camera)
	var el: float = Cam.t_el(_camera)
	Cam.motion(_root(), Vector2(200.0, 100.0), _world_point())
	_unchanged(az, el)


func test_ac10_a_world_drag_orbits_with_the_chooser_open_too() -> void:
	if not await _open_main():
		return
	await Ui.open_chooser(self, _controls)
	var before: float = Cam.t_el(_camera)
	Cam.drag(_root(), Vector2(0.0, -40.0), _world_point())
	assert_float(Cam.t_el(_camera)).is_equal_approx(before + 10.0, Cam.ANGLE_TOLERANCE_DEG)


func test_ac10_the_keys_keep_working_with_the_details_panel_open() -> void:
	if not await _open_main():
		return
	await Ui.open_details(self, _controls)
	var az: float = Cam.t_az(_camera)
	var el: float = Cam.t_el(_camera)
	Cam.tap(_root(), KEY_E)
	Cam.tap(_root(), KEY_R)
	assert_float(Cam.t_az(_camera)).is_equal_approx(az - 45.0, Cam.ANGLE_TOLERANCE_DEG)
	assert_float(Cam.t_el(_camera)).is_equal_approx(el + 5.0, Cam.ANGLE_TOLERANCE_DEG)


func test_ac10_opening_and_closing_the_panel_does_not_move_the_camera() -> void:
	if not await _open_main():
		return
	var az: float = Cam.t_az(_camera)
	var el: float = Cam.t_el(_camera)
	await Ui.open_details(self, _controls)
	Ui.details_close_button(_controls).pressed.emit()
	await _wait()
	_unchanged(az, el)


# --- AC 11: a modal dialog blocks the world ---


func _open_dialog() -> bool:
	var dialog: Control = Ui.dialog(_controls)
	(
		assert_bool(dialog != null)
		. override_failure_message("TankChangeDialog is missing from TankControls")
		. is_true()
	)
	if dialog == null:
		return false
	dialog.call("ask", "tank.large_1.name")
	await _wait()
	assert_bool(Ui.dialog_open(_controls)).is_true()
	return Ui.dialog_open(_controls)


func test_ac11_the_change_tank_dialog_is_in_the_world_input_blockers_group() -> void:
	if not await _open_main():
		return
	var dialog: Control = Ui.dialog(_controls)
	assert_bool(dialog != null).is_true()
	if dialog == null:
		return
	assert_bool(dialog.is_in_group(OrbitApi.blocker_group())).is_true()


func test_ac11_the_world_is_blocked_only_while_the_dialog_is_open() -> void:
	if not await _open_main():
		return
	assert_that(OrbitApi.is_blocked(get_tree())).is_equal(false)
	if not await _open_dialog():
		return
	assert_that(OrbitApi.is_blocked(get_tree())).is_equal(true)
	Ui.cancel_button(_controls).pressed.emit()
	await _wait()
	assert_that(OrbitApi.is_blocked(get_tree())).is_equal(false)


func test_ac11_a_drag_with_the_dialog_open_does_not_move_the_camera() -> void:
	if not await _open_main():
		return
	if not await _open_dialog():
		return
	var az: float = Cam.t_az(_camera)
	var el: float = Cam.t_el(_camera)
	Cam.right_press(_root(), _world_point())
	Cam.motion(_root(), Vector2(300.0, 200.0), _world_point() + Vector2(300.0, 200.0))
	Cam.motion(_root(), Vector2(0.0, HUGE), _world_point())
	Cam.right_release(_root(), _world_point())
	assert_bool(Cam.dragging(_camera)).is_false()
	_unchanged(az, el)


func test_ac11_q_e_r_and_f_with_the_dialog_open_do_not_move_the_camera() -> void:
	if not await _open_main():
		return
	if not await _open_dialog():
		return
	var az: float = Cam.t_az(_camera)
	var el: float = Cam.t_el(_camera)
	for keycode: Key in [KEY_Q, KEY_E, KEY_R, KEY_F]:
		Cam.tap(_root(), keycode)
		Cam.key(_root(), keycode, true)
		Cam.step(_camera, 1.0)
		Cam.key(_root(), keycode, false)
	_unchanged(az, el)


func test_ac11_the_camera_works_again_after_the_dialog_closes() -> void:
	if not await _open_main():
		return
	if not await _open_dialog():
		return
	Ui.cancel_button(_controls).pressed.emit()
	await _wait()
	assert_bool(Ui.dialog_open(_controls)).is_false()
	var az: float = Cam.t_az(_camera)
	Cam.tap(_root(), KEY_E)
	assert_float(Cam.t_az(_camera)).is_equal_approx(az - 45.0, Cam.ANGLE_TOLERANCE_DEG)
	var el: float = Cam.t_el(_camera)
	Cam.drag(_root(), Vector2(0.0, -40.0), _world_point())
	assert_float(Cam.t_el(_camera)).is_equal_approx(el + 10.0, Cam.ANGLE_TOLERANCE_DEG)


func test_ac11_a_drag_in_progress_ends_when_the_dialog_opens() -> void:
	if not await _open_main():
		return
	Cam.right_press(_root(), _world_point())
	Cam.motion(_root(), Vector2(40.0, 0.0), _world_point() + Vector2(40.0, 0.0))
	assert_bool(Cam.dragging(_camera)).is_true()
	if not await _open_dialog():
		return
	var az: float = Cam.t_az(_camera)
	var el: float = Cam.t_el(_camera)
	Cam.motion(_root(), Vector2(200.0, 100.0), _world_point())
	assert_bool(Cam.dragging(_camera)).is_false()
	_unchanged(az, el)


func test_ac11_a_held_key_stops_repeating_when_the_dialog_opens() -> void:
	if not await _open_main():
		return
	var az: float = Cam.t_az(_camera)
	Cam.key(_root(), KEY_E, true)
	assert_float(Cam.t_az(_camera)).is_equal_approx(az - 45.0, Cam.ANGLE_TOLERANCE_DEG)
	if not await _open_dialog():
		return
	Cam.step(_camera, 3.0)
	Cam.key(_root(), KEY_E, false)
	assert_float(Cam.t_az(_camera)).is_equal_approx(az - 45.0, Cam.ANGLE_TOLERANCE_DEG)


# --- AC 12: a focused text field keeps its letters ---


func _add_line_edit() -> LineEdit:
	var field: LineEdit = LineEdit.new()
	(_main.get_node("Hud") as Node).add_child(field)
	field.position = Vector2(400.0, 300.0)
	field.size = Vector2(200.0, 32.0)
	field.grab_focus()
	return field


func test_ac12_typing_q_e_r_f_in_a_focused_text_field_does_not_move_the_camera() -> void:
	if not await _open_main():
		return
	var field: LineEdit = _add_line_edit()
	await _wait()
	assert_bool(field.has_focus()).is_true()
	var az: float = Cam.t_az(_camera)
	var el: float = Cam.t_el(_camera)
	for pair: Array in [[KEY_Q, 113], [KEY_E, 101], [KEY_R, 114], [KEY_F, 102]]:
		Cam.key(_root(), pair[0], true, false, 0, pair[1])
		Cam.step(_camera, 1.0)
		Cam.key(_root(), pair[0], false, false, 0, pair[1])
	# The field did take the letters: the test really typed into it.
	assert_str(field.text).is_equal("qerf")
	_unchanged(az, el)


func test_ac12_the_keys_work_again_when_the_text_field_loses_the_focus() -> void:
	if not await _open_main():
		return
	var field: LineEdit = _add_line_edit()
	await _wait()
	field.release_focus()
	await _wait()
	var az: float = Cam.t_az(_camera)
	Cam.key(_root(), KEY_E, true, false, 0, 101)
	Cam.key(_root(), KEY_E, false, false, 0, 101)
	assert_float(Cam.t_az(_camera)).is_equal_approx(az - 45.0, Cam.ANGLE_TOLERANCE_DEG)
