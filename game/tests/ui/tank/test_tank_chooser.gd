# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #24 criteria 15, 16, 17, 18, 20 and 27 (first half) (owner: developer): the tank chooser panel.
## A real room and the real controls on a fixture model, catalog and history; clicks are `pressed`
## emissions, keys go through the viewport. The node names are the contract of
## tests/helpers/tank_ui_rig.gd.

const Api := preload("res://tests/helpers/late_api.gd")
const Rig := preload("res://tests/helpers/room_rig.gd")
const Ui := preload("res://tests/helpers/tank_ui_rig.gd")
const Table := preload("res://tests/helpers/tank_table.gd")
const Recorder := preload("res://tests/helpers/signal_recorder.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")

const WINDOW := Vector2i(1280, 720)
## The card keeps this much room around its text on every side (the scene uses 10).
const CARD_PADDING := 10.0

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


## Builds the room and the controls; false (and a failed assert) while the scene is missing.
func _build(model: AquariumModel = null, catalog: RefCounted = null, parent: Node = null) -> bool:
	if model != null:
		_model = model
	if catalog != null:
		_catalog = catalog
	var rig: Dictionary = await Ui.open(
		parent if parent != null else self, _model, _catalog, _history
	)
	_room = rig["room"]
	_controls = rig["controls"]
	auto_free(_room)
	(
		assert_bool(_controls != null)
		. override_failure_message("%s is missing" % Ui.CONTROLS_SCENE)
		. is_true()
	)
	if _controls != null:
		auto_free(_controls)
	return _controls != null


func _open_chooser(parent: Node = null) -> bool:
	if not await _build(null, null, parent):
		return false
	await Ui.open_chooser(self, _controls)
	(
		assert_bool(Ui.is_open(_controls))
		. override_failure_message("the Change tank button did not open the chooser")
		. is_true()
	)
	return Ui.is_open(_controls)


## True when the catalog holds the three tanks (the fixtures below copy them).
func _have_tanks() -> bool:
	for id: StringName in Table.IDS:
		if Rig.definition_of(id) == null:
			assert_bool(false).override_failure_message("%s is not in the catalog" % id).is_true()
			return false
	return true


func _wait() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


# --- AC 15: what the chooser shows ---


func test_ac15_the_chooser_is_closed_until_the_change_tank_button_opens_it() -> void:
	if not await _build():
		return
	assert_object(Ui.change_button(_controls)).is_not_null()
	assert_str(Ui.shown(Ui.change_button(_controls))).is_equal("Change tank")
	assert_bool(Ui.is_open(_controls)).is_false()
	await Ui.open_chooser(self, _controls)
	assert_bool(Ui.is_open(_controls)).is_true()
	assert_str(Ui.shown(Ui.chooser(_controls).find_child(Ui.TITLE, true, false) as Label)).is_equal(
		"Choose your tank"
	)


func test_ac15_it_lists_exactly_the_three_catalog_tanks_in_ascending_size_order() -> void:
	if not await _open_chooser():
		return
	assert_array(Ui.card_ids(_controls)).is_equal(Table.IDS)


func test_ac15_each_card_shows_name_litres_and_description_in_english() -> void:
	if not await _open_chooser():
		return
	for id: StringName in Table.IDS:
		var row: Dictionary = Table.row(id)
		assert_str(Ui.shown(Ui.card_label(_controls, id, "NameLabel"))).is_equal(row["name_en"])
		assert_str(Ui.shown(Ui.card_label(_controls, id, "LitresLabel"))).is_equal(
			"%d L" % row["litres"]
		)
		assert_str(Ui.shown(Ui.card_label(_controls, id, "DescriptionLabel"))).is_equal(
			row["description_en"]
		)


func test_ac15_each_card_shows_name_litres_and_description_in_hungarian() -> void:
	TranslationServer.set_locale("hu")
	if not await _open_chooser():
		return
	for id: StringName in Table.IDS:
		var row: Dictionary = Table.row(id)
		assert_str(Ui.shown(Ui.card_label(_controls, id, "NameLabel"))).is_equal(row["name_hu"])
		assert_str(Ui.shown(Ui.card_label(_controls, id, "LitresLabel"))).is_equal(
			"%d l" % row["litres"]
		)
		assert_str(Ui.shown(Ui.card_label(_controls, id, "DescriptionLabel"))).is_equal(
			row["description_hu"]
		)


