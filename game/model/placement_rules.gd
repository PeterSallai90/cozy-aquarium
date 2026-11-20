class_name PlacementRules
extends RefCounted
## The validity seam of placement (ADR 0012 rule 4): the one place that says whether an item may
## stand where a command or the ghost wants it. Pure data, no Node.
##
## #31 rule: every value is finite and the item centre lies inside the interior rectangle of the
## model's tank (the edge counts as inside). A change that keeps the position (a rotation only)
## skips the position check, so items of old saves outside the interior can still be turned.
## #33 replaces the body of allows() (footprint, overlap, water line) and the commands stay as
## they are.

var _tanks: TankCatalog = null


func _init(tanks: TankCatalog = null) -> void:
	_tanks = tanks


## True when the item may stand as `candidate` in the model. `before` is the item as it is now, or
## null for a placement.
func allows(model: AquariumModel, candidate: PlacedItem, before: PlacedItem) -> bool:
	if model == null or candidate == null:
		return false
	if not _all_finite(candidate):
		return false
	if before != null and _same_spot(before, candidate):
		return true
	if _tanks == null:
		return false
	var definition: TankDefinition = _tanks.get_definition(model.get_tank_id())
	if definition == null:
		return false
	return is_point_inside(definition.interior_size_m, candidate.position.x, candidate.position.z)


## True when (x, z), tank-local with the origin at the centre of the floor, lies inside the
## interior rectangle; the edges count as inside. NaN and infinity are never inside.
static func is_point_inside(interior_size_m: Vector3, x: float, z: float) -> bool:
	if not (is_finite(x) and is_finite(z)):
		return false
	return absf(x) <= interior_size_m.x / 2.0 and absf(z) <= interior_size_m.z / 2.0


static func _all_finite(item: PlacedItem) -> bool:
	return (
		is_finite(item.position.x)
		and is_finite(item.position.y)
		and is_finite(item.position.z)
		and is_finite(item.rotation_y)
		and is_finite(item.scale)
	)


static func _same_spot(a: PlacedItem, b: PlacedItem) -> bool:
	return a.position.x == b.position.x and a.position.z == b.position.z
