extends GdUnitTestSuite
## #32 AC 8, 9 and 10 (model part; owner: developer): RecolourItemCommand(model, uid, has_colour,
## colour). One item_changed per do and per undo; uid, catalog_id, position, rotation, scale and
## the list order stay; undo restores the exact colour state from before (an earlier colour or
## has_colour = false), redo the new one; "Original colour" (has_colour false) on a coloured item
## clears the flag; a request equal to the current state (by to_rgba32, or Original on an
## uncoloured item) and a missing uid make do() return false with no change, no signal and no
## history entry. The command is catalog-free: it recolours any item, the caller checks colourable.
## Test decision: the engine output of a refused do() is not pinned.

const Api := preload("res://tests/helpers/edit_api.gd")
const Factory := preload("res://tests/helpers/factory.gd")
const ModelState := preload("res://tests/helpers/model_state.gd")
const Recorder := preload("res://tests/helpers/signal_recorder.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")

const A := "a0000001"
const B := "a0000002"
const TEAL := Color8(0x2A, 0x7F, 0x9E)
const BRICK := Color8(0xB5, 0x4A, 0x33)

var _history: CommandHistory = null


func before_test() -> void:
	_history = CommandHistory.new()


func _have() -> bool:
	var found: bool = Api.exists(Api.RECOLOUR)
	(
		assert_bool(found)
		. override_failure_message("game/model/recolour_item_command.gd is missing")
		. is_true()
	)
	return found


## B is an amphora with a free angle and a scale, between two other items.
func _model(coloured: bool = false) -> AquariumModel:
	var model: AquariumModel = AquariumModel.new("2026-11-01T12:00:00Z")
	model.apply_set_tank_id(&"tank_medium_1")
	model.apply_insert_item(Factory.item(A, &"river_stone", Vector3(-0.1, 0, 0), 5.0, 1.0), 0)
	var middle: PlacedItem = Factory.item(B, &"clay_amphora", Vector3(0.1, 0, 0.05), 37.5, 1.5)
	if coloured:
		middle.has_colour = true
		middle.colour = TEAL
	model.apply_insert_item(middle, 1)
	model.apply_insert_item(Factory.item("a0000003", &"driftwood_branch"), 2)
	return model


func _recolour(model: AquariumModel, has_colour: bool, colour: Color, uid: String = B) -> bool:
	return _history.execute(Api.recolour_command(model, uid, has_colour, colour))


func _state(model: AquariumModel) -> Dictionary:
	var state: Dictionary = ModelState.snapshot(model)
	state.erase("modified")
	return state


func test_ac08_the_command_is_a_command_subclass() -> void:
	if not _have():
		return
	assert_bool(Api.recolour_command(_model(), B, true, TEAL) is Command).is_true()


func test_ac08_do_sets_the_colour_with_exactly_one_item_changed() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	var recorder: Recorder = Recorder.new()
	recorder.watch(model)
	assert_bool(_recolour(model, true, TEAL)).is_true()
	assert_array(recorder.names()).is_equal(["item_changed"])
	assert_array(recorder.args_of(0)).is_equal([B, 1])
	var item: PlacedItem = model.get_item(B)
	assert_bool(item.has_colour).is_true()
	assert_int(item.colour.to_rgba32()).is_equal(TEAL.to_rgba32())
	assert_int(_history.get_undo_count()).is_equal(1)


func test_ac08_uid_catalog_id_transform_and_list_order_stay() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	assert_bool(_recolour(model, true, BRICK)).is_true()
	var item: PlacedItem = model.get_item(B)
	assert_str(item.uid).is_equal(B)
	assert_that(item.catalog_id).is_equal(&"clay_amphora")
	assert_vector(item.position).is_equal(Vector3(0.1, 0.0, 0.05))
	assert_float(item.rotation_y).is_equal(37.5)
	assert_float(item.scale).is_equal(1.5)
	assert_int(model.get_item_index(B)).is_equal(1)
	assert_int(model.get_item_count()).is_equal(3)
	assert_bool(model.get_item(A).has_colour).is_false()


func test_ac09_undo_restores_the_uncoloured_state_and_redo_the_new_colour() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	var before: Dictionary = _state(model)
	assert_bool(_recolour(model, true, TEAL)).is_true()
	var after: Dictionary = _state(model)
	var recorder: Recorder = Recorder.new()
	recorder.watch(model)
	assert_bool(_history.undo()).is_true()
	assert_array(recorder.names()).is_equal(["item_changed"])
	assert_dict(_state(model)).is_equal(before)
	assert_bool(model.get_item(B).has_colour).is_false()
	assert_bool(_history.redo()).is_true()
	assert_array(recorder.names()).is_equal(["item_changed", "item_changed"])
	assert_dict(_state(model)).is_equal(after)


