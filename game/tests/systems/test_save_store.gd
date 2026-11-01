# gdlint: disable=max-public-methods
extends GdUnitTestSuite

const ModelState := preload("res://tests/helpers/model_state.gd")
const SaveFixtures := preload("res://tests/helpers/save_fixtures.gd")
const SignalRecorder := preload("res://tests/helpers/signal_recorder.gd")
const EventBusScript := preload("res://systems/event_bus.gd")
const AddItemCommand := preload("res://tests/helpers/commands/add_item_command.gd")
const SetTankCommand := preload("res://tests/helpers/commands/set_tank_command.gd")
const Factory := preload("res://tests/helpers/factory.gd")

const STAMP := "2026-11-01T12:00:00Z"

var _dir: String = ""
var _model: AquariumModel
var _history: CommandHistory
var _bus: Node = null


func before_test() -> void:
	_dir = SaveFixtures.make_dir("store")
	_model = SaveFixtures.populated_model()
	_history = CommandHistory.new()
	_bus = null


func after_test() -> void:
	if _bus != null:
		_bus.unbind_history()
	SaveFixtures.remove_dir(_dir)
	SaveFixtures.remove_root_if_empty()


func _store(stamp: String = STAMP) -> SaveStore:
	var clock: Callable = func() -> String: return stamp
	return SaveStore.new(clock)


func _path(file_name: String = "tank.json") -> String:
	return _dir.path_join(file_name)


func _write(file_name: String, data: Variant) -> String:
	var path: String = _path(file_name)
	SaveFixtures.write_text(path, SaveFixtures.to_text(data))
	return path


## A history with one executed command and one undone command, so both stacks hold something.
func _busy_history() -> void:
	var item: PlacedItem = Factory.item("c0000001")
	assert_bool(_history.execute(AddItemCommand.new(_model, item))).is_true()
	assert_bool(_history.execute(SetTankCommand.new(_model, &"tank_x"))).is_true()
	assert_bool(_history.undo()).is_true()
	assert_bool(_history.can_undo()).is_true()
	assert_bool(_history.can_redo()).is_true()


# --- order and effects of a successful load --------------------------------------------------


func test_load_signal_order_model_then_history_then_bus() -> void:
	var path: String = _write("tank.json", SaveFixtures.base_dict())
	_busy_history()
	_bus = auto_free(EventBusScript.new())
	var recorder: SignalRecorder = SignalRecorder.new()
	recorder.watch(_model)
	recorder.watch(_history)
	_bus.bind_history(_history)
	recorder.watch(_bus)
	recorder.clear()
	var result: SaveResult = _store().load_into(path, _model, _history)
	assert_int(result.kind).is_equal(SaveResult.Kind.OK)
	assert_array(recorder.names()).is_equal(["model_reset", "history_changed", "history_changed"])
	assert_array(recorder.args_of(1)).is_equal([false, false])
	assert_array(recorder.args_of(2)).is_equal([false, false])
	# The model is already filled when model_reset fires, and history clears after it.
	assert_str(_model.get_aquarium_name()).is_equal("Base")


func test_load_refills_same_object_one_reset_only() -> void:
	var path: String = _write("tank.json", SaveFixtures.base_dict())
	var same: AquariumModel = _model
	var recorder: SignalRecorder = SignalRecorder.new()
	recorder.watch(_model)
	var result: SaveResult = _store().load_into(path, _model, _history)
	assert_int(result.kind).is_equal(SaveResult.Kind.OK)
	assert_bool(is_same(_model, same)).is_true()
	assert_array(recorder.events).is_equal([["model_reset", []]])
	assert_str(_model.get_aquarium_name()).is_equal("Base")
	assert_int(_model.get_item_count()).is_equal(1)
	assert_int(_model.get_fish_count()).is_equal(1)
	recorder.clear()
	_model.apply_set_name("After")
	assert_array(recorder.events).is_equal([["name_changed", ["After"]]])


func test_load_clears_history() -> void:
	var path: String = _write("tank.json", SaveFixtures.base_dict())
	_busy_history()
	assert_bool(_history.can_undo()).is_true()
	var result: SaveResult = _store().load_into(path, _model, _history)
	assert_int(result.kind).is_equal(SaveResult.Kind.OK)
	assert_bool(_history.can_undo()).is_false()
	assert_bool(_history.can_redo()).is_false()
	assert_int(_history.get_undo_count()).is_equal(0)
	assert_int(_history.get_redo_count()).is_equal(0)


