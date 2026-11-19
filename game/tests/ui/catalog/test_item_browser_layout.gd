extends GdUnitTestSuite
## #30 criterion 22, layout (owner: developer): in a 1152 x 648 viewport (the project's window, no
## minimum size is defined) with the Hungarian texts every label and button fits at least its own
## minimum size inside the panel, the card list scrolls inside the panel and the panel rectangle
## stays inside the window. The viewport is a SubViewport below the suite, so the check works
## headless (pattern of test_substrate_chooser_layout.gd). Pixel style, card size and panel width
## are the owner's judgment on the preview and are not asserted.

const Ir := preload("res://tests/helpers/item_browser_rig.gd")
const Ui := preload("res://tests/helpers/tank_ui_rig.gd")

const TOLERANCE := 0.5

var _saved_locale: String = ""
var _language_state: Dictionary = {}
var _translations: Array[Translation] = []
var _controls: Control = null


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()
	_language_state = Ui.begin_language_isolation("item_browser_layout")
	_translations = Ir.add_translations()
	TranslationServer.set_locale("en")


func after_test() -> void:
	Ir.remove_translations(_translations)
	Ui.end_language_isolation(_language_state, _saved_locale)


## Opens the panel in a 1152 x 648 SubViewport; the first card is picked so the Selected text is
## shown too.
func _open(locale: String, items: ItemCatalog) -> bool:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Ir.WINDOW
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(auto_free(viewport))
	var holder: Node = Node.new()
	viewport.add_child(holder)
	_controls = await Ir.open(holder, AquariumModel.new(), items)
	auto_free(_controls)
	if _controls == null or Ir.open_button(_controls) == null:
		assert_bool(false).override_failure_message("no Items button in TankControls").is_true()
		return false
	if locale != "en":
		await Ui.set_language(self, locale)
	await Ir.press_open(self, _controls)
	assert_bool(Ir.is_open(_controls)).override_failure_message("the panel did not open").is_true()
	if not Ir.is_open(_controls):
		return false
	var first: Array[Button] = Ir.visible_cards(_controls)
	if not first.is_empty():
		first[0].pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	return true


func _screen() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(Ir.WINDOW))


func _inside(rect: Rect2, outer: Rect2, label: String) -> void:
	(
		assert_bool(outer.grow(TOLERANCE).encloses(rect))
		. override_failure_message("%s %s lies outside %s" % [label, rect, outer])
		. is_true()
	)


func _fits_own_minimum(control: Control, label: String) -> void:
	var need: Vector2 = control.get_combined_minimum_size()
	var fits: bool = control.size.x + TOLERANCE >= need.x and control.size.y + TOLERANCE >= need.y
	(
		assert_bool(fits)
		. override_failure_message("%s %s is below its minimum %s" % [label, control.size, need])
		. is_true()
	)


func _fixed_parts() -> Array[Control]:
	var parts: Array[Control] = [
		Ir.title_label(_controls),
		Ir.search(_controls),
		Ir.clear_button(_controls),
		Ir.close_button(_controls),
		Ir.scroll(_controls),
	]
	for button: Button in Ir.categories(_controls):
		if button.is_visible_in_tree():
			parts.append(button)
	return parts


func _check_layout(locale: String, items: ItemCatalog) -> void:
	if not await _open(locale, items):
		return
	assert_vector(_controls.get_viewport().get_visible_rect().size).is_equal(Vector2(Ir.WINDOW))
	var panel_rect: Rect2 = Ir.panel(_controls).get_global_rect()
	_inside(panel_rect, _screen(), "%s panel" % locale)
	for part: Control in _fixed_parts():
		(
			assert_bool(part.is_visible_in_tree())
			. override_failure_message("%s is not visible" % part.name)
			. is_true()
		)
		_inside(part.get_global_rect(), panel_rect, "%s %s in panel" % [locale, part.name])
		_inside(part.get_global_rect(), _screen(), "%s %s" % [locale, part.name])
		_fits_own_minimum(part, "%s %s" % [locale, part.name])
	for button: Button in Ir.cards(_controls):
		for node: Node in button.find_children("*", "Label", true, false):
			_fits_own_minimum(node as Control, "%s %s/%s" % [locale, button.name, node.name])
		_fits_own_minimum(button, "%s %s" % [locale, button.name])


func test_ac22_the_panel_and_its_parts_fit_the_default_window_in_hungarian() -> void:
	await _check_layout("hu", Ir.catalog())


