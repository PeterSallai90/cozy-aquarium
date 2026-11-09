# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #24 criteria 1, 2 and 23 (owner: developer for the catalog files): the three tank entries, their
## consistency, the trim field and the Mode 2 data. #22 criteria 1 and 2 for the medium tank are
## covered by the same checks (the id is now tank_medium_1). TankDefinition and TankCatalog are
## reached through LateApi (see its header).

const Api := preload("res://tests/helpers/late_api.gd")
const Table := preload("res://tests/helpers/tank_table.gd")

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


func _catalog() -> RefCounted:
	return Api.catalog_load_dir("res://catalog/tanks")


func _definition(id: StringName) -> Resource:
	var definition: Resource = Api.definition_of(_catalog(), id)
	assert_object(definition).override_failure_message("%s not in the catalog" % id).is_not_null()
	return definition


func _fixture(id: StringName) -> Resource:
	var definition: Resource = Api.new_definition()
	definition.set("id", id)
	return definition


func _float(definition: Resource, field: String) -> float:
	return Api.prop(definition, field, Api.MISSING_NUMBER)


func _int(definition: Resource, field: String) -> int:
	return Api.prop(definition, field, -1)


func _tres_text(id: StringName) -> String:
	var path: String = Table.catalog_path(id)
	(
		assert_bool(FileAccess.file_exists(path))
		. override_failure_message("%s missing" % path)
		. is_true()
	)
	return FileAccess.get_file_as_string(path)


## True when the .tres text assigns the field on a line of its own.
func _written(text: String, field: String) -> bool:
	var pattern: RegEx = RegEx.create_from_string("(?m)^%s = " % field)
	return pattern.search(text) != null


func _property_names(object: Object) -> Array[String]:
	var names: Array[String] = []
	for property: Dictionary in object.get_property_list():
		names.append(String(property["name"]))
	return names


# --- AC 1: the set of tanks ---


func test_ac01_the_catalog_holds_exactly_three_tanks_with_unique_ids() -> void:
	var ids: Array = Api.ids_of(_catalog())
	assert_int(ids.size()).is_equal(3)
	var unique: Dictionary = {}
	for id: Variant in ids:
		unique[id] = true
	assert_int(unique.size()).is_equal(3)


func test_ac01_ordered_by_volume_they_are_small_medium_large_with_strictly_rising_volume() -> void:
	var catalog: RefCounted = _catalog()
	var found: Array[Resource] = []
	for id: Variant in Api.ids_of(catalog):
		found.append(Api.definition_of(catalog, id))
	found.sort_custom(
		func(a: Resource, b: Resource) -> bool:
			return _int(a, "volume_litres") < _int(b, "volume_litres")
	)
	var ordered: Array = []
	for definition: Resource in found:
		ordered.append(Api.prop(definition, "id", &""))
	assert_array(ordered).is_equal(Table.IDS)
	for index: int in range(1, found.size()):
		assert_int(_int(found[index], "volume_litres")).is_greater(
			_int(found[index - 1], "volume_litres")
		)


func test_ac01_no_id_holds_a_litre_value_it_is_size_class_and_variant_index() -> void:
	var pattern: RegEx = RegEx.create_from_string("^tank_(small|medium|large)_\\d+$")
	var ids: Array = Api.ids_of(_catalog())
	assert_int(ids.size()).is_greater(0)
	for id: Variant in ids:
		(
			assert_bool(pattern.search(String(id)) != null)
			. override_failure_message("%s does not match tank_(small|medium|large)_<n>" % id)
			. is_true()
		)
	for id: StringName in Table.IDS:
		assert_array(ids).contains([id])
	for old_id: StringName in [&"tank_medium_60l", &"tank_small_25l", &"tank_large_200l"]:
		assert_array(ids).not_contains([old_id])


func test_ac01_each_definition_id_matches_its_catalog_id_and_file_name() -> void:
	for id: StringName in Table.IDS:
		assert_that(Api.prop(_definition(id), "id", &"")).is_equal(id)
		assert_bool(FileAccess.file_exists(Table.catalog_path(id))).is_true()


func test_ac01_name_and_description_keys_follow_the_id_suffix() -> void:
	for id: StringName in Table.IDS:
		var definition: Resource = _definition(id)
		var suffix: String = Table.suffix(id)
		assert_str(Api.prop(definition, "name_key", "")).is_equal("tank.%s.name" % suffix)
		assert_str(Api.prop(definition, "description_key", "")).is_equal(
			"tank.%s.description" % suffix
		)