func test_save_then_load_nothing_to_undo() -> void:
	_busy_history()
	var path: String = _path()
	var store: SaveStore = _store()
	assert_int(store.save(_model, path).kind).is_equal(SaveResult.Kind.OK)
	# The history is not in the file and saving does not touch it.
	assert_bool(_history.can_undo()).is_true()
	var other: AquariumModel = AquariumModel.new(STAMP)
	var other_history: CommandHistory = CommandHistory.new()
	assert_int(store.load_into(path, other, other_history).kind).is_equal(SaveResult.Kind.OK)
	assert_bool(other_history.can_undo()).is_false()
	assert_int(store.load_into(path, _model, _history).kind).is_equal(SaveResult.Kind.OK)
	assert_bool(_history.can_undo()).is_false()
	assert_bool(_history.can_redo()).is_false()


func test_load_takes_created_and_modified_from_file() -> void:
	var store: SaveStore = _store("2030-01-01T00:00:00Z")
	var target: AquariumModel = AquariumModel.new("2029-01-01T00:00:00Z")
	var result: SaveResult = store.load_into(SaveFixtures.GOLDEN_PATH, target, _history)
	assert_int(result.kind).is_equal(SaveResult.Kind.OK)
	assert_str(target.get_created()).is_equal(SaveFixtures.STAMP_CREATED)
	assert_str(target.get_modified()).is_equal(SaveFixtures.STAMP_MODIFIED)


func test_load_uses_the_clock_for_missing_stamps() -> void:
	var path: String = _write("tank.json", {"format_version": 1})
	var store: SaveStore = _store("2031-02-03T04:05:06Z")
	assert_int(store.load_into(path, _model, _history).kind).is_equal(SaveResult.Kind.OK)
	assert_str(_model.get_created()).is_equal("2031-02-03T04:05:06Z")
	assert_str(_model.get_modified()).is_equal("2031-02-03T04:05:06Z")


func test_golden_v1_loads_through_store_from_res_path() -> void:
	var result: SaveResult = _store().load_into(SaveFixtures.GOLDEN_PATH, _model, _history)
	assert_int(result.kind).is_equal(SaveResult.Kind.OK)
	var expected: AquariumModel = SaveFixtures.golden_expected()
	assert_dict(ModelState.snapshot_8bit(_model)).is_equal(ModelState.snapshot_8bit(expected))


func test_load_never_modifies_the_file() -> void:
	var path: String = _write("tank.json", SaveFixtures.base_dict())
	var before: PackedByteArray = SaveFixtures.read_bytes(path)
	var times: int = FileAccess.get_modified_time(path)
	assert_int(_store().load_into(path, _model, _history).kind).is_equal(SaveResult.Kind.OK)
	assert_bool(SaveFixtures.read_bytes(path) == before).is_true()
	assert_int(FileAccess.get_modified_time(path)).is_equal(times)
	assert_array(SaveFixtures.listing(_dir)).is_equal(["tank.json"])


func test_load_accepts_a_file_with_a_bom() -> void:
	var bom: PackedByteArray = PackedByteArray([0xEF, 0xBB, 0xBF])
	var path: String = _path()
	SaveFixtures.write_bytes(path, bom + SaveFixtures.to_bytes(SaveFixtures.base_dict()))
	assert_int(_store().load_into(path, _model, _history).kind).is_equal(SaveResult.Kind.OK)
	assert_str(_model.get_aquarium_name()).is_equal("Base")


# --- busy history and bad arguments ------------------------------------------------------------


func test_load_from_model_signal_handler_is_internal() -> void:
	var path: String = _write("tank.json", SaveFixtures.base_dict())
	var store: SaveStore = _store()
	var results: Array = []
	var on_added: Callable = func(_uid: String, _index: int) -> void:
		results.append(store.load_into(path, _model, _history))
	_model.item_added.connect(on_added)
	var recorder: SignalRecorder = SignalRecorder.new()
	recorder.watch(_model)
	recorder.watch(_history)
	var item: PlacedItem = Factory.item("c0000001")
	assert_bool(_history.execute(AddItemCommand.new(_model, item))).is_true()
	assert_int(results.size()).is_equal(1)
	var nested: SaveResult = SaveResult.new()
	if not results.is_empty():
		nested = results[0]
	assert_int(nested.kind).is_equal(SaveResult.Kind.INTERNAL)
	assert_array(recorder.names()).is_equal(["item_added", "executed", "history_changed"])
	assert_str(_model.get_aquarium_name()).is_equal("Reef Árvíztűrő")
	assert_int(_model.get_item_count()).is_equal(4)
	assert_bool(_history.can_undo()).is_true()


