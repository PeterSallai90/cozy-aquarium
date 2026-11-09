class_name TankDetails
extends PanelContainer
## Read-only panel with the data of the tank the room displays: name, description, interior size,
## water level, nominal volume and glass thickness. It reads the model only for the tank id and
## never changes it. Values come from the catalog; broken data shows the Unknown placeholder.

signal close_requested

const PANEL_WIDTH: float = 360.0

var _model: AquariumModel = null
var _catalog: TankCatalog = null
var _displayed_id: StringName = &""

@onready var _rows: VBoxContainer = $Layout/Rows
@onready var _fallback: Label = $Layout/FallbackLabel
@onready var _close: Button = $Layout/CloseButton


func _ready() -> void:
	for row: Node in _rows.get_children():
		(row.get_node("ValueLabel") as Label).auto_translate_mode = (
			Node.AUTO_TRANSLATE_MODE_DISABLED
		)
	_close.focus_next = NodePath(".")
	_close.focus_previous = NodePath(".")
	_close.pressed.connect(close_requested.emit)
	EventBus.tank_displayed.connect(set_displayed_tank)
	EventBus.language_changed.connect(_on_language_changed)
	visibility_changed.connect(_on_visibility_changed)
	refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		refresh()


## May be called any time; refreshes.
func setup(model: AquariumModel, catalog: TankCatalog) -> void:
	_model = model
	_catalog = catalog
	refresh()


func set_displayed_tank(tank_id: StringName) -> void:
	_displayed_id = tank_id
	refresh()


func focus_start() -> void:
	_close.grab_focus()


## Rebuilds every value text and the note; never creates or frees nodes.
func refresh() -> void:
	if not is_node_ready():
		return
	var model_id: StringName = _model.get_tank_id() if _model != null else &""
	var definition: TankDefinition = null
	if _displayed_id != &"" and _catalog != null:
		definition = _catalog.get_definition(_displayed_id)
	_fallback.visible = definition == null or _displayed_id != model_id
	if definition == null and _catalog != null:
		definition = _catalog.get_definition(AquariumModel.DEFAULT_TANK_ID)
	_fill(definition)


func _fill(definition: TankDefinition) -> void:
	var values: Array[String] = []
	if definition == null:
		for i: int in 8:
			values.append(tr("number.unknown"))
	else:
		values = [
			_text_or_unknown(definition.name_key),
			_text_or_unknown(definition.description_key),
			_cm_text(definition.interior_size_m.x, 0),
			_cm_text(definition.interior_size_m.z, 0),
			_cm_text(definition.interior_size_m.y, 0),
			_cm_text(definition.water_line_height_m, 0),
			_litres_text(definition.volume_litres),
			_cm_text(definition.glass_thickness_m, 1),
		]
	var rows: Array[Node] = _rows.get_children()
	for i: int in mini(rows.size(), values.size()):
		(rows[i].get_node("ValueLabel") as Label).text = values[i]


func _on_language_changed(_language: String) -> void:
	refresh()


func _on_visibility_changed() -> void:
	if visible:
		refresh()


func _cm_text(metres: float, decimals: int) -> String:
	if not is_finite(metres) or metres <= 0.0:
		return tr("number.unknown")
	var factor: float = pow(10.0, decimals)
	var cm: float = roundf(metres * 100.0 * factor) / factor
	if cm <= 0.0:
		return tr("number.unknown")
	return tr("unit.cm") % Localization.local_format().format_number(cm, decimals)


func _litres_text(litres: int) -> String:
	if litres <= 0:
		return tr("number.unknown")
	return tr("unit.litre") % Localization.local_format().format_number(litres, 0)


func _text_or_unknown(key: String) -> String:
	return tr("number.unknown") if key.is_empty() else tr(key)
