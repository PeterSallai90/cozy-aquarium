# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #28 criteria 4 to 8, 10 and 22 (owner: developer): SetSubstrateCommand through a CommandHistory.
## The Command is literal (BA decision Q2): it writes exactly the id and colour it is given, after
## checking them against the catalog, and rejects the state the model already has. The "choosing a
## type resets the colour" rule is the pick helper's, not tested here. Swatches are addressed by
## number from the catalog, never by hex, except the Sand default.

const Sub := preload("res://tests/helpers/substrate_api.gd")
const Recorder := preload("res://tests/helpers/signal_recorder.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")
const ModelState := preload("res://tests/helpers/model_state.gd")

var _catalog: RefCounted = null
var _history: CommandHistory = null


func before_test() -> void:
	_catalog = Sub.catalog()
	_history = CommandHistory.new()


func _run(model: AquariumModel, id: StringName, colour: Color) -> bool:
	return _history.execute(Sub.command(model, _catalog, id, colour))


func _same(actual: Color, expected: Color) -> void:
	(
		assert_bool(Sub.same_colour(actual, expected))
		. override_failure_message("expected %s, got %s" % [Sub.hex(expected), Sub.hex(actual)])
		. is_true()
	)


func _at_default(id: StringName) -> AquariumModel:
	return Sub.model_with(id, Sub.default_colour(_catalog, id))


## The substrate_changed events as [[id, colour], ...].
func _changes(recorder: Recorder) -> Array:
	var found: Array = []
	for index: int in recorder.count():
		if recorder.events[index][0] == "substrate_changed":
			found.append(recorder.args_of(index))
	return found


# --- AC 4: a type change, all 20 ordered pairs ---


func test_ac04_the_command_class_exists() -> void:
	(
		assert_bool(Sub.command_exists())
		. override_failure_message("res://model/set_substrate_command.gd is missing")
		. is_true()
	)


func test_ac04_every_ordered_pair_of_types_changes_id_and_default_colour_in_one_entry() -> void:
	for from_id: StringName in Sub.IDS:
		for to_id: StringName in Sub.IDS:
			if from_id == to_id:
				continue
			_history = CommandHistory.new()
			var model: AquariumModel = _at_default(from_id)
			var target: Color = Sub.default_colour(_catalog, to_id)
			var recorder: Recorder = Recorder.new()
			recorder.watch(model)
			var label: String = "%s -> %s" % [from_id, to_id]
			assert_bool(_run(model, to_id, target)).override_failure_message(label).is_true()
			assert_that(model.get_substrate_id()).override_failure_message(label).is_equal(to_id)
			_same(model.get_substrate_colour(), target)
			var changes: Array = _changes(recorder)
			assert_int(changes.size()).override_failure_message(label).is_equal(1)
			assert_array(recorder.names()).override_failure_message(label).is_equal(
				["substrate_changed"]
			)
			if changes.size() == 1:
				assert_that(changes[0][0]).is_equal(to_id)
				_same(changes[0][1], target)
			assert_int(_history.get_undo_count()).override_failure_message(label).is_equal(1)


func test_ac04_a_type_change_then_a_colour_change_are_two_entries() -> void:
	var model: AquariumModel = _at_default(Sub.SAND)
	assert_bool(_run(model, Sub.GRAVEL, Sub.default_colour(_catalog, Sub.GRAVEL))).is_true()
	assert_bool(_run(model, Sub.GRAVEL, Sub.swatch(_catalog, Sub.GRAVEL, 2))).is_true()
	assert_int(_history.get_undo_count()).is_equal(2)


# --- AC 5: a colour change ---


func test_ac05_swatch_2_of_coloured_gravel_keeps_the_id_and_sets_the_colour() -> void:
	var model: AquariumModel = _at_default(Sub.COLOURED)
	var second: Color = Sub.swatch(_catalog, Sub.COLOURED, 2)
	var recorder: Recorder = Recorder.new()
	recorder.watch(model)
	assert_bool(_run(model, Sub.COLOURED, second)).is_true()
	assert_that(model.get_substrate_id()).is_equal(Sub.COLOURED)
	_same(model.get_substrate_colour(), second)
	assert_array(recorder.names()).is_equal(["substrate_changed"])
	var changes: Array = _changes(recorder)
	if changes.size() == 1:
		assert_that(changes[0][0]).is_equal(Sub.COLOURED)
		_same(changes[0][1], second)
	assert_int(_history.get_undo_count()).is_equal(1)


