class_name PlacementRules
extends RefCounted
## The validity seam of placement (ADR 0012 rule 4 and Amendment 2 rules 12 to 14): the one place
## that says whether an item may stand where a command or the ghost wants it. Pure data, no Node.
##
## An item is a rectangle on the floor: footprint_cm x and z times scale, rotated by rotation_y
## around the item origin (the footprint centre). A candidate is valid when
## 1. its data can be placed (known definition, finite and positive size and scale, position.y 0),
## 2. every corner lies inside the interior of the model's tank,
## 3. its top (surface at the origin plus footprint_cm.y x scale) fits under the interior height,
##    and for rocks and ornaments also under the water line,
## 4. it overlaps no other item (separating axis test; touching is allowed).
## Every limit has the tolerance TOLERANCE_M. An item that is already invalid may still be turned
## in place to any finite angle (rule 5 of the amendment); loading never repairs an item.
## The rules keep no state between calls and read three catalogs that are injected.

## Touching is valid: a penetration or an excess of up to this many metres (0.1 mm) is ignored.
const TOLERANCE_M: float = 0.0001

var _tanks: TankCatalog = null
var _items: ItemCatalogSource = null
var _substrates: SubstrateCatalog = null


func _init(
	tanks: TankCatalog = null, items: ItemCatalogSource = null, substrates: SubstrateCatalog = null
) -> void:
	_tanks = tanks
	_items = items
	_substrates = substrates


## True when the item may stand as `candidate` in the model. `before` is the item as it is now, or
## null for a placement.
func allows(model: AquariumModel, candidate: PlacedItem, before: PlacedItem) -> bool:
	if model == null or candidate == null:
		return false
	if _tanks == null or _items == null or _substrates == null:
		return false
	var tank: TankDefinition = _tanks.get_definition(model.get_tank_id())
	var substrate: SubstrateDefinition = _substrates.resolve(model.get_substrate_id())
	if tank == null or substrate == null:
		return false
	var skip_uid: String = before.uid if before != null else ""
	if _passes(model, tank, substrate, candidate, skip_uid):
		return true
	# Rotation in place: an item that is already invalid may turn to any finite angle.
	if before != null and candidate.position == before.position and is_finite(candidate.rotation_y):
		return not _passes(model, tank, substrate, before, skip_uid)
	return false


## The height of the top of an item above the tank floor: the surface under its origin plus its
## height (footprint_cm.y) times the scale.
static func item_top(surface_m: float, footprint_cm: Vector3, item_scale: float) -> float:
	return surface_m + footprint_cm.y * item_scale / 100.0


## True when (x, z), tank-local with the origin at the centre of the floor, lies inside the
## interior rectangle; the edges count as inside. NaN and infinity are never inside.
static func is_point_inside(interior_size_m: Vector3, x: float, z: float) -> bool:
	if not (is_finite(x) and is_finite(z)):
		return false
	return absf(x) <= interior_size_m.x / 2.0 and absf(z) <= interior_size_m.z / 2.0


func _passes(
	model: AquariumModel,
	tank: TankDefinition,
	substrate: SubstrateDefinition,
	candidate: PlacedItem,
	skip_uid: String
) -> bool:
	var catalog: ItemCatalog = _items.get_catalog()
	var definition: ItemDefinition = catalog.get_definition(candidate.catalog_id)
	if not _usable(definition, candidate):
		return false
	if not (
		is_finite(candidate.position.x)
		and is_finite(candidate.position.y)
		and is_finite(candidate.position.z)
		and is_finite(candidate.rotation_y)
		and absf(candidate.position.y) <= TOLERANCE_M
	):
		return false
	if not _fits_tank(model, tank, substrate, candidate, definition):
		return false
	return _free_of_others(model, catalog, candidate, definition, skip_uid)


