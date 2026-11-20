extends GdUnitTestSuite
## #32 AC 7 (request part), 8, 9 and 10 (owner: developer, with clay_amphora.colourable of the
## technical-artist): recolouring the selected item through EventBus.item_colour_requested(
## has_colour, colour), which the colour dots and the Original colour button emit. One
## RecolourItemCommand: has_colour and the colour, one item_changed, one history entry, the
## selection and the selection mark stay (#31 AC 35). A request on an item whose definition is not
## colourable does nothing; so do a request equal to the current state (by to_rgba32), a request
## without a selection and a request during a drag, a rotate hold, a blocker or a busy history.
## Undo and redo keep the selection. The request carries no uid: it acts on the selection only.
## Test decisions: the shipped catalog decides colourable (clay_amphora true, river_stone false);
## the colours are fixed constants, the command does not check the swatch list (the dots do).

const Rig := preload("res://tests/helpers/placement_rig.gd")
const Session := preload("res://tests/helpers/placement_session.gd")
const Api := preload("res://tests/helpers/placement_api.gd")
const Edit := preload("res://tests/helpers/edit_api.gd")
const Recorder := preload("res://tests/helpers/signal_recorder.gd")
const ModelState := preload("res://tests/helpers/model_state.gd")

const STONE_UID := "a0000001"
const VASE := "a0000002"
const OTHER_VASE := "a0000003"
const TEAL := Color8(0x2A, 0x7F, 0x9E)
const BRICK := Color8(0xB5, 0x4A, 0x33)

var _s: Session = null


func after_test() -> void:
	Rig.close(_s)


func _open(model: AquariumModel = null) -> bool:
	_s = await Rig.open(self, model if model != null else _model())
	var complete: bool = _s.placement != null and _s.view != null and _s.ghost != null
	(
		assert_bool(complete)
		. override_failure_message("RoomCorner needs a Placement child with PlacedItems and Ghost")
		. is_true()
	)
	var wired: bool = EventBus.has_signal("item_colour_requested") and Edit.exists(Edit.RECOLOUR)
	(
		assert_bool(wired)
		. override_failure_message("EventBus.item_colour_requested or RecolourItemCommand missing")
		. is_true()
	)
	return complete and wired


func _model() -> AquariumModel:
	var model: AquariumModel = Rig.model()
	Rig.add_item(model, STONE_UID, Rig.STONE, -0.15, 0.0)
	Rig.add_item(model, VASE, Rig.AMPHORA, 0.15, 0.0, 37.5)
	Rig.add_item(model, OTHER_VASE, Rig.AMPHORA, 0.0, 0.12)
	return model


func _select(uid: String) -> void:
	_s.click(_s.screen_of_item(uid))
	assert_str(_s.selected_uid()).is_equal(uid)


func _request(has_colour: bool, colour: Color) -> void:
	EventBus.emit_signal("item_colour_requested", has_colour, colour)
	await _s.frame()


func _marked(uid: String) -> int:
	var count: int = 0
	for found: Node in _s.node_for(uid).find_children("*", "GeometryInstance3D", true, false):
		if (found as GeometryInstance3D).material_overlay != null:
			count += 1
	return count


func _assert_unchanged(before_state: Dictionary, events: Recorder) -> void:
	assert_dict(ModelState.snapshot(_s.model)).is_equal(before_state)
	assert_int(events.count()).is_equal(0)
	assert_int(_s.history.get_undo_count()).is_equal(0)


func test_ac08_a_swatch_request_runs_one_command_with_one_item_changed() -> void:
	if not await _open():
		return
	_select(VASE)
	var events: Recorder = Recorder.new()
	events.watch(_s.model)
	await _request(true, TEAL)
	assert_array(events.names()).is_equal(["item_changed"])
	assert_array(events.args_of(0)).is_equal([VASE, 1])
	var item: PlacedItem = _s.model.get_item(VASE)
	assert_bool(item.has_colour).is_true()
	assert_int(item.colour.to_rgba32()).is_equal(TEAL.to_rgba32())
	assert_int(_s.history.get_undo_count()).is_equal(1)


