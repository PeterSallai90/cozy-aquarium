extends GdUnitTestSuite
## #22 criteria 1, 2 and 16 (owner: developer): the tank catalog entry, its consistency and its
## translations. TankDefinition and TankCatalog are reached through LateApi (see its header).

const Api := preload("res://tests/helpers/late_api.gd")

const TANK_ID := &"tank_medium_60l"
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

var _saved_locale: String = ""


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()


func after_test() -> void:
	TranslationServer.set_locale(_saved_locale)


func _medium() -> Resource:
	var definition: Resource = Api.definition_of(Api.catalog_load_dir(), TANK_ID)
	(
		assert_object(definition)
		. override_failure_message("tank_medium_60l not in catalog")
		. is_not_null()
	)
	return definition


func _fixture(id: StringName) -> Resource:
	var definition: Resource = Api.new_definition()
	definition.set("id", id)
	return definition


func _float(definition: Resource, field: String) -> float:
	return Api.prop(definition, field, Api.MISSING_NUMBER)


func _int(definition: Resource, field: String) -> int:
	return Api.prop(definition, field, -1)


# --- AC 1 ---


func test_ac01_medium_tank_exists_in_the_catalog_directory() -> void:
	var catalog: RefCounted = Api.catalog_load_dir("res://catalog/tanks")
	assert_array(Api.ids_of(catalog)).contains([TANK_ID])
	assert_object(Api.definition_of(catalog, TANK_ID)).is_not_null()


func test_ac01_definition_id_matches_the_catalog_id() -> void:
	assert_that(Api.prop(_medium(), "id", &"")).is_equal(TANK_ID)


func test_ac01_name_and_description_keys_are_set() -> void:
	var definition: Resource = _medium()
	assert_str(Api.prop(definition, "name_key", "")).is_equal("tank.medium_60l.name")
	assert_str(Api.prop(definition, "description_key", "")).is_equal("tank.medium_60l.description")


func test_ac01_scene_loads_and_instantiates_as_node3d() -> void:
	var scene: PackedScene = Api.prop(_medium(), "scene", null) as PackedScene
	assert_object(scene).is_not_null()
	if scene == null:
		return
	var instance: Node = scene.instantiate()
	assert_object(instance).is_instanceof(Node3D)
	instance.free()


func test_ac01_interior_size_is_60_by_35_by_30_cm() -> void:
	var size: Vector3 = Api.prop(_medium(), "interior_size_m", Vector3.ZERO)
	assert_float(size.x).is_equal_approx(0.60, 0.0001)
	assert_float(size.y).is_equal_approx(0.35, 0.0001)
	assert_float(size.z).is_equal_approx(0.30, 0.0001)


func test_ac01_glass_water_line_and_volume() -> void:
	var definition: Resource = _medium()
	assert_float(_float(definition, "glass_thickness_m")).is_equal_approx(0.005, 0.00001)
	assert_float(_float(definition, "water_line_height_m")).is_equal_approx(0.33, 0.0001)
	var interior: Vector3 = Api.prop(definition, "interior_size_m", Vector3.ZERO)
	assert_float(_float(definition, "water_line_height_m")).is_less(interior.y)
	assert_int(_int(definition, "volume_litres")).is_equal(60)


func test_ac01_every_mode_2_field_exists() -> void:
	var definition: Resource = _medium()
	var names: Array[String] = []
	for property: Dictionary in definition.get_property_list():
		names.append(String(property["name"]))
	for field: String in MODE_2_FIELDS:
		assert_array(names).override_failure_message("missing field %s" % field).contains([field])


