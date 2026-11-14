extends GdUnitTestSuite
## #28 criterion 15, layout (owner: developer; BA decision Q6): in a 1152 x 648 viewport (Godot's
## default window, no minimum size is defined) the panel with its five cards lies inside the
## viewport, the swatch row and Close are inside it and visible, and nothing overlaps the three
## tank-control buttons. Content taller than the viewport scrolls inside the panel and the cards
## keep their size. Pixel style and spacing are the owner's judgment, not asserted. The viewport is
## a SubViewport below the suite, so the check works headless (pattern of test_tank_chooser.gd).

const Rig := preload("res://tests/helpers/room_rig.gd")
const Ui := preload("res://tests/helpers/tank_ui_rig.gd")
const Sub := preload("res://tests/helpers/substrate_api.gd")
const Sui := preload("res://tests/helpers/substrate_ui_rig.gd")
const Table := preload("res://tests/helpers/tank_table.gd")

const TOLERANCE := 0.5

var _saved_locale: String = ""
var _language_state: Dictionary = {}
var _controls: Control = null
var _viewport: SubViewport = null


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()
	_language_state = Ui.begin_language_isolation("substrate_layout")
	TranslationServer.set_locale("en")


func after_test() -> void:
	Ui.end_language_isolation(_language_state, _saved_locale)


## Opens the panel in a 1152 x 648 SubViewport.
func _open(locale: String = "en") -> bool:
	_viewport = SubViewport.new()
	_viewport.size = Sui.WINDOW
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(auto_free(_viewport))
	var holder: Node = Node.new()
	_viewport.add_child(holder)
	var model: AquariumModel = Sub.model_with(Sub.SAND, Sub.SAND_DEFAULT, Table.MEDIUM)
	var rig: Dictionary = await Ui.open(holder, model, Rig.default_catalog(), CommandHistory.new())
	auto_free(rig["room"])
	_controls = rig["controls"]
	if _controls == null or Sui.open_button(_controls) == null:
		assert_bool(false).override_failure_message("no Substrate button in TankControls").is_true()
		return false
	auto_free(_controls)
	if locale != "en":
		await Ui.set_language(self, locale)
	await Sui.press_open(self, _controls)
	assert_bool(Sui.is_open(_controls)).override_failure_message("the panel did not open").is_true()
	return Sui.is_open(_controls)


func _inside(rect: Rect2, outer: Rect2, label: String) -> void:
	(
		assert_bool(outer.grow(TOLERANCE).encloses(rect))
		. override_failure_message("%s %s lies outside %s" % [label, rect, outer])
		. is_true()
	)


func _screen() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(Sui.WINDOW))


func _check_layout(locale: String) -> void:
	if not await _open(locale):
		return
	assert_vector(_controls.get_viewport().get_visible_rect().size).is_equal(Vector2(Sui.WINDOW))
	assert_int(Sui.cards(_controls).size()).is_equal(5)
	var panel_rect: Rect2 = Sui.panel(_controls).get_global_rect()
	_inside(panel_rect, _screen(), "%s panel" % locale)
	_inside(Sui.swatch_row(_controls).get_global_rect(), _screen(), "%s swatch row" % locale)
	_inside(
		Sui.swatch_row(_controls).get_global_rect(), panel_rect, "%s swatch row in panel" % locale
	)
	_inside(Sui.close_button(_controls).get_global_rect(), _screen(), "%s Close" % locale)
	_inside(Sui.close_button(_controls).get_global_rect(), panel_rect, "%s Close in panel" % locale)
	for swatch: Button in Sui.swatches(_controls):
		assert_bool(swatch.is_visible_in_tree()).is_true()
		_inside(swatch.get_global_rect(), _screen(), "%s %s" % [locale, swatch.name])
	for button: Button in [
		Ui.change_button(_controls), Ui.details_button(_controls), Sui.open_button(_controls)
	]:
		(
			assert_bool(button.get_global_rect().intersects(panel_rect))
			. override_failure_message("%s overlaps the panel" % button.name)
			. is_false()
		)
		_inside(button.get_global_rect(), _screen(), "%s button" % button.name)


func test_ac15_the_panel_swatch_row_and_close_fit_the_default_window_in_english() -> void:
	await _check_layout("en")


func test_ac15_the_panel_swatch_row_and_close_fit_the_default_window_in_hungarian() -> void:
	await _check_layout("hu")


func test_ac15_the_three_buttons_do_not_overlap_each_other() -> void:
	if not await _open():
		return
	var rects: Array[Rect2] = [
		Ui.change_button(_controls).get_global_rect(),
		Ui.details_button(_controls).get_global_rect(),
		Sui.open_button(_controls).get_global_rect(),
	]
	for first: int in rects.size():
		for second: int in range(first + 1, rects.size()):
			assert_bool(rects[first].intersects(rects[second])).is_false()


func test_ac15_the_cards_keep_their_size_and_do_not_overlap() -> void:
	if not await _open():
		return
	var rects: Array[Rect2] = []
	for button: Button in Sui.cards(_controls):
		var need: Vector2 = button.get_combined_minimum_size()
		(
			assert_float(button.size.y)
			. override_failure_message("%s is squeezed below its minimum height" % button.name)
			. is_greater_equal(need.y - TOLERANCE)
		)
		rects.append(button.get_global_rect())
	for first: int in rects.size():
		for second: int in range(first + 1, rects.size()):
			(
				assert_bool(rects[first].grow(-TOLERANCE).intersects(rects[second]))
				. override_failure_message("cards %d and %d overlap" % [first, second])
				. is_false()
			)


func test_ac15_the_cards_sit_in_a_vertical_scroll_that_is_not_disabled() -> void:
	if not await _open():
		return
	var scroll: ScrollContainer = Sui.scroll(_controls)
	assert_object(scroll).is_not_null()
	if scroll != null:
		assert_int(scroll.vertical_scroll_mode).is_not_equal(ScrollContainer.SCROLL_MODE_DISABLED)
		assert_bool(scroll.is_ancestor_of(Sui.card(_controls, Sub.SAND))).is_true()
		assert_bool(scroll.is_ancestor_of(Sui.swatch_row(_controls))).is_false()
		assert_bool(scroll.is_ancestor_of(Sui.close_button(_controls))).is_false()


func test_ac15_the_visible_cards_lie_inside_the_scroll_area_and_the_scroll_inside_the_screen(
) -> void:
	if not await _open():
		return
	var scroll: ScrollContainer = Sui.scroll(_controls)
	if scroll == null:
		assert_bool(false).override_failure_message("no Scroll").is_true()
		return
	_inside(scroll.get_global_rect(), _screen(), "scroll")
	var first: Button = Sui.cards(_controls)[0]
	var rect: Rect2 = first.get_global_rect()
	assert_bool(scroll.get_global_rect().grow(TOLERANCE).intersects(rect)).is_true()
