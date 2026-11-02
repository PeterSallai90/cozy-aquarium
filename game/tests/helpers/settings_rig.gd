extends RefCounted
## Loads the B09a settings code by path, so a missing script fails the test that needs it and not
## the whole suite at parse time. Also builds fresh autoload instances on a test path: tests never
## write through the live /root/Localization or /root/Settings. Test helper only.

const KEY_SCRIPT := "res://systems/settings/setting_key.gd"
const SERVICE_SCRIPT := "res://systems/settings/settings_service.gd"
const SETTINGS_AUTOLOAD := "res://systems/settings/settings.gd"
const LOCALIZATION_AUTOLOAD := "res://systems/localization/localization.gd"
const LIST_SCRIPT := "res://ui/settings/settings_section_list.gd"
const SCREEN_SCENE := "res://ui/settings/settings_screen.tscn"
const LANGUAGE_SCENE := "res://ui/settings/language_section.tscn"
const SECTIONS_RESOURCE := "res://ui/settings/settings_sections.tres"
const FIXTURE_TITLE := "Fixture section"


static func load_or_null(path: String) -> Resource:
	if not ResourceLoader.exists(path):
		return null
	return load(path)


## A SettingKey; null while the class is missing.
static func key(
	section: String,
	name: String,
	value_type: int,
	default_value: Variant,
	min_value: float = NAN,
	max_value: float = NAN
) -> RefCounted:
	var script: GDScript = load_or_null(KEY_SCRIPT) as GDScript
	if script == null:
		return null
	return script.new(section, name, value_type, default_value, min_value, max_value)


## The fixture key of the plumbing tests: [fixture] volume, float 0.0 to 1.0, default 0.5.
static func volume_key() -> RefCounted:
	return key("fixture", "volume", TYPE_FLOAT, 0.5, 0.0, 1.0)


## The second fixture key: [fixture] pan, float -1.0 to 1.0, default 0.0.
static func pan_key() -> RefCounted:
	return key("fixture", "pan", TYPE_FLOAT, 0.0, -1.0, 1.0)


## A SettingsService on a store at the path; null while the class is missing.
static func service(path: String, store: SettingsStore = null) -> RefCounted:
	var script: GDScript = load_or_null(SERVICE_SCRIPT) as GDScript
	if script == null:
		return null
	return script.new(store if store != null else SettingsStore.new(path))


## A fresh Settings autoload instance in the tree of `parent`; null while the script is missing.
static func make_settings(parent: Node, path: String) -> Node:
	var script: GDScript = load_or_null(SETTINGS_AUTOLOAD) as GDScript
	if script == null:
		return null
	var node: Node = script.new()
	node.settings_path = path
	parent.add_child(node)
	return node


## A fresh Localization autoload instance with an injected OS locale.
static func make_localization(parent: Node, path: String, os_locale: String) -> Node:
	var node: Node = load(LOCALIZATION_AUTOLOAD).new()
	node.settings_path = path
	node.os_locale_source = func() -> String: return os_locale
	parent.add_child(node)
	return node


## A SettingsSectionList resource holding the given scenes; null while the class is missing.
static func section_list(scenes: Array[PackedScene]) -> Resource:
	var script: GDScript = load_or_null(LIST_SCRIPT) as GDScript
	if script == null:
		return null
	var list: Resource = script.new()
	list.set("sections", scenes)
	return list


## The fixture section: a SettingsSection with a constant title, a Label ("Info") and a focusable
## Button ("FixtureButton"). Built from source at run time, so a missing SettingsSection fails
## the tests that use it and does not stop gdUnit from scanning the test folder. Null while the
## base class is missing.
static func make_fixture() -> Control:
	var script: GDScript = GDScript.new()
	var lines: PackedStringArray = ["extends SettingsSection", "", "func get_title() -> String:"]
	lines.append('\treturn "%s"' % FIXTURE_TITLE)
	script.source_code = "\n".join(lines) + "\n"
	if script.reload() != OK:
		return null
	var section: Control = script.new() as Control
	if section == null:
		return null
	var info: Label = Label.new()
	info.name = "Info"
	info.text = "Fixture content"
	section.add_child(info)
	var button: Button = Button.new()
	button.name = "FixtureButton"
	button.text = "Fixture button"
	section.add_child(button)
	return section


## The fixture section packed as a scene, for a SettingsSectionList; null while it cannot be built.
static func fixture_scene() -> PackedScene:
	var section: Control = make_fixture()
	if section == null:
		return null
	for child: Node in section.get_children():
		child.owner = section
	var packed: PackedScene = PackedScene.new()
	var error: Error = packed.pack(section)
	section.free()
	if error != OK:
		return null
	return packed


static func read_config(path: String) -> ConfigFile:
	var config: ConfigFile = ConfigFile.new()
	config.load(path)
	return config


## The text a control shows now: its own text translated (a key and finished text both work).
static func shown(label: Control) -> String:
	return label.tr(label.get("text"))


## A settings screen with both services injected, not yet in the tree; null while the scene is
## missing. Pass a SettingsSectionList to replace the shipped list.
static func new_screen(settings: Node, localization: Node, list: Resource = null) -> Control:
	var packed: PackedScene = load_or_null(SCREEN_SCENE) as PackedScene
	if packed == null:
		return null
	var screen: Control = packed.instantiate() as Control
	screen.localization = localization
	screen.settings = settings
	if list != null:
		screen.section_list = list
	return screen


## The node with this name below the screen; null when there is none.
static func part(screen: Node, node_name: String) -> Node:
	return screen.find_child(node_name, true, false)


## The Language section: the node that has choose_language.
static func language_section(screen: Node) -> Node:
	for node: Node in screen.find_children("*", "", true, false):
		if node.has_method("choose_language"):
			return node
	return null


## Every focusable, visible control below the node, in tree order.
static func focusable(root: Node) -> Array[Control]:
	var result: Array[Control] = []
	for node: Node in root.find_children("*", "Control", true, false):
		var control: Control = node as Control
		if control.focus_mode == Control.FOCUS_ALL and control.is_visible_in_tree():
			result.append(control)
	return result
