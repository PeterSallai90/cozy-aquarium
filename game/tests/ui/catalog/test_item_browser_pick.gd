# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #30 criteria 14 to 18, picking (owner: developer): the Selected mark, EventBus.item_picked and
## item_pick_cleared with their counts and arguments (a listener is connected to the autoload), the
## re-pick, the pick that survives filtering, clear_pick(), model_reset (clears) against
## EventBus.tank_displayed and a ChangeTankCommand (do not), and that a pick changes neither the
## model, the save nor the history. Tank controls on fixture items (item_browser_rig.gd).

const Ir := preload("res://tests/helpers/item_browser_rig.gd")
const Ui := preload("res://tests/helpers/tank_ui_rig.gd")
const ModelState := preload("res://tests/helpers/model_state.gd")
const Table := preload("res://tests/helpers/tank_table.gd")
const Rig := preload("res://tests/helpers/room_rig.gd")

var _saved_locale: String = ""
var _language_state: Dictionary = {}
var _translations: Array[Translation] = []
var _model: AquariumModel = null
var _history: CommandHistory = null
var _controls: Control = null
var _listener: Ir.Listener = null


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()
	_language_state = Ui.begin_language_isolation("item_browser_pick")
	_translations = Ir.add_translations()
	TranslationServer.set_locale("en")
	_history = CommandHistory.new()
	_model = Ui.furnished_model(Table.MEDIUM)
	_listener = Ir.listen()


func after_test() -> void:
	Ir.unlisten(_listener)
	Ir.remove_translations(_translations)
	Ui.end_language_isolation(_language_state, _saved_locale)


func _open() -> bool:
	_controls = await Ir.open(self, _model, Ir.catalog(), _history)
	auto_free(_controls)
	var ok: bool = _controls != null and Ir.open_button(_controls) != null
	assert_bool(ok).override_failure_message("TankControls has no ItemsButton").is_true()
	if not ok:
		return false
	await Ir.press_open(self, _controls)
	assert_bool(Ir.is_open(_controls)).override_failure_message("the panel did not open").is_true()
	return Ir.is_open(_controls)


func _panel_call(method: String) -> void:
	var panel: Control = Ir.panel(_controls)
	(
		assert_bool(panel != null and panel.has_method(method))
		. override_failure_message("ItemBrowser.%s() is missing" % method)
		. is_true()
	)
	if panel != null and panel.has_method(method):
		panel.call(method)


func _empty_model() -> AquariumModel:
	return AquariumModel.new("2026-11-02T08:00:00Z")


# --- AC 18: the signals ---


func test_ac18_the_event_bus_has_the_two_pick_signals() -> void:
	assert_bool(EventBus.has_signal("item_picked")).is_true()
	assert_bool(EventBus.has_signal("item_pick_cleared")).is_true()


func test_ac18_the_pick_signals_are_the_only_route_no_browser_signal_carries_the_pick() -> void:
	if not await _open():
		return
	var panel: Control = Ir.panel(_controls)
	var names: Array[String] = []
	for entry: Dictionary in panel.get_script().get_script_signal_list():
		names.append(String(entry["name"]))
	assert_array(names).not_contains(["item_picked"])
	assert_array(names).not_contains(["item_pick_cleared"])


# --- AC 14: a pick ---


func test_ac14_clicking_a_card_marks_it_and_emits_one_item_picked_with_its_id() -> void:
	if not await _open():
		return
	Ir.click_card(_controls, &"rock_slate")
	assert_that(_listener.picked).is_equal([&"rock_slate"])
	assert_int(_listener.cleared).is_equal(0)
	assert_that(Ir.marked_ids(_controls)).is_equal(["rock_slate"])
	assert_str(Ir.picked_id(_controls)).is_equal("rock_slate")


func test_ac14_the_mark_is_a_text_on_the_card_not_only_a_colour() -> void:
	if not await _open():
		return
	Ir.click_card(_controls, &"rock_slate")
	var mark: Label = Ir.card_part(_controls, &"rock_slate", "SelectedLabel") as Label
	assert_object(mark).is_not_null()
	assert_bool(mark.is_visible_in_tree()).is_true()
	assert_str(Ir.shown(mark)).is_equal("Selected")
	(
		assert_bool(Ir.card_part(_controls, &"rock_granite", "SelectedLabel").is_visible_in_tree())
		. is_false()
	)


func test_ac14_no_card_is_marked_before_a_pick() -> void:
	if not await _open():
		return
	assert_that(Ir.marked_ids(_controls)).is_equal([])
	assert_str(Ir.picked_id(_controls)).is_equal("")
	assert_that(_listener.timeline).is_equal([])


func test_ac14_the_signal_carries_the_catalog_id_as_a_string_name() -> void:
	if not await _open():
		return
	Ir.click_card(_controls, &"plant_fern")
	assert_int(_listener.picked.size()).is_equal(1)
	assert_int(typeof(_listener.picked[0])).is_equal(TYPE_STRING_NAME)
	assert_that(_listener.picked[0]).is_equal(&"plant_fern")


