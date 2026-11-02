class_name SettingsSection
extends VBoxContainer
## Base of one settings section (a tab of the settings screen). The screen sets `localization`
## and `settings` before the section enters the tree. Later issues add a section by extending
## this class and appending its scene to settings_sections.tres.

var localization: Node = null
var settings: Node = null


## The tab title. Subclasses return tr("literal.key"); the screen asks again when the language
## changes.
func get_title() -> String:
	return ""
