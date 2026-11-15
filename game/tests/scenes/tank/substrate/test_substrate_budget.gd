extends GdUnitTestSuite
## #28 criterion 33, the automated budget (owner: technical-artist for the assembler, the LOD helper
## and the view; the measured GPU numbers of AC 34 are in tests/measure/substrate_budget_measure.gd,
## not here). For each of the three tanks and each of the five types:
## (a) at most 100,000 unique stones per bed in the large tank (sand: at most 90,000 unique ring
##     grains plus each shared top tile counted once), no more in the other two tanks;
## (b) the drawn-triangle estimate (chunks in the frustum, the LOD the distance selects, ray-cast
##     quads count 2) is at most 600,000 at the default camera and at most 1,000,000 at each of the
##     eight close-up views in the large tank, and no more in the other tanks of the same type at
##     the same views;
## (c) every instance comes from a baked record with at least one visibility flag;
## (d) no stone or grain casts a shadow, the core floor skin does;
## (e) the MultiMeshInstance3D count is within the ceiling of 800 in the large tank and no more in
##     the others; the counts are printed for the test report.

const Api := preload("res://tests/helpers/substrate_bed_api.gd")
const Fixture := preload("res://tests/helpers/substrate_bed_fixture.gd")
const Geo := preload("res://tests/helpers/substrate_geometry.gd")
const Rig := preload("res://tests/helpers/substrate_scene_rig.gd")
const Sub := preload("res://tests/helpers/substrate_api.gd")
const Table := preload("res://tests/helpers/tank_table.gd")
const Views := preload("res://tests/helpers/substrate_views.gd")

const MAX_UNIQUE := 100000
const MAX_SAND_RING := 90000
const MAX_DEFAULT_TRIANGLES := 600000
const MAX_CLOSE_UP_TRIANGLES := 1000000
const MAX_NODES := 800
const FLAG_BITS := 0x70
const RECORD_FLOATS := 9


func _ready_for(tank_id: StringName, id: StringName) -> bool:
	var missing: String = Api.missing_script([Api.LOD_PATH])
	assert_str(missing).is_empty()
	var why: String = Fixture.analysis_problem(tank_id, id)
	assert_str(why).override_failure_message("%s in %s: %s" % [id, tank_id, why]).is_empty()
	return missing.is_empty() and why.is_empty()


## The unique stones of a bed counted independently of the bed's own method.
func _unique_stones(data: RefCounted) -> int:
	var total: int = 0
	for entry: Dictionary in Geo.unique_buffers(data):
		total += (entry["buffer"] as PackedFloat32Array).size() / Geo.FLOATS
	return total


func _estimate(tank_id: StringName, id: StringName, view_name: String) -> int:
	var data: RefCounted = Fixture.bed_of(tank_id, id)
	var look: Resource = Api.look_of(id)
	var pose: Dictionary = Views.pose_of(view_name, tank_id, Api.fill_depth(id))
	var lod: GDScript = load(Api.LOD_PATH) as GDScript
	var grains: Dictionary = Fixture.grains_of(look)
	return int(
		lod.call(
			"estimate_triangles",
			data,
			look,
			grains["triangles"],
			Views.frustum(pose),
			pose["position"]
		)
	)


# --- (a) unique stones ---


func test_ac33_unique_stones_per_bed_are_at_most_100000_and_no_more_than_the_large_tank() -> void:
	for id: StringName in Sub.IDS:
		if not _ready_for(Table.LARGE, id):
			return
		var large: int = _unique_stones(Fixture.bed_of(Table.LARGE, id))
		print("[#28 budget] unique stones %s in %s: %d" % [id, Table.LARGE, large])
		assert_int(large).override_failure_message("%s: %d unique stones" % [id, large]).is_between(
			1, MAX_UNIQUE
		)
		for tank_id: StringName in [Table.SMALL, Table.MEDIUM]:
			if not _ready_for(tank_id, id):
				return
			var count: int = _unique_stones(Fixture.bed_of(tank_id, id))
			(
				assert_int(count)
				. override_failure_message(
					(
						"%s in %s: %d unique stones, the large tank has %d"
						% [id, tank_id, count, large]
					)
				)
				. is_less_equal(large)
			)


func test_ac33_sand_has_at_most_90000_unique_ring_grains_and_shares_its_top_tiles() -> void:
	for tank_id: StringName in Table.IDS:
		for id: StringName in Api.SAND_IDS:
			if not _ready_for(tank_id, id):
				return
			var data: RefCounted = Fixture.bed_of(tank_id, id)
			(
				assert_int(Api.chunk_instance_count(data))
				. override_failure_message("%s in %s: ring grains" % [id, tank_id])
				. is_less_equal(MAX_SAND_RING)
			)
			var tiles: Array = data.get("top_tiles")
			(
				assert_int(tiles.size())
				. override_failure_message("%s: no shared top tiles" % id)
				. is_greater(0)
			)
			var placements: PackedFloat32Array = data.get("top_placements")
			(
				assert_int(tiles.size())
				. override_failure_message(
					(
						"%s in %s: %d tile buffers for %d placements, each tile is shared"
						% [id, tank_id, tiles.size(), placements.size() / 5]
					)
				)
				. is_less(placements.size() / 5)
			)


func test_ac33_the_unique_stone_count_of_the_bed_matches_the_independent_count() -> void:
	for id: StringName in Sub.IDS:
		if not _ready_for(Table.MEDIUM, id):
			return
		var data: RefCounted = Fixture.bed_of(Table.MEDIUM, id)
		assert_int(int(data.call("unique_stone_count"))).override_failure_message(id).is_equal(
			_unique_stones(data)
		)
		assert_int(int(data.call("byte_size"))).is_greater(0)


