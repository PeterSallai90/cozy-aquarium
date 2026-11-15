# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #28 criteria 14, 27, 28, 29, 31, 33, 39 and 40, the built bed of one type (owner:
## technical-artist: SubstrateBedView, the materials, the shaders' parameters). A view is built from
## assembled data and a look: Core and CoreFloor at once, then the chunks in steps
## (Chunk_<ix>_<iz>_v<n>), and for sand SandSurface under the grains and SandTop_<a>_<b> cells.
## Tests build the view from the
## fixture data with build_all() and the steps API, in the tree, without frames. MultiMesh buffers
## cannot be read back headless (dummy render server), so the instance data is checked on the
## assembled data and the nodes, meshes, materials and visibility here.

const Api := preload("res://tests/helpers/substrate_bed_api.gd")
const Checks := preload("res://tests/helpers/proof_fish_checks.gd")
const Fixture := preload("res://tests/helpers/substrate_bed_fixture.gd")
const Rig := preload("res://tests/helpers/substrate_scene_rig.gd")
const Sub := preload("res://tests/helpers/substrate_api.gd")
const Table := preload("res://tests/helpers/tank_table.gd")
const Views := preload("res://tests/helpers/substrate_views.gd")

const SWATCH := Color(0.2, 0.4, 0.6)
const SHADER_BY_PART: Dictionary = {
	"stone": "substrate_stone",
	"grain": "substrate_sand_grain",
	"top": "substrate_sand_top",
	"core": "substrate_core",
}
const MAX_STEPS := 100000
const STEP_USEC := 1000
const AABB_TOLERANCE := 1e-5


func _ready_for(tank_id: StringName, id: StringName) -> bool:
	var missing: String = Api.missing_script([Api.VIEW_PATH])
	assert_str(missing).is_empty()
	var why: String = Fixture.analysis_problem(tank_id, id)
	assert_str(why).override_failure_message("%s in %s: %s" % [id, tank_id, why]).is_empty()
	return missing.is_empty() and why.is_empty()


## A view in the tree, begun but not built.
func _begun(tank_id: StringName, id: StringName) -> Node3D:
	var script: GDScript = load(Api.VIEW_PATH) as GDScript
	var view: Node3D = script.new() as Node3D
	add_child(view)
	auto_free(view)
	view.call("begin", Fixture.bed_of(tank_id, id), Api.look_of(id))
	return view


func _built(tank_id: StringName, id: StringName) -> Node3D:
	var view: Node3D = _begun(tank_id, id)
	view.call("build_all")
	return view


func _shader_name(material: Material) -> String:
	var shader_material: ShaderMaterial = material as ShaderMaterial
	if shader_material == null or shader_material.shader == null:
		return ""
	return shader_material.shader.resource_path.get_file().get_basename()


func _node_shaders(node: GeometryInstance3D) -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	for material: Material in Rig.materials_of(node):
		names.append(_shader_name(material))
	return names


# --- begin, steps, complete ---


func test_ac32_begin_shows_the_core_and_the_floor_skin_at_once_without_stones() -> void:
	for id: StringName in Sub.IDS:
		if not _ready_for(Table.SMALL, id):
			return
		var view: Node3D = _begun(Table.SMALL, id)
		(
			assert_object(view.get_node_or_null("Core"))
			. override_failure_message("%s: no Core" % id)
			. is_not_null()
		)
		(
			assert_object(view.get_node_or_null("CoreFloor"))
			. override_failure_message("%s: no CoreFloor" % id)
			. is_not_null()
		)
		assert_bool((view.get_node("Core") as Node3D).is_visible_in_tree()).is_true()
		assert_bool((view.get_node("CoreFloor") as Node3D).is_visible_in_tree()).is_true()
		assert_bool(bool(view.call("is_complete"))).is_false()
		(
			assert_int(int(view.call("get_multimesh_node_count")))
			. override_failure_message("%s: stones before the first build step" % id)
			. is_equal(0)
		)


func test_ac32_build_step_always_progresses_and_ends_complete_with_the_same_nodes_as_build_all(
) -> void:
	for id: StringName in [Sub.PEBBLES, Sub.GRAVEL, Sub.SAND]:
		if not _ready_for(Table.SMALL, id):
			return
		var stepped: Node3D = _begun(Table.SMALL, id)
		var steps: int = 0
		while not bool(stepped.call("build_step", STEP_USEC)) and steps < MAX_STEPS:
			steps += 1
		assert_int(steps).override_failure_message("%s: build_step never completed" % id).is_less(
			MAX_STEPS
		)
		assert_bool(bool(stepped.call("is_complete"))).is_true()
		var all_at_once: Node3D = _built(Table.SMALL, id)
		assert_bool(bool(all_at_once.call("is_complete"))).is_true()
		(
			assert_int(int(stepped.call("get_multimesh_node_count")))
			. override_failure_message("%s: stepping and build_all differ" % id)
			. is_equal(int(all_at_once.call("get_multimesh_node_count")))
		)
		assert_int(int(stepped.call("get_multimesh_node_count"))).is_greater(0)


