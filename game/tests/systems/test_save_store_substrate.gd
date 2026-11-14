extends GdUnitTestSuite
## #28 criteria 11 and 12 (owner: developer): SaveStore with a SubstrateCatalog (ADR 0010 rule 4).
## A save whose substrate id is empty or unknown loads as Sand with its default colour, exactly one
## warning, an empty history and an unchanged file; every type round-trips with its default and
## with swatch 2; the format version does not change; a non-swatch colour is kept and re-saves
## byte for byte. Stores without a catalog keep their old behaviour (test_save_store.gd).

const Sub := preload("res://tests/helpers/substrate_api.gd")
const SaveFixtures := preload("res://tests/helpers/save_fixtures.gd")
const Recorder := preload("res://tests/helpers/signal_recorder.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")
const Factory := preload("res://tests/helpers/factory.gd")
const AddItemCommand := preload("res://tests/helpers/commands/add_item_command.gd")

var _dir: String = ""
var _catalog: RefCounted = null
var _model: AquariumModel = null
var _history: CommandHistory = null


func before_test() -> void:
	_dir = SaveFixtures.make_dir("store_substrate")
	_catalog = Sub.catalog()
	_model = AquariumModel.new(Sub.STAMP)
	_history = CommandHistory.new()


func after_test() -> void:
	SaveFixtures.remove_dir(_dir)
	SaveFixtures.remove_root_if_empty()


## The store with the catalog; a failed assert and null while SaveStore has no catalog argument.
func _store() -> SaveStore:
	var clock: Callable = func() -> String: return Sub.STAMP
	var store: SaveStore = Sub.save_store(clock, _catalog)
	(
		assert_bool(store != null)
		. override_failure_message("SaveStore._init has no third parameter (substrates)")
		. is_true()
	)
	return store


func _path(file_name: String = "tank.json") -> String:
	return _dir.path_join(file_name)


func _write(file_name: String, data: Variant) -> String:
	var path: String = _path(file_name)
	SaveFixtures.write_text(path, SaveFixtures.to_text(data))
	return path


func _file_with(id: String, colour: String) -> Dictionary:
	var data: Dictionary = SaveFixtures.base_dict()
	data["substrate"]["id"] = id
	data["substrate"]["colour"] = colour
	return data


func _same(actual: Color, expected: Color) -> void:
	(
		assert_bool(Sub.same_colour(actual, expected))
		. override_failure_message("expected %s, got %s" % [Sub.hex(expected), Sub.hex(actual)])
		. is_true()
	)


# --- AC 11: the fallback ---


func test_ac11_an_unknown_id_loads_as_sand_with_its_default_and_one_warning() -> void:
	var store: SaveStore = _store()
	if store == null:
		return
	var path: String = _write("tank.json", _file_with("pebbles_x", "#123456"))
	var result: Array = []
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void: result.append(store.load_into(path, _model, _history))
	)
	assert_int((result[0] as SaveResult).kind).is_equal(SaveResult.Kind.OK)
	assert_that(_model.get_substrate_id()).is_equal(Sub.SAND)
	_same(_model.get_substrate_colour(), Sub.SAND_DEFAULT)
	var warnings: Dictionary = seen["warnings"]
	assert_int(warnings.size()).is_equal(1)
	if warnings.size() == 1:
		assert_str(str(warnings.keys()[0])).contains(Sub.WARN_UNKNOWN_ID)
		assert_str(str(warnings.keys()[0])).contains("pebbles_x")
		assert_int(int(warnings.values()[0])).is_equal(1)
	assert_dict(seen["errors"]).is_empty()


func test_ac11_an_empty_id_loads_as_sand_with_one_warning() -> void:
	var store: SaveStore = _store()
	if store == null:
		return
	var path: String = _write("tank.json", _file_with("", "#FFFFFF"))
	var result: Array = []
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void: result.append(store.load_into(path, _model, _history))
	)
	assert_int((result[0] as SaveResult).kind).is_equal(SaveResult.Kind.OK)
	assert_that(_model.get_substrate_id()).is_equal(Sub.SAND)
	_same(_model.get_substrate_colour(), Sub.SAND_DEFAULT)
	assert_int(seen["warnings"].size()).is_equal(1)


func test_ac11_the_fallback_adds_no_history_and_the_file_is_unchanged() -> void:
	var store: SaveStore = _store()
	if store == null:
		return
	var path: String = _write("tank.json", _file_with("pebbles_x", "#123456"))
	var before: PackedByteArray = SaveFixtures.read_bytes(path)
	assert_bool(_history.execute(AddItemCommand.new(_model, Factory.item("c0000001")))).is_true()
	await EngineOutput.capture(func() -> void: store.load_into(path, _model, _history))
	assert_bool(_history.can_undo()).is_false()
	assert_bool(_history.can_redo()).is_false()
	assert_that(SaveFixtures.read_bytes(path)).is_equal(before)
	assert_array(SaveFixtures.listing(_dir)).is_equal(["tank.json"])


func test_ac11_the_fallback_gives_one_model_reset_and_no_substrate_changed() -> void:
	var store: SaveStore = _store()
	if store == null:
		return
	var path: String = _write("tank.json", _file_with("pebbles_x", "#123456"))
	var recorder: Recorder = Recorder.new()
	recorder.watch(_model)
	await EngineOutput.capture(func() -> void: store.load_into(path, _model, _history))
	assert_array(recorder.names()).is_equal(["model_reset"])