func test_ac01_mode_2_fields_hold_the_issue_values() -> void:
	var definition: Resource = _medium()
	assert_float(_float(definition, "empty_weight_kg")).is_equal_approx(8.0, 0.0001)
	assert_float(_float(definition, "heat_loss_factor")).is_equal_approx(1.0, 0.0001)
	assert_float(_float(definition, "evaporation_l_per_day")).is_equal_approx(0.5, 0.0001)
	assert_int(_int(definition, "heater_slots")).is_equal(1)
	assert_int(_int(definition, "filter_slots")).is_equal(1)
	assert_int(_int(definition, "light_slots")).is_equal(1)
	assert_int(_int(definition, "recommended_heater_watts")).is_equal(50)
	assert_int(_int(definition, "recommended_filter_lph")).is_equal(240)
	assert_bool(Api.prop(definition, "has_lid", true)).is_false()


func test_ac01_exterior_and_water_volume_helpers() -> void:
	var definition: Resource = _medium()
	var exterior: Vector3 = Api.call_on(definition, "get_exterior_size_m", [], Vector3.ZERO)
	var water: Vector3 = Api.call_on(definition, "get_water_volume_size_m", [], Vector3.ZERO)
	assert_vector(exterior).is_equal_approx(Vector3(0.61, 0.355, 0.31), Vector3.ONE * 0.0001)
	assert_vector(water).is_equal_approx(Vector3(0.60, 0.33, 0.30), Vector3.ONE * 0.0001)


# --- AC 2 ---


func test_ac02_volume_from_interior_size_and_water_line_is_within_2_percent() -> void:
	var definition: Resource = _medium()
	var interior: Vector3 = Api.prop(definition, "interior_size_m", Vector3.ZERO)
	var litres: float = interior.x * interior.z * _float(definition, "water_line_height_m") * 1000.0
	var nominal: float = float(_int(definition, "volume_litres"))
	assert_float(litres).is_greater(0.0)
	assert_float(absf(litres - nominal) / nominal).is_less_equal(0.02)


# --- catalog API ---


func test_catalog_from_definitions_finds_each_id_and_lists_them() -> void:
	var first: Resource = _fixture(&"tank_a")
	var second: Resource = _fixture(&"tank_b")
	var catalog: RefCounted = Api.catalog_from([first, second])
	assert_object(Api.definition_of(catalog, &"tank_a")).is_same(first)
	assert_object(Api.definition_of(catalog, &"tank_b")).is_same(second)
	assert_array(Api.ids_of(catalog)).contains_exactly_in_any_order([&"tank_a", &"tank_b"])


func test_catalog_unknown_and_empty_ids_return_null() -> void:
	var catalog: RefCounted = Api.catalog_from([_fixture(&"tank_a")])
	assert_bool(catalog.has_method("get_definition")).is_true()
	assert_object(Api.definition_of(catalog, &"no_such_tank")).is_null()
	assert_object(Api.definition_of(catalog, &"")).is_null()


func test_catalog_from_no_definitions_is_empty() -> void:
	var catalog: RefCounted = Api.catalog_from([])
	assert_bool(catalog.has_method("get_ids")).is_true()
	assert_int(Api.ids_of(catalog).size()).is_equal(0)


# --- AC 16 ---


func test_ac16_name_and_description_are_translated_in_english() -> void:
	TranslationServer.set_locale("en")
	var definition: Resource = _medium()
	var description_key: String = Api.prop(definition, "description_key", "")
	assert_str(tr(Api.prop(definition, "name_key", ""))).is_equal("Medium tank")
	assert_str(tr(description_key)).is_not_empty()
	assert_str(tr(description_key)).is_not_equal(description_key)


func test_ac16_name_and_description_are_translated_in_hungarian() -> void:
	TranslationServer.set_locale("hu")
	var definition: Resource = _medium()
	var description_key: String = Api.prop(definition, "description_key", "")
	assert_str(tr(Api.prop(definition, "name_key", ""))).is_equal("Közepes akvárium")
	assert_str(tr(description_key)).is_not_empty()
	assert_str(tr(description_key)).is_not_equal(description_key)


func test_ac16_hungarian_description_differs_from_english() -> void:
	var description_key: String = Api.prop(_medium(), "description_key", "")
	TranslationServer.set_locale("en")
	var english: String = tr(description_key)
	TranslationServer.set_locale("hu")
	assert_str(tr(description_key)).is_not_equal(english)
