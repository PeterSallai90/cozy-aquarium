class_name SubstrateBedCache
extends RefCounted
## The session cache of the substrate beds (ADR 0011 rule 10), owned by the room and shared by the
## bed of every tank it shows: assembled data per (tank, type, packing version), the six used last
## kept, and the baked data per file. A return to a tank or a type then only re-instances. The data
## is immutable once assembled, so a cached bed is never copied. Main thread only.

const CAPACITY: int = 6

var _data: Dictionary[String, SubstrateBedData] = {}
## Keys of _data, the one used last at the end.
var _order: Array[String] = []
var _bakes: Dictionary[String, SubstrateBakeData] = {}


## "<tank_id>|<substrate_id>|<packing_version>".
static func key_for(
	tank_id: StringName, substrate_id: StringName, version: int = SubstrateAssembler.PACKING_VERSION
) -> String:
	return "%s|%s|%d" % [tank_id, substrate_id, version]


## The assembled bed of the pair, or null; a hit becomes the entry used last.
func get_data(tank_id: StringName, substrate_id: StringName) -> SubstrateBedData:
	var key: String = key_for(tank_id, substrate_id)
	if not _data.has(key):
		return null
	_order.erase(key)
	_order.append(key)
	return _data[key]


## Keeps an assembled bed under the key of its input; drops the entry used longest ago when the
## cache is full.
func put_data(data: SubstrateBedData) -> void:
	if data == null or data.input == null:
		return
	var key: String = key_for(
		data.input.tank_id, data.input.substrate_id, data.input.packing_version
	)
	_order.erase(key)
	_order.append(key)
	_data[key] = data
	while _order.size() > CAPACITY:
		_data.erase(_order.pop_front())


func has_data(tank_id: StringName, substrate_id: StringName) -> bool:
	return _data.has(key_for(tank_id, substrate_id))


## The baked data read from `path`, or null.
func get_bake(path: String) -> SubstrateBakeData:
	return _bakes.get(path) as SubstrateBakeData


func put_bake(path: String, bake: SubstrateBakeData) -> void:
	if bake != null and not path.is_empty():
		_bakes[path] = bake


func clear() -> void:
	_data.clear()
	_order.clear()
	_bakes.clear()


## Bytes held: the instance buffers of the cached beds and the records of the cached bake files.
func memory_bytes() -> int:
	var total: int = 0
	for key: String in _data:
		total += _data[key].byte_size()
	for path: String in _bakes:
		total += _bakes[path].stones.size() * 4
	return total


func data_count() -> int:
	return _data.size()