func test_ac05_every_swatch_of_every_type_can_be_applied_with_one_signal_and_one_entry() -> void:
	for id: StringName in Sub.IDS:
		var list: Array[Color] = Sub.swatches(_catalog, id)
		assert_int(list.size()).is_greater(1)
		for number: int in range(2, list.size() + 1):
			_history = CommandHistory.new()
			var model: AquariumModel = _at_default(id)
			var recorder: Recorder = Recorder.new()
			recorder.watch(model)
			var label: String = "%s swatch %d" % [id, number]
			assert_bool(_run(model, id, list[number - 1])).override_failure_message(label).is_true()
			_same(model.get_substrate_colour(), list[number - 1])
			assert_int(_changes(recorder).size()).override_failure_message(label).is_equal(1)
			assert_int(_history.get_undo_count()).override_failure_message(label).is_equal(1)


func test_ac05_the_stored_colour_is_the_catalog_swatch_even_when_given_with_float_noise() -> void:
	var model: AquariumModel = _at_default(Sub.GRAVEL)
	var exact: Color = Sub.swatch(_catalog, Sub.GRAVEL, 2)
	var noisy: Color = Color(exact.r + 0.0004, exact.g - 0.0004, exact.b, 1.0)
	assert_bool(_run(model, Sub.GRAVEL, noisy)).is_true()
	assert_that(model.get_substrate_colour()).is_equal(exact)


# --- AC 6: undo and redo ---


func test_ac06_undo_and_redo_are_exact_for_all_ordered_pairs() -> void:
	for from_id: StringName in Sub.IDS:
		for to_id: StringName in Sub.IDS:
			if from_id == to_id:
				continue
			_history = CommandHistory.new()
			var model: AquariumModel = _at_default(from_id)
			var before: Color = model.get_substrate_colour()
			var target: Color = Sub.default_colour(_catalog, to_id)
			var label: String = "%s -> %s" % [from_id, to_id]
			assert_bool(_run(model, to_id, target)).override_failure_message(label).is_true()
			var recorder: Recorder = Recorder.new()
			recorder.watch(model)
			assert_bool(_history.undo()).override_failure_message(label).is_true()
			assert_that(model.get_substrate_id()).override_failure_message(label).is_equal(from_id)
			assert_that(model.get_substrate_colour()).is_equal(before)
			var undone: Array = _changes(recorder)
			assert_int(undone.size()).override_failure_message(label).is_equal(1)
			if undone.size() == 1:
				assert_that(undone[0][0]).is_equal(from_id)
				assert_that(undone[0][1]).is_equal(before)
			recorder.clear()
			assert_bool(_history.redo()).override_failure_message(label).is_true()
			assert_that(model.get_substrate_id()).override_failure_message(label).is_equal(to_id)
			_same(model.get_substrate_colour(), target)
			var redone: Array = _changes(recorder)
			assert_int(redone.size()).override_failure_message(label).is_equal(1)
			if redone.size() == 1:
				assert_that(redone[0][0]).is_equal(to_id)
				_same(redone[0][1], target)


func test_ac06_undo_and_redo_of_a_colour_change_are_exact() -> void:
	var model: AquariumModel = _at_default(Sub.COLOURED)
	var first: Color = model.get_substrate_colour()
	var second: Color = Sub.swatch(_catalog, Sub.COLOURED, 2)
	assert_bool(_run(model, Sub.COLOURED, second)).is_true()
	assert_bool(_history.undo()).is_true()
	assert_that(model.get_substrate_id()).is_equal(Sub.COLOURED)
	assert_that(model.get_substrate_colour()).is_equal(first)
	assert_bool(_history.redo()).is_true()
	assert_that(model.get_substrate_colour()).is_equal(second)


