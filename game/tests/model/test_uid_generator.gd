extends GdUnitTestSuite

const Factory := preload("res://tests/helpers/factory.gd")


func test_format_is_8_lower_hex() -> void:
	var generator: UidGenerator = UidGenerator.new(7)
	var model: AquariumModel = AquariumModel.new()
	var pattern: RegEx = RegEx.create_from_string("^[0-9a-f]{8}$")
	for _i: int in range(1000):
		var uid: String = generator.generate(model)
		assert_object(pattern.search(uid)).is_not_null()


func test_unseeded_generator_works() -> void:
	var generator: UidGenerator = UidGenerator.new()
	var uid: String = generator.generate(AquariumModel.new())
	assert_int(uid.length()).is_equal(8)


func test_same_seed_same_sequence() -> void:
	var first: UidGenerator = UidGenerator.new(1234)
	var second: UidGenerator = UidGenerator.new(1234)
	var model: AquariumModel = AquariumModel.new()
	for _i: int in range(20):
		assert_str(first.generate(model)).is_equal(second.generate(model))


func test_different_seed_different_sequence() -> void:
	var first: String = UidGenerator.new(1).generate(null)
	var second: String = UidGenerator.new(2).generate(null)
	assert_str(first).is_not_equal(second)


func test_skips_existing_uid() -> void:
	var model: AquariumModel = AquariumModel.new()
	var u1: String = UidGenerator.new(99).generate(model)
	var inserted: bool = model.apply_insert_item(Factory.item(u1), 0)
	assert_bool(inserted).is_true()
	var next: String = UidGenerator.new(99).generate(model)
	assert_str(next).is_not_equal(u1)
	assert_bool(model.has_uid(next)).is_false()


func test_skips_uid_used_by_fish() -> void:
	var model: AquariumModel = AquariumModel.new()
	var u1: String = UidGenerator.new(99).generate(model)
	var inserted: bool = model.apply_insert_fish(Factory.fish(u1), 0)
	assert_bool(inserted).is_true()
	var next: String = UidGenerator.new(99).generate(model)
	assert_str(next).is_not_equal(u1)


func test_null_model_allowed() -> void:
	var uid: String = UidGenerator.new(5).generate(null)
	assert_int(uid.length()).is_equal(8)