# --- (b) triangles ---


func test_ac33_the_triangle_estimate_is_within_the_budget_at_every_view_of_the_large_tank() -> void:
	for id: StringName in Sub.IDS:
		if not _ready_for(Table.LARGE, id):
			return
		for view_name: String in Views.all_names():
			var triangles: int = _estimate(Table.LARGE, id, view_name)
			var limit: int = (
				MAX_DEFAULT_TRIANGLES if view_name == Views.DEFAULT_VIEW else MAX_CLOSE_UP_TRIANGLES
			)
			print("[#28 budget] triangles %s at %s: %d" % [id, view_name, triangles])
			(
				assert_int(triangles)
				. override_failure_message(
					"%s at %s: %d triangles, limit %d" % [id, view_name, triangles, limit]
				)
				. is_between(1, limit)
			)


func test_ac33_the_smaller_tanks_draw_no_more_than_the_large_tank_at_the_same_views() -> void:
	for id: StringName in Sub.IDS:
		if not _ready_for(Table.LARGE, id):
			return
		for view_name: String in Views.all_names():
			var large: int = _estimate(Table.LARGE, id, view_name)
			for tank_id: StringName in [Table.SMALL, Table.MEDIUM]:
				if not _ready_for(tank_id, id):
					return
				var count: int = _estimate(tank_id, id, view_name)
				(
					assert_int(count)
					. override_failure_message(
						(
							"%s at %s: %d triangles in %s, %d in the large tank"
							% [id, view_name, count, tank_id, large]
						)
					)
					. is_less_equal(large)
				)


# --- (c) flags ---


func test_ac33_every_baked_record_has_a_visibility_flag_through_the_reader() -> void:
	for id: StringName in Sub.IDS:
		for tank_id: StringName in Table.IDS:
			if not _ready_for(tank_id, id):
				return
			var stones: PackedFloat32Array = Fixture.bake_of(tank_id, id).get("stones")
			var unflagged: int = 0
			for record: int in stones.size() / RECORD_FLOATS:
				if (int(stones[record * RECORD_FLOATS + 8]) & FLAG_BITS) == 0:
					unflagged += 1
			(
				assert_int(unflagged)
				. override_failure_message(
					"%s in %s: %d baked records without a flag" % [id, tank_id, unflagged]
				)
				. is_equal(0)
			)


func test_ac33_a_pebble_bed_is_exactly_its_baked_records_nothing_more() -> void:
	for tank_id: StringName in Table.IDS:
		if not _ready_for(tank_id, Api.PEBBLES):
			return
		var records: int = (
			(Fixture.bake_of(tank_id, Api.PEBBLES).get("stones") as PackedFloat32Array).size()
			/ RECORD_FLOATS
		)
		(
			assert_int(Api.chunk_instance_count(Fixture.bed_of(tank_id, Api.PEBBLES)))
			. override_failure_message(
				"pebbles in %s: every instance comes from a flagged record" % tank_id
			)
			. is_equal(records)
		)


# --- (d) and (e) the built view ---


func _view(tank_id: StringName, id: StringName) -> Node3D:
	var script: GDScript = load(Api.VIEW_PATH) as GDScript
	var view: Node3D = script.new() as Node3D
	add_child(view)
	auto_free(view)
	view.call("begin", Fixture.bed_of(tank_id, id), Api.look_of(id))
	view.call("build_all")
	return view


func test_ac33_no_stone_or_grain_casts_a_shadow_and_the_core_floor_does() -> void:
	for id: StringName in Sub.IDS:
		if not _ready_for(Table.SMALL, id):
			return
		var view: Node3D = _view(Table.SMALL, id)
		var stones: int = 0
		for instance: GeometryInstance3D in Rig.geometry_below(view):
			if instance is MultiMeshInstance3D:
				stones += 1
				(
					assert_int(instance.cast_shadow)
					. override_failure_message("%s: %s casts a shadow" % [id, instance.name])
					. is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
				)
		assert_int(stones).override_failure_message("%s: no stone nodes" % id).is_greater(0)
		var floor_skin: GeometryInstance3D = (
			view.get_node_or_null("CoreFloor") as GeometryInstance3D
		)
		assert_object(floor_skin).override_failure_message("%s: no CoreFloor" % id).is_not_null()
		if floor_skin != null:
			(
				assert_int(floor_skin.cast_shadow)
				. override_failure_message("%s: CoreFloor must cast the bed shadow" % id)
				. is_not_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			)


func test_ac33_the_multimesh_node_count_is_within_800_and_no_more_in_the_smaller_tanks() -> void:
	for id: StringName in Sub.IDS:
		if not _ready_for(Table.LARGE, id):
			return
		var large_view: Node3D = _view(Table.LARGE, id)
		var large: int = int(large_view.call("get_multimesh_node_count"))
		print("[#28 budget] MultiMesh nodes %s in %s: %d" % [id, Table.LARGE, large])
		assert_int(large).override_failure_message("%s: %d nodes" % [id, large]).is_between(
			1, MAX_NODES
		)
		var counted: int = 0
		for instance: GeometryInstance3D in Rig.geometry_below(large_view):
			if instance is MultiMeshInstance3D:
				counted += 1
		(
			assert_int(large)
			. override_failure_message("%s: get_multimesh_node_count is not the node count" % id)
			. is_equal(counted)
		)
		for tank_id: StringName in [Table.SMALL, Table.MEDIUM]:
			if not _ready_for(tank_id, id):
				return
			var count: int = int(_view(tank_id, id).call("get_multimesh_node_count"))
			(
				assert_int(count)
				. override_failure_message(
					"%s in %s: %d nodes, the large tank has %d" % [id, tank_id, count, large]
				)
				. is_less_equal(large)
			)
