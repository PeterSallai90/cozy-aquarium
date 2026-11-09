# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #24 criteria 4 to 7, 18 and 22 (command level): the change-tank Command. ChangeTankCommand is
## reached through LateApi because it does not exist before the implementation. Contract of the
## technical plan: ChangeTankCommand.new(model, catalog, tank_id), plus the static helpers
## is_heightmap_flat(model) and would_clear(model); the Command validates first, then removes fish,
## items and (when not flat) the heightmap, and writes the tank id last.

const Api := preload("res://tests/helpers/late_api.gd")
const Rig := preload("res://tests/helpers/room_rig.gd")
const Factory := preload("res://tests/helpers/factory.gd")
const ModelState := preload("res://tests/helpers/model_state.gd")
const Recorder := preload("res://tests/helpers/signal_recorder.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")
const Table := preload("res://tests/helpers/tank_table.gd")

const STAMP := "2026-11-01T12:00:00Z"
const SAND := Color(0.8, 0.7, 0.5)

var _model: AquariumModel = null
var _history: CommandHistory = null
var _catalog: RefCounted = null


func before_test() -> void:
	_catalog = Rig.default_catalog()
	_history = CommandHistory.new()


## Three items, two fish, a substrate and a 3 x 2 heightmap on the given tank.
func _furnished(tank_id: StringName = Table.MEDIUM) -> AquariumModel:
	var model: AquariumModel = AquariumModel.new(STAMP)
	model.apply_set_name("Reef")
	model.apply_set_tank_id(tank_id)
	model.apply_set_substrate(&"fine_sand", SAND)
	model.apply_set_heightmap(PackedFloat32Array([0.0, 0.1, 0.2, 0.3, 0.4, 0.5]), Vector2i(3, 2))
	model.apply_insert_item(Factory.item("a0000001", &"rock_a", Vector3(0.1, 0.0, 0.0)), 0)
	model.apply_insert_item(Factory.coloured_item("a0000002", Color(0.2, 0.4, 0.6)), 1)
	model.apply_insert_item(Factory.item("a0000003", &"plant_fern", Vector3(-0.2, 0.1, 0.05)), 2)
	model.apply_insert_fish(Factory.fish("f0000001", &"neon_tetra", 1, "Nemo"), 0)
	model.apply_insert_fish(Factory.fish("f0000002", &"guppy", 0, ""), 1)
	return model


func _empty(tank_id: StringName = Table.MEDIUM) -> AquariumModel:
	var model: AquariumModel = AquariumModel.new(STAMP)
	model.apply_set_tank_id(tank_id)
	return model


func _change(model: AquariumModel, tank_id: StringName) -> bool:
	return _history.execute(Api.change_tank(model, _catalog, tank_id))


func _watch(model: AquariumModel) -> Recorder:
	var recorder: Recorder = Recorder.new()
	recorder.watch(model)
	return recorder


func _count(recorder: Recorder, signal_name: String) -> int:
	var found: int = 0
	for name: String in recorder.names():
		if name == signal_name:
			found += 1
	return found


# --- the helpers the dialog and the Command share (plan section 5) ---


func test_ac04_the_command_class_exists() -> void:
	(
		assert_bool(Api.change_tank_exists())
		. override_failure_message("res://model/change_tank_command.gd is missing")
		. is_true()
	)


func test_ac24_a_new_empty_model_would_clear_nothing() -> void:
	var model: AquariumModel = _empty()
	assert_that(Api.is_heightmap_flat(model)).is_equal(true)
	assert_that(Api.would_clear(model)).is_equal(false)


func test_ac24_an_item_would_be_cleared() -> void:
	var model: AquariumModel = _empty()
	model.apply_insert_item(Factory.item("a0000001"), 0)
	assert_that(Api.would_clear(model)).is_equal(true)


func test_ac24_a_fish_would_be_cleared() -> void:
	var model: AquariumModel = _empty()
	model.apply_insert_fish(Factory.fish("f0000001"), 0)
	assert_that(Api.would_clear(model)).is_equal(true)


