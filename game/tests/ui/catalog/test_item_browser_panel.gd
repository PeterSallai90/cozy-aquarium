# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #30 criteria 1 to 3, opening and closing (owner: developer): the Items button, the panel in the
## TankControls group, one panel at a time in both directions, Close, Esc wherever the focus is
## (search field, Items button, nowhere), Esc with the change-tank dialog open, the dialog rule for
## the button, and the state that survives a close. Tank controls on a fixture item catalog; clicks
## are `pressed` emissions, keys go through the viewport. The contract is in item_browser_rig.gd.

const Ir := preload("res://tests/helpers/item_browser_rig.gd")
const Ui := preload("res://tests/helpers/tank_ui_rig.gd")
const Sui := preload("res://tests/helpers/substrate_ui_rig.gd")
const ModelState := preload("res://tests/helpers/model_state.gd")
const Table := preload("res://tests/helpers/tank_table.gd")

var _saved_locale: String = ""
var _language_state: Dictionary = {}
var _translations: Array[Translation] = []
var _model: AquariumModel = null
var _history: CommandHistory = null
var _controls: Control = null


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()
	_language_state = Ui.begin_language_isolation("item_browser_panel")
	_translations = Ir.add_translations()
	TranslationServer.set_locale("en")
	_history = CommandHistory.new()
	_model = Ui.furnished_model(Table.MEDIUM)


func after_test() -> void:
	Ir.remove_translations(_translations)
	Ui.end_language_isolation(_language_state, _saved_locale)


func _build() -> bool:
	_controls = await Ir.open(self, _model, Ir.catalog(), _history)
	auto_free(_controls)
	var ok: bool = _controls != null and Ir.open_button(_controls) != null
	(
		assert_bool(ok)
		. override_failure_message("TankControls has no ItemsButton (or its setup lacks `items`)")
		. is_true()
	)
	return ok


func _open_panel(by_keyboard: bool = false) -> bool:
	if not await _build():
		return false
	await Ir.press_open(self, _controls, by_keyboard)
	assert_bool(Ir.is_open(_controls)).override_failure_message("the panel did not open").is_true()
	return Ir.is_open(_controls)


func _wait() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


# --- AC 1: the button and the closed panel ---


func test_ac01_the_items_button_is_visible_and_the_panel_is_closed() -> void:
	if not await _build():
		return
	assert_bool(Ir.open_button(_controls).is_visible_in_tree()).is_true()
	assert_object(Ir.panel(_controls)).is_not_null()
	assert_bool(Ir.is_open(_controls)).is_false()


func test_ac01_the_items_button_sits_after_the_tank_and_substrate_buttons() -> void:
	if not await _build():
		return
	var row: Node = Ir.open_button(_controls).get_parent()
	assert_object(Ui.change_button(_controls).get_parent()).is_same(row)
	assert_object(Ui.details_button(_controls).get_parent()).is_same(row)
	assert_object(Sui.open_button(_controls).get_parent()).is_same(row)
	assert_int(Ir.open_button(_controls).get_index()).is_greater(
		Sui.open_button(_controls).get_index()
	)


func test_ac01_the_items_button_shows_the_translated_text() -> void:
	if not await _build():
		return
	assert_str(Ir.shown(Ir.open_button(_controls))).is_equal("Items")


# --- AC 2: opening and toggling ---


func test_ac02_pressing_the_items_button_opens_the_panel() -> void:
	if not await _open_panel():
		return
	assert_bool(Ir.panel(_controls).is_visible_in_tree()).is_true()


func test_ac02_pressing_the_items_button_again_closes_the_panel() -> void:
	if not await _open_panel():
		return
	await Ir.press_open(self, _controls)
	assert_bool(Ir.is_open(_controls)).is_false()


func test_ac02_opening_the_items_panel_closes_each_other_panel() -> void:
	if not await _build():
		return
	var openers: Array[Button] = [
		Ui.change_button(_controls), Ui.details_button(_controls), Sui.open_button(_controls)
	]
	var panels: Array[Control] = [
		Ui.chooser(_controls), Ui.details(_controls), Sui.panel(_controls)
	]
	for index: int in openers.size():
		openers[index].pressed.emit()
		await _wait()
		assert_bool(panels[index].is_visible_in_tree()).is_true()
		await Ir.press_open(self, _controls)
		assert_bool(Ir.is_open(_controls)).is_true()
		assert_bool(panels[index].is_visible_in_tree()).is_false()
		await Ir.press_open(self, _controls)
		assert_bool(Ir.is_open(_controls)).is_false()


