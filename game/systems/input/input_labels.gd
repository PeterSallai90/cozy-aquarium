class_name InputLabels
extends RefCounted
## Key labels for tooltips and hints, read from the live input map so a remapped key (#81) stays
## correct.

const NO_KEY_LABEL: String = "?"


## The label of the first key event of the action, with its modifiers: the logical label when the
## event binds a keycode, the physical label otherwise; "?" when there is none.
static func primary_label(action: StringName) -> String:
	if not InputMap.has_action(action):
		return NO_KEY_LABEL
	for event: InputEvent in InputMap.action_get_events(action):
		var key: InputEventKey = event as InputEventKey
		if key != null:
			if key.keycode != 0:
				return key.as_text_keycode()
			return key.as_text_physical_keycode()
	return NO_KEY_LABEL
