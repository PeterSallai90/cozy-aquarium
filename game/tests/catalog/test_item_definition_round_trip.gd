extends GdUnitTestSuite
## #152 criteria 9 and 10 (owner: developer): no Mode 2 field is dropped, renamed or rounded by a
## save and load of the resource, and fields that do not apply to a kind keep their defaults.

const Items := preload("res://tests/helpers/item_api.gd")
const ROUND_ITEM := "res://tests/fixtures/items/round_trip/round_item.tres"
const SAVED := "user://item_round_trip_test.tres"
## The only field that stays at its default in the round-trip fixture: an unsafe item would be
## skipped by the catalog, and the loader is not what this suite exercises.
const KEPT_AT_DEFAULT: Array[String] = ["aquarium_safe"]


func after_test() -> void:
	if FileAccess.file_exists(SAVED):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVED))


func _have_class() -> bool:
	var ok: bool = Items.script_exists(Items.DEFINITION_PATH)
	assert_bool(ok).override_failure_message("ItemDefinition does not exist").is_true()
	return ok


func _have(cat: RefCounted) -> bool:
	var ok: bool = Items.has_api(cat)
	assert_bool(ok).override_failure_message("ItemCatalog or its API is missing").is_true()
	return ok


func _equal(a: Variant, b: Variant) -> bool:
	return typeof(a) == typeof(b) and a == b


# --- AC 9: the round trip ---


func test_ac09_the_fixture_has_a_non_default_value_in_every_mode_2_field() -> void:
	if not _have_class():
		return
	var fixture: Resource = load(ROUND_ITEM) as Resource
	assert_object(fixture).is_not_null()
	var fresh: Resource = Items.new_definition()
	for block: Dictionary in [Items.COMMON, Items.PLANT]:
		for field: String in block:
			if KEPT_AT_DEFAULT.has(field):
				continue
			(
				assert_bool(_equal(fixture.get(field), fresh.get(field)))
				. override_failure_message("%s is at its default in the fixture" % field)
				. is_false()
			)


