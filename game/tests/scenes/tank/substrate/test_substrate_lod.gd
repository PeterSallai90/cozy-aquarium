extends GdUnitTestSuite
## #28 criteria 33 and 34, the LOD helper (owner: technical-artist: SubstrateLod). select() picks
## the LOD of a chunk from the camera distance with a 5 % hysteresis: going up the chain happens a
## little
## beyond the switch distance, going back a little before it, so a chunk never flickers at the edge.
## estimate_triangles() is the AC 33 estimate: the sum over the chunks that intersect the frustum of
## instances x the triangles of the LOD the distance to the chunk bounds selects; ray-cast sand
## quads count 2 each; a chunk outside the frustum counts 0. The synthetic beds here pin the maths
## without the baked data. Contract of the arguments (technical plan v3, 3.1): triangles is an Array
## with one PackedInt32Array of triangle counts per LOD for each mesh variant (empty for sand),
## frustum has outward normals like Camera3D.get_frustum(), camera_local is in the bed's space.

const Api := preload("res://tests/helpers/substrate_bed_api.gd")
const Views := preload("res://tests/helpers/substrate_views.gd")

const SWITCH: Array[float] = [0.1, 0.3]
const HYSTERESIS := 0.05
const STEP_M := 0.0001
const SWEEP_TOP_M := 0.6
const EDGE_TOLERANCE := 0.12


func _have_lod() -> bool:
	var missing: String = Api.missing_script(
		[Api.LOD_PATH, Api.BED_DATA_PATH, Api.CHUNK_DATA_PATH, Api.LOOK_SCRIPT_PATH]
	)
	assert_str(missing).is_empty()
	return missing.is_empty()


func _select(distance: float, current: int) -> int:
	var lod: GDScript = load(Api.LOD_PATH) as GDScript
	var switch_m: PackedFloat32Array = PackedFloat32Array(SWITCH)
	return int(lod.call("select", distance, switch_m, current, HYSTERESIS))


# --- select ---


func test_ac33_a_chunk_next_to_the_camera_is_lod0_and_a_far_chunk_the_last_lod() -> void:
	if not _have_lod():
		return
	assert_int(_select(0.0, 0)).is_equal(0)
	assert_int(_select(0.01, 0)).is_equal(0)
	assert_int(_select(100.0, 0)).is_equal(SWITCH.size())
	assert_int(_select(100.0, SWITCH.size())).is_equal(SWITCH.size())
	assert_int(_select(0.0, SWITCH.size())).is_equal(0)


func test_ac33_the_middle_of_a_band_gives_that_lod_whatever_the_current_one_is() -> void:
	if not _have_lod():
		return
	for current: int in [0, 1, 2]:
		(
			assert_int(_select(0.2, current))
			. override_failure_message("0.2 m from LOD %d" % current)
			. is_equal(1)
		)
		(
			assert_int(_select(0.02, current))
			. override_failure_message("0.02 m from LOD %d" % current)
			. is_equal(0)
		)
		(
			assert_int(_select(0.5, current))
			. override_failure_message("0.5 m from LOD %d" % current)
			. is_equal(2)
		)


func test_ac33_at_the_switch_distance_the_current_lod_is_kept() -> void:
	if not _have_lod():
		return
	for index: int in SWITCH.size():
		(
			assert_int(_select(SWITCH[index], index))
			. override_failure_message("at %.2f m the chunk left LOD %d" % [SWITCH[index], index])
			. is_equal(index)
		)
		(
			assert_int(_select(SWITCH[index], index + 1))
			. override_failure_message(
				"at %.2f m the chunk left LOD %d" % [SWITCH[index], index + 1]
			)
			. is_equal(index + 1)
		)


func test_ac33_sweeping_out_and_back_switches_each_edge_once_with_a_gap_of_at_most_12_percent(
) -> void:
	if not _have_lod():
		return
	var ups: Array[float] = []
	var downs: Array[float] = []
	var current: int = 0
	var steps: int = int(SWEEP_TOP_M / STEP_M)
	for step: int in range(0, steps + 1):
		var next: int = _select(float(step) * STEP_M, current)
		(
			assert_int(next)
			. override_failure_message("going out the LOD fell from %d to %d" % [current, next])
			. is_greater_equal(current)
		)
		(
			assert_int(next - current)
			. override_failure_message("a jump of more than one LOD")
			. is_less_equal(1)
		)
		if next != current:
			ups.append(float(step) * STEP_M)
		current = next
	assert_int(current).is_equal(SWITCH.size())
	for step: int in range(steps, -1, -1):
		var next_down: int = _select(float(step) * STEP_M, current)
		assert_int(next_down).override_failure_message("going in the LOD rose").is_less_equal(
			current
		)
		if next_down != current:
			downs.append(float(step) * STEP_M)
		current = next_down
	assert_int(current).is_equal(0)
	assert_int(ups.size()).override_failure_message("switches going out: %s" % [ups]).is_equal(
		SWITCH.size()
	)
	(
		assert_int(downs.size())
		. override_failure_message("switches coming back: %s" % [downs])
		. is_equal(SWITCH.size())
	)
	downs.reverse()
	for index: int in SWITCH.size():
		var edge: float = SWITCH[index]
		(
			assert_float(ups[index])
			. override_failure_message(
				"switch %d going out at %.4f m, wanted near %.2f" % [index, ups[index], edge]
			)
			. is_between(edge * (1.0 - EDGE_TOLERANCE), edge * (1.0 + EDGE_TOLERANCE))
		)
		(
			assert_float(downs[index])
			. override_failure_message("switch %d coming back at %.4f m" % [index, downs[index]])
			. is_less(ups[index])
		)
		(
			assert_float(ups[index] - downs[index])
			. override_failure_message(
				"hysteresis gap %.4f m at edge %.2f" % [ups[index] - downs[index], edge]
			)
			. is_less_equal(edge * EDGE_TOLERANCE)
		)