func test_ac15_a_card_has_no_dimensions_line() -> void:
	if not await _open_chooser():
		return
	for id: StringName in Table.IDS:
		var texts: PackedStringArray = PackedStringArray()
		for node: Node in Ui.card(_controls, id).find_children("*", "Label", true, false):
			texts.append(Ui.shown(node as Label))
		for text: String in texts:
			(
				assert_bool(text.contains(" cm") or text.contains(" x ") or text.contains("×"))
				. override_failure_message("%s shows a dimensions line: %s" % [id, text])
				. is_false()
			)
		(
			assert_int(Ui.card(_controls, id).find_children("*", "Label", true, false).size())
			. override_failure_message("%s: name, litres, description and marker only" % id)
			. is_equal(4)
		)


func test_ac15_exactly_one_card_is_marked_in_use_the_displayed_tank() -> void:
	if not await _open_chooser():
		return
	assert_array(Ui.marked_ids(_controls)).is_equal([Table.MEDIUM])
	assert_str(Ui.shown(Ui.card_label(_controls, Table.MEDIUM, "InUseLabel"))).is_equal("In use")


func test_ac15_the_marker_is_on_the_tank_the_model_started_with() -> void:
	for id: StringName in [Table.SMALL, Table.LARGE]:
		_model = Rig.model_with(id)
		if not await _open_chooser():
			return
		assert_array(Ui.marked_ids(_controls)).override_failure_message(id).is_equal([id])
		_controls.free()
		_room.free()


func test_ac15_the_litres_come_from_the_catalog_not_from_the_text() -> void:
	# AC 27: litres 25 -> 15 in a fixture catalog changes the small card and nothing else.
	if not _have_tanks():
		return
	var small: Resource = Rig.definition_of(Table.SMALL).duplicate()
	small.set("volume_litres", 15)
	var catalog: RefCounted = Api.catalog_from(
		[small, Rig.definition_of(Table.MEDIUM), Rig.definition_of(Table.LARGE)]
	)
	if not await _build(null, catalog):
		return
	await Ui.open_chooser(self, _controls)
	assert_str(Ui.shown(Ui.card_label(_controls, Table.SMALL, "LitresLabel"))).is_equal("15 L")
	assert_str(Ui.shown(Ui.card_label(_controls, Table.SMALL, "NameLabel"))).is_equal("Small tank")
	assert_array(Ui.card_ids(_controls)).is_equal(Table.IDS)
	assert_str(Ui.shown(Ui.card_label(_controls, Table.MEDIUM, "LitresLabel"))).is_equal("60 L")
	assert_that(_model.get_tank_id()).is_equal(Table.MEDIUM)


func test_ac27_the_litres_value_is_formatted_with_the_hungarian_unit_too() -> void:
	if not _have_tanks():
		return
	TranslationServer.set_locale("hu")
	var small: Resource = Rig.definition_of(Table.SMALL).duplicate()
	small.set("volume_litres", 15)
	var catalog: RefCounted = Api.catalog_from(
		[small, Rig.definition_of(Table.MEDIUM), Rig.definition_of(Table.LARGE)]
	)
	if not await _build(null, catalog):
		return
	await Ui.open_chooser(self, _controls)
	assert_str(Ui.shown(Ui.card_label(_controls, Table.SMALL, "LitresLabel"))).is_equal("15 l")


func test_ac15_the_order_follows_the_volume_with_the_id_as_tie_breaker_not_the_file_order() -> void:
	if not _have_tanks():
		return
	var twin: Resource = Rig.variant(&"tank_medium_2", Rig.definition_of(Table.MEDIUM).get("scene"))
	twin.set("volume_litres", 60)
	var catalog: RefCounted = Api.catalog_from(
		[Rig.definition_of(Table.LARGE), twin, Rig.definition_of(Table.MEDIUM)]
	)
	if not await _build(null, catalog):
		return
	await Ui.open_chooser(self, _controls)
	assert_array(Ui.card_ids(_controls)).is_equal([Table.MEDIUM, &"tank_medium_2", Table.LARGE])


# --- AC 16: clicking ---