func test_ac13_the_fixture_has_non_default_colour_swatches_that_survive_a_save() -> void:
	if not _have_class():
		return
	var fixture: Resource = load(ROUND_ITEM) as Resource
	assert_object(fixture).is_not_null()
	if fixture == null:
		return
	var raw: Variant = fixture.get("colour_swatches")
	assert_bool(raw is Array).override_failure_message("colour_swatches is missing").is_true()
	if not raw is Array:
		return
	var swatches: Array = raw
	assert_int(swatches.size()).override_failure_message("colour_swatches").is_equal(2)
	assert_int(ResourceSaver.save(fixture.duplicate() as Resource, SAVED)).is_equal(OK)
	var loaded: Resource = ResourceLoader.load(SAVED, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_object(loaded).is_not_null()
	if loaded == null:
		return
	var back: Array = loaded.get("colour_swatches") as Array
	assert_int(back.size()).is_equal(2)
	for index: int in swatches.size():
		assert_bool((back[index] as Color).is_equal_approx(swatches[index] as Color)).is_true()


func test_ac09_every_enum_field_of_the_fixture_is_not_unset() -> void:
	if not _have_class():
		return
	var fixture: Resource = load(ROUND_ITEM) as Resource
	assert_object(fixture).is_not_null()
	if fixture == null:
		return
	for block: Dictionary in [Items.MODE_1, Items.COMMON, Items.PLANT]:
		for field: String in block:
			var spec: Array = block[field]
			if spec[0] == TYPE_INT and not String(spec[1]).is_empty():
				(
					assert_int(fixture.get(field))
					. override_failure_message("%s is UNSET" % field)
					. is_not_equal(0)
				)


func test_ac09_every_value_survives_save_and_load() -> void:
	if not _have_class():
		return
	var fixture: Resource = load(ROUND_ITEM) as Resource
	assert_object(fixture).is_not_null()
	if fixture == null:
		return
	# The fixture keeps aquarium_safe at its default (the catalog skips unsafe items), so the
	# non-default value is set on a copy that never goes through the catalog.
	var original: Resource = fixture.duplicate() as Resource
	original.set("aquarium_safe", false)
	assert_bool(original.get("aquarium_safe")).is_false()
	assert_int(ResourceSaver.save(original, SAVED)).is_equal(OK)
	var loaded: Resource = ResourceLoader.load(SAVED, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_object(loaded).is_not_null()
	if loaded == null:
		return
	assert_bool(loaded != original).is_true()
	var names: Array[String] = Items.property_names()
	assert_int(names.size()).is_equal(Items.all_field_names().size())
	for field: String in names:
		(
			assert_bool(_equal(original.get(field), loaded.get(field)))
			. override_failure_message(
				"%s: %s became %s" % [field, original.get(field), loaded.get(field)]
			)
			. is_true()
		)


func test_ac09_the_fixture_values_are_the_ones_in_the_file() -> void:
	if not _have_class():
		return
	var item: Resource = load(ROUND_ITEM) as Resource
	assert_object(item).is_not_null()
	if item == null:
		return
	assert_float(item.get("weight_kg")).is_equal(0.37)
	assert_that(item.get("footprint_cm")).is_equal(Vector3(12.37, 21.13, 9.07))
	assert_int(item.get("growth_form")).is_equal(Items.enum_value("GrowthForm", "BALL"))
	assert_int(item.get("anchoring")).is_equal(Items.enum_value("Anchoring", "LOOSE"))
	assert_int(item.get("hardness_effect")).is_equal(Items.enum_value("WaterEffect", "LOWERS"))
	assert_bool(item.get("provides_cover")).is_true()


func test_ac09_the_catalog_keeps_the_round_trip_item_with_every_value() -> void:
	var cat: RefCounted = Items.fixture("round_trip")
	if not _have(cat):
		return
	var from_file: Resource = load(ROUND_ITEM) as Resource
	var from_catalog: Resource = Items.definition(cat, &"round_item")
	assert_object(from_catalog).is_not_null()
	if from_catalog == null or from_file == null:
		return
	for field: String in Items.property_names():
		(
			assert_bool(_equal(from_file.get(field), from_catalog.get(field)))
			. override_failure_message(field)
			. is_true()
		)


# --- AC 10: fields that do not apply keep their defaults ---


func test_ac10_a_rock_with_every_plant_field_at_its_default_loads_and_keeps_its_values() -> void:
	var cat: RefCounted = Items.fixture("valid")
	if not _have(cat):
		return
	var rock: Resource = Items.definition(cat, &"rock_minimal")
	assert_object(rock).is_not_null()
	if rock == null:
		return
	var fresh: Resource = Items.new_definition()
	for field: String in Items.PLANT:
		(
			assert_bool(_equal(rock.get(field), fresh.get(field)))
			. override_failure_message("plant field %s of a rock" % field)
			. is_true()
		)
	assert_float(rock.get("weight_kg")).is_equal(3.0)
	assert_float(rock.get("volume_displacement_l")).is_equal(1.2)
	assert_that(rock.get("footprint_cm")).is_equal(Vector3(25, 12, 18))
	assert_int(rock.get("ph_effect")).is_equal(Items.enum_value("WaterEffect", "RAISES_SLIGHTLY"))
	assert_int(rock.get("hiding_places")).is_equal(1)
	assert_float(rock.get("hiding_quality")).is_equal(0.4)


func test_ac10_a_plant_with_only_the_plant_block_and_the_minimum_loads_and_keeps_its_values(
) -> void:
	var cat: RefCounted = Items.fixture("valid")
	if not _have(cat):
		return
	var plant: Resource = Items.definition(cat, &"plant_minimal")
	assert_object(plant).is_not_null()
	if plant == null:
		return
	assert_int(plant.get("material")).is_equal(Items.enum_value("ItemMaterial", "LIVE_PLANT"))
	assert_that(plant.get("footprint_cm")).is_equal(Vector3(10, 20, 10))
	assert_int(plant.get("growth_form")).is_equal(Items.enum_value("GrowthForm", "STEM"))
	assert_int(plant.get("anchoring")).is_equal(Items.enum_value("Anchoring", "ROOTED"))
	assert_int(plant.get("light_need")).is_equal(Items.enum_value("LightNeed", "MODERATE"))
	assert_float(plant.get("max_height_cm")).is_equal(40.0)
	assert_float(plant.get("temp_min_c")).is_equal(20.0)
	assert_float(plant.get("ph_max")).is_equal(7.5)
	assert_bool(plant.get("provides_cover")).is_true()


func test_ac10_a_plant_keeps_the_common_fields_it_does_not_use_at_their_defaults() -> void:
	var cat: RefCounted = Items.fixture("valid")
	if not _have(cat):
		return
	var plant: Resource = Items.definition(cat, &"plant_minimal")
	assert_object(plant).is_not_null()
	if plant == null:
		return
	assert_float(plant.get("weight_kg")).is_equal(0.0)
	assert_int(plant.get("hiding_places")).is_equal(0)
	assert_bool(plant.get("breaks_down")).is_false()
	assert_bool(plant.get("aquarium_safe")).is_true()
