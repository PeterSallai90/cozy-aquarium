# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #28 criteria 32 and 34, switching the bed (owner: developer: SubstrateBed, its cache and the
## swap rules of technical plan v3, 3.2). show_type() on the same id that is shown only changes the
## tint; on the id that is already pending it does nothing; on a type already built in this bed it
## swaps in the same call without a job; on a data cache hit it only re-instances; otherwise it
## cancels the running job and starts a new one. With no bed shown yet the core of the pending view
## is visible at once and the stones appear at the swap. A swap makes the new view visible with the
## current tint, hides the old one and emits bed_swapped in one frame. Ten rapid switches leave no
## orphan nodes, never show a half-built bed and end like a fresh build of the last type. Headless
## tests use finish_pending(); no test waits on frames for the bed.

const Api := preload("res://tests/helpers/substrate_bed_api.gd")
const Fixture := preload("res://tests/helpers/substrate_bed_fixture.gd")
const Rig := preload("res://tests/helpers/room_rig.gd")
const Scene := preload("res://tests/helpers/substrate_scene_rig.gd")
const Sub := preload("res://tests/helpers/substrate_api.gd")
const Table := preload("res://tests/helpers/tank_table.gd")

const BUILD_BUDGET_USEC := 3000
const OTHER_TINT := Color(0.3, 0.2, 0.7)

var _substrates: RefCounted = null
var _swaps: Array[StringName] = []


func before_test() -> void:
	_substrates = Sub.catalog()
	_swaps = []


func _have_classes() -> bool:
	var missing: String = Api.missing_script(
		[Api.BED_PATH, Api.CACHE_PATH, Api.VIEW_PATH, Api.JOB_PATH]
	)
	assert_str(missing).is_empty()
	return missing.is_empty()


func _bed() -> Node3D:
	var script: GDScript = load(Api.BED_PATH) as GDScript
	var bed: Node3D = script.new() as Node3D
	var cache: RefCounted = (load(Api.CACHE_PATH) as GDScript).new() as RefCounted
	bed.call("setup", cache)
	add_child(bed)
	auto_free(bed)
	bed.connect(&"bed_swapped", func(swapped_id: StringName) -> void: _swaps.append(swapped_id))
	return bed


func _show(
	bed: Node3D, tank_id: StringName, id: StringName, colour: Color = Color.TRANSPARENT
) -> void:
	var wanted: Color = (
		Sub.default_colour(_substrates, id) if colour == Color.TRANSPARENT else colour
	)
	bed.call("show_type", Rig.definition_of(tank_id), Sub.definition(_substrates, id), wanted)


func _count(bed: Node3D, method: String) -> int:
	return int(bed.call(method))


## The views of the bed with visible stones.
func _stone_views(bed: Node3D) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for view: Node3D in Scene.views_of(bed):
		if Scene.stones_visible(view):
			found.append(view)
	return found


func test_ac32_the_budget_per_frame_is_3_ms() -> void:
	assert_int(int(Api.constant(Api.BED_PATH, "BUILD_BUDGET_USEC", -1))).is_equal(BUILD_BUDGET_USEC)


func test_ac32_a_new_bed_shows_nothing_and_has_no_job() -> void:
	if not _have_classes():
		return
	var bed: Node3D = _bed()
	assert_that(bed.call("get_shown_id")).is_equal(&"")
	assert_that(bed.call("get_pending_id")).is_equal(&"")
	assert_bool(bool(bed.call("is_building"))).is_false()
	assert_int(_count(bed, "get_assembly_count")).is_equal(0)
	bed.call("finish_pending")
	(
		assert_that(bed.call("get_shown_id"))
		. override_failure_message("finish_pending with nothing pending")
		. is_equal(&"")
	)
	assert_array(_swaps).is_empty()


func test_ac32_the_first_type_shows_its_core_at_once_and_its_stones_at_the_swap() -> void:
	if not _have_classes():
		return
	var bed: Node3D = _bed()
	_show(bed, Table.SMALL, Sub.GRAVEL)
	assert_that(bed.call("get_pending_id")).is_equal(Sub.GRAVEL)
	assert_that(bed.call("get_shown_id")).is_equal(&"")
	assert_bool(bool(bed.call("is_building"))).is_true()
	var views: Array[Node3D] = Scene.views_of(bed)
	assert_int(views.size()).override_failure_message("views while building").is_equal(1)
	(
		assert_bool((views[0].get_node("Core") as Node3D).is_visible_in_tree())
		. override_failure_message(
			"the lamp-lit cabinet shows through an empty floor: the core is not visible at once"
		)
		. is_true()
	)
	assert_bool((views[0].get_node("CoreFloor") as Node3D).is_visible_in_tree()).is_true()
	(
		assert_bool(Scene.stones_visible(views[0]))
		. override_failure_message("stones before the swap")
		. is_false()
	)
	bed.call("finish_pending")
	assert_that(bed.call("get_shown_id")).is_equal(Sub.GRAVEL)
	assert_array(_swaps).is_equal([Sub.GRAVEL])
	assert_bool(bool(bed.call("is_building"))).is_false()
	assert_int(_count(bed, "get_assembly_count")).is_equal(1)
	assert_bool(Scene.stones_visible(bed.call("get_shown_view"))).is_true()
	assert_bool(bool((bed.call("get_shown_view") as Node3D).call("is_complete"))).is_true()


