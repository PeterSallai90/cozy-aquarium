extends GdUnitTestSuite
## #31 Input section and AC 12, 28 (owner: developer): the three placement actions of the input map
## (ADR 0008 rule 5 and Amendment 1 rule 7): place_primary is the left mouse button;
## place_rotate_left is physical Comma and place_rotate_right physical Period, one event each, no
## modifier and no Shift variant, deadzone 0.5 like the camera actions. The existing test that no
## two actions share a binding keeps covering collisions.

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
	assert_int(events.size()).override_failure_message("%s: one event" % action).is_equal(1)
	if events.size() != 1:
		return
	var key: InputEventKey = events[0] as InputEventKey
	assert_bool(key != null).is_true()
	if key == null:
		return
	assert_int(key.physical_keycode).is_equal(keycode)
	assert_int(key.keycode).is_equal(0)
	var modified: bool = (
		key.ctrl_pressed or key.shift_pressed or key.alt_pressed or key.meta_pressed
	)
	assert_bool(modified).is_false()
	assert_float(InputMap.action_get_deadzone(action)).is_equal_approx(DEADZONE, 0.0001)


func test_place_primary_is_the_left_mouse_button() -> void:
	var events: Array[InputEvent] = _events("place_primary")
	assert_int(events.size()).is_equal(1)
	if events.size() != 1:
		return
	var button: InputEventMouseButton = events[0] as InputEventMouseButton
	assert_bool(button != null).is_true()
	if button == null:
		return
	assert_int(button.button_index).is_equal(MOUSE_BUTTON_LEFT)
	assert_float(InputMap.action_get_deadzone("place_primary")).is_equal_approx(DEADZONE, 0.0001)


func test_place_rotate_left_is_physical_comma() -> void:
	_assert_key("place_rotate_left", KEY_COMMA)


func test_place_rotate_right_is_physical_period() -> void:
	_assert_key("place_rotate_right", KEY_PERIOD)


func test_the_three_placement_actions_are_the_only_actions_with_the_place_prefix() -> void:
	var found: Array[String] = []
	for action: StringName in InputMap.get_actions():
		if String(action).begins_with("place_"):
			found.append(String(action))
	found.sort()
	assert_array(found).is_equal(["place_primary", "place_rotate_left", "place_rotate_right"])


func test_the_camera_actions_do_not_use_comma_period_or_the_left_button() -> void:
	for action: StringName in InputMap.get_actions():
		if not String(action).begins_with("camera_"):
			continue
		for event: InputEvent in InputMap.action_get_events(action):
			var key: InputEventKey = event as InputEventKey
			if key != null:
				assert_bool(key.physical_keycode in [KEY_COMMA, KEY_PERIOD]).is_false()
			var button: InputEventMouseButton = event as InputEventMouseButton
			if button != null:
				assert_int(button.button_index).is_not_equal(MOUSE_BUTTON_LEFT)
