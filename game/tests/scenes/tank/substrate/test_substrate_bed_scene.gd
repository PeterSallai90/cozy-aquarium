# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #28 criteria 14 and 31, the bed in the room (owner: developer for SubstrateBed and
## room_corner.gd; the tank scenes lose their flat plane: technical-artist). For each of the three
## tanks and each of the five types: no PlaneMesh floor is left in any tank scene, the room adds a
## SubstrateBed named Substrate under SubstrateAnchor, and
## - after substrate_colour_changed (same id, another swatch) the tint of the bed and of every
##   material copy of the shown view (stone or grain, sand top, core) equals the model colour right
##   after history.execute, with no new assembly and the same MultiMesh objects (AC 31);
## - after a type change and finish_pending() the new type is shown, and inside the bed_swapped
##   handler the shown id is the new one and its tint equals the model colour (AC 14).
## Headless tests use finish_pending(); no test waits on frames for the bed.

const Api := preload("res://tests/helpers/substrate_bed_api.gd")
const Rig := preload("res://tests/helpers/room_rig.gd")
const Scene := preload("res://tests/helpers/substrate_scene_rig.gd")
const Sub := preload("res://tests/helpers/substrate_api.gd")
const Table := preload("res://tests/helpers/tank_table.gd")

var _tanks: RefCounted = null
var _substrates: RefCounted = null
var _history: CommandHistory = null


func before_test() -> void:
	_tanks = Rig.default_catalog()
	_substrates = Sub.catalog()
	_history = CommandHistory.new()


func _room(model: AquariumModel) -> Node3D:
	var room: Node3D = Rig.instantiate(model, _tanks)
	add_child(room)
	auto_free(room)
	await get_tree().process_frame
	return room


## The bed of the room after finish_pending(), null after a failed assert.
func _bed(room: Node3D, label: String) -> Node3D:
	var bed: Node3D = Scene.bed_of_room(room)
	(
		assert_object(bed)
		. override_failure_message(
			"%s: %s is missing or not a SubstrateBed" % [label, Scene.BED_IN_ROOM]
		)
		. is_not_null()
	)
	if bed == null:
		return null
	(
		assert_str(Api.class_of(bed))
		. override_failure_message("%s: the node is not a SubstrateBed" % label)
		. is_equal(Scene.BED_CLASS)
	)
	bed.call("finish_pending")
	return bed


func _pick(model: AquariumModel, id: StringName, swatch: int = 1) -> void:
	var colour: Color = Sub.pick(
		_substrates, model.get_substrate_id(), model.get_substrate_colour(), id
	)
	if swatch > 1:
		colour = Sub.swatch(_substrates, id, swatch)
	assert_bool(_history.execute(Sub.command(model, _substrates, id, colour))).is_true()


func _assert_shows(bed: Node3D, id: StringName, colour: Color, label: String) -> void:
	assert_that(bed.call("get_shown_id")).override_failure_message("%s: shown id" % label).is_equal(
		id
	)
	(
		assert_bool(Scene.same_tint(bed.call("get_tint"), colour))
		. override_failure_message("%s: bed tint" % label)
		. is_true()
	)
	var view: Node3D = bed.call("get_shown_view")
	assert_object(view).override_failure_message("%s: no shown view" % label).is_not_null()
	assert_str(Scene.tint_mismatch(view, colour)).override_failure_message(label).is_empty()


# --- the tank scenes ---


