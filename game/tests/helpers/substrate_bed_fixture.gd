extends RefCounted
## Assembles each (tank, type) bed once per test run and keeps the result for every suite of #28
## (technical plan v3, section 3.3: static cache). Also reads the grain meshes of a look once.
## Everything here is late-bound through substrate_bed_api.gd, so a missing production class
## gives a readable problem text and not a parse error.

const Api := preload("res://tests/helpers/substrate_bed_api.gd")
const Geo := preload("res://tests/helpers/substrate_geometry.gd")
const Glb := preload("res://tests/helpers/glb_mesh_checks.gd")
const Checks := preload("res://tests/helpers/proof_fish_checks.gd")
const Table := preload("res://tests/helpers/tank_table.gd")

const NODE_PATTERN := "^(?<class>[a-z0-9]+)_v(?<variant>\\d+)_lod(?<lod>\\d+)$"

static var _beds: Dictionary = {}
static var _bakes: Dictionary = {}
static var _analyses: Dictionary = {}
static var _grains: Dictionary = {}


static func key(tank_id: StringName, substrate_id: StringName) -> String:
	return "%s|%s" % [tank_id, substrate_id]


## "" when the bed of the pair can be assembled, else why it cannot (one readable text).
static func problem(tank_id: StringName, substrate_id: StringName) -> String:
	var missing: String = (
		Api
		. missing_script(
			[
				Api.BAKE_SCRIPT_PATH,
				Api.INPUT_PATH,
				Api.ASSEMBLER_PATH,
				Api.LOOK_SCRIPT_PATH,
				Api.BED_DATA_PATH,
				Api.CHUNK_DATA_PATH,
			]
		)
	)
	if not missing.is_empty():
		return missing
	var look: Resource = Api.look_of(substrate_id)
	if look == null:
		return "%s is missing" % Api.look_path(substrate_id)
	var path: String = Api.bake_path(look, tank_id)
	if path.is_empty() or not FileAccess.file_exists(path):
		return "baked data of %s in %s is missing: %s" % [substrate_id, tank_id, path]
	return ""


static func look_of(substrate_id: StringName) -> Resource:
	return Api.look_of(substrate_id)


## The baked data of the pair (cached), null when the file or the reader is missing.
static func bake_of(tank_id: StringName, substrate_id: StringName) -> RefCounted:
	var path: String = Api.bake_path(Api.look_of(substrate_id), tank_id)
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	if not _bakes.has(path):
		_bakes[path] = Api.load_bake(path)
	return _bakes[path]


## The assembled bed of the pair (cached), null while a piece is missing.
static func bed_of(tank_id: StringName, substrate_id: StringName) -> RefCounted:
	var wanted: String = key(tank_id, substrate_id)
	if _beds.has(wanted):
		return _beds[wanted]
	if not problem(tank_id, substrate_id).is_empty():
		return null
	var bake: RefCounted = bake_of(tank_id, substrate_id)
	var input: RefCounted = Api.create_input(tank_id, substrate_id, Api.look_of(substrate_id))
	var result: RefCounted = Api.assemble(input, bake)
	if result != null:
		_beds[wanted] = result
	return result


## What the look's grain glb holds: {"numbers": Array[int] sorted variant numbers, "triangles":
## Array (per variant a PackedInt32Array per LOD), "lod0": Array[PackedVector3Array], "extents":
## PackedFloat32Array of the LOD0 longest extent per variant, "axes": PackedInt32Array of its
## longest axis}. Empty arrays for sand (no glb).
static func grains_of(look: Resource) -> Dictionary:
	var empty: Dictionary = {
		"numbers": [],
		"triangles": [],
		"lod0": [] as Array[PackedVector3Array],
		"extents": PackedFloat32Array(),
		"axes": PackedInt32Array(),
	}
	if look == null:
		return empty
	var scene: PackedScene = look.get("grain_glb") as PackedScene
	if scene == null:
		return empty
	if _grains.has(scene.resource_path):
		return _grains[scene.resource_path]
	var root: Node3D = scene.instantiate() as Node3D
	var by_variant: Dictionary = {}
	var pattern: RegEx = RegEx.create_from_string(NODE_PATTERN)
	for instance: MeshInstance3D in Glb.mesh_instances(root):
		var found: RegExMatch = pattern.search(String(instance.name))
		if found == null:
			continue
		var number: int = int(found.get_string("variant"))
		var lod: int = int(found.get_string("lod"))
		var entry: Dictionary = by_variant.get(number, {})
		entry[lod] = {
			"triangles": Checks.triangle_count(instance.mesh),
			"vertices": Glb.vertices_in(instance, root),
		}
		by_variant[number] = entry
	var numbers: Array = by_variant.keys()
	numbers.sort()
	var triangles: Array = []
	var lod0: Array[PackedVector3Array] = []
	var extents: PackedFloat32Array = PackedFloat32Array()
	var axes: PackedInt32Array = PackedInt32Array()
	for number: int in numbers:
		var lods: Dictionary = by_variant[number]
		var counts: PackedInt32Array = PackedInt32Array()
		var lod_keys: Array = lods.keys()
		lod_keys.sort()
		for lod: int in lod_keys:
			counts.append(int(lods[lod]["triangles"]))
		triangles.append(counts)
		var base: PackedVector3Array = (
			lods[lod_keys[0]]["vertices"] if not lod_keys.is_empty() else PackedVector3Array()
		)
		lod0.append(base)
		extents.append(Geo.longest_extent(base))
		axes.append(Geo.longest_axis(base))
	root.free()
	var result: Dictionary = {
		"numbers": numbers,
		"triangles": triangles,
		"lod0": lod0,
		"extents": extents,
		"axes": axes,
	}
	_grains[scene.resource_path] = result
	return result


## The analysis of the bed of the pair (cached): see SubstrateGeometry.analyse. Empty while the bed
## cannot be assembled.
static func analysis_of(tank_id: StringName, substrate_id: StringName) -> Dictionary:
	var wanted: String = key(tank_id, substrate_id)
	if _analyses.has(wanted):
		return _analyses[wanted]
	var data: RefCounted = bed_of(tank_id, substrate_id)
	if data == null:
		return {}
	var grains: Dictionary = grains_of(Api.look_of(substrate_id))
	var lod0: Array[PackedVector3Array] = grains["lod0"]
	var result: Dictionary = Geo.analyse(
		Geo.entries_of(data),
		lod0,
		Table.interior(tank_id),
		data.get("core_centre"),
		data.get("core_size"),
		Api.is_sand(substrate_id)
	)
	_analyses[wanted] = result
	return result


## "" when `analysis_of` has a bed, else a failure text for one assert.
static func analysis_problem(tank_id: StringName, substrate_id: StringName) -> String:
	var why: String = problem(tank_id, substrate_id)
	if not why.is_empty():
		return why
	if bed_of(tank_id, substrate_id) == null:
		return "assemble returned null for %s in %s" % [substrate_id, tank_id]
	return ""
