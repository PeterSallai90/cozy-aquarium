extends GdUnitTestSuite
## #36 Add command (owner: developer): AddFishCommand(model, fish). The caller fixes the whole
## instance, uid included. do() appends at the end and emits one fish_added; undo() removes it;
## redo re-inserts it at the stored index with the same uid, species, variant and nickname. A used
## uid, an empty uid or a null fish or model make do() return false with the model untouched, no
## signal and no history entry (BA decision Q7). make_fish picks species_id, a variant in
## 0..colour_variants.size()-1 (0 when there are none) and an empty nickname, and reads no Mode 2
## field. Double add gives two fish; two undos remove both.
## Test decision: the engine output of a refused do() is not pinned.

const Edit := preload("res://tests/helpers/fish_edit_api.gd")
const Api := preload("res://tests/helpers/fish_api.gd")
const Factory := preload("res://tests/helpers/factory.gd")
const ModelState := preload("res://tests/helpers/model_state.gd")
const Recorder := preload("res://tests/helpers/signal_recorder.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")

const A := "f0000001"
const B := "f0000002"

var _history: CommandHistory = null


func before_test() -> void:
	_history = CommandHistory.new()


func _have() -> bool:
	var found: bool = Edit.exists(Edit.ADD)
	(
		assert_bool(found)
		. override_failure_message("game/model/add_fish_command.gd is missing")
		. is_true()
	)
	return found


func _model() -> AquariumModel:
	var model: AquariumModel = AquariumModel.new("2026-11-01T12:00:00Z")
	model.apply_set_tank_id(&"tank_medium_1")
	model.apply_insert_fish(Factory.fish("f0000009", &"angelfish", 1, "Old"), 0)
	return model


func _add(model: AquariumModel, fish: FishInstance) -> bool:
	return _history.execute(Edit.add_command(model, fish))


func _state(model: AquariumModel) -> Dictionary:
	var state: Dictionary = ModelState.snapshot(model)
	state.erase("modified")
	return state


func test_36_the_command_is_a_command_subclass() -> void:
	if not _have():
		return
	var command: Command = Edit.add_command(_model(), Factory.fish(A))
	assert_object(command).is_not_null()
	assert_bool(command is Command).is_true()


func test_36_do_appends_the_fish_with_one_fish_added_and_one_history_entry() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	var recorder: Recorder = Recorder.new()
	recorder.watch(model)
	assert_bool(_add(model, Factory.fish(A, &"neon_tetra", 2, ""))).is_true()
	assert_array(recorder.names()).is_equal(["fish_added"])
	assert_array(recorder.args_of(0)).is_equal([A, 1])
	assert_int(model.get_fish_count()).is_equal(2)
	assert_str(model.get_fish_at(1).uid).is_equal(A)
	assert_int(_history.get_undo_count()).is_equal(1)


func test_36_undo_removes_the_fish_and_restores_the_model() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	var state_before: Dictionary = _state(model)
	assert_bool(_add(model, Factory.fish(A))).is_true()
	var recorder: Recorder = Recorder.new()
	recorder.watch(model)
	assert_bool(_history.undo()).is_true()
	assert_array(recorder.names()).is_equal(["fish_removed"])
	assert_array(recorder.args_of(0)).is_equal([A, 1])
	assert_dict(_state(model)).is_equal(state_before)


func test_36_redo_puts_the_same_fish_back_at_the_same_index() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	assert_bool(_add(model, Factory.fish(A, &"bronze_corydoras", 1, "Nick Á"))).is_true()
	var after_do: Dictionary = _state(model)
	assert_bool(_history.undo()).is_true()
	var recorder: Recorder = Recorder.new()
	recorder.watch(model)
	assert_bool(_history.redo()).is_true()
	assert_array(recorder.names()).is_equal(["fish_added"])
	assert_array(recorder.args_of(0)).is_equal([A, 1])
	assert_dict(_state(model)).is_equal(after_do)
	var fish: FishInstance = model.get_fish(A)
	assert_str(String(fish.species_id)).is_equal("bronze_corydoras")
	assert_int(fish.variant).is_equal(1)
	assert_str(fish.nickname).is_equal("Nick Á")


func test_36_a_used_fish_uid_makes_do_fail_without_a_trace() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	var state_before: Dictionary = _state(model)
	var recorder: Recorder = Recorder.new()
	recorder.watch(model)
	var result: Array = [false]
	await EngineOutput.capture(
		func() -> void: result[0] = _add(model, Factory.fish("f0000009", &"neon_tetra"))
	)
	assert_bool(result[0]).is_false()
	assert_int(recorder.count()).is_equal(0)
	assert_dict(_state(model)).is_equal(state_before)
	assert_bool(_history.can_undo()).is_false()
	assert_int(_history.get_undo_count()).is_equal(0)


