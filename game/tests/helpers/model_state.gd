extends RefCounted
## By-value snapshot of an AquariumModel for "exactly equal" checks.
##
## Test helper only. It is not the save serializer and must never move into game/model.


static func snapshot(model: AquariumModel) -> Dictionary:
	var items: Array = []
	for item: PlacedItem in model.get_items():
		(
			items
			. append(
				{
					"uid": item.uid,
					"catalog_id": item.catalog_id,
					"position": item.position,
					"rotation_y": item.rotation_y,
					"scale": item.scale,
					"has_colour": item.has_colour,
					"colour": item.colour,
				}
			)
		)
	var fish: Array = []
	for member: FishInstance in model.get_fish_list():
		(
			fish
			. append(
				{
					"uid": member.uid,
					"species_id": member.species_id,
					"variant": member.variant,
					"nickname": member.nickname,
				}
			)
		)
	return {
		"aquarium_name": model.get_aquarium_name(),
		"tank_id": model.get_tank_id(),
		"substrate_id": model.get_substrate_id(),
		"substrate_colour": model.get_substrate_colour(),
		"heightmap": model.get_heightmap(),
		"heightmap_size": model.get_heightmap_size(),
		"created": model.get_created(),
		"modified": model.get_modified(),
		"items": items,
		"fish": fish,
	}
