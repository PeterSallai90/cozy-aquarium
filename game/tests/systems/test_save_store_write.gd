# gdlint: disable=max-public-methods
extends GdUnitTestSuite

const ModelState := preload("res://tests/helpers/model_state.gd")
const SaveFixtures := preload("res://tests/helpers/save_fixtures.gd")
const SignalRecorder := preload("res://tests/helpers/signal_recorder.gd")

const STAMP := "2026-11-01T12:00:00Z"
const LATER := "2026-11-02T08:00:00Z"

var _dir: String = ""
var _model: AquariumModel


func before_test() -> void:
	_dir = SaveFixtures.make_dir("store_write")
	_model = SaveFixtures.populated_model()


func after_test() -> void:
	SaveFixtures.remove_dir(_dir)
	SaveFixtures.remove_root_if_empty()


func _store(stamp: String = STAMP) -> SaveStore:
	var clock: Callable = func() -> String: return stamp
	return SaveStore.new(clock)


func _path(file_name: String = "tank.json") -> String:
	return _dir.path_join(file_name)


func _load_name(path: String) -> String:
	var target: AquariumModel = AquariumModel.new(STAMP)
	var result: SaveResult = _store().load_into(path, target, CommandHistory.new())
	assert_int(result.kind).is_equal(SaveResult.Kind.OK)
	return target.get_aquarium_name()


# --- where files go ------------------------------------------------------------------------


func test_save_creates_missing_folder() -> void:
	var path: String = _path("a/b/c/tank.json")
	assert_bool(DirAccess.dir_exists_absolute(_path("a"))).is_false()
	var result: SaveResult = _store().save(_model, path)
	assert_int(result.kind).is_equal(SaveResult.Kind.OK)
	assert_bool(FileAccess.file_exists(path)).is_true()
	assert_array(SaveFixtures.listing(_path("a/b/c"))).is_equal(["tank.json"])


func test_save_writes_the_file_at_the_given_user_path() -> void:
	var path: String = _path()
	assert_int(_store().save(_model, path).kind).is_equal(SaveResult.Kind.OK)
	assert_bool(FileAccess.file_exists(path)).is_true()
	assert_array(SaveFixtures.listing(_dir)).is_equal(["tank.json"])
	assert_bool(SaveFixtures.read_bytes(path).size() > 100).is_true()


func test_is_save_path_allowed_truth_table() -> void:
	var allowed: Array = [
		"user://a.json",
		"user://saves/a.json",
		"user://saves/deeper/a.json",
		"user://a..b.json",
		"user://..a/b.json",
		"user://a/b..json",
		"user://.hidden/a.json",
		"user://a b/c d.json",
	]
	var refused: Array = [
		"",
		"user://",
		"user:/a.json",
		"res://a.json",
		"res://tests/fixtures/saves/golden_v1.json",
		"C:/x.json",
		"C:\\x.json",
		"/tmp/x.json",
		"x.json",
		"../x.json",
		"user://../x.json",
		"user://a/../b.json",
		"user://a/..",
		"user://..",
		"user://a\\..\\b.json",
		"user://..\\x.json",
		"user://saves/",
		"user://saves\\",
		"user://a/b/",
		"USER://x.json",
	]
	var failures: PackedStringArray = PackedStringArray()
	for path: String in allowed:
		if not SaveStore.is_save_path_allowed(path):
			failures.append("'%s' should be allowed" % path)
	for path: String in refused:
		if SaveStore.is_save_path_allowed(path):
			failures.append("'%s' should be refused" % path)
	assert_array(failures).is_empty()


