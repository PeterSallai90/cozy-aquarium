# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #32 AC 3 (controls part), 5 (button), 7 and 12 (ring rules) (owner: developer):
## ItemActions (game/ui/placement/item_actions.tscn), the Delete button and the Colour row of the
## selected item. setup(model, source) mirrors EventBus.item_selected and item_selection_cleared.
## DeleteButton shows while an item is selected; ColourRow (ColourLabel, Swatches, OriginalButton)
## only for a colourable definition. One dot per swatch, in order: a Button whose normal, hover and
## pressed styles are a StyleBoxFlat with exactly the stored colour, focusable (Tab), with the
## untranslated tooltip "#RRGGBB"; a child Panel named Ring (border only, ignores the mouse) shows
## on the dot equal to the stored colour by to_rgba32() and on no other dot; OriginalButton is
## marked only while has_colour is false; an off-list colour marks nothing. The row is rebuilt
## when the selection changes and the ring follows item_changed. Presses only emit
## EventBus.item_delete_requested and item_colour_requested(has_colour, colour); the node never
## touches the model, never calls grab_focus, and calls get_catalog() only after a selection.
## Hidden while a blocker is up. A focused Delete button that hides releases the focus to the world.
## Test decisions: OriginalButton's mark is a visible child Panel named Ring or button_pressed
## (the plan says "ring/pressed mark"); the 8-swatch worst case is a fixture definition.

const Rig := preload("res://tests/helpers/placement_rig.gd")
const Api := preload("res://tests/helpers/placement_api.gd")
const Edit := preload("res://tests/helpers/edit_api.gd")
const Factory := preload("res://tests/helpers/factory.gd")
const Recorder := preload("res://tests/helpers/signal_recorder.gd")

const WINDOW := Vector2i(1152, 648)
const STONE_UID := "a0000001"
const VASE := "a0000002"
const EIGHT := "a0000003"
const UNKNOWN_UID := "a0000004"
const MANY: StringName = &"many_colours"
const PALETTE: Array[Color] = [
	Color8(0xB5, 0x4A, 0x33),
	Color8(0xD9, 0xA4, 0x41),
	Color8(0xF1, 0xE6, 0xC8),
	Color8(0x4F, 0x6D, 0x8C),
	Color8(0x3E, 0x9E, 0x93),
	Color8(0x2B, 0x2A, 0x33),
	Color8(0x7A, 0x5C, 0x8E),
	Color8(0x8C, 0x9A, 0x4A),
]

var _model: AquariumModel = null
var _source: RefCounted = null
var _viewport: SubViewport = null
var _actions: Control = null
var _delete_requests: int = 0
var _colour_requests: Array = []


func after_test() -> void:
	_disconnect("item_delete_requested", _on_delete)
	_disconnect("item_colour_requested", _on_colour)


func _disconnect(signal_name: String, callback: Callable) -> void:
	if EventBus.has_signal(signal_name) and EventBus.is_connected(signal_name, callback):
		EventBus.disconnect(signal_name, callback)


func _on_delete() -> void:
	_delete_requests += 1


func _on_colour(has_colour: bool, colour: Color) -> void:
	_colour_requests.append([has_colour, colour])


## A catalog with the shipped items and a fixture "many_colours" with 8 swatches.
func _catalog() -> ItemCatalog:
	var list: Array[ItemDefinition] = []
	var shipped: ItemCatalog = ItemCatalog.load_dirs()
	for id: StringName in shipped.get_ids():
		list.append(shipped.get_definition(id))
	var many: ItemDefinition = ItemDefinition.new()
	many.id = MANY
	many.name_key = "item.many_colours.name"
	many.category = ItemDefinition.Category.ORNAMENT
	many.colourable = true
	var swatches: Array[Color] = PALETTE.duplicate()
	many.set("colour_swatches", swatches)
	list.append(many)
	return ItemCatalog.from_definitions(list)


func _make_model() -> AquariumModel:
	var model: AquariumModel = Rig.model()
	Rig.add_item(model, STONE_UID, Rig.STONE, -0.15, 0.0)
	Rig.add_item(model, VASE, Rig.AMPHORA, 0.15, 0.0)
	Rig.add_item(model, EIGHT, MANY, 0.0, 0.1)
	Rig.add_item(model, UNKNOWN_UID, Rig.UNKNOWN, 0.1, 0.1)
	return model


