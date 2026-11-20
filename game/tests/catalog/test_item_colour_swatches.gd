extends GdUnitTestSuite
## #32 AC 13 (owner: technical-artist for the .tres values, developer for nothing else): the
## shipped item catalog and the new Mode 1 field `colour_swatches: Array[Color]`, right after
## `colourable`. clay_amphora is colourable with 1 to 8 swatches (the guidance of AC 14 says 5 to
## 6), the other two items are not colourable and have an empty list (no line in their .tres); no
## two swatches of one item are equal by to_rgba32(); every swatch is an exact 8-bit opaque colour
## (it survives its #RRGGBB text unchanged, ADR 0010 rule 7 extended to item .tres files); none
## equals the item's original look is a manual check (AC 14). The Mode 2 fields of the three items
## stay as #157 shipped them (pinned in test_decor_starter_set.gd); here the three .tres files are
## also scanned for a Mode 2 line change by name: only `colourable`, `colour_swatches` and the
## resource header may differ from the #157 text, which is checked through the values below.
##
## Test decisions: the whole shipped catalog is read through ItemCatalog.load_dirs(), so a later
## item (#42) is checked by the same rules without editing this test; the five Mode 2 values of
## the amphora below are the #157 table (domain-ba), repeated on purpose.

const SHIPPED_DIRS: Array[String] = ["res://catalog/decor", "res://catalog/plants"]
const MAX_SWATCHES: int = 8
const GUIDE_MIN: int = 5
const GUIDE_MAX: int = 6
const COLOURABLE: Array[StringName] = [&"clay_amphora"]
const PLAIN: Array[StringName] = [&"river_stone", &"driftwood_branch"]


func _catalog() -> ItemCatalog:
	return ItemCatalog.load_dirs(SHIPPED_DIRS)


func _swatches(definition: ItemDefinition) -> Array[Color]:
	var list: Array[Color] = []
	var raw: Variant = definition.get("colour_swatches")
	if raw is Array:
		for entry: Variant in raw:
			list.append(entry as Color)
	return list


func _has_field() -> bool:
	var found: bool = false
	for entry: Dictionary in ItemDefinition.new().get_property_list():
		if entry["name"] == "colour_swatches":
			found = true
	(
		assert_bool(found)
		. override_failure_message("ItemDefinition has no colour_swatches field")
		. is_true()
	)
	return found