func test_refused_paths() -> void:
	var refused: Array = [
		"res://tests/fixtures/saves/refused_by_test.json",
		"C:/cozy_aquarium_refused_by_test.json",
		"/tmp/cozy_aquarium_refused_by_test.json",
		"user://../cozy_aquarium_refused_by_test.json",
		"user://test_saves/store_write/a/../b.json",
		"user://test_saves/store_write/a\\..\\b.json",
		"user://test_saves/store_write/",
		"user://",
		"",
	]
	var before: Array = [_model.get_modified(), SaveFixtures.listing(_dir)]
	var recorder: SignalRecorder = SignalRecorder.new()
	recorder.watch(_model)
	var failures: PackedStringArray = PackedStringArray()
	for path: String in refused:
		var result: SaveResult = _store().save(_model, path)
		if result.kind != SaveResult.Kind.PATH_REFUSED:
			failures.append("'%s' gave kind %d" % [path, result.kind])
		if not path.is_empty() and not path.ends_with("/") and FileAccess.file_exists(path):
			failures.append("'%s' was written" % path)
	assert_array(failures).is_empty()
	assert_str(_model.get_modified()).is_equal(before[0])
	assert_array(SaveFixtures.listing(_dir)).is_equal(before[1])
	assert_array(recorder.events).is_empty()
	for stray: String in refused:
		if stray.begins_with("C:/") or stray.begins_with("/tmp/"):
			DirAccess.remove_absolute(stray)


# --- the writer refuses a model the reader would refuse -----------------------------------------


func test_internal_writes_nothing_and_keeps_previous_file() -> void:
	var path: String = _path()
	assert_int(_store().save(_model, path).kind).is_equal(SaveResult.Kind.OK)
	var before: PackedByteArray = SaveFixtures.read_bytes(path)
	var names: PackedStringArray = SaveFixtures.listing(_dir)
	_model.apply_set_name("changed after the first save")
	var broken: Array = [
		func(m: AquariumModel) -> void: m.get_item_at(0).scale = INF,
		func(m: AquariumModel) -> void: m.get_item_at(0).position = Vector3(NAN, 0.0, 0.0),
		func(m: AquariumModel) -> void: m.get_fish_at(0).uid = "NOT-HEX!",
		func(m: AquariumModel) -> void: m.get_fish_at(0).variant = 256,
		func(m: AquariumModel) -> void:
			m.apply_set_heightmap(PackedFloat32Array([1.0]), Vector2i(2, 2)),
	]
	var failures: PackedStringArray = PackedStringArray()
	for index: int in broken.size():
		var model: AquariumModel = SaveFixtures.populated_model()
		var mutate: Callable = broken[index]
		mutate.call(model)
		var modified: String = model.get_modified()
		var result: SaveResult = _store(LATER).save(model, path)
		if result.kind != SaveResult.Kind.INTERNAL:
			failures.append("case %d: kind %d" % [index, result.kind])
		if SaveFixtures.read_bytes(path) != before:
			failures.append("case %d: previous file changed" % index)
		if SaveFixtures.listing(_dir) != names:
			failures.append("case %d: files in the folder changed" % index)
		if model.get_modified() != modified:
			failures.append("case %d: modified changed" % index)
	assert_array(failures).is_empty()


func test_internal_for_a_bad_model_with_no_previous_file() -> void:
	_model.get_item_at(0).scale = 0.0
	var result: SaveResult = _store().save(_model, _path())
	assert_int(result.kind).is_equal(SaveResult.Kind.INTERNAL)
	assert_array(SaveFixtures.listing(_dir)).is_empty()


func test_save_of_a_null_model_is_internal() -> void:
	var result: SaveResult = _store().save(null, _path())
	assert_int(result.kind).is_equal(SaveResult.Kind.INTERNAL)
	assert_array(SaveFixtures.listing(_dir)).is_empty()


func test_internal_for_a_bad_clock_stamp_writes_nothing() -> void:
	var result: SaveResult = _store("not a stamp").save(_model, _path())
	assert_int(result.kind).is_equal(SaveResult.Kind.INTERNAL)
	assert_array(SaveFixtures.listing(_dir)).is_empty()
	assert_str(_model.get_modified()).is_equal(SaveFixtures.STAMP_CREATED)


# --- failed writes ---------------------------------------------------------------------------


func _block_tmp(path: String) -> void:
	# A folder with a file in it where the temporary file would go makes the open for write fail.
	var blocker: String = path + ".tmp"
	DirAccess.make_dir_recursive_absolute(blocker)
	SaveFixtures.write_text(blocker.path_join("keep.txt"), "x")


