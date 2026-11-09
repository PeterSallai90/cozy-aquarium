# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #24 criteria 24, 25 and 26 (owner: developer): the confirmation dialog before a change that
## would clear contents. Fixture models hold an item, a fish, a sculpted heightmap or nothing. The
## chooser (UI) decides whether to ask; the Command always does the full change. The node names
## are the contract of tests/helpers/tank_ui_rig.gd.

const Api := preload("res://tests/helpers/late_api.gd")
const Rig := preload("res://tests/helpers/room_rig.gd")
const Ui := preload("res://tests/helpers/tank_ui_rig.gd")
const Table := preload("res://tests/helpers/tank_table.gd")
const Factory := preload("res://tests/helpers/factory.gd")
const Recorder := preload("res://tests/helpers/signal_recorder.gd")
const ModelState := preload("res://tests/helpers/model_state.gd")

var _saved_locale: String = ""
var _model: AquariumModel = null
var _catalog: RefCounted = null
var _history: CommandHistory = null
var _controls: Control = null
var _room: Node3D = null


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	_history = CommandHistory.new()
	_catalog = Rig.default_catalog()
	_model = Rig.model_with(Table.MEDIUM)


func after_test() -> void:
	TranslationServer.set_locale(_saved_locale)


func _build_open() -> bool:
	var rig: Dictionary = await Ui.open(self, _model, _catalog, _history)
	_room = rig["room"]
	_controls = rig["controls"]
	auto_free(_room)
	(
		assert_bool(_controls != null)
		. override_failure_message("%s is missing" % Ui.CONTROLS_SCENE)
		. is_true()
	)
	if _controls == null:
		return false
	auto_free(_controls)
	await Ui.open_chooser(self, _controls)
	return Ui.is_open(_controls)


## Opens the chooser on the model and clicks the large tank; true when the dialog is showing.
func _ask() -> bool:
	if not await _build_open():
		return false
	Ui.card(_controls, Table.LARGE).pressed.emit()
	await _wait()
	(
		assert_bool(Ui.dialog_open(_controls))
		. override_failure_message("clicking the large tank did not open the dialog")
		. is_true()
	)
	return Ui.dialog_open(_controls)


func _wait() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _only_items() -> AquariumModel:
	var model: AquariumModel = Rig.model_with(Table.MEDIUM)
	model.apply_insert_item(Factory.item("a0000001"), 0)
	return model


func _only_fish() -> AquariumModel:
	var model: AquariumModel = Rig.model_with(Table.MEDIUM)
	model.apply_insert_fish(Factory.fish("f0000001"), 0)
	return model


func _only_heightmap() -> AquariumModel:
	var model: AquariumModel = Rig.model_with(Table.MEDIUM)
	model.apply_set_heightmap(PackedFloat32Array([0.0, 0.3]), Vector2i(2, 1))
	return model


func _only_zero_heightmap() -> AquariumModel:
	var model: AquariumModel = Rig.model_with(Table.MEDIUM)
	model.apply_set_heightmap(PackedFloat32Array([0.0, 0.0, 0.0, 0.0]), Vector2i(2, 2))
	return model


func _assert_nothing_changed(before: Dictionary) -> void:
	assert_dict(ModelState.snapshot(_model)).is_equal(before)
	assert_int(_history.get_undo_count()).is_equal(0)
	assert_bool(_history.can_undo()).is_false()


# --- AC 24: when the dialog opens ---


func test_ac24_an_item_alone_opens_the_dialog_with_the_new_tank_named_in_the_body() -> void:
	_model = _only_items()
	if not await _ask():
		return
	assert_str(Ui.shown(Ui.dialog(_controls).find_child(Ui.TITLE, true, false) as Label)).is_equal(
		"Change tank?"
	)
	assert_str(Ui.shown(Ui.dialog(_controls).find_child(Ui.BODY, true, false) as Label)).is_equal(
		(
			"Changing to the Large tank will clear everything in this tank: "
			+ "decor, plants, fish and the sand shape."
		)
	)
	assert_str(Ui.shown(Ui.cancel_button(_controls))).is_equal("Cancel")
	assert_str(Ui.shown(Ui.confirm_button(_controls))).is_equal("Change tank")


func test_ac24_a_fish_alone_opens_the_dialog() -> void:
	_model = _only_fish()
	if not await _ask():
		return


func test_ac24_a_sculpted_heightmap_alone_opens_the_dialog() -> void:
	_model = _only_heightmap()
	if not await _ask():
		return