func test_ac01_each_scene_loads_and_instantiates_as_node3d() -> void:
	for id: StringName in Table.IDS:
		var scene: PackedScene = Api.prop(_definition(id), "scene", null) as PackedScene
		assert_object(scene).override_failure_message("%s has no scene" % id).is_not_null()
		if scene == null:
			continue
		assert_str(scene.resource_path).is_equal(Table.scene_path(id))
		var instance: Node = scene.instantiate()
		assert_object(instance).is_instanceof(Node3D)
		instance.free()


func test_ac01_each_tank_holds_the_interior_glass_water_line_and_volume_of_the_issue() -> void:
	for id: StringName in Table.IDS:
		var definition: Resource = _definition(id)
		var size: Vector3 = Api.prop(definition, "interior_size_m", Vector3.ZERO)
		assert_vector(size).override_failure_message("%s interior" % id).is_equal_approx(
			Table.interior(id), Vector3.ONE * 0.0001
		)
		assert_float(_float(definition, "glass_thickness_m")).is_equal_approx(
			Table.glass(id), 0.00001
		)
		assert_float(_float(definition, "water_line_height_m")).is_equal_approx(
			Table.water_line(id), 0.0001
		)
		assert_int(_int(definition, "volume_litres")).is_equal(Table.row(id)["litres"])


func test_ac01_the_water_line_is_below_the_interior_height_by_the_2_cm_freeboard() -> void:
	for id: StringName in Table.IDS:
		var definition: Resource = _definition(id)
		var interior: Vector3 = Api.prop(definition, "interior_size_m", Vector3.ZERO)
		assert_float(_float(definition, "water_line_height_m")).is_less(interior.y)
		assert_float(interior.y - _float(definition, "water_line_height_m")).is_equal_approx(
			0.02, 0.0001
		)


func test_ac01_exterior_and_water_volume_helpers() -> void:
	for id: StringName in Table.IDS:
		var definition: Resource = _definition(id)
		var exterior: Vector3 = Api.call_on(definition, "get_exterior_size_m", [], Vector3.ZERO)
		var water: Vector3 = Api.call_on(definition, "get_water_volume_size_m", [], Vector3.ZERO)
		assert_vector(exterior).is_equal_approx(Table.exterior(id), Vector3.ONE * 0.0001)
		var interior: Vector3 = Table.interior(id)
		assert_vector(water).is_equal_approx(
			Vector3(interior.x, Table.water_line(id), interior.z), Vector3.ONE * 0.0001
		)


func test_ac01_the_exterior_does_not_count_the_trim() -> void:
	# Medium: 0.355 high without the trim (0.365 with it), as delivered in #22.
	var exterior: Vector3 = Api.call_on(
		_definition(Table.MEDIUM), "get_exterior_size_m", [], Vector3.ZERO
	)
	assert_float(exterior.y).is_equal_approx(0.355, 0.0001)


func test_ac01_every_mode_2_field_exists() -> void:
	var names: Array[String] = _property_names(_definition(Table.MEDIUM))
	for field: String in MODE_2_FIELDS:
		assert_array(names).override_failure_message("missing field %s" % field).contains([field])


func test_ac01_every_mode_2_field_is_written_explicitly_in_each_tres() -> void:
	for id: StringName in Table.IDS:
		var text: String = _tres_text(id)
		for field: String in MODE_2_FIELDS:
			(
				assert_bool(_written(text, field))
				. override_failure_message("%s does not write %s explicitly" % [id, field])
				. is_true()
			)


func test_ac01_mode_2_fields_hold_plausible_values_above_zero() -> void:
	for id: StringName in Table.IDS:
		var definition: Resource = _definition(id)
		assert_float(_float(definition, "empty_weight_kg")).is_greater(0.0)
		assert_float(_float(definition, "evaporation_l_per_day")).is_greater(0.0)
		assert_float(_float(definition, "heat_loss_factor")).is_greater(0.0)
		for field: String in [
			"heater_slots",
			"filter_slots",
			"light_slots",
			"recommended_heater_watts",
			"recommended_filter_lph"
		]:
			(
				assert_int(_int(definition, field))
				. override_failure_message("%s %s must be above 0" % [id, field])
				. is_greater(0)
			)