func test_write_failure_keeps_previous_save() -> void:
	var path: String = _path()
	assert_int(_store().save(_model, path).kind).is_equal(SaveResult.Kind.OK)
	var before: PackedByteArray = SaveFixtures.read_bytes(path)
	_block_tmp(path)
	var names: PackedStringArray = SaveFixtures.listing(_dir)
	_model.apply_set_name("A newer name that never reached the disk")
	var result: SaveResult = _store(LATER).save(_model, path)
	assert_int(result.kind).is_equal(SaveResult.Kind.WRITE_FAILED)
	assert_bool(SaveFixtures.read_bytes(path) == before).is_true()
	assert_array(SaveFixtures.listing(_dir)).is_equal(names)
	assert_array(SaveFixtures.listing(path + ".tmp")).is_equal(["keep.txt"])
	assert_str(_load_name(path)).is_equal("Reef Árvíztűrő")


func test_failed_write_keeps_modified_and_emits_nothing() -> void:
	var path: String = _path()
	_block_tmp(path)
	var modified: String = _model.get_modified()
	var created: String = _model.get_created()
	var recorder: SignalRecorder = SignalRecorder.new()
	recorder.watch(_model)
	var result: SaveResult = _store(LATER).save(_model, path)
	assert_int(result.kind).is_equal(SaveResult.Kind.WRITE_FAILED)
	assert_str(_model.get_modified()).is_equal(modified)
	assert_str(_model.get_created()).is_equal(created)
	assert_array(recorder.events).is_empty()
	assert_bool(FileAccess.file_exists(path)).is_false()


func test_parent_is_a_file_is_write_failed() -> void:
	SaveFixtures.write_text(_path("blocker"), "I am a file, not a folder")
	var names: PackedStringArray = SaveFixtures.listing(_dir)
	var recorder: SignalRecorder = SignalRecorder.new()
	recorder.watch(_model)
	var modified: String = _model.get_modified()
	var result: SaveResult = _store(LATER).save(_model, _path("blocker/tank.json"))
	assert_int(result.kind).is_equal(SaveResult.Kind.WRITE_FAILED)
	assert_array(SaveFixtures.listing(_dir)).is_equal(names)
	assert_str(SaveFixtures.read_text(_path("blocker"))).is_equal("I am a file, not a folder")
	assert_str(_model.get_modified()).is_equal(modified)
	assert_array(recorder.events).is_empty()


func test_target_that_is_a_folder_is_write_failed_and_untouched() -> void:
	var path: String = _path("tank.json")
	DirAccess.make_dir_recursive_absolute(path)
	SaveFixtures.write_text(path.path_join("inside.txt"), "x")
	var result: SaveResult = _store().save(_model, path)
	assert_int(result.kind).is_equal(SaveResult.Kind.WRITE_FAILED)
	assert_array(SaveFixtures.listing(path)).is_equal(["inside.txt"])
	assert_bool(FileAccess.file_exists(path + ".tmp")).is_false()


# --- replacing an existing save --------------------------------------------------------------


func test_save_over_existing_replaces_and_leaves_no_tmp() -> void:
	var path: String = _path()
	var store: SaveStore = _store()
	assert_int(store.save(_model, path).kind).is_equal(SaveResult.Kind.OK)
	assert_str(_load_name(path)).is_equal("Reef Árvíztűrő")
	_model.apply_set_name("Second save")
	assert_int(_store(LATER).save(_model, path).kind).is_equal(SaveResult.Kind.OK)
	assert_str(_load_name(path)).is_equal("Second save")
	assert_str(SaveFixtures.read_json(path).get("modified", "")).is_equal(LATER)
	assert_array(SaveFixtures.listing(_dir)).is_equal(["tank.json"])
	assert_bool(FileAccess.file_exists(path + ".tmp")).is_false()
	assert_bool(FileAccess.file_exists(path + ".bak")).is_false()


func test_save_over_a_longer_existing_file_leaves_no_old_tail() -> void:
	var path: String = _path()
	SaveFixtures.write_text(path, "x".repeat(200000))
	assert_int(_store().save(_model, path).kind).is_equal(SaveResult.Kind.OK)
	var expected: SaveResult = SaveCodec.new().encode(_model, STAMP)
	assert_bool(SaveFixtures.read_bytes(path) == expected.text.to_utf8_buffer()).is_true()