func test_ac32_a_tiny_budget_still_builds_something_each_step() -> void:
	if not _ready_for(Table.SMALL, Sub.GRAVEL):
		return
	var view: Node3D = _begun(Table.SMALL, Sub.GRAVEL)
	var before: int = int(view.call("get_multimesh_node_count"))
	view.call("build_step", 1)
	(
		assert_int(int(view.call("get_multimesh_node_count")))
		. override_failure_message(
			"a step with a 1 microsecond budget built nothing, the build could stall"
		)
		. is_greater(before)
	)


func test_ac14_the_node_names_follow_the_plan() -> void:
	for id: StringName in Sub.IDS:
		if not _ready_for(Table.SMALL, id):
			return
		var view: Node3D = _built(Table.SMALL, id)
		var chunk: RegEx = RegEx.create_from_string("^Chunk_-?\\d+_-?\\d+_v\\d+$")
		var top: RegEx = RegEx.create_from_string("^SandTop_-?\\d+_-?\\d+$")
		var chunks: int = 0
		var tops: int = 0
		for instance: GeometryInstance3D in Rig.geometry_below(view):
			var node_name: String = String(instance.name)
			if instance is MultiMeshInstance3D:
				if top.search(node_name) != null:
					tops += 1
				else:
					(
						assert_object(chunk.search(node_name))
						. override_failure_message(
							(
								"%s: stone node %s is not named Chunk_<ix>_<iz>_v<n> or SandTop_<a>_<b>"
								% [id, node_name]
							)
						)
						. is_not_null()
					)
					chunks += 1
		assert_int(chunks).override_failure_message("%s: no chunk nodes" % id).is_greater(0)
		if Api.is_sand(id):
			assert_int(tops).override_failure_message("%s: no SandTop cells" % id).is_greater(0)
			assert_object(view.get_node_or_null("SandSurface")).is_not_null()
		else:
			(
				assert_int(tops)
				. override_failure_message("%s: SandTop cells on a stone bed" % id)
				. is_equal(0)
			)
			assert_object(view.get_node_or_null("SandSurface")).is_null()


# --- core, skin, sand surface ---


func test_ac39_the_core_box_is_the_core_of_the_data() -> void:
	for id: StringName in Sub.IDS:
		if not _ready_for(Table.MEDIUM, id):
			return
		var view: Node3D = _begun(Table.MEDIUM, id)
		var data: RefCounted = Fixture.bed_of(Table.MEDIUM, id)
		var box: AABB = Rig.aabb_in_view(view.get_node("Core") as MeshInstance3D, view)
		var centre: Vector3 = data.get("core_centre")
		var size: Vector3 = data.get("core_size")
		assert_that(box.size).override_failure_message("%s: core size" % id).is_equal_approx(
			size, Vector3.ONE * AABB_TOLERANCE
		)
		(
			assert_that(box.get_center())
			. override_failure_message("%s: core centre" % id)
			. is_equal_approx(centre, Vector3.ONE * AABB_TOLERANCE)
		)


func test_ac28_the_floor_skin_covers_the_whole_interior_footprint_and_nothing_more() -> void:
	for tank_id: StringName in Table.IDS:
		for id: StringName in Sub.IDS:
			if not _ready_for(tank_id, id):
				return
			var view: Node3D = _begun(tank_id, id)
			var skin: AABB = Rig.aabb_in_view(view.get_node("CoreFloor") as MeshInstance3D, view)
			var interior: Vector3 = Table.interior(tank_id)
			var label: String = "%s in %s" % [id, tank_id]
			assert_float(skin.position.x).override_failure_message(label).is_equal_approx(
				-interior.x / 2.0, AABB_TOLERANCE
			)
			assert_float(skin.end.x).override_failure_message(label).is_equal_approx(
				interior.x / 2.0, AABB_TOLERANCE
			)
			assert_float(skin.position.z).override_failure_message(label).is_equal_approx(
				-interior.z / 2.0, AABB_TOLERANCE
			)
			assert_float(skin.end.z).override_failure_message(label).is_equal_approx(
				interior.z / 2.0, AABB_TOLERANCE
			)
			(
				assert_float(skin.position.y)
				. override_failure_message("%s: the skin is below the floor" % label)
				. is_greater_equal(-AABB_TOLERANCE)
			)
			(
				assert_float(skin.end.y)
				. override_failure_message("%s: the skin is thick" % label)
				. is_less_equal(Api.fill_depth(id))
			)


