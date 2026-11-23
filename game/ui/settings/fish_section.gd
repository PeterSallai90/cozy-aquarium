extends SettingsSection
## The Fish section: one toggle for [fish] show_names (#164). Placeholder UI by owner decision.
## It reads and writes the Settings only and follows EventBus.setting_changed.

@onready var _toggle: CheckButton = $Row/ShowNames


func _ready() -> void:
	_toggle.set_pressed_no_signal(_current())
	_toggle.toggled.connect(_on_toggled)
	EventBus.setting_changed.connect(_on_setting_changed)


func get_title() -> String:
	return tr("settings.section.fish")


func _current() -> bool:
	return settings.get_value(FishSettingKeys.show_names()) as bool


func _on_toggled(pressed: bool) -> void:
	settings.set_value(FishSettingKeys.show_names(), pressed)


func _on_setting_changed(section: String, key: String, _value: Variant) -> void:
	if section == "fish" and key == "show_names":
		_toggle.set_pressed_no_signal(_current())
