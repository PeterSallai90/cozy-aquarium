extends GdUnitTestSuite
## #28 criterion 40, the sand range and the proxies of "no visible tile repetition" (owner:
## technical-artist; the look itself is judged by the owner at 35 cm). Numbers bound it: the sand
## real-grain range ends between 0.7 and 1.0 m; on the four tile-based types (sand, black sand,
## gravel, coloured gravel) the top tile edge is at least 5 cm, no two edge-adjacent top tiles use
## the same (fill, rotation, mirror), the grain density in a 3 mm band centred on each tile border
## is within +-15 % of the density elsewhere, and the orientation histogram (8 bins of the longest
## axis on the xz plane) of a tile is within 20 % (half the L1 distance) of its neighbour's;
## pebbles use no tiles. The measuring definitions are technical plan v3, 1.9: the band and the
## histograms look at the grains of the top layer (centre at most 2 x the largest grain below the
## nominal surface) in the inner tiles, so the ring against the glass is not counted. The sand
## surface node under the grains is in test_substrate_bed_view.gd.

const Api := preload("res://tests/helpers/substrate_bed_api.gd")
const Fixture := preload("res://tests/helpers/substrate_bed_fixture.gd")
const Geo := preload("res://tests/helpers/substrate_geometry.gd")
const Sub := preload("res://tests/helpers/substrate_api.gd")
const Table := preload("res://tests/helpers/tank_table.gd")

const MIN_TILE_EDGE_M := 0.05
const DENSITY_TOLERANCE := 0.15
const HISTOGRAM_TOLERANCE := 0.20
const MIN_POINTS_PER_TILE := 30
const MIN_PAIRS := 4
const RANGE_END_MIN_M := 0.7
const RANGE_END_MAX_M := 1.0


func _ready_for(tank_id: StringName, id: StringName) -> bool:
	var why: String = Fixture.analysis_problem(tank_id, id)
	assert_str(why).override_failure_message("%s in %s: %s" % [id, tank_id, why]).is_empty()
	return why.is_empty()


func _placements(tank_id: StringName, id: StringName) -> PackedFloat32Array:
	return Fixture.bed_of(tank_id, id).get("top_placements")


func test_ac40_the_sand_range_ends_between_0_7_and_1_0_m_and_begins_before_it() -> void:
	for id: StringName in Api.SAND_IDS:
		var look: Resource = Api.look_of(id)
		assert_object(look).override_failure_message("no look for %s" % id).is_not_null()
		if look == null:
			continue
		var begin: float = float(look.get("sand_range_begin_m"))
		var end: float = float(look.get("sand_range_end_m"))
		assert_float(end).override_failure_message("%s: range end %s" % [id, end]).is_between(
			RANGE_END_MIN_M, RANGE_END_MAX_M
		)
		assert_float(begin).override_failure_message("%s: range begin %s" % [id, begin]).is_between(
			0.0, end
		)


func test_ac40_the_tile_types_have_placements_and_pebbles_have_none() -> void:
	for tank_id: StringName in Table.IDS:
		for id: StringName in Sub.IDS:
			if not _ready_for(tank_id, id):
				return
			var data: RefCounted = Fixture.bed_of(tank_id, id)
			var placements: PackedFloat32Array = _placements(tank_id, id)
			assert_int(placements.size() % 5).is_equal(0)
			if id == Api.PEBBLES:
				(
					assert_int(placements.size())
					. override_failure_message("pebbles in %s use tiles" % tank_id)
					. is_equal(0)
				)
				assert_array(data.get("top_tiles")).is_empty()
			else:
				(
					assert_int(placements.size())
					. override_failure_message(
						"%s in %s has no top tile placements" % [id, tank_id]
					)
					. is_greater(0)
				)


func test_ac40_the_top_tile_edge_is_at_least_5_cm_and_the_tiles_fill_the_interior() -> void:
	for tank_id: StringName in Table.IDS:
		for id: StringName in Api.TILE_IDS:
			if not _ready_for(tank_id, id):
				return
			var placements: PackedFloat32Array = _placements(tank_id, id)
			var pitch: Vector2 = Geo.tile_pitch(placements)
			var label: String = "%s in %s" % [id, tank_id]
			(
				assert_float(pitch.x)
				. override_failure_message("%s: tile edge x %.4f" % [label, pitch.x])
				. is_greater_equal(MIN_TILE_EDGE_M - 1e-6)
			)
			(
				assert_float(pitch.y)
				. override_failure_message("%s: tile edge z %.4f" % [label, pitch.y])
				. is_greater_equal(MIN_TILE_EDGE_M - 1e-6)
			)
			var interior: Vector3 = Table.interior(tank_id)
			var cells: Dictionary = Geo.lattice(placements, pitch)
			(
				assert_int(cells.size())
				. override_failure_message(
					(
						"%s: %d tiles for %.2f x %.2f m with a %.3f x %.3f m pitch"
						% [label, cells.size(), interior.x, interior.z, pitch.x, pitch.y]
					)
				)
				. is_equal(roundi(interior.x / pitch.x) * roundi(interior.z / pitch.y))
			)


