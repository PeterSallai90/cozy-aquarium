extends Node
## Autoload "Settings": typed settings values. Relays every real change to
## EventBus.setting_changed (once per change, never at startup, never for the language, which
## has language_changed). _ready reads and writes nothing.
##
## No class_name here: it would clash with the autoload name.

## Set only before the node enters the tree (tests).
var settings_path: String = SettingsStore.DEFAULT_PATH

var _service: SettingsService


func _ready() -> void:
	_service = SettingsService.new(SettingsStore.new(settings_path))
	_service.changed.connect(_on_changed)


func get_value(key: SettingKey) -> Variant:
	return _service.get_value(key)


func set_value(key: SettingKey, value: Variant) -> Error:
	return _service.set_value(key, value)


func get_last_save_error() -> Error:
	return _service.get_last_save_error()


func _on_changed(section: String, key: String, value: Variant) -> void:
	EventBus.setting_changed.emit(section, key, value)
