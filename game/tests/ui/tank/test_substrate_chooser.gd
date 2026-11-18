# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #28 criteria 9 (chooser part), 15, 16, 20, 21 and 23 (owner: developer): the substrate chooser
## panel. A real room and the real tank controls on a fixture model and history; clicks are
## `pressed` emissions, keys go through the viewport. The node names are the contract of
## tests/helpers/substrate_ui_rig.gd. Swatches are addressed by number from the catalog; the only
## hard-coded colour is the Sand default. ADR 0008 input checks are in
## test_substrate_chooser_input.gd, the 1152 x 648 layout in test_substrate_chooser_layout.gd.

const Rig := preload("res://tests/helpers/room_rig.gd")
const Ui := preload("res://tests/helpers/tank_ui_rig.gd")
const Sub := preload("res://tests/helpers/substrate_api.gd")
const Sui := preload("res://tests/helpers/substrate_ui_rig.gd")
const Table := preload("res://tests/helpers/tank_table.gd")

const NAMES_EN: Dictionary = {
	"sand_fine": "Sand",
	"gravel_natural": "Gravel",
	"pebbles_river": "Pebbles",
	"sand_black": "Black sand",
	"gravel_coloured": "Coloured gravel",
}
const DESCRIPTIONS_EN: Dictionary = {
	"sand_fine": "Fine, soft sand for a calm, sunny floor.",
	"gravel_natural": "Small natural stones with a lively, earthy look.",
	"pebbles_river": "Smooth, rounded river stones, like a quiet stream bed.",
	"sand_black": "Dark, fine sand that makes colours glow.",
	"gravel_coloured": "Bright, playful gravel in cheerful colours.",
}

var _saved_locale: String = ""
var _language_state: Dictionary = {}
var _model: AquariumModel = null
var _tanks: RefCounted = null
var _substrates: RefCounted = null
var _history: CommandHistory = null
var _controls: Control = null
var _room: Node3D = null


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()
	_language_state = Ui.begin_language_isolation("substrate_chooser")
	TranslationServer.set_locale("en")
	_history = CommandHistory.new()
	_tanks = Rig.default_catalog()
	_substrates = Sub.catalog()


func after_test() -> void:
	Ui.end_language_isolation(_language_state, _saved_locale)


## Builds the room and the controls on a model with the given substrate (Sand default when none).
func _build(
	id: StringName = Sub.SAND, colour: Color = Sub.SAND_DEFAULT, parent: Node = null
) -> bool:
	_model = Sub.model_with(id, colour, Table.MEDIUM)
	var rig: Dictionary = await Ui.open(
		parent if parent != null else self, _model, _tanks, _history
	)
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
	(
		assert_bool(Sui.open_button(_controls) != null)
		. override_failure_message("TankControls has no %s" % Sui.BUTTON)
		. is_true()
	)
	return Sui.open_button(_controls) != null


func _open(
	id: StringName = Sub.SAND, colour: Color = Sub.SAND_DEFAULT, parent: Node = null
) -> bool:
	if not await _build(id, colour, parent):
		return false
	await Sui.press_open(self, _controls)
	(
		assert_bool(Sui.is_open(_controls))
		. override_failure_message("the Substrate button did not open the chooser")
		. is_true()
	)
	return Sui.is_open(_controls)


## Frees the room and the controls of the last build, so a test can build again.
func _reset_rig() -> void:
	for node: Node in [_controls, _room]:
		if is_instance_valid(node):
			node.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _wait() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _same(actual: Color, expected: Color) -> void:
	(
		assert_bool(Sub.same_colour(actual, expected))
		. override_failure_message("expected %s, got %s" % [Sub.hex(expected), Sub.hex(actual)])
		. is_true()
	)


func _click_card(id: StringName) -> void:
	Sui.card(_controls, id).pressed.emit()
	await _wait()


func _click_swatch(number: int) -> void:
	Sui.swatches(_controls)[number - 1].pressed.emit()
	await _wait()


# --- AC 15: opening ---


