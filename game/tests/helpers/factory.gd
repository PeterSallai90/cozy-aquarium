extends RefCounted
## Builds model records for tests.


static func item(
	uid: String,
	catalog_id: StringName = &"rock_a",
	position: Vector3 = Vector3(0.1, 0.0, -0.05),
	rotation_y: float = 12.5,
	item_scale: float = 1.25
) -> PlacedItem:
	var result: PlacedItem = PlacedItem.new()
	result.uid = uid
	result.catalog_id = catalog_id
	result.position = position
	result.rotation_y = rotation_y
	result.scale = item_scale
	return result


static func coloured_item(uid: String, colour: Color) -> PlacedItem:
	var result: PlacedItem = item(uid)
	result.has_colour = true
	result.colour = colour
	return result


static func fish(
	uid: String, species_id: StringName = &"neon_tetra", variant: int = 0, nickname: String = ""
) -> FishInstance:
	var result: FishInstance = FishInstance.new()
	result.uid = uid
	result.species_id = species_id
	result.variant = variant
	result.nickname = nickname
	return result
