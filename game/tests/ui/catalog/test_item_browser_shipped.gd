extends GdUnitTestSuite
## #30 criterion 24 and the first-open load of criterion 23 (owner: developer): the game's tank
## controls get no item catalog (the three- and four-argument setup of today), so the browser loads
## the shipped folders itself on the first open. #30 ships them empty, so the panel shows "All" and
## "No items yet." and nothing else in the list. Once content issues fill the folders, the same
## test checks that the cards are exactly the shipped items instead of the empty state.

const Ir := preload("res://tests/helpers/item_browser_rig.gd")
const Ui := preload("res://tests/helpers/tank_ui_rig.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")

var _saved_locale: String = ""
var _language_state: Dictionary = {}
var _controls: Control = null


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()
	_language_state = Ui.begin_language_isolation("item_browser_shipped")
	TranslationServer.set_locale("en")


func after_test() -> void:
	Ui.end_language_isolation(_language_state, _saved_locale)


func _build() -> bool:
	_controls = await Ir.open_shipped(self, AquariumModel.new())
	auto_free(_controls)
	var ok: bool = _controls != null and Ir.open_button(_controls) != null
	assert_bool(ok).override_failure_message("TankControls has no ItemsButton").is_true()
	return ok


func _shipped_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: StringName in ItemCatalog.load_dirs().get_ids():
		ids.append(String(id))
	return ids


func test_ac24_the_shipped_panel_lists_exactly_the_shipped_items() -> void:
	if not await _build():
		return
	await Ir.press_open(self, _controls)
	assert_bool(Ir.is_open(_controls)).is_true()
	assert_that(Ir.visible_ids(_controls)).is_equal(_shipped_ids())
	assert_that(Ir.all_ids(_controls)).is_equal(_shipped_ids())


func test_ac24_with_the_folders_empty_the_panel_shows_all_and_no_items_yet() -> void:
	if not _shipped_ids().is_empty():
		return
	if not await _build():
		return
	await Ir.press_open(self, _controls)
	assert_that(Ir.visible_category_names(_controls)).is_equal(["Category_all"])
	assert_that(Ir.selected_category_names(_controls)).is_equal(["Category_all"])
	assert_int(Ir.visible_cards(_controls).size()).is_equal(0)
	assert_bool(Ir.empty_label(_controls).is_visible_in_tree()).is_true()
	assert_str(Ir.shown(Ir.empty_label(_controls))).is_equal("No items yet.")
	assert_str(Ir.shown(Ir.category(_controls, "Category_all"))).is_equal("All")


func test_ac24_no_card_exists_before_the_first_open() -> void:
	if not await _build():
		return
	assert_int(Ir.cards_box(_controls).get_child_count()).is_equal(0)


func test_ac24_opening_the_shipped_panel_logs_no_error_or_warning() -> void:
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void:
			if await _build():
				await Ir.press_open(self, _controls)
				Ir.type_text(_controls, "ro")
				Ir.type_text(_controls, "")
	)
	assert_dict(seen["errors"]).is_empty()
	assert_dict(seen["warnings"]).is_empty()
	assert_dict(seen["script_errors"]).is_empty()


func test_ac24_the_shipped_panel_can_be_opened_closed_and_reopened() -> void:
	if not await _build():
		return
	await Ir.press_open(self, _controls)
	Ir.close_button(_controls).pressed.emit()
	await get_tree().process_frame
	assert_bool(Ir.is_open(_controls)).is_false()
	await Ir.press_open(self, _controls)
	assert_bool(Ir.is_open(_controls)).is_true()


func test_ac24_main_shows_the_panel_without_an_item_catalog_injected() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	auto_free(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var controls: Control = main.get_node("Hud/TankControls") as Control
	(
		assert_object(Ir.open_button(controls))
		. override_failure_message("no Items button")
		. is_not_null()
	)
	if Ir.open_button(controls) == null:
		return
	assert_int(Ir.cards_box(controls).get_child_count()).is_equal(0)
	await Ir.press_open(self, controls)
	assert_bool(Ir.is_open(controls)).is_true()
	assert_that(Ir.visible_ids(controls)).is_equal(_shipped_ids())