func test_ac15_the_substrate_button_sits_after_change_tank_and_tank_info_and_says_substrate(
) -> void:
	if not await _build():
		return
	var button: Button = Sui.open_button(_controls)
	assert_str(Sui.shown(button)).is_equal("Substrate")
	var row: Node = button.get_parent()
	assert_object(Ui.change_button(_controls).get_parent()).is_same(row)
	assert_object(Ui.details_button(_controls).get_parent()).is_same(row)
	assert_int(button.get_index()).is_greater(Ui.details_button(_controls).get_index())
	assert_int(Ui.details_button(_controls).get_index()).is_greater(
		Ui.change_button(_controls).get_index()
	)


func test_ac15_the_panel_is_closed_until_the_button_opens_it() -> void:
	if not await _build():
		return
	assert_object(Sui.panel(_controls)).is_not_null()
	assert_bool(Sui.is_open(_controls)).is_false()
	await Sui.press_open(self, _controls)
	assert_bool(Sui.is_open(_controls)).is_true()
	assert_str(Sui.shown(Sui.title_label(_controls))).is_equal("Choose your substrate")


func test_ac15_it_opens_with_five_cards_in_the_chooser_order() -> void:
	if not await _open():
		return
	assert_int(Sui.cards(_controls).size()).is_equal(5)
	assert_array(Sui.card_ids(_controls)).is_equal(Sub.IDS)


func test_ac15_each_card_shows_name_and_description_in_english() -> void:
	if not await _open():
		return
	for id: StringName in Sub.IDS:
		assert_str(Sui.shown(Sui.card_label(_controls, id, "NameLabel"))).is_equal(NAMES_EN[id])
		assert_str(Sui.shown(Sui.card_label(_controls, id, "DescriptionLabel"))).is_equal(
			DESCRIPTIONS_EN[id]
		)


func test_ac15_the_type_in_use_carries_the_in_use_mark() -> void:
	if not await _open(Sub.PEBBLES, Sub.default_colour(_substrates, Sub.PEBBLES)):
		return
	assert_array(Sui.marked_ids(_controls)).is_equal([Sub.PEBBLES])
	assert_str(Sui.shown(Sui.card_label(_controls, Sub.PEBBLES, "InUseLabel"))).is_equal("In use")


func test_ac15_it_shows_the_swatches_of_the_current_type_in_catalog_order() -> void:
	for id: StringName in Sub.IDS:
		if not await _open(id, Sub.default_colour(_substrates, id)):
			return
		var expected: Array[Color] = Sub.swatches(_substrates, id)
		var shown: Array[Color] = Sui.swatch_colours(_controls)
		assert_int(shown.size()).override_failure_message("%s: swatch count" % id).is_equal(
			expected.size()
		)
		for index: int in mini(shown.size(), expected.size()):
			(
				assert_bool(Sub.same_colour(shown[index], expected[index]))
				. override_failure_message(
					(
						"%s swatch %d shows %s, want %s"
						% [id, index + 1, Sub.hex(shown[index]), Sub.hex(expected[index])]
					)
				)
				. is_true()
			)
		await _reset_rig()


func test_ac15_the_swatch_in_use_is_marked_and_only_that_one() -> void:
	var colour: Color = Sub.swatch(_substrates, Sub.GRAVEL, 3)
	if not await _open(Sub.GRAVEL, colour):
		return
	assert_array(Sui.marked_swatches(_controls)).is_equal([2])


func test_ac15_the_default_swatch_is_marked_for_a_new_sand_floor() -> void:
	if not await _open():
		return
	assert_array(Sui.marked_swatches(_controls)).is_equal([0])
	assert_array(Sui.marked_ids(_controls)).is_equal([Sub.SAND])


func test_ac15_opening_it_closes_the_change_tank_and_tank_info_panels() -> void:
	if not await _build():
		return
	await Ui.open_chooser(self, _controls)
	assert_bool(Ui.is_open(_controls)).is_true()
	await Sui.press_open(self, _controls)
	assert_bool(Sui.is_open(_controls)).is_true()
	assert_bool(Ui.is_open(_controls)).is_false()
	await Ui.open_details(self, _controls)
	assert_bool(Ui.details_open(_controls)).is_true()
	assert_bool(Sui.is_open(_controls)).is_false()
	await Sui.press_open(self, _controls)
	assert_bool(Sui.is_open(_controls)).is_true()
	assert_bool(Ui.details_open(_controls)).is_false()
	assert_bool(Ui.is_open(_controls)).is_false()


