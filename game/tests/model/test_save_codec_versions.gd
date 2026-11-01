extends GdUnitTestSuite

const ModelState := preload("res://tests/helpers/model_state.gd")
const SaveFixtures := preload("res://tests/helpers/save_fixtures.gd")

const NOW := "2026-11-01T12:00:00Z"


func _decode_text(text: String, codec: SaveCodec = SaveCodec.new()) -> SaveResult:
	return codec.decode(text, NOW)


func _versioned(version: Variant) -> String:
	return SaveFixtures.to_text({"format_version": version})


func _step_that_renames(seen: Array, suffix: String) -> Callable:
	return func(data: Dictionary) -> Variant:
		seen.append(int(data["format_version"]))
		var result: Dictionary = data.duplicate(true)
		result["name"] = str(result.get("name", "")) + suffix
		return result


# --- production defaults -------------------------------------------------------------------


func test_production_chain_is_empty_for_v1() -> void:
	assert_int(SaveCodec.FORMAT_VERSION).is_equal(1)
	assert_int(SaveCodec.new().get_current_version()).is_equal(1)
	assert_dict(SaveMigrations.steps()).is_empty()


# --- newer versions ------------------------------------------------------------------------


func test_newer_version_refused_before_steps() -> void:
	var seen: Array = []
	var steps: Dictionary = {
		1: _step_that_renames(seen, "a"),
		2: _step_that_renames(seen, "b"),
		3: _step_that_renames(seen, "c"),
	}
	var codec: SaveCodec = SaveCodec.new(3, steps)
	var data: Dictionary = SaveFixtures.changed(["format_version"], 4)
	var result: SaveResult = _decode_text(SaveFixtures.to_text(data), codec)
	assert_int(result.kind).is_equal(SaveResult.Kind.NEWER_VERSION)
	assert_object(result.model).is_null()
	assert_array(seen).is_empty()


func test_newer_version_is_not_damaged_even_when_the_rest_is_garbage() -> void:
	var text: String = '{"format_version": 2, "name": 5, "items": "nonsense"}'
	assert_int(_decode_text(text).kind).is_equal(SaveResult.Kind.NEWER_VERSION)


func test_huge_format_version_is_newer() -> void:
	var failures: PackedStringArray = PackedStringArray()
	for raw: String in [
		"2", "2.0", "100", "1e16", "9007199254740993", "1e300", "123456789012345678901"
	]:
		var result: SaveResult = _decode_text('{"format_version": %s}' % raw)
		if result.kind != SaveResult.Kind.NEWER_VERSION:
			failures.append("%s gave kind %d" % [raw, result.kind])
	assert_array(failures).is_empty()


# --- bad versions --------------------------------------------------------------------------


func test_bad_format_version_is_damaged() -> void:
	var texts: Array[String] = [
		'{"name": "no version"}',
		"{}",
		'{"format_version": true}',
		'{"format_version": false}',
		'{"format_version": "1"}',
		'{"format_version": null}',
		'{"format_version": [1]}',
		'{"format_version": {"v": 1}}',
		'{"format_version": 1e999}',
		'{"format_version": -1e999}',
		'{"format_version": 0}',
		'{"format_version": -1}',
		'{"format_version": 0.5}',
		'{"format_version": 1.5}',
		'{"format_version": 1.0000001}',
		'{"format_version": -0.0}',
	]
	var failures: PackedStringArray = PackedStringArray()
	for text: String in texts:
		var result: SaveResult = _decode_text(text)
		if result.kind != SaveResult.Kind.DAMAGED:
			failures.append("%s gave kind %d" % [text, result.kind])
	assert_array(failures).is_empty()


func test_version_one_point_zero_accepted() -> void:
	var result: SaveResult = _decode_text('{"format_version": 1.0}')
	assert_int(result.kind).is_equal(SaveResult.Kind.OK)
	assert_object(result.model).is_not_null()
	assert_int(_decode_text('{"format_version": 1}').kind).is_equal(SaveResult.Kind.OK)


# --- migrations ----------------------------------------------------------------------------


func test_steps_run_in_order_and_advance_version() -> void:
	var seen: Array = []
	var steps: Dictionary = {
		1: _step_that_renames(seen, "+one"),
		2: _step_that_renames(seen, "+two"),
	}
	var codec: SaveCodec = SaveCodec.new(3, steps)
	var data: Dictionary = SaveFixtures.changed(["name"], "start")
	data["format_version"] = 1
	var result: SaveResult = _decode_text(SaveFixtures.to_text(data), codec)
	assert_int(result.kind).is_equal(SaveResult.Kind.OK)
	assert_array(seen).is_equal([1, 2])
	assert_str(SaveFixtures.model_of(result).get_aquarium_name()).is_equal("start+one+two")


func test_steps_start_at_the_file_version() -> void:
	var seen: Array = []
	var steps: Dictionary = {
		1: _step_that_renames(seen, "+one"),
		2: _step_that_renames(seen, "+two"),
	}
	var codec: SaveCodec = SaveCodec.new(3, steps)
	var data: Dictionary = SaveFixtures.changed(["name"], "start")
	data["format_version"] = 2
	var result: SaveResult = _decode_text(SaveFixtures.to_text(data), codec)
	assert_int(result.kind).is_equal(SaveResult.Kind.OK)
	assert_array(seen).is_equal([2])
	assert_str(SaveFixtures.model_of(result).get_aquarium_name()).is_equal("start+two")