func test_ac24_a_sized_heightmap_of_zeros_counts_as_not_flat_and_opens_the_dialog() -> void:
	_model = _only_zero_heightmap()
	if not await _ask():
		return


func test_ac24_the_dialog_uses_the_name_of_the_clicked_tank_in_hungarian_too() -> void:
	TranslationServer.set_locale("hu")
	_model = _only_items()
	if not await _ask():
		return
	assert_str(Ui.shown(Ui.dialog(_controls).find_child(Ui.TITLE, true, false) as Label)).is_equal(
		"Akvárium cseréje?"
	)
	assert_str(Ui.shown(Ui.dialog(_controls).find_child(Ui.BODY, true, false) as Label)).is_equal(
		(
			"A(z) Nagy akvárium akváriumra váltás mindent kiüríti ebből az akváriumból: "
			+ "dekorációt, növényeket, halakat és a homok formáját."
		)
	)
	assert_str(Ui.shown(Ui.cancel_button(_controls))).is_equal("Mégse")
	assert_str(Ui.shown(Ui.confirm_button(_controls))).is_equal("Csere")


func test_ac24_the_dialog_opens_with_the_focus_on_cancel() -> void:
	_model = _only_items()
	if not await _ask():
		return
	assert_object(Ui.focus_owner(_controls)).is_same(Ui.cancel_button(_controls))


func test_ac24_until_confirm_the_model_is_unchanged_and_there_is_no_history_entry() -> void:
	_model = Ui.furnished_model(Table.MEDIUM)
	var before: Dictionary = ModelState.snapshot(_model)
	var recorder: Recorder = Recorder.new()
	recorder.watch(_model)
	if not await _ask():
		return
	assert_int(recorder.count()).is_equal(0)
	_assert_nothing_changed(before)
	assert_that(Rig.displayed_id(_room)).is_equal(Table.MEDIUM)
	assert_bool(Ui.is_open(_controls)).is_true()


func test_ac24_an_empty_tank_runs_the_command_at_once_without_a_dialog() -> void:
	if not await _build_open():
		return
	var opened: Array[bool] = []
	Ui.card(_controls, Table.LARGE).pressed.emit()
	opened.append(Ui.dialog_open(_controls))
	await _wait()
	opened.append(Ui.dialog_open(_controls))
	assert_array(opened).is_equal([false, false])
	assert_that(_model.get_tank_id()).is_equal(Table.LARGE)
	assert_int(_history.get_undo_count()).is_equal(1)
	assert_bool(Ui.is_open(_controls)).is_false()


func test_ac24_an_already_flat_empty_heightmap_set_explicitly_still_counts_as_empty() -> void:
	_model.apply_set_heightmap(PackedFloat32Array(), Vector2i.ZERO)
	if not await _build_open():
		return
	Ui.card(_controls, Table.LARGE).pressed.emit()
	await _wait()
	assert_bool(Ui.dialog_open(_controls)).is_false()
	assert_that(_model.get_tank_id()).is_equal(Table.LARGE)


# --- AC 25: answering the dialog ---


func test_ac25_cancel_closes_the_dialog_keeps_the_chooser_and_returns_focus_to_the_card() -> void:
	_model = Ui.furnished_model(Table.MEDIUM)
	var before: Dictionary = ModelState.snapshot(_model)
	if not await _ask():
		return
	Ui.cancel_button(_controls).pressed.emit()
	await _wait()
	assert_bool(Ui.dialog_open(_controls)).is_false()
	assert_bool(Ui.is_open(_controls)).is_true()
	assert_object(Ui.focus_owner(_controls)).is_same(Ui.card(_controls, Table.LARGE))
	_assert_nothing_changed(before)


func test_ac25_esc_acts_as_cancel_and_closes_only_the_dialog() -> void:
	_model = Ui.furnished_model(Table.MEDIUM)
	var before: Dictionary = ModelState.snapshot(_model)
	if not await _ask():
		return
	Ui.tap(_controls, KEY_ESCAPE)
	await _wait()
	assert_bool(Ui.dialog_open(_controls)).is_false()
	(
		assert_bool(Ui.is_open(_controls))
		. override_failure_message("Esc closed the chooser as well as the dialog")
		. is_true()
	)
	assert_object(Ui.focus_owner(_controls)).is_same(Ui.card(_controls, Table.LARGE))
	_assert_nothing_changed(before)


func test_ac25_a_second_esc_then_closes_the_chooser() -> void:
	_model = _only_items()
	if not await _ask():
		return
	Ui.tap(_controls, KEY_ESCAPE)
	await _wait()
	Ui.tap(_controls, KEY_ESCAPE)
	await _wait()
	assert_bool(Ui.is_open(_controls)).is_false()
	assert_that(_model.get_tank_id()).is_equal(Table.MEDIUM)


