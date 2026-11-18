# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #28 criterion 42 (owner: technical-artist): the committed baked data of the substrate beds and
## the reader of it (technical plan v3, sections 3.1 and 6; ADR 0011 rule 8). Each data file has
## the magic CASB, format version 1, a JSON header and records of 9 float32 with at least one
## visibility flag; the bake report says all stones are at rest; each file is at most 1 MB and all
## together at most 3 MB; pebbles have one file per tank; the tile types come with their sets. The
## bake itself (minutes per type in Blender) is never run here.
##
## The records are read straight from the bytes, independent of the reader; the reader has its own
## tests below (valid file, missing file, wrong magic, wrong format version, wrong packing version).
## Header key names follow the plan's words; where the plan leaves a name open an alias list is
## accepted (see _header_value) and the failure names the aliases.

const Api := preload("res://tests/helpers/substrate_bed_api.gd")
const LfsGuard := preload("res://tests/helpers/lfs_guard.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")
const Table := preload("res://tests/helpers/tank_table.gd")

const MAGIC: PackedByteArray = [0x43, 0x41, 0x53, 0x42]
const FORMAT_VERSION := 1
const PREAMBLE_BYTES := 12
const RECORD_FLOATS := 9
const RECORD_BYTES := 36
const MAX_FILE_BYTES := 1024 * 1024
const MAX_TOTAL_BYTES := 3 * 1024 * 1024
const FLAG_BITS := 0x70
const KNOWN_BITS := 0x7FF
const SCRATCH := "user://substrate_bake_test/"

## File name, data set type, fill depth, mode, tank id ("" for tile data).
const FILES: Array[Dictionary] = [
	{"file": "sand.bin", "type": "sand_fine", "depth": 0.03, "mode": "tiles", "tank": ""},
	{
		"file": "gravel_natural.bin",
		"type": "gravel_natural",
		"depth": 0.04,
		"mode": "tiles",
		"tank": ""
	},
	{
		"file": "gravel_coloured.bin",
		"type": "gravel_coloured",
		"depth": 0.04,
		"mode": "tiles",
		"tank": ""
	},
	{
		"file": "pebbles_river_tank_small_1.bin",
		"type": "pebbles_river",
		"depth": 0.06,
		"mode": "tank",
		"tank": "tank_small_1"
	},
	{
		"file": "pebbles_river_tank_medium_1.bin",
		"type": "pebbles_river",
		"depth": 0.06,
		"mode": "tank",
		"tank": "tank_medium_1"
	},
	{
		"file": "pebbles_river_tank_large_1.bin",
		"type": "pebbles_river",
		"depth": 0.06,
		"mode": "tank",
		"tank": "tank_large_1"
	},
]
## Drawn size range in metres of the median and the largest stone per type (AC 29, 30).
const SIZE_RANGE_M: Dictionary = {
	"sand_fine": [0.001, 0.0025],
	"gravel_natural": [0.002, 0.006],
	"gravel_coloured": [0.003, 0.0065],
	"pebbles_river": [0.012, 0.032],
}


func after_test() -> void:
	var dir: DirAccess = DirAccess.open(SCRATCH)
	if dir != null:
		for file_name: String in dir.get_files():
			dir.remove(file_name)


func _path(entry: Dictionary) -> String:
	return "%s/%s" % [Api.BAKE_DIR, entry["file"]]


## The raw file: {"problem", "bytes", "version", "header_length", "header", "records"}.
func _parse(path: String) -> Dictionary:
	var result: Dictionary = {"problem": "", "bytes": PackedByteArray(), "header": {}, "records": 0}
	var problem: String = LfsGuard.problem(path, MAGIC)
	if not problem.is_empty():
		result["problem"] = problem
		return result
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	result["bytes"] = bytes
	if bytes.size() < PREAMBLE_BYTES:
		result["problem"] = "%s is shorter than the preamble" % path
		return result
	var header_length: int = bytes.decode_u32(8)
	result["version"] = bytes.decode_u32(4)
	result["header_length"] = header_length
	if PREAMBLE_BYTES + header_length > bytes.size():
		result["problem"] = "%s: the header length runs past the end of the file" % path
		return result
	var parsed: Variant = JSON.parse_string(
		bytes.slice(PREAMBLE_BYTES, PREAMBLE_BYTES + header_length).get_string_from_utf8()
	)
	if not parsed is Dictionary:
		result["problem"] = "%s: the header is not a JSON object" % path
		return result
	result["header"] = parsed
	var record_bytes: int = bytes.size() - PREAMBLE_BYTES - header_length
	# record_bytes / RECORD_BYTES: whole 36-byte records; the leftover bytes are reported as
	# record_remainder on the next line.
	@warning_ignore("integer_division")
	result["records"] = record_bytes / RECORD_BYTES
	result["record_remainder"] = record_bytes % RECORD_BYTES
	return result