func _open(lazy_source: bool = false) -> bool:
	_model = _make_model()
	_source = Api.new_source() if lazy_source else Api.source_from(_catalog())
	_viewport = SubViewport.new()
	_viewport.size = WINDOW
	add_child(_viewport)
	auto_free(_viewport)
	_actions = Edit.instance(Edit.ACTIONS_SCENE)
	(
		assert_bool(_actions != null)
		. override_failure_message("game/ui/placement/item_actions.tscn is missing")
		. is_true()
	)
	if _actions == null or _source == null:
		return false
	_actions.call("setup", _model, _source)
	_viewport.add_child(_actions)
	var wired: bool = EventBus.has_signal("item_delete_requested")
	wired = wired and EventBus.has_signal("item_colour_requested")
	(
		assert_bool(wired)
		. override_failure_message("EventBus needs item_delete_requested and item_colour_requested")
		. is_true()
	)
	if not wired:
		return false
	EventBus.connect("item_delete_requested", _on_delete)
	EventBus.connect("item_colour_requested", _on_colour)
	_delete_requests = 0
	_colour_requests.clear()
	await _frames()
	return true


func _frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _select(uid: String) -> void:
	EventBus.emit_signal("item_selected", uid)
	await _frames()


func _clear() -> void:
	EventBus.emit_signal("item_selection_cleared")
	await _frames()


func _part(node_name: String) -> Control:
	return _actions.find_child(node_name, true, false) as Control


func _delete_button() -> Button:
	return _part("DeleteButton") as Button


func _row() -> Control:
	return _part("ColourRow")


func _original() -> Button:
	return _part("OriginalButton") as Button


func _dots() -> Array[Button]:
	var found: Array[Button] = []
	var box: Control = _part("Swatches")
	if box == null:
		return found
	for child: Node in box.get_children():
		if child is Button:
			found.append(child as Button)
	return found


func _ring_shown(dot: Control) -> bool:
	var ring: Control = dot.get_node_or_null("Ring") as Control
	return ring != null and ring.visible


func _original_marked() -> bool:
	var button: Button = _original()
	return _ring_shown(button) or button.button_pressed


func _marked_indices() -> Array:
	var marked: Array = []
	var dots: Array[Button] = _dots()
	for index: int in dots.size():
		if _ring_shown(dots[index]):
			marked.append(index)
	return marked


func _click(button: Button) -> void:
	var at: Vector2 = button.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		_viewport.push_input(event)
	await get_tree().process_frame


func _vase_swatches() -> Array[Color]:
	var definition: ItemDefinition = (_source.call("get_catalog") as ItemCatalog).get_definition(
		Rig.AMPHORA
	)
	var list: Array[Color] = []
	var raw: Variant = definition.get("colour_swatches")
	if raw is Array:
		for colour: Color in raw:
			list.append(colour)
	return list


func _colour_vase(colour: Color, has_colour: bool = true) -> void:
	var changed: PlacedItem = _model.get_item(VASE).copy()
	changed.has_colour = has_colour
	changed.colour = colour
	assert_bool(_model.apply_replace_item(changed)).is_true()
	await _frames()


# --- structure ---


