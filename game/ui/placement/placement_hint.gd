class_name PlacementHint
extends Label
## The one-line hint at the bottom centre of the window (#31 AC 32 and 38). It is shown while a pick
## or a selection exists and hidden otherwise and while the world is blocked (a modal dialog or
## photo mode). It reads only EventBus signals and WorldInput, ignores the mouse and re-translates
## at once on language_changed. The text holds the live labels of the two rotate keys, left key
## first, so a remapped key (#81) stays correct.

enum Mode { NONE, PLACE, SELECTED }

const KEY_SEPARATOR: String = " / "
const NO_KEY_LABEL: String = "?"

var _mode: Mode = Mode.NONE


## The labels of the first event of place_rotate_left and place_rotate_right, joined with a slash.
static func key_labels() -> String:
	return _label_of(&"place_rotate_left") + KEY_SEPARATOR + _label_of(&"place_rotate_right")


static func _label_of(action: StringName) -> String:
	if not InputMap.has_action(action):
		return NO_KEY_LABEL
	for event: InputEvent in InputMap.action_get_events(action):
		var key: InputEventKey = event as InputEventKey
		if key != null:
			return key.as_text_physical_keycode()
	return NO_KEY_LABEL


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	visible = false
	EventBus.item_picked.connect(_on_item_picked)
	EventBus.item_pick_cleared.connect(_on_item_pick_cleared)
	EventBus.item_selected.connect(_on_item_selected)
	EventBus.item_selection_cleared.connect(_on_item_selection_cleared)
	EventBus.language_changed.connect(_on_language_changed)


func _process(_delta: float) -> void:
	_apply_visibility()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_apply_text()


func _on_item_picked(_catalog_id: StringName) -> void:
	_set_mode(Mode.PLACE)


func _on_item_pick_cleared() -> void:
	if _mode == Mode.PLACE:
		_set_mode(Mode.NONE)


func _on_item_selected(_uid: String) -> void:
	_set_mode(Mode.SELECTED)


func _on_item_selection_cleared() -> void:
	if _mode == Mode.SELECTED:
		_set_mode(Mode.NONE)


func _on_language_changed(_language: String) -> void:
	_apply_text()


func _set_mode(mode: Mode) -> void:
	_mode = mode
	_apply_text()
	_apply_visibility()


func _apply_text() -> void:
	match _mode:
		Mode.PLACE:
			text = tr("placement.hint.place") % key_labels()
		Mode.SELECTED:
			text = tr("placement.hint.selected") % key_labels()
		_:
			text = ""


func _apply_visibility() -> void:
	visible = _mode != Mode.NONE and not WorldInput.is_blocked(get_tree())
