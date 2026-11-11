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


# --- #26 (owner: developer): zoom, pan and Home actions ---


func _assert_wheel(action: String, index: MouseButton) -> void:
	var events: Array[InputEvent] = _events(action)
	assert_int(events.size()).is_equal(1)
	if events.size() != 1:
		return
	var button: InputEventMouseButton = events[0] as InputEventMouseButton
	assert_bool(button != null).is_true()
	if button == null:
		return
	assert_int(button.button_index).is_equal(index)
	var modified: bool = (
		button.ctrl_pressed or button.shift_pressed or button.alt_pressed or button.meta_pressed
	)
	assert_bool(modified).is_false()
	assert_float(InputMap.action_get_deadzone(action)).is_equal_approx(DEADZONE, 0.0001)


func test_26_camera_zoom_in_is_the_wheel_up() -> void:
	_assert_wheel("camera_zoom_in", MOUSE_BUTTON_WHEEL_UP)


func test_26_camera_zoom_out_is_the_wheel_down() -> void:
	_assert_wheel("camera_zoom_out", MOUSE_BUTTON_WHEEL_DOWN)


func test_26_camera_pan_drag_is_the_middle_mouse_button() -> void:
	_assert_wheel("camera_pan_drag", MOUSE_BUTTON_MIDDLE)


func test_26_camera_home_is_physical_home() -> void:
	_assert_key("camera_home", KEY_HOME)


func test_26_no_two_actions_share_a_binding() -> void:
	var seen: Dictionary = {}
	for action: StringName in InputMap.get_actions():
		if String(action).begins_with("ui_") or String(action).begins_with("spatial_editor"):
			continue
		for event: InputEvent in InputMap.action_get_events(action):
			var key: String = _binding(event)
			if key.is_empty():
				continue
			(
				assert_bool(seen.has(key))
				. override_failure_message(
					"%s and %s share the binding %s" % [seen.get(key, ""), action, key]
				)
				. is_false()
			)
			seen[key] = String(action)


func test_26_the_camera_actions_avoid_the_reserved_bindings() -> void:
	var camera_actions: int = 0
	for action: StringName in InputMap.get_actions():
		if not String(action).begins_with("camera_"):
			continue
		camera_actions += 1
		for event: InputEvent in InputMap.action_get_events(action):
			var key: InputEventKey = event as InputEventKey
			if key != null:
				for reserved: Key in [KEY_ESCAPE, KEY_P, KEY_Z]:
					assert_int(key.physical_keycode).is_not_equal(reserved)
					assert_int(key.keycode).is_not_equal(reserved)
			var button: InputEventMouseButton = event as InputEventMouseButton
			if button != null:
				assert_int(button.button_index).is_not_equal(MOUSE_BUTTON_LEFT)
	assert_int(camera_actions).is_greater_equal(9)


## One string per physical binding: kind, code and modifiers.
func _binding(event: InputEvent) -> String:
	var modifiers: String = ""
	var key: InputEventKey = event as InputEventKey
	if key != null:
		var code: int = key.physical_keycode if key.physical_keycode != 0 else key.keycode
		modifiers = (
			"%s%s%s%s" % [key.ctrl_pressed, key.shift_pressed, key.alt_pressed, key.meta_pressed]
		)
		return "key:%d:%s" % [code, modifiers]
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null:
		modifiers = (
			"%s%s%s%s"
			% [button.ctrl_pressed, button.shift_pressed, button.alt_pressed, button.meta_pressed]
		)
		return "mouse:%d:%s" % [button.button_index, modifiers]
	return ""