func test_ac24_a_sculpted_heightmap_is_not_flat() -> void:
	var model: AquariumModel = _empty()
	model.apply_set_heightmap(PackedFloat32Array([0.0, 0.2]), Vector2i(2, 1))
	assert_that(Api.is_heightmap_flat(model)).is_equal(false)
	assert_that(Api.would_clear(model)).is_equal(true)


func test_ac24_a_sized_heightmap_of_all_zeros_is_not_flat() -> void:
	# DoR note 1: flat means the empty array of size (0, 0), nothing else.
	var model: AquariumModel = _empty()
	model.apply_set_heightmap(PackedFloat32Array([0.0, 0.0, 0.0, 0.0]), Vector2i(2, 2))
	assert_that(Api.is_heightmap_flat(model)).is_equal(false)
	assert_that(Api.would_clear(model)).is_equal(true)


func test_ac24_the_empty_array_of_size_zero_is_flat_even_after_being_set_explicitly() -> void:
	var model: AquariumModel = _empty()
	model.apply_set_heightmap(PackedFloat32Array(), Vector2i.ZERO)
	assert_that(Api.is_heightmap_flat(model)).is_equal(true)
	assert_that(Api.would_clear(model)).is_equal(false)


# --- AC 4 ---


func test_ac04_tank_items_fish_and_heightmap_change_in_one_step() -> void:
	var model: AquariumModel = _furnished()
	var before: Dictionary = ModelState.snapshot(model)
	assert_bool(_change(model, Table.LARGE)).is_true()
	assert_that(model.get_tank_id()).is_equal(Table.LARGE)
	assert_int(model.get_item_count()).is_equal(0)
	assert_int(model.get_fish_count()).is_equal(0)
	assert_int(model.get_heightmap().size()).is_equal(0)
	assert_that(model.get_heightmap_size()).is_equal(Vector2i.ZERO)
	assert_str(model.get_aquarium_name()).is_equal(before["aquarium_name"])
	assert_int(_history.get_undo_count()).is_equal(1)


func test_ac04_substrate_id_and_colour_stay() -> void:
	var model: AquariumModel = _furnished()
	_change(model, Table.SMALL)
	assert_that(model.get_substrate_id()).is_equal(&"fine_sand")
	assert_that(model.get_substrate_colour()).is_equal(SAND)


func test_ac04_tank_changed_is_emitted_once_with_the_new_id() -> void:
	var model: AquariumModel = _furnished()
	var recorder: Recorder = _watch(model)
	_change(model, Table.LARGE)
	var found: Array = []
	for index: int in recorder.count():
		if recorder.events[index][0] == "tank_changed":
			found.append(recorder.args_of(index))
	assert_array(found).is_equal([[Table.LARGE]])


func test_ac04_tank_changed_comes_last_when_the_contents_are_already_gone() -> void:
	var model: AquariumModel = _furnished()
	var seen: Array = []
	model.tank_changed.connect(
		func(_id: StringName) -> void:
			seen.append(
				[
					model.get_item_count(),
					model.get_fish_count(),
					model.get_heightmap().size(),
					model.get_heightmap_size()
				]
			)
	)
	_change(model, Table.LARGE)
	assert_array(seen).is_equal([[0, 0, 0, Vector2i.ZERO]])


func test_ac04_every_removal_and_the_heightmap_reset_are_announced_once() -> void:
	var model: AquariumModel = _furnished()
	var recorder: Recorder = _watch(model)
	_change(model, Table.LARGE)
	assert_int(recorder.count()).override_failure_message("no model signal was emitted").is_greater(
		0
	)
	if recorder.count() == 0:
		return
	assert_int(_count(recorder, "item_removed")).is_equal(3)
	assert_int(_count(recorder, "fish_removed")).is_equal(2)
	assert_int(_count(recorder, "heightmap_changed")).is_equal(1)
	assert_int(_count(recorder, "tank_changed")).is_equal(1)
	assert_int(_count(recorder, "substrate_changed")).is_equal(0)
	assert_int(_count(recorder, "name_changed")).is_equal(0)
	assert_str(recorder.names()[recorder.count() - 1]).is_equal("tank_changed")


