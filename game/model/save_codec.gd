class_name SaveCodec
extends RefCounted
## Encodes an AquariumModel to save text and decodes save text into a fresh model. Pure: no file
## access, no clock, no Node. The stamps come in as arguments.
##
## Decoding never touches a live model: it fills a new AquariumModel and returns it in the
## result, and any broken rule gives DAMAGED (or NEWER_VERSION) with no model at all. Encoding
## builds the file data from the model and runs the reader's own rules on it, so the writer never
## writes a file the reader would refuse (INTERNAL instead). The layout and rules are in
## docs/architecture.md, chapter "Save format".

const FORMAT_VERSION: int = 1
const MAX_FILE_BYTES: int = 16 * 1024 * 1024
const _BOM: PackedByteArray = [0xEF, 0xBB, 0xBF]

var _current_version: int = FORMAT_VERSION
var _migrations: Dictionary = {}
## The first broken rule of the current read, or "". Reset by _read_model().
var _failure: String = ""


## `migrations` maps a from-version (int) to a Callable(data: Dictionary) -> Variant that returns
## the data upgraded by one version, or null on failure. See SaveMigrations.
func _init(
	current_version: int = FORMAT_VERSION, migrations: Dictionary = SaveMigrations.steps()
) -> void:
	_current_version = current_version
	_migrations = migrations


func get_current_version() -> int:
	return _current_version


## The save text of a model, with `modified_utc` written as the modified stamp. OK with text, or
## INTERNAL when the model cannot be written as a file the reader accepts.
func encode(model: AquariumModel, modified_utc: String) -> SaveResult:
	if not SaveRules.is_stamp(modified_utc):
		return SaveResult.failure(SaveResult.Kind.INTERNAL, "the modified stamp is malformed")
	if not _colours_are_finite(model):
		return SaveResult.failure(SaveResult.Kind.INTERNAL, "a colour has a non-finite component")
	var data: Dictionary = _model_to_dictionary(model, modified_utc)
	var check: SaveResult = _read_model(data, modified_utc)
	if not check.is_ok():
		return SaveResult.failure(
			SaveResult.Kind.INTERNAL, "the model is not writable: %s" % check.detail
		)
	var text: String = SaveJson.stringify(data)
	if text.is_empty():
		return SaveResult.failure(SaveResult.Kind.INTERNAL, "a number cannot be written exactly")
	var file_text: String = text + "\n"
	if file_text.to_utf8_buffer().size() > MAX_FILE_BYTES:
		return SaveResult.failure(
			SaveResult.Kind.INTERNAL, "the file would be larger than the reader limit"
		)
	return SaveResult.with_text(file_text)


## Decodes the bytes of a file: size limit, one optional leading BOM, strict UTF-8, then decode().
func decode_bytes(bytes: PackedByteArray, now_utc: String) -> SaveResult:
	if bytes.size() > MAX_FILE_BYTES:
		return SaveResult.failure(SaveResult.Kind.DAMAGED, "the file is larger than the limit")
	var body: PackedByteArray = bytes
	if body.size() >= _BOM.size() and body.slice(0, _BOM.size()) == _BOM:
		body = body.slice(_BOM.size())
	if body.is_empty():
		return SaveResult.failure(SaveResult.Kind.DAMAGED, "the file is empty")
	var text: String = body.get_string_from_utf8()
	if text.to_utf8_buffer() != body:
		return SaveResult.failure(SaveResult.Kind.DAMAGED, "the file is not valid UTF-8")
	return decode(text, now_utc)


## Decodes save text: parse, version check, migrations, validation. A text with a newer
## format_version is refused before anything else is read.
func decode(text: String, now_utc: String) -> SaveResult:
	if not SaveRules.is_stamp(now_utc):
		return SaveResult.failure(SaveResult.Kind.INTERNAL, "the load time is malformed")
	var json: SaveJson = SaveJson.new()
	if json.parse(text) != OK:
		return SaveResult.failure(SaveResult.Kind.DAMAGED, json.error_message)
	if typeof(json.data) != TYPE_DICTIONARY:
		return SaveResult.failure(SaveResult.Kind.DAMAGED, "the top level is not an object")
	var data: Dictionary = json.data
	var problem: SaveResult = _version_problem(data)
	if problem != null:
		return problem
	var migrated: Variant = _migrate(data, int(data["format_version"]))
	if typeof(migrated) != TYPE_DICTIONARY:
		return SaveResult.failure(SaveResult.Kind.DAMAGED, str(migrated))
	return _read_model(migrated, now_utc)


