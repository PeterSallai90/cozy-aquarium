class_name FishPanel
extends PanelContainer
## The fish panel (#36): the species of the fish catalog (one toggle button each), the info card,
## Add to tank, and the "In your tank" list with a Remove button per fish. Adding and removing run
## AddFishCommand and RemoveFishCommand through the history; the panel only listens to the model's
## fish signals, so undo, redo and a model reset reach it the same way. It is non-modal (ADR 0008):
## not a world input blocker, and every interactive control stops the mouse.
##
## setup() only stores. The lists are built on the first show and then kept in sync one row at a
## time.

signal close_requested

## Fixed panel width, like the width class of the item browser.
const PANEL_WIDTH: float = 420.0
const SCREEN_MARGIN: float = 16.0
const MIN_SCROLL_HEIGHT: float = 120.0
const NAME_MIN_WIDTH: float = 120.0
const SPECIES_MIN_WIDTH: float = 90.0

var _model: AquariumModel = null
var _history: CommandHistory = null
var _species: FishCatalog = null
var _uids: UidGenerator = null
var _rng: RandomNumberGenerator = null
var _built: bool = false
var _species_id: StringName = &""
var _shown_uid: String = ""
var _species_buttons: Dictionary[StringName, Button] = {}
var _rows: Dictionary[String, Control] = {}
var _fit_queued: bool = false

@onready var _species_box: VBoxContainer = $Layout/SpeciesList
@onready var _card: FishInfoCard = $Layout/InfoCard
@onready var _add: Button = $Layout/AddButton
@onready var _count: Label = $Layout/TankHeadingRow/CountLabel
@onready var _scroll: ScrollContainer = $Layout/TankScroll
@onready var _rows_box: VBoxContainer = $Layout/TankScroll/Rows
@onready var _empty: Label = $Layout/EmptyTankLabel
@onready var _close: Button = $Layout/CloseButton


func _ready() -> void:
	custom_minimum_size.x = PANEL_WIDTH
	_add.pressed.connect(_on_add_pressed)
	_close.pressed.connect(close_requested.emit)
	EventBus.language_changed.connect(_on_language_changed)
	visibility_changed.connect(_on_visibility_changed)
	visibility_changed.connect(_queue_fit)
	_rows_box.minimum_size_changed.connect(_queue_fit)
	_card.minimum_size_changed.connect(_queue_fit)
	_species_box.minimum_size_changed.connect(_queue_fit)
	get_viewport().size_changed.connect(_queue_fit)


## Stores the collaborators; nothing is built here. A null catalog is loaded from the shipped
## folder on the first show, a null generator or random source is made then too.
func setup(
	model: AquariumModel,
	history: CommandHistory,
	species: FishCatalog = null,
	uids: UidGenerator = null,
	rng: RandomNumberGenerator = null
) -> void:
	if model == null:
		push_error("FishPanel.setup: model is null")
		return
	_model = model
	_history = history
	_species = species
	_uids = uids
	_rng = rng
	_model.fish_added.connect(_on_fish_added)
	_model.fish_removed.connect(_on_fish_removed)
	_model.fish_changed.connect(_on_fish_changed)
	_model.model_reset.connect(_on_model_reset)


## The species Add uses; empty with no species in the catalog.
func get_selected_species_id() -> StringName:
	return _species_id


## The uid of the fish on the card, or empty while the card shows a species.
func get_shown_fish_uid() -> String:
	return _shown_uid


## Puts the focus on the selected species, else Add, else Close.
func focus_start() -> void:
	_ensure_built()
	if _species_buttons.has(_species_id):
		_species_buttons[_species_id].grab_focus()
	elif not _add.disabled:
		_add.grab_focus()
	else:
		_close.grab_focus()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _built:
		_apply_texts()


func _on_language_changed(_language: String) -> void:
	if _built:
		_apply_texts()


func _on_visibility_changed() -> void:
	if visible:
		_ensure_built()


# --- building ---


func _ensure_built() -> void:
	if _built or not is_node_ready() or _model == null:
		return
	_built = true
	if _species == null:
		_species = FishCatalog.load_dir()
	if _uids == null:
		_uids = UidGenerator.new()
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.randomize()
	var group: ButtonGroup = ButtonGroup.new()
	for id: StringName in _species.get_ids():
		var button: Button = _make_species_button(id, group)
		_species_box.add_child(button)
		_species_buttons[id] = button
	_select_first_species()
	for fish: FishInstance in _model.get_fish_list():
		_add_row(fish, _rows_box.get_child_count())
	_apply_texts()
	_wire_focus()