## The parsed file, failing once with the problem text; an empty dictionary when it has one.
func _file(entry: Dictionary) -> Dictionary:
	var parsed: Dictionary = _parse(_path(entry))
	assert_str(String(parsed["problem"])).is_empty()
	return parsed if String(parsed["problem"]).is_empty() else {}


func _header_value(header: Dictionary, aliases: Array[String]) -> Variant:
	var found: Variant = Api.header_value(header, aliases)
	(
		assert_bool(found != null)
		. override_failure_message("the header has none of the keys %s" % [aliases])
		. is_true()
	)
	return found


# --- the files ---


func test_ac42_each_data_file_exists_and_is_the_real_binary_not_an_lfs_pointer() -> void:
	for entry: Dictionary in FILES:
		assert_str(LfsGuard.problem(_path(entry), MAGIC)).is_empty()


func test_ac42_pebbles_have_one_file_per_tank_and_the_other_types_one_file_each() -> void:
	var has_folder: bool = DirAccess.dir_exists_absolute(Api.BAKE_DIR)
	assert_bool(has_folder).override_failure_message("%s is missing" % Api.BAKE_DIR).is_true()
	if not has_folder:
		return
	var names: PackedStringArray = DirAccess.get_files_at(Api.BAKE_DIR)
	assert_int(names.size()).override_failure_message("files: %s" % names).is_equal(FILES.size())
	for tank_id: StringName in Table.IDS:
		assert_bool(names.has("pebbles_river_%s.bin" % tank_id)).is_true()


func test_ac42_the_format_version_is_1_and_the_reader_constant_says_so() -> void:
	assert_int(int(Api.constant(Api.BAKE_SCRIPT_PATH, "FORMAT_VERSION", -1))).is_equal(
		FORMAT_VERSION
	)
	for entry: Dictionary in FILES:
		var parsed: Dictionary = _file(entry)
		if not parsed.is_empty():
			(
				assert_int(int(parsed["version"]))
				. override_failure_message(String(entry["file"]))
				. is_equal(FORMAT_VERSION)
			)


func test_ac42_the_file_is_a_header_and_whole_records_of_9_float32() -> void:
	for entry: Dictionary in FILES:
		var parsed: Dictionary = _file(entry)
		if parsed.is_empty():
			continue
		(
			assert_int(int(parsed["records"]))
			. override_failure_message("%s has no records" % entry["file"])
			. is_greater(0)
		)
		(
			assert_int(int(parsed["record_remainder"]))
			. override_failure_message(
				"%s: bytes after the header are not a multiple of 36" % entry["file"]
			)
			. is_equal(0)
		)


func test_ac42_each_file_is_at_most_1_mb_and_all_together_at_most_3_mb() -> void:
	var total: int = 0
	for entry: Dictionary in FILES:
		var size: int = FileAccess.get_file_as_bytes(_path(entry)).size()
		total += size
		(
			assert_int(size)
			. override_failure_message("%s is %d bytes" % [entry["file"], size])
			. is_between(1, MAX_FILE_BYTES)
		)
	assert_int(total).override_failure_message("all files: %d bytes" % total).is_between(
		1, MAX_TOTAL_BYTES
	)


