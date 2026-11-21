extends RefCounted
## Late-bound access to the #34 game classes (FishSpecies, FishCatalog, FishHash, FishExtents,
## FishZones, FishRestPose, FishView and SubstrateSurface.top_allowance).
##
## The tests were written before those classes exist. A direct reference to a missing class is a
## parse error, and GdUnit4 then aborts the whole run. Going through load() keeps every other
## suite running, and each test fails on its own with a readable message until the class exists.
## Every function returns a harmless stand-in (null, empty Dictionary, MISSING_NUMBER) when the
## script is missing.

const SPECIES_PATH := "res://catalog/fish_species.gd"
const CATALOG_PATH := "res://catalog/fish_catalog.gd"
const CATALOG_DIR := "res://catalog/fish"
const HASH_PATH := "res://model/fish_hash.gd"
const EXTENTS_PATH := "res://model/fish_extents.gd"
const ZONES_PATH := "res://model/fish_zones.gd"
const POSE_PATH := "res://model/fish_rest_pose.gd"
const SURFACE_PATH := "res://model/substrate_surface.gd"
const VIEW_PATH := "res://scenes/tank/fish/fish_view.gd"

const NEON: StringName = &"neon_tetra"
const ANGEL: StringName = &"angelfish"
const CORY: StringName = &"bronze_corydoras"
const IDS: Array[StringName] = [NEON, ANGEL, CORY]

## FishSpecies.Zone, Temperament and Light values as fixed by docs/architecture.md (UNSET = 0).
const ZONE_UNSET := 0
const ZONE_TOP := 1
const ZONE_MIDDLE := 2
const ZONE_BOTTOM := 3

## A value no assertion accepts (NAN would pass GdUnit4 float asserts).
const MISSING_NUMBER := -999.0

static var _shipped: RefCounted = null


static func script_of(path: String) -> GDScript:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as GDScript


static func has(path: String) -> bool:
	return ResourceLoader.exists(path)


## A constant of a script by name, or `fallback` when the script or the constant is missing.
static func constant(path: String, wanted: String, fallback: Variant) -> Variant:
	var script: GDScript = script_of(path)
	if script == null:
		return fallback
	return script.get_script_constant_map().get(wanted, fallback)


static func new_species() -> Resource:
	var script: GDScript = script_of(SPECIES_PATH)
	if script == null:
		return null
	return script.new() as Resource


## FishCatalog.load_dir(path); null while the class is missing.
static func catalog_load_dir(path: String = CATALOG_DIR) -> RefCounted:
	var script: GDScript = script_of(CATALOG_PATH)
	if script == null:
		return null
	return script.call("load_dir", path) as RefCounted


## FishCatalog.from_definitions(definitions); null while a class is missing.
static func catalog_from(definitions: Array) -> RefCounted:
	var script: GDScript = script_of(CATALOG_PATH)
	var species_script: GDScript = script_of(SPECIES_PATH)
	if script == null or species_script == null:
		return null
	var typed: Array = Array(definitions, TYPE_OBJECT, &"Resource", species_script)
	return script.call("from_definitions", typed) as RefCounted


## The shipped catalog, loaded once; null while the class is missing.
static func shipped() -> RefCounted:
	if _shipped == null:
		_shipped = catalog_load_dir()
	return _shipped


## The shipped definition of a species, or null.
static func species(id: StringName) -> Resource:
	var catalog: RefCounted = shipped()
	if catalog == null:
		return null
	return catalog.call("get_definition", id) as Resource


## A field of a shipped species, or `fallback` when the species is missing.
static func field(id: StringName, wanted: String, fallback: Variant) -> Variant:
	var definition: Resource = species(id)
	if definition == null:
		return fallback
	var value: Variant = definition.get(wanted)
	return fallback if value == null else value