func test_ac15_opening_change_tank_closes_the_substrate_panel() -> void:
	if not await _open():
		return
	await Ui.open_chooser(self, _controls)
	assert_bool(Ui.is_open(_controls)).is_true()
	assert_bool(Sui.is_open(_controls)).is_false()


func test_ac15_the_button_is_refused_while_the_change_tank_dialog_is_active() -> void:
	if not await _build():
		return
	var dialog: Control = Ui.dialog(_controls)
	dialog.call("ask", "tank.large_1.name")
	await _wait()
	assert_bool(Ui.dialog_open(_controls)).is_true()
	await Sui.press_open(self, _controls)
	assert_bool(Sui.is_open(_controls)).is_false()
	assert_bool(Ui.dialog_open(_controls)).is_true()


func test_ac15_opening_it_puts_the_focus_on_the_card_in_use() -> void:
	if not await _open(Sub.BLACK, Sub.default_colour(_substrates, Sub.BLACK)):
		return
	assert_object(Ui.focus_owner(_controls)).is_same(Sui.card(_controls, Sub.BLACK))


# --- AC 16: clicking ---


func test_ac16_a_card_click_changes_the_type_and_resets_to_its_default_colour() -> void:
	if not await _open():
		return
	await _click_card(Sub.PEBBLES)
	assert_that(_model.get_substrate_id()).is_equal(Sub.PEBBLES)
	_same(_model.get_substrate_colour(), Sub.default_colour(_substrates, Sub.PEBBLES))
	assert_int(_history.get_undo_count()).is_equal(1)
	assert_bool(Sui.is_open(_controls)).is_true()


func test_ac16_every_card_click_from_a_non_default_swatch_gives_the_new_default() -> void:
	for id: StringName in [Sub.GRAVEL, Sub.PEBBLES, Sub.BLACK, Sub.COLOURED]:
		_history = CommandHistory.new()
		if not await _open(Sub.SAND, Sub.swatch(_substrates, Sub.SAND, 3)):
			return
		await _click_card(id)
		assert_that(_model.get_substrate_id()).override_failure_message(String(id)).is_equal(id)
		_same(_model.get_substrate_colour(), Sub.default_colour(_substrates, id))
		assert_int(_history.get_undo_count()).is_equal(1)
		await _reset_rig()


func test_ac16_after_a_card_click_the_swatch_row_switches_and_the_marks_move() -> void:
	if not await _open():
		return
	await _click_card(Sub.COLOURED)
	assert_array(Sui.marked_ids(_controls)).is_equal([Sub.COLOURED])
	var expected: Array[Color] = Sub.swatches(_substrates, Sub.COLOURED)
	var shown: Array[Color] = Sui.swatch_colours(_controls)
	assert_int(shown.size()).is_equal(expected.size())
	for index: int in mini(shown.size(), expected.size()):
		_same(shown[index], expected[index])
	assert_array(Sui.marked_swatches(_controls)).is_equal([0])


func test_ac16_a_swatch_click_changes_the_colour_and_keeps_the_type() -> void:
	if not await _open(Sub.COLOURED, Sub.default_colour(_substrates, Sub.COLOURED)):
		return
	await _click_swatch(2)
	assert_that(_model.get_substrate_id()).is_equal(Sub.COLOURED)
	_same(_model.get_substrate_colour(), Sub.swatch(_substrates, Sub.COLOURED, 2))
	assert_int(_history.get_undo_count()).is_equal(1)
	assert_bool(Sui.is_open(_controls)).is_true()
	assert_array(Sui.marked_swatches(_controls)).is_equal([1])
	assert_array(Sui.marked_ids(_controls)).is_equal([Sub.COLOURED])