func _make_species_button(id: StringName, group: ButtonGroup) -> Button:
	var button: Button = Button.new()
	button.name = "Species_%s" % id
	button.toggle_mode = true
	button.button_group = group
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	button.pressed.connect(_on_species_pressed.bind(id))
	return button


## With no valid selection the first catalog species is selected (none: nothing).
func _select_first_species() -> void:
	if not _species_buttons.has(_species_id):
		var ids: Array[StringName] = _species.get_ids()
		_species_id = ids[0] if not ids.is_empty() else &""
	if _species_buttons.has(_species_id):
		_species_buttons[_species_id].set_pressed_no_signal(true)


func _make_row(fish: FishInstance) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "Row_" + fish.uid
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var name_button: Button = Button.new()
	name_button.name = "NameButton"
	name_button.flat = true
	name_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_button.clip_text = true
	name_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_button.custom_minimum_size.x = NAME_MIN_WIDTH
	name_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	name_button.pressed.connect(_on_name_pressed.bind(fish.uid))
	row.add_child(name_button)
	var species_label: Label = Label.new()
	species_label.name = "SpeciesLabel"
	species_label.clip_text = true
	species_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	species_label.custom_minimum_size.x = SPECIES_MIN_WIDTH
	species_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	row.add_child(species_label)
	var remove: Button = Button.new()
	remove.name = "RemoveButton"
	remove.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	remove.pressed.connect(_on_remove_pressed.bind(fish.uid))
	row.add_child(remove)
	return row


func _add_row(fish: FishInstance, index: int) -> Control:
	var row: HBoxContainer = _make_row(fish)
	_rows_box.add_child(row)
	_rows_box.move_child(row, index)
	_rows[fish.uid] = row
	_apply_row(row, fish)
	return row


func _remove_row(uid: String) -> void:
	var row: Control = _rows.get(uid) as Control
	if row == null:
		return
	_rows.erase(uid)
	_rows_box.remove_child(row)
	row.queue_free()


# --- texts ---


## Sets every code-made text and tooltip again.
func _apply_texts() -> void:
	for id: StringName in _species_buttons:
		var definition: FishSpecies = _species.get_definition(id)
		var button: Button = _species_buttons[id]
		button.text = tr(definition.name_key)
		button.tooltip_text = tr(definition.description_key)
	for uid: String in _rows:
		var fish: FishInstance = _model.get_fish(uid)
		if fish != null:
			_apply_row(_rows[uid], fish)
	_update_state()


func _apply_row(row: Control, fish: FishInstance) -> void:
	var shown_line: String = FishNameText.one_line(FishNameText.shown_name(fish, self))
	var name_button: Button = row.get_node("NameButton") as Button
	name_button.text = FishNameText.display(shown_line)
	name_button.tooltip_text = shown_line
	var definition: FishSpecies = _species.get_definition(fish.species_id)
	var species_label: Label = row.get_node("SpeciesLabel") as Label
	species_label.text = (
		tr(definition.name_key) if definition != null else tr("fish.card.unknown_species")
	)
	var remove: Button = row.get_node("RemoveButton") as Button
	remove.text = tr("fish.browser.remove")
	remove.tooltip_text = tr("fish.browser.remove.tooltip") % shown_line


## Count, empty label, Add state and the card.
func _update_state() -> void:
	var total: int = _model.get_fish_count()
	_count.text = tr_n("fish.browser.count", "fish.browser.count.plural", total) % total
	_empty.visible = total == 0
	_add.disabled = not _species_buttons.has(_species_id)
	_update_card()


func _update_card() -> void:
	var fish: FishInstance = null
	if not _shown_uid.is_empty():
		fish = _model.get_fish(_shown_uid)
		if fish == null:
			_shown_uid = ""
	if fish != null:
		_card.show_fish(fish, _species.get_definition(fish.species_id))
	else:
		_card.show_species(_species.get_definition(_species_id))
	_queue_fit()


# --- player actions ---


func _on_species_pressed(id: StringName) -> void:
	_species_id = id
	_shown_uid = ""
	_update_card()


func _on_name_pressed(uid: String) -> void:
	_shown_uid = uid
	_update_card()


