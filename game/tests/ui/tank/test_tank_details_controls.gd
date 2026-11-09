# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #117 criteria 11 to 14 (owner: developer): the details button and panel inside the panel group,
## the focus rules (focus returns to the button of the panel that closes), the chooser regression
## and the non-modal and read-only rules. A real room and real controls, like Main wires them.
## Node names: tests/helpers/tank_ui_rig.gd.

const Api := preload("res://tests/helpers/late_api.gd")
const Rig := preload("res://tests/helpers/room_rig.gd")
const Ui := preload("res://tests/helpers/tank_ui_rig.gd")
const Table := preload("res://tests/helpers/tank_table.gd")
const Recorder := preload("res://tests/helpers/signal_recorder.gd")
const ModelState := preload("res://tests/helpers/model_state.gd")

const WINDOW := Vector2i(1280, 720)

var _saved_locale: String = ""
var _language_state: Dictionary = {}
var _model: AquariumModel = null
var _history: CommandHistory = null
var _controls: Control = null
var _room: Node3D = null


## Counts the mouse buttons that no Control consumed.
class WorldListener:
	extends Node
	var presses: int = 0

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			presses += 1


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()
	_language_state = Ui.begin_language_isolation("tank_details_controls")
	_history = CommandHistory.new()
	_model = Rig.model_with(Table.MEDIUM)


func after_test() -> void:
	Ui.end_language_isolation(_language_state, _saved_locale)


func _wait() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


## Room and controls on `_model`; false (and a failed assert) while the panel is missing.
func _build(parent: Node = null) -> bool:
	var rig: Dictionary = await Ui.open(
		parent if parent != null else self, _model, Rig.default_catalog(), _history
	)
	_room = rig["room"]
	_controls = rig["controls"]
	auto_free(_room)
	if _controls != null:
		auto_free(_controls)
	var found: bool = _controls != null and Ui.details(_controls) != null
	(
		assert_bool(found)
		. override_failure_message("the TankDetails panel is missing in %s" % Ui.CONTROLS_SCENE)
		. is_true()
	)
	return found and Ui.details_button(_controls) != null


func _open_details(parent: Node = null) -> bool:
	if not await _build(parent):
		return false
	await Ui.open_details(self, _controls)
	return Ui.details_open(_controls)


func _same_focus(expected: Control) -> void:
	var owner: Control = Ui.focus_owner(_controls)
	(
		assert_bool(owner == expected)
		. override_failure_message(
			(
				"the focus is on %s, expected %s"
				% [
					owner.name if owner != null else "nothing",
					expected.name if expected != null else "nothing"
				]
			)
		)
		. is_true()
	)


# --- AC 11: the panel group ---


func test_ac11_the_details_button_sits_next_to_change_tank_in_one_box() -> void:
	if not await _build():
		return
	var change: Button = Ui.change_button(_controls)
	var details: Button = Ui.details_button(_controls)
	assert_object(details.get_parent()).is_same(change.get_parent())
	assert_bool(change.get_parent() is HBoxContainer).is_true()
	assert_int(details.get_index()).is_greater(change.get_index())
	assert_str(Ui.shown(details)).is_equal("Tank details")


func test_ac11_the_details_button_opens_the_panel_with_the_focus_on_close() -> void:
	if not await _open_details():
		return
	assert_bool(Ui.is_open(_controls)).is_false()
	_same_focus(Ui.details_close_button(_controls))


func test_ac11_pressing_details_while_the_chooser_is_open_swaps_the_panels() -> void:
	if not await _build():
		return
	await Ui.open_chooser(self, _controls)
	assert_bool(Ui.is_open(_controls)).is_true()
	await Ui.open_details(self, _controls)
	assert_bool(Ui.is_open(_controls)).is_false()
	assert_bool(Ui.details_open(_controls)).is_true()
	_same_focus(Ui.details_close_button(_controls))


func test_ac11_pressing_change_tank_while_details_is_open_swaps_back_to_the_card() -> void:
	if not await _open_details():
		return
	await Ui.open_chooser(self, _controls)
	assert_bool(Ui.details_open(_controls)).is_false()
	assert_bool(Ui.is_open(_controls)).is_true()
	_same_focus(Ui.card(_controls, Table.MEDIUM))


func test_ac11_pressing_the_details_button_again_closes_the_panel() -> void:
	if not await _open_details():
		return
	await Ui.open_details(self, _controls)
	assert_bool(Ui.details_open(_controls)).is_false()
	_same_focus(Ui.details_button(_controls))


func test_ac11_only_one_panel_is_open_at_a_time() -> void:
	if not await _build():
		return
	for step: int in 3:
		await Ui.open_chooser(self, _controls)
		await Ui.open_details(self, _controls)
		assert_bool(Ui.is_open(_controls) and Ui.details_open(_controls)).is_false()
		assert_bool(Ui.details_open(_controls)).is_true()