## Null when format_version is a whole number from 1 to the current version. Otherwise DAMAGED,
## or NEWER_VERSION for any whole number above the current version, however large.
func _version_problem(data: Dictionary) -> SaveResult:
	var version: Variant = data.get("format_version")
	if not SaveRules.is_whole(version) or float(version) < 1.0:
		return SaveResult.failure(SaveResult.Kind.DAMAGED, "format_version is not a whole number")
	if float(version) > float(_current_version):
		return SaveResult.failure(SaveResult.Kind.NEWER_VERSION, "format_version %s" % version)
	return null


# --- Migrations -----------------------------------------------------------------------------


## The data upgraded to the current version, or an error text (String) when a step fails.
func _migrate(data: Dictionary, from_version: int) -> Variant:
	var current: Dictionary = data
	for step_version: int in range(from_version, _current_version):
		var entry: Variant = _migrations.get(step_version)
		if typeof(entry) != TYPE_CALLABLE:
			return "no migration step from version %d" % step_version
		var step: Callable = entry
		if not step.is_valid():
			return "no migration step from version %d" % step_version
		var result: Variant = step.call(current)
		if typeof(result) != TYPE_DICTIONARY:
			return "migration step %d did not return an object" % step_version
		current = result
		current["format_version"] = step_version + 1
	return current


# --- Writer: model to data --------------------------------------------------------------------


func _colours_are_finite(model: AquariumModel) -> bool:
	if not _is_finite_colour(model.get_substrate_colour()):
		return false
	for item: PlacedItem in model.get_items():
		if item.has_colour and not _is_finite_colour(item.colour):
			return false
	return true


func _is_finite_colour(colour: Color) -> bool:
	return (
		is_finite(colour.r) and is_finite(colour.g) and is_finite(colour.b) and is_finite(colour.a)
	)


## The file data in key order: format_version, name, tank_id, substrate, items, fish, created,
## modified.
func _model_to_dictionary(model: AquariumModel, modified_utc: String) -> Dictionary:
	var size: Vector2i = model.get_heightmap_size()
	var heightmap: Dictionary = {
		"size": [size.x, size.y],
		"data": SaveRules.heightmap_to_base64(model.get_heightmap()),
	}
	var substrate: Dictionary = {
		"id": String(model.get_substrate_id()),
		"colour": SaveRules.colour_to_hex(model.get_substrate_colour()),
		"heightmap": heightmap,
	}
	var items: Array = []
	for item: PlacedItem in model.get_items():
		items.append(_item_to_dictionary(item))
	var fish: Array = []
	for member: FishInstance in model.get_fish_list():
		(
			fish
			. append(
				{
					"uid": member.uid,
					"species_id": String(member.species_id),
					"variant": member.variant,
					"nickname": member.nickname,
				}
			)
		)
	return {
		"format_version": _current_version,
		"name": model.get_aquarium_name(),
		"tank_id": String(model.get_tank_id()),
		"substrate": substrate,
		"items": items,
		"fish": fish,
		"created": model.get_created(),
		"modified": modified_utc,
	}


func _item_to_dictionary(item: PlacedItem) -> Dictionary:
	var colour: Variant = null
	if item.has_colour:
		colour = SaveRules.colour_to_hex(item.colour)
	return {
		"uid": item.uid,
		"catalog_id": String(item.catalog_id),
		"position": [item.position.x, item.position.y, item.position.z],
		"rotation_y": item.rotation_y,
		"scale": item.scale,
		"colour": colour,
	}


# --- Reader: data to model --------------------------------------------------------------------