func test_ac16_clicking_another_tank_on_an_empty_model_runs_the_command_once_and_closes() -> void:
	if not await _open_chooser():
		return
	var recorder: Recorder = Recorder.new()
	recorder.watch(_model)
	Ui.card(_controls, Table.LARGE).pressed.emit()
	await _wait()
	assert_that(_model.get_tank_id()).is_equal(Table.LARGE)
	assert_int(_history.get_undo_count()).is_equal(1)
	assert_int(recorder.names().count("tank_changed")).is_equal(1)
	assert_bool(Ui.is_open(_controls)).is_false()
	assert_bool(Ui.dialog_open(_controls)).is_false()


func test_ac16_after_the_click_the_room_shows_the_new_tank_and_the_marker_moves() -> void:
	if not await _open_chooser():
		return
	Ui.card(_controls, Table.SMALL).pressed.emit()
	await _wait()
	assert_that(Rig.displayed_id(_room)).is_equal(Table.SMALL)
	await Ui.open_chooser(self, _controls)
	assert_array(Ui.marked_ids(_controls)).is_equal([Table.SMALL])


func test_ac16_clicking_the_tank_in_use_closes_the_chooser_and_changes_nothing() -> void:
	if not await _open_chooser():
		return
	var recorder: Recorder = Recorder.new()
	recorder.watch(_model)
	Ui.card(_controls, Table.MEDIUM).pressed.emit()
	await _wait()
	assert_bool(Ui.is_open(_controls)).is_false()
	assert_int(recorder.count()).is_equal(0)
	assert_int(_history.get_undo_count()).is_equal(0)
	assert_bool(Ui.dialog_open(_controls)).is_false()


func test_ac16_clicking_the_tank_in_use_never_asks_even_on_a_furnished_tank() -> void:
	_model = Ui.furnished_model(Table.MEDIUM)
	if not await _open_chooser():
		return
	Ui.card(_controls, Table.MEDIUM).pressed.emit()
	await _wait()
	assert_bool(Ui.dialog_open(_controls)).is_false()
	assert_bool(Ui.is_open(_controls)).is_false()
	assert_int(_model.get_item_count()).is_equal(1)
	assert_int(_history.get_undo_count()).is_equal(0)


func test_ac16_two_quick_clicks_leave_exactly_one_history_entry() -> void:
	if not await _open_chooser():
		return
	var card: Button = Ui.card(_controls, Table.LARGE)
	card.pressed.emit()
	card.pressed.emit()
	await _wait()
	assert_int(_history.get_undo_count()).is_equal(1)
	assert_that(_model.get_tank_id()).is_equal(Table.LARGE)


func test_ac16_a_click_while_the_history_is_busy_is_a_no_op_without_an_error_log() -> void:
	if not await _open_chooser():
		return
	var card: Button = Ui.card(_controls, Table.LARGE)
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void:
			# A model signal handler runs inside the Command, while the history is busy.
			var clicked: Array[bool] = []
			_model.tank_changed.connect(
				func(_id: StringName) -> void:
					if clicked.is_empty():
						clicked.append(true)
						card.pressed.emit()
			)
			card.pressed.emit()
			await get_tree().process_frame
	)
	assert_dict(seen["errors"]).is_empty()
	assert_int(_history.get_undo_count()).is_equal(1)


func test_ac16_the_chooser_never_changes_the_model_by_itself() -> void:
	if not await _open_chooser():
		return
	var recorder: Recorder = Recorder.new()
	recorder.watch(_model)
	Ui.close_button(_controls).pressed.emit()
	await _wait()
	await Ui.open_chooser(self, _controls)
	assert_int(recorder.count()).is_equal(0)
	assert_int(_history.get_undo_count()).is_equal(0)


# --- AC 17: closing and language ---


func test_ac17_close_closes_the_chooser_and_leaves_the_model_unchanged() -> void:
	if not await _open_chooser():
		return
	assert_str(Ui.shown(Ui.close_button(_controls))).is_equal("Close")
	Ui.close_button(_controls).pressed.emit()
	await _wait()
	assert_bool(Ui.is_open(_controls)).is_false()
	assert_that(_model.get_tank_id()).is_equal(Table.MEDIUM)
	assert_int(_history.get_undo_count()).is_equal(0)


func test_ac17_esc_closes_the_chooser_and_leaves_the_model_unchanged() -> void:
	if not await _open_chooser():
		return
	Ui.tap(_controls, KEY_ESCAPE)
	await _wait()
	assert_bool(Ui.is_open(_controls)).is_false()
	assert_that(_model.get_tank_id()).is_equal(Table.MEDIUM)
	assert_int(_history.get_undo_count()).is_equal(0)