func test_ac06_undo_of_a_change_from_a_loaded_non_swatch_colour_restores_it_exactly() -> void:
	var model: AquariumModel = Sub.model_with(Sub.SAND, Sub.NOT_A_SWATCH)
	assert_bool(_run(model, Sub.SAND, Sub.default_colour(_catalog, Sub.SAND))).is_true()
	_same(model.get_substrate_colour(), Sub.SAND_DEFAULT)
	assert_bool(_history.undo()).is_true()
	assert_that(model.get_substrate_colour()).is_equal(Sub.NOT_A_SWATCH)


func test_ac06_undo_redo_cycles_stay_exact() -> void:
	var model: AquariumModel = _at_default(Sub.SAND)
	var target: Color = Sub.default_colour(_catalog, Sub.BLACK)
	assert_bool(_run(model, Sub.BLACK, target)).is_true()
	for cycle: int in 3:
		assert_bool(_history.undo()).override_failure_message("undo %d" % cycle).is_true()
		assert_that(model.get_substrate_id()).is_equal(Sub.SAND)
		assert_bool(_history.redo()).override_failure_message("redo %d" % cycle).is_true()
		assert_that(model.get_substrate_id()).is_equal(Sub.BLACK)
		_same(model.get_substrate_colour(), target)


# --- AC 7: nothing else changes ---


func _without_substrate(snapshot: Dictionary) -> Dictionary:
	var copy: Dictionary = snapshot.duplicate(true)
	copy.erase("substrate_id")
	copy.erase("substrate_colour")
	return copy


func test_ac07_everything_else_is_identical_after_a_type_change_and_after_undo() -> void:
	var model: AquariumModel = Sub.furnished(Sub.SAND, Sub.SAND_DEFAULT)
	assert_int(model.get_item_count()).is_equal(3)
	assert_int(model.get_fish_count()).is_equal(2)
	var before: Dictionary = ModelState.snapshot(model)
	assert_bool(_run(model, Sub.PEBBLES, Sub.default_colour(_catalog, Sub.PEBBLES))).is_true()
	assert_that(_without_substrate(ModelState.snapshot(model))).is_equal(_without_substrate(before))
	assert_bool(_history.undo()).is_true()
	assert_that(ModelState.snapshot(model)).is_equal(before)


func test_ac07_everything_else_is_identical_after_a_colour_change_and_after_undo() -> void:
	var model: AquariumModel = Sub.furnished(Sub.GRAVEL, Sub.default_colour(_catalog, Sub.GRAVEL))
	var before: Dictionary = ModelState.snapshot(model)
	assert_bool(_run(model, Sub.GRAVEL, Sub.swatch(_catalog, Sub.GRAVEL, 2))).is_true()
	assert_that(_without_substrate(ModelState.snapshot(model))).is_equal(_without_substrate(before))
	assert_bool(_history.undo()).is_true()
	assert_that(ModelState.snapshot(model)).is_equal(before)


func test_ac07_the_command_emits_only_substrate_changed_on_a_furnished_model() -> void:
	var model: AquariumModel = Sub.furnished(Sub.SAND, Sub.SAND_DEFAULT)
	var recorder: Recorder = Recorder.new()
	recorder.watch(model)
	_run(model, Sub.BLACK, Sub.default_colour(_catalog, Sub.BLACK))
	_history.undo()
	assert_array(recorder.names()).is_equal(["substrate_changed", "substrate_changed"])


# --- AC 8: the no-op ---


## The no-op tests only mean something when the Command and the catalog exist: a missing class
## also "returns false". Fails once with a readable message.
func _ready_to_run(id: StringName = Sub.SAND) -> void:
	(
		assert_bool(Sub.command_exists())
		. override_failure_message("res://model/set_substrate_command.gd is missing")
		. is_true()
	)
	(
		assert_object(Sub.definition(_catalog, id))
		. override_failure_message("%s is not in the catalog" % id)
		. is_not_null()
	)


