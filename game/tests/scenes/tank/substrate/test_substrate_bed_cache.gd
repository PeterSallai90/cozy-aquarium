extends GdUnitTestSuite
## #28 criterion 32 (developer's own checks): the session cache of SubstrateBed keeps the six
## assembled beds used last, keyed by tank, type and packing version, and the baked data per file.

const Fixture := preload("res://tests/helpers/substrate_bed_fixture.gd")
const Sub := preload("res://tests/helpers/substrate_api.gd")
const Table := preload("res://tests/helpers/tank_table.gd")


## A bed whose input names the pair (the buffers do not matter to the cache).
func _data(tank_id: StringName, substrate_id: StringName) -> SubstrateBedData:
	var data: SubstrateBedData = SubstrateBedData.new()
	data.input = SubstrateAssemblyInput.new()
	data.input.tank_id = tank_id
	data.input.substrate_id = substrate_id
	data.input.packing_version = SubstrateAssembler.PACKING_VERSION
	return data


func test_ac32_the_key_names_tank_type_and_packing_version() -> void:
	assert_str(SubstrateBedCache.key_for(&"tank_small_1", &"sand_fine", 7)).is_equal(
		"tank_small_1|sand_fine|7"
	)
	assert_str(SubstrateBedCache.key_for(&"tank_small_1", &"sand_fine")).is_equal(
		"tank_small_1|sand_fine|%d" % SubstrateAssembler.PACKING_VERSION
	)


func test_ac32_a_stored_bed_comes_back_as_the_same_object() -> void:
	var cache: SubstrateBedCache = SubstrateBedCache.new()
	var data: SubstrateBedData = _data(Table.SMALL, Sub.GRAVEL)
	cache.put_data(data)
	assert_bool(is_same(cache.get_data(Table.SMALL, Sub.GRAVEL), data)).is_true()
	assert_object(cache.get_data(Table.MEDIUM, Sub.GRAVEL)).is_null()
	assert_object(cache.get_data(Table.SMALL, Sub.SAND)).is_null()


func test_ac32_the_cache_keeps_the_six_used_last() -> void:
	var cache: SubstrateBedCache = SubstrateBedCache.new()
	var pairs: Array[Array] = []
	for tank_id: StringName in [Table.SMALL, Table.MEDIUM]:
		for id: StringName in [Sub.SAND, Sub.GRAVEL, Sub.PEBBLES]:
			pairs.append([tank_id, id])
	for pair: Array in pairs:
		cache.put_data(_data(pair[0], pair[1]))
	assert_int(cache.data_count()).is_equal(SubstrateBedCache.CAPACITY)
	# a hit makes the oldest entry the newest one, so the next one in line is dropped instead
	assert_object(cache.get_data(Table.SMALL, Sub.SAND)).is_not_null()
	cache.put_data(_data(Table.LARGE, Sub.SAND))
	assert_int(cache.data_count()).is_equal(SubstrateBedCache.CAPACITY)
	assert_bool(cache.has_data(Table.SMALL, Sub.SAND)).is_true()
	assert_bool(cache.has_data(Table.SMALL, Sub.GRAVEL)).is_false()
	assert_bool(cache.has_data(Table.LARGE, Sub.SAND)).is_true()


func test_ac32_baked_data_is_kept_per_file_and_counted_in_the_memory() -> void:
	var cache: SubstrateBedCache = SubstrateBedCache.new()
	var bake: SubstrateBakeData = Fixture.bake_of(Table.SMALL, Sub.PEBBLES) as SubstrateBakeData
	var path: String = "res://assets/substrate/bake/pebbles_river_tank_small_1.bin"
	cache.put_bake(path, bake)
	cache.put_bake("", bake)
	cache.put_bake("res://none.bin", null)
	assert_bool(is_same(cache.get_bake(path), bake)).is_true()
	assert_object(cache.get_bake("res://none.bin")).is_null()
	assert_int(cache.memory_bytes()).is_equal(bake.stones.size() * 4)
	var bed: SubstrateBedData = Fixture.bed_of(Table.SMALL, Sub.PEBBLES) as SubstrateBedData
	cache.put_data(bed)
	assert_int(cache.memory_bytes()).is_equal(bake.stones.size() * 4 + bed.byte_size())
	cache.clear()
	assert_int(cache.memory_bytes()).is_equal(0)
	assert_object(cache.get_bake(path)).is_null()
	assert_int(cache.data_count()).is_equal(0)