## Builds a fresh model from file data (already at the current version). The first broken rule
## gives DAMAGED, and the half-built model is dropped. Used by decode() and by the writer check.
func _read_model(data: Dictionary, now_utc: String) -> SaveResult:
	_failure = ""
	var model: AquariumModel = AquariumModel.new(now_utc)
	model.apply_set_name(_read_string(data, "name", "", "name"))
	model.apply_set_tank_id(StringName(_read_string(data, "tank_id", "", "tank_id")))
	_read_substrate(data, model)
	if _failure.is_empty():
		_read_items(data, model)
	if _failure.is_empty():
		_read_fish(data, model)
	var created: String = _read_stamp(data, "created", now_utc)
	var modified: String = _read_stamp(data, "modified", now_utc)
	model.set_save_times(created, modified)
	if not _failure.is_empty():
		return SaveResult.failure(SaveResult.Kind.DAMAGED, _failure)
	return SaveResult.with_model(model)


func _fail(why: String) -> void:
	if _failure.is_empty():
		_failure = why


func _read_substrate(data: Dictionary, model: AquariumModel) -> void:
	var substrate: Dictionary = _read_dictionary(data, "substrate")
	var colour: Color = Color.WHITE
	if substrate.has("colour"):
		colour = _read_colour(substrate["colour"], "substrate.colour")
	model.apply_set_substrate(StringName(_read_string(substrate, "id", "", "substrate.id")), colour)
	_read_heightmap(_read_dictionary(substrate, "heightmap"), model)


func _read_heightmap(map: Dictionary, model: AquariumModel) -> void:
	var size: Vector2i = _read_heightmap_size(map)
	var text: String = _read_string(map, "data", "", "heightmap.data")
	if not _failure.is_empty():
		return
	var byte_count: int = SaveRules.base64_byte_length(text)
	if byte_count < 0:
		_fail("heightmap.data is not valid base64")
		return
	if byte_count != size.x * size.y * 4:
		_fail("heightmap.data does not match heightmap.size")
		return
	var values: PackedFloat32Array = PackedFloat32Array()
	if byte_count > 0:
		values = Marshalls.base64_to_raw(text).to_float32_array()
	for value: float in values:
		if not is_finite(value):
			_fail("heightmap.data has a non-finite value")
			return
	model.apply_set_heightmap(values, size)


## Both sides 0, or both 1..MAX_HEIGHTMAP_SIDE. Zero Vector2i after a failure.
func _read_heightmap_size(map: Dictionary) -> Vector2i:
	if not map.has("size"):
		return Vector2i.ZERO
	var value: Variant = map["size"]
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 2:
		_fail("heightmap.size is not a pair")
		return Vector2i.ZERO
	var pair: Array = value
	for side: Variant in pair:
		var limit: float = float(SaveRules.MAX_HEIGHTMAP_SIDE)
		if not SaveRules.is_whole(side) or float(side) < 0.0 or float(side) > limit:
			_fail("heightmap.size has a side that is not a whole number from 0 to 1024")
			return Vector2i.ZERO
	var size: Vector2i = Vector2i(int(pair[0]), int(pair[1]))
	if (size.x == 0) != (size.y == 0):
		_fail("heightmap.size has one side 0")
		return Vector2i.ZERO
	return size


func _read_items(data: Dictionary, model: AquariumModel) -> void:
	for entry: Variant in _read_list(data, "items"):
		if typeof(entry) != TYPE_DICTIONARY:
			_fail("items has an entry that is not an object")
			return
		var item: PlacedItem = _read_item(entry)
		if not _failure.is_empty():
			return
		if not model.apply_insert_item(item, model.get_item_count()):
			_fail("items has a duplicate uid %s" % item.uid)
			return


func _read_item(entry: Dictionary) -> PlacedItem:
	var item: PlacedItem = PlacedItem.new()
	item.uid = _read_uid(entry, "items.uid")
	item.catalog_id = StringName(_read_identity(entry, "catalog_id", "items.catalog_id"))
	item.position = _read_position(entry)
	item.rotation_y = _read_number(entry, "rotation_y", 0.0, "items.rotation_y")
	item.scale = _read_number(entry, "scale", 1.0, "items.scale")
	if item.scale <= 0.0:
		_fail("items.scale is not above 0")
	if entry.has("colour") and entry["colour"] != null:
		item.has_colour = true
		item.colour = _read_colour(entry["colour"], "items.colour")
	return item


