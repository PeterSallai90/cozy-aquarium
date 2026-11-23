class_name AddFishCommand
extends Command
## Adds one complete FishInstance (uid included, fixed by the caller) at the end of the fish list.
## Redo re-inserts it at the index of the first do(); undo removes it. Refuses a null fish, an
## empty or used uid, with the model untouched and no signal.

var _model: AquariumModel = null
var _fish: FishInstance = null
var _index: int = -1


func _init(model: AquariumModel, fish: FishInstance) -> void:
	_model = model
	_fish = fish


## A new fish of the species: nickname empty (the shown name is derived), variant 0 when the
## species has no colour variants, else a random index of them. Reads only the id and the
## number of colour variants.
static func make_fish(
	uid: String, species: FishSpecies, rng: RandomNumberGenerator
) -> FishInstance:
	var fish: FishInstance = FishInstance.new()
	fish.uid = uid
	fish.species_id = species.id
	var variants: int = species.colour_variants.size()
	fish.variant = 0 if variants == 0 else rng.randi_range(0, variants - 1)
	fish.nickname = ""
	return fish


func do() -> bool:
	if _model == null or _fish == null or _fish.uid.is_empty() or _model.has_uid(_fish.uid):
		return false
	var at: int = _index
	if at < 0 or at > _model.get_fish_count():
		at = _model.get_fish_count()
	if not _model.apply_insert_fish(_fish, at):
		return false
	_index = at
	return true


func undo() -> bool:
	return _model.apply_remove_fish(_fish.uid)
