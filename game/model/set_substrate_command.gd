class_name SetSubstrateCommand
extends Command
## Sets the substrate type and colour of the model in one undoable step. Literal: it does what it
## is told or refuses. The id must be in the catalog and the colour a swatch of that type; the
## chooser picks the colour (SubstrateCatalog.colour_for_pick) before it gets here. Never touches
## the tank, items, fish, heightmap or the save times.

var _model: AquariumModel = null
var _catalog: SubstrateCatalog = null
var _new_id: StringName = &""
var _new_colour: Color = Color.WHITE

var _old_id: StringName = &""
var _old_colour: Color = Color.WHITE


func _init(
	model: AquariumModel, catalog: SubstrateCatalog, substrate_id: StringName, colour: Color
) -> void:
	_model = model
	_catalog = catalog
	_new_id = substrate_id
	_new_colour = colour


func do() -> bool:
	if (
		_new_id == _model.get_substrate_id()
		and _new_colour.to_rgba32() == _model.get_substrate_colour().to_rgba32()
	):
		return false
	if _new_id == &"" or _catalog == null or _catalog.get_definition(_new_id) == null:
		push_error('SetSubstrateCommand: unknown substrate id "%s"' % _new_id)
		return false
	var index: int = _catalog.swatch_index(_new_id, _new_colour)
	if index < 0:
		push_error(
			(
				'SetSubstrateCommand: colour %s is not a swatch of "%s"'
				% [_new_colour.to_html(false), _new_id]
			)
		)
		return false
	_old_id = _model.get_substrate_id()
	_old_colour = _model.get_substrate_colour()
	var definition: SubstrateDefinition = _catalog.get_definition(_new_id)
	_model.apply_set_substrate(_new_id, definition.colour_swatches[index])
	return true


func undo() -> bool:
	_model.apply_set_substrate(_old_id, _old_colour)
	return true