func test_ac16_the_clicked_swatch_keeps_the_focus_when_the_marks_move() -> void:
	if not await _open(Sub.GRAVEL, Sub.default_colour(_substrates, Sub.GRAVEL)):
		return
	var swatch: Button = Sui.swatches(_controls)[1]
	swatch.grab_focus()
	swatch.pressed.emit()
	await _wait()
	assert_bool(is_instance_valid(swatch)).is_true()
	assert_object(Ui.focus_owner(_controls)).is_same(swatch)


func test_ac16_rapid_distinct_clicks_make_one_entry_each() -> void:
	if not await _open(Sub.GRAVEL, Sub.default_colour(_substrates, Sub.GRAVEL)):
		return
	Sui.swatches(_controls)[1].pressed.emit()
	Sui.swatches(_controls)[2].pressed.emit()
	Sui.swatches(_controls)[3].pressed.emit()
	await _wait()
	assert_int(_history.get_undo_count()).is_equal(3)
	_same(_model.get_substrate_colour(), Sub.swatch(_substrates, Sub.GRAVEL, 4))
	assert_array(Sui.marked_swatches(_controls)).is_equal([3])


func test_ac16_rapid_clicks_on_cards_make_one_entry_each() -> void:
	if not await _open():
		return
	Sui.card(_controls, Sub.GRAVEL).pressed.emit()
	Sui.card(_controls, Sub.PEBBLES).pressed.emit()
	Sui.card(_controls, Sub.BLACK).pressed.emit()
	await _wait()
	assert_int(_history.get_undo_count()).is_equal(3)
	assert_that(_model.get_substrate_id()).is_equal(Sub.BLACK)


func test_ac16_a_click_on_the_swatch_in_use_makes_no_entry() -> void:
	if not await _open():
		return
	await _click_swatch(1)
	assert_int(_history.get_undo_count()).is_equal(0)
	assert_bool(Sui.is_open(_controls)).is_true()


func test_ac09_a_click_on_the_card_in_use_keeps_the_swatch_and_makes_no_entry() -> void:
	var colour: Color = Sub.swatch(_substrates, Sub.BLACK, 2)
	if not await _open(Sub.BLACK, colour):
		return
	await _click_card(Sub.BLACK)
	assert_int(_history.get_undo_count()).is_equal(0)
	assert_that(_model.get_substrate_id()).is_equal(Sub.BLACK)
	_same(_model.get_substrate_colour(), colour)
	assert_array(Sui.marked_swatches(_controls)).is_equal([1])


func test_ac16_a_click_changes_nothing_but_the_substrate() -> void:
	if not await _open():
		return
	var rig_model: AquariumModel = Sub.furnished(Sub.SAND, Sub.SAND_DEFAULT, Table.MEDIUM)
	_model.reset_from(rig_model)
	await _wait()
	await _click_card(Sub.GRAVEL)
	assert_int(_model.get_item_count()).is_equal(3)
	assert_int(_model.get_fish_count()).is_equal(2)
	assert_int(_model.get_heightmap().size()).is_equal(6)
	assert_that(_model.get_tank_id()).is_equal(Table.MEDIUM)


func test_ac16_escape_closes_the_panel_without_a_model_change() -> void:
	if not await _open(Sub.GRAVEL, Sub.swatch(_substrates, Sub.GRAVEL, 2)):
		return
	Ui.tap(_controls, KEY_ESCAPE)
	await _wait()
	assert_bool(Sui.is_open(_controls)).is_false()
	assert_that(_model.get_substrate_id()).is_equal(Sub.GRAVEL)
	_same(_model.get_substrate_colour(), Sub.swatch(_substrates, Sub.GRAVEL, 2))
	assert_int(_history.get_undo_count()).is_equal(0)


func test_ac16_close_closes_the_panel_without_a_model_change_and_focus_returns() -> void:
	if not await _open():
		return
	Sui.close_button(_controls).pressed.emit()
	await _wait()
	assert_bool(Sui.is_open(_controls)).is_false()
	assert_that(_model.get_substrate_id()).is_equal(Sub.SAND)
	assert_int(_history.get_undo_count()).is_equal(0)
	assert_object(Ui.focus_owner(_controls)).is_same(Sui.open_button(_controls))