func test_ac42_the_header_records_the_bake_report_with_all_stones_at_rest() -> void:
	for entry: Dictionary in FILES:
		var parsed: Dictionary = _file(entry)
		if parsed.is_empty():
			continue
		var header: Dictionary = parsed["header"]
		var at_rest: Variant = Api.find_deep(header, "all_at_rest")
		(
			assert_bool(at_rest == true)
			. override_failure_message(
				(
					"%s: the settling report does not say all_at_rest: true (%s)"
					% [entry["file"], at_rest]
				)
			)
			. is_true()
		)


func test_ac42_the_header_records_blender_version_seed_commands_and_packing_version() -> void:
	for entry: Dictionary in FILES:
		var parsed: Dictionary = _file(entry)
		if parsed.is_empty():
			continue
		var header: Dictionary = parsed["header"]
		var blender: Variant = _header_value(header, ["blender_version"])
		assert_str(str(blender)).override_failure_message(String(entry["file"])).is_not_empty()
		var seed_value: Variant = _header_value(header, ["seed", "bake_seed"])
		assert_bool(seed_value is float or seed_value is int).is_true()
		var commands: Variant = _header_value(header, ["commands", "bake_commands"])
		assert_bool(not str(commands).is_empty() and str(commands) != "[]").is_true()
		var packing: Variant = _header_value(header, ["packing_version"])
		(
			assert_int(int(packing))
			. override_failure_message(
				(
					"%s: packing_version differs from SubstrateAssembler.PACKING_VERSION"
					% entry["file"]
				)
			)
			. is_equal(Api.packing_version())
		)


func test_ac42_the_header_names_the_mode_the_depth_the_size_classes_and_the_variant_shapes(
) -> void:
	for entry: Dictionary in FILES:
		var parsed: Dictionary = _file(entry)
		if parsed.is_empty():
			continue
		var header: Dictionary = parsed["header"]
		(
			assert_str(str(_header_value(header, ["mode"])))
			. override_failure_message(String(entry["file"]))
			. is_equal(String(entry["mode"]))
		)
		assert_float(float(_header_value(header, ["fill_depth_m", "fill_depth"]))).is_equal_approx(
			float(entry["depth"]), 1e-6
		)
		assert_bool(not str(_header_value(header, ["size_classes", "sizes"])).is_empty()).is_true()
		(
			assert_bool(
				Api.header_value(header, ["half_extents", "axes", "ellipsoid_axes"]) != null
			)
			. override_failure_message("%s: no variant half extents or axes" % entry["file"])
			. is_true()
		)
		if String(entry["mode"]) == "tank":
			assert_str(str(_header_value(header, ["tank_id", "tank"]))).is_equal(
				String(entry["tank"])
			)


func test_ac42_every_record_has_a_flag_a_unit_quaternion_and_a_drawn_size() -> void:
	for entry: Dictionary in FILES:
		var parsed: Dictionary = _file(entry)
		if parsed.is_empty():
			continue
		var bytes: PackedByteArray = parsed["bytes"]
		var start: int = PREAMBLE_BYTES + int(parsed["header_length"])
		var bad_flags: int = 0
		var bad_bits: int = 0
		var bad_quaternion: int = 0
		var bad_size: int = 0
		for record: int in int(parsed["records"]):
			var at: int = start + record * RECORD_BYTES
			var quaternion: Quaternion = Quaternion(
				bytes.decode_float(at + 12),
				bytes.decode_float(at + 16),
				bytes.decode_float(at + 20),
				bytes.decode_float(at + 24)
			)
			if absf(quaternion.length() - 1.0) > 1e-3:
				bad_quaternion += 1
			var size: float = bytes.decode_float(at + 28)
			if not (size > 0.0 and size < 0.05):
				bad_size += 1
			var packed: int = int(bytes.decode_float(at + 32))
			if (packed & FLAG_BITS) == 0:
				bad_flags += 1
			if (packed & ~KNOWN_BITS) != 0:
				bad_bits += 1
		var label: String = String(entry["file"])
		(
			assert_int(bad_flags)
			. override_failure_message("%s: records without a flag" % label)
			. is_equal(0)
		)
		(
			assert_int(bad_bits)
			. override_failure_message("%s: records with unknown bits" % label)
			. is_equal(0)
		)
		(
			assert_int(bad_quaternion)
			. override_failure_message("%s: non-unit quaternions" % label)
			. is_equal(0)
		)
		assert_int(bad_size).override_failure_message("%s: bad drawn sizes" % label).is_equal(0)