func test_ac02_opening_each_other_panel_closes_the_items_panel() -> void:
	if not await _build():
		return
	var openers: Array[Button] = [
		Ui.change_button(_controls), Ui.details_button(_controls), Sui.open_button(_controls)
	]
	var panels: Array[Control] = [
		Ui.chooser(_controls), Ui.details(_controls), Sui.panel(_controls)
	]
	for index: int in openers.size():
		await Ir.press_open(self, _controls)
		assert_bool(Ir.is_open(_controls)).is_true()
		openers[index].pressed.emit()
		await _wait()
		assert_bool(Ir.is_open(_controls)).is_false()
		assert_bool(panels[index].is_visible_in_tree()).is_true()
		openers[index].pressed.emit()
		await _wait()


func test_ac02_only_one_panel_of_the_group_is_open_at_a_time() -> void:
	if not await _build():
		return
	var openers: Array[Button] = [
		Ui.change_button(_controls), Ir.open_button(_controls), Sui.open_button(_controls)
	]
	for opener: Button in openers:
		if opener == Ir.open_button(_controls):
			await Ir.press_open(self, _controls)
		else:
			opener.pressed.emit()
			await _wait()
		var open_count: int = 0
		for panel: Control in [
			Ui.chooser(_controls), Ui.details(_controls), Sui.panel(_controls), Ir.panel(_controls)
		]:
			if panel.is_visible_in_tree():
				open_count += 1
		assert_int(open_count).is_equal(1)


func test_ac02_the_items_button_does_nothing_while_the_change_dialog_is_active() -> void:
	if not await _build():
		return
	Ui.dialog(_controls).call("ask", "tank.large_1.name")
	await _wait()
	assert_bool(Ui.dialog_open(_controls)).is_true()
	await Ir.press_open(self, _controls)
	assert_bool(Ir.is_open(_controls)).is_false()
	assert_bool(Ui.dialog_open(_controls)).is_true()


func test_ac02_the_items_button_does_nothing_with_the_panel_open_and_the_dialog_active() -> void:
	if not await _open_panel():
		return
	Ui.dialog(_controls).call("ask", "tank.large_1.name")
	await _wait()
	await Ir.press_open(self, _controls)
	assert_bool(Ir.is_open(_controls)).is_true()
	assert_bool(Ui.dialog_open(_controls)).is_true()


func test_ac02_opening_the_panel_changes_neither_the_model_nor_the_history() -> void:
	if not await _build():
		return
	var model_before: Dictionary = ModelState.snapshot(_model)
	await Ir.press_open(self, _controls)
	await Ir.press_open(self, _controls)
	assert_dict(ModelState.snapshot(_model)).is_equal(model_before)
	assert_int(_history.get_undo_count()).is_equal(0)


# --- AC 3: closing ---


func test_ac03_the_close_button_closes_the_panel_and_the_focus_returns_to_the_items_button(
) -> void:
	if not await _open_panel():
		return
	Ir.close_button(_controls).pressed.emit()
	await _wait()
	assert_bool(Ir.is_open(_controls)).is_false()
	assert_object(Ir.focus_owner(_controls)).is_same(Ir.open_button(_controls))


func test_ac03_escape_with_the_focus_in_the_search_field_closes_the_panel() -> void:
	if not await _open_panel(true):
		return
	assert_object(Ir.focus_owner(_controls)).is_same(Ir.search(_controls))
	Ui.tap(_controls, KEY_ESCAPE)
	await _wait()
	assert_bool(Ir.is_open(_controls)).is_false()
	assert_object(Ir.focus_owner(_controls)).is_same(Ir.open_button(_controls))


func test_ac03_escape_with_text_in_the_search_field_closes_the_panel_and_keeps_the_text() -> void:
	if not await _open_panel(true):
		return
	Ir.type_text(_controls, "ro")
	Ui.tap(_controls, KEY_ESCAPE)
	await _wait()
	assert_bool(Ir.is_open(_controls)).is_false()
	assert_str(Ir.search(_controls).text).is_equal("ro")


func test_ac03_escape_with_the_focus_on_a_card_closes_the_panel() -> void:
	if not await _open_panel():
		return
	Ir.card(_controls, &"rock_granite").grab_focus()
	Ui.tap(_controls, KEY_ESCAPE)
	await _wait()
	assert_bool(Ir.is_open(_controls)).is_false()
	assert_object(Ir.focus_owner(_controls)).is_same(Ir.open_button(_controls))


