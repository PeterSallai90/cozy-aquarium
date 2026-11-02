extends Control
## The settings screen shell: title, one tab per section, a message line and Close. Sections are
## listed in settings_sections.tres or added with add_section(). The screen is self-contained:
## it can run on its own, hides itself on Esc or Close and emits `closed`; the caller decides
## what happens next.

signal closed

@export var section_list: SettingsSectionList = preload("res://ui/settings/settings_sections.tres")

## The two services; set before the screen enters the tree (tests), else the live autoloads.
var localization: Node = null
var settings: Node = null

var _pending: Array[SettingsSection] = []
var _sections: Array[SettingsSection] = []

@onready var _tabs: TabContainer = $Panel/Layout/Sections
@onready var _message: Label = $Panel/Layout/Message
@onready var _close: Button = $Panel/Layout/Footer/Close


func _ready() -> void:
	if localization == null:
		localization = get_node("/root/Localization")
	if settings == null:
		settings = get_node("/root/Settings")
	# Tab titles are set from code already translated; sections keep normal auto-translate.
	_tabs.get_tab_bar().auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_close.pressed.connect(close)
	EventBus.language_changed.connect(_on_language_changed)
	EventBus.setting_changed.connect(_on_setting_changed)
	if section_list != null:
		for scene: PackedScene in section_list.sections:
			add_section(scene.instantiate() as SettingsSection)
	for section: SettingsSection in _pending:
		add_section(section)
	_pending.clear()
	if visible:
		open()


## Adds a section as the last tab. Before _ready it is queued and comes after the listed ones.
func add_section(section: SettingsSection) -> void:
	if not is_node_ready():
		_pending.append(section)
		return
	section.localization = localization
	section.settings = settings
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "Scroll_%s" % section.name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(section)
	_tabs.add_child(scroll)
	_sections.append(section)
	_tabs.set_tab_title(_tabs.get_tab_count() - 1, section.get_title())


## Shows the screen with no old message and puts the focus on its first control. Writes nothing.
func open() -> void:
	show()
	_show_save_state(OK)
	var section: SettingsSection = _current_section()
	if section != null:
		for node: Node in section.find_children("*", "Control", true, false):
			var control: Control = node as Control
			if control.focus_mode == Control.FOCUS_ALL and control.is_visible_in_tree():
				control.grab_focus()
				return
	_tabs.get_tab_bar().grab_focus()


## Hides the screen and emits `closed` once; does nothing when it is already hidden.
func close() -> void:
	if not visible:
		return
	_show_save_state(OK)
	hide()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what != NOTIFICATION_TRANSLATION_CHANGED or not is_node_ready():
		return
	for index: int in _sections.size():
		_tabs.set_tab_title(index, _sections[index].get_title())
	if _message.visible:
		_message.text = tr("settings.error.not_saved")


func _current_section() -> SettingsSection:
	var index: int = _tabs.current_tab
	if index < 0 or index >= _sections.size():
		return null
	return _sections[index]


func _show_save_state(error: Error) -> void:
	if error == OK:
		_message.text = ""
		_message.hide()
	else:
		_message.text = tr("settings.error.not_saved")
		_message.show()


func _on_language_changed(_language: String) -> void:
	_show_save_state(localization.get_last_save_error())


func _on_setting_changed(_section: String, _key: String, _value: Variant) -> void:
	_show_save_state(settings.get_last_save_error())