func test_ac14_every_card_can_be_picked_and_gives_its_own_id() -> void:
	if not await _open():
		return
	for id: String in Ir.order_ids():
		Ir.click_card(_controls, StringName(id))
		assert_that(Ir.marked_ids(_controls)).is_equal([id])
	assert_int(_listener.picked.size()).is_equal(9)
	assert_int(_listener.cleared).is_equal(0)


func test_ac14_a_pick_changes_neither_the_model_nor_the_save_nor_the_history() -> void:
	if not await _open():
		return
	var model_before: Dictionary = ModelState.snapshot(_model)
	var saved: SaveResult = SaveCodec.new().encode(_model, "2026-11-02T08:00:00Z")
	Ir.click_card(_controls, &"rock_slate")
	Ir.click_card(_controls, &"wood_drift")
	Ir.click_card(_controls, &"wood_drift")
	assert_dict(ModelState.snapshot(_model)).is_equal(model_before)
	assert_int(_history.get_undo_count()).is_equal(0)
	assert_bool(_history.can_undo()).is_false()
	var saved_after: SaveResult = SaveCodec.new().encode(_model, "2026-11-02T08:00:00Z")
	assert_str(saved_after.text).is_equal(saved.text)


func test_ac14_the_pick_is_not_stored_in_the_model_json() -> void:
	if not await _open():
		return
	Ir.click_card(_controls, &"rock_slate")
	var saved: SaveResult = SaveCodec.new().encode(_model, "2026-11-02T08:00:00Z")
	assert_str(saved.text).not_contains("rock_slate")


# --- AC 15: another card, the marked card again ---


func test_ac15_picking_another_card_marks_only_the_new_one_and_emits_no_clear() -> void:
	if not await _open():
		return
	Ir.click_card(_controls, &"rock_slate")
	Ir.click_card(_controls, &"wood_root")
	assert_that(Ir.marked_ids(_controls)).is_equal(["wood_root"])
	assert_that(_listener.timeline).is_equal(["picked:rock_slate", "picked:wood_root"])
	assert_int(_listener.cleared).is_equal(0)
	assert_str(Ir.picked_id(_controls)).is_equal("wood_root")


func test_ac15_picking_the_marked_card_again_clears_the_pick_and_emits_one_clear() -> void:
	if not await _open():
		return
	Ir.click_card(_controls, &"rock_slate")
	Ir.click_card(_controls, &"rock_slate")
	assert_that(Ir.marked_ids(_controls)).is_equal([])
	assert_str(Ir.picked_id(_controls)).is_equal("")
	assert_that(_listener.timeline).is_equal(["picked:rock_slate", "cleared"])


func test_ac15_picking_the_same_card_three_times_picks_clears_and_picks_again() -> void:
	if not await _open():
		return
	for _round: int in 3:
		Ir.click_card(_controls, &"plant_fern")
	assert_that(_listener.timeline).is_equal(["picked:plant_fern", "cleared", "picked:plant_fern"])
	assert_that(Ir.marked_ids(_controls)).is_equal(["plant_fern"])


# --- AC 16: the pick survives filtering, clear_pick() ---


func test_ac16_changing_the_category_keeps_the_pick_and_the_mark_returns() -> void:
	if not await _open():
		return
	Ir.click_card(_controls, &"rock_slate")
	Ir.select_category(_controls, "Category_wood")
	assert_that(Ir.marked_ids(_controls)).is_equal([])
	assert_str(Ir.picked_id(_controls)).is_equal("rock_slate")
	Ir.select_category(_controls, "Category_rock")
	assert_that(Ir.marked_ids(_controls)).is_equal(["rock_slate"])
	assert_that(_listener.timeline).is_equal(["picked:rock_slate"])


func test_ac16_searching_keeps_the_pick_and_the_mark_returns() -> void:
	if not await _open():
		return
	Ir.click_card(_controls, &"rock_slate")
	Ir.type_text(_controls, "fern")
	assert_that(Ir.visible_ids(_controls)).is_equal(["plant_fern"])
	assert_that(Ir.marked_ids(_controls)).is_equal([])
	assert_str(Ir.picked_id(_controls)).is_equal("rock_slate")
	Ir.type_text(_controls, "")
	assert_that(Ir.marked_ids(_controls)).is_equal(["rock_slate"])
	assert_that(_listener.timeline).is_equal(["picked:rock_slate"])


func test_ac16_a_search_with_no_match_keeps_the_pick() -> void:
	if not await _open():
		return
	Ir.click_card(_controls, &"rock_slate")
	Ir.type_text(_controls, "zzz")
	Ir.type_text(_controls, "slate")
	assert_that(Ir.marked_ids(_controls)).is_equal(["rock_slate"])
	assert_int(_listener.cleared).is_equal(0)


func test_ac16_clear_pick_clears_the_pick_and_emits_one_clear() -> void:
	if not await _open():
		return
	Ir.click_card(_controls, &"rock_slate")
	_panel_call("clear_pick")
	assert_that(Ir.marked_ids(_controls)).is_equal([])
	assert_str(Ir.picked_id(_controls)).is_equal("")
	assert_that(_listener.timeline).is_equal(["picked:rock_slate", "cleared"])