## A copy of a shipped species with the given fields changed; null when the species is missing.
static func variant_of(id: StringName, changes: Dictionary) -> Resource:
	var source: Resource = species(id)
	if source == null:
		return null
	var copy: Resource = source.duplicate() as Resource
	for key: Variant in changes:
		copy.set(str(key), changes[key])
	return copy


static func hash_unit(uid: String, salt: String) -> float:
	var script: GDScript = script_of(HASH_PATH)
	if script == null:
		return MISSING_NUMBER
	return script.call("unit", uid, salt)


## A FishExtents with the three values set; null while the class is missing.
static func extents(radius_m: float, below_m: float, above_m: float) -> Object:
	var script: GDScript = script_of(EXTENTS_PATH)
	if script == null:
		return null
	var result: Object = script.new() as Object
	result.set("horizontal_radius_m", radius_m)
	result.set("below_m", below_m)
	result.set("above_m", above_m)
	return result


## FishZones.origin_range as {"min_y", "max_y", "pinned"}; empty while the class is missing.
static func origin_range(
	zone: int,
	surface_at: Callable,
	x: float,
	z: float,
	water_line_m: float,
	grain_allowance_m: float,
	fish_extents: Object
) -> Dictionary:
	var script: GDScript = script_of(ZONES_PATH)
	if script == null or fish_extents == null:
		return {}
	var result: Object = (
		script.call(
			"origin_range", zone, surface_at, x, z, water_line_m, grain_allowance_m, fish_extents
		)
		as Object
	)
	if result == null:
		return {}
	return {
		"min_y": result.get("min_y"),
		"max_y": result.get("max_y"),
		"pinned": result.get("pinned"),
	}


## FishZones.surface_source(...); an invalid Callable while the class is missing.
static func surface_source(
	definition: SubstrateDefinition,
	heightmap: PackedFloat32Array,
	heightmap_size: Vector2i,
	interior_size_m: Vector3
) -> Callable:
	var script: GDScript = script_of(ZONES_PATH)
	if script == null:
		return Callable()
	return script.call("surface_source", definition, heightmap, heightmap_size, interior_size_m)


## FishRestPose.compute as {"position", "yaw", "pinned"}; empty while the class is missing.
static func rest_pose(
	uid: String,
	zone: int,
	fish_extents: Object,
	interior_size_m: Vector3,
	water_line_m: float,
	surface_at: Callable,
	grain_allowance_m: float
) -> Dictionary:
	var script: GDScript = script_of(POSE_PATH)
	if script == null or fish_extents == null:
		return {}
	var result: Object = (
		script.call(
			"compute",
			uid,
			zone,
			fish_extents,
			interior_size_m,
			water_line_m,
			surface_at,
			grain_allowance_m
		)
		as Object
	)
	if result == null:
		return {}
	return {
		"position": result.get("position"),
		"yaw": result.get("yaw"),
		"pinned": result.get("pinned"),
	}


## SubstrateSurface.top_allowance(definition); MISSING_NUMBER while the function is missing.
static func top_allowance(definition: SubstrateDefinition) -> float:
	var script: GDScript = script_of(SURFACE_PATH)
	if script == null:
		return MISSING_NUMBER
	var has_function: bool = false
	for entry: Dictionary in script.get_script_method_list():
		if entry["name"] == &"top_allowance":
			has_function = true
	if not has_function:
		return MISSING_NUMBER
	return script.call("top_allowance", definition)


## The 32-bit FNV-1a hash, written out here so the tests do not depend on FishHash.
static func fnv1a32(text: String) -> int:
	var hash_value: int = 2166136261
	for byte: int in text.to_utf8_buffer():
		hash_value = ((hash_value ^ byte) * 16777619) & 0xFFFFFFFF
	return hash_value


## The expected FishHash.unit(uid, salt): fnv1a32(salt + ":" + uid) / 2^32.
static func expected_unit(uid: String, salt: String) -> float:
	return float(fnv1a32(salt + ":" + uid)) / 4294967296.0
