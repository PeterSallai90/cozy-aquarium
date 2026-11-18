extends RefCounted
## Late-bound access to the classes of the real 3D substrate bed of #28 (technical plan v3).
##
## The tests were written before those classes exist. A direct reference to a missing class_name
## is a parse error that aborts the whole run, so every class is reached through load() and call().
## Each function returns null (or a harmless stand-in) when the script or the file is missing; the
## caller asserts with a readable message and the rest of the suites keep running.
##
## Contract of the technical plan (Technical plan v3 and its F = 3 amendment on #28):
## - SubstrateBakeData.load_file(path), header, stones (9 floats per record), median_size(),
##   largest_size(), set_names(), get_set(name), half_extents, axes.
## - SubstrateBedLook (resource): bake_path_for(tank_id), grain_glb, lod_distances_m,
##   sand_range_begin_m, sand_range_end_m, tone_* and the four materials.
## - SubstrateAssemblyInput.create(tank_id, substrate_id, interior_size_m, fill_depth_m, look).
## - SubstrateAssembler.assemble(input, bake, cancel) -> SubstrateBedData, seed_for(...).
## - SubstrateBedData (chunks, top_tiles, top_placements, core_size, core_centre) and
##   SubstrateChunkData (key, aabb, buffers per variant with 16 floats per instance, counts).
## - SubstrateBedView, SubstrateBed, SubstrateAssemblyJob, SubstrateCancelToken, SubstrateLod.
## Conventions the helpers rely on (not spelled out by the plan, flagged in the test report):
## - Instance buffers and the core are in tank-local metres (x and z centred, floor at y = 0, front
##   glass at +z). The 12 transform floats are the MultiMesh layout (basis rows with the origin as
##   the fourth column); the last 4 are the custom data (lightness factor, hue shift in turns,
##   saturation plus 4 x exposure, random).
## - A mesh stone has the glb variant mesh (longest extent 1.0) scaled by its basis. A sand grain is
##   a unit sphere (radius 1) transformed by its basis, so the columns are the semi-axes and the
##   drawn size is twice the longest column.
## - top_placements holds 5 floats per tile cell: x, z, quarter turns, mirror, tile index.

const Table := preload("res://tests/helpers/tank_table.gd")

const DIR := "res://scenes/tank/substrate/"
const BED_PATH := DIR + "substrate_bed.gd"
const VIEW_PATH := DIR + "substrate_bed_view.gd"
const LOOK_SCRIPT_PATH := DIR + "substrate_bed_look.gd"
const BAKE_SCRIPT_PATH := DIR + "substrate_bake_data.gd"
const INPUT_PATH := DIR + "substrate_assembly_input.gd"
const TOKEN_PATH := DIR + "substrate_cancel_token.gd"
const ASSEMBLER_PATH := DIR + "substrate_assembler.gd"
const LOD_PATH := DIR + "substrate_lod.gd"
const JOB_PATH := DIR + "substrate_assembly_job.gd"
const CACHE_PATH := DIR + "substrate_bed_cache.gd"
const BED_DATA_PATH := DIR + "substrate_bed_data.gd"
const CHUNK_DATA_PATH := DIR + "substrate_chunk_data.gd"
const SURFACE_PATH := "res://model/substrate_surface.gd"
const LOOK_DIR := "res://assets/substrate/looks"
const BAKE_DIR := "res://assets/substrate/bake"
const GLB_DIR := "res://assets/substrate"
const SHADER_DIR := "res://shaders"