func test_ac32_the_same_id_as_the_shown_one_only_changes_the_tint() -> void:
	if not _have_classes():
		return
	var bed: Node3D = _bed()
	_show(bed, Table.SMALL, Sub.PEBBLES)
	bed.call("finish_pending")
	var view: Node3D = bed.call("get_shown_view")
	_show(bed, Table.SMALL, Sub.PEBBLES, OTHER_TINT)
	assert_bool(bool(bed.call("is_building"))).is_false()
	assert_int(_count(bed, "get_assembly_count")).is_equal(1)
	assert_bool(is_same(view, bed.call("get_shown_view"))).is_true()
	assert_bool(Scene.same_tint(bed.call("get_tint"), OTHER_TINT)).is_true()
	assert_str(Scene.tint_mismatch(view, OTHER_TINT)).is_empty()
	assert_array(_swaps).is_equal([Sub.PEBBLES])


func test_ac32_the_same_id_as_the_pending_one_does_nothing() -> void:
	if not _have_classes():
		return
	var bed: Node3D = _bed()
	_show(bed, Table.SMALL, Sub.GRAVEL)
	_show(bed, Table.SMALL, Sub.GRAVEL)
	(
		assert_int(_count(bed, "get_assembly_count"))
		. override_failure_message("a second job for the same type")
		. is_equal(1)
	)
	assert_that(bed.call("get_pending_id")).is_equal(Sub.GRAVEL)
	assert_int(Scene.views_of(bed).size()).is_equal(1)
	bed.call("finish_pending")
	assert_array(_swaps).is_equal([Sub.GRAVEL])


func test_ac32_a_type_built_in_this_bed_swaps_back_in_the_same_call_without_a_job() -> void:
	if not _have_classes():
		return
	var bed: Node3D = _bed()
	_show(bed, Table.SMALL, Sub.GRAVEL)
	bed.call("finish_pending")
	_show(bed, Table.SMALL, Sub.PEBBLES)
	bed.call("finish_pending")
	var assemblies: int = _count(bed, "get_assembly_count")
	assert_int(assemblies).is_equal(2)
	_show(bed, Table.SMALL, Sub.GRAVEL)
	(
		assert_that(bed.call("get_shown_id"))
		. override_failure_message("a built type did not swap in the same call")
		. is_equal(Sub.GRAVEL)
	)
	assert_bool(bool(bed.call("is_building"))).is_false()
	assert_that(bed.call("get_pending_id")).is_equal(&"")
	assert_int(_count(bed, "get_assembly_count")).is_equal(assemblies)
	assert_array(_swaps).is_equal([Sub.GRAVEL, Sub.PEBBLES, Sub.GRAVEL])
	assert_int(_stone_views(bed).size()).override_failure_message("two views show stones").is_equal(
		1
	)


func test_ac32_a_new_switch_cancels_the_running_job_and_the_old_type_is_never_shown() -> void:
	if not _have_classes():
		return
	var bed: Node3D = _bed()
	_show(bed, Table.SMALL, Sub.GRAVEL)
	_show(bed, Table.SMALL, Sub.PEBBLES)
	assert_that(bed.call("get_pending_id")).is_equal(Sub.PEBBLES)
	assert_int(_count(bed, "get_assembly_count")).is_equal(2)
	bed.call("finish_pending")
	assert_that(bed.call("get_shown_id")).is_equal(Sub.PEBBLES)
	assert_array(_swaps).override_failure_message("the cancelled type was swapped in").is_equal(
		[Sub.PEBBLES]
	)
	assert_int(_stone_views(bed).size()).is_equal(1)


func test_ac32_sand_pebbles_sand_ends_like_the_first_sand() -> void:
	if not _have_classes():
		return
	var bed: Node3D = _bed()
	_show(bed, Table.SMALL, Sub.SAND)
	bed.call("finish_pending")
	var first_view: Node3D = bed.call("get_shown_view")
	var stones: int = int(first_view.call("get_unique_stone_count"))
	var nodes: int = int(first_view.call("get_multimesh_node_count"))
	_show(bed, Table.SMALL, Sub.PEBBLES)
	bed.call("finish_pending")
	_show(bed, Table.SMALL, Sub.SAND)
	bed.call("finish_pending")
	var view: Node3D = bed.call("get_shown_view")
	assert_int(int(view.call("get_unique_stone_count"))).is_equal(stones)
	assert_int(int(view.call("get_multimesh_node_count"))).is_equal(nodes)
	assert_array(_swaps).is_equal([Sub.SAND, Sub.PEBBLES, Sub.SAND])
	assert_str(Scene.tint_mismatch(view, Sub.default_colour(_substrates, Sub.SAND))).is_empty()


