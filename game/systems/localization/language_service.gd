class_name LanguageService
extends RefCounted
## Current language, its persistence and the language_changed signal.
## Holds no reference to the model, the command history or save files.

signal language_changed(language: String)

var _store: SettingsStore
var _apply: Callable
var _language: String = LanguagePolicy.DEFAULT_LANGUAGE


## Takes the settings store and an optional Callable(code: String) that applies the locale
## (default: TranslationServer.set_locale). Tests pass a recorder.
func _init(store: SettingsStore, apply_locale: Callable = Callable()) -> void:
	_store = store
	_apply = apply_locale


## Resolves stored value, then OS locale, then English, and applies it. Emits no signal and
## never writes the settings file, so a bad stored value stays on disk.
func start(os_locale: String) -> void:
	var stored: Variant = _store.read_value(
		SettingsStore.SECTION_GENERAL, SettingsStore.KEY_LANGUAGE
	)
	_language = LanguagePolicy.resolve(stored, os_locale)
	_apply_locale(_language)


func get_language() -> String:
	return _language


## OK when the language switched or is already current; ERR_INVALID_PARAMETER for an
## unsupported code. A failed save is logged only: the language still switches for this session.
func set_language(code: String) -> Error:
	if not LanguagePolicy.is_supported(code):
		push_warning("Unsupported language: %s" % code)
		return ERR_INVALID_PARAMETER
	if code == _language:
		return OK
	_language = code
	_apply_locale(code)
	var error: Error = _store.write_value(
		SettingsStore.SECTION_GENERAL, SettingsStore.KEY_LANGUAGE, code
	)
	if error != OK:
		push_warning("Language setting not saved: %s" % error_string(error))
	language_changed.emit(code)
	return OK


func _apply_locale(code: String) -> void:
	if _apply.is_valid():
		_apply.call(code)
	else:
		TranslationServer.set_locale(code)