func test_ac08_uid_catalog_id_position_rotation_and_scale_stay() -> void:
	if not await _open():
		return
	_select(VASE)
	await _request(true, TEAL)
	var item: PlacedItem = _s.model.get_item(VASE)
	assert_str(item.uid).is_equal(VASE)
	assert_that(item.catalog_id).is_equal(Rig.AMPHORA)
	assert_float(item.position.x).is_equal(0.15)
	assert_float(item.rotation_y).is_equal(37.5)
	assert_float(item.scale).is_equal(1.0)
	assert_int(_s.model.get_item_index(VASE)).is_equal(1)
	assert_bool(_s.model.get_item(OTHER_VASE).has_colour).is_false()


func test_ac08_the_selection_and_the_mark_stay_and_no_selection_signal_fires() -> void:
	if not await _open():
		return
	_select(VASE)
	var timeline: Array[String] = _s.selection_timeline.duplicate()
	var marks: int = _marked(VASE)
	assert_int(marks).is_greater(0)
	await _request(true, TEAL)
	assert_str(_s.selected_uid()).is_equal(VASE)
	assert_array(_s.selection_timeline).is_equal(timeline)
	assert_int(_marked(VASE)).is_equal(marks)


func test_ac09_undo_and_redo_restore_the_colour_and_keep_the_selection() -> void:
	if not await _open():
		return
	_select(VASE)
	await _request(true, TEAL)
	await _request(true, BRICK)
	var timeline: Array[String] = _s.selection_timeline.duplicate()
	assert_bool(_s.history.undo()).is_true()
	assert_int(_s.model.get_item(VASE).colour.to_rgba32()).is_equal(TEAL.to_rgba32())
	assert_bool(_s.history.undo()).is_true()
	assert_bool(_s.model.get_item(VASE).has_colour).is_false()
	assert_bool(_s.history.redo()).is_true()
	assert_bool(_s.history.redo()).is_true()
	assert_int(_s.model.get_item(VASE).colour.to_rgba32()).is_equal(BRICK.to_rgba32())
	assert_str(_s.selected_uid()).is_equal(VASE)
	assert_array(_s.selection_timeline).is_equal(timeline)
	assert_int(_marked(VASE)).is_greater(0)


func test_ac09_original_colour_on_a_coloured_item_clears_the_flag_with_one_command() -> void:
	if not await _open():
		return
	_select(VASE)
	await _request(true, TEAL)
	var undo_before: int = _s.history.get_undo_count()
	await _request(false, Color.WHITE)
	assert_bool(_s.model.get_item(VASE).has_colour).is_false()
	assert_int(_s.history.get_undo_count()).is_equal(undo_before + 1)
	assert_bool(_s.history.undo()).is_true()
	assert_bool(_s.model.get_item(VASE).has_colour).is_true()
	assert_int(_s.model.get_item(VASE).colour.to_rgba32()).is_equal(TEAL.to_rgba32())


func test_ac10_the_current_colour_runs_no_command() -> void:
	if not await _open():
		return
	_select(VASE)
	await _request(true, TEAL)
	_s.history.clear()
	var before_state: Dictionary = ModelState.snapshot(_s.model)
	var events: Recorder = Recorder.new()
	events.watch(_s.model)
	await _request(true, TEAL)
	_assert_unchanged(before_state, events)


func test_ac10_original_colour_on_an_uncoloured_item_runs_no_command() -> void:
	if not await _open():
		return
	_select(VASE)
	var before_state: Dictionary = ModelState.snapshot(_s.model)
	var events: Recorder = Recorder.new()
	events.watch(_s.model)
	await _request(false, Color.WHITE)
	_assert_unchanged(before_state, events)


func test_ac07_a_request_on_a_non_colourable_item_does_nothing() -> void:
	if not await _open():
		return
	_select(STONE_UID)
	var before_state: Dictionary = ModelState.snapshot(_s.model)
	var events: Recorder = Recorder.new()
	events.watch(_s.model)
	await _request(true, TEAL)
	await _request(false, Color.WHITE)
	_assert_unchanged(before_state, events)
	assert_str(_s.selected_uid()).is_equal(STONE_UID)