func test_ac32_a_data_cache_hit_after_a_tank_change_instances_without_a_new_job() -> void:
	if not _have_classes():
		return
	var bed: Node3D = _bed()
	_show(bed, Table.SMALL, Sub.GRAVEL)
	bed.call("finish_pending")
	_show(bed, Table.MEDIUM, Sub.GRAVEL)
	bed.call("finish_pending")
	(
		assert_int(_count(bed, "get_assembly_count"))
		. override_failure_message("another tank needs its own bed")
		. is_equal(2)
	)
	_show(bed, Table.SMALL, Sub.GRAVEL)
	bed.call("finish_pending")
	(
		assert_int(_count(bed, "get_assembly_count"))
		. override_failure_message(
			"the small tank's gravel was assembled again instead of coming from the cache"
		)
		. is_equal(2)
	)
	assert_that(bed.call("get_shown_id")).is_equal(Sub.GRAVEL)


func test_ac32_the_colour_in_force_at_the_swap_is_the_colour_of_the_new_view() -> void:
	if not _have_classes():
		return
	var bed: Node3D = _bed()
	_show(bed, Table.SMALL, Sub.COLOURED)
	bed.call("set_tint", OTHER_TINT)
	bed.call("finish_pending")
	assert_bool(Scene.same_tint(bed.call("get_tint"), OTHER_TINT)).is_true()
	assert_str(Scene.tint_mismatch(bed.call("get_shown_view"), OTHER_TINT)).is_empty()


func test_ac32_ten_rapid_switches_end_like_a_fresh_build_with_no_orphans_and_no_half_built_bed(
) -> void:
	if not _have_classes():
		return
	var bed: Node3D = _bed()
	var order: Array[StringName] = [
		Sub.GRAVEL,
		Sub.PEBBLES,
		Sub.BLACK,
		Sub.COLOURED,
		Sub.SAND,
		Sub.GRAVEL,
		Sub.PEBBLES,
		Sub.BLACK,
		Sub.COLOURED,
		Sub.SAND,
	]
	var orphans_before: int = Node.get_orphan_node_ids().size()
	for id: StringName in order:
		_show(bed, Table.SMALL, id)
		var showing: Array[Node3D] = _stone_views(bed)
		(
			assert_int(showing.size())
			. override_failure_message(
				"%d views show stones after switching to %s" % [showing.size(), id]
			)
			. is_less_equal(1)
		)
		for view: Node3D in showing:
			(
				assert_bool(bool(view.call("is_complete")))
				. override_failure_message("a half-built bed is visible after switching to %s" % id)
				. is_true()
			)
	bed.call("finish_pending")
	assert_that(bed.call("get_shown_id")).is_equal(Sub.SAND)
	assert_array(_swaps).override_failure_message("swaps: %s" % [_swaps]).is_equal([Sub.SAND])
	var rapid: Node3D = bed.call("get_shown_view")
	var fresh_bed: Node3D = _bed()
	_show(fresh_bed, Table.SMALL, Sub.SAND)
	fresh_bed.call("finish_pending")
	var fresh: Node3D = fresh_bed.call("get_shown_view")
	assert_int(int(rapid.call("get_unique_stone_count"))).is_equal(
		int(fresh.call("get_unique_stone_count"))
	)
	assert_int(int(rapid.call("get_multimesh_node_count"))).is_equal(
		int(fresh.call("get_multimesh_node_count"))
	)
	assert_str(Scene.tint_mismatch(rapid, Sub.default_colour(_substrates, Sub.SAND))).is_empty()
	await get_tree().process_frame
	await get_tree().process_frame
	(
		assert_int(Node.get_orphan_node_ids().size())
		. override_failure_message("ten rapid switches left orphan nodes")
		. is_less_equal(orphans_before)
	)


func test_ac32_freeing_a_bed_with_a_running_job_waits_for_it_without_an_error() -> void:
	if not _have_classes():
		return
	var script: GDScript = load(Api.BED_PATH) as GDScript
	var bed: Node3D = script.new() as Node3D
	bed.call("setup", (load(Api.CACHE_PATH) as GDScript).new())
	add_child(bed)
	_show(bed, Table.LARGE, Sub.GRAVEL)
	remove_child(bed)
	bed.free()
	assert_bool(is_instance_valid(bed)).is_false()


func test_ac34_the_frame_statistics_can_be_reset() -> void:
	if not _have_classes():
		return
	var bed: Node3D = _bed()
	_show(bed, Table.SMALL, Sub.PEBBLES)
	bed.call("finish_pending")
	bed.call("reset_frame_stats")
	assert_int(_count(bed, "get_max_frame_main_usec")).is_equal(0)
	assert_int(_count(bed, "get_last_frame_main_usec")).is_equal(0)
	assert_int(_count(bed, "get_last_lod_usec")).is_equal(0)