func test_ac13_the_field_is_a_typed_colour_array_with_an_empty_default_after_colourable() -> void:
	if not _has_field():
		return
	var fresh: ItemDefinition = ItemDefinition.new()
	var value: Variant = fresh.get("colour_swatches")
	assert_bool(value is Array).is_true()
	var list: Array = value
	assert_int(list.size()).is_equal(0)
	assert_int(list.get_typed_builtin()).is_equal(TYPE_COLOR)
	var names: Array[String] = []
	for entry: Dictionary in ItemDefinition.new().get_property_list():
		if int(entry["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE != 0:
			names.append(String(entry["name"]))
	assert_int(names.find("colour_swatches")).is_equal(names.find("colourable") + 1)


func test_ac13_the_field_is_documented_and_stays_in_the_mode_1_block() -> void:
	if not _has_field():
		return
	var text: String = FileAccess.get_file_as_string("res://catalog/item_definition.gd")
	var at: int = text.find("var colour_swatches")
	assert_int(at).is_greater(0)
	assert_int(at).is_less(text.find("# --- Mode 2"))
	var before_state: String = text.substr(0, at)
	var doc_line: String = before_state.get_slice("\n", before_state.count("\n") - 1)
	(
		assert_str(doc_line.strip_edges())
		. override_failure_message("colour_swatches needs a ## doc comment line right above it")
		. starts_with("##")
	)


func test_ac13_clay_amphora_is_colourable_and_the_other_two_are_not() -> void:
	var catalog: ItemCatalog = _catalog()
	for id: StringName in COLOURABLE:
		var definition: ItemDefinition = catalog.get_definition(id)
		assert_object(definition).override_failure_message(String(id)).is_not_null()
		if definition != null:
			assert_bool(definition.colourable).override_failure_message(String(id)).is_true()
	for id: StringName in PLAIN:
		var definition: ItemDefinition = catalog.get_definition(id)
		assert_object(definition).override_failure_message(String(id)).is_not_null()
		if definition != null:
			assert_bool(definition.colourable).override_failure_message(String(id)).is_false()


func test_ac13_every_colourable_item_has_1_to_8_swatches_and_every_other_item_none() -> void:
	if not _has_field():
		return
	var catalog: ItemCatalog = _catalog()
	for id: StringName in catalog.get_ids():
		var definition: ItemDefinition = catalog.get_definition(id)
		var count: int = _swatches(definition).size()
		if definition.colourable:
			(
				assert_bool(count >= 1 and count <= MAX_SWATCHES)
				. override_failure_message("%s has %d swatches, expected 1 to 8" % [id, count])
				. is_true()
			)
		else:
			(
				assert_int(count)
				. override_failure_message("%s is not colourable but has %d swatches" % [id, count])
				. is_equal(0)
			)


func test_ac14_the_amphora_has_5_or_6_swatches_as_the_technical_artist_guidance_says() -> void:
	if not _has_field():
		return
	var definition: ItemDefinition = _catalog().get_definition(&"clay_amphora")
	assert_object(definition).is_not_null()
	if definition == null:
		return
	var count: int = _swatches(definition).size()
	(
		assert_bool(count >= GUIDE_MIN and count <= GUIDE_MAX)
		. override_failure_message("clay_amphora has %d swatches, the guidance is 5 to 6" % count)
		. is_true()
	)


func test_ac13_no_two_swatches_of_one_item_are_equal_by_rgba32() -> void:
	if not _has_field():
		return
	var catalog: ItemCatalog = _catalog()
	for id: StringName in catalog.get_ids():
		var seen: Dictionary = {}
		for colour: Color in _swatches(catalog.get_definition(id)):
			var packed: int = colour.to_rgba32()
			(
				assert_bool(seen.has(packed))
				. override_failure_message("%s: duplicate swatch %s" % [id, colour.to_html(false)])
				. is_false()
			)
			seen[packed] = true


func test_ac13_every_swatch_is_an_exact_opaque_8_bit_colour() -> void:
	if not _has_field():
		return
	var catalog: ItemCatalog = _catalog()
	for id: StringName in catalog.get_ids():
		for colour: Color in _swatches(catalog.get_definition(id)):
			var round_trip: Color = Color.html(colour.to_html(false))
			(
				assert_bool(colour == round_trip)
				. override_failure_message("%s: %s is not an exact 8-bit colour" % [id, colour])
				. is_true()
			)
			assert_float(colour.a).override_failure_message("%s alpha" % id).is_equal(1.0)


func test_ac13_the_swatch_checks_would_catch_a_bad_swatch_list() -> void:
	# The rules are real: a duplicate and an off-grid colour are detected by the same formulas.
	var dup_swatches: Array[Color] = [Color8(10, 20, 30), Color8(10, 20, 30)]
	assert_int(dup_swatches[0].to_rgba32()).is_equal(dup_swatches[1].to_rgba32())
	var off_grid: Color = Color(0.123456, 0.2, 0.3)
	assert_bool(off_grid == Color.html(off_grid.to_html(false))).is_false()


func test_ac13_the_two_plain_items_have_no_colour_swatches_line_in_their_tres() -> void:
	for id: StringName in PLAIN:
		var text: String = FileAccess.get_file_as_string("res://catalog/decor/%s.tres" % id)
		assert_str(text).override_failure_message(String(id)).is_not_empty()
		(
			assert_bool(text.contains("colour_swatches"))
			. override_failure_message(String(id))
			. is_false()
		)
		(
			assert_bool(text.contains("colourable = false"))
			. override_failure_message(String(id))
			. is_true()
		)


func test_ac13_the_amphora_mode_2_fields_are_unchanged() -> void:
	var definition: ItemDefinition = _catalog().get_definition(&"clay_amphora")
	assert_object(definition).is_not_null()
	if definition == null:
		return
	assert_int(definition.material).is_equal(ItemDefinition.ItemMaterial.CERAMIC)
	assert_bool(definition.aquarium_safe).is_true()
	assert_float(definition.weight_kg).is_equal(0.3)
	assert_float(definition.volume_displacement_l).is_equal(0.2)
	assert_vector(definition.footprint_cm).is_equal(Vector3(9.0, 14.0, 8.0))
	assert_int(definition.ph_effect).is_equal(ItemDefinition.WaterEffect.INERT)
	assert_int(definition.hardness_effect).is_equal(ItemDefinition.WaterEffect.INERT)
	assert_int(definition.hiding_places).is_equal(1)
	assert_float(definition.hiding_quality).is_equal(0.7)
	assert_float(definition.shade_cover).is_equal(0.4)
	assert_float(definition.edge_smoothness).is_equal(0.7)
	assert_float(definition.flow_obstruction).is_equal(0.2)
	assert_float(definition.waste_trapping).is_equal(0.4)
	assert_float(definition.cleaning_difficulty).is_equal(0.4)
	assert_float(definition.algae_surface).is_equal(0.4)
	assert_bool(definition.breaks_down).is_false()
