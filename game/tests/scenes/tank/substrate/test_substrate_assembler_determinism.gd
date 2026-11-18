extends GdUnitTestSuite
## #28 criterion 32, deterministic assembly (owner: technical-artist: the assembler, its input, the
## seed and the cancel token). The bed is a pure function of (input, baked data): the same input
## twice gives identical buffers, on a worker thread and on the main thread too; another tank or
## type gives another seed and other buffers; Sand, Pebbles, Sand gives the first Sand again; the
## colour is not an input; the seed is the 32-bit FNV-1a of "<tank_id>|<substrate_id>|<version>";
## the packing version in the baked data equals the assembler constant; a cancelled assembly
## returns null, writes nothing shared and checks its token at least once per chunk.

const Api := preload("res://tests/helpers/substrate_bed_api.gd")
const Fixture := preload("res://tests/helpers/substrate_bed_fixture.gd")
const Sub := preload("res://tests/helpers/substrate_api.gd")
const Table := preload("res://tests/helpers/tank_table.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")

const PACKING_VERSION := 1
const MAX_CALLS_AFTER_CANCEL := 2


func _have_pipeline(tank_id: StringName, id: StringName) -> bool:
	var why: String = Fixture.problem(tank_id, id)
	assert_str(why).override_failure_message("%s in %s: %s" % [id, tank_id, why]).is_empty()
	return why.is_empty()


func _make_input(tank_id: StringName, id: StringName, depth: float = -1.0) -> RefCounted:
	return Api.create_input(tank_id, id, Api.look_of(id), depth)


## A cancel token that counts how often it is asked and says "cancelled" from the n-th ask on
## (never when n is negative). Built at run time as a subclass of the real token.
func _counting_token(cancel_from_call: int) -> RefCounted:
	var script: GDScript = GDScript.new()
	script.source_code = (
		(
			'extends "%s"\nvar calls: int = 0\nvar cancel_from: int = %d\n\n\n'
			% [Api.TOKEN_PATH, cancel_from_call]
		)
		+ "func is_cancelled() -> bool:\n\tcalls += 1\n"
		+ "\treturn cancel_from >= 0 and calls >= cancel_from\n"
	)
	var error: int = script.reload()
	assert_int(error).override_failure_message("the counting token does not compile").is_equal(OK)
	return script.new() as RefCounted if error == OK else null


# --- the seed and the version ---


func test_ac32_the_packing_version_is_1() -> void:
	assert_int(Api.packing_version()).is_equal(PACKING_VERSION)


func test_ac32_the_seed_is_the_fnv_1a_of_tank_type_and_version() -> void:
	assert_bool(Api.script_exists(Api.ASSEMBLER_PATH)).is_true()
	for tank_id: StringName in Table.IDS:
		for id: StringName in Sub.IDS:
			var wanted: int = Api.fnv1a_32("%s|%s|%d" % [tank_id, id, PACKING_VERSION])
			(
				assert_int(Api.seed_for(tank_id, id))
				. override_failure_message("seed of %s in %s" % [id, tank_id])
				. is_equal(wanted)
			)
	assert_int(Api.seed_for(Table.LARGE, Sub.SAND, 7)).is_equal(
		Api.fnv1a_32("tank_large_1|sand_fine|7")
	)


func test_ac32_the_fnv_1a_reference_values() -> void:
	# The published 32-bit FNV-1a test vectors, so the helper that pins the seed is itself pinned.
	assert_int(Api.fnv1a_32("")).is_equal(0x811C9DC5)
	assert_int(Api.fnv1a_32("a")).is_equal(0xE40C292C)
	assert_int(Api.fnv1a_32("foobar")).is_equal(0xBF9CF968)


func test_ac32_another_tank_type_or_version_gives_another_seed() -> void:
	var seeds: Dictionary = {}
	for tank_id: StringName in Table.IDS:
		for id: StringName in Sub.IDS:
			seeds[Api.seed_for(tank_id, id)] = true
	assert_int(seeds.size()).override_failure_message("15 pairs, %d seeds" % seeds.size()).is_equal(
		15
	)
	assert_int(Api.seed_for(Table.LARGE, Sub.SAND, 1)).is_not_equal(
		Api.seed_for(Table.LARGE, Sub.SAND, 2)
	)