func test_ac16_the_panel_stays_open_after_a_click() -> void:
	if not await _open():
		return
	await _click_card(Sub.GRAVEL)
	await _click_swatch(2)
	await _click_card(Sub.SAND)
	assert_bool(Sui.is_open(_controls)).is_true()


func test_ac16_undo_while_open_moves_the_marks_back() -> void:
	if not await _open():
		return
	await _click_card(Sub.PEBBLES)
	assert_array(Sui.marked_ids(_controls)).is_equal([Sub.PEBBLES])
	assert_bool(_history.undo()).is_true()
	await _wait()
	assert_bool(Sui.is_open(_controls)).is_true()
	assert_array(Sui.marked_ids(_controls)).is_equal([Sub.SAND])
	assert_array(Sui.marked_swatches(_controls)).is_equal([0])
	assert_int(Sui.swatches(_controls).size()).is_equal(Sub.swatches(_substrates, Sub.SAND).size())


func test_ac16_a_model_reset_while_open_refreshes_the_marks_and_the_swatch_row() -> void:
	if not await _open():
		return
	var other: AquariumModel = Sub.model_with(
		Sub.COLOURED, Sub.swatch(_substrates, Sub.COLOURED, 3), Table.MEDIUM
	)
	_model.reset_from(other)
	await _wait()
	assert_bool(Sui.is_open(_controls)).is_true()
	assert_array(Sui.marked_ids(_controls)).is_equal([Sub.COLOURED])
	assert_array(Sui.marked_swatches(_controls)).is_equal([2])
	assert_int(Sui.swatches(_controls).size()).is_equal(
		Sub.swatches(_substrates, Sub.COLOURED).size()
	)


func test_ac16_a_confirmed_tank_change_closes_the_panel() -> void:
	if not await _build():
		return
	await Ui.open_chooser(self, _controls)
	Ui.card(_controls, Table.LARGE).pressed.emit()
	await _wait()
	assert_that(_model.get_tank_id()).is_equal(Table.LARGE)
	assert_bool(Sui.is_open(_controls)).is_false()
	assert_bool(Ui.is_open(_controls)).is_false()


# --- AC 20: a saved colour that is no swatch ---


func test_ac20_the_card_is_marked_and_no_swatch_is_marked() -> void:
	if not await _open(Sub.SAND, Sub.NOT_A_SWATCH):
		return
	assert_array(Sui.marked_ids(_controls)).is_equal([Sub.SAND])
	assert_array(Sui.marked_swatches(_controls)).is_empty()
	assert_int(Sui.swatches(_controls).size()).is_equal(Sub.swatches(_substrates, Sub.SAND).size())


func test_ac20_clicking_swatch_1_gives_the_default_with_one_entry_and_undo_restores() -> void:
	if not await _open(Sub.SAND, Sub.NOT_A_SWATCH):
		return
	await _click_swatch(1)
	_same(_model.get_substrate_colour(), Sub.SAND_DEFAULT)
	assert_int(_history.get_undo_count()).is_equal(1)
	assert_array(Sui.marked_swatches(_controls)).is_equal([0])
	assert_bool(_history.undo()).is_true()
	await _wait()
	_same(_model.get_substrate_colour(), Sub.NOT_A_SWATCH)
	assert_array(Sui.marked_swatches(_controls)).is_empty()


func test_ac20_clicking_the_type_in_use_stays_a_no_op_for_a_non_swatch_colour() -> void:
	if not await _open(Sub.SAND, Sub.NOT_A_SWATCH):
		return
	await _click_card(Sub.SAND)
	assert_int(_history.get_undo_count()).is_equal(0)
	_same(_model.get_substrate_colour(), Sub.NOT_A_SWATCH)


# --- AC 21: keyboard and non-colour cues ---


