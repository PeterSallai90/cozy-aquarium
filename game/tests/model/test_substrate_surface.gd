extends GdUnitTestSuite
## #28 criteria 25 and 26 (owner: developer): SubstrateSurface is the one source of the nominal
## substrate surface height (ADR 0011 rule 4). In #28 it returns the flat fill depth of the type for
## every input and ignores the heightmap on purpose (pinned here, flipped by #29). The result is
## never below 3 cm; a null definition logs one error and gives 3 cm; x and z outside the interior,
## NaN and infinity are clamped without error. H1: an item's position.y is the height above that
## surface, so a type change never moves an item in the model and the save file does not change.
## SubstrateSurface does not exist before the implementation, so it is reached through call().

const Sub := preload("res://tests/helpers/substrate_api.gd")
const Bed := preload("res://tests/helpers/substrate_bed_api.gd")
const Table := preload("res://tests/helpers/tank_table.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")

const ERR_NO_DEFINITION := "SubstrateSurface: no substrate definition"
const MIN_DEPTH_M := 0.03

var _catalog: RefCounted = null
var _history: CommandHistory = null


func before_test() -> void:
	_catalog = Sub.catalog()
	_history = CommandHistory.new()


func _have_surface() -> bool:
	var found: bool = Bed.script_exists(Bed.SURFACE_PATH)
	assert_bool(found).override_failure_message("%s is missing" % Bed.SURFACE_PATH).is_true()
	return found


func _flat(def: Resource) -> float:
	var script: GDScript = load(Bed.SURFACE_PATH) as GDScript
	return float(script.call("flat_depth", def))


func _height(
	def: Resource,
	heightmap: PackedFloat32Array,
	size: Vector2i,
	interior: Vector3,
	x: float,
	z: float
) -> float:
	var script: GDScript = load(Bed.SURFACE_PATH) as GDScript
	return float(script.call("height_at", def, heightmap, size, interior, x, z))


func _absolute(def: Resource, position: Vector3) -> float:
	var script: GDScript = load(Bed.SURFACE_PATH) as GDScript
	return float(
		script.call(
			"absolute_y",
			def,
			PackedFloat32Array(),
			Vector2i.ZERO,
			Table.interior(Table.MEDIUM),
			position
		)
	)


func _def(id: StringName) -> Resource:
	return Sub.definition(_catalog, id)


# --- AC 25 ---


func test_ac25_the_class_and_its_minimum_exist() -> void:
	if _have_surface():
		assert_float(float(Bed.constant(Bed.SURFACE_PATH, "MIN_DEPTH_M", -1.0))).is_equal(
			MIN_DEPTH_M
		)


func test_ac25_an_empty_heightmap_gives_the_fill_depth_of_the_type_in_every_tank() -> void:
	if not _have_surface():
		return
	for tank_id: StringName in Table.IDS:
		for id: StringName in Sub.IDS:
			var height: float = _height(
				_def(id), PackedFloat32Array(), Vector2i.ZERO, Table.interior(tank_id), 0.1, -0.05
			)
			(
				assert_float(height)
				. override_failure_message("%s in %s" % [id, tank_id])
				. is_equal_approx(Bed.fill_depth(id), 1e-9)
			)


func test_ac25_flat_depth_is_the_fill_depth() -> void:
	if not _have_surface():
		return
	for id: StringName in Sub.IDS:
		assert_float(_flat(_def(id))).override_failure_message(String(id)).is_equal_approx(
			Bed.fill_depth(id), 1e-9
		)


func test_ac25_a_non_empty_heightmap_is_ignored_pinned_for_29() -> void:
	if not _have_surface():
		return
	var interior: Vector3 = Table.interior(Table.MEDIUM)
	var maps: Array[PackedFloat32Array] = [
		PackedFloat32Array([0.0, 0.1, 0.2, 0.3, 0.4, 0.5]),
		PackedFloat32Array([0.9, 0.9, 0.9, 0.9, 0.9, 0.9]),
		PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]),
		PackedFloat32Array([0.001, 0.002, 0.003, 0.004, 0.005, 0.006]),
	]
	for id: StringName in Sub.IDS:
		for map: PackedFloat32Array in maps:
			var height: float = _height(_def(id), map, Vector2i(3, 2), interior, 0.0, 0.0)
			(
				assert_float(height)
				. override_failure_message("%s with map %s" % [id, map])
				. is_equal_approx(Bed.fill_depth(id), 1e-9)
			)


func test_ac25_x_and_z_outside_the_interior_nan_and_infinity_give_the_fill_depth_silently() -> void:
	if not _have_surface():
		return
	var interior: Vector3 = Table.interior(Table.MEDIUM)
	var pairs: Array[Vector2] = [
		Vector2(10.0, 10.0),
		Vector2(-10.0, -10.0),
		Vector2(NAN, 0.0),
		Vector2(0.0, NAN),
		Vector2(INF, 0.0),
		Vector2(0.0, -INF),
		Vector2(NAN, INF),
	]
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void:
			for id: StringName in Sub.IDS:
				for pair: Vector2 in pairs:
					var height: float = _height(
						_def(id), PackedFloat32Array(), Vector2i.ZERO, interior, pair.x, pair.y
					)
					(
						assert_float(height)
						. override_failure_message("%s at %s" % [id, pair])
						. is_equal_approx(Bed.fill_depth(id), 1e-9)
					)
	)
	assert_dict(seen["errors"]).is_empty()
	assert_dict(seen["warnings"]).is_empty()


