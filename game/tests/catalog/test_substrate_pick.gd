extends GdUnitTestSuite
## #28 criterion 9 (helper part) and the support functions of the catalog (owner: developer): the
## pick rule of BA decision Q2 and the 8-bit swatch matching of ADR 0010 rule 7. The rule: picking
## the type in use keeps the colour (even a non-default swatch or a loaded non-swatch colour),
## picking another known type gives that type's default_colour, an unknown id keeps the colour (the
## Command then rejects it). The helper is called on the catalog, as the plan lists it.

const Sub := preload("res://tests/helpers/substrate_api.gd")

var _catalog: RefCounted = null


func before_test() -> void:
	_catalog = Sub.catalog()


func _pick_exists() -> bool:
	var found: bool = _catalog.has_method("colour_for_pick")
	(
		assert_bool(found)
		. override_failure_message("SubstrateCatalog.colour_for_pick is missing")
		. is_true()
	)
	return found


func _same(actual: Color, expected: Color) -> void:
	(
		assert_bool(Sub.same_colour(actual, expected))
		. override_failure_message("expected %s, got %s" % [Sub.hex(expected), Sub.hex(actual)])
		. is_true()
	)


# --- colour_for_pick ---


func test_ac09_picking_the_type_in_use_returns_the_current_default() -> void:
	if not _pick_exists():
		return
	for id: StringName in Sub.IDS:
		var current: Color = Sub.default_colour(_catalog, id)
		_same(Sub.pick(_catalog, id, current, id), current)


func test_ac09_picking_black_sand_with_a_non_default_swatch_keeps_that_swatch() -> void:
	if not _pick_exists():
		return
	var second: Color = Sub.swatch(_catalog, Sub.BLACK, 2)
	_same(Sub.pick(_catalog, Sub.BLACK, second, Sub.BLACK), second)
	assert_bool(Sub.same_colour(second, Sub.default_colour(_catalog, Sub.BLACK))).is_false()


func test_ac09_picking_the_type_in_use_keeps_a_colour_that_is_not_a_swatch() -> void:
	if not _pick_exists():
		return
	_same(Sub.pick(_catalog, Sub.SAND, Sub.NOT_A_SWATCH, Sub.SAND), Sub.NOT_A_SWATCH)


func test_ac04_picking_another_type_gives_its_default_colour_for_all_ordered_pairs() -> void:
	if not _pick_exists():
		return
	for from_id: StringName in Sub.IDS:
		for to_id: StringName in Sub.IDS:
			if from_id == to_id:
				continue
			var current: Color = Sub.default_colour(_catalog, from_id)
			_same(Sub.pick(_catalog, from_id, current, to_id), Sub.default_colour(_catalog, to_id))


func test_ac22_picking_another_type_drops_a_non_default_swatch() -> void:
	if not _pick_exists():
		return
	var third: Color = Sub.swatch(_catalog, Sub.GRAVEL, 3)
	_same(
		Sub.pick(_catalog, Sub.GRAVEL, third, Sub.PEBBLES),
		Sub.default_colour(_catalog, Sub.PEBBLES)
	)


func test_ac09_picking_another_type_from_a_non_swatch_colour_gives_the_default() -> void:
	if not _pick_exists():
		return
	_same(
		Sub.pick(_catalog, Sub.SAND, Sub.NOT_A_SWATCH, Sub.GRAVEL),
		Sub.default_colour(_catalog, Sub.GRAVEL)
	)


func test_ac10_picking_an_unknown_id_keeps_the_current_colour() -> void:
	if not _pick_exists():
		return
	var current: Color = Sub.default_colour(_catalog, Sub.SAND)
	_same(Sub.pick(_catalog, Sub.SAND, current, Sub.UNKNOWN_ID), current)
	_same(Sub.pick(_catalog, Sub.SAND, current, &""), current)


# --- is_swatch and swatch_index ---


func test_every_swatch_of_every_type_is_found_at_its_position() -> void:
	assert_bool(_catalog.has_method("swatch_index")).is_true()
	for id: StringName in Sub.IDS:
		var list: Array[Color] = Sub.swatches(_catalog, id)
		assert_int(list.size()).is_greater(1)
		for index: int in list.size():
			assert_that(Sub.swatch_index(_catalog, id, list[index])).is_equal(index)
			assert_that(Sub.is_swatch(_catalog, id, list[index])).is_equal(true)


func test_a_colour_that_is_no_swatch_has_index_minus_one() -> void:
	assert_bool(_catalog.has_method("swatch_index")).is_true()
	for id: StringName in Sub.IDS:
		assert_that(Sub.swatch_index(_catalog, id, Sub.NOT_A_SWATCH)).is_equal(-1)
		assert_that(Sub.is_swatch(_catalog, id, Sub.NOT_A_SWATCH)).is_equal(false)


func test_a_swatch_of_another_type_is_not_a_swatch_here() -> void:
	assert_bool(_catalog.has_method("is_swatch")).is_true()
	# Coloured gravel swatch 2 is a bright non-natural tone, no other type holds it.
	var bright: Color = Sub.swatch(_catalog, Sub.COLOURED, 2)
	assert_that(Sub.is_swatch(_catalog, Sub.COLOURED, bright)).is_equal(true)
	assert_that(Sub.is_swatch(_catalog, Sub.SAND, bright)).is_equal(false)


func test_an_unknown_or_empty_id_has_no_swatches() -> void:
	assert_bool(_catalog.has_method("is_swatch")).is_true()
	assert_that(Sub.is_swatch(_catalog, Sub.UNKNOWN_ID, Sub.SAND_DEFAULT)).is_equal(false)
	assert_that(Sub.is_swatch(_catalog, &"", Sub.SAND_DEFAULT)).is_equal(false)
	assert_that(Sub.swatch_index(_catalog, Sub.UNKNOWN_ID, Sub.SAND_DEFAULT)).is_equal(-1)


func test_matching_uses_8_bit_precision_like_the_save_file() -> void:
	assert_bool(_catalog.has_method("is_swatch")).is_true()
	var exact: Color = Sub.swatch(_catalog, Sub.GRAVEL, 2)
	# A float noise far below one 8-bit step must still match; a whole step must not.
	var noisy: Color = Color(exact.r + 0.0004, exact.g - 0.0004, exact.b, 1.0)
	assert_that(Sub.is_swatch(_catalog, Sub.GRAVEL, noisy)).is_equal(true)
	var one_step: Color = Color(exact.r + 1.0 / 255.0, exact.g, exact.b, 1.0)
	assert_that(Sub.is_swatch(_catalog, Sub.GRAVEL, one_step)).is_equal(false)