func test_ac22_the_panel_and_its_parts_fit_the_default_window_in_english() -> void:
	await _check_layout("en", Ir.catalog())


func test_ac22_a_hundred_items_in_hungarian_still_fit_and_scroll() -> void:
	await _check_layout("hu", Ir.big_catalog(100))


func test_ac22_the_empty_catalog_text_fits_in_hungarian() -> void:
	var empty: ItemCatalog = ItemCatalog.from_definitions([] as Array[ItemDefinition])
	if not await _open("hu", empty):
		return
	var label: Label = Ir.empty_label(_controls)
	assert_bool(label.is_visible_in_tree()).is_true()
	assert_str(Ir.shown(label)).is_equal("Még nincsenek elemek.")
	_inside(label.get_global_rect(), Ir.panel(_controls).get_global_rect(), "empty text")
	_fits_own_minimum(label, "empty text")


func test_ac22_the_no_match_text_fits_in_hungarian() -> void:
	if not await _open("hu", Ir.catalog()):
		return
	Ir.type_text(_controls, "zzz")
	await get_tree().process_frame
	var label: Label = Ir.empty_label(_controls)
	assert_str(Ir.shown(label)).is_equal("Nincs a keresésnek megfelelő elem.")
	_inside(label.get_global_rect(), Ir.panel(_controls).get_global_rect(), "no match text")
	_fits_own_minimum(label, "no match text")


func test_ac22_the_list_scrolls_inside_the_panel() -> void:
	if not await _open("hu", Ir.big_catalog(100)):
		return
	var scroll: ScrollContainer = Ir.scroll(_controls)
	assert_int(scroll.vertical_scroll_mode).is_not_equal(ScrollContainer.SCROLL_MODE_DISABLED)
	assert_int(scroll.horizontal_scroll_mode).is_equal(ScrollContainer.SCROLL_MODE_DISABLED)
	assert_bool(scroll.is_ancestor_of(Ir.cards_box(_controls))).is_true()
	assert_bool(scroll.is_ancestor_of(Ir.close_button(_controls))).is_false()
	assert_bool(scroll.is_ancestor_of(Ir.search(_controls))).is_false()
	_inside(scroll.get_global_rect(), _screen(), "scroll")
	_inside(scroll.get_global_rect(), Ir.panel(_controls).get_global_rect(), "scroll in panel")
	assert_float(Ir.cards_box(_controls).size.y).is_greater(scroll.size.y)


func test_ac22_the_first_card_lies_inside_the_scroll_area() -> void:
	if not await _open("hu", Ir.catalog()):
		return
	var first: Button = Ir.visible_cards(_controls)[0]
	var scroll: ScrollContainer = Ir.scroll(_controls)
	var area: Rect2 = scroll.get_global_rect().grow(TOLERANCE)
	assert_bool(area.intersects(first.get_global_rect())).is_true()


func test_ac22_the_cards_keep_their_minimum_size_and_do_not_overlap() -> void:
	if not await _open("hu", Ir.catalog()):
		return
	var rects: Array[Rect2] = []
	for button: Button in Ir.cards(_controls):
		_fits_own_minimum(button, button.name)
		rects.append(button.get_global_rect())
	for first: int in rects.size():
		for second: int in range(first + 1, rects.size()):
			(
				assert_bool(rects[first].grow(-TOLERANCE).intersects(rects[second]))
				. override_failure_message("cards %d and %d overlap" % [first, second])
				. is_false()
			)


func test_ac22_the_four_buttons_do_not_overlap_the_panel_or_each_other() -> void:
	if not await _open("hu", Ir.catalog()):
		return
	var panel_rect: Rect2 = Ir.panel(_controls).get_global_rect()
	var rects: Array[Rect2] = []
	for button: Button in [
		Ui.change_button(_controls),
		Ui.details_button(_controls),
		Ir.part(_controls, "SubstrateButton") as Button,
		Ir.open_button(_controls),
	]:
		(
			assert_bool(button.get_global_rect().intersects(panel_rect))
			. override_failure_message("%s overlaps the panel" % button.name)
			. is_false()
		)
		_inside(button.get_global_rect(), _screen(), "%s button" % button.name)
		rects.append(button.get_global_rect())
	for first: int in rects.size():
		for second: int in range(first + 1, rects.size()):
			assert_bool(rects[first].intersects(rects[second])).is_false()
