class_name FishInstance
extends RefCounted
## One individual fish in the tank. Plain record.
## Once inside an AquariumModel it is read-only by convention.

## 8 lowercase hex chars, shared uid space with placed items.
var uid: String = ""
var species_id: StringName = &""
## Index into the species colour_variants.
var variant: int = 0
## Any Unicode, any length, may be empty; stored unchanged.
var nickname: String = ""


## Returns a new instance with every field copied.
func copy() -> FishInstance:
	var result := FishInstance.new()
	result.uid = uid
	result.species_id = species_id
	result.variant = variant
	result.nickname = nickname
	return result