func test_ac42_the_tile_data_comes_with_its_tile_and_seam_stone_sets() -> void:
	for entry: Dictionary in FILES:
		if String(entry["mode"]) != "tiles":
			continue
		var parsed: Dictionary = _file(entry)
		if parsed.is_empty():
			continue
		var sets: Variant = _header_value(parsed["header"], ["sets", "set_table"])
		(
			assert_bool((sets is Dictionary or sets is Array) and not str(sets).is_empty())
			. override_failure_message("%s: no set table" % entry["file"])
			. is_true()
		)


func test_ac42_the_bake_files_are_tracked_by_git_lfs() -> void:
	var text: String = FileAccess.get_file_as_string("res://../.gitattributes")
	var found: bool = false
	for line: String in text.split("\n"):
		if line.begins_with("game/assets/substrate/bake/*.bin") and line.contains("filter=lfs"):
			found = true
	(
		assert_bool(found)
		. override_failure_message(
			".gitattributes has no LFS rule for game/assets/substrate/bake/*.bin"
		)
		. is_true()
	)


func test_ac42_every_export_preset_includes_the_bake_folder() -> void:
	var config: ConfigFile = ConfigFile.new()
	assert_int(config.load("res://export_presets.cfg")).is_equal(OK)
	var presets: int = 0
	for section: String in config.get_sections():
		if not section.begins_with("preset.") or section.ends_with(".options"):
			continue
		presets += 1
		var filter_text: String = config.get_value(section, "include_filter", "") as String
		for entry: Dictionary in FILES:
			(
				assert_bool(_matches(_path(entry), filter_text))
				. override_failure_message(
					(
						'%s include_filter "%s" does not match %s'
						% [section, filter_text, _path(entry)]
					)
				)
				. is_true()
			)
	assert_int(presets).is_equal(3)


## The Godot exporter rule: a filter matches the res:// path or the path without the prefix.
func _matches(path: String, filter_text: String) -> bool:
	var relative: String = path.trim_prefix("res://")
	for item: String in filter_text.split(","):
		var pattern: String = item.strip_edges()
		if not pattern.is_empty() and (relative.matchn(pattern) or path.matchn(pattern)):
			return true
	return false


# --- the reader ---


func _need_reader() -> bool:
	var found: bool = Api.script_exists(Api.BAKE_SCRIPT_PATH)
	assert_bool(found).override_failure_message("%s is missing" % Api.BAKE_SCRIPT_PATH).is_true()
	return found


func test_ac42_the_reader_loads_each_file_into_stones_and_sets() -> void:
	if not _need_reader():
		return
	for entry: Dictionary in FILES:
		var bake: RefCounted = Api.load_bake(_path(entry))
		assert_object(bake).override_failure_message("load_file(%s)" % entry["file"]).is_not_null()
		if bake == null:
			continue
		var parsed: Dictionary = _file(entry)
		var stones: PackedFloat32Array = bake.get("stones")
		assert_int(stones.size()).override_failure_message(String(entry["file"])).is_equal(
			int(parsed.get("records", -1)) * RECORD_FLOATS
		)
		assert_dict(bake.get("header")).is_not_empty()
		var set_names: PackedStringArray = bake.call("set_names")
		if String(entry["mode"]) == "tiles":
			(
				assert_array(set_names)
				. override_failure_message("%s: no sets" % entry["file"])
				. is_not_empty()
			)
		for set_label: String in set_names:
			var records: PackedFloat32Array = bake.call("get_set", set_label)
			(
				assert_int(records.size() % RECORD_FLOATS)
				. override_failure_message("%s set %s" % [entry["file"], set_label])
				. is_equal(0)
			)
			assert_int(records.size()).is_greater(0)