func test_ac14_no_tank_scene_keeps_a_flat_plane_or_the_old_layer() -> void:
	for tank_id: StringName in Table.IDS:
		var tank_node: Node3D = Scene.tank_scene(tank_id)
		auto_free(tank_node)
		var anchor: Node3D = tank_node.get_node_or_null(Scene.ANCHOR) as Node3D
		(
			assert_object(anchor)
			. override_failure_message("%s: no SubstrateAnchor" % tank_id)
			. is_not_null()
		)
		if anchor != null:
			(
				assert_that(anchor.position)
				. override_failure_message("%s: anchor moved" % tank_id)
				. is_equal(Vector3.ZERO)
			)
			(
				assert_object(Scene.bed_of_tank(tank_node))
				. override_failure_message(
					"%s: the scene must not carry a ready-made bed, the room adds it" % tank_id
				)
				. is_null()
			)
			for node: Node in anchor.find_children("*", "MeshInstance3D", true, false):
				(
					assert_bool((node as MeshInstance3D).mesh is PlaneMesh)
					. override_failure_message(
						"%s: a PlaneMesh floor %s is left under the anchor" % [tank_id, node.name]
					)
					. is_false()
				)
		# The only PlaneMesh of a tank is the protected water surface (AC 36), outside the anchor
		# (code-reviewer decision, issue #28 comment 6957252973).
		for node: Node in tank_node.find_children("*", "MeshInstance3D", true, false):
			if not (node as MeshInstance3D).mesh is PlaneMesh:
				continue
			var path: String = String(tank_node.get_path_to(node))
			(
				assert_bool(anchor != null and anchor.is_ancestor_of(node))
				. override_failure_message(
					"%s: the PlaneMesh %s lies under SubstrateAnchor" % [tank_id, path]
				)
				. is_false()
			)
			(
				assert_str(path)
				. override_failure_message(
					"%s: PlaneMesh at %s, only WaterVolume/Surface may carry one" % [tank_id, path]
				)
				. is_equal("WaterVolume/Surface")
			)
		var text: String = FileAccess.get_file_as_string(Table.scene_path(tank_id))
		assert_str(text).not_contains("substrate_layer")
		assert_str(text).not_contains("substrate.gdshader")


func test_ac14_the_files_of_the_flat_layer_are_gone() -> void:
	for path: String in Scene.FLAT_LAYER_FILES:
		(
			assert_bool(FileAccess.file_exists(path))
			. override_failure_message("%s still exists" % path)
			. is_false()
		)


# --- the room builds the bed ---


func test_ac14_each_tank_shows_each_type_with_the_model_colour_after_the_swap() -> void:
	for tank_id: StringName in Table.IDS:
		var model: AquariumModel = Sub.model_with(
			Sub.SAND, Sub.default_colour(_substrates, Sub.SAND), tank_id
		)
		var room: Node3D = await _room(model)
		var bed: Node3D = _bed(room, "%s start" % tank_id)
		if bed == null:
			return
		assert_object(bed.get_parent()).is_equal(room.get_node("Tank/SubstrateAnchor"))
		_assert_shows(bed, Sub.SAND, model.get_substrate_colour(), "%s start" % tank_id)
		for id: StringName in [Sub.GRAVEL, Sub.PEBBLES, Sub.BLACK, Sub.COLOURED, Sub.SAND]:
			_pick(model, id)
			bed.call("finish_pending")
			_assert_shows(bed, id, model.get_substrate_colour(), "%s %s" % [tank_id, id])


func test_ac14_the_bed_is_in_the_tank_frame_at_the_anchor() -> void:
	var model: AquariumModel = Sub.model_with(
		Sub.GRAVEL, Sub.default_colour(_substrates, Sub.GRAVEL)
	)
	var room: Node3D = await _room(model)
	var bed: Node3D = _bed(room, "gravel")
	if bed == null:
		return
	assert_that(bed.position).is_equal(Vector3.ZERO)
	assert_that(bed.transform.basis).is_equal(Basis.IDENTITY)
	assert_that((room.get_node("Tank/SubstrateAnchor") as Node3D).position).is_equal(Vector3.ZERO)


# --- the colour ---


func test_ac14_a_colour_change_reaches_the_bed_and_every_material_copy_in_the_same_frame() -> void:
	for id: StringName in Sub.IDS:
		var model: AquariumModel = Sub.model_with(
			id, Sub.default_colour(_substrates, id), Table.SMALL
		)
		var room: Node3D = await _room(model)
		var bed: Node3D = _bed(room, String(id))
		if bed == null:
			return
		var assemblies: int = int(bed.call("get_assembly_count"))
		var second: Color = Sub.swatch(_substrates, id, 2)
		assert_bool(_history.execute(Sub.command(model, _substrates, id, second))).is_true()
		# No frame, no finish_pending: the tint is applied inside the signal handler.
		_assert_shows(bed, id, second, "%s swatch 2" % id)
		(
			assert_int(int(bed.call("get_assembly_count")))
			. override_failure_message("%s: a colour change assembled" % id)
			. is_equal(assemblies)
		)
		assert_bool(bool(bed.call("is_building"))).is_false()
		assert_bool(_history.undo()).is_true()
		_assert_shows(bed, id, Sub.default_colour(_substrates, id), "%s after undo" % id)


