extends SettingsSection
## The Language section: one selector with the supported languages in their own names. It holds
## no language logic; it calls Localization and follows EventBus.language_changed.

@onready var _option: OptionButton = $Row/LanguageOption


func _ready() -> void:
	for code: String in localization.get_supported_languages():
		_option.add_item(localization.get_language_display_name(code))
		_option.set_item_metadata(_option.item_count - 1, code)
	_select_active()
	_option.item_selected.connect(_on_item_selected)
	EventBus.language_changed.connect(_on_language_changed)


func get_title() -> String:
	return tr("settings.section.language")


## Asks Localization for the language; afterwards the selector shows the active language again,
## also for an unsupported code or the current language.
func choose_language(code: String) -> Error:
	var error: Error = localization.set_language(code)
	_select_active()
	return error


func _select_active() -> void:
	var active: String = localization.get_language()
	for index: int in _option.item_count:
		if _option.get_item_metadata(index) == active:
			_option.select(index)
			return


func _on_item_selected(index: int) -> void:
	choose_language(_option.get_item_metadata(index) as String)


func _on_language_changed(_language: String) -> void:
	_select_active()