func test_ac25_confirm_by_mouse_runs_the_command_once_and_closes_dialog_and_chooser() -> void:
	_model = Ui.furnished_model(Table.MEDIUM)
	if not await _ask():
		return
	Ui.confirm_button(_controls).pressed.emit()
	await _wait()
	assert_that(_model.get_tank_id()).is_equal(Table.LARGE)
	assert_int(_model.get_item_count()).is_equal(0)
	assert_int(_model.get_fish_count()).is_equal(0)
	assert_int(_model.get_heightmap().size()).is_equal(0)
	assert_int(_history.get_undo_count()).is_equal(1)
	assert_bool(Ui.dialog_open(_controls)).is_false()
	assert_bool(Ui.is_open(_controls)).is_false()
	assert_object(Ui.focus_owner(_controls)).is_same(Ui.change_button(_controls))
	assert_that(Rig.displayed_id(_room)).is_equal(Table.LARGE)


func test_ac25_confirm_by_enter_on_the_focused_button_runs_the_command_once() -> void:
	_model = _only_items()
	if not await _ask():
		return
	Ui.confirm_button(_controls).grab_focus()
	Ui.tap(_controls, KEY_ENTER)
	await _wait()
	assert_that(_model.get_tank_id()).is_equal(Table.LARGE)
	assert_int(_history.get_undo_count()).is_equal(1)
	assert_bool(Ui.is_open(_controls)).is_false()


func test_ac25_confirm_by_space_on_the_focused_button_runs_the_command_once() -> void:
	_model = _only_fish()
	if not await _ask():
		return
	Ui.confirm_button(_controls).grab_focus()
	Ui.tap(_controls, KEY_SPACE)
	await _wait()
	assert_that(_model.get_tank_id()).is_equal(Table.LARGE)
	assert_int(_history.get_undo_count()).is_equal(1)


func test_ac25_enter_on_the_default_focus_cancels_it_never_confirms() -> void:
	_model = _only_items()
	if not await _ask():
		return
	Ui.tap(_controls, KEY_ENTER)
	await _wait()
	assert_bool(Ui.dialog_open(_controls)).is_false()
	assert_that(_model.get_tank_id()).is_equal(Table.MEDIUM)
	assert_int(_history.get_undo_count()).is_equal(0)


func test_ac25_tab_and_shift_tab_move_between_cancel_and_confirm_and_wrap() -> void:
	_model = _only_items()
	if not await _ask():
		return
	var cancel: Button = Ui.cancel_button(_controls)
	var confirm: Button = Ui.confirm_button(_controls)
	assert_object(Ui.focus_owner(_controls)).is_same(cancel)
	Ui.tap(_controls, KEY_TAB)
	assert_object(Ui.focus_owner(_controls)).is_same(confirm)
	Ui.tap(_controls, KEY_TAB)
	assert_object(Ui.focus_owner(_controls)).is_same(cancel)
	Ui.tap(_controls, KEY_TAB, true)
	assert_object(Ui.focus_owner(_controls)).is_same(confirm)
	Ui.tap(_controls, KEY_TAB, true)
	assert_object(Ui.focus_owner(_controls)).is_same(cancel)


func test_ac25_after_a_confirm_undo_brings_everything_back() -> void:
	_model = Ui.furnished_model(Table.MEDIUM)
	var before: Dictionary = ModelState.snapshot(_model)
	if not await _ask():
		return
	Ui.confirm_button(_controls).pressed.emit()
	await _wait()
	assert_bool(_history.undo()).is_true()
	assert_dict(ModelState.snapshot(_model)).is_equal(before)


# --- AC 26: edge cases ---


func test_ac26_a_language_switch_rebuilds_title_body_and_buttons() -> void:
	_model = _only_items()
	if not await _ask():
		return
	TranslationServer.set_locale("hu")
	EventBus.language_changed.emit("hu")
	await _wait()
	assert_bool(Ui.dialog_open(_controls)).is_true()
	assert_str(Ui.shown(Ui.dialog(_controls).find_child(Ui.TITLE, true, false) as Label)).is_equal(
		"Akvárium cseréje?"
	)
	assert_str(Ui.shown(Ui.dialog(_controls).find_child(Ui.BODY, true, false) as Label)).contains(
		"Nagy akvárium"
	)
	assert_str(Ui.shown(Ui.cancel_button(_controls))).is_equal("Mégse")
	assert_str(Ui.shown(Ui.confirm_button(_controls))).is_equal("Csere")