func test_ac11_while_the_change_dialog_is_open_the_details_button_does_nothing() -> void:
	_model = Ui.furnished_model(Table.MEDIUM)
	if not await _build():
		return
	await Ui.open_chooser(self, _controls)
	Ui.card(_controls, Table.LARGE).pressed.emit()
	await _wait()
	assert_bool(Ui.dialog_open(_controls)).is_true()
	var before: Control = Ui.focus_owner(_controls)
	Ui.details_button(_controls).pressed.emit()
	await _wait()
	assert_bool(Ui.details_open(_controls)).is_false()
	assert_bool(Ui.dialog_open(_controls)).is_true()
	_same_focus(before)
	assert_that(_model.get_tank_id()).is_equal(Table.MEDIUM)


# --- AC 12: focus and keys ---


func test_ac12_close_returns_the_focus_to_the_details_button() -> void:
	if not await _open_details():
		return
	Ui.details_close_button(_controls).pressed.emit()
	await _wait()
	assert_bool(Ui.details_open(_controls)).is_false()
	_same_focus(Ui.details_button(_controls))


func test_ac12_escape_closes_the_panel_and_returns_the_focus_to_the_details_button() -> void:
	if not await _open_details():
		return
	Ui.tap(_controls, KEY_ESCAPE)
	await _wait()
	assert_bool(Ui.details_open(_controls)).is_false()
	_same_focus(Ui.details_button(_controls))


func test_ac12_tab_and_shift_tab_stay_on_close() -> void:
	if not await _open_details():
		return
	var close: Button = Ui.details_close_button(_controls)
	Ui.tap(_controls, KEY_TAB)
	await _wait()
	_same_focus(close)
	Ui.tap(_controls, KEY_TAB, true)
	await _wait()
	_same_focus(close)
	assert_bool(Ui.details_open(_controls)).is_true()


func test_ac12_the_close_button_is_the_only_focusable_control_of_the_panel() -> void:
	if not await _open_details():
		return
	for node: Node in Ui.details(_controls).find_children("*", "Control", true, false):
		var control: Control = node as Control
		if control == Ui.details_close_button(_controls):
			continue
		(
			assert_int(control.focus_mode)
			. override_failure_message("%s can take the focus" % control.name)
			. is_equal(Control.FOCUS_NONE)
		)


# --- AC 13: the chooser keeps its behaviour, and the focus follows the opener ---


func test_ac13_the_chooser_opens_on_the_card_of_the_displayed_tank() -> void:
	if not await _build():
		return
	await Ui.open_chooser(self, _controls)
	_same_focus(Ui.card(_controls, Table.MEDIUM))


func test_ac13_chooser_close_and_escape_return_the_focus_to_change_tank() -> void:
	if not await _build():
		return
	await Ui.open_chooser(self, _controls)
	Ui.close_button(_controls).pressed.emit()
	await _wait()
	_same_focus(Ui.change_button(_controls))
	await Ui.open_chooser(self, _controls)
	Ui.tap(_controls, KEY_ESCAPE)
	await _wait()
	assert_bool(Ui.is_open(_controls)).is_false()
	_same_focus(Ui.change_button(_controls))


func test_ac13_chooser_to_details_then_close_focuses_the_details_button() -> void:
	if not await _build():
		return
	await Ui.open_chooser(self, _controls)
	await Ui.open_details(self, _controls)
	Ui.details_close_button(_controls).pressed.emit()
	await _wait()
	assert_bool(Ui.details_open(_controls)).is_false()
	_same_focus(Ui.details_button(_controls))


func test_ac13_details_to_chooser_then_escape_focuses_change_tank() -> void:
	if not await _open_details():
		return
	await Ui.open_chooser(self, _controls)
	Ui.tap(_controls, KEY_ESCAPE)
	await _wait()
	assert_bool(Ui.is_open(_controls)).is_false()
	_same_focus(Ui.change_button(_controls))


func test_ac13_the_opener_is_not_remembered_from_an_earlier_panel() -> void:
	if not await _open_details():
		return
	Ui.tap(_controls, KEY_ESCAPE)
	await _wait()
	await Ui.open_chooser(self, _controls)
	Ui.close_button(_controls).pressed.emit()
	await _wait()
	_same_focus(Ui.change_button(_controls))
	await Ui.open_details(self, _controls)
	Ui.details_close_button(_controls).pressed.emit()
	await _wait()
	_same_focus(Ui.details_button(_controls))


func test_ac13_picking_a_card_on_an_empty_tank_focuses_change_tank() -> void:
	if not await _build():
		return
	await Ui.open_chooser(self, _controls)
	Ui.card(_controls, Table.LARGE).pressed.emit()
	await _wait()
	assert_that(_model.get_tank_id()).is_equal(Table.LARGE)
	assert_bool(Ui.is_open(_controls)).is_false()
	_same_focus(Ui.change_button(_controls))