func test_ac40_the_procedural_sand_surface_lies_under_the_grains_not_above_the_nominal_top(
) -> void:
	for id: StringName in Api.SAND_IDS:
		if not _ready_for(Table.MEDIUM, id):
			return
		var view: Node3D = _begun(Table.MEDIUM, id)
		var surface: MeshInstance3D = view.get_node_or_null("SandSurface") as MeshInstance3D
		assert_object(surface).override_failure_message("%s: no SandSurface" % id).is_not_null()
		if surface == null:
			continue
		var top: float = Rig.aabb_in_view(surface, view).end.y
		(
			assert_float(top)
			. override_failure_message(
				(
					"%s: the sand surface top %.4f is above the nominal %.3f"
					% [id, top, Api.fill_depth(id)]
				)
			)
			. is_less_equal(Api.fill_depth(id) + AABB_TOLERANCE)
		)
		(
			assert_float(top)
			. override_failure_message("%s: the sand surface is too deep to show" % id)
			. is_greater(Api.fill_depth(id) - 0.01)
		)


# --- materials and tint ---


func test_ac39_every_node_uses_the_shader_of_its_part() -> void:
	for id: StringName in Sub.IDS:
		if not _ready_for(Table.SMALL, id):
			return
		var view: Node3D = _built(Table.SMALL, id)
		for instance: GeometryInstance3D in Rig.geometry_below(view):
			var shaders: PackedStringArray = _node_shaders(instance)
			var node_name: String = String(instance.name)
			var wanted: String = ""
			if node_name == "Core" or node_name == "CoreFloor":
				wanted = SHADER_BY_PART["core"]
			elif node_name == "SandSurface":
				wanted = SHADER_BY_PART["top"]
			elif Api.is_sand(id):
				wanted = SHADER_BY_PART["grain"]
			else:
				wanted = SHADER_BY_PART["stone"]
			(
				assert_array(shaders)
				. override_failure_message("%s: %s has no material" % [id, node_name])
				. is_not_empty()
			)
			for shader_name: String in shaders:
				(
					assert_str(shader_name)
					. override_failure_message(
						"%s: %s uses shader %s, wanted %s" % [id, node_name, shader_name, wanted]
					)
					. is_equal(wanted)
				)


func test_ac31_set_tint_reaches_every_material_of_the_view_in_the_same_call() -> void:
	for id: StringName in Sub.IDS:
		if not _ready_for(Table.SMALL, id):
			return
		var view: Node3D = _built(Table.SMALL, id)
		view.call("set_tint", SWATCH)
		(
			assert_bool(Rig.same_tint(view.call("get_tint"), SWATCH))
			. override_failure_message("%s: get_tint" % id)
			. is_true()
		)
		assert_str(Rig.tint_mismatch(view, SWATCH)).override_failure_message(id).is_empty()
		view.call("set_tint", Sub.SAND_DEFAULT)
		(
			assert_str(Rig.tint_mismatch(view, Sub.SAND_DEFAULT))
			. override_failure_message(id)
			. is_empty()
		)


func test_ac31_the_view_works_on_copies_and_never_changes_the_look_materials() -> void:
	for id: StringName in Sub.IDS:
		if not _ready_for(Table.SMALL, id):
			return
		var look: Resource = Api.look_of(id)
		var before: Dictionary = {}
		for property: String in [
			"stone_material", "grain_material", "top_material", "core_material"
		]:
			var material: ShaderMaterial = look.get(property) as ShaderMaterial
			if material != null:
				before[property] = Rig.tint_of_material(material)
		var view: Node3D = _built(Table.SMALL, id)
		view.call("set_tint", SWATCH)
		for property: String in before:
			var material: ShaderMaterial = look.get(property) as ShaderMaterial
			(
				assert_bool(Rig.same_tint(Rig.tint_of_material(material), before[property]))
				. override_failure_message("%s: the look's %s was changed" % [id, property])
				. is_true()
			)
			for tinted: Material in Rig.tinted_materials(view):
				(
					assert_bool(is_same(tinted, material))
					. override_failure_message(
						"%s: the view uses the look's %s itself, not a copy" % [id, property]
					)
					. is_false()
				)