func test_load_from_history_changed_handler_is_internal() -> void:
	var path: String = _write("tank.json", SaveFixtures.base_dict())
	var store: SaveStore = _store()
	var results: Array = []
	var on_changed: Callable = func(_can_undo: bool, _can_redo: bool) -> void:
		results.append(store.load_into(path, _model, _history))
	_history.history_changed.connect(on_changed)
	var recorder: SignalRecorder = SignalRecorder.new()
	recorder.watch(_model)
	assert_bool(_history.execute(SetTankCommand.new(_model, &"tank_x"))).is_true()
	assert_int(results.size()).is_equal(1)
	var nested: SaveResult = SaveResult.new()
	if not results.is_empty():
		nested = results[0]
	assert_int(nested.kind).is_equal(SaveResult.Kind.INTERNAL)
	assert_array(recorder.names()).is_equal(["tank_changed"])
	assert_str(String(_model.get_tank_id())).is_equal("tank_x")
	assert_str(_model.get_aquarium_name()).is_equal("Reef Árvíztűrő")
	assert_bool(_history.can_undo()).is_true()


func test_load_with_null_model_or_history_is_internal() -> void:
	var path: String = _write("tank.json", SaveFixtures.base_dict())
	var store: SaveStore = _store()
	var no_model: SaveResult = store.load_into(path, null, _history)
	assert_int(no_model.kind).is_equal(SaveResult.Kind.INTERNAL)
	var before: Dictionary = ModelState.snapshot(_model)
	var no_history: SaveResult = store.load_into(path, _model, null)
	assert_int(no_history.kind).is_equal(SaveResult.Kind.INTERNAL)
	assert_dict(ModelState.snapshot(_model)).is_equal(before)


# --- refused loads touch nothing ------------------------------------------------------------


func _damaged_files() -> Array:
	var items: Array = []
	for index: int in 3:
		var item: Dictionary = (SaveFixtures.base_dict()["items"][0] as Dictionary).duplicate(true)
		item["uid"] = "b000000%d" % index
		items.append(item)
	var broken: Dictionary = (items[0] as Dictionary).duplicate(true)
	broken["uid"] = "b0000009"
	broken["position"] = [1.0, 2.0]
	items.append(broken)
	var partly: Dictionary = SaveFixtures.base_dict()
	partly["items"] = items
	var golden: String = SaveFixtures.read_text(SaveFixtures.GOLDEN_PATH)
	return [
		["empty", PackedByteArray()],
		["truncated", golden.substr(0, golden.length() / 2).to_utf8_buffer()],
		["not json", "not json".to_utf8_buffer()],
		["top level array", "[1, 2]".to_utf8_buffer()],
		["bad utf8", SaveFixtures.bytes_with_name(PackedByteArray([0xC3, 0x28]))],
		["bad uid", SaveFixtures.to_bytes(SaveFixtures.changed(["items", 0, "uid"], "xyz"))],
		["wrong type", SaveFixtures.to_bytes(SaveFixtures.changed(["name"], 5))],
		["3 valid items and 1 invalid", SaveFixtures.to_bytes(partly)],
		["deep nesting", SaveFixtures.deep_text(2000, true).to_utf8_buffer()],
	]


func test_damaged_load_leaves_everything_untouched() -> void:
	_busy_history()
	var path: String = _path()
	var before: Dictionary = ModelState.snapshot(_model)
	var undo_count: int = _history.get_undo_count()
	var redo_count: int = _history.get_redo_count()
	var recorder: SignalRecorder = SignalRecorder.new()
	recorder.watch(_model)
	recorder.watch(_history)
	var store: SaveStore = _store()
	var failures: PackedStringArray = PackedStringArray()
	for case: Array in _damaged_files():
		SaveFixtures.write_bytes(path, case[1])
		var file_before: PackedByteArray = SaveFixtures.read_bytes(path)
		var result: SaveResult = store.load_into(path, _model, _history)
		if result.kind != SaveResult.Kind.DAMAGED:
			failures.append("%s: kind %d" % [case[0], result.kind])
		if ModelState.snapshot(_model) != before:
			failures.append("%s: model changed" % case[0])
		if not recorder.events.is_empty():
			failures.append("%s: signals %s" % [case[0], recorder.names()])
			recorder.clear()
		if _history.get_undo_count() != undo_count or _history.get_redo_count() != redo_count:
			failures.append("%s: history changed" % case[0])
		if SaveFixtures.read_bytes(path) != file_before:
			failures.append("%s: file changed" % case[0])
	assert_array(failures).is_empty()


