extends GdUnitTestSuite
## #31 AC 28 (owner: developer): WorldInput.allows_fine_modifier(event) is true when Ctrl, Alt and
## Meta are all up, whatever Shift does (ADR 0008 Amendment 1 rule 7: Shift alone is the one
## allowed modifier of the two rotate actions; Shift with Ctrl, Alt or Meta does nothing).

const Api := preload("res://tests/helpers/placement_api.gd")

## [ctrl, alt, meta, expected] for each of the eight combinations; Shift is tried both ways.
const COMBINATIONS: Array[Array] = [
	[false, false, false, true],
	[true, false, false, false],
	[false, true, false, false],
	[false, false, true, false],
	[true, true, false, false],
	[true, false, true, false],
	[false, true, true, false],
	[true, true, true, false],
]


func _have() -> bool:
	var found: bool = Api.declares_method(WorldInput as Script, "allows_fine_modifier")
	(
		assert_bool(found)
		. override_failure_message("WorldInput.allows_fine_modifier is missing")
		. is_true()
	)
	return found


func _key(ctrl: bool, alt: bool, meta: bool, shift: bool) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = KEY_COMMA
	event.pressed = true
	event.ctrl_pressed = ctrl
	event.alt_pressed = alt
	event.meta_pressed = meta
	event.shift_pressed = shift
	return event


func test_ac28_only_ctrl_alt_and_meta_decide_and_shift_never_matters() -> void:
	if not _have():
		return
	for row: Array in COMBINATIONS:
		for shift: bool in [false, true]:
			var event: InputEventKey = _key(row[0], row[1], row[2], shift)
			var allowed: Variant = (WorldInput as Script).call("allows_fine_modifier", event)
			(
				assert_bool(allowed == row[3])
				. override_failure_message(
					(
						"ctrl %s alt %s meta %s shift %s: expected %s, got %s"
						% [row[0], row[1], row[2], shift, row[3], allowed]
					)
				)
				. is_true()
			)


func test_ac28_it_accepts_any_event_with_modifiers_not_only_keys() -> void:
	if not _have():
		return
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.shift_pressed = true
	assert_bool((WorldInput as Script).call("allows_fine_modifier", click) == true).is_true()
	click.ctrl_pressed = true
	assert_bool((WorldInput as Script).call("allows_fine_modifier", click) == false).is_true()