func test_ac08_the_same_id_and_colour_returns_false_with_no_signal_and_no_entry() -> void:
	_ready_to_run()
	var model: AquariumModel = _at_default(Sub.SAND)
	var recorder: Recorder = Recorder.new()
	recorder.watch(model)
	var seen: Dictionary = await EngineOutput.capture_result(
		func() -> Variant: return _run(model, Sub.SAND, Sub.SAND_DEFAULT)
	)
	assert_that(seen["result"]).is_equal(false)
	assert_int(recorder.count()).is_equal(0)
	assert_int(_history.get_undo_count()).is_equal(0)
	assert_dict(seen["errors"]).is_empty()
	assert_dict(seen["warnings"]).is_empty()


func test_ac08_the_swatch_already_in_use_is_a_silent_no_op_for_every_type() -> void:
	_ready_to_run()
	for id: StringName in Sub.IDS:
		var colour: Color = Sub.swatch(_catalog, id, 2)
		var model: AquariumModel = Sub.model_with(id, colour)
		var seen: Dictionary = await EngineOutput.capture_result(
			func() -> Variant: return _run(model, id, colour)
		)
		assert_that(seen["result"]).override_failure_message(String(id)).is_equal(false)
		assert_dict(seen["errors"]).is_empty()
	assert_int(_history.get_undo_count()).is_equal(0)


func test_ac08_equal_state_is_compared_at_8_bit_precision() -> void:
	_ready_to_run(Sub.GRAVEL)
	var model: AquariumModel = _at_default(Sub.GRAVEL)
	var exact: Color = model.get_substrate_colour()
	var noisy: Color = Color(exact.r + 0.0004, exact.g, exact.b - 0.0004, 1.0)
	var seen: Dictionary = await EngineOutput.capture_result(
		func() -> Variant: return _run(model, Sub.GRAVEL, noisy)
	)
	assert_that(seen["result"]).is_equal(false)
	assert_int(_history.get_undo_count()).is_equal(0)


func test_ac08_a_loaded_non_swatch_colour_repeated_is_a_silent_no_op() -> void:
	# The equal-state check runs before the swatch check (plan section 2), so AC 20 logs nothing.
	_ready_to_run()
	var model: AquariumModel = Sub.model_with(Sub.SAND, Sub.NOT_A_SWATCH)
	var seen: Dictionary = await EngineOutput.capture_result(
		func() -> Variant: return _run(model, Sub.SAND, Sub.NOT_A_SWATCH)
	)
	assert_that(seen["result"]).is_equal(false)
	assert_dict(seen["errors"]).is_empty()
	assert_int(_history.get_undo_count()).is_equal(0)


# --- AC 10: rejections ---


func _rejected(id: StringName, colour: Color, needle: String, label: String) -> void:
	var model: AquariumModel = _at_default(Sub.SAND)
	var before: Dictionary = ModelState.snapshot(model)
	var recorder: Recorder = Recorder.new()
	recorder.watch(model)
	var seen: Dictionary = await EngineOutput.capture_result(
		func() -> Variant: return _run(model, id, colour)
	)
	assert_that(seen["result"]).override_failure_message(label).is_equal(false)
	var errors: Dictionary = seen["errors"]
	assert_int(errors.size()).override_failure_message("%s: errors %s" % [label, errors]).is_equal(
		1
	)
	if errors.size() == 1:
		assert_str(str(errors.keys()[0])).override_failure_message(label).contains(needle)
		assert_int(int(errors.values()[0])).override_failure_message(label).is_equal(1)
	assert_dict(seen["warnings"]).override_failure_message(label).is_empty()
	assert_that(ModelState.snapshot(model)).override_failure_message(label).is_equal(before)
	assert_int(recorder.count()).override_failure_message(label).is_equal(0)
	assert_int(_history.get_undo_count()).override_failure_message(label).is_equal(0)


func test_ac10_an_unknown_id_is_refused_with_an_error() -> void:
	await _rejected(Sub.UNKNOWN_ID, Sub.SAND_DEFAULT, Sub.ERR_UNKNOWN_ID, "unknown id")


