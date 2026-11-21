extends GdUnitTestSuite
## #34 AC 15 (owner: developer), ADR 0013 rule 7: SubstrateSurface.top_allowance(definition) is the
## u of ADR 0011 rule 5 by grain shape: SAND 0.0015, ANGULAR 0.003, ROUND 0.00325, PEBBLE 0.016
## metres; a null definition gives 0.0015 without any log. height_at is not changed by it.

const Api := preload("res://tests/helpers/fish_api.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")

## Shipped substrate id to the allowance of its grain shape.
const EXPECTED: Dictionary[StringName, float] = {
	&"sand_fine": 0.0015,
	&"sand_black": 0.0015,
	&"gravel_natural": 0.003,
	&"gravel_coloured": 0.00325,
	&"pebbles_river": 0.016,
}


func _definition(id: StringName) -> SubstrateDefinition:
	return SubstrateCatalog.load_dir().get_definition(id)


func test_top_allowance_follows_the_grain_shape_of_every_shipped_substrate() -> void:
	for id: StringName in EXPECTED:
		var definition: SubstrateDefinition = _definition(id)
		assert_object(definition).is_not_null()
		(
			assert_float(Api.top_allowance(definition))
			. override_failure_message("top_allowance of %s" % id)
			. is_equal_approx(EXPECTED[id], 1e-9)
		)


func test_a_null_definition_gives_the_sand_value_and_logs_nothing() -> void:
	var holder: Array[float] = []
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void: holder.append(Api.top_allowance(null))
	)
	assert_float(holder[0]).is_equal_approx(0.0015, 1e-9)
	assert_dict(seen["errors"]).is_empty()
	assert_dict(seen["warnings"]).is_empty()


func test_height_at_is_unchanged_by_the_allowance() -> void:
	var definition: SubstrateDefinition = _definition(&"pebbles_river")
	var height: float = SubstrateSurface.height_at(
		definition, PackedFloat32Array(), Vector2i.ZERO, Vector3(0.4, 0.27, 0.25), 0.1, 0.05
	)
	assert_float(height).is_equal_approx(0.06, 1e-9)
