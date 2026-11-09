extends GdUnitTestSuite
## #23 criterion 8 (owner: developer): the water and glass shading story adds no field to
## TankDefinition, and every Mode 2 field stays. The exact property list is pinned, so a new,
## renamed or dropped field fails here.

const Table := preload("res://tests/helpers/tank_table.gd")
const Api := preload("res://tests/helpers/late_api.gd")

const MODE_1_FIELDS: Array[String] = [
	"id",
	"name_key",
	"description_key",
	"scene",
	"interior_size_m",
	"volume_litres",
	"glass_thickness_m",
	"water_line_height_m",
	"trim_size_m",
	"cabinet_scene",
	"lamp_scene",
]

const MODE_2_FIELDS: Array[String] = [
	"empty_weight_kg",
	"heat_loss_factor",
	"evaporation_l_per_day",
	"heater_slots",
	"filter_slots",
	"light_slots",
	"recommended_heater_watts",
	"recommended_filter_lph",
	"has_lid",
]


func _fields() -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	var script: GDScript = load(Api.DEFINITION_PATH) as GDScript
	for entry: Dictionary in script.get_script_property_list():
		var usage: int = int(entry["usage"])
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE != 0 and usage & PROPERTY_USAGE_STORAGE != 0:
			names.append(entry["name"])
	return names


func test_ac08_tank_definition_has_exactly_the_known_fields() -> void:
	var expected: PackedStringArray = PackedStringArray()
	expected.append_array(MODE_1_FIELDS)
	expected.append_array(MODE_2_FIELDS)
	var actual: PackedStringArray = _fields()
	actual.sort()
	expected.sort()
	(
		assert_array(Array(actual))
		. override_failure_message(
			"TankDefinition fields changed.\nexpected: %s\nactual: %s" % [expected, actual]
		)
		. is_equal(Array(expected))
	)


func test_ac08_every_mode_2_field_still_exists() -> void:
	var actual: PackedStringArray = _fields()
	for field: String in MODE_2_FIELDS:
		(
			assert_bool(field in actual)
			. override_failure_message("Mode 2 field gone: %s" % field)
			. is_true()
		)


func test_ac08_the_water_volume_size_still_comes_from_interior_and_water_line() -> void:
	for id: StringName in Table.IDS:
		var definition: TankDefinition = (
			Api.definition_of(Api.catalog_load_dir(), id) as TankDefinition
		)
		(
			assert_object(definition)
			. override_failure_message("%s not in the catalog" % id)
			. is_not_null()
		)
		if definition == null:
			continue
		var inner: Vector3 = definition.interior_size_m
		(
			assert_vector(definition.get_water_volume_size_m())
			. override_failure_message(str(id))
			. is_equal(Vector3(inner.x, definition.water_line_height_m, inner.z))
		)


func test_ac08_the_catalog_values_of_the_three_tanks_are_unchanged() -> void:
	for id: StringName in Table.IDS:
		var definition: TankDefinition = (
			Api.definition_of(Api.catalog_load_dir(), id) as TankDefinition
		)
		if definition == null:
			fail("%s not in the catalog" % id)
			continue
		var row: Dictionary = Table.row(id)
		assert_vector(definition.interior_size_m).override_failure_message(str(id)).is_equal_approx(
			row["interior"], Vector3.ONE * 0.0001
		)
		(
			assert_float(definition.water_line_height_m)
			. override_failure_message(str(id))
			. is_equal_approx(row["water_line"], 0.0001)
		)
		(
			assert_float(definition.glass_thickness_m)
			. override_failure_message(str(id))
			. is_equal_approx(row["glass"], 0.0001)
		)
		assert_int(definition.volume_litres).override_failure_message(str(id)).is_equal(
			row["litres"]
		)
