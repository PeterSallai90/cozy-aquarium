extends GdUnitTestSuite
## #126 criterion 7 (owner: developer): the caustics story adds no field to TankDefinition, no
## property name contains "caustic", and every Mode 2 field stays. The exported property names
## are pinned to the list at d74d147 (develop before #126).

const Api := preload("res://tests/helpers/late_api.gd")

const SNAPSHOT: Array[String] = [
	"cabinet_scene",
	"description_key",
	"empty_weight_kg",
	"evaporation_l_per_day",
	"filter_slots",
	"glass_thickness_m",
	"has_lid",
	"heat_loss_factor",
	"heater_slots",
	"id",
	"interior_size_m",
	"lamp_scene",
	"light_slots",
	"name_key",
	"recommended_filter_lph",
	"recommended_heater_watts",
	"scene",
	"trim_size_m",
	"volume_litres",
	"water_line_height_m",
]

const MODE_2_FIELDS: Array[String] = [
	"volume_litres",
	"glass_thickness_m",
	"water_line_height_m",
	"interior_size_m",
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


func _exported() -> Array[String]:
	var names: Array[String] = []
	var script: GDScript = load(Api.DEFINITION_PATH) as GDScript
	for entry: Dictionary in script.get_script_property_list():
		var usage: int = int(entry["usage"])
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE != 0 and usage & PROPERTY_USAGE_STORAGE != 0:
			names.append(String(entry["name"]))
	names.sort()
	return names


func test_ac07_the_exported_property_names_equal_the_snapshot() -> void:
	assert_array(_exported()).is_equal(SNAPSHOT)


func test_ac07_no_tank_definition_property_name_contains_caustic() -> void:
	for property: String in _exported():
		assert_bool(property.contains("caustic")).override_failure_message(property).is_false()


func test_ac07_every_mode_2_field_still_exists() -> void:
	var names: Array[String] = _exported()
	for field: String in MODE_2_FIELDS:
		(
			assert_bool(field in names)
			. override_failure_message("Mode 2 field gone: " + field)
			. is_true()
		)