func test_ac31_a_tint_change_keeps_every_multimesh_object() -> void:
	for id: StringName in [Sub.GRAVEL, Sub.SAND]:
		if not _ready_for(Table.SMALL, id):
			return
		var view: Node3D = _built(Table.SMALL, id)
		var before: Array[MultiMesh] = []
		for instance: GeometryInstance3D in Rig.geometry_below(view):
			if instance is MultiMeshInstance3D:
				before.append((instance as MultiMeshInstance3D).multimesh)
		view.call("set_tint", SWATCH)
		var after: Array[MultiMesh] = []
		for instance: GeometryInstance3D in Rig.geometry_below(view):
			if instance is MultiMeshInstance3D:
				after.append((instance as MultiMeshInstance3D).multimesh)
		assert_int(after.size()).is_equal(before.size())
		for index: int in before.size():
			(
				assert_bool(is_same(before[index], after[index]))
				. override_failure_message(
					"%s: MultiMesh %d was replaced by a tint change" % [id, index]
				)
				. is_true()
			)


func test_ac32_hiding_the_stones_leaves_the_core_visible() -> void:
	if not _ready_for(Table.SMALL, Sub.GRAVEL):
		return
	var view: Node3D = _built(Table.SMALL, Sub.GRAVEL)
	assert_bool(Rig.stones_visible(view)).is_true()
	view.call("set_stones_visible", false)
	assert_bool(Rig.stones_visible(view)).is_false()
	assert_bool((view.get_node("Core") as Node3D).is_visible_in_tree()).is_true()
	assert_bool((view.get_node("CoreFloor") as Node3D).is_visible_in_tree()).is_true()
	view.call("set_stones_visible", true)
	assert_bool(Rig.stones_visible(view)).is_true()


# --- counts and the estimate ---


func test_ac33_the_view_reports_the_stones_and_the_memory_of_its_data() -> void:
	for id: StringName in Sub.IDS:
		if not _ready_for(Table.MEDIUM, id):
			return
		var view: Node3D = _built(Table.MEDIUM, id)
		var data: RefCounted = Fixture.bed_of(Table.MEDIUM, id)
		assert_int(int(view.call("get_unique_stone_count"))).override_failure_message(id).is_equal(
			int(data.call("unique_stone_count"))
		)
		assert_int(int(view.call("get_memory_bytes"))).is_greater(0)


func test_ac33_the_estimate_of_the_view_is_the_estimate_of_the_lod_helper() -> void:
	if not (_ready_for(Table.LARGE, Sub.GRAVEL) and _ready_for(Table.LARGE, Sub.SAND)):
		return
	for id: StringName in [Sub.GRAVEL, Sub.SAND]:
		var view: Node3D = _built(Table.LARGE, id)
		for view_name: String in [Views.DEFAULT_VIEW, "glass_close_front", "top_35"]:
			var pose: Dictionary = Views.pose_of(view_name, Table.LARGE, Api.fill_depth(id))
			var camera: Camera3D = Views.make_camera(pose)
			add_child(camera)
			auto_free(camera)
			var estimate: int = int(view.call("get_drawn_triangle_estimate", camera))
			var lod: GDScript = load(Api.LOD_PATH) as GDScript
			var grains: Dictionary = Fixture.grains_of(Api.look_of(id))
			var expected: int = int(
				lod.call(
					"estimate_triangles",
					Fixture.bed_of(Table.LARGE, id),
					Api.look_of(id),
					grains["triangles"],
					Views.frustum(pose),
					pose["position"]
				)
			)
			(
				assert_int(estimate)
				. override_failure_message(
					(
						"%s at %s: the view says %d, the helper %d"
						% [id, view_name, estimate, expected]
					)
				)
				. is_between(int(float(expected) * 0.95), int(float(expected) * 1.05) + 1)
			)


# --- LOD and the sand range ---


func _chunk_nodes(view: Node3D) -> Array[MultiMeshInstance3D]:
	var found: Array[MultiMeshInstance3D] = []
	for instance: GeometryInstance3D in Rig.geometry_below(view):
		if instance is MultiMeshInstance3D and String(instance.name).begins_with("Chunk_"):
			found.append(instance as MultiMeshInstance3D)
	return found


