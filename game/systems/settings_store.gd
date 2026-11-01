class_name SettingsStore
extends RefCounted
## The one settings file (user://settings.cfg), shared by every settings feature.
## It is read again on every call and replaced safely on every write; no cache.

const DEFAULT_PATH: String = "user://settings.cfg"
const BACKUP_SUFFIX: String = ".bak"
const SECTION_GENERAL: String = "general"
const KEY_LANGUAGE: String = "language"

var _path: String


func _init(path: String = DEFAULT_PATH) -> void:
	_path = path


func get_path() -> String:
	return _path


## Returns `default` for a missing, unreadable or damaged file and for a missing key.
## Never writes and never creates folders.
func read_value(section: String, key: String, default: Variant = null) -> Variant:
	var config: ConfigFile = ConfigFile.new()
	if config.load(_path) != OK:
		return default
	if not config.has_section_key(section, key):
		return default
	return config.get_value(section, key, default)


## Read-modify-write of one key; every other section and key survives. A file that does not
## parse is first copied to "<path>.bak". Returns OK or the error; the old file stays intact.
func write_value(section: String, key: String, value: Variant) -> Error:
	if not SaveStore.is_save_path_allowed(_path):
		return ERR_FILE_BAD_PATH
	var config: ConfigFile = ConfigFile.new()
	var error: Error = config.load(_path)
	if error == ERR_PARSE_ERROR:
		var old: PackedByteArray = FileAccess.get_file_as_bytes(_path)
		var copy_error: Error = SaveStore.write_atomic(_path + BACKUP_SUFFIX, old)
		if copy_error != OK:
			return copy_error
		config = ConfigFile.new()
	elif error != OK and error != ERR_FILE_NOT_FOUND:
		return error
	config.set_value(section, key, value)
	return SaveStore.write_atomic(_path, config.encode_to_text().to_utf8_buffer())