func test_ac10_the_error_names_the_unknown_id() -> void:
	var model: AquariumModel = _at_default(Sub.SAND)
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void: _run(model, Sub.UNKNOWN_ID, Sub.SAND_DEFAULT)
	)
	var errors: Dictionary = seen["errors"]
	assert_int(errors.size()).is_equal(1)
	if errors.size() == 1:
		assert_str(str(errors.keys()[0])).contains(String(Sub.UNKNOWN_ID))


func test_ac10_an_empty_id_is_refused_with_an_error() -> void:
	await _rejected(&"", Sub.SAND_DEFAULT, Sub.ERR_UNKNOWN_ID, "empty id")


func test_ac10_a_known_id_with_a_colour_that_is_no_swatch_is_refused_with_an_error() -> void:
	await _rejected(Sub.GRAVEL, Sub.NOT_A_SWATCH, Sub.ERR_COLOUR, "non-swatch colour")


func test_ac10_a_swatch_of_another_type_is_refused() -> void:
	# Coloured gravel swatch 2 is a swatch of Coloured gravel only.
	await _rejected(Sub.SAND, Sub.swatch(_catalog, Sub.COLOURED, 2), Sub.ERR_COLOUR, "wrong type")


func test_ac10_a_type_change_with_a_colour_that_is_not_its_swatch_is_refused() -> void:
	# Picking Pebbles but passing the Sand default: choosing the right colour is the pick helper's.
	await _rejected(Sub.PEBBLES, Sub.SAND_DEFAULT, Sub.ERR_COLOUR, "sand colour on pebbles")


func test_ac10_a_null_catalog_refuses_with_an_error_and_changes_nothing() -> void:
	var model: AquariumModel = _at_default(Sub.SAND)
	var before: Dictionary = ModelState.snapshot(model)
	var seen: Dictionary = await EngineOutput.capture_result(
		func() -> Variant:
			return _history.execute(Sub.command(model, null, Sub.GRAVEL, Sub.SAND_DEFAULT))
	)
	assert_that(seen["result"]).is_equal(false)
	var errors: Dictionary = seen["errors"]
	assert_int(errors.size()).is_equal(1)
	assert_that(ModelState.snapshot(model)).is_equal(before)
	assert_int(_history.get_undo_count()).is_equal(0)


func test_ac10_a_refused_command_keeps_the_redo_stack() -> void:
	var model: AquariumModel = _at_default(Sub.SAND)
	assert_bool(_run(model, Sub.GRAVEL, Sub.default_colour(_catalog, Sub.GRAVEL))).is_true()
	assert_bool(_history.undo()).is_true()
	await EngineOutput.capture(func() -> void: _run(model, Sub.UNKNOWN_ID, Sub.SAND_DEFAULT))
	assert_bool(_history.can_redo()).is_true()


# --- AC 22: the destructive path ---


func test_ac22_gravel_swatch_3_then_pebbles_drops_the_swatch_and_undo_restores_it() -> void:
	var model: AquariumModel = Sub.model_with(Sub.GRAVEL, Sub.swatch(_catalog, Sub.GRAVEL, 3))
	var swatch_3: Color = model.get_substrate_colour()
	var pebbles_default: Color = Sub.default_colour(_catalog, Sub.PEBBLES)
	# The colour a chooser click passes comes from the pick helper.
	var picked: Color = Sub.pick(_catalog, Sub.GRAVEL, swatch_3, Sub.PEBBLES)
	_same(picked, pebbles_default)
	var recorder: Recorder = Recorder.new()
	recorder.watch(model)
	assert_bool(_run(model, Sub.PEBBLES, picked)).is_true()
	assert_that(model.get_substrate_id()).is_equal(Sub.PEBBLES)
	_same(model.get_substrate_colour(), pebbles_default)
	assert_int(_changes(recorder).size()).is_equal(1)
	assert_int(_history.get_undo_count()).is_equal(1)
	assert_bool(_history.undo()).is_true()
	assert_that(model.get_substrate_id()).is_equal(Sub.GRAVEL)
	assert_that(model.get_substrate_colour()).is_equal(swatch_3)
	assert_bool(_history.redo()).is_true()
	assert_that(model.get_substrate_id()).is_equal(Sub.PEBBLES)
	_same(model.get_substrate_colour(), pebbles_default)