## The box of the chunk a node named Chunk_<ix>_<iz>_v<n> draws, from the assembled data.
func _chunk_box(data: RefCounted, node_name: String) -> AABB:
	var pattern: RegEx = RegEx.create_from_string("^Chunk_(-?\\d+)_(-?\\d+)_v\\d+$")
	var parts: RegExMatch = pattern.search(node_name)
	if parts == null:
		return AABB()
	var key: Vector2i = Vector2i(int(parts.get_string(1)), int(parts.get_string(2)))
	var chunks: Array = data.get("chunks")
	for chunk: RefCounted in chunks:
		if chunk.get("key") == key:
			return chunk.get("aabb")
	return AABB()


func test_ac33_chunks_near_the_camera_use_a_finer_lod_than_far_chunks() -> void:
	for id: StringName in [Sub.GRAVEL, Sub.PEBBLES]:
		if not _ready_for(Table.LARGE, id):
			return
		var view: Node3D = _built(Table.LARGE, id)
		var camera_local: Vector3 = Vector3(-0.45, Api.fill_depth(id) + 0.03, 0.18)
		view.call("update_lod", camera_local)
		var data: RefCounted = Fixture.bed_of(Table.LARGE, id)
		var near: MultiMeshInstance3D = null
		var far: MultiMeshInstance3D = null
		var near_distance: float = INF
		var far_distance: float = -INF
		for node: MultiMeshInstance3D in _chunk_nodes(view):
			var box: AABB = _chunk_box(data, String(node.name))
			var distance: float = box.get_center().distance_to(camera_local)
			if distance < near_distance:
				near_distance = distance
				near = node
			if distance > far_distance:
				far_distance = distance
				far = node
		assert_object(near).is_not_null()
		assert_object(far).is_not_null()
		if near == null or far == null:
			continue
		(
			assert_int(Checks.triangle_count(near.multimesh.mesh))
			. override_failure_message(
				"%s: the nearest chunk is not drawn finer than the farthest" % id
			)
			. is_greater(Checks.triangle_count(far.multimesh.mesh))
		)


func test_ac33_a_second_lod_update_from_the_same_place_changes_nothing() -> void:
	if not _ready_for(Table.MEDIUM, Sub.GRAVEL):
		return
	var view: Node3D = _built(Table.MEDIUM, Sub.GRAVEL)
	var camera_local: Vector3 = Vector3(0.1, 0.1, 0.3)
	view.call("update_lod", camera_local)
	var before: Array[Mesh] = []
	for node: MultiMeshInstance3D in _chunk_nodes(view):
		before.append(node.multimesh.mesh)
	view.call("update_lod", camera_local)
	var index: int = 0
	for node: MultiMeshInstance3D in _chunk_nodes(view):
		(
			assert_bool(is_same(before[index], node.multimesh.mesh))
			. override_failure_message(
				"chunk %s changed its mesh without the camera moving" % node.name
			)
			. is_true()
		)
		index += 1


func test_ac40_sand_top_cells_near_the_camera_are_drawn_and_those_beyond_the_range_are_not(
) -> void:
	for id: StringName in Api.SAND_IDS:
		if not _ready_for(Table.LARGE, id):
			return
		var view: Node3D = _built(Table.LARGE, id)
		var camera_local: Vector3 = Vector3(0.1, Api.fill_depth(id) + 0.35, 0.02)
		view.call("update_lod", camera_local)
		var range_end: float = float(Api.look_of(id).get("sand_range_end_m"))
		var near: int = 0
		var far: int = 0
		for instance: GeometryInstance3D in Rig.geometry_below(view):
			if not (
				instance is MultiMeshInstance3D and String(instance.name).begins_with("SandTop_")
			):
				continue
			var centre: Vector3 = (instance as Node3D).position
			centre.y = Api.fill_depth(id)
			var distance: float = centre.distance_to(camera_local)
			if distance <= 0.7 - 0.05:
				near += 1
				(
					assert_bool(instance.visible)
					. override_failure_message(
						(
							"%s: %s is %.3f m from the camera and not drawn"
							% [id, instance.name, distance]
						)
					)
					. is_true()
				)
			elif distance >= range_end + 0.05:
				far += 1
				(
					assert_bool(instance.visible)
					. override_failure_message(
						(
							"%s: %s is %.3f m from the camera, beyond the range end %.2f, and drawn"
							% [id, instance.name, distance, range_end]
						)
					)
					. is_false()
				)
		(
			assert_int(near)
			. override_failure_message("%s: no sand cell near the camera" % id)
			. is_greater(0)
		)
		(
			assert_int(far)
			. override_failure_message("%s: no sand cell beyond the range" % id)
			. is_greater(0)
		)
