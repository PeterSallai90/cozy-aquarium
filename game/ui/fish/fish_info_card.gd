class_name FishInfoCard
extends VBoxContainer
## The info card of the fish panel (#36): the common name, the Latin name exactly as stored, the
## description, the adult length and the water zone of one species, with the name of the fish on
## top while a fish is shown. Text only. An unknown species shows a placeholder name and nothing
## else. Every text is set in code, so no node looks a nickname or a Latin name up as a key.

var _fish: FishInstance = null
var _species: FishSpecies = null
var _has_subject: bool = false

@onready var _fish_name: Label = $FishNameLabel
@onready var _common: Label = $CommonNameLabel
@onready var _latin: Label = $LatinLabel
@onready var _description: Label = $DescriptionLabel
@onready var _length_row: Control = $LengthRow
@onready var _length_caption: Label = $LengthRow/LengthCaption
@onready var _length_value: Label = $LengthRow/LengthValue
@onready var _zone_row: Control = $ZoneRow
@onready var _zone_caption: Label = $ZoneRow/ZoneCaption
@onready var _zone_value: Label = $ZoneRow/ZoneValue


func _ready() -> void:
	refresh()


## Shows a species (no fish name line). A null species hides the card.
func show_species(species: FishSpecies) -> void:
	_fish = null
	_species = species
	_has_subject = species != null
	refresh()


## Shows one fish: its name on top, then the data of its species. A null species shows the
## unknown-species placeholder.
func show_fish(fish: FishInstance, species: FishSpecies) -> void:
	_fish = fish
	_species = species
	_has_subject = fish != null
	refresh()


## Sets every text again, for example after a language change.
func refresh() -> void:
	if not is_node_ready():
		return
	visible = _has_subject
	if not _has_subject:
		return
	_fish_name.visible = _fish != null
	if _fish != null:
		var full: String = FishNameText.one_line(FishNameText.shown_name(_fish, self))
		_fish_name.text = FishNameText.display(full)
		_fish_name.tooltip_text = full
	if _species == null:
		_show_unknown()
		return
	_common.text = tr(_species.name_key)
	var latin: String = _species.scientific_name
	_latin.text = latin
	_latin.visible = not latin.is_empty()
	_description.text = tr(_species.description_key)
	_description.visible = true
	_length_caption.text = tr("fish.card.length")
	_length_value.text = _length_text(_species.adult_length_cm)
	_length_row.visible = true
	var zone: String = _zone_text(_species.preferred_zone)
	_zone_row.visible = not zone.is_empty()
	_zone_caption.text = tr("fish.card.zone")
	_zone_value.text = zone


func _show_unknown() -> void:
	_common.text = tr("fish.card.unknown_species")
	_latin.visible = false
	_description.visible = false
	_length_row.visible = false
	_zone_row.visible = false


## Whole values without decimals, else one decimal; the separator follows the game language.
func _length_text(cm: float) -> String:
	if not is_finite(cm) or cm <= 0.0:
		return tr("number.unknown")
	var rounded: float = roundf(cm * 10.0) / 10.0
	var decimals: int = 0 if is_equal_approx(rounded, floorf(rounded)) else 1
	return tr("unit.cm") % Localization.local_format().format_number(cm, decimals)


## The zone text, empty for an unset zone (the row is then hidden).
func _zone_text(zone: FishSpecies.Zone) -> String:
	match zone:
		FishSpecies.Zone.TOP:
			return tr("fish.zone.top")
		FishSpecies.Zone.MIDDLE:
			return tr("fish.zone.middle")
		FishSpecies.Zone.BOTTOM:
			return tr("fish.zone.bottom")
	return ""