func test_ac17_a_language_switch_rebuilds_every_text_without_reopening() -> void:
	if not await _open_chooser():
		return
	TranslationServer.set_locale("hu")
	EventBus.language_changed.emit("hu")
	await _wait()
	assert_bool(Ui.is_open(_controls)).is_true()
	assert_str(Ui.shown(Ui.change_button(_controls))).is_equal("Akvárium cseréje")
	assert_str(Ui.shown(Ui.chooser(_controls).find_child(Ui.TITLE, true, false) as Label)).is_equal(
		"Válaszd ki az akváriumot"
	)
	assert_str(Ui.shown(Ui.close_button(_controls))).is_equal("Bezárás")
	for id: StringName in Table.IDS:
		var row: Dictionary = Table.row(id)
		assert_str(Ui.shown(Ui.card_label(_controls, id, "NameLabel"))).is_equal(row["name_hu"])
		assert_str(Ui.shown(Ui.card_label(_controls, id, "LitresLabel"))).is_equal(
			"%d l" % row["litres"]
		)
		assert_str(Ui.shown(Ui.card_label(_controls, id, "DescriptionLabel"))).is_equal(
			row["description_hu"]
		)
	assert_str(Ui.shown(Ui.card_label(_controls, Table.MEDIUM, "InUseLabel"))).is_equal(
		"Használatban"
	)


func test_ac17_switching_back_to_english_restores_the_english_texts() -> void:
	if not await _open_chooser():
		return
	TranslationServer.set_locale("hu")
	EventBus.language_changed.emit("hu")
	await _wait()
	TranslationServer.set_locale("en")
	EventBus.language_changed.emit("en")
	await _wait()
	assert_str(Ui.shown(Ui.card_label(_controls, Table.LARGE, "NameLabel"))).is_equal("Large tank")
	assert_str(Ui.shown(Ui.close_button(_controls))).is_equal("Close")


func test_ac17_no_text_of_the_controls_is_a_raw_key_after_a_language_switch() -> void:
	if not await _open_chooser():
		return
	TranslationServer.set_locale("hu")
	EventBus.language_changed.emit("hu")
	await _wait()
	for node: Node in _controls.find_children("*", "Control", true, false):
		if node is Label or node is Button:
			var text: String = Ui.shown(node as Control)
			(
				assert_bool(
					(
						text.begins_with("tank.")
						or text.begins_with("unit.")
						or text.begins_with("settings.")
					)
				)
				. override_failure_message("%s shows a raw key: %s" % [node.name, text])
				. is_false()
			)


# --- AC 18: an unknown id in the model ---


## Opens the chooser on a model with an unknown tank id; the room logs its one warning meanwhile.
## Returns what was logged, plus "open": whether the chooser is showing.
func _open_fallback() -> Dictionary:
	_model = Rig.model_with(&"tank_from_the_future")
	var seen: Dictionary = await EngineOutput.capture(func() -> void: await _open_chooser())
	seen["open"] = _controls != null and Ui.is_open(_controls)
	return seen


func test_ac18_the_chooser_marks_the_displayed_fallback_medium_as_in_use() -> void:
	var seen: Dictionary = await _open_fallback()
	if not seen["open"]:
		return
	assert_int((seen["warnings"] as Dictionary).size()).is_equal(1)
	assert_dict(seen["errors"]).is_empty()
	assert_array(Ui.marked_ids(_controls)).is_equal([Table.MEDIUM])
	assert_that(_model.get_tank_id()).is_equal(&"tank_from_the_future")


func test_ac18_picking_medium_while_the_model_holds_an_unknown_id_runs_the_command() -> void:
	var seen: Dictionary = await _open_fallback()
	if not seen["open"]:
		return
	Ui.card(_controls, Table.MEDIUM).pressed.emit()
	await _wait()
	assert_that(_model.get_tank_id()).is_equal(Table.MEDIUM)
	assert_int(_history.get_undo_count()).is_equal(1)
	assert_bool(Ui.is_open(_controls)).is_false()
	var undo_seen: Dictionary = await EngineOutput.capture(func() -> void: _history.undo())
	assert_that(_model.get_tank_id()).is_equal(&"tank_from_the_future")
	(
		assert_dict(undo_seen["warnings"])
		. is_equal(
			{
				'RoomCorner: unknown tank id "tank_from_the_future"; showing the default tank "tank_medium_1"':
				1
			}
		)
	)
	assert_dict(undo_seen["errors"]).is_empty()
	assert_that(Rig.displayed_id(_room)).is_equal(Table.MEDIUM)


