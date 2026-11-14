extends GdUnitTestSuite
## #28 criteria 3 and 11 (model level; owner: developer): SubstrateSetup, the one place that writes
## the substrate outside a Command (ADR 0010). apply_default gives a new model Sand and its catalog
## default colour; normalise replaces an empty or unknown id by that default with exactly one
## warning and returns true, and leaves a known id alone, a non-swatch colour or white included,
## without any output. The model itself stays catalog-free: a bare model has no substrate id and
## white (asserted in test_aquarium_model.gd).

const Sub := preload("res://tests/helpers/substrate_api.gd")
const Recorder := preload("res://tests/helpers/signal_recorder.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")
const ErrorContains := preload("res://tests/helpers/error_contains.gd")

var _catalog: RefCounted = null


func before_test() -> void:
	_catalog = Sub.catalog()


func _setup_exists() -> bool:
	var found: bool = Sub.setup_exists()
	(
		assert_bool(found)
		. override_failure_message("res://model/substrate_setup.gd is missing")
		. is_true()
	)
	return found


func _model(id: StringName, colour: Color) -> AquariumModel:
	var model: AquariumModel = AquariumModel.new(Sub.STAMP)
	model.apply_set_substrate(id, colour)
	return model


# --- AC 3: the default ---


func test_ac03_apply_default_gives_sand_with_the_decided_cream() -> void:
	if not _setup_exists():
		return
	var model: AquariumModel = AquariumModel.new(Sub.STAMP)
	assert_bool(Sub.apply_default(model, _catalog)).is_true()
	assert_that(model.get_substrate_id()).is_equal(Sub.SAND)
	assert_bool(Sub.same_colour(model.get_substrate_colour(), Sub.SAND_DEFAULT)).is_true()


func test_ac03_apply_default_uses_the_catalog_default_colour() -> void:
	if not _setup_exists():
		return
	var model: AquariumModel = AquariumModel.new(Sub.STAMP)
	Sub.apply_default(model, _catalog)
	(
		assert_bool(
			Sub.same_colour(model.get_substrate_colour(), Sub.default_colour(_catalog, Sub.SAND))
		)
		. is_true()
	)


func test_ac03_apply_default_emits_one_substrate_changed_and_touches_nothing_else() -> void:
	if not _setup_exists():
		return
	var model: AquariumModel = AquariumModel.new(Sub.STAMP)
	var recorder: Recorder = Recorder.new()
	recorder.watch(model)
	Sub.apply_default(model, _catalog)
	assert_array(recorder.names()).is_equal(["substrate_changed"])
	assert_int(model.get_item_count()).is_equal(0)
	assert_int(model.get_fish_count()).is_equal(0)


func test_ac03_a_bare_model_still_starts_without_a_catalog_id() -> void:
	var model: AquariumModel = AquariumModel.new(Sub.STAMP)
	assert_that(model.get_substrate_id()).is_equal(&"")
	assert_that(model.get_substrate_colour()).is_equal(Color.WHITE)


# --- AC 11: normalise ---


func test_ac11_an_unknown_id_becomes_sand_with_one_warning_and_returns_true() -> void:
	if not _setup_exists():
		return
	var model: AquariumModel = _model(Sub.UNKNOWN_ID, Sub.NOT_A_SWATCH)
	var seen: Dictionary = await EngineOutput.capture_result(
		func() -> Variant: return Sub.normalise(model, _catalog)
	)
	assert_that(seen["result"]).is_equal(true)
	assert_that(model.get_substrate_id()).is_equal(Sub.SAND)
	assert_bool(Sub.same_colour(model.get_substrate_colour(), Sub.SAND_DEFAULT)).is_true()
	var warnings: Dictionary = seen["warnings"]
	assert_int(warnings.size()).is_equal(1)
	var text: String = str(warnings.keys()[0])
	assert_str(text).contains(Sub.WARN_UNKNOWN_ID)
	assert_str(text).contains(String(Sub.UNKNOWN_ID))
	assert_int(int(warnings.values()[0])).is_equal(1)
	assert_dict(seen["errors"]).is_empty()


