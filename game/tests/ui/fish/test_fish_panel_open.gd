extends GdUnitTestSuite
## #36 panel open and close (owner: developer): TankControls gets a "FishButton" right after the
## Items button and a hidden "FishPanel". The fish panel and the item browser are mutually
## exclusive (opening one closes the other); Escape closes the panel and the focus returns to the
## Fish button; the Close button closes it; with no tank displayed the button is disabled and the
## panel closed; opening the panel asks placement to clear an active pick through
## EventBus.item_pick_clear_requested (no new signal, nothing placed). The first species is
## preselected on open.

const Fp := preload("res://tests/helpers/fish_panel_rig.gd")
const Ir := preload("res://tests/helpers/item_browser_rig.gd")
const Ui := preload("res://tests/helpers/tank_ui_rig.gd")

var _saved_locale: String = ""
var _language_state: Dictionary = {}
var _clear_requests: int = 0


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()
	_language_state = Ui.begin_language_isolation("fish_panel_open")
	TranslationServer.set_locale("en")
	_clear_requests = 0
	EventBus.item_pick_clear_requested.connect(_on_clear_requested)


func after_test() -> void:
	EventBus.item_pick_clear_requested.disconnect(_on_clear_requested)
	Ui.end_language_isolation(_language_state, _saved_locale)


func _on_clear_requested() -> void:
	_clear_requests += 1


func _open(displayed: StringName = Fp.TANK) -> Control:
	var model: AquariumModel = Fp.model_with_tank()
	var controls: Control = await Fp.open_controls(self, model, null, null, displayed)
	assert_object(controls).override_failure_message("TankControls scene is missing").is_not_null()
	if controls != null:
		auto_free(controls)
	return controls


func _have(controls: Control) -> bool:
	if controls == null:
		return false
	var found: bool = Fp.button_of(controls) != null and Fp.panel_of(controls) != null
	(
		assert_bool(found)
		. override_failure_message("TankControls has no FishButton or no FishPanel")
		. is_true()
	)
	return found


func test_36_the_panel_is_hidden_until_the_fish_button_is_pressed() -> void:
	var controls: Control = await _open()
	if not _have(controls):
		return
	assert_bool(Fp.is_open(controls)).is_false()
	await Fp.press_open(self, controls)
	assert_bool(Fp.is_open(controls)).is_true()


func test_36_the_fish_button_sits_right_after_the_items_button_with_the_translated_text() -> void:
	var controls: Control = await _open()
	if not _have(controls):
		return
	var items: Button = Ir.open_button(controls)
	var fish: Button = Fp.button_of(controls)
	assert_object(fish.get_parent()).is_same(items.get_parent())
	assert_int(fish.get_index()).is_equal(items.get_index() + 1)
	assert_str(Fp.shown(fish)).is_equal("Fish")
	await Ui.set_language(self, "hu")
	assert_str(Fp.shown(fish)).is_equal("Halak")


func test_36_opening_the_fish_panel_closes_the_item_browser() -> void:
	var controls: Control = await _open()
	if not _have(controls):
		return
	await Ir.press_open(self, controls)
	assert_bool(Ir.is_open(controls)).is_true()
	await Fp.press_open(self, controls)
	assert_bool(Fp.is_open(controls)).is_true()
	assert_bool(Ir.is_open(controls)).is_false()


func test_36_opening_the_item_browser_closes_the_fish_panel() -> void:
	var controls: Control = await _open()
	if not _have(controls):
		return
	await Fp.press_open(self, controls)
	await Ir.press_open(self, controls)
	assert_bool(Ir.is_open(controls)).is_true()
	assert_bool(Fp.is_open(controls)).is_false()


func test_36_escape_closes_the_panel_and_the_focus_returns_to_the_fish_button() -> void:
	var controls: Control = await _open()
	if not _have(controls):
		return
	await Fp.press_open(self, controls)
	Ui.tap(controls, KEY_ESCAPE)
	await Fp.frames(self)
	assert_bool(Fp.is_open(controls)).is_false()
	assert_object(Fp.focus_owner(controls)).is_same(Fp.button_of(controls))


func test_36_the_close_button_closes_the_panel() -> void:
	var controls: Control = await _open()
	if not _have(controls):
		return
	await Fp.press_open(self, controls)
	assert_object(Fp.close_button(controls)).is_not_null()
	await Fp.click(self, Fp.close_button(controls))
	assert_bool(Fp.is_open(controls)).is_false()


func test_36_with_no_tank_the_fish_button_is_disabled() -> void:
	var controls: Control = await _open(&"")
	if not _have(controls):
		return
	assert_bool(Fp.button_of(controls).disabled).is_true()


func test_36_a_tank_enables_the_button_and_losing_it_disables_it_and_closes_the_panel() -> void:
	var controls: Control = await _open()
	if not _have(controls):
		return
	assert_bool(Fp.button_of(controls).disabled).is_false()
	await Fp.press_open(self, controls)
	assert_bool(Fp.is_open(controls)).is_true()
	EventBus.tank_displayed.emit(&"")
	await Fp.frames(self)
	assert_bool(Fp.button_of(controls).disabled).is_true()
	assert_bool(Fp.is_open(controls)).is_false()
	EventBus.tank_displayed.emit(Fp.TANK)
	await Fp.frames(self)
	assert_bool(Fp.button_of(controls).disabled).is_false()


func test_36_opening_the_panel_asks_placement_to_clear_the_pick() -> void:
	var controls: Control = await _open()
	if not _have(controls):
		return
	await Fp.press_open(self, controls)
	assert_int(_clear_requests).is_equal(1)


func test_36_opening_the_panel_places_nothing_and_adds_no_history_entry() -> void:
	var model: AquariumModel = Fp.model_with_tank()
	var history: CommandHistory = CommandHistory.new()
	var controls: Control = await Fp.open_controls(self, model, null, history)
	if not _have(controls):
		return
	auto_free(controls)
	await Fp.press_open(self, controls)
	assert_int(model.get_item_count()).is_equal(0)
	assert_int(model.get_fish_count()).is_equal(0)
	assert_bool(history.can_undo()).is_false()


func test_36_the_first_catalog_species_is_preselected_on_open() -> void:
	var controls: Control = await _open()
	if not _have(controls):
		return
	await Fp.press_open(self, controls)
	var ids: Array[String] = Fp.species_ids(controls)
	assert_int(ids.size()).is_equal(3)
	assert_str(Fp.selected_species(controls)).is_equal(ids[0])
	assert_bool(Fp.species_buttons(controls)[0].button_pressed).is_true()