func test_ac04_an_already_flat_heightmap_is_not_written_again() -> void:
	var model: AquariumModel = _empty()
	model.apply_insert_item(Factory.item("a0000001"), 0)
	var recorder: Recorder = _watch(model)
	_change(model, Table.SMALL)
	assert_int(_count(recorder, "heightmap_changed")).is_equal(0)
	assert_int(_count(recorder, "tank_changed")).is_equal(1)


func test_ac04_a_sized_heightmap_of_zeros_is_reset_to_the_empty_map() -> void:
	var model: AquariumModel = _empty()
	model.apply_set_heightmap(PackedFloat32Array([0.0, 0.0, 0.0, 0.0]), Vector2i(2, 2))
	var recorder: Recorder = _watch(model)
	_change(model, Table.SMALL)
	assert_int(_count(recorder, "heightmap_changed")).is_equal(1)
	assert_int(model.get_heightmap().size()).is_equal(0)
	assert_that(model.get_heightmap_size()).is_equal(Vector2i.ZERO)


func test_ac04_an_empty_model_changes_only_the_tank_id() -> void:
	var model: AquariumModel = _empty()
	var recorder: Recorder = _watch(model)
	assert_bool(_change(model, Table.LARGE)).is_true()
	assert_array(recorder.names()).contains_exactly(["tank_changed"])
	assert_that(model.get_tank_id()).is_equal(Table.LARGE)


func test_ac04_created_and_modified_are_not_touched() -> void:
	var model: AquariumModel = _furnished()
	_change(model, Table.LARGE)
	assert_str(model.get_created()).is_equal(STAMP)
	assert_str(model.get_modified()).is_equal(STAMP)


func test_ac04_every_catalog_tank_can_be_chosen_from_every_other() -> void:
	for from_id: StringName in Table.IDS:
		for to_id: StringName in Table.IDS:
			if from_id == to_id:
				continue
			var model: AquariumModel = _empty(from_id)
			(
				assert_bool(_change(model, to_id))
				. override_failure_message("%s to %s" % [from_id, to_id])
				. is_true()
			)
			assert_that(model.get_tank_id()).is_equal(to_id)


# --- AC 5 ---


func test_ac05_undo_restores_tank_items_fish_heightmap_and_the_rest_exactly() -> void:
	var model: AquariumModel = _furnished()
	var before: Dictionary = ModelState.snapshot(model)
	_change(model, Table.LARGE)
	assert_bool(_history.undo()).is_true()
	assert_dict(ModelState.snapshot(model)).is_equal(before)


func test_ac05_undo_brings_back_the_same_instances_in_the_same_order() -> void:
	var model: AquariumModel = _furnished()
	var items: Array[PlacedItem] = model.get_items()
	var fish: Array[FishInstance] = model.get_fish_list()
	_change(model, Table.LARGE)
	_history.undo()
	var items_after: Array[PlacedItem] = model.get_items()
	var fish_after: Array[FishInstance] = model.get_fish_list()
	assert_int(items_after.size()).is_equal(items.size())
	for index: int in items.size():
		assert_object(items_after[index]).is_same(items[index])
	for index: int in fish.size():
		assert_object(fish_after[index]).is_same(fish[index])


func test_ac05_undo_announces_the_old_tank_before_the_contents_return() -> void:
	var model: AquariumModel = _furnished()
	_change(model, Table.LARGE)
	var recorder: Recorder = _watch(model)
	_history.undo()
	assert_int(recorder.count()).override_failure_message("no model signal was emitted").is_greater(
		0
	)
	if recorder.count() == 0:
		return
	assert_str(recorder.names()[0]).is_equal("tank_changed")
	assert_array(recorder.args_of(0)).is_equal([Table.MEDIUM])
	assert_int(_count(recorder, "tank_changed")).is_equal(1)
	assert_int(_count(recorder, "item_added")).is_equal(3)
	assert_int(_count(recorder, "fish_added")).is_equal(2)
	assert_int(_count(recorder, "heightmap_changed")).is_equal(1)