func test_ac26_model_reset_closes_the_dialog_and_the_dialog_does_not_change_the_model() -> void:
	_model = _only_items()
	if not await _ask():
		return
	var replacement: AquariumModel = Rig.model_with(Table.SMALL)
	var after_reset: Dictionary = ModelState.snapshot(replacement)
	_model.reset_from(replacement)
	await _wait()
	assert_bool(Ui.dialog_open(_controls)).is_false()
	assert_dict(ModelState.snapshot(_model)).is_equal(after_reset)
	assert_int(_history.get_undo_count()).is_equal(0)
	assert_that(Rig.displayed_id(_room)).is_equal(Table.SMALL)


func test_ac26_a_second_confirm_creates_no_second_history_entry() -> void:
	_model = _only_items()
	if not await _ask():
		return
	var confirm: Button = Ui.confirm_button(_controls)
	confirm.pressed.emit()
	confirm.pressed.emit()
	await _wait()
	assert_int(_history.get_undo_count()).is_equal(1)
	assert_that(_model.get_tank_id()).is_equal(Table.LARGE)


func test_ac26_while_the_dialog_is_open_a_full_screen_control_stops_the_mouse() -> void:
	_model = _only_items()
	if not await _ask():
		return
	var dimmer: Control = Ui.dialog(_controls).find_child(Ui.DIMMER, true, false) as Control
	assert_object(dimmer).override_failure_message("the dialog has no Dimmer").is_not_null()
	if dimmer == null:
		return
	var screen: Rect2 = _controls.get_viewport().get_visible_rect()
	assert_int(dimmer.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	assert_bool(dimmer.is_visible_in_tree()).is_true()
	(
		assert_bool(dimmer.get_global_rect().encloses(screen))
		. override_failure_message(
			"the Dimmer %s does not cover the screen %s" % [dimmer.get_global_rect(), screen]
		)
		. is_true()
	)


func test_ac26_while_the_dialog_is_open_the_chooser_takes_no_keyboard_focus() -> void:
	_model = _only_items()
	if not await _ask():
		return
	Ui.tap(_controls, KEY_TAB)
	Ui.tap(_controls, KEY_TAB)
	Ui.tap(_controls, KEY_TAB)
	var focused: Control = Ui.focus_owner(_controls)
	(
		assert_bool(Ui.dialog(_controls).is_ancestor_of(focused))
		. override_failure_message("focus left the dialog while it is open")
		. is_true()
	)


func test_ac25_arrow_keys_and_tab_stay_inside_the_change_dialog() -> void:
	_model = _only_items()
	if not await _ask():
		return
	var keys: Dictionary = {
		"ui_up": [KEY_UP, false],
		"ui_down": [KEY_DOWN, false],
		"ui_left": [KEY_LEFT, false],
		"ui_right": [KEY_RIGHT, false],
		"Tab": [KEY_TAB, false],
		"Shift+Tab": [KEY_TAB, true],
	}
	var starts: Array[Button] = [Ui.cancel_button(_controls), Ui.confirm_button(_controls)]
	var escaped: Array[String] = []
	for start: Button in starts:
		for label: String in keys:
			start.grab_focus()
			await _wait()
			var key: Array = keys[label]
			Ui.tap(_controls, key[0] as Key, key[1] as bool)
			await _wait()
			var focused: Control = Ui.focus_owner(_controls)
			var inside: bool = focused == starts[0] or focused == starts[1]
			if not inside:
				escaped.append(
					(
						"%s from %s -> %s"
						% [label, start.name, focused.get_path() if focused else "none"]
					)
				)
	(
		assert_array(escaped)
		. override_failure_message("focus left Cancel/Confirm: %s" % [escaped])
		. is_empty()
	)


func test_ac26_while_the_dialog_is_open_another_panel_cannot_be_opened() -> void:
	_model = _only_items()
	if not await _ask():
		return
	var stub: Control = Control.new()
	stub.visible = false
	_controls.add_child(stub)
	_controls.call("open_panel", stub)
	await _wait()
	assert_bool(stub.visible).is_false()
	assert_bool(Ui.dialog_open(_controls)).is_true()


func test_ac26_after_cancel_another_panel_can_be_opened_again() -> void:
	_model = _only_items()
	if not await _ask():
		return
	Ui.cancel_button(_controls).pressed.emit()
	await _wait()
	var stub: Control = Control.new()
	stub.visible = false
	_controls.add_child(stub)
	_controls.call("open_panel", stub)
	await _wait()
	assert_bool(stub.visible).is_true()
