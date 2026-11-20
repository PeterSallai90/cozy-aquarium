extends GdUnitTestSuite
## #31 hand-forward 2 and AC 15 (owner: developer): the item browser answers
## EventBus.item_pick_clear_requested with its existing clear_pick(): exactly one item_pick_cleared
## when there was a pick, nothing when there was none (#30 AC 16). The browser is the only owner of
## the pick; placement only asks. Also: the browser takes its catalog from a shared
## ItemCatalogSource when TankControls.setup() gets one (sixth argument, plan section 1) and the
## source loads on the first open only.
## Test decisions: the panel is built alone with setup(model, items) and a card is clicked by
## emitting pressed (the item_browser_rig contract); the source test goes through the real
## TankControls with the sixth argument, falling back to the five-argument call so a missing
## parameter fails an assertion instead of an engine error.

const Browser := preload("res://tests/helpers/item_browser_rig.gd")
const Api := preload("res://tests/helpers/placement_api.gd")
const Rig := preload("res://tests/helpers/room_rig.gd")
const Ui := preload("res://tests/helpers/tank_ui_rig.gd")

var _listener: Browser.Listener = null
var _saved_locale: String = ""
var _language_state: Dictionary = {}


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()
	_language_state = Ui.begin_language_isolation("browser_clear_request")
	_listener = Browser.listen()


func after_test() -> void:
	Browser.unlisten(_listener)
	Ui.end_language_isolation(_language_state, _saved_locale)


func _have_signal() -> bool:
	var found: bool = EventBus.has_signal("item_pick_clear_requested")
	(
		assert_bool(found)
		. override_failure_message("EventBus.item_pick_clear_requested is missing")
		. is_true()
	)
	return found


func _panel() -> Control:
	var panel: Control = Browser.panel_alone(AquariumModel.new(), Browser.catalog())
	add_child(panel)
	auto_free(panel)
	return panel


func test_a_clear_request_clears_the_pick_with_one_item_pick_cleared() -> void:
	if not _have_signal():
		return
	var panel: Control = _panel()
	await get_tree().process_frame
	panel.call("focus_start", false)
	await get_tree().process_frame
	var card: Button = panel.find_child("Card_rock_granite", true, false) as Button
	assert_object(card).is_not_null()
	card.pressed.emit()
	assert_str(str(panel.call("get_picked_id"))).is_equal("rock_granite")
	var state_before: int = _listener.cleared
	EventBus.emit_signal("item_pick_clear_requested")
	assert_str(str(panel.call("get_picked_id"))).is_equal("")
	assert_int(_listener.cleared).is_equal(state_before + 1)


func test_a_clear_request_without_a_pick_emits_nothing() -> void:
	if not _have_signal():
		return
	var panel: Control = _panel()
	await get_tree().process_frame
	panel.call("focus_start", false)
	await get_tree().process_frame
	var state_before: int = _listener.cleared
	EventBus.emit_signal("item_pick_clear_requested")
	assert_int(_listener.cleared).is_equal(state_before)
	assert_str(str(panel.call("get_picked_id"))).is_equal("")


func test_two_requests_in_a_row_emit_one_clear() -> void:
	if not _have_signal():
		return
	var panel: Control = _panel()
	await get_tree().process_frame
	panel.call("focus_start", false)
	await get_tree().process_frame
	var card: Button = panel.find_child("Card_rock_granite", true, false) as Button
	card.pressed.emit()
	var state_before: int = _listener.cleared
	EventBus.emit_signal("item_pick_clear_requested")
	EventBus.emit_signal("item_pick_clear_requested")
	assert_int(_listener.cleared).is_equal(state_before + 1)


func test_the_browser_loads_the_shared_source_on_the_first_open_only() -> void:
	if not Api.exists(Api.SOURCE):
		assert_bool(false).override_failure_message("ItemCatalogSource is missing").is_true()
		return
	var source: RefCounted = Api.new_source()
	var model: AquariumModel = AquariumModel.new()
	var controls: Control = (load(Ui.CONTROLS_SCENE) as PackedScene).instantiate() as Control
	var script: Script = controls.get_script() as Script
	var arguments: int = 0
	for entry: Dictionary in script.get_script_method_list():
		if entry["name"] == &"setup":
			arguments = (entry["args"] as Array).size()
	(
		assert_int(arguments)
		. override_failure_message("TankControls.setup() has no sixth parameter (item source)")
		. is_greater_equal(6)
	)
	if arguments < 6:
		controls.free()
		return
	controls.call("setup", model, Rig.default_catalog(), CommandHistory.new(), null, null, source)
	add_child(controls)
	auto_free(controls)
	await get_tree().process_frame
	assert_int(source.call("get_load_count")).is_equal(0)
	await Browser.press_open(self, controls)
	assert_int(source.call("get_load_count")).is_equal(1)
	assert_object(Browser.card(controls, &"river_stone")).is_not_null()
	Browser.click_card(controls, &"river_stone")
	assert_str(Browser.picked_id(controls)).is_equal("river_stone")
	assert_int(source.call("get_load_count")).is_equal(1)