func test_ac32_the_seed_function_has_no_colour_parameter_and_is_stable() -> void:
	var names: PackedStringArray = Api.method_arg_names(Api.ASSEMBLER_PATH, "seed_for")
	assert_array(names).override_failure_message("seed_for is missing").is_not_empty()
	for arg_name: String in names:
		(
			assert_bool(
				(
					arg_name.contains("colour")
					or arg_name.contains("color")
					or arg_name.contains("swatch")
				)
			)
			. override_failure_message("seed_for takes %s" % arg_name)
			. is_false()
		)
	assert_int(Api.seed_for(Table.LARGE, Sub.GRAVEL)).is_equal(
		Api.seed_for(Table.LARGE, Sub.GRAVEL)
	)


# --- the input ---


func test_ac32_the_input_copies_plain_values_and_has_no_colour() -> void:
	if not _have_pipeline(Table.MEDIUM, Sub.GRAVEL):
		return
	var look: Resource = Api.look_of(Sub.GRAVEL)
	var input: RefCounted = _make_input(Table.MEDIUM, Sub.GRAVEL)
	assert_object(input).is_not_null()
	assert_that(input.get("tank_id")).is_equal(Table.MEDIUM)
	assert_that(input.get("substrate_id")).is_equal(Sub.GRAVEL)
	assert_that(input.get("interior_size_m")).is_equal(Table.interior(Table.MEDIUM))
	assert_float(float(input.get("fill_depth_m"))).is_equal_approx(0.04, 1e-9)
	assert_int(int(input.get("packing_version"))).is_equal(PACKING_VERSION)
	assert_int(int(input.get("seed"))).is_equal(Api.seed_for(Table.MEDIUM, Sub.GRAVEL))
	for entry: Dictionary in input.get_property_list():
		if (int(entry["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var property: String = String(entry["name"])
		(
			assert_int(int(entry["type"]))
			. override_failure_message(
				"input.%s is an object: the input must hold plain values only" % property
			)
			. is_not_equal(TYPE_OBJECT)
		)
		(
			assert_bool(property.contains("colour") or property.contains("color"))
			. override_failure_message("input.%s: the colour is not an input" % property)
			. is_false()
		)
	# A later change of the look must not reach the input (the input is a copy).
	var value_before: float = float(input.get("tone_lightness"))
	look.set("tone_lightness", value_before + 0.5)
	assert_float(float(input.get("tone_lightness"))).is_equal(value_before)
	look.set("tone_lightness", value_before)


# --- identical buffers ---


func test_ac32_the_same_input_twice_gives_identical_buffers() -> void:
	for id: StringName in Sub.IDS:
		if not _have_pipeline(Table.MEDIUM, id):
			return
		var first: RefCounted = Fixture.bed_of(Table.MEDIUM, id)
		var again: RefCounted = Api.assemble(
			_make_input(Table.MEDIUM, id), Fixture.bake_of(Table.MEDIUM, id)
		)
		assert_object(first).override_failure_message("%s: no bed" % id).is_not_null()
		(
			assert_bool(Api.beds_equal(first, again))
			. override_failure_message(
				"%s: assembling the same input twice gives different data" % id
			)
			. is_true()
		)


func test_ac32_another_type_gives_another_bed_even_on_the_same_baked_data() -> void:
	if not (_have_pipeline(Table.MEDIUM, Sub.SAND) and _have_pipeline(Table.MEDIUM, Sub.BLACK)):
		return
	var sand: RefCounted = Fixture.bed_of(Table.MEDIUM, Sub.SAND)
	var black: RefCounted = Fixture.bed_of(Table.MEDIUM, Sub.BLACK)
	assert_object(sand).is_not_null()
	(
		assert_bool(Api.beds_equal(sand, black))
		. override_failure_message(
			"sand_fine and sand_black share sand.bin but must not share buffers (other seed)"
		)
		. is_false()
	)


func test_ac32_another_tank_gives_another_bed() -> void:
	for id: StringName in [Sub.GRAVEL, Sub.PEBBLES]:
		if not (_have_pipeline(Table.SMALL, id) and _have_pipeline(Table.LARGE, id)):
			return
		(
			assert_bool(
				Api.beds_equal(Fixture.bed_of(Table.SMALL, id), Fixture.bed_of(Table.LARGE, id))
			)
			. override_failure_message("%s: two tanks give the same data" % id)
			. is_false()
		)


func test_ac32_sand_then_pebbles_then_sand_equals_the_first_sand() -> void:
	if not (_have_pipeline(Table.MEDIUM, Sub.SAND) and _have_pipeline(Table.MEDIUM, Sub.PEBBLES)):
		return
	var first: RefCounted = Fixture.bed_of(Table.MEDIUM, Sub.SAND)
	var pebbles: RefCounted = Api.assemble(
		_make_input(Table.MEDIUM, Sub.PEBBLES), Fixture.bake_of(Table.MEDIUM, Sub.PEBBLES)
	)
	var third: RefCounted = Api.assemble(
		_make_input(Table.MEDIUM, Sub.SAND), Fixture.bake_of(Table.MEDIUM, Sub.SAND)
	)
	assert_object(pebbles).is_not_null()
	(
		assert_bool(Api.beds_equal(first, third))
		. override_failure_message("Sand after Pebbles differs from the first Sand")
		. is_true()
	)


func test_ac32_the_assembly_runs_on_a_worker_thread_with_identical_buffers() -> void:
	for id: StringName in [Sub.PEBBLES, Sub.COLOURED, Sub.SAND]:
		if not _have_pipeline(Table.SMALL, id):
			return
		var main_result: RefCounted = Fixture.bed_of(Table.SMALL, id)
		var input: RefCounted = _make_input(Table.SMALL, id)
		var bake: RefCounted = Fixture.bake_of(Table.SMALL, id)
		var holder: Array[RefCounted] = [null]
		var script: GDScript = Api.assembler_script()
		var task: int = WorkerThreadPool.add_task(
			func() -> void: holder[0] = script.call("assemble", input, bake, null)
		)
		WorkerThreadPool.wait_for_task_completion(task)
		(
			assert_object(holder[0])
			. override_failure_message("%s: the worker returned null" % id)
			. is_not_null()
		)
		(
			assert_bool(Api.beds_equal(main_result, holder[0]))
			. override_failure_message(
				"%s: the worker result differs from the main thread result" % id
			)
			. is_true()
		)


func test_ac32_two_assemblies_may_read_the_same_baked_data_at_once() -> void:
	if not _have_pipeline(Table.SMALL, Sub.COLOURED):
		return
	var bake: RefCounted = Fixture.bake_of(Table.SMALL, Sub.COLOURED)
	var stones_before: PackedFloat32Array = (bake.get("stones") as PackedFloat32Array).duplicate()
	var token: RefCounted = Api.new_token()
	var holder: Array[RefCounted] = [null, null]
	var input: RefCounted = _make_input(Table.SMALL, Sub.COLOURED)
	var other_input: RefCounted = _make_input(Table.SMALL, Sub.COLOURED)
	var script: GDScript = Api.assembler_script()
	var cancelled_task: int = WorkerThreadPool.add_task(
		func() -> void: holder[0] = script.call("assemble", other_input, bake, token)
	)
	var kept_task: int = WorkerThreadPool.add_task(
		func() -> void: holder[1] = script.call("assemble", input, bake, null)
	)
	token.call("cancel")
	WorkerThreadPool.wait_for_task_completion(cancelled_task)
	WorkerThreadPool.wait_for_task_completion(kept_task)
	(
		assert_bool(Api.beds_equal(Fixture.bed_of(Table.SMALL, Sub.COLOURED), holder[1]))
		. override_failure_message("the second job's result is not the plain result")
		. is_true()
	)
	(
		assert_array(bake.get("stones"))
		. override_failure_message("the baked data changed while two jobs read it")
		. is_equal(stones_before)
	)


# --- cancel ---


func test_ac32_a_token_cancelled_before_the_start_gives_null() -> void:
	if not _have_pipeline(Table.SMALL, Sub.GRAVEL):
		return
	var token: RefCounted = Api.new_token()
	assert_object(token).is_not_null()
	token.call("cancel")
	assert_bool(bool(token.call("is_cancelled"))).is_true()
	var result: RefCounted = Api.assemble(
		_make_input(Table.SMALL, Sub.GRAVEL), Fixture.bake_of(Table.SMALL, Sub.GRAVEL), token
	)
	assert_object(result).override_failure_message("a cancelled assembly returned data").is_null()


func test_ac32_a_fresh_token_changes_nothing() -> void:
	if not _have_pipeline(Table.SMALL, Sub.PEBBLES):
		return
	var token: RefCounted = Api.new_token()
	assert_bool(bool(token.call("is_cancelled"))).is_false()
	var result: RefCounted = Api.assemble(
		_make_input(Table.SMALL, Sub.PEBBLES), Fixture.bake_of(Table.SMALL, Sub.PEBBLES), token
	)
	assert_bool(Api.beds_equal(Fixture.bed_of(Table.SMALL, Sub.PEBBLES), result)).is_true()


func test_ac32_the_token_is_checked_at_least_once_per_chunk() -> void:
	for id: StringName in [Sub.GRAVEL, Sub.SAND, Sub.PEBBLES]:
		if not _have_pipeline(Table.SMALL, id):
			return
		var token: RefCounted = _counting_token(-1)
		if token == null:
			return
		var result: RefCounted = Api.assemble(
			_make_input(Table.SMALL, id), Fixture.bake_of(Table.SMALL, id), token
		)
		assert_object(result).is_not_null()
		var chunks: int = (result.get("chunks") as Array).size()
		(
			assert_int(int(token.get("calls")))
			. override_failure_message(
				"%s: %d chunks, the token was asked %d times" % [id, chunks, token.get("calls")]
			)
			. is_greater_equal(chunks)
		)


func test_ac32_a_cancel_in_the_middle_stops_the_assembly_at_once_and_returns_null() -> void:
	for id: StringName in [Sub.GRAVEL, Sub.SAND]:
		if not _have_pipeline(Table.LARGE, id):
			return
		var token: RefCounted = _counting_token(3)
		if token == null:
			return
		var result: RefCounted = Api.assemble(
			_make_input(Table.LARGE, id), Fixture.bake_of(Table.LARGE, id), token
		)
		(
			assert_object(result)
			. override_failure_message("%s: a cancelled assembly returned data" % id)
			. is_null()
		)
		(
			assert_int(int(token.get("calls")))
			. override_failure_message(
				(
					"%s: the assembly kept working after the cancel, token asked %d times"
					% [id, token.get("calls")]
				)
			)
			. is_less_equal(3 + MAX_CALLS_AFTER_CANCEL)
		)


# --- failures ---


func test_ac32_a_fill_depth_that_is_not_the_baked_one_gives_null() -> void:
	if not _have_pipeline(Table.SMALL, Sub.PEBBLES):
		return
	var results: Array[RefCounted] = []
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void:
			results.append(
				Api.assemble(
					_make_input(Table.SMALL, Sub.PEBBLES, 0.061),
					Fixture.bake_of(Table.SMALL, Sub.PEBBLES)
				)
			)
	)
	assert_object(results[0]).override_failure_message("a wrong fill depth was accepted").is_null()
	assert_dict(seen["warnings"]).is_empty()


func test_ac32_the_packing_version_of_every_data_file_is_the_constant() -> void:
	for tank_id: StringName in Table.IDS:
		for id: StringName in Sub.IDS:
			if not _have_pipeline(tank_id, id):
				return
			var bake: RefCounted = Fixture.bake_of(tank_id, id)
			assert_object(bake).is_not_null()
			assert_int(int(Api.header_value(bake.get("header"), ["packing_version"]))).is_equal(
				Api.packing_version()
			)