func test_ac07_a_stored_colour_on_a_non_colourable_item_is_not_changed_by_a_request() -> void:
	var model: AquariumModel = _model()
	model.get_item(STONE_UID).has_colour = true
	model.get_item(STONE_UID).colour = BRICK
	if not await _open(model):
		return
	_select(STONE_UID)
	var before_state: Dictionary = ModelState.snapshot(_s.model)
	var events: Recorder = Recorder.new()
	events.watch(_s.model)
	await _request(false, Color.WHITE)
	await _request(true, TEAL)
	_assert_unchanged(before_state, events)


func test_ac08_a_request_without_a_selection_does_nothing() -> void:
	if not await _open():
		return
	var before_state: Dictionary = ModelState.snapshot(_s.model)
	var events: Recorder = Recorder.new()
	events.watch(_s.model)
	await _request(true, TEAL)
	_assert_unchanged(before_state, events)


func test_ac08_the_request_acts_on_the_current_selection_only() -> void:
	if not await _open():
		return
	_select(VASE)
	_select(OTHER_VASE)
	await _request(true, BRICK)
	assert_bool(_s.model.get_item(OTHER_VASE).has_colour).is_true()
	assert_bool(_s.model.get_item(VASE).has_colour).is_false()


func test_ac08_an_off_list_colour_can_be_replaced_by_a_swatch_request() -> void:
	var model: AquariumModel = _model()
	model.get_item(VASE).has_colour = true
	model.get_item(VASE).colour = Color8(1, 2, 3)
	if not await _open(model):
		return
	_select(VASE)
	await _request(true, TEAL)
	assert_int(_s.model.get_item(VASE).colour.to_rgba32()).is_equal(TEAL.to_rgba32())
	assert_bool(_s.history.undo()).is_true()
	assert_int(_s.model.get_item(VASE).colour.to_rgba32()).is_equal(Color8(1, 2, 3).to_rgba32())


func test_ac08_a_request_during_a_drag_a_hold_or_a_blocker_does_nothing() -> void:
	if not await _open():
		return
	_select(VASE)
	_s.key(KEY_COMMA, true)
	assert_bool(_s.holding()).is_true()
	await _request(true, TEAL)
	assert_bool(_s.model.get_item(VASE).has_colour).is_false()
	_s.key(KEY_COMMA, false)
	var undo_after_rotate: int = _s.history.get_undo_count()
	var blocker: Control = _s.make_blocker()
	_s.set_blocked(blocker, true)
	await _request(true, TEAL)
	_s.set_blocked(blocker, false)
	assert_bool(_s.model.get_item(VASE).has_colour).is_false()
	var start: Vector2 = _s.screen_of_item(VASE)
	_s.press(start)
	_s.move(start + Vector2(Api.tuning("DRAG_THRESHOLD_PX") + 4.0, 0.0))
	assert_bool(_s.dragging()).is_true()
	await _request(true, TEAL)
	assert_bool(_s.model.get_item(VASE).has_colour).is_false()
	_s.release(start)
	assert_int(_s.history.get_undo_count()).is_less_equal(undo_after_rotate + 1)


func test_ac08_a_busy_history_is_not_asked() -> void:
	if not await _open():
		return
	_select(VASE)
	var fake: Command = BusyRecolourCommand.new(self)
	assert_bool(_s.history.execute(fake)).is_true()
	assert_bool(_s.model.get_item(VASE).has_colour).is_false()
	assert_int(_s.history.get_undo_count()).is_equal(1)


## Sends the colour request from inside do(), when the history is busy.
class BusyRecolourCommand:
	extends Command

	var _suite: Node = null

	func _init(suite: Node) -> void:
		_suite = suite

	func do() -> bool:
		_suite.call("_request", true, Color8(0x2A, 0x7F, 0x9E))
		return true

	func undo() -> bool:
		return true