func test_ac05_redo_gives_the_state_after_the_change_again() -> void:
	var model: AquariumModel = _furnished()
	_change(model, Table.LARGE)
	var after: Dictionary = ModelState.snapshot(model)
	_history.undo()
	assert_bool(_history.redo()).is_true()
	assert_dict(ModelState.snapshot(model)).is_equal(after)
	assert_that(model.get_tank_id()).is_equal(Table.LARGE)
	assert_int(_history.get_undo_count()).is_equal(1)
	assert_int(_history.get_redo_count()).is_equal(0)


func test_ac05_undo_redo_undo_cycles_stay_exact() -> void:
	var model: AquariumModel = _furnished()
	var before: Dictionary = ModelState.snapshot(model)
	_change(model, Table.SMALL)
	var after: Dictionary = ModelState.snapshot(model)
	for cycle: int in 3:
		_history.undo()
		assert_dict(ModelState.snapshot(model)).is_equal(before)
		_history.redo()
		assert_dict(ModelState.snapshot(model)).is_equal(after)


func test_ac05_one_undo_step_undoes_the_whole_change() -> void:
	var model: AquariumModel = _furnished()
	_change(model, Table.LARGE)
	assert_int(_history.get_undo_count()).is_equal(1)
	_history.undo()
	assert_bool(_history.can_undo()).is_false()
	assert_bool(_history.can_redo()).is_true()


func test_ac05_undo_of_a_change_on_an_empty_model_restores_the_old_id() -> void:
	var model: AquariumModel = _empty(Table.SMALL)
	_change(model, Table.LARGE)
	_history.undo()
	assert_that(model.get_tank_id()).is_equal(Table.SMALL)


func test_ac05_two_changes_undo_in_reverse_order() -> void:
	var model: AquariumModel = _furnished()
	var before: Dictionary = ModelState.snapshot(model)
	_change(model, Table.SMALL)
	_change(model, Table.LARGE)
	assert_int(_history.get_undo_count()).is_equal(2)
	_history.undo()
	assert_that(model.get_tank_id()).is_equal(Table.SMALL)
	_history.undo()
	assert_dict(ModelState.snapshot(model)).is_equal(before)


# --- AC 6 ---


func test_ac06_the_same_id_changes_nothing_emits_nothing_and_adds_no_history() -> void:
	var model: AquariumModel = _furnished()
	var before: Dictionary = ModelState.snapshot(model)
	var recorder: Recorder = _watch(model)
	var history_signals: Recorder = Recorder.new()
	history_signals.watch(_history)
	var seen: Dictionary = await EngineOutput.capture_result(
		func() -> bool: return _change(model, Table.MEDIUM)
	)
	assert_bool(seen["result"]).is_false()
	assert_dict(seen["errors"]).is_empty()
	assert_dict(seen["warnings"]).is_empty()
	assert_dict(ModelState.snapshot(model)).is_equal(before)
	assert_int(recorder.count()).is_equal(0)
	assert_int(history_signals.count()).is_equal(0)
	assert_int(_history.get_undo_count()).is_equal(0)
	assert_bool(_history.can_undo()).is_false()


# --- AC 7 ---


func test_ac07_an_id_that_is_not_in_the_catalog_logs_one_error_and_changes_nothing() -> void:
	var model: AquariumModel = _furnished()
	var before: Dictionary = ModelState.snapshot(model)
	var recorder: Recorder = _watch(model)
	var seen: Dictionary = await EngineOutput.capture_result(
		func() -> bool: return _change(model, &"no_such_tank")
	)
	assert_bool(seen["result"]).is_false()
	assert_dict(seen["errors"]).is_equal({'ChangeTankCommand: unknown tank id "no_such_tank"': 1})
	assert_dict(seen["warnings"]).is_empty()
	assert_dict(ModelState.snapshot(model)).is_equal(before)
	assert_int(recorder.count()).is_equal(0)
	assert_int(_history.get_undo_count()).is_equal(0)


