extends Node3D
## Dev-only route to the fish (#34): the real room with a tank, a substrate and a few fish of each
## species, drawn by the room's FishView. Not referenced by any game scene and not in the menu;
## #36 owns the player-facing way to add fish.
##
## The model is made the way a loaded save is: a save text is decoded with SaveCodec and the
## result is copied into a model with reset_from, so nothing here writes the model directly.
## Change the exported values in the editor, or use the Remote tree, to look at other tanks and
## beds. The room's camera, lamp and water are the ones of the game.

const ROOM_SCENE: String = "res://scenes/room/room_corner.tscn"
const STAMP: String = "2026-11-01T12:00:00Z"
const UID_BASE: int = 0xF1000000

@export var tank_id: String = "tank_medium_1"
@export var substrate_id: String = "sand_fine"
## Fish per species, in catalog order: neon tetra, angelfish, bronze corydoras. The variants are
## used in turn, so every shipped variant shows when there are enough fish.
@export var neon_tetra_count: int = 6
@export var angelfish_count: int = 2
@export var bronze_corydoras_count: int = 4

var _model: AquariumModel = null


func _ready() -> void:
	var tanks: TankCatalog = TankCatalog.load_dir()
	var species: FishCatalog = FishCatalog.load_dir()
	_model = _build_model(species)
	var room: Node3D = (load(ROOM_SCENE) as PackedScene).instantiate() as Node3D
	room.call("setup", _model, tanks)
	add_child(room)


func _build_model(species: FishCatalog) -> AquariumModel:
	var model: AquariumModel = AquariumModel.new(STAMP)
	var result: SaveResult = SaveCodec.new().decode(_save_text(species), STAMP)
	if not result.is_ok():
		push_error("fish preview: the generated save is refused: %s" % result.detail)
		return model
	var decoded: AquariumModel = result.model
	model.reset_from(decoded)
	return model


## The save text of the staged aquarium: the tank, the bed with its default colour and the fish.
func _save_text(species: FishCatalog) -> String:
	var bed: SubstrateDefinition = SubstrateCatalog.load_dir().resolve(StringName(substrate_id))
	var fish: Array[Dictionary] = []
	var counts: Dictionary[StringName, int] = {
		&"neon_tetra": neon_tetra_count,
		&"angelfish": angelfish_count,
		&"bronze_corydoras": bronze_corydoras_count,
	}
	for id: String in species.get_ids():
		var variants: int = species.get_definition(StringName(id)).colour_variants.size()
		for index: int in maxi(0, counts.get(StringName(id), 0)):
			(
				fish
				. append(
					{
						"uid": "%08x" % (UID_BASE + fish.size() + 1),
						"species_id": id,
						"variant": index % maxi(1, variants),
						"nickname": "",
					}
				)
			)
	var data: Dictionary = {
		"format_version": SaveCodec.FORMAT_VERSION,
		"name": "Fish preview",
		"tank_id": tank_id,
		"substrate":
		{
			"id": substrate_id,
			"colour": "#" + (bed.default_colour.to_html(false) if bed != null else "ffffff"),
			"heightmap": {"size": [0, 0], "data": ""},
		},
		"items": [],
		"fish": fish,
		"created": STAMP,
		"modified": STAMP,
	}
	return JSON.stringify(data)