func test_ac11_an_empty_id_becomes_sand_with_one_warning() -> void:
	if not _setup_exists():
		return
	var model: AquariumModel = _model(&"", Color.WHITE)
	var seen: Dictionary = await EngineOutput.capture_result(
		func() -> Variant: return Sub.normalise(model, _catalog)
	)
	assert_that(seen["result"]).is_equal(true)
	assert_that(model.get_substrate_id()).is_equal(Sub.SAND)
	assert_bool(Sub.same_colour(model.get_substrate_colour(), Sub.SAND_DEFAULT)).is_true()
	var warnings: Dictionary = seen["warnings"]
	assert_int(warnings.size()).is_equal(1)
	assert_str(str(warnings.keys()[0])).contains(Sub.WARN_UNKNOWN_ID)


func test_ac11_the_warning_matches_the_stable_substring_of_the_plan() -> void:
	if not _setup_exists():
		return
	var model: AquariumModel = _model(Sub.UNKNOWN_ID, Color.WHITE)
	var result: Array = []
	await (
		assert_error(func() -> void: result.append(Sub.normalise(model, _catalog)))
		. is_push_warning(ErrorContains.new(Sub.WARN_UNKNOWN_ID))
	)
	assert_array(result).is_equal([true])


func test_ac11_normalise_adds_no_history_and_no_other_change() -> void:
	if not _setup_exists():
		return
	var model: AquariumModel = Sub.furnished(Sub.UNKNOWN_ID, Color.WHITE)
	var items: int = model.get_item_count()
	var fish: int = model.get_fish_count()
	var heights: PackedFloat32Array = model.get_heightmap()
	var tank: StringName = model.get_tank_id()
	await EngineOutput.capture(func() -> void: Sub.normalise(model, _catalog))
	assert_int(model.get_item_count()).is_equal(items)
	assert_int(model.get_fish_count()).is_equal(fish)
	assert_that(model.get_heightmap()).is_equal(heights)
	assert_that(model.get_tank_id()).is_equal(tank)


func test_ac11_a_known_id_with_a_non_swatch_colour_is_kept_silently() -> void:
	if not _setup_exists():
		return
	var model: AquariumModel = _model(Sub.SAND, Sub.NOT_A_SWATCH)
	var seen: Dictionary = await EngineOutput.capture_result(
		func() -> Variant: return Sub.normalise(model, _catalog)
	)
	assert_that(seen["result"]).is_equal(false)
	assert_that(model.get_substrate_id()).is_equal(Sub.SAND)
	assert_bool(Sub.same_colour(model.get_substrate_colour(), Sub.NOT_A_SWATCH)).is_true()
	assert_dict(seen["warnings"]).is_empty()
	assert_dict(seen["errors"]).is_empty()


func test_ac11_a_known_id_with_a_missing_colour_keeps_white_as_a_non_swatch_colour() -> void:
	if not _setup_exists():
		return
	var model: AquariumModel = _model(Sub.PEBBLES, Color.WHITE)
	var seen: Dictionary = await EngineOutput.capture_result(
		func() -> Variant: return Sub.normalise(model, _catalog)
	)
	assert_that(seen["result"]).is_equal(false)
	assert_that(model.get_substrate_id()).is_equal(Sub.PEBBLES)
	assert_that(model.get_substrate_colour()).is_equal(Color.WHITE)
	assert_dict(seen["warnings"]).is_empty()


func test_ac11_every_known_type_with_its_default_is_left_alone() -> void:
	if not _setup_exists():
		return
	for id: StringName in Sub.IDS:
		var colour: Color = Sub.default_colour(_catalog, id)
		var model: AquariumModel = _model(id, colour)
		var seen: Dictionary = await EngineOutput.capture_result(
			func() -> Variant: return Sub.normalise(model, _catalog)
		)
		assert_that(seen["result"]).is_equal(false)
		assert_that(model.get_substrate_id()).is_equal(id)
		assert_bool(Sub.same_colour(model.get_substrate_colour(), colour)).is_true()
		assert_dict(seen["warnings"]).is_empty()