func _read_position(entry: Dictionary) -> Vector3:
	if not entry.has("position"):
		return Vector3.ZERO
	var value: Variant = entry["position"]
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 3:
		_fail("items.position is not three numbers")
		return Vector3.ZERO
	var parts: Array = value
	for part: Variant in parts:
		if not SaveRules.is_number(part):
			_fail("items.position is not three numbers")
			return Vector3.ZERO
	var position: Vector3 = Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
	if not (is_finite(position.x) and is_finite(position.y) and is_finite(position.z)):
		_fail("items.position does not fit in 32 bits")
	return position


func _read_fish(data: Dictionary, model: AquariumModel) -> void:
	for entry: Variant in _read_list(data, "fish"):
		if typeof(entry) != TYPE_DICTIONARY:
			_fail("fish has an entry that is not an object")
			return
		var fish: FishInstance = _read_fish_entry(entry)
		if not _failure.is_empty():
			return
		if not model.apply_insert_fish(fish, model.get_fish_count()):
			_fail("fish has a duplicate uid %s" % fish.uid)
			return


func _read_fish_entry(entry: Dictionary) -> FishInstance:
	var fish: FishInstance = FishInstance.new()
	fish.uid = _read_uid(entry, "fish.uid")
	fish.species_id = StringName(_read_identity(entry, "species_id", "fish.species_id"))
	fish.nickname = _read_string(entry, "nickname", "", "fish.nickname")
	if entry.has("variant"):
		var variant: Variant = entry["variant"]
		if (
			not SaveRules.is_whole(variant)
			or float(variant) < 0.0
			or float(variant) > float(SaveRules.MAX_VARIANT)
		):
			_fail("fish.variant is not a whole number from 0 to 255")
		else:
			fish.variant = int(variant)
	return fish


# --- Reader: single values ---------------------------------------------------------------------


## A Dictionary value; empty when the key is missing. A present value of another type fails.
func _read_dictionary(parent: Dictionary, key: String) -> Dictionary:
	if not parent.has(key):
		return {}
	var value: Variant = parent[key]
	if typeof(value) != TYPE_DICTIONARY:
		_fail("%s is not an object" % key)
		return {}
	return value


## An Array value; empty when the key is missing. A present value of another type fails.
func _read_list(parent: Dictionary, key: String) -> Array:
	if not parent.has(key):
		return []
	var value: Variant = parent[key]
	if typeof(value) != TYPE_ARRAY:
		_fail("%s is not a list" % key)
		return []
	return value


## A String value, or the default when the key is missing. Null and other types fail.
func _read_string(parent: Dictionary, key: String, default: String, label: String) -> String:
	if not parent.has(key):
		return default
	var value: Variant = parent[key]
	if typeof(value) != TYPE_STRING:
		_fail("%s is not a string" % label)
		return default
	return value


## A required, non-empty String (catalog_id, species_id).
func _read_identity(parent: Dictionary, key: String, label: String) -> String:
	var value: String = _read_string(parent, key, "", label)
	if value.is_empty():
		_fail("%s is missing or empty" % label)
	return value


func _read_uid(parent: Dictionary, label: String) -> String:
	var value: Variant = parent.get("uid")
	if not SaveRules.is_uid(value):
		_fail("%s is not 8 lowercase hex characters" % label)
		return ""
	return value


## A finite number, or the default when the key is missing.
func _read_number(parent: Dictionary, key: String, default: float, label: String) -> float:
	if not parent.has(key):
		return default
	var value: Variant = parent[key]
	if not SaveRules.is_number(value):
		_fail("%s is not a finite number" % label)
		return default
	return float(value)


func _read_colour(value: Variant, label: String) -> Color:
	if not SaveRules.is_hex_colour(value):
		_fail("%s is not #RRGGBB or #RRGGBBAA" % label)
		return Color.WHITE
	return SaveRules.hex_to_colour(value)


## A stamp, or the default when the key is missing.
func _read_stamp(parent: Dictionary, key: String, default: String) -> String:
	if not parent.has(key):
		return default
	var value: Variant = parent[key]
	if not SaveRules.is_stamp(value):
		_fail("%s is not YYYY-MM-DDTHH:MM:SSZ" % key)
		return default
	return value