## Fill depth of every type in metres (AC 1), not read from the catalog so the suites run before
## the catalog has the field.
const FILL_DEPTH_M: Dictionary = {
	"sand_fine": 0.03,
	"gravel_natural": 0.04,
	"pebbles_river": 0.06,
	"sand_black": 0.03,
	"gravel_coloured": 0.04,
}
## Types drawn as ray-cast sand grains (grain shape SAND).
const SAND_IDS: Array[StringName] = [&"sand_fine", &"sand_black"]
## Types that are poured from settled tiles (everything but the whole-tank pebble bake).
const TILE_IDS: Array[StringName] = [
	&"sand_fine", &"sand_black", &"gravel_natural", &"gravel_coloured"
]
const PEBBLES: StringName = &"pebbles_river"
## The decided grain shape numbers (AC 1, technical plan 1.5).
const SHAPE_BY_ID: Dictionary = {
	"sand_fine": 0,
	"sand_black": 0,
	"gravel_natural": 1,
	"gravel_coloured": 2,
	"pebbles_river": 3,
}
const BAKE_FILE_BY_ID: Dictionary = {
	"sand_fine": "sand.bin",
	"sand_black": "sand.bin",
	"gravel_natural": "gravel_natural.bin",
	"gravel_coloured": "gravel_coloured.bin",
}
const MISSING_NUMBER: float = -999.0


static func _script(path: String) -> GDScript:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as GDScript


static func script_exists(path: String) -> bool:
	return _script(path) != null


## "" when every script exists, else the first missing path (for one readable failure).
static func missing_script(paths: Array[String]) -> String:
	for path: String in paths:
		if not script_exists(path):
			return "%s is missing" % path
	return ""


static func constant(path: String, wanted: String, fallback: Variant) -> Variant:
	var script: GDScript = _script(path)
	if script == null:
		return fallback
	return script.get_script_constant_map().get(wanted, fallback)


## The parameter names of a method of a script ([] when the script or method is missing).
static func method_arg_names(path: String, method_name: String) -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	var script: GDScript = _script(path)
	if script == null:
		return names
	for method: Dictionary in script.get_script_method_list():
		if method["name"] == method_name:
			var args: Array = method["args"]
			for arg: Dictionary in args:
				names.append(String(arg["name"]))
	return names


static func has_static_method(path: String, method_name: String) -> bool:
	var script: GDScript = _script(path)
	if script == null:
		return false
	for method: Dictionary in script.get_script_method_list():
		if method["name"] == method_name:
			return true
	return false


## The global class name of an object's script ("" when it has none).
static func class_of(object: Object) -> String:
	if object == null:
		return ""
	var script: Script = object.get_script() as Script
	if script == null:
		return ""
	return String(script.get_global_name())


# --- looks, bake data, input, assembler ---


static func fill_depth(substrate_id: StringName) -> float:
	return FILL_DEPTH_M.get(String(substrate_id), MISSING_NUMBER)


static func is_sand(substrate_id: StringName) -> bool:
	return SAND_IDS.has(substrate_id)


static func look_path(substrate_id: StringName) -> String:
	return "%s/%s.tres" % [LOOK_DIR, substrate_id]


static func look_of(substrate_id: StringName) -> Resource:
	var path: String = look_path(substrate_id)
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Resource


static func bake_path(look: Resource, tank_id: StringName) -> String:
	if look == null or not look.has_method("bake_path_for"):
		return ""
	return String(look.call("bake_path_for", tank_id))


static func load_bake(path: String) -> RefCounted:
	var script: GDScript = _script(BAKE_SCRIPT_PATH)
	if script == null or path.is_empty():
		return null
	return script.call("load_file", path) as RefCounted


static func create_input(
	tank_id: StringName, substrate_id: StringName, look: Resource, fill_depth_m: float = -1.0
) -> RefCounted:
	var script: GDScript = _script(INPUT_PATH)
	if script == null or look == null:
		return null
	var depth: float = fill_depth(substrate_id) if fill_depth_m < 0.0 else fill_depth_m
	return script.call("create", tank_id, substrate_id, Table.interior(tank_id), depth, look)


static func new_token() -> RefCounted:
	var script: GDScript = _script(TOKEN_PATH)
	if script == null:
		return null
	return script.new() as RefCounted


## The assembler script, loaded on the calling thread so a worker lambda can call it without load().
static func assembler_script() -> GDScript:
	return _script(ASSEMBLER_PATH)


static func assemble(input: RefCounted, bake: RefCounted, token: RefCounted = null) -> RefCounted:
	var script: GDScript = _script(ASSEMBLER_PATH)
	if script == null or input == null or bake == null:
		return null
	return script.call("assemble", input, bake, token) as RefCounted


