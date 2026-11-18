extends GdUnitTestSuite
## #28 criterion 16, world input (owner: developer; ADR 0008, BA decision Q10 d): the substrate
## panel is non-modal. It does not join the world_input_blockers group, a press on it never starts
## an orbit or pan, a drag that started in the world keeps working over it and ends on the release
## anywhere, Q/E/R/F keep working while it is open, and Esc closes it without moving the camera.
## Run inside the real Main scene next to the HUD, like test_build_camera_routing.gd (pattern and
## helpers), with the camera driven by step() only.

const Cam := preload("res://tests/helpers/camera_rig.gd")
const Ui := preload("res://tests/helpers/tank_ui_rig.gd")
const Sui := preload("res://tests/helpers/substrate_ui_rig.gd")
const OrbitApi := preload("res://tests/helpers/orbit_api.gd")

const MAIN_SCENE := "res://scenes/main.tscn"
const HUGE := 1000000.0

var _saved_locale: String = ""
var _language_state: Dictionary = {}
var _main: Node = null
var _controls: Control = null
var _camera: Camera3D = null
var _saved_window_size: Vector2i = Vector2i.ZERO


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()
	_language_state = Ui.begin_language_isolation("substrate_input")
	_saved_window_size = Vector2i.ZERO


func after_test() -> void:
	if _saved_window_size != Vector2i.ZERO:
		get_tree().root.size = _saved_window_size
	Ui.end_language_isolation(_language_state, _saved_locale)