func test_file_at_current_version_runs_no_step() -> void:
	var seen: Array = []
	var steps: Dictionary = {
		1: _step_that_renames(seen, "+one"), 2: _step_that_renames(seen, "+two")
	}
	var codec: SaveCodec = SaveCodec.new(3, steps)
	var data: Dictionary = SaveFixtures.base_dict()
	data["format_version"] = 3
	var result: SaveResult = _decode_text(SaveFixtures.to_text(data), codec)
	assert_int(result.kind).is_equal(SaveResult.Kind.OK)
	assert_array(seen).is_empty()


func test_steps_see_the_data_before_any_field_is_read() -> void:
	# A step may repair data that would be damaged in the current shape.
	var repair: Callable = func(data: Dictionary) -> Variant:
		var result: Dictionary = data.duplicate(true)
		result["name"] = "repaired"
		return result
	var codec: SaveCodec = SaveCodec.new(2, {1: repair})
	var result: SaveResult = _decode_text('{"format_version": 1, "name": 5}', codec)
	assert_int(result.kind).is_equal(SaveResult.Kind.OK)
	assert_str(SaveFixtures.model_of(result).get_aquarium_name()).is_equal("repaired")


func test_missing_step_is_damaged() -> void:
	var seen: Array = []
	var codec: SaveCodec = SaveCodec.new(3, {1: _step_that_renames(seen, "+one")})
	var data: Dictionary = SaveFixtures.base_dict()
	var result: SaveResult = _decode_text(SaveFixtures.to_text(data), codec)
	assert_int(result.kind).is_equal(SaveResult.Kind.DAMAGED)
	assert_object(result.model).is_null()
	var no_steps: SaveCodec = SaveCodec.new(2, {})
	assert_int(_decode_text(SaveFixtures.to_text(data), no_steps).kind).is_equal(
		SaveResult.Kind.DAMAGED
	)


func test_invalid_step_callable_is_damaged() -> void:
	var codec: SaveCodec = SaveCodec.new(2, {1: Callable()})
	var data: Dictionary = SaveFixtures.base_dict()
	assert_int(_decode_text(SaveFixtures.to_text(data), codec).kind).is_equal(
		SaveResult.Kind.DAMAGED
	)
	var not_callable: SaveCodec = SaveCodec.new(2, {1: "not a callable"})
	assert_int(_decode_text(SaveFixtures.to_text(data), not_callable).kind).is_equal(
		SaveResult.Kind.DAMAGED
	)


func test_step_returning_a_non_dictionary_is_damaged() -> void:
	var failures: PackedStringArray = PackedStringArray()
	var returns: Array = [null, [], "text", 5, true]
	for value: Variant in returns:
		var step: Callable = func(_data: Dictionary) -> Variant: return value
		var codec: SaveCodec = SaveCodec.new(2, {1: step})
		var result: SaveResult = _decode_text(SaveFixtures.to_text(SaveFixtures.base_dict()), codec)
		if result.kind != SaveResult.Kind.DAMAGED:
			failures.append("%s gave kind %d" % [str(value), result.kind])
	assert_array(failures).is_empty()


func test_migrated_data_invalid_is_damaged() -> void:
	var break_it: Callable = func(data: Dictionary) -> Variant:
		var result: Dictionary = data.duplicate(true)
		result["name"] = 5
		return result
	var codec: SaveCodec = SaveCodec.new(2, {1: break_it})
	var result: SaveResult = _decode_text(SaveFixtures.to_text(SaveFixtures.base_dict()), codec)
	assert_int(result.kind).is_equal(SaveResult.Kind.DAMAGED)
	assert_object(result.model).is_null()


func test_second_step_failing_is_damaged() -> void:
	var seen: Array = []
	var fails: Callable = func(_data: Dictionary) -> Variant: return null
	var codec: SaveCodec = SaveCodec.new(3, {1: _step_that_renames(seen, "+one"), 2: fails})
	var result: SaveResult = _decode_text(SaveFixtures.to_text(SaveFixtures.base_dict()), codec)
	assert_int(result.kind).is_equal(SaveResult.Kind.DAMAGED)
	assert_array(seen).is_equal([1])


# --- golden file ---------------------------------------------------------------------------


func test_golden_v1_loads_expected_model() -> void:
	var bytes: PackedByteArray = SaveFixtures.read_bytes(SaveFixtures.GOLDEN_PATH)
	assert_int(bytes.size()).is_greater(100)
	var result: SaveResult = SaveCodec.new().decode_bytes(bytes, NOW)
	assert_int(result.kind).is_equal(SaveResult.Kind.OK)
	var expected: AquariumModel = SaveFixtures.golden_expected()
	assert_dict(ModelState.snapshot_8bit(SaveFixtures.model_of(result))).is_equal(
		ModelState.snapshot_8bit(expected)
	)


func test_golden_v1_pins_little_endian_heightmap() -> void:
	var bytes: PackedByteArray = SaveFixtures.read_bytes(SaveFixtures.GOLDEN_PATH)
	var result: SaveResult = SaveCodec.new().decode_bytes(bytes, NOW)
	assert_int(result.kind).is_equal(SaveResult.Kind.OK)
	var values: PackedFloat32Array = SaveFixtures.model_of(result).get_heightmap()
	assert_array(values).is_equal(PackedFloat32Array([0.0, 0.5, 1.0, 0.25, 0.125, 0.0625]))
	assert_bool(SaveFixtures.model_of(result).get_heightmap_size() == Vector2i(3, 2)).is_true()
	assert_str(SaveFixtures.model_of(result).get_created()).is_equal(SaveFixtures.STAMP_CREATED)
	assert_str(SaveFixtures.model_of(result).get_modified()).is_equal(SaveFixtures.STAMP_MODIFIED)