func test_ac21_tab_visits_every_card_then_every_swatch_then_close_then_wraps() -> void:
	if not await _open():
		return
	var order: Array[Control] = []
	for button: Button in Sui.cards(_controls):
		order.append(button)
	for swatch: Button in Sui.swatches(_controls):
		order.append(swatch)
	order.append(Sui.close_button(_controls))
	Sui.cards(_controls)[0].grab_focus()
	var visited: Array[Control] = [Ui.focus_owner(_controls)]
	for step: int in order.size():
		Ui.tap(_controls, KEY_TAB)
		visited.append(Ui.focus_owner(_controls))
	assert_array(visited.slice(0, order.size())).is_equal(order)
	assert_object(visited[order.size()]).is_same(order[0])


func test_ac21_shift_tab_walks_backwards_from_the_first_card_to_close_and_wraps() -> void:
	if not await _open():
		return
	Sui.cards(_controls)[0].grab_focus()
	Ui.tap(_controls, KEY_TAB, true)
	assert_object(Ui.focus_owner(_controls)).is_same(Sui.close_button(_controls))
	Ui.tap(_controls, KEY_TAB, true)
	var list: Array[Button] = Sui.swatches(_controls)
	assert_object(Ui.focus_owner(_controls)).is_same(list[list.size() - 1])


func test_ac21_the_arrow_keys_move_between_swatches() -> void:
	if not await _open():
		return
	var list: Array[Button] = Sui.swatches(_controls)
	list[0].grab_focus()
	Ui.tap(_controls, KEY_RIGHT)
	assert_object(Ui.focus_owner(_controls)).is_same(list[1])
	Ui.tap(_controls, KEY_RIGHT)
	assert_object(Ui.focus_owner(_controls)).is_same(list[2])
	Ui.tap(_controls, KEY_LEFT)
	assert_object(Ui.focus_owner(_controls)).is_same(list[1])


func test_ac21_enter_on_each_swatch_applies_it() -> void:
	if not await _open(Sub.GRAVEL, Sub.default_colour(_substrates, Sub.GRAVEL)):
		return
	var count: int = Sui.swatches(_controls).size()
	for number: int in range(2, count + 1):
		Sui.swatches(_controls)[number - 1].grab_focus()
		Ui.tap(_controls, KEY_ENTER)
		await _wait()
		_same(_model.get_substrate_colour(), Sub.swatch(_substrates, Sub.GRAVEL, number))
		assert_array(Sui.marked_swatches(_controls)).is_equal([number - 1])
	assert_int(_history.get_undo_count()).is_equal(count - 1)


func test_ac21_space_on_a_swatch_applies_it_too() -> void:
	if not await _open():
		return
	Sui.swatches(_controls)[1].grab_focus()
	Ui.tap(_controls, KEY_SPACE)
	await _wait()
	_same(_model.get_substrate_colour(), Sub.swatch(_substrates, Sub.SAND, 2))


func test_ac21_enter_on_each_card_applies_it() -> void:
	if not await _open():
		return
	for id: StringName in [Sub.GRAVEL, Sub.PEBBLES, Sub.BLACK, Sub.COLOURED, Sub.SAND]:
		Sui.card(_controls, id).grab_focus()
		Ui.tap(_controls, KEY_ENTER)
		await _wait()
		assert_that(_model.get_substrate_id()).override_failure_message(String(id)).is_equal(id)
		_same(_model.get_substrate_colour(), Sub.default_colour(_substrates, id))
	assert_int(_history.get_undo_count()).is_equal(5)


func test_ac21_every_focusable_control_has_the_theme_focus_style_and_no_override() -> void:
	if not await _open():
		return
	var checked: int = 0
	var controls: Array[Control] = []
	for button: Button in Sui.cards(_controls):
		controls.append(button)
	for swatch: Button in Sui.swatches(_controls):
		controls.append(swatch)
	controls.append(Sui.close_button(_controls))
	for control: Control in controls:
		var style: StyleBox = control.get_theme_stylebox("focus")
		(
			assert_bool(style != null and not style is StyleBoxEmpty)
			. override_failure_message("%s has no visible focus style" % control.name)
			. is_true()
		)
		(
			assert_int(control.focus_mode)
			. override_failure_message("%s is not focusable" % control.name)
			. is_equal(Control.FOCUS_ALL)
		)
		checked += 1
	for swatch: Button in Sui.swatches(_controls):
		(
			assert_bool(swatch.has_theme_stylebox_override("focus"))
			. override_failure_message("%s overrides the focus style" % swatch.name)
			. is_false()
		)
	assert_int(checked).is_equal(5 + Sui.swatches(_controls).size() + 1)