func test_ac01_mode_2_fields_hold_the_domain_ba_values() -> void:
	for id: StringName in Table.IDS:
		var definition: Resource = _definition(id)
		var row: Dictionary = Table.row(id)
		assert_float(_float(definition, "empty_weight_kg")).is_equal_approx(row["weight"], 0.0001)
		assert_float(_float(definition, "heat_loss_factor")).is_equal_approx(
			row["heat_loss"], 0.0001
		)
		assert_float(_float(definition, "evaporation_l_per_day")).is_equal_approx(
			row["evaporation"], 0.0001
		)
		assert_int(_int(definition, "heater_slots")).is_equal(row["heater_slots"])
		assert_int(_int(definition, "filter_slots")).is_equal(row["filter_slots"])
		assert_int(_int(definition, "light_slots")).is_equal(row["light_slots"])
		assert_int(_int(definition, "recommended_heater_watts")).is_equal(row["heater_watts"])
		assert_int(_int(definition, "recommended_filter_lph")).is_equal(row["filter_lph"])
		assert_bool(Api.prop(definition, "has_lid", true)).is_false()


func test_ac01_one_lamp_per_tank_even_with_two_heater_slots() -> void:
	for id: StringName in Table.IDS:
		assert_int(_int(_definition(id), "light_slots")).is_equal(1)


# --- AC 2 ---


func test_ac02_volume_from_interior_size_and_water_line_is_within_2_percent() -> void:
	for id: StringName in Table.IDS:
		var definition: Resource = _definition(id)
		var interior: Vector3 = Api.prop(definition, "interior_size_m", Vector3.ZERO)
		var litres: float = (
			interior.x * interior.z * _float(definition, "water_line_height_m") * 1000.0
		)
		var nominal: float = float(_int(definition, "volume_litres"))
		assert_float(litres).is_greater(0.0)
		(
			assert_float(absf(litres - nominal) / nominal)
			. override_failure_message("%s: %.2f L against %s L" % [id, litres, nominal])
			. is_less_equal(0.02)
		)


# --- AC 23: the trim field and the furniture scenes ---


func test_ac23_trim_size_m_is_a_field_of_the_definition() -> void:
	assert_array(_property_names(Api.new_definition())).contains(["trim_size_m"])


func test_ac23_trim_size_m_is_001_on_all_three_tanks_and_written_in_the_tres() -> void:
	for id: StringName in Table.IDS:
		(
			assert_float(_float(_definition(id), "trim_size_m"))
			. override_failure_message("%s trim_size_m" % id)
			. is_equal_approx(Table.TRIM_M, 0.00001)
		)
		assert_bool(_written(_tres_text(id), "trim_size_m")).is_true()


func test_ac23_trim_is_at_least_the_glass_and_below_a_quarter_of_the_depth() -> void:
	for id: StringName in Table.IDS:
		var definition: Resource = _definition(id)
		var trim: float = _float(definition, "trim_size_m")
		var depth: float = (Api.prop(definition, "interior_size_m", Vector3.ZERO) as Vector3).z
		assert_float(trim).is_greater_equal(_float(definition, "glass_thickness_m"))
		assert_float(trim).is_less(depth / 4.0)


func test_ac23_no_mode_2_field_was_removed_or_renamed() -> void:
	var names: Array[String] = _property_names(Api.new_definition())
	for field: String in MODE_2_FIELDS:
		assert_array(names).override_failure_message("Mode 2 field %s is gone" % field).contains(
			[field]
		)
	for field: String in [
		"id",
		"name_key",
		"description_key",
		"scene",
		"interior_size_m",
		"volume_litres",
		"glass_thickness_m",
		"water_line_height_m"
	]:
		assert_array(names).contains([field])


func test_ac23_the_definition_names_its_cabinet_and_lamp_scenes() -> void:
	# Plan section 2: the room finds the furniture of a tank through catalog data.
	for id: StringName in Table.IDS:
		var definition: Resource = _definition(id)
		var cabinet: PackedScene = Api.prop(definition, "cabinet_scene", null) as PackedScene
		var lamp: PackedScene = Api.prop(definition, "lamp_scene", null) as PackedScene
		(
			assert_object(cabinet)
			. override_failure_message("%s has no cabinet_scene" % id)
			. is_not_null()
		)
		assert_object(lamp).override_failure_message("%s has no lamp_scene" % id).is_not_null()
		if cabinet != null:
			var node: Node = cabinet.instantiate()
			assert_object(node).is_instanceof(Node3D)
			node.free()
		if lamp != null:
			assert_str(lamp.resource_path).is_equal(Table.lamp_scene_path(id))
			var node: Node = lamp.instantiate()
			assert_object(node).is_instanceof(Node3D)
			node.free()


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


func test_catalog_has_no_alias_for_the_old_medium_id() -> void:
	# Owner decision 2026-11-09: no alias; the old id is an unknown id (the #22 fallback).
	assert_object(Api.definition_of(_catalog(), &"tank_medium_60l")).is_null()
