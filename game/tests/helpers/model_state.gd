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


## Like snapshot(), but every Color becomes [r8, g8, b8, a8] (alpha included). The save file stores
## hex colours, so colours compare at 8 bits per channel and everything else stays exact.
## The formula is repeated here on purpose: it must not call production code.
static func snapshot_8bit(model: AquariumModel) -> Dictionary:
	var result: Dictionary = snapshot(model)
	result["substrate_colour"] = _channels(model.get_substrate_colour())
	var items: Array = result["items"]
	for item: Dictionary in items:
		var colour: Color = item["colour"]
		item["colour"] = _channels(colour)
	return result


static func _channels(colour: Color) -> Array:
	return [_byte(colour.r), _byte(colour.g), _byte(colour.b), _byte(colour.a)]


static func _byte(component: float) -> int:
	return roundi(clampf(component, 0.0, 1.0) * 255.0)