## Main with the substrate panel open; false (and a failed assert) while a part is missing.
func _open_main_with_panel() -> bool:
	var scene: PackedScene = load(MAIN_SCENE) as PackedScene
	_main = scene.instantiate()
	_saved_window_size = get_tree().root.size
	get_tree().root.size = Cam.SIZE_16_9
	add_child(_main)
	auto_free(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	_controls = _main.get_node("Hud/TankControls") as Control
	_camera = Cam.camera_of(_main.get_node("RoomCorner"))
	(
		assert_bool(_camera != null and Sui.open_button(_controls) != null)
		. override_failure_message("BuildCamera or the Substrate button is missing")
		. is_true()
	)
	if _camera == null or Sui.open_button(_controls) == null:
		return false
	Cam.freeze(_main.get_node("RoomCorner"))
	await Sui.press_open(self, _controls)
	assert_bool(Sui.is_open(_controls)).override_failure_message("the panel did not open").is_true()
	return Sui.is_open(_controls)


func _root() -> Viewport:
	return get_viewport()


func _world_point() -> Vector2:
	var size: Vector2 = _root().get_visible_rect().size
	return Vector2(size.x * 0.8, size.y * 0.7)


func _panel_point() -> Vector2:
	return Sui.panel(_controls).get_global_rect().get_center()


func _wait() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func test_ac16_the_panel_is_not_in_the_world_input_blockers_and_does_not_block() -> void:
	if not await _open_main_with_panel():
		return
	assert_bool(Sui.panel(_controls).is_in_group(OrbitApi.blocker_group())).is_false()
	for node: Node in Sui.panel(_controls).find_children("*", "Control", true, false):
		assert_bool(node.is_in_group(OrbitApi.blocker_group())).is_false()
	assert_that(OrbitApi.is_blocked(get_tree())).is_equal(false)


func test_ac16_the_panel_and_its_buttons_stop_the_mouse() -> void:
	if not await _open_main_with_panel():
		return
	assert_int(Sui.panel(_controls).mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	for button: Button in Sui.cards(_controls) + Sui.swatches(_controls):
		(
			assert_int(button.mouse_filter)
			. override_failure_message("%s does not stop the mouse" % button.name)
			. is_equal(Control.MOUSE_FILTER_STOP)
		)
	assert_bool(WorldInput.is_over_stop_control(_main, _panel_point())).is_true()


func test_ac16_the_world_point_is_free_of_stopping_hud_controls() -> void:
	if not await _open_main_with_panel():
		return
	var hud: Node = _main.get_node("Hud")
	for node: Node in hud.find_children("*", "Control", true, false):
		var control: Control = node as Control
		if control.is_visible_in_tree() and control.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			(
				assert_bool(control.get_global_rect().has_point(_world_point()))
				. override_failure_message("%s covers the world point" % control.name)
				. is_false()
			)


func test_ac16_a_press_on_the_panel_never_starts_an_orbit_or_pan() -> void:
	if not await _open_main_with_panel():
		return
	var az: float = Cam.t_az(_camera)
	var el: float = Cam.t_el(_camera)
	var pivot: Vector3 = Cam.t_pivot(_camera)
	Cam.right_press(_root(), _panel_point())
	assert_bool(Cam.dragging(_camera)).is_false()
	Cam.motion(_root(), Vector2(60.0, 40.0), _panel_point() + Vector2(60.0, 40.0))
	Cam.motion(_root(), Vector2(300.0, 200.0), _world_point())
	assert_bool(Cam.dragging(_camera)).is_false()
	Cam.right_release(_root(), _world_point())
	assert_float(Cam.t_az(_camera)).is_equal(az)
	assert_float(Cam.t_el(_camera)).is_equal(el)
	assert_vector(Cam.t_pivot(_camera)).is_equal(pivot)


func test_ac16_a_drag_started_in_the_world_keeps_orbiting_over_the_panel() -> void:
	if not await _open_main_with_panel():
		return
	Cam.right_press(_root(), _world_point())
	assert_bool(Cam.dragging(_camera)).is_true()
	var before: float = Cam.t_az(_camera)
	Cam.motion(_root(), Vector2(-40.0, 0.0), _panel_point())
	assert_float(absf(Cam.t_az(_camera) - before)).is_equal_approx(10.0, Cam.ANGLE_TOLERANCE_DEG)
	Cam.motion(_root(), Vector2(-40.0, 0.0), _panel_point() + Vector2(5.0, 5.0))
	assert_float(absf(Cam.t_az(_camera) - before)).is_equal_approx(20.0, Cam.ANGLE_TOLERANCE_DEG)
	assert_bool(Cam.dragging(_camera)).is_true()


func test_ac16_a_release_over_the_panel_ends_the_world_drag() -> void:
	if not await _open_main_with_panel():
		return
	Cam.right_press(_root(), _world_point())
	Cam.motion(_root(), Vector2(-40.0, 0.0), _panel_point())
	Cam.right_release(_root(), _panel_point())
	assert_bool(Cam.dragging(_camera)).is_false()
	var az: float = Cam.t_az(_camera)
	Cam.motion(_root(), Vector2(200.0, 100.0), _world_point())
	assert_float(Cam.t_az(_camera)).is_equal(az)


func test_ac16_a_world_drag_orbits_normally_with_the_panel_open() -> void:
	if not await _open_main_with_panel():
		return
	var before: float = Cam.t_el(_camera)
	Cam.drag(_root(), Vector2(0.0, -40.0), _world_point())
	assert_float(Cam.t_el(_camera)).is_equal_approx(before + 10.0, Cam.ANGLE_TOLERANCE_DEG)


func test_ac16_q_e_r_f_keep_working_with_the_panel_open() -> void:
	if not await _open_main_with_panel():
		return
	var az: float = Cam.t_az(_camera)
	var el: float = Cam.t_el(_camera)
	Cam.tap(_root(), KEY_E)
	assert_float(Cam.t_az(_camera)).is_equal_approx(az - 45.0, Cam.ANGLE_TOLERANCE_DEG)
	Cam.tap(_root(), KEY_Q)
	assert_float(Cam.t_az(_camera)).is_equal_approx(az, Cam.ANGLE_TOLERANCE_DEG)
	Cam.tap(_root(), KEY_R)
	assert_float(Cam.t_el(_camera)).is_equal_approx(el + 5.0, Cam.ANGLE_TOLERANCE_DEG)
	Cam.tap(_root(), KEY_F)
	assert_float(Cam.t_el(_camera)).is_equal_approx(el, Cam.ANGLE_TOLERANCE_DEG)
	assert_bool(Sui.is_open(_controls)).is_true()


func test_ac16_escape_closes_the_panel_and_does_not_move_the_camera_or_the_model() -> void:
	if not await _open_main_with_panel():
		return
	var az: float = Cam.t_az(_camera)
	var el: float = Cam.t_el(_camera)
	var model: AquariumModel = _main.call("get_model") as AquariumModel
	var colour: Color = model.get_substrate_colour()
	Cam.tap(_root(), KEY_ESCAPE)
	await _wait()
	assert_bool(Sui.is_open(_controls)).is_false()
	assert_float(Cam.t_az(_camera)).is_equal(az)
	assert_float(Cam.t_el(_camera)).is_equal(el)
	assert_that(model.get_substrate_colour()).is_equal(colour)
	var history: CommandHistory = _main.get("history") as CommandHistory
	assert_bool(history.can_undo()).is_false()


func test_ac16_opening_and_closing_the_panel_does_not_move_the_camera() -> void:
	if not await _open_main_with_panel():
		return
	var az: float = Cam.t_az(_camera)
	var el: float = Cam.t_el(_camera)
	Sui.close_button(_controls).pressed.emit()
	await _wait()
	assert_float(Cam.t_az(_camera)).is_equal(az)
	assert_float(Cam.t_el(_camera)).is_equal(el)