func test_ac42_the_size_classes_of_the_reader_lie_in_the_packing_ranges_of_the_type() -> void:
	if not _need_reader():
		return
	for entry: Dictionary in FILES:
		var bake: RefCounted = Api.load_bake(_path(entry))
		if bake == null:
			assert_object(bake).override_failure_message(String(entry["file"])).is_not_null()
			continue
		var range_m: Array = SIZE_RANGE_M[String(entry["type"])]
		var median: float = float(bake.call("median_size"))
		var largest: float = float(bake.call("largest_size"))
		var label: String = String(entry["file"])
		assert_float(median).override_failure_message("%s median %s" % [label, median]).is_between(
			range_m[0], range_m[1]
		)
		(
			assert_float(largest)
			. override_failure_message("%s largest %s" % [label, largest])
			. is_between(median, range_m[1] + 1e-9)
		)


func test_ac42_the_reader_gives_null_and_an_error_for_a_missing_file() -> void:
	if not _need_reader():
		return
	var results: Array[RefCounted] = []
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void: results.append(Api.load_bake("res://assets/substrate/bake/not_there.bin"))
	)
	assert_object(results[0]).is_null()
	assert_dict(seen["errors"]).is_not_empty()


## A copy of sand.bin in the scratch folder with `edit` applied to (bytes, header) before writing;
## the Callable returns the new bytes. Returns the path.
func _write_variant(file_label: String, edit: Callable) -> String:
	DirAccess.make_dir_recursive_absolute(SCRATCH)
	var source: Dictionary = _parse("%s/sand.bin" % Api.BAKE_DIR)
	assert_str(String(source["problem"])).is_empty()
	var bytes: PackedByteArray = edit.call(source)
	var path: String = SCRATCH + file_label
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	return path


func _expect_rejected(path: String) -> void:
	var results: Array[RefCounted] = []
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void: results.append(Api.load_bake(path))
	)
	assert_object(results[0]).override_failure_message("a bad file was accepted").is_null()
	(
		assert_dict(seen["errors"])
		. override_failure_message("no push_error for a bad file")
		. is_not_empty()
	)


func test_ac42_the_reader_rejects_a_wrong_magic() -> void:
	if not _need_reader():
		return
	var path: String = _write_variant(
		"magic.bin",
		func(source: Dictionary) -> PackedByteArray:
			var bytes: PackedByteArray = (source["bytes"] as PackedByteArray).duplicate()
			bytes[0] = 0x58
			return bytes
	)
	await _expect_rejected(path)


func test_ac42_the_reader_rejects_a_wrong_format_version() -> void:
	if not _need_reader():
		return
	var path: String = _write_variant(
		"version.bin",
		func(source: Dictionary) -> PackedByteArray:
			var bytes: PackedByteArray = (source["bytes"] as PackedByteArray).duplicate()
			bytes.encode_u32(4, FORMAT_VERSION + 1)
			return bytes
	)
	await _expect_rejected(path)


func test_ac42_the_reader_rejects_a_packing_version_that_is_not_the_assembler_constant() -> void:
	if not _need_reader():
		return
	var path: String = _write_variant(
		"packing.bin",
		func(source: Dictionary) -> PackedByteArray:
			var header: Dictionary = (source["header"] as Dictionary).duplicate(true)
			_set_deep(header, "packing_version", Api.packing_version() + 1)
			var header_bytes: PackedByteArray = JSON.stringify(header).to_utf8_buffer()
			var bytes: PackedByteArray = source["bytes"]
			var rebuilt: PackedByteArray = bytes.slice(0, 8)
			rebuilt.resize(PREAMBLE_BYTES)
			rebuilt.encode_u32(8, header_bytes.size())
			rebuilt.append_array(header_bytes)
			rebuilt.append_array(bytes.slice(PREAMBLE_BYTES + int(source["header_length"])))
			return rebuilt
	)
	await _expect_rejected(path)


func _set_deep(value: Variant, wanted: String, replacement: Variant) -> void:
	if value is Dictionary:
		var dict: Dictionary = value
		if dict.has(wanted):
			dict[wanted] = replacement
		for key: Variant in dict:
			_set_deep(dict[key], wanted, replacement)
	elif value is Array:
		for entry: Variant in value:
			_set_deep(entry, wanted, replacement)
