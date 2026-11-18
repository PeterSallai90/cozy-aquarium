class_name SubstrateSetup
extends RefCounted
## Model construction steps for the substrate (ADR 0010): the default of a new aquarium and the
## fallback for a loaded one. Neither is a player change, so neither goes through a Command and
## neither makes a history entry. The callers are the session start (main.gd) and the save store.


## A new aquarium gets the default type and its default colour.
static func apply_default(model: AquariumModel, catalog: SubstrateCatalog) -> void:
	var definition: SubstrateDefinition = catalog.get_default()
	if definition == null:
		push_error("SubstrateSetup: the catalog has no default substrate")
		return
	model.apply_set_substrate(definition.id, definition.default_colour)


## An empty or unknown id becomes the default type with its default colour, with one warning.
## A known id is left alone, whatever its colour. True when the model was changed.
static func normalise(model: AquariumModel, catalog: SubstrateCatalog) -> bool:
	var id: StringName = model.get_substrate_id()
	if id != &"" and catalog.get_definition(id) != null:
		return false
	var definition: SubstrateDefinition = catalog.get_default()
	if definition == null:
		push_error("SubstrateSetup: the catalog has no default substrate")
		return false
	push_warning('SubstrateSetup: unknown substrate id "%s"; using "%s"' % [id, definition.id])
	model.apply_set_substrate(definition.id, definition.default_colour)
	return true