func test_ac25_a_null_definition_logs_one_error_and_gives_3_cm() -> void:
	if not _have_surface():
		return
	var heights: Array[float] = []
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void:
			heights.append(_flat(null))
			heights.append(
				_height(
					null,
					PackedFloat32Array(),
					Vector2i.ZERO,
					Table.interior(Table.MEDIUM),
					0.0,
					0.0
				)
			)
	)
	assert_array(heights).is_equal([MIN_DEPTH_M, MIN_DEPTH_M])
	# One error per call: the plan's text, nothing else.
	assert_dict(seen["errors"]).is_equal({ERR_NO_DEFINITION: 2})


func test_ac25_the_result_is_never_below_3_cm() -> void:
	if not _have_surface():
		return
	for fill: float in [0.0, -1.0, 0.01, 0.0299]:
		var def: Resource = Sub.new_definition()
		def.set("fill_depth_m", fill)
		assert_float(_flat(def)).override_failure_message("fill %s" % fill).is_equal(MIN_DEPTH_M)
	var deep: Resource = Sub.new_definition()
	deep.set("fill_depth_m", 0.05)
	assert_float(_flat(deep)).is_equal_approx(0.05, 1e-9)


func test_ac25_it_needs_no_node_and_runs_headless() -> void:
	if _have_surface():
		assert_float(_flat(_def(Sub.SAND))).is_equal_approx(0.03, 1e-9)


# --- AC 26: H1 ---


func test_ac26_the_absolute_height_is_the_surface_plus_the_item_y() -> void:
	if not _have_surface():
		return
	assert_float(_absolute(_def(Sub.SAND), Vector3(0.1, 0.0, 0.0))).is_equal_approx(0.03, 1e-9)
	assert_float(_absolute(_def(Sub.PEBBLES), Vector3(0.1, 0.0, 0.0))).is_equal_approx(0.06, 1e-9)
	assert_float(_absolute(_def(Sub.GRAVEL), Vector3(0.1, 0.05, 0.0))).is_equal_approx(0.09, 1e-9)


func test_ac26_sand_pebbles_sand_keeps_the_item_y_and_moves_the_standing_height() -> void:
	if not _have_surface():
		return
	var model: AquariumModel = Sub.furnished(Sub.SAND, Sub.SAND_DEFAULT)
	var item: PlacedItem = model.get_item("a0000001")
	assert_float(item.position.y).is_equal(0.0)
	assert_float(_absolute(_def(model.get_substrate_id()), item.position)).is_equal_approx(
		0.03, 1e-9
	)
	var expected: Array[float] = [0.06, 0.03]
	var order: Array[StringName] = [Sub.PEBBLES, Sub.SAND]
	for step: int in order.size():
		var id: StringName = order[step]
		var colour: Color = Sub.pick(
			_catalog, model.get_substrate_id(), model.get_substrate_colour(), id
		)
		assert_bool(_history.execute(Sub.command(model, _catalog, id, colour))).is_true()
		var after: PlacedItem = model.get_item("a0000001")
		assert_float(after.position.y).override_failure_message("model y moved").is_equal(0.0)
		(
			assert_float(_absolute(_def(id), after.position))
			. override_failure_message("standing height after %s" % id)
			. is_equal_approx(expected[step], 1e-9)
		)


func test_ac26_the_save_file_does_not_change_with_the_round_trip_through_pebbles() -> void:
	if not _have_surface():
		return
	var codec: SaveCodec = SaveCodec.new()
	var model: AquariumModel = Sub.furnished(Sub.SAND, Sub.SAND_DEFAULT)
	var before: SaveResult = codec.encode(model, Sub.STAMP)
	assert_bool(before.is_ok()).is_true()
	for id: StringName in [Sub.PEBBLES, Sub.SAND]:
		var colour: Color = Sub.pick(
			_catalog, model.get_substrate_id(), model.get_substrate_colour(), id
		)
		assert_bool(_history.execute(Sub.command(model, _catalog, id, colour))).is_true()
	var after: SaveResult = codec.encode(model, Sub.STAMP)
	assert_str(after.text).is_equal(before.text)
	var parsed: Variant = JSON.parse_string(after.text)
	assert_bool(parsed is Dictionary).is_true()
	assert_int(int((parsed as Dictionary).get("format_version", -1))).is_equal(1)
	assert_int(codec.get_current_version()).is_equal(1)


func test_ac26_a_saved_item_at_y_zero_loads_and_saves_again_identically() -> void:
	if not _have_surface():
		return
	var codec: SaveCodec = SaveCodec.new()
	var model: AquariumModel = Sub.furnished(Sub.PEBBLES, Sub.default_colour(_catalog, Sub.PEBBLES))
	var saved: SaveResult = codec.encode(model, Sub.STAMP)
	var loaded: SaveResult = codec.decode(saved.text, Sub.STAMP)
	assert_bool(loaded.is_ok()).is_true()
	assert_float(loaded.model.get_item("a0000001").position.y).is_equal(0.0)
	assert_str(codec.encode(loaded.model, Sub.STAMP).text).is_equal(saved.text)
