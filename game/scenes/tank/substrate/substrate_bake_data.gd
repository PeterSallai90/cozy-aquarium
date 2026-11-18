class_name SubstrateBakeData
extends RefCounted
## The committed baked stone data of one data set (game/assets/substrate/bake/*.bin, written by
## tools/blender/bake_substrate.py; ADR 0011 rule 8). Read with FileAccess only, so a worker
## thread may read it; never changed after load_file, so two assemblies may read it at once.
##
## File: 4 bytes "CASB", u32 format version, u32 byte length of a UTF-8 JSON header, the header,
## then records of 9 float32: x, y, z, qx, qy, qz, qw, drawn size, packed integer (bits 0 to 3
## variant, bit 4 visible from above, bit 5 visible through a pane, bit 6 kept behind, bits 7 to
## 10 exposure). Set-local Godot frame, metres.

const MAGIC: String = "CASB"
const FORMAT_VERSION: int = 1
const FLOATS: int = 9
const PREAMBLE_BYTES: int = 12
const RECORD_BYTES: int = 36
const VARIANT_MASK: int = 15
const FLAG_ABOVE: int = 16
const FLAG_PANE: int = 32
const FLAG_BEHIND: int = 64
const EXPOSURE_SHIFT: int = 7
const EXPOSURE_MASK: int = 15
const MODE_TANK: String = "tank"
const MODE_TILES: String = "tiles"

var header: Dictionary = {}
## All records, 9 floats each.
var stones: PackedFloat32Array = PackedFloat32Array()
## Half extents of the LOD0 mesh of every variant at unit size.
var half_extents: PackedVector3Array = PackedVector3Array()
## Ellipsoid semi-axes of every variant at unit size (the drawn sand grain).
var axes: PackedVector3Array = PackedVector3Array()


## The data of a file, or null with one push_error when the file is missing, is no CASB file, has
## another format version or was baked for another packing version.
static func load_file(path: String) -> SubstrateBakeData:
	if not FileAccess.file_exists(path):
		push_error("SubstrateBakeData: missing file %s" % path)
		return null
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var why: String = _problem(bytes)
	if not why.is_empty():
		push_error("SubstrateBakeData: %s: %s" % [path, why])
		return null
	var header_length: int = bytes.decode_u32(8)
	var parsed: Variant = JSON.parse_string(
		bytes.slice(PREAMBLE_BYTES, PREAMBLE_BYTES + header_length).get_string_from_utf8()
	)
	var data: SubstrateBakeData = SubstrateBakeData.new()
	data.header = parsed
	data.stones = bytes.slice(PREAMBLE_BYTES + header_length).to_float32_array()
	data.half_extents = _vectors(data.header.get("half_extents", []) as Array)
	data.axes = _vectors(data.header.get("axes", []) as Array)
	return data


static func _problem(bytes: PackedByteArray) -> String:
	if bytes.size() < PREAMBLE_BYTES:
		return "shorter than the preamble"
	if bytes.slice(0, 4).get_string_from_ascii() != MAGIC:
		return "the magic is not %s" % MAGIC
	if bytes.decode_u32(4) != FORMAT_VERSION:
		return "format version %d, this reader knows %d" % [bytes.decode_u32(4), FORMAT_VERSION]
	var header_length: int = bytes.decode_u32(8)
	var records: int = bytes.size() - PREAMBLE_BYTES - header_length
	if records < 0 or records % RECORD_BYTES != 0:
		return "the header length or the record block is broken"
	var parsed: Variant = JSON.parse_string(
		bytes.slice(PREAMBLE_BYTES, PREAMBLE_BYTES + header_length).get_string_from_utf8()
	)
	if not parsed is Dictionary:
		return "the header is not a JSON object"
	var version: int = int((parsed as Dictionary).get("packing_version", -1))
	if version != SubstrateAssembler.PACKING_VERSION:
		return (
			"baked for packing version %d, the assembler has %d"
			% [version, SubstrateAssembler.PACKING_VERSION]
		)
	return ""


static func _vectors(rows: Array) -> PackedVector3Array:
	var result: PackedVector3Array = PackedVector3Array()
	for row: Variant in rows:
		var values: Array = row
		result.append(Vector3(values[0], values[1], values[2]))
	return result


func mode() -> String:
	return str(header.get("mode", ""))


## The depth the data was poured to, in metres.
func depth_m() -> float:
	return float(header.get("fill_depth", 0.0))


func median_size() -> float:
	return float(header.get("median_size_m", 0.0))


func largest_size() -> float:
	return float(header.get("largest_size_m", 0.0))


func variant_count() -> int:
	return half_extents.size()


func record_count() -> int:
	# stones.size() / FLOATS: float count to record count; stones holds whole records,
	# so there is no remainder.
	@warning_ignore("integer_division")
	return stones.size() / FLOATS


func set_names() -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	var table: Dictionary = header.get("sets", {})
	for set_name: String in table:
		names.append(set_name)
	return names


func has_set(set_name: String) -> bool:
	return (header.get("sets", {}) as Dictionary).has(set_name)


## First record and record count of a named set (both 0 when the set is missing).
func set_range(set_name: String) -> Vector2i:
	var table: Dictionary = header.get("sets", {})
	if not table.has(set_name):
		return Vector2i.ZERO
	var entry: Dictionary = table[set_name]
	return Vector2i(int(entry["offset"]), int(entry["count"]))


## A copy of the records of one named set (9 floats per stone); empty when the set is missing.
func get_set(set_name: String) -> PackedFloat32Array:
	var span: Vector2i = set_range(set_name)
	return stones.slice(span.x * FLOATS, (span.x + span.y) * FLOATS)


## A number of the "ring" or "top" block of a tile header.
func tile_value(block: String, key: String, fallback: float = 0.0) -> float:
	var table: Dictionary = header.get(block, {})
	return float(table.get(key, fallback))