func test_ac03_escape_with_the_focus_on_the_items_button_closes_the_panel() -> void:
	if not await _open_panel():
		return
	Ir.open_button(_controls).grab_focus()
	Ui.tap(_controls, KEY_ESCAPE)
	await _wait()
	assert_bool(Ir.is_open(_controls)).is_false()
	assert_object(Ir.focus_owner(_controls)).is_same(Ir.open_button(_controls))


func test_ac03_escape_with_no_focus_closes_the_panel_and_the_focus_returns() -> void:
	if not await _open_panel():
		return
	var focused: Control = Ir.focus_owner(_controls)
	if focused != null:
		focused.release_focus()
	assert_object(Ir.focus_owner(_controls)).is_null()
	Ui.tap(_controls, KEY_ESCAPE)
	await _wait()
	assert_bool(Ir.is_open(_controls)).is_false()
	assert_object(Ir.focus_owner(_controls)).is_same(Ir.open_button(_controls))


func test_ac03_escape_with_the_dialog_open_cancels_the_dialog_and_the_panel_stays() -> void:
	if not await _open_panel():
		return
	Ui.dialog(_controls).call("ask", "tank.large_1.name")
	await _wait()
	assert_bool(Ui.dialog_open(_controls)).is_true()
	Ui.tap(_controls, KEY_ESCAPE)
	await _wait()
	assert_bool(Ui.dialog_open(_controls)).is_false()
	assert_bool(Ir.is_open(_controls)).is_true()


func test_ac03_escape_in_the_search_field_with_the_dialog_open_cancels_the_dialog_first() -> void:
	if not await _open_panel(true):
		return
	Ui.dialog(_controls).call("ask", "tank.large_1.name")
	await _wait()
	Ir.search(_controls).grab_focus()
	Ui.tap(_controls, KEY_ESCAPE)
	await _wait()
	assert_bool(Ui.dialog_open(_controls)).is_false()
	assert_bool(Ir.is_open(_controls)).is_true()


func test_ac03_a_second_escape_after_the_dialog_closes_the_panel() -> void:
	if not await _open_panel():
		return
	Ui.dialog(_controls).call("ask", "tank.large_1.name")
	await _wait()
	Ui.tap(_controls, KEY_ESCAPE)
	await _wait()
	Ui.tap(_controls, KEY_ESCAPE)
	await _wait()
	assert_bool(Ir.is_open(_controls)).is_false()


func test_ac03_closing_never_changes_the_model_or_the_history() -> void:
	if not await _open_panel(true):
		return
	var model_before: Dictionary = ModelState.snapshot(_model)
	Ir.click_card(_controls, &"rock_granite")
	Ui.tap(_controls, KEY_ESCAPE)
	await _wait()
	assert_dict(ModelState.snapshot(_model)).is_equal(model_before)
	assert_int(_history.get_undo_count()).is_equal(0)
	assert_bool(_history.can_undo()).is_false()


func test_ac03_reopening_shows_the_panel_as_it_was_left() -> void:
	if not await _open_panel(true):
		return
	Ir.select_category(_controls, "Category_rock")
	Ir.type_text(_controls, "ro")
	Ir.click_card(_controls, &"rock_osko")
	Ir.close_button(_controls).pressed.emit()
	await _wait()
	await Ir.press_open(self, _controls)
	assert_str(Ir.search(_controls).text).is_equal("ro")
	assert_that(Ir.selected_category_names(_controls)).is_equal(["Category_rock"])
	assert_that(Ir.visible_ids(_controls)).is_equal(["rock_slate", "rock_osko"])
	assert_that(Ir.marked_ids(_controls)).is_equal(["rock_osko"])
	assert_str(Ir.picked_id(_controls)).is_equal("rock_osko")


func test_ac03_the_pick_survives_closing_by_escape_and_by_the_button() -> void:
	if not await _open_panel():
		return
	var listener: Ir.Listener = Ir.listen()
	Ir.click_card(_controls, &"wood_drift")
	Ui.tap(_controls, KEY_ESCAPE)
	await _wait()
	await Ir.press_open(self, _controls)
	Ir.open_button(_controls).pressed.emit()
	await _wait()
	await Ir.press_open(self, _controls)
	assert_str(Ir.picked_id(_controls)).is_equal("wood_drift")
	assert_that(Ir.marked_ids(_controls)).is_equal(["wood_drift"])
	assert_int(listener.cleared).is_equal(0)
	assert_that(listener.picked).is_equal([&"wood_drift"])
	Ir.unlisten(listener)