func test_ac07_the_node_ignores_the_mouse_and_its_controls_stop_it() -> void:
	if not await _open():
		return
	assert_int(_actions.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_object(_delete_button()).is_not_null()
	assert_object(_row()).is_not_null()
	assert_object(_original()).is_not_null()
	assert_object(_part("ColourLabel")).is_not_null()
	assert_object(_part("Swatches")).is_not_null()
	await _select(VASE)
	assert_int(_delete_button().mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	assert_int(_original().mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	for dot: Button in _dots():
		assert_int(dot.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)


# --- AC 3 and 7: visibility ---


func test_ac03_nothing_is_shown_without_a_selection() -> void:
	if not await _open():
		return
	assert_bool(_delete_button().is_visible_in_tree()).is_false()
	assert_bool(_row().is_visible_in_tree()).is_false()


func test_ac07_a_selection_shows_delete_and_a_non_colourable_item_has_no_colour_row() -> void:
	if not await _open():
		return
	await _select(STONE_UID)
	assert_bool(_delete_button().is_visible_in_tree()).is_true()
	assert_bool(_row().is_visible_in_tree()).is_false()
	assert_str(_delete_button().text).is_not_empty()


func test_ac07_a_colourable_item_shows_the_colour_row_with_the_original_button() -> void:
	if not await _open():
		return
	await _select(VASE)
	assert_bool(_delete_button().is_visible_in_tree()).is_true()
	assert_bool(_row().is_visible_in_tree()).is_true()
	assert_bool(_original().is_visible_in_tree()).is_true()
	assert_str(_original().text).is_not_empty()
	assert_str((_part("ColourLabel") as Label).text).is_not_empty()


func test_ac03_clearing_the_selection_hides_the_delete_button_and_the_colour_row() -> void:
	if not await _open():
		return
	await _select(VASE)
	await _clear()
	assert_bool(_delete_button().is_visible_in_tree()).is_false()
	assert_bool(_row().is_visible_in_tree()).is_false()


func test_ac07_an_item_with_an_unknown_catalog_id_shows_no_colour_row_and_no_error() -> void:
	if not await _open():
		return
	await _select(UNKNOWN_UID)
	assert_bool(_row().is_visible_in_tree()).is_false()
	await _select("ffffffff")
	assert_bool(_row().is_visible_in_tree()).is_false()


func test_ac07_the_controls_hide_while_a_blocker_is_up() -> void:
	if not await _open():
		return
	await _select(VASE)
	var blocker: Control = Control.new()
	blocker.add_to_group(&"world_input_blockers")
	blocker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport.add_child(blocker)
	await _frames()
	assert_bool(_delete_button().is_visible_in_tree()).is_false()
	assert_bool(_row().is_visible_in_tree()).is_false()
	blocker.visible = false
	await _frames()
	assert_bool(_delete_button().is_visible_in_tree()).is_true()
	blocker.free()


# --- AC 7: the dots ---


func test_ac07_one_dot_per_swatch_in_the_order_of_the_definition() -> void:
	if not await _open():
		return
	await _select(VASE)
	var swatches: Array[Color] = _vase_swatches()
	assert_int(swatches.size()).is_greater(0)
	var dots: Array[Button] = _dots()
	assert_int(dots.size()).is_equal(swatches.size())
	for index: int in dots.size():
		for style_name: String in ["normal", "hover", "pressed"]:
			var style: StyleBoxFlat = dots[index].get_theme_stylebox(style_name) as StyleBoxFlat
			(
				assert_object(style)
				. override_failure_message(
					"dot %d has no StyleBoxFlat for %s" % [index, style_name]
				)
				. is_not_null()
			)
			if style != null:
				(
					assert_int(style.bg_color.to_rgba32())
					. override_failure_message("dot %d %s" % [index, style_name])
					. is_equal(swatches[index].to_rgba32())
				)
				(
					assert_bool(style.bg_color == swatches[index])
					. override_failure_message(
						"dot %d %s colour is not the stored colour exactly" % [index, style_name]
					)
					. is_true()
				)


func test_ac07_each_dot_is_a_focusable_button_with_the_hex_code_as_its_tooltip() -> void:
	if not await _open():
		return
	await _select(VASE)
	var swatches: Array[Color] = _vase_swatches()
	var dots: Array[Button] = _dots()
	for index: int in dots.size():
		assert_int(dots[index].focus_mode).is_equal(Control.FOCUS_ALL)
		assert_bool(dots[index].disabled).is_false()
		assert_str(dots[index].tooltip_text).is_equal(
			"#" + swatches[index].to_html(false).to_upper()
		)
		assert_str(dots[index].text).is_empty()


func test_ac07_a_dot_ring_is_a_border_only_panel_that_ignores_the_mouse() -> void:
	if not await _open():
		return
	await _select(VASE)
	var dots: Array[Button] = _dots()
	assert_int(dots.size()).is_greater(0)
	for dot: Button in dots:
		var ring: Panel = dot.get_node_or_null("Ring") as Panel
		assert_object(ring).override_failure_message("every dot needs a Ring panel").is_not_null()
		if ring == null:
			continue
		assert_int(ring.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
		var style: StyleBoxFlat = ring.get_theme_stylebox("panel") as StyleBoxFlat
		assert_object(style).is_not_null()
		if style != null:
			var border: int = style.border_width_left + style.border_width_top
			border += style.border_width_right + style.border_width_bottom
			assert_int(border).override_failure_message("the ring has no border").is_greater(0)
			(
				assert_float(style.bg_color.a)
				. override_failure_message("the ring must not fill the dot")
				. is_equal(0.0)
			)


func test_ac07_a_selection_with_8_swatches_shows_8_dots() -> void:
	if not await _open():
		return
	await _select(EIGHT)
	assert_int(_dots().size()).is_equal(8)
	var dots: Array[Button] = _dots()
	for index: int in 8:
		var style: StyleBoxFlat = dots[index].get_theme_stylebox("normal") as StyleBoxFlat
		assert_int(style.bg_color.to_rgba32()).is_equal(PALETTE[index].to_rgba32())


func test_ac07_the_row_is_rebuilt_when_the_selection_changes() -> void:
	if not await _open():
		return
	await _select(VASE)
	var vase_count: int = _dots().size()
	await _select(EIGHT)
	assert_int(_dots().size()).is_equal(8)
	await _select(STONE_UID)
	assert_bool(_row().is_visible_in_tree()).is_false()
	await _select(VASE)
	assert_int(_dots().size()).is_equal(vase_count)
	await _clear()
	await _select(EIGHT)
	assert_int(_dots().size()).is_equal(8)


# --- AC 12: the ring rules ---


func test_ac12_the_ring_marks_the_dot_equal_to_the_stored_colour_and_no_other() -> void:
	if not await _open():
		return
	var swatches: Array[Color] = _vase_swatches()
	await _colour_vase(swatches[1])
	await _select(VASE)
	assert_array(_marked_indices()).is_equal([1])
	assert_bool(_original_marked()).is_false()
	await _colour_vase(swatches[0])
	assert_array(_marked_indices()).is_equal([0])


func test_ac12_the_comparison_is_by_rgba32() -> void:
	if not await _open():
		return
	var swatches: Array[Color] = _vase_swatches()
	var nearly: Color = Color(swatches[0].r + 0.0004, swatches[0].g, swatches[0].b, 1.0)
	assert_int(nearly.to_rgba32()).is_equal(swatches[0].to_rgba32())
	await _colour_vase(nearly)
	await _select(VASE)
	assert_array(_marked_indices()).is_equal([0])


func test_ac12_original_colour_is_marked_only_while_has_colour_is_false() -> void:
	if not await _open():
		return
	await _select(VASE)
	assert_bool(_original_marked()).is_true()
	assert_array(_marked_indices()).is_empty()
	await _colour_vase(_vase_swatches()[0])
	assert_bool(_original_marked()).is_false()
	await _colour_vase(Color.WHITE, false)
	assert_bool(_original_marked()).is_true()
	assert_array(_marked_indices()).is_empty()


func test_ac12_an_off_list_colour_marks_no_dot_and_not_the_original_button() -> void:
	if not await _open():
		return
	var off_list: Color = Color8(0x01, 0x02, 0x03)
	for swatch: Color in _vase_swatches():
		assert_int(swatch.to_rgba32()).is_not_equal(off_list.to_rgba32())
	await _colour_vase(off_list)
	await _select(VASE)
	assert_array(_marked_indices()).is_empty()
	assert_bool(_original_marked()).is_false()


func test_ac12_a_white_swatch_colour_is_not_confused_with_the_default_colour_of_no_colour() -> void:
	if not await _open():
		return
	await _select(EIGHT)
	assert_bool(_original_marked()).is_true()
	var changed: PlacedItem = _model.get_item(EIGHT).copy()
	changed.has_colour = true
	changed.colour = PALETTE[5]
	_model.apply_replace_item(changed)
	await _frames()
	assert_array(_marked_indices()).is_equal([5])
	assert_bool(_original_marked()).is_false()


func test_ac12_a_model_reset_refreshes_the_ring() -> void:
	if not await _open():
		return
	await _select(VASE)
	assert_bool(_original_marked()).is_true()
	var other: AquariumModel = _make_model()
	var coloured: PlacedItem = other.get_item(VASE).copy()
	coloured.has_colour = true
	coloured.colour = _vase_swatches()[2]
	other.apply_replace_item(coloured)
	_model.reset_from(other)
	await _frames()
	assert_array(_marked_indices()).is_equal([2])
	assert_bool(_original_marked()).is_false()


# --- presses: only requests ---


func test_ac05_the_delete_button_emits_one_delete_request_and_nothing_else() -> void:
	if not await _open():
		return
	await _select(STONE_UID)
	var events: Recorder = Recorder.new()
	events.watch(_model)
	await _click(_delete_button())
	assert_int(_delete_requests).is_equal(1)
	assert_array(_colour_requests).is_empty()
	assert_int(events.count()).is_equal(0)
	assert_int(_model.get_item_count()).is_equal(4)


func test_ac08_a_dot_emits_one_colour_request_with_the_exact_swatch() -> void:
	if not await _open():
		return
	await _select(VASE)
	var swatches: Array[Color] = _vase_swatches()
	var dots: Array[Button] = _dots()
	var events: Recorder = Recorder.new()
	events.watch(_model)
	await _click(dots[swatches.size() - 1])
	assert_int(_colour_requests.size()).is_equal(1)
	assert_bool(_colour_requests[0][0]).is_true()
	assert_bool((_colour_requests[0][1] as Color) == swatches[swatches.size() - 1]).is_true()
	assert_int(_delete_requests).is_equal(0)
	assert_int(events.count()).is_equal(0)
	assert_bool(_model.get_item(VASE).has_colour).is_false()


func test_ac09_the_original_button_emits_a_colour_request_without_colour() -> void:
	if not await _open():
		return
	await _colour_vase(_vase_swatches()[0])
	await _select(VASE)
	await _click(_original())
	assert_int(_colour_requests.size()).is_equal(1)
	assert_bool(_colour_requests[0][0]).is_false()
	assert_bool(_model.get_item(VASE).has_colour).is_true()


func test_ac08_a_press_with_the_keyboard_on_a_focused_dot_emits_the_request() -> void:
	if not await _open():
		return
	await _select(EIGHT)
	var dots: Array[Button] = _dots()
	dots[3].grab_focus()
	assert_bool(dots[3].has_focus()).is_true()
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_ENTER
	event.physical_keycode = KEY_ENTER
	event.pressed = true
	_viewport.push_input(event)
	event = event.duplicate() as InputEventKey
	event.pressed = false
	_viewport.push_input(event)
	await _frames()
	assert_int(_colour_requests.size()).is_equal(1)
	assert_bool((_colour_requests[0][1] as Color) == PALETTE[3]).is_true()


# --- AC 3: focus ---


func test_ac03_a_focused_delete_button_that_hides_releases_the_focus_to_the_world() -> void:
	if not await _open():
		return
	await _select(STONE_UID)
	var button: Button = _delete_button()
	button.grab_focus()
	assert_bool(button.has_focus()).is_true()
	await _clear()
	assert_bool(button.is_visible_in_tree()).is_false()
	assert_bool(button.has_focus()).is_false()
	assert_object(_viewport.gui_get_focus_owner()).is_null()
	await _select(VASE)
	(
		assert_object(_viewport.gui_get_focus_owner())
		. override_failure_message("ItemActions must never grab the focus")
		. is_null()
	)


func test_ac03_a_selection_never_grabs_the_focus() -> void:
	if not await _open():
		return
	await _select(VASE)
	await _select(EIGHT)
	await _select(STONE_UID)
	assert_object(_viewport.gui_get_focus_owner()).is_null()
	var source: String = FileAccess.get_file_as_string("res://ui/placement/item_actions.gd")
	(
		assert_bool(source.contains("grab_focus"))
		. override_failure_message("item_actions.gd must never call grab_focus")
		. is_false()
	)


# --- lazy catalog ---


func test_ac07_the_catalog_loads_after_the_first_selection_and_not_at_the_start() -> void:
	if not await _open(true):
		return
	assert_int(_source.call("get_load_count")).is_equal(0)
	assert_bool(_source.call("is_loaded")).is_false()
	await _select(STONE_UID)
	assert_int(_source.call("get_load_count")).is_equal(1)
	await _select(VASE)
	assert_int(_source.call("get_load_count")).is_equal(1)