func test_ac16_clear_pick_clears_a_pick_that_is_not_listed_now() -> void:
	if not await _open():
		return
	Ir.click_card(_controls, &"rock_slate")
	Ir.select_category(_controls, "Category_plant")
	_panel_call("clear_pick")
	assert_int(_listener.cleared).is_equal(1)
	Ir.select_category(_controls, "Category_rock")
	assert_that(Ir.marked_ids(_controls)).is_equal([])


func test_ac16_clear_pick_without_a_pick_emits_nothing() -> void:
	if not await _open():
		return
	_panel_call("clear_pick")
	assert_that(_listener.timeline).is_equal([])


func test_ac16_clear_pick_twice_emits_only_once() -> void:
	if not await _open():
		return
	Ir.click_card(_controls, &"rock_slate")
	_panel_call("clear_pick")
	_panel_call("clear_pick")
	assert_int(_listener.cleared).is_equal(1)


func test_ac16_after_clear_pick_the_same_card_can_be_picked_again() -> void:
	if not await _open():
		return
	Ir.click_card(_controls, &"rock_slate")
	_panel_call("clear_pick")
	Ir.click_card(_controls, &"rock_slate")
	assert_that(_listener.timeline).is_equal(["picked:rock_slate", "cleared", "picked:rock_slate"])
	assert_that(Ir.marked_ids(_controls)).is_equal(["rock_slate"])


func test_ac16_clear_pick_works_while_the_panel_is_closed() -> void:
	if not await _open():
		return
	Ir.click_card(_controls, &"rock_slate")
	Ir.close_button(_controls).pressed.emit()
	await get_tree().process_frame
	_panel_call("clear_pick")
	assert_int(_listener.cleared).is_equal(1)
	await Ir.press_open(self, _controls)
	assert_that(Ir.marked_ids(_controls)).is_equal([])


# --- AC 17: model_reset clears, a tank swap does not ---


func test_ac17_model_reset_clears_the_pick_and_emits_one_clear() -> void:
	if not await _open():
		return
	Ir.click_card(_controls, &"rock_slate")
	_model.reset_from(_empty_model())
	assert_that(_listener.timeline).is_equal(["picked:rock_slate", "cleared"])
	assert_that(Ir.marked_ids(_controls)).is_equal([])
	assert_str(Ir.picked_id(_controls)).is_equal("")


func test_ac17_model_reset_without_a_pick_emits_nothing() -> void:
	if not await _open():
		return
	_model.reset_from(_empty_model())
	assert_that(_listener.timeline).is_equal([])


func test_ac17_model_reset_clears_the_pick_while_the_panel_is_closed() -> void:
	if not await _open():
		return
	Ir.click_card(_controls, &"wood_drift")
	Ir.close_button(_controls).pressed.emit()
	await get_tree().process_frame
	_model.reset_from(_empty_model())
	assert_int(_listener.cleared).is_equal(1)
	assert_str(Ir.picked_id(_controls)).is_equal("")


func test_ac17_two_model_resets_emit_one_clear() -> void:
	if not await _open():
		return
	Ir.click_card(_controls, &"rock_slate")
	_model.reset_from(_empty_model())
	_model.reset_from(_empty_model())
	assert_int(_listener.cleared).is_equal(1)


func test_ac17_a_tank_displayed_signal_does_not_clear_the_pick() -> void:
	if not await _open():
		return
	Ir.click_card(_controls, &"rock_slate")
	EventBus.emit_signal("tank_displayed", Table.LARGE)
	await get_tree().process_frame
	assert_int(_listener.cleared).is_equal(0)
	assert_that(Ir.marked_ids(_controls)).is_equal(["rock_slate"])
	assert_str(Ir.picked_id(_controls)).is_equal("rock_slate")


func test_ac17_a_change_tank_command_does_not_clear_the_pick() -> void:
	if not await _open():
		return
	Ir.click_card(_controls, &"rock_slate")
	var swap: ChangeTankCommand = ChangeTankCommand.new(
		_model, Rig.default_catalog() as TankCatalog, Table.LARGE
	)
	assert_bool(_history.execute(swap)).is_true()
	await get_tree().process_frame
	assert_that(_model.get_tank_id()).is_equal(Table.LARGE)
	assert_int(_listener.cleared).is_equal(0)
	assert_that(_listener.timeline).is_equal(["picked:rock_slate"])
	assert_that(Ir.marked_ids(_controls)).is_equal(["rock_slate"])


func test_ac17_a_pick_made_after_a_reset_is_a_normal_pick() -> void:
	if not await _open():
		return
	Ir.click_card(_controls, &"rock_slate")
	_model.reset_from(_empty_model())
	Ir.click_card(_controls, &"rock_slate")
	assert_that(_listener.timeline).is_equal(["picked:rock_slate", "cleared", "picked:rock_slate"])