func test_ac18_picking_another_tank_while_the_model_holds_an_unknown_id_works_the_same_way(
) -> void:
	var seen: Dictionary = await _open_fallback()
	if not seen["open"]:
		return
	Ui.card(_controls, Table.LARGE).pressed.emit()
	await _wait()
	assert_that(_model.get_tank_id()).is_equal(Table.LARGE)
	assert_that(Rig.displayed_id(_room)).is_equal(Table.LARGE)


func test_ac18_the_room_and_the_chooser_alone_never_rewrite_the_unknown_id() -> void:
	var seen: Dictionary = await _open_fallback()
	if not seen["open"]:
		return
	Ui.close_button(_controls).pressed.emit()
	await _wait()
	assert_that(_model.get_tank_id()).is_equal(&"tank_from_the_future")
	assert_int(_history.get_undo_count()).is_equal(0)


# --- AC 20: keyboard, focus, outside input, one panel at a time ---


func test_ac20_when_the_chooser_opens_the_focus_is_on_the_card_of_the_tank_in_use() -> void:
	if not await _open_chooser():
		return
	assert_object(Ui.focus_owner(_controls)).is_same(Ui.card(_controls, Table.MEDIUM))


func test_ac20_with_a_fallback_medium_the_focus_is_on_the_medium_card() -> void:
	var seen: Dictionary = await _open_fallback()
	if not seen["open"]:
		return
	assert_object(Ui.focus_owner(_controls)).is_same(Ui.card(_controls, Table.MEDIUM))


func test_ac20_tab_moves_through_the_cards_in_size_order_then_close_then_wraps() -> void:
	if not await _open_chooser():
		return
	Ui.card(_controls, Table.SMALL).grab_focus()
	var visited: Array[Control] = []
	for step: int in 5:
		Ui.tap(_controls, KEY_TAB)
		visited.append(Ui.focus_owner(_controls))
	(
		assert_array(visited)
		. is_equal(
			[
				Ui.card(_controls, Table.MEDIUM),
				Ui.card(_controls, Table.LARGE),
				Ui.close_button(_controls),
				Ui.card(_controls, Table.SMALL),
				Ui.card(_controls, Table.MEDIUM),
			]
		)
	)


func test_ac20_shift_tab_walks_backwards_and_wraps_inside_the_panel() -> void:
	if not await _open_chooser():
		return
	Ui.card(_controls, Table.MEDIUM).grab_focus()
	var visited: Array[Control] = []
	for step: int in 4:
		Ui.tap(_controls, KEY_TAB, true)
		visited.append(Ui.focus_owner(_controls))
	(
		assert_array(visited)
		. is_equal(
			[
				Ui.card(_controls, Table.SMALL),
				Ui.close_button(_controls),
				Ui.card(_controls, Table.LARGE),
				Ui.card(_controls, Table.MEDIUM),
			]
		)
	)


func test_ac20_enter_on_a_focused_card_acts_like_a_click() -> void:
	if not await _open_chooser():
		return
	Ui.card(_controls, Table.LARGE).grab_focus()
	Ui.tap(_controls, KEY_ENTER)
	await _wait()
	assert_that(_model.get_tank_id()).is_equal(Table.LARGE)
	assert_int(_history.get_undo_count()).is_equal(1)


func test_ac20_space_on_a_focused_card_acts_like_a_click() -> void:
	if not await _open_chooser():
		return
	Ui.card(_controls, Table.SMALL).grab_focus()
	Ui.tap(_controls, KEY_SPACE)
	await _wait()
	assert_that(_model.get_tank_id()).is_equal(Table.SMALL)


func test_ac20_esc_closes_the_chooser_and_the_focus_returns_to_the_change_tank_button() -> void:
	if not await _open_chooser():
		return
	Ui.tap(_controls, KEY_ESCAPE)
	await _wait()
	assert_bool(Ui.is_open(_controls)).is_false()
	assert_object(Ui.focus_owner(_controls)).is_same(Ui.change_button(_controls))


