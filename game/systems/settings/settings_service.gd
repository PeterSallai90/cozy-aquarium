class_name SettingsService
extends RefCounted
## Typed settings on top of SettingsStore: a session cache, one write per real change and a
## changed signal. Holds no reference to the model, the command history or save files.

signal changed(section: String, key: String, value: Variant)

var _store: SettingsStore
var _values: Dictionary[String, Variant] = {}
var _last_save_error: Error = OK


func _init(store: SettingsStore) -> void:
	_store = store


## The session value, else the stored value coerced to the key. Never writes.
func get_value(key: SettingKey) -> Variant:
	var id: String = key.id()
	if _values.has(id):
		return _values[id]
	var value: Variant = key.coerce(_store.read_value(key.section, key.key, key.default_value))
	_values[id] = value
	return value


## OK, or ERR_INVALID_PARAMETER for a value of the wrong type. A same value writes nothing and
## emits nothing. A failed save is logged and reported by get_last_save_error(); the value
## still holds for the session.
func set_value(key: SettingKey, value: Variant) -> Error:
	if not key.accepts(value):
		push_warning("Wrong type for setting %s" % key.id())
		return ERR_INVALID_PARAMETER
	var coerced: Variant = key.coerce(value)
	var current: Variant = get_value(key)
	if typeof(coerced) == typeof(current) and coerced == current:
		return OK
	_values[key.id()] = coerced
	_last_save_error = _store.write_value(key.section, key.key, coerced)
	if _last_save_error != OK:
		push_warning("Setting %s not saved: %s" % [key.id(), error_string(_last_save_error)])
	changed.emit(key.section, key.key, coerced)
	return OK


## The result of the latest write; OK when there was none.
func get_last_save_error() -> Error:
	return _last_save_error