func test_partly_invalid_file_applies_nothing() -> void:
	var rows: Array = _damaged_files()
	var partly: Array = rows[7]
	var path: String = _path()
	SaveFixtures.write_bytes(path, partly[1])
	var before: Dictionary = ModelState.snapshot(_model)
	var recorder: SignalRecorder = SignalRecorder.new()
	recorder.watch(_model)
	var result: SaveResult = _store().load_into(path, _model, _history)
	assert_int(result.kind).is_equal(SaveResult.Kind.DAMAGED)
	assert_dict(ModelState.snapshot(_model)).is_equal(before)
	assert_array(recorder.events).is_empty()


func test_newer_version_leaves_live_model_and_file_untouched() -> void:
	_busy_history()
	var data: Dictionary = SaveFixtures.changed(["format_version"], 2)
	data["from_the_future"] = {"x": 1}
	var path: String = _write("future.json", data)
	var file_before: PackedByteArray = SaveFixtures.read_bytes(path)
	var time_before: int = FileAccess.get_modified_time(path)
	var before: Dictionary = ModelState.snapshot(_model)
	var recorder: SignalRecorder = SignalRecorder.new()
	recorder.watch(_model)
	recorder.watch(_history)
	var result: SaveResult = _store().load_into(path, _model, _history)
	assert_int(result.kind).is_equal(SaveResult.Kind.NEWER_VERSION)
	assert_dict(ModelState.snapshot(_model)).is_equal(before)
	assert_array(recorder.events).is_empty()
	assert_bool(_history.can_undo()).is_true()
	assert_bool(_history.can_redo()).is_true()
	assert_bool(SaveFixtures.read_bytes(path) == file_before).is_true()
	assert_int(FileAccess.get_modified_time(path)).is_equal(time_before)
	assert_array(SaveFixtures.listing(_dir)).is_equal(["future.json"])


func test_missing_file_is_not_found() -> void:
	_busy_history()
	var before: Dictionary = ModelState.snapshot(_model)
	var recorder: SignalRecorder = SignalRecorder.new()
	recorder.watch(_model)
	recorder.watch(_history)
	var result: SaveResult = _store().load_into(_path("nothing_here.json"), _model, _history)
	assert_int(result.kind).is_equal(SaveResult.Kind.NOT_FOUND)
	assert_dict(ModelState.snapshot(_model)).is_equal(before)
	assert_array(recorder.events).is_empty()
	assert_bool(_history.can_undo()).is_true()
	assert_array(SaveFixtures.listing(_dir)).is_empty()


func test_folder_path_is_not_found() -> void:
	DirAccess.make_dir_recursive_absolute(_path("a_folder"))
	var before: Dictionary = ModelState.snapshot(_model)
	var result: SaveResult = _store().load_into(_path("a_folder"), _model, _history)
	assert_int(result.kind).is_equal(SaveResult.Kind.NOT_FOUND)
	assert_dict(ModelState.snapshot(_model)).is_equal(before)


func test_empty_and_odd_paths_are_not_found() -> void:
	var before: Dictionary = ModelState.snapshot(_model)
	var failures: PackedStringArray = PackedStringArray()
	for path: String in ["", "user://", "res://tests/fixtures/saves/does_not_exist.json"]:
		var result: SaveResult = _store().load_into(path, _model, _history)
		if result.kind != SaveResult.Kind.NOT_FOUND:
			failures.append("'%s' gave kind %d" % [path, result.kind])
	assert_array(failures).is_empty()
	assert_dict(ModelState.snapshot(_model)).is_equal(before)


func test_oversized_file_is_damaged_through_the_store() -> void:
	var path: String = _path("huge.json")
	SaveFixtures.write_bytes(path, SaveFixtures.padded_bytes(SaveFixtures.MAX_FILE_BYTES + 1))
	var before: Dictionary = ModelState.snapshot(_model)
	var result: SaveResult = _store().load_into(path, _model, _history)
	assert_int(result.kind).is_equal(SaveResult.Kind.DAMAGED)
	assert_dict(ModelState.snapshot(_model)).is_equal(before)


# --- saving ----------------------------------------------------------------------------------