func test_ac40_no_two_edge_adjacent_top_tiles_share_fill_rotation_and_mirror() -> void:
	for tank_id: StringName in Table.IDS:
		for id: StringName in Api.TILE_IDS:
			if not _ready_for(tank_id, id):
				return
			var placements: PackedFloat32Array = _placements(tank_id, id)
			var cells: Dictionary = Geo.lattice(placements, Geo.tile_pitch(placements))
			(
				assert_int(Geo.adjacent_equal_pairs(cells))
				. override_failure_message(
					"%s in %s: adjacent tiles repeat (fill, rotation, mirror)" % [id, tank_id]
				)
				. is_equal(0)
			)


func _grid_of(tank_id: StringName, id: StringName) -> Dictionary:
	var placements: PackedFloat32Array = _placements(tank_id, id)
	var pitch: Vector2 = Geo.tile_pitch(placements)
	var cells: Dictionary = Geo.lattice(placements, pitch)
	var columns: int = 0
	var rows: int = 0
	for key: Vector2i in cells:
		columns = maxi(columns, key.x + 1)
		rows = maxi(rows, key.y + 1)
	var origin: Vector2 = Vector2(INF, INF)
	# placements.size() / 5: five floats per tile placement, so a whole placement count.
	@warning_ignore("integer_division")
	for cell: int in placements.size() / 5:
		origin = origin.min(Vector2(placements[cell * 5], placements[cell * 5 + 1]))
	return {"pitch": pitch, "columns": columns, "rows": rows, "origin": origin}


func _top_points(tank_id: StringName, id: StringName) -> PackedFloat32Array:
	var data: RefCounted = Fixture.bed_of(tank_id, id)
	var grains: Dictionary = Fixture.grains_of(Api.look_of(id))
	return Geo.top_layer_points(
		Geo.entries_of(data),
		grains["axes"],
		Api.fill_depth(id),
		2.0 * float(Fixture.bake_of(tank_id, id).call("largest_size")),
		Api.is_sand(id)
	)


func test_ac40_the_grain_density_in_the_seam_band_is_within_15_percent_of_the_rest() -> void:
	for tank_id: StringName in [Table.MEDIUM, Table.LARGE]:
		for id: StringName in Api.TILE_IDS:
			if not _ready_for(tank_id, id):
				return
			var grid: Dictionary = _grid_of(tank_id, id)
			var ratio: float = Geo.seam_density_ratio(
				_top_points(tank_id, id),
				grid["origin"],
				grid["pitch"],
				grid["columns"],
				grid["rows"]
			)
			(
				assert_float(ratio)
				. override_failure_message(
					(
						"%s in %s: seam band density is %.3f x the density elsewhere"
						% [id, tank_id, ratio]
					)
				)
				. is_between(1.0 - DENSITY_TOLERANCE, 1.0 + DENSITY_TOLERANCE)
			)


func test_ac40_the_orientation_histogram_of_a_tile_is_within_20_percent_of_its_neighbour() -> void:
	for tank_id: StringName in [Table.MEDIUM, Table.LARGE]:
		for id: StringName in Api.TILE_IDS:
			if not _ready_for(tank_id, id):
				return
			var grid: Dictionary = _grid_of(tank_id, id)
			var histograms: Dictionary = Geo.orientation_histograms(
				_top_points(tank_id, id),
				grid["origin"],
				grid["pitch"],
				grid["columns"],
				grid["rows"],
				MIN_POINTS_PER_TILE
			)
			var pairs: int = 0
			for key: Vector2i in histograms:
				for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
					var other: Vector2i = key + step
					if not histograms.has(other):
						continue
					pairs += 1
					var distance: float = Geo.histogram_distance(histograms[key], histograms[other])
					(
						assert_float(distance)
						. override_failure_message(
							(
								"%s in %s: tiles %s and %s differ by %.3f in orientation"
								% [id, tank_id, key, other, distance]
							)
						)
						. is_less_equal(HISTOGRAM_TOLERANCE)
					)
			(
				assert_int(pairs)
				. override_failure_message(
					(
						"%s in %s: only %d tile pairs with at least %d grains to compare"
						% [id, tank_id, pairs, MIN_POINTS_PER_TILE]
					)
				)
				. is_greater_equal(MIN_PAIRS)
			)