func test_ac11_the_rest_of_the_save_loads_as_written() -> void:
	var store: SaveStore = _store()
	if store == null:
		return
	var path: String = _write("tank.json", _file_with("pebbles_x", "#123456"))
	await EngineOutput.capture(func() -> void: store.load_into(path, _model, _history))
	assert_str(_model.get_aquarium_name()).is_equal("Base")
	assert_that(_model.get_tank_id()).is_equal(&"tank_60")
	assert_int(_model.get_item_count()).is_equal(1)
	assert_int(_model.get_fish_count()).is_equal(1)
	assert_that(_model.get_heightmap_size()).is_equal(Vector2i(2, 1))


func test_ac11_a_known_id_with_a_missing_colour_keeps_white_without_a_warning() -> void:
	var store: SaveStore = _store()
	if store == null:
		return
	var data: Dictionary = _file_with("pebbles_river", "#FFFFFF")
	var substrate: Dictionary = data["substrate"]
	substrate.erase("colour")
	var path: String = _write("tank.json", data)
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void: store.load_into(path, _model, _history)
	)
	assert_that(_model.get_substrate_id()).is_equal(Sub.PEBBLES)
	assert_that(_model.get_substrate_colour()).is_equal(Color.WHITE)
	assert_dict(seen["warnings"]).is_empty()


func test_ac11_a_load_without_a_catalog_keeps_an_unknown_id_as_before() -> void:
	var clock: Callable = func() -> String: return Sub.STAMP
	var store: SaveStore = SaveStore.new(clock)
	var path: String = _write("tank.json", _file_with("pebbles_x", "#123456"))
	assert_int(store.load_into(path, _model, _history).kind).is_equal(SaveResult.Kind.OK)
	assert_that(_model.get_substrate_id()).is_equal(&"pebbles_x")


# --- AC 12: round trips ---


func _round_trip(id: StringName, colour: Color, label: String) -> void:
	var store: SaveStore = _store()
	if store == null:
		return
	var source: AquariumModel = Sub.furnished(id, colour)
	var path: String = _path("%s.json" % label)
	assert_int(store.save(source, path).kind).override_failure_message(label).is_equal(
		SaveResult.Kind.OK
	)
	var loaded: AquariumModel = AquariumModel.new(Sub.STAMP)
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void: store.load_into(path, loaded, CommandHistory.new())
	)
	assert_that(loaded.get_substrate_id()).override_failure_message(label).is_equal(id)
	(
		assert_bool(Sub.same_colour(loaded.get_substrate_colour(), colour))
		. override_failure_message(
			(
				"%s: colour %s became %s"
				% [label, Sub.hex(colour), Sub.hex(loaded.get_substrate_colour())]
			)
		)
		. is_true()
	)
	assert_dict(seen["warnings"]).override_failure_message(label).is_empty()
	assert_dict(seen["errors"]).override_failure_message(label).is_empty()
	var data: Dictionary = SaveFixtures.read_json(path)
	assert_int(int(data.get("format_version", -1))).override_failure_message(label).is_equal(1)


func test_ac12_every_type_with_its_default_colour_round_trips() -> void:
	for id: StringName in Sub.IDS:
		await _round_trip(id, Sub.default_colour(_catalog, id), "default_%s" % id)


func test_ac12_every_type_with_swatch_2_round_trips() -> void:
	for id: StringName in Sub.IDS:
		await _round_trip(id, Sub.swatch(_catalog, id, 2), "swatch2_%s" % id)


func test_ac12_the_saved_colour_is_the_hex_of_the_catalog_colour() -> void:
	var store: SaveStore = _store()
	if store == null:
		return
	for id: StringName in Sub.IDS:
		var colour: Color = Sub.swatch(_catalog, id, 2)
		var path: String = _path("hex_%s.json" % id)
		store.save(Sub.model_with(id, colour), path)
		var substrate: Dictionary = SaveFixtures.read_json(path).get("substrate", {})
		assert_str(str(substrate.get("id", ""))).is_equal(String(id))
		assert_str(str(substrate.get("colour", ""))).is_equal(
			"#" + colour.to_html(false).to_upper()
		)


func test_ac12_a_save_made_before_this_issue_loads_unchanged() -> void:
	var store: SaveStore = _store()
	if store == null:
		return
	var path: String = _write("old.json", _file_with("sand_fine", "#E8D9B0"))
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void: store.load_into(path, _model, _history)
	)
	assert_that(_model.get_substrate_id()).is_equal(Sub.SAND)
	_same(_model.get_substrate_colour(), Sub.SAND_DEFAULT)
	assert_dict(seen["warnings"]).is_empty()
	assert_int(int(SaveFixtures.read_json(path)["format_version"])).is_equal(1)


func test_ac12_a_non_swatch_colour_loads_and_re_saves_identically() -> void:
	var store: SaveStore = _store()
	if store == null:
		return
	var first: String = _path("first.json")
	var second: String = _path("second.json")
	var source: AquariumModel = Sub.furnished(Sub.SAND, Sub.NOT_A_SWATCH)
	assert_int(store.save(source, first).kind).is_equal(SaveResult.Kind.OK)
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void: store.load_into(first, _model, _history)
	)
	assert_that(_model.get_substrate_id()).is_equal(Sub.SAND)
	_same(_model.get_substrate_colour(), Sub.NOT_A_SWATCH)
	assert_dict(seen["warnings"]).is_empty()
	assert_int(store.save(_model, second).kind).is_equal(SaveResult.Kind.OK)
	assert_that(SaveFixtures.read_bytes(second)).is_equal(SaveFixtures.read_bytes(first))
