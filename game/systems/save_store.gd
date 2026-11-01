class_name SaveStore
extends RefCounted
## Saves and loads an AquariumModel as a file: path policy, safe write, clock and the load
## orchestration. The format itself lives in SaveCodec (game/model). Not an autoload and no
## EventBus reference: the history relays its own signals through EventBus when it is bound.
##
## Saving is allowed only below user:// . Loading reads any readable path, because it never
## writes; the player-facing load only offers files from the save folder.

const _USER_PREFIX: String = "user://"
const _TEMP_SUFFIX: String = ".tmp"

var _clock: Callable = Callable()
var _codec: SaveCodec = null


## `clock` is a Callable returning a stamp (YYYY-MM-DDTHH:MM:SSZ). When empty or invalid the
## system clock is used (UTC). `codec` is only passed by tests that need another format version.
func _init(clock: Callable = Callable(), codec: SaveCodec = null) -> void:
	_clock = clock
	_codec = codec if codec != null else SaveCodec.new()


## Writes the model to the path. PATH_REFUSED for a path outside user://, INTERNAL for a null
## model or one the writer refuses, WRITE_FAILED when the file cannot be written. Takes exactly
## one stamp from the clock. Only after the file was replaced is the model's modified time set
## to that stamp (no signal, no history change). On any error the model is untouched.
func save(model: AquariumModel, path: String) -> SaveResult:
	if model == null:
		return SaveResult.failure(SaveResult.Kind.INTERNAL, "save() called with a null model")
	if not is_save_path_allowed(path):
		return SaveResult.failure(SaveResult.Kind.PATH_REFUSED, "not a save path: %s" % path)
	var stamp: String = _now()
	var encoded: SaveResult = _codec.encode(model, stamp)
	if not encoded.is_ok():
		return encoded
	var error: Error = write_atomic(path, encoded.text.to_utf8_buffer())
	if error != OK:
		return SaveResult.failure(SaveResult.Kind.WRITE_FAILED, error_string(error))
	model.set_save_times(model.get_created(), stamp)
	return SaveResult.success()


## Reads the file into a fresh model; only if everything is valid, refills `model` in place
## (model_reset once) and then clears `history` (history_changed(false, false)), in that order.
## Any other outcome leaves the model, its listeners, the history and the file exactly as they
## were: NOT_FOUND (missing or unreadable), DAMAGED, NEWER_VERSION, or INTERNAL for a null
## argument or a busy history (a load started from a model or history signal handler).
## A load started from a model_reset handler is allowed: it completes fully, and the outer load
## then clears an already empty history.
func load_into(path: String, model: AquariumModel, history: CommandHistory) -> SaveResult:
	if model == null or history == null:
		return SaveResult.failure(
			SaveResult.Kind.INTERNAL, "load_into() called with a null argument"
		)
	if history.is_busy():
		return SaveResult.failure(SaveResult.Kind.INTERNAL, "load_into() while the history is busy")
	var read: Variant = _read_file(path)
	if read is SaveResult:
		return read
	var bytes: PackedByteArray = read
	var decoded: SaveResult = _codec.decode_bytes(bytes, _now())
	if not decoded.is_ok():
		return decoded
	model.reset_from(decoded.model)
	history.clear()
	return SaveResult.success()


## True only for a path that begins with user://, has something after it, does not end with a
## slash or backslash, and has no ".." segment (split on both separators).
static func is_save_path_allowed(path: String) -> bool:
	if not path.begins_with(_USER_PREFIX):
		return false
	var rest: String = path.substr(_USER_PREFIX.length())
	if rest.is_empty() or rest.ends_with("/") or rest.ends_with("\\"):
		return false
	for segment: String in rest.replace("\\", "/").split("/"):
		if segment == "..":
			return false
	return true


## Writes the bytes next to the target as <path>.tmp, checks them, then renames over the target.
## Creates missing folders. A stale .tmp from an earlier crash is overwritten. On any failure the
## .tmp file is removed and the target still holds its old complete content.
## Callers must check is_save_path_allowed() first; this does not apply the path policy itself.
static func write_atomic(path: String, bytes: PackedByteArray) -> Error:
	if DirAccess.dir_exists_absolute(path):
		return ERR_FILE_CANT_WRITE
	var folder: String = path.get_base_dir()
	var folder_error: Error = DirAccess.make_dir_recursive_absolute(folder)
	if not DirAccess.dir_exists_absolute(folder):
		return folder_error if folder_error != OK else ERR_CANT_CREATE
	var temp_path: String = path + _TEMP_SUFFIX
	var error: Error = _write_checked(temp_path, bytes)
	if error == OK:
		error = DirAccess.rename_absolute(temp_path, path)
	if error != OK and FileAccess.file_exists(temp_path):
		DirAccess.remove_absolute(temp_path)
	return error


# --- Internals ------------------------------------------------------------------------------


static func _write_checked(path: String, bytes: PackedByteArray) -> Error:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(bytes)
	var error: Error = file.get_error()
	if error == OK:
		file.flush()
		error = file.get_error()
	file.close()
	if error != OK:
		return error
	var check: FileAccess = FileAccess.open(path, FileAccess.READ)
	if check == null:
		return FileAccess.get_open_error()
	if check.get_length() != bytes.size():
		return ERR_FILE_CORRUPT
	return OK


## The file content as PackedByteArray, or a failed SaveResult: NOT_FOUND when the path is not a
## readable file, DAMAGED when it is larger than the limit (not read at all).
func _read_file(path: String) -> Variant:
	if DirAccess.dir_exists_absolute(path):
		return SaveResult.failure(SaveResult.Kind.NOT_FOUND, "the path is a folder")
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return SaveResult.failure(
			SaveResult.Kind.NOT_FOUND, error_string(FileAccess.get_open_error())
		)
	var length: int = file.get_length()
	if length > SaveCodec.MAX_FILE_BYTES:
		return SaveResult.failure(SaveResult.Kind.DAMAGED, "the file is larger than the limit")
	var bytes: PackedByteArray = file.get_buffer(length)
	if file.get_error() != OK or bytes.size() != length:
		return SaveResult.failure(SaveResult.Kind.NOT_FOUND, "the file could not be read")
	return bytes


func _now() -> String:
	if _clock.is_valid():
		return String(_clock.call())
	return Time.get_datetime_string_from_system(true) + "Z"
