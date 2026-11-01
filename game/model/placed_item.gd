class_name PlacedItem
extends RefCounted
## One decor, plant or rock instance placed in the tank. Plain record.
## Once inside an AquariumModel it is read-only by convention: change a copy and
## swap it in through a command.

## 8 lowercase hex chars, shared uid space with fish.
var uid: String = ""
var catalog_id: StringName = &""
## Metres, tank-local (+Y up, +X right from front, +Z toward front glass,
## origin = centre of the inner floor).
var position: Vector3 = Vector3.ZERO
## Degrees around +Y, stored as given (not normalised).
var rotation_y: float = 0.0
## Uniform scale, unitless.
var scale: float = 1.0
## False means "no colour".
var has_colour: bool = false
## Meaningful only when has_colour is true.
var colour: Color = Color.WHITE


## Returns a new instance with every field copied.
func copy() -> PlacedItem:
	var result := PlacedItem.new()
	result.uid = uid
	result.catalog_id = catalog_id
	result.position = position
	result.rotation_y = rotation_y
	result.scale = scale
	result.has_colour = has_colour
	result.colour = colour
	return result