func test_ac21_the_in_use_mark_is_a_visible_shape_on_the_in_use_swatch_only() -> void:
	if not await _open(Sub.GRAVEL, Sub.swatch(_substrates, Sub.GRAVEL, 2)):
		return
	var list: Array[Button] = Sui.swatches(_controls)
	for index: int in list.size():
		var mark: Control = list[index].find_child(Sui.IN_USE_MARK, true, false) as Control
		if index == 1:
			(
				assert_object(mark)
				. override_failure_message("no InUseMark on the in-use swatch")
				. is_not_null()
			)
			if mark != null:
				assert_bool(mark.is_visible_in_tree()).is_true()
				(
					assert_bool(mark is Label or mark is Button)
					. override_failure_message("the mark must be a drawn shape, not text")
					. is_false()
				)
		elif mark != null:
			(
				assert_bool(mark.is_visible_in_tree())
				. override_failure_message("swatch %d shows a mark" % (index + 1))
				. is_false()
			)


func test_ac21_the_mark_is_not_a_tint_change_of_the_swatch() -> void:
	var marked: Color = Sub.swatch(_substrates, Sub.GRAVEL, 2)
	if not await _open(Sub.GRAVEL, marked):
		return
	var list: Array[Button] = Sui.swatches(_controls)
	var expected: Array[Color] = Sub.swatches(_substrates, Sub.GRAVEL)
	for index: int in mini(list.size(), expected.size()):
		_same(Sui.swatch_colour(list[index]), expected[index])
		for style_name: String in ["hover", "pressed"]:
			var style: StyleBoxFlat = list[index].get_theme_stylebox(style_name) as StyleBoxFlat
			(
				assert_object(style)
				. override_failure_message(
					"swatch %d: %s is not a StyleBoxFlat" % [index + 1, style_name]
				)
				. is_not_null()
			)


func test_ac21_the_mark_moves_with_the_selection_and_the_colours_stay() -> void:
	if not await _open(Sub.GRAVEL, Sub.default_colour(_substrates, Sub.GRAVEL)):
		return
	var before: Array[Color] = Sui.swatch_colours(_controls)
	await _click_swatch(3)
	assert_array(Sui.marked_swatches(_controls)).is_equal([2])
	var after: Array[Color] = Sui.swatch_colours(_controls)
	assert_int(after.size()).is_equal(before.size())
	for index: int in mini(after.size(), before.size()):
		_same(after[index], before[index])


# --- AC 23: no id is ever shown ---


func _assert_no_id_in_texts(label: String) -> void:
	var texts: PackedStringArray = Sui.visible_texts(_controls)
	assert_int(texts.size()).override_failure_message("%s: no texts found" % label).is_greater(8)
	for text: String in texts:
		for id: StringName in Sub.IDS:
			(
				assert_str(text.to_lower())
				. override_failure_message("%s: '%s' contains the id %s" % [label, text, id])
				. not_contains(String(id))
			)
			(
				assert_str(text.to_lower())
				. override_failure_message("%s: '%s' shows a raw id" % [label, text])
				. not_contains("substrate.")
			)


func test_ac23_no_label_button_or_tooltip_contains_an_id_in_english() -> void:
	if not await _open():
		return
	_assert_no_id_in_texts("en")


func test_ac23_no_label_button_or_tooltip_contains_an_id_in_hungarian() -> void:
	if not await _open():
		return
	await Ui.set_language(self, "hu")
	_assert_no_id_in_texts("hu")


func test_ac23_the_swatches_have_no_text_and_no_tooltip() -> void:
	if not await _open():
		return
	for swatch: Button in Sui.swatches(_controls):
		assert_str(swatch.text).is_empty()
		assert_str(swatch.tooltip_text).is_empty()