## Bounds and height of a candidate whose data is usable.
func _fits_tank(
	model: AquariumModel,
	tank: TankDefinition,
	substrate: SubstrateDefinition,
	candidate: PlacedItem,
	definition: ItemDefinition
) -> bool:
	var half_x: float = definition.footprint_cm.x * candidate.scale / 200.0
	var half_z: float = definition.footprint_cm.z * candidate.scale / 200.0
	var angle: float = deg_to_rad(candidate.rotation_y)
	# Bounds: the extent of the rotated rectangle on x and z.
	var reach_x: float = absf(half_x * cos(angle)) + absf(half_z * sin(angle))
	var reach_z: float = absf(half_x * sin(angle)) + absf(half_z * cos(angle))
	var interior: Vector3 = tank.interior_size_m
	if absf(candidate.position.x) + reach_x > interior.x / 2.0 + TOLERANCE_M:
		return false
	if absf(candidate.position.z) + reach_z > interior.z / 2.0 + TOLERANCE_M:
		return false
	var surface: float = SubstrateSurface.height_at(
		substrate,
		model.get_heightmap(),
		model.get_heightmap_size(),
		interior,
		candidate.position.x,
		candidate.position.z
	)
	var top: float = item_top(surface, definition.footprint_cm, candidate.scale)
	if top > interior.y + TOLERANCE_M:
		return false
	var under_water: bool = (
		definition.category == ItemDefinition.Category.ROCK
		or definition.category == ItemDefinition.Category.ORNAMENT
	)
	return not (under_water and top > tank.water_line_height_m + TOLERANCE_M)


## True when the candidate overlaps no other item of the model (the one with skip_uid excepted).
func _free_of_others(
	model: AquariumModel,
	catalog: ItemCatalog,
	candidate: PlacedItem,
	definition: ItemDefinition,
	skip_uid: String
) -> bool:
	var half_x: float = definition.footprint_cm.x * candidate.scale / 200.0
	var half_z: float = definition.footprint_cm.z * candidate.scale / 200.0
	var angle: float = deg_to_rad(candidate.rotation_y)
	var ux: float = cos(angle)
	var uz: float = -sin(angle)
	var vx: float = sin(angle)
	var vz: float = cos(angle)
	for other: PlacedItem in model.get_items():
		if other.uid == skip_uid:
			continue
		var other_definition: ItemDefinition = catalog.get_definition(other.catalog_id)
		if not _usable(other_definition, other):
			continue
		if not (
			is_finite(other.position.x)
			and is_finite(other.position.z)
			and is_finite(other.rotation_y)
		):
			continue
		if _overlaps(
			candidate.position.x,
			candidate.position.z,
			half_x,
			half_z,
			ux,
			uz,
			vx,
			vz,
			other,
			other_definition
		):
			return false
	return true


## True when the definition exists and the item has a size that can be placed.
static func _usable(definition: ItemDefinition, item: PlacedItem) -> bool:
	if definition == null:
		return false
	var size: Vector3 = definition.footprint_cm
	if not (is_finite(size.x) and is_finite(size.y) and is_finite(size.z)):
		return false
	if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
		return false
	return is_finite(item.scale) and item.scale > 0.0


## Separating axis test of the rectangle A (centre ax, az, half sizes, axes u and v) against the
## placed item `other`. Overlapping when the penetration exceeds the tolerance on all four axes.
static func _overlaps(
	ax: float,
	az: float,
	half_x: float,
	half_z: float,
	ux: float,
	uz: float,
	vx: float,
	vz: float,
	other: PlacedItem,
	other_definition: ItemDefinition
) -> bool:
	var other_half_x: float = other_definition.footprint_cm.x * other.scale / 200.0
	var other_half_z: float = other_definition.footprint_cm.z * other.scale / 200.0
	var other_angle: float = deg_to_rad(other.rotation_y)
	var oux: float = cos(other_angle)
	var ouz: float = -sin(other_angle)
	var ovx: float = sin(other_angle)
	var ovz: float = cos(other_angle)
	var dx: float = other.position.x - ax
	var dz: float = other.position.z - az
	# Axes: u and v of A, then u and v of the other.
	for axis: int in 4:
		var nx: float = ux
		var nz: float = uz
		match axis:
			1:
				nx = vx
				nz = vz
			2:
				nx = oux
				nz = ouz
			3:
				nx = ovx
				nz = ovz
		var radius_a: float = half_x * absf(ux * nx + uz * nz) + half_z * absf(vx * nx + vz * nz)
		var radius_b: float = (
			other_half_x * absf(oux * nx + ouz * nz) + other_half_z * absf(ovx * nx + ovz * nz)
		)
		var centre_gap: float = absf(dx * nx + dz * nz)
		# Both intervals centred on their own centre: the penetration along this axis.
		var penetration: float = radius_a + radius_b - centre_gap
		if penetration <= TOLERANCE_M:
			return false
	return true
