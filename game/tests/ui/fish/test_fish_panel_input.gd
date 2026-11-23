extends GdUnitTestSuite
## #36 input pass-through (owner: developer, ADR 0008, pattern of test_item_browser_input.gd): the
## fish panel is not a world input blocker, it stops the mouse over its rectangle (click and wheel
## never reach the camera or placement), a press on it never starts an orbit or pan, and outside it
## the world still orbits. Every interactive child stops the mouse, plain labels ignore it;
## FishNameLabel is the one named exception and stops it too (its tooltip needs mouse events).
## Test decision: the real Main scene next to the HUD.

const Fp := preload("res://tests/helpers/fish_panel_rig.gd")
const Ui := preload("res://tests/helpers/tank_ui_rig.gd")
const Cam := preload("res://tests/helpers/camera_rig.gd")

const MAIN_SCENE := "res://scenes/main.tscn"

var _saved_locale: String = ""
var _language_state: Dictionary = {}
var _saved_window_size: Vector2i = Vector2i.ZERO
var _main: Node = null
var _controls: Control = null
var _camera: Camera3D = null


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()
	_language_state = Ui.begin_language_isolation("fish_panel_input")
	TranslationServer.set_locale("en")
	_saved_window_size = Vector2i.ZERO


func after_test() -> void:
	if _saved_window_size != Vector2i.ZERO:
		get_tree().root.size = _saved_window_size
	Ui.end_language_isolation(_language_state, _saved_locale)


func _open_main() -> bool:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_saved_window_size = get_tree().root.size
	get_tree().root.size = Cam.SIZE_16_9
	add_child(_main)
	auto_free(_main)
	await Fp.frames(self)
	_controls = _main.get_node("Hud/TankControls") as Control
	_camera = Cam.camera_of(_main.get_node("RoomCorner"))
	var ok: bool = _camera != null and Fp.button_of(_controls) != null
	assert_bool(ok).override_failure_message("BuildCamera or the Fish button is missing").is_true()
	if not ok:
		return false
	Cam.freeze(_main.get_node("RoomCorner"))
	await Fp.press_open(self, _controls)
	assert_bool(Fp.is_open(_controls)).override_failure_message("the panel did not open").is_true()
	return Fp.is_open(_controls)


func _panel_point() -> Vector2:
	return Fp.panel_of(_controls).get_global_rect().get_center()


func _world_point() -> Vector2:
	var size: Vector2 = get_viewport().get_visible_rect().size
	return Vector2(size.x * 0.8, size.y * 0.7)


func test_36_the_panel_is_not_a_world_input_blocker() -> void:
	if not await _open_main():
		return
	assert_bool(Fp.panel_of(_controls).is_in_group(WorldInput.BLOCKER_GROUP)).is_false()
	assert_bool(WorldInput.is_blocked(get_tree())).is_false()


func test_36_the_panel_stops_the_mouse_so_click_and_wheel_stay_in_the_panel() -> void:
	if not await _open_main():
		return
	assert_int(Fp.panel_of(_controls).mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	assert_bool(WorldInput.is_over_stop_control(_main, _panel_point())).is_true()


func test_36_outside_the_panel_the_event_passes_through() -> void:
	if not await _open_main():
		return
	assert_bool(WorldInput.is_over_stop_control(_main, _world_point())).is_false()


func test_36_every_button_stops_the_mouse_and_labels_ignore_it() -> void:
	if not await _open_main():
		return
	for node: Node in Fp.panel_of(_controls).find_children("*", "Control", true, false):
		if node is BaseButton:
			assert_int((node as Control).mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
		elif node is Label and node.name == &"FishNameLabel":
			assert_int((node as Control).mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
		elif node is Label:
			assert_int((node as Control).mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


func test_36_a_press_on_the_panel_never_starts_an_orbit_or_pan() -> void:
	if not await _open_main():
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


func test_36_a_world_drag_still_orbits_with_the_panel_open() -> void:
	if not await _open_main():
		return
	var elevation_before: float = Cam.t_el(_camera)
	Cam.drag(get_viewport(), Vector2(0.0, -40.0), _world_point())
	assert_float(Cam.t_el(_camera)).is_equal_approx(
		elevation_before + 10.0, Cam.ANGLE_TOLERANCE_DEG
	)
