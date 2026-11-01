# gdlint: disable=max-public-methods
class_name AquariumModel
extends RefCounted
## Pure data of one aquarium. No Node references.
##
## Scalar state is private: read it through the getters. Only commands call the apply_ methods
## (enforced by a test scan). Every apply_ method validates first; on failure it changes nothing
## and emits nothing, on success it mutates and emits exactly one signal.
## Item and fish signals carry (uid, index); listeners read the instance with get_item_at(),
## get_fish_at() or get_item().

signal model_reset
signal name_changed(aquarium_name: String)
signal tank_changed(tank_id: StringName)
signal substrate_changed(substrate_id: StringName, colour: Color)
## B05 always passes the full area: Rect2i(Vector2i.ZERO, heightmap_size).
signal heightmap_changed(region: Rect2i)
signal item_added(uid: String, index: int)
## The index is the one the item had before removal.
signal item_removed(uid: String, index: int)
signal item_changed(uid: String, index: int)
signal fish_added(uid: String, index: int)
signal fish_removed(uid: String, index: int)
signal fish_changed(uid: String, index: int)

var _aquarium_name: String = ""
var _tank_id: StringName = &""
var _substrate_id: StringName = &""
var _substrate_colour: Color = Color.WHITE
var _heightmap: PackedFloat32Array = PackedFloat32Array()
var _heightmap_size: Vector2i = Vector2i.ZERO
var _created: String = ""
var _modified: String = ""
var _items: Array[PlacedItem] = []
var _fish: Array[FishInstance] = []


## An empty now_utc means the system clock, formatted YYYY-MM-DDTHH:MM:SSZ.
func _init(now_utc: String = "") -> void:
	var stamp: String = now_utc
	if stamp.is_empty():
		stamp = Time.get_datetime_string_from_system(true) + "Z"
	_created = stamp
	_modified = stamp


# --- Read API -------------------------------------------------------------------------------


func get_aquarium_name() -> String:
	return _aquarium_name


func get_tank_id() -> StringName:
	return _tank_id


func get_substrate_id() -> StringName:
	return _substrate_id


func get_substrate_colour() -> Color:
	return _substrate_colour


func get_heightmap() -> PackedFloat32Array:
	return _heightmap


func get_heightmap_size() -> Vector2i:
	return _heightmap_size


func get_created() -> String:
	return _created


func get_modified() -> String:
	return _modified


## Shallow copy of the list; the instances are read-only.
func get_items() -> Array[PlacedItem]:
	return _items.duplicate()


func get_item_count() -> int:
	return _items.size()


## Returns null if the index is out of range.
func get_item_at(index: int) -> PlacedItem:
	if index < 0 or index >= _items.size():
		return null
	return _items[index]


## Returns null if the uid is unknown.
func get_item(uid: String) -> PlacedItem:
	return get_item_at(get_item_index(uid))


## Returns -1 if the uid is unknown.
func get_item_index(uid: String) -> int:
	for i: int in _items.size():
		if _items[i].uid == uid:
			return i
	return -1


func get_fish_list() -> Array[FishInstance]:
	return _fish.duplicate()


func get_fish_count() -> int:
	return _fish.size()


## Returns null if the index is out of range.
func get_fish_at(index: int) -> FishInstance:
	if index < 0 or index >= _fish.size():
		return null
	return _fish[index]


## Returns null if the uid is unknown.
func get_fish(uid: String) -> FishInstance:
	return get_fish_at(get_fish_index(uid))


## Returns -1 if the uid is unknown.
func get_fish_index(uid: String) -> int:
	for i: int in _fish.size():
		if _fish[i].uid == uid:
			return i
	return -1


## True if any item or fish has the uid.
func has_uid(uid: String) -> bool:
	return get_item_index(uid) != -1 or get_fish_index(uid) != -1


# --- Mutators (commands only) ---------------------------------------------------------------


## Emits name_changed even if the value is unchanged.
func apply_set_name(value: String) -> void:
	_aquarium_name = value
	name_changed.emit(value)


func apply_set_tank_id(value: StringName) -> void:
	_tank_id = value
	tank_changed.emit(value)


func apply_set_substrate(substrate_id: StringName, colour: Color) -> void:
	_substrate_id = substrate_id
	_substrate_colour = colour
	substrate_changed.emit(substrate_id, colour)


## No size validation yet (B18).
func apply_set_heightmap(values: PackedFloat32Array, size: Vector2i) -> void:
	_heightmap = values
	_heightmap_size = size
	heightmap_changed.emit(Rect2i(Vector2i.ZERO, size))


## False if the item is null, its uid is empty or used, or the index is outside 0..count.
func apply_insert_item(item: PlacedItem, index: int) -> bool:
	if item == null or item.uid.is_empty() or has_uid(item.uid):
		return false
	if index < 0 or index > _items.size():
		return false
	_items.insert(index, item)
	item_added.emit(item.uid, index)
	return true


func apply_remove_item(uid: String) -> bool:
	var index: int = get_item_index(uid)
	if index == -1:
		return false
	_items.remove_at(index)
	item_removed.emit(uid, index)
	return true


## Swaps in a new instance at the index of item.uid.
func apply_replace_item(item: PlacedItem) -> bool:
	if item == null:
		return false
	var index: int = get_item_index(item.uid)
	if index == -1:
		return false
	_items[index] = item
	item_changed.emit(item.uid, index)
	return true


## Same rules as apply_insert_item; items and fish share one uid space.
func apply_insert_fish(fish: FishInstance, index: int) -> bool:
	if fish == null or fish.uid.is_empty() or has_uid(fish.uid):
		return false
	if index < 0 or index > _fish.size():
		return false
	_fish.insert(index, fish)
	fish_added.emit(fish.uid, index)
	return true


func apply_remove_fish(uid: String) -> bool:
	var index: int = get_fish_index(uid)
	if index == -1:
		return false
	_fish.remove_at(index)
	fish_removed.emit(uid, index)
	return true


func apply_replace_fish(fish: FishInstance) -> bool:
	if fish == null:
		return false
	var index: int = get_fish_index(fish.uid)
	if index == -1:
		return false
	_fish[index] = fish
	fish_changed.emit(fish.uid, index)
	return true


# --- Reset ----------------------------------------------------------------------------------


## Copies every field of source into this instance and emits model_reset once, nothing else.
## Not a command and does not touch any history; the save system calls it.
func reset_from(source: AquariumModel) -> void:
	if source == null:
		push_error("AquariumModel: reset_from() called with a null source")
		return
	_aquarium_name = source._aquarium_name
	_tank_id = source._tank_id
	_substrate_id = source._substrate_id
	_substrate_colour = source._substrate_colour
	_heightmap = source._heightmap.duplicate()
	_heightmap_size = source._heightmap_size
	_created = source._created
	_modified = source._modified
	_items.clear()
	for item: PlacedItem in source._items:
		_items.push_back(item.copy())
	_fish.clear()
	for fish: FishInstance in source._fish:
		_fish.push_back(fish.copy())
	model_reset.emit()