func _on_add_pressed() -> void:
	if _history == null or _history.is_busy():
		return
	var definition: FishSpecies = _species.get_definition(_species_id)
	if definition == null:
		return
	var fish: FishInstance = AddFishCommand.make_fish(_uids.generate(_model), definition, _rng)
	_history.execute(AddFishCommand.new(_model, fish))


func _on_remove_pressed(uid: String) -> void:
	if _history == null or _history.is_busy():
		return
	var row: Control = _rows.get(uid) as Control
	var by_keyboard: bool = row != null and (row.get_node("RemoveButton") as Button).has_focus()
	var index: int = row.get_index() if row != null else -1
	_history.execute(RemoveFishCommand.new(_model, uid))
	if by_keyboard and not _rows.has(uid):
		_focus_after_remove(index)


## The Remove button of the row that took the place, else of the one before, else Add.
func _focus_after_remove(index: int) -> void:
	var count: int = _rows_box.get_child_count()
	var target: Control = _add
	if index < count:
		target = _rows_box.get_child(index).get_node("RemoveButton") as Control
	elif count > 0:
		target = _rows_box.get_child(count - 1).get_node("RemoveButton") as Control
	if target is Button and (target as Button).disabled:
		target = _close
	target.grab_focus()


# --- model signals ---


func _on_fish_added(uid: String, index: int) -> void:
	if not _built:
		return
	var fish: FishInstance = _model.get_fish(uid)
	if fish == null:
		return
	_add_row(fish, index)
	_update_state()
	_wire_focus()
	_scroll_to.call_deferred(uid)


func _on_fish_removed(uid: String, _index: int) -> void:
	if not _built:
		return
	_remove_row(uid)
	if _shown_uid == uid:
		_shown_uid = ""
	_update_state()
	_wire_focus()


func _on_fish_changed(uid: String, _index: int) -> void:
	if not _built:
		return
	var fish: FishInstance = _model.get_fish(uid)
	if fish != null and _rows.has(uid):
		_apply_row(_rows[uid], fish)
	_update_card()


func _on_model_reset() -> void:
	if not _built:
		return
	for uid: String in _rows.keys():
		_remove_row(uid)
	for fish: FishInstance in _model.get_fish_list():
		_add_row(fish, _rows_box.get_child_count())
	if not _shown_uid.is_empty() and _model.get_fish(_shown_uid) == null:
		_shown_uid = ""
	_update_state()
	_wire_focus()


## Scrolls the new row into view once the layout knows its place.
func _scroll_to(uid: String) -> void:
	await get_tree().process_frame
	if not is_instance_valid(self) or not is_inside_tree():
		return
	await get_tree().process_frame
	if not is_instance_valid(self) or not is_inside_tree():
		return
	var row: Control = _rows.get(uid) as Control
	if row != null and is_instance_valid(row) and row.is_inside_tree():
		_scroll.ensure_control_visible(row)


# --- focus ---


## Tab and Shift+Tab run through the species, Add, every row (name, then Remove) and Close, and
## wrap inside the panel.
func _wire_focus() -> void:
	var order: Array[Control] = []
	for id: StringName in _species.get_ids():
		order.append(_species_buttons[id])
	if not _add.disabled:
		order.append(_add)
	for row: Node in _rows_box.get_children():
		order.append(row.get_node("NameButton") as Control)
		order.append(row.get_node("RemoveButton") as Control)
	order.append(_close)
	for index: int in order.size():
		var next: Control = order[(index + 1) % order.size()]
		var previous: Control = order[(index + order.size() - 1) % order.size()]
		order[index].focus_next = order[index].get_path_to(next)
		order[index].focus_previous = order[index].get_path_to(previous)


# --- fit ---


func _queue_fit() -> void:
	if _fit_queued or not is_inside_tree():
		return
	_fit_queued = true
	_fit_scroll.call_deferred()


## Caps the height of the list so the panel fits the window; the list scrolls when taller.
func _fit_scroll() -> void:
	_fit_queued = false
	if not is_inside_tree():
		return
	_scroll.custom_minimum_size.y = 0.0
	var content: float = _rows_box.get_combined_minimum_size().y
	var others: float = get_combined_minimum_size().y
	var available: float = (
		get_viewport().get_visible_rect().size.y - global_position.y - SCREEN_MARGIN - others
	)
	_scroll.custom_minimum_size.y = clampf(content, 0.0, maxf(available, MIN_SCROLL_HEIGHT))
