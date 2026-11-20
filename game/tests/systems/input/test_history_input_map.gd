extends GdUnitTestSuite
## #32 AC 4 and 17 (owner: developer), ADR 0008 Amendment 2 rules 12, 14 and 15: the three new
## input actions. item_delete is physical Delete with no modifier (a world key, positional like
## the camera and rotate keys), deadzone 0.5. history_undo is the logical key Z with Ctrl and
## history_redo is the logical key Y with Ctrl, then the logical key Z with Ctrl and Shift (two
## events, Ctrl+Y first, it is the one shown in tooltips). The letter shortcuts bind `keycode`
## and leave `physical_keycode` at 0: on the Hungarian QWERTZ layout the physical Z position is
## labelled Y, so a physical binding would swap undo and redo for those players. The built-in
## ui_undo and ui_redo stay as the engine ships them (text fields use them). No new action shares
## a binding with another non-ui action.

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


func _key_at(action: String, index: int) -> InputEventKey:
	var events: Array[InputEvent] = _events(action)
	if events.size() <= index:
		(
			assert_bool(false)
			. override_failure_message("%s has no event %d" % [action, index])
			. is_true()
		)
		return null
	var key: InputEventKey = events[index] as InputEventKey
	assert_bool(key != null).is_true()
	return key


func _assert_logical(action: String, index: int, keycode: Key, ctrl: bool, shift: bool) -> void:
	var key: InputEventKey = _key_at(action, index)
	if key == null:
		return
	assert_int(key.keycode).override_failure_message("%s keycode" % action).is_equal(keycode)
	(
		assert_int(key.physical_keycode)
		. override_failure_message("%s must bind the logical key, not the physical one" % action)
		. is_equal(0)
	)
	assert_bool(key.ctrl_pressed).override_failure_message("%s ctrl" % action).is_equal(ctrl)
	assert_bool(key.shift_pressed).override_failure_message("%s shift" % action).is_equal(shift)
	assert_bool(key.alt_pressed).is_false()
	assert_bool(key.meta_pressed).is_false()
	assert_bool(key.command_or_control_autoremap).is_false()


func test_item_delete_is_physical_delete_with_no_modifier() -> void:
	var events: Array[InputEvent] = _events("item_delete")
	assert_int(events.size()).is_equal(1)
	var key: InputEventKey = _key_at("item_delete", 0)
	if key == null:
		return
	assert_int(key.physical_keycode).is_equal(KEY_DELETE)
	assert_int(key.keycode).is_equal(0)
	var modified: bool = (
		key.ctrl_pressed or key.shift_pressed or key.alt_pressed or key.meta_pressed
	)
	assert_bool(modified).is_false()
	if InputMap.has_action("item_delete"):
		assert_float(InputMap.action_get_deadzone("item_delete")).is_equal_approx(DEADZONE, 0.0001)


func test_history_undo_is_ctrl_and_the_logical_key_z() -> void:
	assert_int(_events("history_undo").size()).is_equal(1)
	_assert_logical("history_undo", 0, KEY_Z, true, false)
	if InputMap.has_action("history_undo"):
		assert_float(InputMap.action_get_deadzone("history_undo")).is_equal_approx(DEADZONE, 0.0001)


func test_history_redo_is_ctrl_y_first_and_ctrl_shift_z_second_both_logical() -> void:
	assert_int(_events("history_redo").size()).is_equal(2)
	_assert_logical("history_redo", 0, KEY_Y, true, false)
	_assert_logical("history_redo", 1, KEY_Z, true, true)
	if InputMap.has_action("history_redo"):
		assert_float(InputMap.action_get_deadzone("history_redo")).is_equal_approx(DEADZONE, 0.0001)


func test_a_qwertz_style_event_with_the_physical_y_position_does_not_undo() -> void:
	# On QWERTZ the key at the physical Z position is labelled Y: logical keycode Y, physical Z.
	if not InputMap.has_action("history_undo"):
		assert_bool(false).override_failure_message("history_undo is missing").is_true()
		return
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_Y
	event.physical_keycode = KEY_Z
	event.ctrl_pressed = true
	event.pressed = true
	assert_bool(event.is_action("history_undo", true)).is_false()
	assert_bool(event.is_action("history_redo", true)).is_true()


func test_ctrl_z_with_the_label_z_undoes_on_any_layout() -> void:
	if not InputMap.has_action("history_undo"):
		assert_bool(false).override_failure_message("history_undo is missing").is_true()
		return
	for physical: Key in [KEY_Z, KEY_Y, KEY_NONE]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = KEY_Z
		event.physical_keycode = physical
		event.ctrl_pressed = true
		event.pressed = true
		(
			assert_bool(event.is_action("history_undo", true))
			. override_failure_message("physical %d" % physical)
			. is_true()
		)


func test_exact_match_rejects_extra_modifiers_and_a_bare_letter() -> void:
	if not InputMap.has_action("history_undo"):
		assert_bool(false).override_failure_message("history_undo is missing").is_true()
		return
	var bare: InputEventKey = InputEventKey.new()
	bare.keycode = KEY_Z
	bare.pressed = true
	assert_bool(bare.is_action("history_undo", true)).is_false()
	var alt: InputEventKey = InputEventKey.new()
	alt.keycode = KEY_Z
	alt.ctrl_pressed = true
	alt.alt_pressed = true
	alt.pressed = true
	assert_bool(alt.is_action("history_undo", true)).is_false()
	var shifted: InputEventKey = InputEventKey.new()
	shifted.keycode = KEY_Z
	shifted.ctrl_pressed = true
	shifted.shift_pressed = true
	shifted.pressed = true
	assert_bool(shifted.is_action("history_undo", true)).is_false()
	assert_bool(shifted.is_action("history_redo", true)).is_true()


func test_the_built_in_text_field_undo_and_redo_actions_are_still_there() -> void:
	assert_bool(InputMap.has_action("ui_undo")).is_true()
	assert_bool(InputMap.has_action("ui_redo")).is_true()
	assert_int(InputMap.action_get_events("ui_undo").size()).is_greater(0)
	assert_int(InputMap.action_get_events("ui_redo").size()).is_greater(0)


func test_no_new_action_shares_a_binding_with_another_non_ui_action() -> void:
	var mine: Array[String] = ["item_delete", "history_undo", "history_redo"]
	for action: String in mine:
		if not InputMap.has_action(action):
			assert_bool(false).override_failure_message("%s is missing" % action).is_true()
			return
	for action: StringName in InputMap.get_actions():
		var other: String = String(action)
		if other.begins_with("ui_") or other.begins_with("spatial_editor"):
			continue
		for mine_name: String in mine:
			if mine_name == other:
				continue
			for mine_event: InputEvent in InputMap.action_get_events(mine_name):
				for event: InputEvent in InputMap.action_get_events(action):
					var clash: bool = (
						mine_event.is_match(event, true) or event.is_match(mine_event, true)
					)
					(
						assert_bool(clash)
						. override_failure_message("%s and %s share a binding" % [mine_name, other])
						. is_false()
					)