func test_save_twice_with_fixed_clock_byte_identical() -> void:
	var store: SaveStore = _store()
	var first: String = _path("first.json")
	var second: String = _path("second.json")
	assert_int(store.save(_model, first).kind).is_equal(SaveResult.Kind.OK)
	assert_int(store.save(_model, second).kind).is_equal(SaveResult.Kind.OK)
	assert_bool(SaveFixtures.read_bytes(first) == SaveFixtures.read_bytes(second)).is_true()
	assert_int(store.save(_model, first).kind).is_equal(SaveResult.Kind.OK)
	assert_bool(SaveFixtures.read_bytes(first) == SaveFixtures.read_bytes(second)).is_true()


func test_saved_file_is_what_the_codec_writes() -> void:
	var path: String = _path()
	assert_int(_store().save(_model, path).kind).is_equal(SaveResult.Kind.OK)
	var expected: SaveResult = SaveCodec.new().encode(_model, STAMP)
	assert_bool(SaveFixtures.read_bytes(path) == expected.text.to_utf8_buffer()).is_true()
	var data: Dictionary = SaveFixtures.read_json(path)
	assert_str(data["modified"]).is_equal(STAMP)


func test_save_takes_one_stamp_and_sets_modified_after_write() -> void:
	var calls: Array = []
	var counter: Callable = func() -> String:
		calls.append(1)
		return "2026-11-01T12:00:%02dZ" % calls.size()
	var store: SaveStore = SaveStore.new(counter)
	_busy_history()
	var created: String = _model.get_created()
	var recorder: SignalRecorder = SignalRecorder.new()
	recorder.watch(_model)
	recorder.watch(_history)
	var path: String = _path()
	var result: SaveResult = store.save(_model, path)
	assert_int(result.kind).is_equal(SaveResult.Kind.OK)
	assert_int(calls.size()).is_equal(1)
	assert_str(SaveFixtures.read_json(path).get("modified", "")).is_equal("2026-11-01T12:00:01Z")
	assert_str(_model.get_modified()).is_equal("2026-11-01T12:00:01Z")
	assert_str(_model.get_created()).is_equal(created)
	assert_array(recorder.events).is_empty()
	assert_bool(_history.can_undo()).is_true()
	assert_bool(_history.can_redo()).is_true()
	assert_int(store.save(_model, path).kind).is_equal(SaveResult.Kind.OK)
	assert_int(calls.size()).is_equal(2)
	assert_str(_model.get_modified()).is_equal("2026-11-01T12:00:02Z")


func test_save_refuses_an_oversized_model_and_keeps_the_good_save() -> void:
	var path: String = _path()
	var store: SaveStore = _store()
	assert_int(store.save(_model, path).kind).is_equal(SaveResult.Kind.OK)
	var before: PackedByteArray = SaveFixtures.read_bytes(path)
	var modified: String = _model.get_modified()
	_model.apply_set_name("a".repeat(SaveFixtures.MAX_FILE_BYTES))
	var result: SaveResult = store.save(_model, path)
	assert_int(result.kind).is_equal(SaveResult.Kind.INTERNAL)
	assert_bool(SaveFixtures.read_bytes(path) == before).is_true()
	assert_str(_model.get_modified()).is_equal(modified)


func test_save_then_load_round_trips_through_the_store() -> void:
	var path: String = _path()
	var store: SaveStore = _store()
	assert_int(store.save(_model, path).kind).is_equal(SaveResult.Kind.OK)
	var loaded: AquariumModel = AquariumModel.new("2020-01-01T00:00:00Z")
	assert_int(store.load_into(path, loaded, _history).kind).is_equal(SaveResult.Kind.OK)
	assert_dict(ModelState.snapshot_8bit(loaded)).is_equal(ModelState.snapshot_8bit(_model))
	assert_str(loaded.get_modified()).is_equal(STAMP)


func test_save_with_the_default_clock_writes_a_valid_stamp() -> void:
	var path: String = _path()
	var result: SaveResult = SaveStore.new().save(_model, path)
	assert_int(result.kind).is_equal(SaveResult.Kind.OK)
	var stamp: String = SaveFixtures.read_json(path).get("modified", "")
	var pattern: RegEx = RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$")
	assert_bool(pattern.search(stamp) != null).is_true()
	assert_str(_model.get_modified()).is_equal(stamp)


func test_save_does_not_read_or_change_files_it_was_not_given() -> void:
	SaveFixtures.write_text(_path("other.json"), "keep me")
	assert_int(_store().save(_model, _path()).kind).is_equal(SaveResult.Kind.OK)
	assert_str(SaveFixtures.read_text(_path("other.json"))).is_equal("keep me")
	assert_array(SaveFixtures.listing(_dir)).is_equal(["other.json", "tank.json"])