func test_stale_tmp_is_overwritten() -> void:
	var path: String = _path()
	SaveFixtures.write_text(path + ".tmp", "garbage from an earlier crash".repeat(5000))
	assert_int(_store().save(_model, path).kind).is_equal(SaveResult.Kind.OK)
	assert_bool(FileAccess.file_exists(path + ".tmp")).is_false()
	assert_array(SaveFixtures.listing(_dir)).is_equal(["tank.json"])
	assert_str(_load_name(path)).is_equal("Reef Árvíztűrő")


func test_stale_tmp_next_to_an_existing_save_is_overwritten() -> void:
	var path: String = _path()
	assert_int(_store().save(_model, path).kind).is_equal(SaveResult.Kind.OK)
	SaveFixtures.write_text(path + ".tmp", "stale")
	_model.apply_set_name("Third")
	assert_int(_store(LATER).save(_model, path).kind).is_equal(SaveResult.Kind.OK)
	assert_array(SaveFixtures.listing(_dir)).is_equal(["tank.json"])
	assert_str(_load_name(path)).is_equal("Third")


# --- write_atomic ----------------------------------------------------------------------------


func test_write_atomic_writes_exactly_the_bytes() -> void:
	var path: String = _path("sub/data.bin")
	var bytes: PackedByteArray = PackedByteArray([0, 1, 2, 255, 10, 13, 0, 7])
	assert_int(SaveStore.write_atomic(path, bytes)).is_equal(OK)
	assert_bool(SaveFixtures.read_bytes(path) == bytes).is_true()
	assert_array(SaveFixtures.listing(_path("sub"))).is_equal(["data.bin"])


func test_write_atomic_replaces_existing_and_leaves_no_tmp() -> void:
	var path: String = _path("data.bin")
	assert_int(SaveStore.write_atomic(path, "first, a longer content".to_utf8_buffer())).is_equal(
		OK
	)
	assert_int(SaveStore.write_atomic(path, "second".to_utf8_buffer())).is_equal(OK)
	assert_str(SaveFixtures.read_text(path)).is_equal("second")
	assert_array(SaveFixtures.listing(_dir)).is_equal(["data.bin"])


func test_write_atomic_empty_bytes() -> void:
	var path: String = _path("empty.bin")
	assert_int(SaveStore.write_atomic(path, PackedByteArray())).is_equal(OK)
	assert_bool(FileAccess.file_exists(path)).is_true()
	assert_int(SaveFixtures.read_bytes(path).size()).is_equal(0)


func test_write_atomic_reports_an_error_when_the_parent_is_a_file() -> void:
	SaveFixtures.write_text(_path("blocker"), "file")
	var error: int = SaveStore.write_atomic(_path("blocker/x.bin"), PackedByteArray([1]))
	assert_int(error).is_not_equal(OK)
	assert_array(SaveFixtures.listing(_dir)).is_equal(["blocker"])


func test_write_atomic_failure_keeps_the_old_file() -> void:
	var path: String = _path("data.bin")
	assert_int(SaveStore.write_atomic(path, "old".to_utf8_buffer())).is_equal(OK)
	_block_tmp(path)
	var error: int = SaveStore.write_atomic(path, "new".to_utf8_buffer())
	assert_int(error).is_not_equal(OK)
	assert_str(SaveFixtures.read_text(path)).is_equal("old")


func test_write_atomic_fails_while_the_target_is_open_for_reading_and_keeps_it() -> void:
	# Engine check A: on Windows a rename over a file that is open for reading fails cleanly.
	# On other platforms the rename may succeed; both outcomes must leave a complete file.
	var path: String = _path("data.bin")
	assert_int(SaveStore.write_atomic(path, "old".to_utf8_buffer())).is_equal(OK)
	var reader: FileAccess = FileAccess.open(path, FileAccess.READ)
	var error: int = SaveStore.write_atomic(path, "new".to_utf8_buffer())
	reader = null
	var text: String = SaveFixtures.read_text(path)
	if error == OK:
		assert_str(text).is_equal("new")
	else:
		assert_str(text).is_equal("old")
	assert_array(SaveFixtures.listing(_dir)).is_equal(["data.bin"])