func test_ac07_an_empty_id_logs_one_error_and_changes_nothing() -> void:
	var model: AquariumModel = _furnished()
	var before: Dictionary = ModelState.snapshot(model)
	var recorder: Recorder = _watch(model)
	var seen: Dictionary = await EngineOutput.capture_result(
		func() -> bool: return _change(model, &"")
	)
	assert_bool(seen["result"]).is_false()
	assert_dict(seen["errors"]).is_equal({'ChangeTankCommand: unknown tank id ""': 1})
	assert_dict(ModelState.snapshot(model)).is_equal(before)
	assert_int(recorder.count()).is_equal(0)
	assert_int(_history.get_undo_count()).is_equal(0)


func test_ac07_an_empty_catalog_rejects_every_id() -> void:
	var model: AquariumModel = _furnished()
	var empty_catalog: RefCounted = Api.catalog_from([])
	var seen: Dictionary = await EngineOutput.capture_result(
		func() -> bool: return _history.execute(Api.change_tank(model, empty_catalog, Table.LARGE))
	)
	assert_bool(seen["result"]).is_false()
	assert_dict(seen["errors"]).is_equal({'ChangeTankCommand: unknown tank id "tank_large_1"': 1})
	assert_that(model.get_tank_id()).is_equal(Table.MEDIUM)


# --- AC 18 (command level) ---


func test_ac18_picking_medium_while_the_model_holds_an_unknown_id_is_a_real_change() -> void:
	var model: AquariumModel = _furnished(&"tank_from_the_future")
	var before: Dictionary = ModelState.snapshot(model)
	var recorder: Recorder = _watch(model)
	assert_bool(_change(model, Table.MEDIUM)).is_true()
	assert_that(model.get_tank_id()).is_equal(Table.MEDIUM)
	assert_int(model.get_item_count()).is_equal(0)
	assert_int(model.get_fish_count()).is_equal(0)
	assert_int(model.get_heightmap().size()).is_equal(0)
	assert_int(_count(recorder, "tank_changed")).is_equal(1)
	assert_int(_history.get_undo_count()).is_equal(1)
	_history.undo()
	assert_dict(ModelState.snapshot(model)).is_equal(before)
	assert_that(model.get_tank_id()).is_equal(&"tank_from_the_future")


func test_ac18_picking_medium_on_an_empty_model_with_an_unknown_id_still_writes_the_id() -> void:
	var model: AquariumModel = _empty(&"tank_from_the_future")
	assert_bool(_change(model, Table.MEDIUM)).is_true()
	assert_that(model.get_tank_id()).is_equal(Table.MEDIUM)
	assert_int(_history.get_undo_count()).is_equal(1)
	_history.undo()
	assert_that(model.get_tank_id()).is_equal(&"tank_from_the_future")


func test_ac18_the_old_medium_id_of_a_pre_rename_save_is_replaced_by_the_pick() -> void:
	var model: AquariumModel = _empty(&"tank_medium_60l")
	assert_bool(_change(model, Table.MEDIUM)).is_true()
	assert_that(model.get_tank_id()).is_equal(Table.MEDIUM)


# --- AC 22 (command level) ---


func test_ac22_a_catalog_tank_whose_scene_fails_to_load_is_still_written_by_the_command() -> void:
	var broken: Resource = Rig.variant(&"tank_broken", null)
	var catalog: RefCounted = Api.catalog_from([Rig.default_definition(), broken])
	var model: AquariumModel = _furnished()
	var before: Dictionary = ModelState.snapshot(model)
	var seen: Dictionary = await EngineOutput.capture_result(
		func() -> bool: return _history.execute(Api.change_tank(model, catalog, &"tank_broken"))
	)
	assert_bool(seen["result"]).is_true()
	assert_dict(seen["errors"]).is_empty()
	assert_that(model.get_tank_id()).is_equal(&"tank_broken")
	assert_int(_history.get_undo_count()).is_equal(1)
	_history.undo()
	assert_dict(ModelState.snapshot(model)).is_equal(before)
