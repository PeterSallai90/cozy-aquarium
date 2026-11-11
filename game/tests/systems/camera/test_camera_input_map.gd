extends GdUnitTestSuite
## #25 scope (owner: developer): the five camera_ actions of the input map with their bindings
## (ADR 0008 rule 5): right mouse button for the drag, physical Q, E, R and F for the steps, each
## with deadzone 0.5 and no modifiers. Left mouse is not bound to any camera_ action.

const DEADZONE := 0.5


func _events(action: String) -> Array[InputEvent]:
	(
		assert_bool(InputMap.has_action(action))
		. override_failure_message("input action %s is missing" % action)
		. is_true()
	)
	if not InputMap.has_action(action):
		return []
	return InputMap.action_get_events(action)


func _assert_key(action: String, keycode: Key) -> void:
	var events: Array[InputEvent] = _events(action)
	assert_int(events.size()).is_equal(1)
	if events.size() != 1:
		return
	var key: InputEventKey = events[0] as InputEventKey
	assert_bool(key != null).is_true()
	if key == null:
		return
	assert_int(key.physical_keycode).is_equal(keycode)
	var modified: bool = (
		key.ctrl_pressed or key.shift_pressed or key.alt_pressed or key.meta_pressed
	)
	assert_bool(modified).is_false()
	assert_float(InputMap.action_get_deadzone(action)).is_equal_approx(DEADZONE, 0.0001)


func test_camera_orbit_drag_is_the_right_mouse_button() -> void:
	var events: Array[InputEvent] = _events("camera_orbit_drag")
	assert_int(events.size()).is_equal(1)
	if events.size() != 1:
		return
	var button: InputEventMouseButton = events[0] as InputEventMouseButton
	assert_bool(button != null).is_true()
	if button == null:
		return
	assert_int(button.button_index).is_equal(MOUSE_BUTTON_RIGHT)
	var deadzone: float = InputMap.action_get_deadzone("camera_orbit_drag")
	assert_float(deadzone).is_equal_approx(DEADZONE, 0.0001)


func test_camera_orbit_left_is_physical_q() -> void:
	_assert_key("camera_orbit_left", KEY_Q)


func test_camera_orbit_right_is_physical_e() -> void:
	_assert_key("camera_orbit_right", KEY_E)


func test_camera_elevation_up_is_physical_r() -> void:
	_assert_key("camera_elevation_up", KEY_R)


func test_camera_elevation_down_is_physical_f() -> void:
	_assert_key("camera_elevation_down", KEY_F)


func test_ac09_no_camera_action_is_bound_to_the_left_mouse_button() -> void:
	var camera_actions: int = 0
	for action: StringName in InputMap.get_actions():
		if not String(action).begins_with("camera_"):
			continue
		camera_actions += 1
		for event: InputEvent in InputMap.action_get_events(action):
			var button: InputEventMouseButton = event as InputEventMouseButton
			if button != null:
				assert_int(button.button_index).is_not_equal(MOUSE_BUTTON_LEFT)
	assert_int(camera_actions).is_greater_equal(5)