func test_ac31_a_colour_change_keeps_every_multimesh_and_assembles_nothing() -> void:
	var model: AquariumModel = Sub.model_with(
		Sub.GRAVEL, Sub.default_colour(_substrates, Sub.GRAVEL), Table.SMALL
	)
	var room: Node3D = await _room(model)
	var bed: Node3D = _bed(room, "gravel")
	if bed == null:
		return
	var view: Node3D = bed.call("get_shown_view")
	var value_before: Array[MultiMesh] = []
	for instance: GeometryInstance3D in Scene.geometry_below(view):
		if instance is MultiMeshInstance3D:
			value_before.append((instance as MultiMeshInstance3D).multimesh)
	assert_int(value_before.size()).is_greater(0)
	(
		assert_bool(
			_history.execute(
				Sub.command(model, _substrates, Sub.GRAVEL, Sub.swatch(_substrates, Sub.GRAVEL, 2))
			)
		)
		. is_true()
	)
	var value_after: Array[MultiMesh] = []
	for instance: GeometryInstance3D in Scene.geometry_below(bed.call("get_shown_view")):
		if instance is MultiMeshInstance3D:
			value_after.append((instance as MultiMeshInstance3D).multimesh)
	(
		assert_bool(is_same(view, bed.call("get_shown_view")))
		. override_failure_message("the shown view was replaced")
		. is_true()
	)
	assert_int(value_after.size()).is_equal(value_before.size())
	for index: int in value_before.size():
		assert_bool(is_same(value_before[index], value_after[index])).is_true()


# --- the swap ---


func test_ac14_inside_the_swap_the_shown_id_is_new_and_the_tint_is_the_model_colour() -> void:
	var model: AquariumModel = Sub.model_with(Sub.SAND, Sub.SAND_DEFAULT, Table.SMALL)
	var room: Node3D = await _room(model)
	var bed: Node3D = _bed(room, "sand")
	if bed == null:
		return
	var seen: Array[Dictionary] = []
	bed.connect(
		&"bed_swapped",
		func(swapped_id: StringName) -> void:
			(
				seen
				. append(
					{
						"signal": swapped_id,
						"shown": bed.call("get_shown_id"),
						"tint": bed.call("get_tint"),
						"view": bed.call("get_shown_view"),
					}
				)
			)
	)
	_pick(model, Sub.PEBBLES)
	bed.call("finish_pending")
	(
		assert_int(seen.size())
		. override_failure_message("bed_swapped fired %d times" % seen.size())
		. is_equal(1)
	)
	if seen.is_empty():
		return
	assert_that(seen[0]["signal"]).is_equal(Sub.PEBBLES)
	assert_that(seen[0]["shown"]).is_equal(Sub.PEBBLES)
	assert_bool(Scene.same_tint(seen[0]["tint"], model.get_substrate_colour())).is_true()
	assert_str(Scene.tint_mismatch(seen[0]["view"], model.get_substrate_colour())).is_empty()


func test_ac14_make_input_copies_the_tank_the_type_and_the_fill_depth() -> void:
	(
		assert_bool(Api.script_exists(Api.BED_PATH))
		. override_failure_message("%s is missing" % Api.BED_PATH)
		. is_true()
	)
	if not Api.script_exists(Api.BED_PATH):
		return
	var script: GDScript = load(Api.BED_PATH) as GDScript
	for tank_id: StringName in Table.IDS:
		for id: StringName in Sub.IDS:
			var input: RefCounted = script.call(
				"make_input", Rig.definition_of(tank_id), Sub.definition(_substrates, id)
			)
			assert_object(input).override_failure_message("make_input returned null").is_not_null()
			if input == null:
				return
			assert_that(input.get("tank_id")).is_equal(tank_id)
			assert_that(input.get("substrate_id")).is_equal(id)
			assert_that(input.get("interior_size_m")).is_equal(Table.interior(tank_id))
			assert_float(float(input.get("fill_depth_m"))).is_equal_approx(Api.fill_depth(id), 1e-9)