func test_36_a_uid_used_by_an_item_makes_do_fail() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	model.apply_insert_item(Factory.item("a0000001"), 0)
	var state_before: Dictionary = _state(model)
	var result: Array = [false]
	await EngineOutput.capture(
		func() -> void: result[0] = _add(model, Factory.fish("a0000001", &"neon_tetra"))
	)
	assert_bool(result[0]).is_false()
	assert_dict(_state(model)).is_equal(state_before)
	assert_bool(_history.can_undo()).is_false()


func test_36_a_null_fish_an_empty_uid_and_a_null_model_make_do_fail() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	var state_before: Dictionary = _state(model)
	var results: Array[bool] = [true, true, true]
	await EngineOutput.capture(
		func() -> void:
			results[0] = _add(model, null)
			results[1] = _add(model, Factory.fish(""))
			results[2] = _add(null, Factory.fish(A))
	)
	assert_array(results).is_equal([false, false, false])
	assert_dict(_state(model)).is_equal(state_before)
	assert_bool(_history.can_undo()).is_false()


func test_36_a_double_add_gives_two_fish_and_two_undos_remove_both() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	assert_bool(_add(model, Factory.fish(A))).is_true()
	assert_bool(_add(model, Factory.fish(B))).is_true()
	assert_int(model.get_fish_count()).is_equal(3)
	(
		assert_array(model.get_fish_list().map(func(f: FishInstance) -> String: return f.uid))
		. is_equal(["f0000009", A, B])
	)
	assert_bool(_history.undo()).is_true()
	assert_bool(_history.undo()).is_true()
	assert_int(model.get_fish_count()).is_equal(1)
	assert_bool(_history.can_undo()).is_false()


func test_36_a_new_add_after_an_undo_drops_the_redo_branch() -> void:
	if not _have():
		return
	var model: AquariumModel = _model()
	assert_bool(_add(model, Factory.fish(A))).is_true()
	assert_bool(_history.undo()).is_true()
	assert_bool(_history.can_redo()).is_true()
	assert_bool(_add(model, Factory.fish(B))).is_true()
	assert_bool(_history.can_redo()).is_false()


func test_36_make_fish_fills_species_a_valid_variant_and_an_empty_nickname() -> void:
	if not _have():
		return
	var species: FishSpecies = Api.species(Api.NEON) as FishSpecies
	assert_object(species).is_not_null()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	var seen: Dictionary = {}
	for i: int in 300:
		var fish: FishInstance = Edit.make_fish("%08x" % i, species, rng)
		assert_object(fish).is_not_null()
		assert_str(fish.uid).is_equal("%08x" % i)
		assert_str(String(fish.species_id)).is_equal("neon_tetra")
		assert_str(fish.nickname).is_empty()
		assert_bool(fish.variant >= 0 and fish.variant < species.colour_variants.size()).is_true()
		seen[fish.variant] = true
	assert_int(seen.size()).is_equal(species.colour_variants.size())


func test_36_make_fish_is_deterministic_for_a_seeded_rng() -> void:
	if not _have():
		return
	var species: FishSpecies = Api.species(Api.ANGEL) as FishSpecies
	var first: Array[int] = []
	var second: Array[int] = []
	for run: Array[int] in [first, second]:
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = 99
		for i: int in 50:
			run.append(Edit.make_fish("%08x" % i, species, rng).variant)
	assert_array(first).is_equal(second)


func test_36_make_fish_with_no_colour_variants_gives_variant_zero() -> void:
	if not _have():
		return
	var species: FishSpecies = FishSpecies.new()
	species.id = &"plain"
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var fish: FishInstance = Edit.make_fish("0000abcd", species, rng)
	assert_object(fish).is_not_null()
	assert_int(fish.variant).is_equal(0)
	assert_str(String(fish.species_id)).is_equal("plain")
	assert_str(fish.nickname).is_empty()


func test_36_a_species_with_every_mode_2_field_empty_can_be_added() -> void:
	if not _have():
		return
	var species: FishSpecies = FishSpecies.new()
	species.id = &"bare"
	species.colour_variants = [Color.RED]
	var model: AquariumModel = _model()
	var fish: FishInstance = Edit.make_fish("0000abcd", species, RandomNumberGenerator.new())
	assert_bool(_add(model, fish)).is_true()
	assert_int(model.get_fish("0000abcd").variant).is_equal(0)
