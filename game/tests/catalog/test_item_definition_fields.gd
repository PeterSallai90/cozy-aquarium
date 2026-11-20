extends GdUnitTestSuite
## #152 criteria 1 to 3 (owner: developer): the fields, the enum values and the defaults of
## ItemDefinition. The class is reached through item_api.gd, so a missing class fails a test and
## does not abort the run.

const Items := preload("res://tests/helpers/item_api.gd")
const DEFINITION_FILE := "res://catalog/item_definition.gd"
const MARKER := "stored, never shown or used in Mode 1"


func _have_class() -> bool:
	var found: bool = Items.script_exists(Items.DEFINITION_PATH)
	assert_bool(found).override_failure_message("ItemDefinition does not exist").is_true()
	return found


func _names(block: Dictionary) -> Array[String]:
	var names: Array[String] = []
	for field: String in block:
		names.append(field)
	return names


# --- AC 1: the fields ---


func test_ac01_the_class_exists_and_extends_resource() -> void:
	if not _have_class():
		return
	assert_bool(Items.new_definition() is Resource).is_true()
	assert_str(Items.new_definition().get_script().get_global_name()).is_equal("ItemDefinition")


func test_ac01_the_stored_fields_are_exactly_the_three_tables() -> void:
	if not _have_class():
		return
	var expected: Array[String] = Items.all_field_names()
	var found: Array[String] = Items.property_names()
	assert_int(found.size()).is_equal(expected.size())
	for field: String in expected:
		assert_bool(found.has(field)).override_failure_message("%s is missing" % field).is_true()
	for field: String in found:
		assert_bool(expected.has(field)).override_failure_message("%s is extra" % field).is_true()


func test_ac01_the_field_blocks_hold_9_17_and_15_fields() -> void:
	assert_int(Items.MODE_1.size()).is_equal(9)
	assert_int(Items.COMMON.size()).is_equal(17)
	assert_int(Items.PLANT.size()).is_equal(15)


func test_ac01_every_mode_1_field_comes_before_every_mode_2_field() -> void:
	if not _have_class():
		return
	var found: Array[String] = Items.property_names()
	var last_mode_1: int = -1
	for field: String in Items.MODE_1:
		last_mode_1 = maxi(last_mode_1, found.find(field))
	var first_mode_2: int = found.size()
	for block: Dictionary in [Items.COMMON, Items.PLANT]:
		for field: String in block:
			var at: int = found.find(field)
			if at >= 0:
				first_mode_2 = mini(first_mode_2, at)
	assert_int(last_mode_1).is_greater_equal(0)
	assert_int(last_mode_1).is_less(first_mode_2)


func test_ac01_the_common_block_comes_before_the_plant_block() -> void:
	if not _have_class():
		return
	var found: Array[String] = Items.property_names()
	var last_common: int = -1
	for field: String in Items.COMMON:
		last_common = maxi(last_common, found.find(field))
	var first_plant: int = found.size()
	for field: String in Items.PLANT:
		var at: int = found.find(field)
		if at >= 0:
			first_plant = mini(first_plant, at)
	assert_int(last_common).is_greater_equal(0)
	assert_int(last_common).is_less(first_plant)


func test_ac01_no_field_is_a_drawn_size() -> void:
	if not _have_class():
		return
	var banned: Array[String] = ["drawn_size", "size", "scale", "drawn_scale", "model_scale"]
	for field: String in Items.property_names():
		(
			assert_bool(banned.has(field))
			. override_failure_message("%s is a drawn size" % field)
			. is_false()
		)


func test_ac01_the_source_marks_the_mode_2_blocks_as_stored_not_used() -> void:
	if not _have_class():
		return
	var text: String = FileAccess.get_file_as_string(DEFINITION_FILE)
	assert_str(text).override_failure_message("marker text missing").contains(MARKER)
	assert_int(text.count(MARKER)).is_greater_equal(2)


# --- AC 2: the enum values ---


func test_ac02_every_enum_value_has_the_number_of_the_schema() -> void:
	if not _have_class():
		return
	for enum_name: String in Items.ENUMS:
		var expected: Dictionary = Items.ENUMS[enum_name]
		var found: Dictionary = Items.enum_map(enum_name)
		(
			assert_bool(found.is_empty())
			. override_failure_message("enum %s missing" % enum_name)
			. is_false()
		)
		for member: String in expected:
			(
				assert_int(found.get(member, -99))
				. override_failure_message("%s.%s" % [enum_name, member])
				. is_equal(expected[member])
			)


func test_ac02_no_enum_has_an_extra_or_missing_value() -> void:
	if not _have_class():
		return
	for enum_name: String in Items.ENUMS:
		var expected: Dictionary = Items.ENUMS[enum_name]
		var found: Dictionary = Items.enum_map(enum_name)
		assert_int(found.size()).override_failure_message("value count of %s" % enum_name).is_equal(
			expected.size()
		)


func test_ac02_unset_is_zero_on_every_enum() -> void:
	if not _have_class():
		return
	for enum_name: String in Items.ENUMS:
		(
			assert_int(Items.enum_value(enum_name, "UNSET"))
			. override_failure_message(enum_name)
			. is_equal(0)
		)


func test_ac02_the_two_values_for_the_moss_ball_are_pinned() -> void:
	if not _have_class():
		return
	assert_int(Items.enum_value("GrowthForm", "BALL")).is_equal(7)
	assert_int(Items.enum_value("Anchoring", "LOOSE")).is_equal(4)


func test_ac02_the_material_enum_is_not_named_like_the_builtin_material_class() -> void:
	if not _have_class():
		return
	assert_bool(Items.enum_map("Material").is_empty()).is_true()
	assert_bool(Items.enum_map("ItemMaterial").is_empty()).is_false()


# --- AC 3: types and defaults ---


func _check_block(block: Dictionary) -> void:
	var definition: Resource = Items.new_definition()
	var listed: Dictionary = Items.properties()
	for field: String in block:
		var spec: Array = block[field]
		var entry: Dictionary = listed.get(field, {})
		assert_bool(entry.is_empty()).override_failure_message("%s is missing" % field).is_false()
		if entry.is_empty():
			continue
		assert_int(entry["type"]).override_failure_message("type of %s" % field).is_equal(spec[0])
		var tag: String = spec[1]
		if spec[0] == TYPE_INT and not tag.is_empty():
			(
				assert_str(String(entry["class_name"]))
				. override_failure_message("%s is not typed as the enum %s" % [field, tag])
				. ends_with(tag)
			)
		elif spec[0] == TYPE_OBJECT:
			(
				assert_str(String(entry["hint_string"]))
				. override_failure_message("%s is not a %s" % [field, tag])
				. is_equal(tag)
			)
		(
			assert_bool(definition.get(field) == spec[2])
			. override_failure_message("default of %s is %s" % [field, definition.get(field)])
			. is_true()
		)


func test_ac03_the_mode_1_fields_have_the_stated_type_and_default() -> void:
	if _have_class():
		_check_block(Items.MODE_1)


func test_ac03_the_common_mode_2_fields_have_the_stated_type_and_default() -> void:
	if _have_class():
		_check_block(Items.COMMON)


func test_ac03_the_plant_fields_have_the_stated_type_and_default() -> void:
	if _have_class():
		_check_block(Items.PLANT)


func test_ac03_a_new_definition_is_not_a_valid_item_yet() -> void:
	if not _have_class():
		return
	var definition: Resource = Items.new_definition()
	assert_int(definition.get("category")).is_equal(0)
	assert_str(String(definition.get("id"))).is_empty()
	assert_bool(definition.get("aquarium_safe")).is_true()