func test_ac13_picking_the_displayed_tank_closes_and_focuses_change_tank() -> void:
	if not await _build():
		return
	await Ui.open_chooser(self, _controls)
	Ui.card(_controls, Table.MEDIUM).pressed.emit()
	await _wait()
	assert_bool(Ui.is_open(_controls)).is_false()
	_same_focus(Ui.change_button(_controls))


func test_ac13_cancel_in_the_dialog_returns_the_focus_to_the_card() -> void:
	_model = Ui.furnished_model(Table.MEDIUM)
	if not await _build():
		return
	await Ui.open_chooser(self, _controls)
	Ui.card(_controls, Table.LARGE).pressed.emit()
	await _wait()
	assert_bool(Ui.dialog_open(_controls)).is_true()
	Ui.cancel_button(_controls).pressed.emit()
	await _wait()
	assert_bool(Ui.dialog_open(_controls)).is_false()
	assert_bool(Ui.is_open(_controls)).is_true()
	_same_focus(Ui.card(_controls, Table.LARGE))


func test_ac13_confirm_in_the_dialog_changes_the_tank_and_focuses_change_tank() -> void:
	_model = Ui.furnished_model(Table.MEDIUM)
	if not await _build():
		return
	await Ui.open_chooser(self, _controls)
	Ui.card(_controls, Table.LARGE).pressed.emit()
	await _wait()
	Ui.confirm_button(_controls).pressed.emit()
	await _wait()
	assert_that(_model.get_tank_id()).is_equal(Table.LARGE)
	assert_bool(Ui.is_open(_controls)).is_false()
	_same_focus(Ui.change_button(_controls))


func test_ac13_a_stub_panel_without_an_opener_still_returns_to_change_tank() -> void:
	if not await _build():
		return
	var stub: Control = Control.new()
	stub.visible = false
	_controls.add_child(stub)
	_controls.call("open_panel", stub)
	await _wait()
	_controls.call("close_panels")
	await _wait()
	_same_focus(Ui.change_button(_controls))


# --- AC 14: non-modal and read-only ---


func _window() -> SubViewport:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = WINDOW
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(auto_free(viewport))
	return viewport


func test_ac14_the_panel_is_non_modal_no_big_control_swallows_mouse_input() -> void:
	var holder: Node = Node.new()
	_window().add_child(holder)
	if not await _open_details(holder):
		return
	var screen: Rect2 = _controls.get_viewport().get_visible_rect()
	assert_vector(screen.size).is_equal(Vector2(WINDOW))
	for node: Node in _controls.find_children("*", "Control", true, false):
		var control: Control = node as Control
		if not control.is_visible_in_tree() or control.mouse_filter != Control.MOUSE_FILTER_STOP:
			continue
		var area: float = control.get_global_rect().get_area()
		(
			assert_float(area)
			. override_failure_message(
				(
					"%s stops the mouse over %.0f%% of the screen"
					% [control.name, 100.0 * area / screen.get_area()]
				)
			)
			. is_less(screen.get_area() * 0.5)
		)


func test_ac14_a_mouse_press_outside_the_panel_reaches_the_world() -> void:
	var viewport: SubViewport = _window()
	var holder: Node = Node.new()
	viewport.add_child(holder)
	var listener: WorldListener = WorldListener.new()
	holder.add_child(listener)
	if not await _open_details(holder):
		return
	var spot: Vector2 = Vector2(-1.0, -1.0)
	for candidate: Vector2 in [
		Vector2(640, 360), Vector2(640, 100), Vector2(300, 360), Vector2(900, 360)
	]:
		var covered: bool = false
		for node: Node in _controls.find_children("*", "Control", true, false):
			var control: Control = node as Control
			if control.is_visible_in_tree() and control.get_global_rect().has_point(candidate):
				covered = true
		if not covered:
			spot = candidate
			break
	(
		assert_bool(spot.x >= 0.0)
		. override_failure_message("every candidate point lies under the controls")
		. is_true()
	)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = spot
	event.global_position = spot
	viewport.push_input(event)
	await _wait()
	assert_int(listener.presses).is_equal(1)


func test_ac14_opening_refreshing_switching_language_and_closing_change_nothing() -> void:
	if not await _build():
		return
	var before: Dictionary = ModelState.snapshot(_model)
	var recorder: Recorder = Recorder.new()
	recorder.watch(_model)
	await Ui.open_details(self, _controls)
	EventBus.emit_signal("tank_displayed", Table.MEDIUM)
	await _wait()
	await Ui.set_language(self, "hu")
	await Ui.set_language(self, "en")
	Ui.details_close_button(_controls).pressed.emit()
	await _wait()
	await Ui.open_details(self, _controls)
	Ui.tap(_controls, KEY_ESCAPE)
	await _wait()
	assert_int(_history.get_undo_count()).is_equal(0)
	assert_int(_history.get_redo_count()).is_equal(0)
	assert_array(recorder.names()).is_empty()
	assert_dict(ModelState.snapshot(_model)).is_equal(before)