func test_ac09_undo_restores_the_earlier_swatch() -> void:
	if not _have():
		return
	var model: AquariumModel = _model(true)
	assert_bool(_recolour(model, true, BRICK)).is_true()
	assert_int(model.get_item(B).colour.to_rgba32()).is_equal(BRICK.to_rgba32())
	assert_bool(_history.undo()).is_true()
	assert_bool(model.get_item(B).has_colour).is_true()
	assert_int(model.get_item(B).colour.to_rgba32()).is_equal(TEAL.to_rgba32())
	assert_bool(_history.redo()).is_true()
	assert_int(model.get_item(B).colour.to_rgba32()).is_equal(BRICK.to_rgba32())


func test_ac09_original_colour_clears_the_flag_with_one_command_and_undo_restores_it() -> void:
	if not _have():
		return
	var model: AquariumModel = _model(true)
	var before: Dictionary = _state(model)
	var recorder: Recorder = Recorder.new()
	recorder.watch(model)
	assert_bool(_recolour(model, false, Color.WHITE)).is_true()
	assert_array(recorder.names()).is_equal(["item_changed"])
	assert_bool(model.get_item(B).has_colour).is_false()
	assert_int(_history.get_undo_count()).is_equal(1)
	assert_bool(_history.undo()).is_true()
	assert_dict(_state(model)).is_equal(before)
	assert_bool(model.get_item(B).has_colour).is_true()
	assert_int(model.get_item(B).colour.to_rgba32()).is_equal(TEAL.to_rgba32())


func test_ac09_the_colour_argument_is_ignored_when_has_colour_is_false() -> void:
	if not _have():
		return
	var model: AquariumModel = _model(true)
	assert_bool(_recolour(model, false, BRICK)).is_true()
	assert_bool(model.get_item(B).has_colour).is_false()
	assert_int(model.get_item(B).colour.to_rgba32()).is_equal(Color.WHITE.to_rgba32())


func test_ac09_the_commands_never_touch_created() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	model.set_save_times("2026-01-01T00:00:00Z", "2026-02-02T00:00:00Z")
	assert_bool(_recolour(model, true, TEAL)).is_true()
	assert_bool(_history.undo()).is_true()
	assert_bool(_history.redo()).is_true()
	assert_str(model.get_created()).is_equal("2026-01-01T00:00:00Z")


func test_ac09_do_is_repeatable_after_undo_when_called_directly() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	var command: Command = Api.recolour_command(model, B, true, TEAL)
	var before: Dictionary = _state(model)
	assert_bool(command.do()).is_true()
	assert_bool(command.undo()).is_true()
	assert_dict(_state(model)).is_equal(before)
	assert_bool(command.do()).is_true()
	assert_bool(model.get_item(B).has_colour).is_true()


func _refused(model: AquariumModel, has_colour: bool, colour: Color, uid: String = B) -> void:
	var before: Dictionary = ModelState.snapshot(model)
	var recorder: Recorder = Recorder.new()
	recorder.watch(model)
	var outcome: Array = []
	var command: Command = Api.recolour_command(model, uid, has_colour, colour)
	await EngineOutput.capture(func() -> void: outcome.append(_history.execute(command)))
	assert_bool(outcome[0]).is_false()
	assert_dict(ModelState.snapshot(model)).is_equal(before)
	assert_int(recorder.count()).is_equal(0)
	assert_int(_history.get_undo_count()).is_equal(0)


func test_ac10_the_current_colour_is_refused() -> void:
	if not _have():
		return
	await _refused(_model(true), true, TEAL)


func test_ac10_the_current_colour_is_compared_by_rgba32_not_by_float_bits() -> void:
	if not _have():
		return
	var nearly: Color = Color(TEAL.r + 0.0004, TEAL.g - 0.0004, TEAL.b, 1.0)
	assert_int(nearly.to_rgba32()).is_equal(TEAL.to_rgba32())
	await _refused(_model(true), true, nearly)


func test_ac10_original_colour_on_an_uncoloured_item_is_refused() -> void:
	if not _have():
		return
	await _refused(_model(), false, Color.WHITE)
	await _refused(_model(), false, BRICK)


func test_ac10_a_missing_uid_is_refused_without_a_change_or_a_signal() -> void:
	if not _have():
		return
	await _refused(_model(), true, TEAL, "ffffffff")
	await _refused(_model(), false, Color.WHITE, "ffffffff")


func test_ac10_a_different_colour_by_one_8_bit_step_is_accepted() -> void:
	if not _have():
		return
	var model: AquariumModel = _model(true)
	var other: Color = Color8(0x2A, 0x7F, 0x9F)
	assert_bool(_recolour(model, true, other)).is_true()
	assert_int(model.get_item(B).colour.to_rgba32()).is_equal(other.to_rgba32())