static func seed_for(tank_id: StringName, substrate_id: StringName, version: int = -1) -> int:
	var script: GDScript = _script(ASSEMBLER_PATH)
	if script == null:
		return -1
	if version < 0:
		return int(script.call("seed_for", tank_id, substrate_id))
	return int(script.call("seed_for", tank_id, substrate_id, version))


static func packing_version() -> int:
	return int(constant(ASSEMBLER_PATH, "PACKING_VERSION", -1))


# --- plain data helpers ---


## 32-bit FNV-1a over the UTF-8 bytes of the text; the hash of technical plan 1.6.
static func fnv1a_32(text: String) -> int:
	var hash_value: int = 2166136261
	for byte: int in text.to_utf8_buffer():
		hash_value = ((hash_value ^ byte) * 16777619) & 0xFFFFFFFF
	return hash_value


## The wanted key or its first alias in a header dictionary, searched at the top level and one level
## down. Returns null when no alias is there.
static func header_value(header: Dictionary, aliases: Array[String]) -> Variant:
	for alias: String in aliases:
		if header.has(alias):
			return header[alias]
	for key: Variant in header:
		var inner: Variant = header[key]
		if inner is Dictionary:
			for alias: String in aliases:
				if (inner as Dictionary).has(alias):
					return (inner as Dictionary)[alias]
	return null


## A value of a key at any depth of nested dictionaries and arrays, or null.
static func find_deep(value: Variant, wanted: String) -> Variant:
	if value is Dictionary:
		var dict: Dictionary = value
		if dict.has(wanted):
			return dict[wanted]
		for key: Variant in dict:
			var found: Variant = find_deep(dict[key], wanted)
			if found != null:
				return found
	elif value is Array:
		for entry: Variant in value:
			var found_in_array: Variant = find_deep(entry, wanted)
			if found_in_array != null:
				return found_in_array
	return null


## True when two assembled beds hold the same buffers, placements and core, value by value.
static func beds_equal(a: RefCounted, b: RefCounted) -> bool:
	if a == null or b == null:
		return false
	var chunks_a: Array = a.get("chunks")
	var chunks_b: Array = b.get("chunks")
	if chunks_a.size() != chunks_b.size():
		return false
	for i: int in chunks_a.size():
		var chunk_a: RefCounted = chunks_a[i]
		var chunk_b: RefCounted = chunks_b[i]
		if chunk_a.get("key") != chunk_b.get("key") or chunk_a.get("aabb") != chunk_b.get("aabb"):
			return false
		if chunk_a.get("counts") != chunk_b.get("counts"):
			return false
		var buffers_a: Array = chunk_a.get("buffers")
		var buffers_b: Array = chunk_b.get("buffers")
		if buffers_a.size() != buffers_b.size():
			return false
		for v: int in buffers_a.size():
			if (buffers_a[v] as PackedFloat32Array) != (buffers_b[v] as PackedFloat32Array):
				return false
	var tiles_a: Array = a.get("top_tiles")
	var tiles_b: Array = b.get("top_tiles")
	if tiles_a.size() != tiles_b.size():
		return false
	for t: int in tiles_a.size():
		if (tiles_a[t] as PackedFloat32Array) != (tiles_b[t] as PackedFloat32Array):
			return false
	return (
		(
			(a.get("top_placements") as PackedFloat32Array)
			== (b.get("top_placements") as PackedFloat32Array)
		)
		and a.get("core_size") == b.get("core_size")
		and a.get("core_centre") == b.get("core_centre")
	)


## The number of instances over the chunk buffers of a bed (tile buffers not included).
static func chunk_instance_count(bed: RefCounted) -> int:
	var total: int = 0
	var chunks: Array = bed.get("chunks")
	for chunk: RefCounted in chunks:
		var buffers: Array = chunk.get("buffers")
		for buffer: PackedFloat32Array in buffers:
			# buffer.size() / 16: 16 floats per instance in a multimesh buffer, so a whole instance count.
			@warning_ignore("integer_division")
			total += buffer.size() / 16
	return total