func test_ac20_close_closes_the_chooser_and_the_focus_returns_to_the_change_tank_button() -> void:
	if not await _open_chooser():
		return
	Ui.close_button(_controls).pressed.emit()
	await _wait()
	assert_bool(Ui.is_open(_controls)).is_false()
	assert_object(Ui.focus_owner(_controls)).is_same(Ui.change_button(_controls))


func test_ac20_after_a_pick_the_focus_returns_to_the_change_tank_button() -> void:
	if not await _open_chooser():
		return
	Ui.card(_controls, Table.LARGE).pressed.emit()
	await _wait()
	assert_object(Ui.focus_owner(_controls)).is_same(Ui.change_button(_controls))


## A 1280x720 SubViewport below the suite, so layout checks work headless.
func _window() -> SubViewport:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = WINDOW
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(auto_free(viewport))
	return viewport


func test_ac20_the_chooser_is_non_modal_no_big_control_swallows_mouse_input() -> void:
	var viewport: SubViewport = _window()
	var holder: Node = Node.new()
	viewport.add_child(holder)
	if not await _open_chooser(holder):
		return
	var screen: Rect2 = _controls.get_viewport().get_visible_rect()
	assert_vector(screen.size).is_equal(Vector2(WINDOW))
	for node: Node in _controls.find_children("*", "Control", true, false):
		var control: Control = node as Control
		if not control.is_visible_in_tree() or control.mouse_filter != Control.MOUSE_FILTER_STOP:
			continue
		var area: float = control.get_global_rect().get_area()
		(
			assert_float(area)
			. override_failure_message(
				(
					"%s stops the mouse over %.0f%% of the screen"
					% [control.name, 100.0 * area / screen.get_area()]
				)
			)
			. is_less(screen.get_area() * 0.5)
		)


func test_ac20_opening_another_panel_of_the_group_closes_the_chooser() -> void:
	if not await _open_chooser():
		return
	var stub: Control = Control.new()
	stub.visible = false
	_controls.add_child(stub)
	_controls.call("open_panel", stub)
	await _wait()
	assert_bool(stub.visible).is_true()
	assert_bool(Ui.is_open(_controls)).is_false()


func test_ac20_opening_the_chooser_closes_the_other_panel() -> void:
	if not await _build():
		return
	var stub: Control = Control.new()
	stub.visible = false
	_controls.add_child(stub)
	_controls.call("open_panel", stub)
	await _wait()
	assert_bool(stub.visible).is_true()
	await Ui.open_chooser(self, _controls)
	assert_bool(Ui.is_open(_controls)).is_true()
	assert_bool(stub.visible).is_false()


func test_ac20_close_panels_closes_everything() -> void:
	if not await _open_chooser():
		return
	_controls.call("close_panels")
	await _wait()
	assert_bool(Ui.is_open(_controls)).is_false()


# --- layout: the cards contain their text ---


func _check_cards_contain_their_text(locale: String) -> void:
	TranslationServer.set_locale(locale)
	var holder: Node = Node.new()
	_window().add_child(holder)
	if not await _open_chooser(holder):
		return
	assert_vector(_controls.get_viewport().get_visible_rect().size).is_equal(Vector2(WINDOW))
	var rects: Array[Rect2] = []
	for button: Button in Ui.cards(_controls):
		var card_rect: Rect2 = button.get_global_rect()
		var padded: Rect2 = card_rect.grow(-CARD_PADDING)
		for node: Node in button.find_children("*", "Label", true, false):
			var label: Label = node as Label
			if not label.is_visible_in_tree():
				continue
			var rect: Rect2 = label.get_global_rect()
			(
				assert_bool(padded.grow(0.5).encloses(rect))
				. override_failure_message(
					(
						"%s (%s): %s %s sticks out of its padded card %s"
						% [locale, button.name, label.name, rect, padded]
					)
				)
				. is_true()
			)
		rects.append(card_rect)
	for first: int in rects.size():
		for second: int in range(first + 1, rects.size()):
			(
				assert_bool(rects[first].intersects(rects[second]))
				. override_failure_message(
					(
						"%s: cards %d and %d overlap: %s %s"
						% [locale, first, second, rects[first], rects[second]]
					)
				)
				. is_false()
			)


func test_chooser_cards_contain_their_text_at_1280x720_in_english() -> void:
	await _check_cards_contain_their_text("en")


func test_chooser_cards_contain_their_text_at_1280x720_in_hungarian() -> void:
	await _check_cards_contain_their_text("hu")
