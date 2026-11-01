extends RefCounted
## Builds save files and models for the B06 tests.
##
## Damaged, deep and oversized files are generated here at test time (the pre-commit hooks would
## refuse or rewrite them if they were committed). Test files live under user://test_saves/<suite>/
## and are deleted by the suite in after_test. Test helper only.

const Factory := preload("res://tests/helpers/factory.gd")

const ROOT := "user://test_saves"
const GOLDEN_PATH := "res://tests/fixtures/saves/golden_v1.json"
const MINIMAL_PATH := "res://tests/fixtures/saves/minimal_v1.json"
## The load time and the save time used by the tests.
const NOW := "2026-11-01T12:00:00Z"
const STAMP_CREATED := "2026-10-01T08:30:00Z"
const STAMP_MODIFIED := "2026-10-02T21:15:30Z"
const MAX_FILE_BYTES := 16 * 1024 * 1024
const RAW := "@@RAW@@"

# --- test folder ---------------------------------------------------------------------------


## Creates an empty folder for one suite and returns its path.
static func make_dir(suite: String) -> String:
	var path: String = ROOT.path_join(suite)
	remove_dir(path)
	DirAccess.make_dir_recursive_absolute(path)
	return path


## Deletes a folder with everything in it. Does nothing if it does not exist.
static func remove_dir(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		remove_dir(path.path_join(sub))
	for file_name: String in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	DirAccess.remove_absolute(path)


## Removes the test root when it is empty (called after the suite folder was deleted).
static func remove_root_if_empty() -> void:
	var dir: DirAccess = DirAccess.open(ROOT)
	if dir == null:
		return
	if dir.get_directories().is_empty() and dir.get_files().is_empty():
		DirAccess.remove_absolute(ROOT)


## Sorted names directly inside a folder; folders end with "/".
static func listing(path: String) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return result
	for sub: String in dir.get_directories():
		result.append(sub + "/")
	for file_name: String in dir.get_files():
		result.append(file_name)
	result.sort()
	return result


static func write_bytes(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "cannot write test file %s" % path)
	file.store_buffer(bytes)
	file.close()


static func write_text(path: String, text: String) -> void:
	write_bytes(path, text.to_utf8_buffer())


static func read_bytes(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path)


static func read_text(path: String) -> String:
	return FileAccess.get_file_as_string(path)


## The parsed JSON of a file (a Dictionary), or an empty Dictionary.
static func read_json(path: String) -> Dictionary:
	var json: JSON = JSON.new()
	if json.parse(read_text(path)) != OK:
		return {}
	var data: Variant = json.data
	if data is Dictionary:
		return data
	return {}


## The decoded model of a result. A failed result has no model: return an empty one, so a failing
## assert does not turn into a runtime error that aborts the rest of the suite. The stand-in
## has one item and one fish, so accessors work; its values match no test expectation.
static func model_of(result: SaveResult) -> AquariumModel:
	if result.model != null:
		return result.model
	var stand_in: AquariumModel = AquariumModel.new(NOW)
	stand_in.apply_set_name("<no model>")
	stand_in.apply_insert_item(Factory.item("00000000"), 0)
	stand_in.apply_insert_fish(Factory.fish("00000001"), 0)
	return stand_in


# --- JSON text -----------------------------------------------------------------------------


## The text the encoder is specified to write: two-space indent, insertion order, full precision,
## one trailing newline.
static func to_text(data: Variant) -> String:
	return JSON.stringify(data, "  ", false, true) + "\n"


static func to_bytes(data: Variant) -> PackedByteArray:
	return to_text(data).to_utf8_buffer()


static func b64(values: Array[float]) -> String:
	return Marshalls.raw_to_base64(PackedFloat32Array(values).to_byte_array())


## A valid version 1 file as a Dictionary, in key order.
static func base_dict() -> Dictionary:
	var item: Dictionary = {
		"uid": "a0000001",
		"catalog_id": "rock_a",
		"position": [0.5, 0.0, -0.25],
		"rotation_y": 35.0,
		"scale": 1.5,
		"colour": "#7A5C3E",
	}
	var fish: Dictionary = {
		"uid": "f0000001",
		"species_id": "neon_tetra",
		"variant": 1,
		"nickname": "Nemo",
	}
	var heightmap: Dictionary = {"size": [2, 1], "data": b64([0.0, 0.5])}
	var substrate: Dictionary = {"id": "sand", "colour": "#E8D9B0", "heightmap": heightmap}
	return {
		"format_version": 1,
		"name": "Base",
		"tank_id": "tank_60",
		"substrate": substrate,
		"items": [item],
		"fish": [fish],
		"created": STAMP_CREATED,
		"modified": STAMP_MODIFIED,
	}


## A deep copy of base_dict() with the value at the path replaced. Path parts are Dictionary keys
## (String) or Array indexes (int), for example ["items", 0, "uid"].
static func changed(path: Array, value: Variant) -> Dictionary:
	var data: Dictionary = base_dict()
	var node: Variant = data
	for index: int in range(path.size() - 1):
		node = node[path[index]]
	node[path.back()] = value
	return data


## A deep copy of base_dict() with the key at the path removed.
static func removed(path: Array) -> Dictionary:
	var data: Dictionary = base_dict()
	var node: Variant = data
	for index: int in range(path.size() - 1):
		node = node[path[index]]
	var parent: Dictionary = node
	parent.erase(path.back())
	return data


## JSON text of base_dict() with the value at the path written as raw text, for example 1e999
## (stringify cannot write a non-finite number).
static func changed_raw(path: Array, raw: String) -> String:
	return to_text(changed(path, RAW)).replace('"%s"' % RAW, raw)


## The text of a file nested `depth` levels deep under an unknown key.
static func deep_text(depth: int, use_arrays: bool) -> String:
	var head: String = '{"format_version": 1, "x": '
	if use_arrays:
		return head + "[".repeat(depth) + "]".repeat(depth) + "}"
	return head + '{"a":'.repeat(depth) + "1" + "}".repeat(depth) + "}"


## A valid `{"format_version": 1}` file padded with spaces to exactly `size` bytes.
static func padded_bytes(size: int) -> PackedByteArray:
	var text: String = '{"format_version": 1}'
	return (text + " ".repeat(size - text.length())).to_utf8_buffer()


## Bytes of a v1 file with raw bytes spliced into the name.
static func bytes_with_name(raw: PackedByteArray) -> PackedByteArray:
	var result: PackedByteArray = '{"format_version": 1, "name": "'.to_utf8_buffer()
	result.append_array(raw)
	result.append_array('"}'.to_utf8_buffer())
	return result


# --- models --------------------------------------------------------------------------------


## 3 items (two coloured, one not), 3 fish, a non-flat 3 x 2 heightmap, odd floats.
static func populated_model() -> AquariumModel:
	var model: AquariumModel = AquariumModel.new(STAMP_CREATED)
	model.apply_set_name("Reef Árvíztűrő")
	model.apply_set_tank_id(&"tank_60")
	model.apply_set_substrate(&"fine_sand", Color(0.8, 0.7, 0.5))
	var values: PackedFloat32Array = PackedFloat32Array([0.0, 0.1, 0.2, 1.0 / 3.0, 0.5, 1e-7])
	model.apply_set_heightmap(values, Vector2i(3, 2))
	var first: PlacedItem = Factory.coloured_item("a0000001", Color(0.2, 0.4, 0.6))
	var second: PlacedItem = Factory.item("a0000002", &"plant_fern", Vector3(-0.3, 0.1, 0.2), -45.0)
	var third: PlacedItem = Factory.coloured_item("a0000003", Color(0.9, 0.1, 0.3, 0.5))
	for item: PlacedItem in [first, second, third]:
		model.apply_insert_item(item, model.get_item_count())
	model.apply_insert_fish(Factory.fish("f0000001", &"neon_tetra", 0, "Nemo"), 0)
	model.apply_insert_fish(Factory.fish("f0000002", &"guppy", 2, ""), 1)
	model.apply_insert_fish(Factory.fish("f0000003", &"betta", 1, "Kék 熱帯魚"), 2)
	return model


## The D18 target tank: 60 fish, 100 items, a 128 x 64 heightmap with varied values.
static func d18_model() -> AquariumModel:
	var model: AquariumModel = AquariumModel.new(STAMP_CREATED)
	var uids: UidGenerator = UidGenerator.new(42)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	model.apply_set_name("D18 tank")
	model.apply_set_tank_id(&"tank_120")
	model.apply_set_substrate(&"gravel", Color(rng.randf(), rng.randf(), rng.randf()))
	var values: PackedFloat32Array = PackedFloat32Array()
	for index: int in 128 * 64:
		values.append(rng.randf() * 0.2)
	model.apply_set_heightmap(values, Vector2i(128, 64))
	for index: int in 100:
		var position: Vector3 = Vector3(rng.randf(), rng.randf(), rng.randf())
		var item: PlacedItem = Factory.item(
			uids.generate(model),
			StringName("item_%d" % (index % 7)),
			position,
			rng.randf() * 360.0,
			0.5 + rng.randf()
		)
		if index % 3 == 0:
			item.has_colour = true
			item.colour = Color(rng.randf(), rng.randf(), rng.randf(), rng.randf())
		model.apply_insert_item(item, model.get_item_count())
	for index: int in 60:
		var uid: String = uids.generate(model)
		var species: StringName = StringName("species_%d" % (index % 3))
		var fish: FishInstance = Factory.fish(uid, species, index % 4, "fish %d" % index)
		model.apply_insert_fish(fish, model.get_fish_count())
	return model


## The model that golden_v1.json must load to. Built by hand, not by the codec.
static func golden_expected() -> AquariumModel:
	var model: AquariumModel = AquariumModel.new(STAMP_CREATED)
	model.set_save_times(STAMP_CREATED, STAMP_MODIFIED)
	model.apply_set_name("Árvíztűrő 熱帯魚")
	model.apply_set_tank_id(&"tank_60")
	model.apply_set_substrate(&"fine_sand", Color8(0xE8, 0xD9, 0xB0))
	var values: PackedFloat32Array = PackedFloat32Array([0.0, 0.5, 1.0, 0.25, 0.125, 0.0625])
	model.apply_set_heightmap(values, Vector2i(3, 2))
	var rock: PlacedItem = Factory.item(
		"a1b2c3d4", &"rock_flat", Vector3(0.5, 0.0, -0.25), 35.0, 1.5
	)
	rock.has_colour = true
	rock.colour = Color8(0x7A, 0x5C, 0x3E)
	var fern: PlacedItem = Factory.item(
		"0badf00d", &"plant_java_fern", Vector3(-0.25, 0.125, 0.5), -90.0, 0.5
	)
	fern.has_colour = true
	fern.colour = Color8(0x11, 0x22, 0x33, 0x80)
	var plain: PlacedItem = Factory.item("00000003", &"unknown_future_item", Vector3.ZERO, 0.0, 1.0)
	for item: PlacedItem in [rock, fern, plain]:
		model.apply_insert_item(item, model.get_item_count())
	model.apply_insert_fish(Factory.fish("f1000001", &"neon_tetra", 0, "Nemo"), 0)
	model.apply_insert_fish(Factory.fish("f1000002", &"guppy", 2, ""), 1)
	return model
