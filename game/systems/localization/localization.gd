extends Node
## Autoload "Localization": the language API. The settings screen calls only these methods and
## listens to EventBus.language_changed; it holds no language logic.
##
## No class_name here: it would clash with the autoload name.

## Set only before the node enters the tree (tests). Defaults: the real settings file and
## OS.get_locale(); this is the only place that reads the OS locale.
var settings_path: String = SettingsStore.DEFAULT_PATH
var os_locale_source: Callable = Callable()

var _service: LanguageService
var _format: LocalFormat


func _ready() -> void:
	_service = LanguageService.new(SettingsStore.new(settings_path))
	_service.language_changed.connect(_on_language_changed)
	var locale: String
	if os_locale_source.is_valid():
		locale = os_locale_source.call() as String
	else:
		locale = OS.get_locale()
	_service.start(locale)
	_format = LocalFormat.new(
		get_language,
		func() -> int: return LocalFormat.system_offset_minutes(),
		func() -> float: return Time.get_unix_time_from_system()
	)


## The date, time and number helper; null before this node is ready.
func local_format() -> LocalFormat:
	return _format


func get_supported_languages() -> PackedStringArray:
	return LanguagePolicy.supported_languages()


func get_language_display_name(code: String) -> String:
	return LanguagePolicy.display_name(code)


func get_language() -> String:
	return _service.get_language()


func set_language(code: String) -> Error:
	return _service.set_language(code)


func _on_language_changed(language: String) -> void:
	EventBus.language_changed.emit(language)