# --- estimate_triangles on a synthetic bed ---


func _typed_array(element_type: int, element_class: StringName, script: Variant) -> Array:
	return Array([], element_type, element_class, script)


func _chunk(key: Vector2i, origin: Vector3, instances: int) -> RefCounted:
	var script: GDScript = load(Api.CHUNK_DATA_PATH) as GDScript
	var chunk: RefCounted = script.new() as RefCounted
	chunk.set("key", key)
	chunk.set("aabb", AABB(origin, Vector3(0.05, 0.05, 0.05)))
	var buffers: Array = _typed_array(TYPE_PACKED_FLOAT32_ARRAY, &"", null)
	var buffer: PackedFloat32Array = PackedFloat32Array()
	buffer.resize(instances * 16)
	buffers.append(buffer)
	chunk.set("buffers", buffers)
	chunk.set("counts", PackedInt32Array([instances]))
	return chunk


## A bed with a chunk of 10 instances at the origin and one of 20 at x = 0.5 m, and a look with the
## switch distances 0.1 and 0.3 m. `grain_class` 0 is sand.
func _bed(grain_class: int) -> Array:
	var chunk_script: GDScript = load(Api.CHUNK_DATA_PATH) as GDScript
	var chunks: Array = _typed_array(TYPE_OBJECT, &"RefCounted", chunk_script)
	chunks.append(_chunk(Vector2i(0, 0), Vector3.ZERO, 10))
	chunks.append(_chunk(Vector2i(10, 0), Vector3(0.5, 0.0, 0.0), 20))
	var bed_script: GDScript = load(Api.BED_DATA_PATH) as GDScript
	var data: RefCounted = bed_script.new() as RefCounted
	data.set("chunks", chunks)
	var look_script: GDScript = load(Api.LOOK_SCRIPT_PATH) as GDScript
	var look: Resource = look_script.new() as Resource
	look.set("grain_class", grain_class)
	look.set("lod_distances_m", PackedFloat32Array(SWITCH))
	look.set("sand_range_begin_m", 0.7)
	look.set("sand_range_end_m", 1.0)
	return [data, look]


func _estimate(grain_class: int, triangles: Array, from: Dictionary, camera_local: Vector3) -> int:
	var parts: Array = _bed(grain_class)
	var lod: GDScript = load(Api.LOD_PATH) as GDScript
	return int(
		lod.call(
			"estimate_triangles", parts[0], parts[1], triangles, Views.frustum(from), camera_local
		)
	)


func _looking(position: Vector3, target: Vector3) -> Dictionary:
	return {"position": position, "target": target}


func test_ac33_the_estimate_is_instances_times_the_triangles_of_the_lod_by_distance() -> void:
	if not _have_lod():
		return
	var triangles: Array = [PackedInt32Array([100, 50, 10])]
	var sees_both: Dictionary = _looking(Vector3(0.3, 0.025, 1.5), Vector3(0.3, 0.025, 0.0))
	# In the first chunk: it is LOD0 (10 x 100), the second is 0.45 m away: LOD2 (20 x 10).
	assert_int(_estimate(1, triangles, sees_both, Vector3(0.025, 0.025, 0.025))).is_equal(1200)
	# 0.25 m and 0.2 m away: both LOD1.
	assert_int(_estimate(1, triangles, sees_both, Vector3(0.3, 0.025, 0.025))).is_equal(1500)
	# Far from both: LOD2 for all 30 instances.
	assert_int(_estimate(1, triangles, sees_both, Vector3(0.3, 0.025, 5.0))).is_equal(300)


func test_ac33_a_chunk_outside_the_frustum_counts_nothing() -> void:
	if not _have_lod():
		return
	var triangles: Array = [PackedInt32Array([100, 50, 10])]
	var sees_first: Dictionary = _looking(Vector3(0.025, 0.025, 0.4), Vector3(0.025, 0.025, 0.0))
	assert_int(_estimate(1, triangles, sees_first, Vector3(0.025, 0.025, 0.025))).is_equal(1000)
	var looks_away: Dictionary = _looking(Vector3(0.3, 0.025, 1.5), Vector3(0.3, 0.025, 3.0))
	assert_int(_estimate(1, triangles, looks_away, Vector3(0.025, 0.025, 0.025))).is_equal(0)


func test_ac33_ray_cast_sand_quads_count_two_triangles_each() -> void:
	if not _have_lod():
		return
	var sees_both: Dictionary = _looking(Vector3(0.3, 0.025, 1.5), Vector3(0.3, 0.025, 0.0))
	assert_int(_estimate(0, [], sees_both, Vector3(0.025, 0.025, 0.025))).is_equal(60)
	var looks_away: Dictionary = _looking(Vector3(0.3, 0.025, 1.5), Vector3(0.3, 0.025, 3.0))
	assert_int(_estimate(0, [], looks_away, Vector3(0.025, 0.025, 0.025))).is_equal(0)
