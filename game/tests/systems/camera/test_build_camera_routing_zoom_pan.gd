# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #26 criteria 18, 19 and 20 (owner: developer): the build camera inside the real Main scene, next
## to the HUD, so the GUI routing is the real one (ADR 0008). The wheel and the middle-drag work
## on the world next to the tank details panel; a Control with mouse_filter STOP consumes the wheel
## and the pan start, PASS and IGNORE let them through; a modal dialog, a focused text field and
## modifier keys block the camera; a pan ends when the window loses focus. Events are pushed
## through the root viewport; the camera is driven by step() only.

const Cz := preload("res://tests/helpers/camera_zoom_rig.gd")
const Cam := preload("res://tests/helpers/camera_rig.gd")
const Ui := preload("res://tests/helpers/tank_ui_rig.gd")
const Table := preload("res://tests/helpers/tank_table.gd")
const OrbitApi := preload("res://tests/helpers/orbit_api.gd")

const MAIN_SCENE := "res://scenes/main.tscn"

var _saved_locale: String = ""
var _language_state: Dictionary = {}
var _main: Node = null
var _controls: Control = null
var _camera: Camera3D = null
var _saved_window_size: Vector2i
var _default: float = 0.0
var _home: Vector3 = Vector3.ZERO
var _pan_box: AABB = AABB()


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()
	_language_state = Ui.begin_language_isolation("camera_routing_zoom_pan")
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
	_saved_window_size = get_tree().root.size
	get_tree().root.size = Cam.SIZE_16_9
	add_child(_main)
	auto_free(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	_controls = _main.get_node("Hud/TankControls") as Control
	var room: Node3D = _main.get_node("RoomCorner") as Node3D
	_camera = Cam.camera_of(room)
	if _camera == null:
		fail("RoomCorner has no BuildCamera child (Camera3D)")
		return false
	Cam.freeze(room)
	if not Cz.require_api(self, _camera):
		return false
	_default = Cam.t_dist(_camera)
	_home = Cam.t_pivot(_camera)
	_pan_box = Cz.pan_box(Table.MEDIUM, Cz.stand_z(room))
	return true


func _root() -> Viewport:
	return get_viewport()


func _world_point() -> Vector2:
	var size: Vector2 = _root().get_visible_rect().size
	return Vector2(size.x * 0.8, size.y * 0.7)


func _wait() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _unchanged() -> void:
	assert_float(Cam.t_dist(_camera)).is_equal_approx(_default, Cz.LENGTH_M)
	assert_vector(Cam.t_pivot(_camera)).is_equal_approx(_home, Vector3.ONE * 0.000001)


## A full-size control of the given filter that covers the world point of the test.
func _cover_world_point(filter: Control.MouseFilter) -> Control:
	var control: Control = Control.new()
	control.mouse_filter = filter
	(_main.get_node("Hud") as Node).add_child(control)
	control.position = _world_point() - Vector2(60.0, 60.0)
	control.size = Vector2(120.0, 120.0)
	return control


# --- AC 18: the details panel and Controls ---


func test_ac18_the_wheel_zooms_the_world_with_the_details_panel_open() -> void:
	if not await _open_main():
		return
	await Ui.open_details(self, _controls)
	Cz.wheel(_root(), true, 1.0, 0, _world_point())
	assert_float(Cam.t_dist(_camera)).is_equal_approx(
		_default * Cz.setting("zoom_step_factor"), Cz.LENGTH_M
	)
	Cz.wheel(_root(), false, 1.0, 0, _world_point())
	assert_float(Cam.t_dist(_camera)).is_equal_approx(_default, Cz.LENGTH_M)


func test_ac18_the_middle_drag_pans_the_world_with_the_details_panel_open() -> void:
	if not await _open_main():
		return
	await Ui.open_details(self, _controls)
	var expected: Vector3 = Cz.expected_pan(_camera, Vector2(-30.0, 12.0), _default)
	Cz.pan(_root(), Vector2(-30.0, 12.0), _world_point())
	assert_vector(Cam.t_pivot(_camera) - _home).is_equal_approx(expected, Vector3.ONE * 0.0003)


func test_ac18_the_wheel_over_a_stop_control_does_not_zoom() -> void:
	if not await _open_main():
		return
	var cover: Control = _cover_world_point(Control.MOUSE_FILTER_STOP)
	await _wait()
	Cz.wheel(_root(), true, 1.0, 0, _world_point())
	Cz.wheel(_root(), false, 1.0, 0, _world_point())
	_unchanged()
	cover.mouse_filter = Control.MOUSE_FILTER_PASS
	Cz.wheel(_root(), true, 1.0, 0, _world_point())
	assert_float(Cam.t_dist(_camera)).is_equal_approx(
		_default * Cz.setting("zoom_step_factor"), Cz.LENGTH_M
	)


func test_ac18_the_wheel_over_a_pass_or_ignore_control_zooms() -> void:
	if not await _open_main():
		return
	var cover: Control = _cover_world_point(Control.MOUSE_FILTER_PASS)
	await _wait()
	Cz.wheel(_root(), true, 1.0, 0, _world_point())
	assert_float(Cam.t_dist(_camera)).is_equal_approx(
		_default * Cz.setting("zoom_step_factor"), Cz.LENGTH_M
	)
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Cz.wheel(_root(), false, 1.0, 0, _world_point())
	assert_float(Cam.t_dist(_camera)).is_equal_approx(_default, Cz.LENGTH_M)


func test_ac18_a_pan_that_starts_over_a_stop_control_never_pans_even_when_the_pointer_leaves(
) -> void:
	if not await _open_main():
		return
	var cover: Control = _cover_world_point(Control.MOUSE_FILTER_STOP)
	await _wait()
	var inside: Vector2 = _world_point()
	Cz.middle_press(_root(), inside)
	assert_bool(Cz.panning(_camera)).is_false()
	Cz.middle_motion(_root(), Vector2(40.0, 20.0), inside + Vector2(40.0, 20.0))
	# The pointer leaves the control and moves through the world.
	Cz.middle_motion(_root(), Vector2(-300.0, -100.0), Vector2(300.0, 200.0))
	Cz.middle_motion(_root(), Vector2(-50.0, 30.0), Vector2(250.0, 230.0))
	assert_bool(Cz.panning(_camera)).is_false()
	Cz.middle_release(_root(), Vector2(250.0, 230.0))
	_unchanged()
	cover.queue_free()


func test_ac18_a_pan_over_a_pass_control_starts() -> void:
	if not await _open_main():
		return
	_cover_world_point(Control.MOUSE_FILTER_PASS)
	await _wait()
	Cz.middle_press(_root(), _world_point())
	assert_bool(Cz.panning(_camera)).is_true()
	Cz.middle_release(_root(), _world_point())


func test_ac18_a_pan_that_starts_in_the_world_keeps_panning_over_the_panel() -> void:
	if not await _open_main():
		return
	await Ui.open_details(self, _controls)
	var panel: Control = Ui.details(_controls)
	var over: Vector2 = panel.get_global_rect().get_center()
	Cz.middle_press(_root(), _world_point())
	assert_bool(Cz.panning(_camera)).is_true()
	var expected: Vector3 = Cz.expected_pan(_camera, Vector2(-20.0, 0.0), _default)
	Cz.middle_motion(_root(), Vector2(-20.0, 0.0), over)
	assert_vector(Cam.t_pivot(_camera) - _home).is_equal_approx(expected, Vector3.ONE * 0.0003)
	Cz.middle_motion(_root(), Vector2(-20.0, 0.0), over + Vector2(5.0, 5.0))
	assert_vector(Cam.t_pivot(_camera) - _home).is_equal_approx(
		expected * 2.0, Vector3.ONE * 0.0006
	)
	assert_bool(Cz.panning(_camera)).is_true()
	Cz.middle_release(_root(), over)
	assert_bool(Cz.panning(_camera)).is_false()


func test_ac18_a_pan_that_starts_on_the_panel_never_pans() -> void:
	if not await _open_main():
		return
	await Ui.open_details(self, _controls)
	var panel: Control = Ui.details(_controls)
	var over: Vector2 = panel.get_global_rect().get_center()
	Cz.middle_press(_root(), over)
	assert_bool(Cz.panning(_camera)).is_false()
	Cz.middle_motion(_root(), Vector2(60.0, 40.0), over + Vector2(60.0, 40.0))
	Cz.middle_motion(_root(), Vector2(300.0, 200.0), _world_point())
	Cz.middle_release(_root(), _world_point())
	_unchanged()


func test_ac18_the_wheel_over_the_details_panel_does_not_zoom() -> void:
	if not await _open_main():
		return
	await Ui.open_details(self, _controls)
	var panel: Control = Ui.details(_controls)
	assert_int(panel.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	Cz.wheel(_root(), true, 1.0, 0, panel.get_global_rect().get_center())
	_unchanged()


# --- AC 19: modal, text field and modifiers ---


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


func _move_away_first() -> void:
	Cam.set_orbit(_camera, 100.0, 40.0, true)
	Cz.set_pivot(_camera, _home + Vector3(0.05, 0.02, 0.0), true)
	_home = Cam.t_pivot(_camera)
	_default = Cam.t_dist(_camera)


func test_ac19_with_a_modal_dialog_open_the_wheel_the_pan_and_home_do_nothing() -> void:
	if not await _open_main():
		return
	_move_away_first()
	if not await _open_dialog():
		return
	var az: float = Cam.t_az(_camera)
	Cz.wheel(_root(), true, 1.0, 0, _world_point())
	Cz.wheel(_root(), false, Cz.HUGE, 0, _world_point())
	Cz.pan(_root(), Vector2(80.0, 40.0), _world_point())
	Cz.home_key(_root())
	assert_bool(Cz.panning(_camera)).is_false()
	_unchanged()
	assert_float(Cam.t_az(_camera)).is_equal_approx(az, Cz.ANGLE_DEG)


func test_ac19_the_wheel_the_pan_and_home_work_again_after_the_dialog_closes() -> void:
	if not await _open_main():
		return
	if not await _open_dialog():
		return
	Ui.cancel_button(_controls).pressed.emit()
	await _wait()
	Cz.wheel(_root(), true, 1.0, 0, _world_point())
	assert_float(Cam.t_dist(_camera)).is_equal_approx(
		_default * Cz.setting("zoom_step_factor"), Cz.LENGTH_M
	)
	Cz.pan(_root(), Vector2(30.0, 0.0), _world_point())
	assert_float((Cam.t_pivot(_camera) - _home).length()).is_greater(0.001)
	Cam.set_orbit(_camera, 100.0, 40.0, true)
	Cz.home_key(_root())
	assert_float(Cam.t_az(_camera)).is_equal_approx(0.0, Cz.ANGLE_DEG)
	assert_float(Cam.t_dist(_camera)).is_equal_approx(_default, Cz.LENGTH_M)


func test_ac19_a_pan_in_progress_ends_when_the_dialog_opens() -> void:
	if not await _open_main():
		return
	Cz.middle_press(_root(), _world_point())
	Cz.middle_motion(_root(), Vector2(20.0, 0.0), _world_point() + Vector2(20.0, 0.0))
	assert_bool(Cz.panning(_camera)).is_true()
	if not await _open_dialog():
		return
	var pivot: Vector3 = Cam.t_pivot(_camera)
	Cz.middle_motion(_root(), Vector2(200.0, 100.0), _world_point())
	Cam.step(_camera, Cz.FRAME_S)
	assert_bool(Cz.panning(_camera)).is_false()
	assert_vector(Cam.t_pivot(_camera)).is_equal_approx(pivot, Vector3.ONE * 0.000001)


func _add_line_edit() -> LineEdit:
	var field: LineEdit = LineEdit.new()
	(_main.get_node("Hud") as Node).add_child(field)
	field.position = Vector2(400.0, 300.0)
	field.size = Vector2(200.0, 32.0)
	field.grab_focus()
	return field


func test_ac19_with_a_focused_text_field_the_wheel_the_pan_and_home_do_nothing() -> void:
	if not await _open_main():
		return
	_move_away_first()
	var field: LineEdit = _add_line_edit()
	await _wait()
	assert_bool(field.has_focus()).is_true()
	var az: float = Cam.t_az(_camera)
	Cz.wheel(_root(), true, 1.0, 0, _world_point())
	Cz.pan(_root(), Vector2(80.0, 40.0), _world_point())
	Cz.home_key(_root())
	assert_bool(Cz.panning(_camera)).is_false()
	_unchanged()
	assert_float(Cam.t_az(_camera)).is_equal_approx(az, Cz.ANGLE_DEG)


func test_ac19_the_camera_works_again_when_the_text_field_loses_the_focus() -> void:
	if not await _open_main():
		return
	var field: LineEdit = _add_line_edit()
	await _wait()
	field.release_focus()
	await _wait()
	Cz.wheel(_root(), true, 1.0, 0, _world_point())
	assert_float(Cam.t_dist(_camera)).is_equal_approx(
		_default * Cz.setting("zoom_step_factor"), Cz.LENGTH_M
	)


func test_ac19_home_with_ctrl_alt_shift_or_meta_does_nothing() -> void:
	if not await _open_main():
		return
	_move_away_first()
	for modifier: int in Cz.MASK_ALL:
		Cz.home_key(_root(), modifier)
		assert_float(Cam.t_az(_camera)).is_equal_approx(100.0, Cz.ANGLE_DEG)
		assert_float(Cam.t_el(_camera)).is_equal_approx(40.0, Cz.ANGLE_DEG)
		assert_vector(Cam.t_pivot(_camera)).is_equal_approx(_home, Vector3.ONE * 0.000001)
	Cz.home_key(_root())
	assert_float(Cam.t_az(_camera)).is_equal_approx(0.0, Cz.ANGLE_DEG)


func test_ac19_the_wheel_with_ctrl_alt_shift_or_meta_does_nothing() -> void:
	if not await _open_main():
		return
	for modifier: int in Cz.MASK_ALL:
		Cz.wheel(_root(), true, 1.0, modifier, _world_point())
		Cz.wheel(_root(), false, 1.0, modifier, _world_point())
		_unchanged()


# --- AC 20: focus loss and combined gestures ---


func test_ac20_the_pan_ends_when_the_application_loses_the_focus() -> void:
	if not await _open_main():
		return
	Cz.middle_press(_root(), _world_point())
	Cz.middle_motion(_root(), Vector2(20.0, 0.0), _world_point() + Vector2(20.0, 0.0))
	assert_bool(Cz.panning(_camera)).is_true()
	Cz.focus_out(_camera)
	assert_bool(Cz.panning(_camera)).is_false()
	var pivot: Vector3 = Cam.t_pivot(_camera)
	Cz.focus_in(_camera)
	Cz.middle_motion(_root(), Vector2(60.0, 40.0), _world_point() + Vector2(80.0, 40.0))
	assert_vector(Cam.t_pivot(_camera)).is_equal_approx(pivot, Vector3.ONE * 0.000001)
	Cz.middle_release(_root(), _world_point())


func test_ac20_the_pan_ends_when_the_window_loses_the_focus() -> void:
	if not await _open_main():
		return
	Cz.middle_press(_root(), _world_point())
	Cz.middle_motion(_root(), Vector2(20.0, 0.0), _world_point() + Vector2(20.0, 0.0))
	assert_bool(Cz.panning(_camera)).is_true()
	Cz.focus_out(_camera, true)
	assert_bool(Cz.panning(_camera)).is_false()
	var pivot: Vector3 = Cam.t_pivot(_camera)
	Cz.focus_in(_camera, true)
	Cz.middle_motion(_root(), Vector2(60.0, 40.0), _world_point() + Vector2(80.0, 40.0))
	assert_vector(Cam.t_pivot(_camera)).is_equal_approx(pivot, Vector3.ONE * 0.000001)
	Cz.middle_release(_root(), _world_point())


func test_ac20_events_that_arrive_while_the_window_is_unfocused_change_nothing() -> void:
	if not await _open_main():
		return
	_move_away_first()
	Cz.focus_out(_camera, true)
	Cz.wheel(_root(), true, 1.0, 0, _world_point())
	Cz.pan(_root(), Vector2(60.0, 40.0), _world_point())
	Cz.home_key(_root())
	assert_bool(Cz.panning(_camera)).is_false()
	_unchanged()
	assert_float(Cam.t_az(_camera)).is_equal_approx(100.0, Cz.ANGLE_DEG)
	Cz.focus_in(_camera, true)
	Cz.wheel(_root(), true, 1.0, 0, _world_point())
	assert_float(Cam.t_dist(_camera)).is_equal_approx(
		_default * Cz.setting("zoom_step_factor"), Cz.LENGTH_M
	)


func test_ac20_a_release_that_never_arrives_does_not_leave_a_stuck_pan() -> void:
	if not await _open_main():
		return
	Cz.middle_press(_root(), _world_point())
	Cz.focus_out(_camera)
	Cz.focus_in(_camera)
	Cam.step(_camera, 1.0)
	Cz.middle_motion(_root(), Vector2(60.0, 40.0), _world_point() + Vector2(60.0, 40.0))
	_unchanged()
	Cz.pan(_root(), Vector2(20.0, 0.0), _world_point())
	assert_float((Cam.t_pivot(_camera) - _home).length()).is_greater(0.001)


func test_ac20_a_pan_together_with_an_orbit_and_a_wheel_stays_clamped_and_does_not_flip() -> void:
	if not await _open_main():
		return
	Cam.set_orbit(_camera, 0.0, 80.0, true)
	var both: int = MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE
	Cam.right_press(_root(), _world_point())
	Cz.middle_press(_root(), _world_point())
	assert_bool(Cam.dragging(_camera)).is_true()
	assert_bool(Cz.panning(_camera)).is_true()
	var failures: PackedStringArray = PackedStringArray()
	for index: int in 12:
		Cam.motion(_root(), Vector2(30.0, -90.0), _world_point(), both)
		Cz.wheel(_root(), index % 2 == 0, 5.0, 0, _world_point())
		Cam.step(_camera, Cz.FRAME_S)
		if Cam.t_el(_camera) > Cam.MAX_ELEVATION_DEG + Cz.ANGLE_DEG:
			failures.append("frame %d: target elevation %s" % [index, Cam.t_el(_camera)])
		if not _pan_box.grow(0.00001).has_point(Cam.pivot(_camera)):
			failures.append("frame %d: pivot %s outside the box" % [index, Cam.pivot(_camera)])
		var low: float = Cz.zoom_in_distance(_default) - Cz.LENGTH_M
		var high: float = Cz.zoom_out_distance(_default) + Cz.LENGTH_M
		if Cam.t_dist(_camera) < low or Cam.t_dist(_camera) > high:
			failures.append("frame %d: distance %s" % [index, Cam.t_dist(_camera)])
		for problem: String in Cam.basis_failures(_camera, Cam.pivot(_camera)):
			failures.append("frame %d: %s" % [index, problem])
	Cam.right_release(_root(), _world_point())
	Cz.middle_release(_root(), _world_point())
	assert_array(failures).override_failure_message(Cz.summary(failures)).is_empty()
	assert_bool(Cam.dragging(_camera)).is_false()
	assert_bool(Cz.panning(_camera)).is_false()
	Cam.settle(_camera)
	assert_float(Cam.t_el(_camera)).is_less_equal(Cam.MAX_ELEVATION_DEG + Cz.ANGLE_DEG)
	assert_array(Cam.basis_failures(_camera, Cam.pivot(_camera))).is_empty()


func test_ac20_an_orbit_drag_alone_still_does_not_pan_and_a_pan_alone_does_not_orbit() -> void:
	if not await _open_main():
		return
	var az: float = Cam.t_az(_camera)
	var el: float = Cam.t_el(_camera)
	Cam.drag(_root(), Vector2(50.0, 30.0), _world_point())
	assert_vector(Cam.t_pivot(_camera)).is_equal_approx(_home, Vector3.ONE * 0.000001)
	assert_float(Cam.t_dist(_camera)).is_equal_approx(_default, Cz.LENGTH_M)
	var orbited_az: float = Cam.t_az(_camera)
	var orbited_el: float = Cam.t_el(_camera)
	assert_float(orbited_az).is_not_equal(az)
	Cz.pan(_root(), Vector2(50.0, 30.0), _world_point())
	assert_float(Cam.t_az(_camera)).is_equal_approx(orbited_az, Cz.ANGLE_DEG)
	assert_float(Cam.t_el(_camera)).is_equal_approx(orbited_el, Cz.ANGLE_DEG)
	assert_float(el).is_not_equal(orbited_el)
