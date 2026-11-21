# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #34 AC 16 to 19, 26 (view part), 27, 28 and 29 (owner: developer): FishView
## (game/scenes/tank/fish/fish_view.gd), the presentation node under the room's tank frame. One pose
## node per fish uid (get_fish_node(uid), position and yaw) whose only child is the species scene,
## scaled by adult_length_cm / 100; the four instance parameters variant_tint_colour,
## variant_tint_strength, swim_phase and swim_speed on every GeometryInstance3D; cast_shadow off
## and extra_cull_margin 0.15; the handlers for fish_added, fish_removed, fish_changed,
## tank_changed, substrate_changed, heightmap_changed and model_reset reposition synchronously
## (checked right after the call, no frame wait). The pose is the pure function of ADR 0013,
## recomputed here with FishRestPose and the real model extents.
## Test decisions where the plan is silent: setup() is called after the view entered the tree;
## a fish node leaves the tree at the next frame at the latest (the tests wait one frame);
## get_skipped lists only the unknown-species entries, not the variant fallback;
## ChangeTankCommand clears the
## fish of the model by design (#24), so after its do() the nodes are gone with the fish and after
## its undo() they are back at the exact earlier pose; the "never outside the new tank" edge of
## AC 27 is checked on a tank_changed that leaves the fish in the model (a direct tank id change).

const Api := preload("res://tests/helpers/fish_api.gd")
const FishRig := preload("res://tests/helpers/fish_view_rig.gd")
const Checks := preload("res://tests/helpers/fish_species_checks.gd")
const Glb := preload("res://tests/helpers/glb_mesh_checks.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")
const SaveFixtures := preload("res://tests/helpers/save_fixtures.gd")

const POSE_EPS := 1e-5
const GOOD_FIXTURE := "res://tests/fixtures/saves/fish_three_species_v1.json"
const BAD_FIXTURE := "res://tests/fixtures/saves/fish_bad_entries_v1.json"


func _open(source: AquariumModel, catalog: RefCounted = null) -> FishRig.Rig:
	var rig: FishRig.Rig = FishRig.open(self, source, catalog)
	(
		assert_object(rig.view)
		. override_failure_message("FishView script is missing or has no setup()")
		. is_not_null()
	)
	return rig


func _ready_rig(source: AquariumModel, catalog: RefCounted = null) -> FishRig.Rig:
	var rig: FishRig.Rig = _open(source, catalog)
	if rig.view == null or Api.shipped() == null:
		assert_bool(false).override_failure_message("FishView or FishCatalog is missing").is_true()
		return null
	return rig


func _frame() -> void:
	await get_tree().process_frame


func _params(node: Node3D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for instance: GeometryInstance3D in FishRig.geometry(node):
		(
			result
			. append(
				{
					"colour": instance.get_instance_shader_parameter("variant_tint_colour"),
					"strength": instance.get_instance_shader_parameter("variant_tint_strength"),
					"phase": instance.get_instance_shader_parameter("swim_phase"),
					"speed": instance.get_instance_shader_parameter("swim_speed"),
				}
			)
		)
	return result


func _variant_colour(id: StringName, variant: int) -> Color:
	return (Api.field(id, "colour_variants", []) as Array)[variant]


func _decoded(path: String) -> AquariumModel:
	var text: String = FileAccess.get_file_as_string(path)
	var result: SaveResult = SaveCodec.new().decode(text, FishRig.STAMP)
	assert_bool(result.is_ok()).override_failure_message("%s: %s" % [path, result.detail]).is_true()
	return SaveFixtures.model_of(result)


# --- structure, scale and instance parameters (AC 17, 18) ---


func test_ac18_one_pose_node_per_entry_with_the_species_scene_as_its_only_child() -> void:
	var rig: FishRig.Rig = _ready_rig(_decoded(GOOD_FIXTURE))
	if rig == null:
		return
	assert_int(rig.model.get_fish_count()).is_equal(7)
	assert_int(rig.view.get_child_count()).is_equal(7)
	for entry: FishInstance in rig.model.get_fish_list():
		var node: Node3D = FishRig.node_of(rig, entry.uid)
		assert_object(node).override_failure_message("no node for %s" % entry.uid).is_not_null()
		if node == null:
			continue
		assert_int(node.get_child_count()).is_equal(1)
		var scene: PackedScene = Api.field(entry.species_id, "scene", null) as PackedScene
		(
			assert_str(node.get_child(0).scene_file_path)
			. override_failure_message("%s does not use the species scene" % entry.uid)
			. is_equal(scene.resource_path)
		)


func test_ac17_the_species_root_scale_is_adult_length_cm_over_100_on_all_axes() -> void:
	var rig: FishRig.Rig = _ready_rig(FishRig.trio())
	if rig == null:
		return
	for entry: FishInstance in rig.model.get_fish_list():
		var node: Node3D = FishRig.node_of(rig, entry.uid)
		if node == null:
			assert_bool(false).override_failure_message("no node for %s" % entry.uid).is_true()
			continue
		var side: float = float(Api.field(entry.species_id, "adult_length_cm", -1.0)) / 100.0
		(
			assert_vector((node.get_child(0) as Node3D).scale)
			. override_failure_message("%s scale" % entry.species_id)
			. is_equal_approx(Vector3.ONE * side, Vector3.ONE * 1e-7)
		)
		assert_vector(node.scale).is_equal_approx(Vector3.ONE, Vector3.ONE * 1e-7)


func test_ac17_changing_adult_length_cm_in_a_test_catalog_changes_the_size() -> void:
	var longer: Resource = Api.variant_of(Api.NEON, {"adult_length_cm": 6.0})
	if longer == null:
		assert_bool(false).override_failure_message("FishSpecies is missing").is_true()
		return
	var catalog: RefCounted = Api.catalog_from([longer])
	var rig: FishRig.Rig = _ready_rig(
		FishRig.model(FishRig.MEDIUM, FishRig.SAND, [FishRig.fish("f1000001", Api.NEON)]), catalog
	)
	if rig == null:
		return
	var node: Node3D = FishRig.node_of(rig, "f1000001")
	assert_object(node).is_not_null()
	if node != null:
		assert_vector((node.get_child(0) as Node3D).scale).is_equal_approx(
			Vector3.ONE * 0.06, Vector3.ONE * 1e-7
		)


func test_ac18_every_fish_geometry_has_the_four_instance_parameters_shadow_off_and_the_margin(
) -> void:
	var rig: FishRig.Rig = _ready_rig(_decoded(GOOD_FIXTURE))
	if rig == null:
		return
	for entry: FishInstance in rig.model.get_fish_list():
		var node: Node3D = FishRig.node_of(rig, entry.uid)
		if node == null:
			assert_bool(false).override_failure_message("no node for %s" % entry.uid).is_true()
			continue
		var species_speed: float = Api.field(entry.species_id, "swim_speed", 0.0)
		var wanted_phase: float = TAU * Api.expected_unit(entry.uid, "fish.swim.phase")
		var geometries: Array[GeometryInstance3D] = FishRig.geometry(node)
		assert_int(geometries.size()).is_greater(0)
		for instance: GeometryInstance3D in geometries:
			var label: String = "%s %s" % [entry.species_id, entry.uid]
			(
				assert_int(instance.cast_shadow)
				. override_failure_message(label + " casts a shadow")
				. is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			)
			assert_float(instance.extra_cull_margin).is_equal_approx(0.15, 1e-6)
			var colour: Variant = instance.get_instance_shader_parameter("variant_tint_colour")
			assert_bool(colour is Color).override_failure_message(label + " tint colour").is_true()
			if colour is Color:
				(
					assert_bool(
						(
							(colour as Color).to_rgba32()
							== _variant_colour(entry.species_id, entry.variant).to_rgba32()
						)
					)
					. override_failure_message(
						label + " tint colour is not colour_variants[variant]"
					)
					. is_true()
				)
			(
				assert_float(float(instance.get_instance_shader_parameter("variant_tint_strength")))
				. override_failure_message(label + " tint strength")
				. is_equal(0.0 if entry.variant == 0 else 1.0)
			)
			(
				assert_float(float(instance.get_instance_shader_parameter("swim_phase")))
				. override_failure_message(label + " swim phase")
				. is_equal_approx(wanted_phase, 1e-5)
			)
			(
				assert_float(float(instance.get_instance_shader_parameter("swim_speed")))
				. override_failure_message(label + " swim speed")
				. is_equal_approx(minf(species_speed * FishRig.IDLE_FACTOR, 1.0), 1e-6)
			)


func test_ac21_the_idle_speed_factor_is_0_35_and_the_three_species_bend_at_different_rates(
) -> void:
	assert_float(Api.constant(Api.VIEW_PATH, "IDLE_SPEED_FACTOR", -1.0)).is_equal_approx(0.35, 1e-6)
	var rig: FishRig.Rig = _ready_rig(FishRig.trio())
	if rig == null:
		return
	var seen: Dictionary = {}
	for uid: String in ["f1000001", "f1000003", "f1000006"]:
		var node: Node3D = FishRig.node_of(rig, uid)
		if node == null:
			assert_bool(false).override_failure_message("no node for %s" % uid).is_true()
			return
		seen[roundi(float(_params(node)[0]["speed"]) * 10000.0)] = true
	assert_int(seen.size()).is_equal(3)
	assert_bool(seen.has(4550) and seen.has(2800) and seen.has(1750)).is_true()


func test_ac18_the_swim_phase_differs_between_fish_and_uses_its_own_salt() -> void:
	var rig: FishRig.Rig = _ready_rig(_decoded(GOOD_FIXTURE))
	if rig == null:
		return
	var phases: Dictionary = {}
	for entry: FishInstance in rig.model.get_fish_list():
		var node: Node3D = FishRig.node_of(rig, entry.uid)
		if node != null:
			phases[snappedf(float(_params(node)[0]["phase"]), 1e-6)] = true
	assert_int(phases.size()).is_equal(7)
	# The rest pose and the swim phase use different salts: x and the phase are not the same unit.
	(
		assert_bool(
			is_equal_approx(
				Api.expected_unit("f1000001", "fish.swim.phase"),
				Api.expected_unit("f1000001", "fish.rest.x")
			)
		)
		. is_false()
	)


func test_ac18_the_phase_and_the_pose_are_never_written_to_the_save_file() -> void:
	var rig: FishRig.Rig = _ready_rig(_decoded(GOOD_FIXTURE))
	if rig == null:
		return
	var result: SaveResult = SaveCodec.new().encode(rig.model, FishRig.STAMP)
	assert_bool(result.is_ok()).is_true()
	var parsed: Dictionary = JSON.parse_string(result.text)
	for entry: Dictionary in parsed["fish"]:
		assert_array(entry.keys()).is_equal(["uid", "species_id", "variant", "nickname"])
	assert_int(int(parsed["format_version"])).is_equal(1)


func test_the_view_has_no_per_frame_process() -> void:
	var rig: FishRig.Rig = _ready_rig(FishRig.trio())
	if rig == null:
		return
	assert_bool(rig.view.has_method("_process")).is_false()
	assert_bool(rig.view.has_method("_physics_process")).is_false()
	assert_bool(rig.view.is_processing()).is_false()


# --- lifecycle (AC 18) ---


func test_ac18_fish_added_creates_exactly_one_node_at_the_expected_pose() -> void:
	var rig: FishRig.Rig = _ready_rig(FishRig.model())
	if rig == null:
		return
	assert_int(rig.view.get_child_count()).is_equal(0)
	rig.model.apply_insert_fish(FishRig.fish("f1000003", Api.ANGEL, 2), 0)
	var node: Node3D = FishRig.node_of(rig, "f1000003")
	assert_object(node).override_failure_message("fish_added drew nothing").is_not_null()
	assert_int(rig.view.get_child_count()).is_equal(1)
	assert_bool(FishRig.at_pose(node, FishRig.expected_pose(rig, "f1000003"))).is_true()
	if node != null:
		(
			assert_bool(
				(
					_variant_colour(Api.ANGEL, 2).to_rgba32()
					== (_params(node)[0]["colour"] as Color).to_rgba32()
				)
			)
			. is_true()
		)


func test_ac18_fish_removed_and_its_undo_free_and_recreate_the_node_without_leftovers() -> void:
	var rig: FishRig.Rig = _ready_rig(FishRig.trio())
	if rig == null:
		return
	var node: Node3D = FishRig.node_of(rig, "f1000003")
	assert_object(node).is_not_null()
	var entry: FishInstance = rig.model.get_fish("f1000003")
	rig.model.apply_remove_fish("f1000003")
	await _frame()
	(
		assert_bool(is_instance_valid(node) and node.is_inside_tree())
		. override_failure_message("the node of a removed fish is still in the tree")
		. is_false()
	)
	assert_object(FishRig.node_of(rig, "f1000003")).is_null()
	assert_int(rig.view.get_child_count()).is_equal(2)
	rig.model.apply_insert_fish(entry, 1)
	assert_int(rig.view.get_child_count()).is_equal(2 + 1)
	var back: Node3D = FishRig.node_of(rig, "f1000003")
	assert_bool(FishRig.at_pose(back, FishRig.expected_pose(rig, "f1000003"))).is_true()


func test_ac18_model_reset_rebuilds_every_node_in_one_pass() -> void:
	var rig: FishRig.Rig = _ready_rig(FishRig.trio())
	if rig == null:
		return
	var other: AquariumModel = _decoded(GOOD_FIXTURE)
	rig.model.reset_from(other)
	await _frame()
	assert_int(rig.view.get_child_count()).is_equal(7)
	for entry: FishInstance in rig.model.get_fish_list():
		var node: Node3D = FishRig.node_of(rig, entry.uid)
		(
			assert_bool(FishRig.at_pose(node, FishRig.expected_pose(rig, entry.uid)))
			. override_failure_message("%s is not at its pose after the reset" % entry.uid)
			. is_true()
		)


# --- AC 19: bad data ---


func test_ac19_a_bad_variant_shows_variant_0_and_an_unknown_species_shows_nothing() -> void:
	var source: AquariumModel = _decoded(BAD_FIXTURE)
	var holder: Array = []
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void: holder.append(_ready_rig(source))
	)
	var rig: FishRig.Rig = holder[0]
	if rig == null:
		return
	(
		assert_object(FishRig.node_of(rig, "b1000002"))
		. override_failure_message("an unknown species must show no fish")
		. is_null()
	)
	var fallback: Node3D = FishRig.node_of(rig, "b1000003")
	(
		assert_object(fallback)
		. override_failure_message("variant 7 must still show a fish")
		. is_not_null()
	)
	if fallback != null:
		var params: Dictionary = _params(fallback)[0]
		assert_float(float(params["strength"])).is_equal(0.0)
		(
			assert_bool(
				(params["colour"] as Color).to_rgba32() == _variant_colour(Api.NEON, 0).to_rgba32()
			)
			. is_true()
		)
	assert_object(FishRig.node_of(rig, "b1000001")).is_not_null()
	var by_uid: Dictionary = {}
	for text: String in seen["warnings"]:
		if text.begins_with("FishView:"):
			for uid: String in ["b1000002", "b1000003"]:
				if text.contains(uid):
					by_uid[uid] = int(by_uid.get(uid, 0)) + int(seen["warnings"][text])
	(
		assert_dict(by_uid)
		. override_failure_message(
			"expected exactly one FishView: warning per bad entry, got %s" % [seen["warnings"]]
		)
		. is_equal({"b1000002": 1, "b1000003": 1})
	)
	assert_int(seen["warnings"].size()).is_equal(2)
	assert_dict(seen["errors"]).is_empty()


func test_ac19_the_model_the_count_and_the_saved_file_are_unchanged_by_bad_entries() -> void:
	var source: AquariumModel = _decoded(BAD_FIXTURE)
	var holder: Array = []
	await EngineOutput.capture(func() -> void: holder.append(_ready_rig(source)))
	var rig: FishRig.Rig = holder[0]
	if rig == null:
		return
	assert_int(rig.model.get_fish_count()).is_equal(3)
	var result: SaveResult = SaveCodec.new().encode(rig.model, FishRig.STAMP)
	assert_bool(result.is_ok()).is_true()
	assert_str(result.text).contains("b1000002").contains("no_such_fish").contains('"variant": 7')


func test_ac19_get_skipped_lists_the_unknown_species_as_a_copy_with_a_reason() -> void:
	var source: AquariumModel = _decoded(BAD_FIXTURE)
	var holder: Array = []
	await EngineOutput.capture(func() -> void: holder.append(_ready_rig(source)))
	var rig: FishRig.Rig = holder[0]
	if rig == null:
		return
	var skipped: Dictionary = rig.view.call("get_skipped")
	assert_bool(skipped.has("b1000002")).is_true()
	assert_str(str(skipped.get("b1000002", ""))).is_not_empty()
	assert_bool(skipped.has("b1000001")).is_false()
	skipped.clear()
	(
		assert_bool((rig.view.call("get_skipped") as Dictionary).has("b1000002"))
		. override_failure_message("get_skipped must return a copy")
		. is_true()
	)


func test_ac19_the_warning_comes_once_per_build_and_never_per_frame() -> void:
	var source: AquariumModel = _decoded(BAD_FIXTURE)
	var holder: Array = []
	await EngineOutput.capture(func() -> void: holder.append(_ready_rig(source)))
	var rig: FishRig.Rig = holder[0]
	if rig == null:
		return
	var later: Dictionary = await EngineOutput.capture(
		func() -> void:
			await get_tree().process_frame
			await get_tree().process_frame
			await get_tree().process_frame
	)
	(
		assert_dict(later["warnings"])
		. override_failure_message("a warning repeats per frame")
		. is_empty()
	)
	assert_dict(later["errors"]).is_empty()
	var rebuilt: Dictionary = await EngineOutput.capture(
		func() -> void: rig.model.reset_from(_decoded(BAD_FIXTURE))
	)
	var count: int = 0
	for text: String in rebuilt["warnings"]:
		if text.begins_with("FishView:"):
			count += int(rebuilt["warnings"][text])
	assert_int(count).override_failure_message("a rebuild must warn once per bad entry").is_equal(2)


func test_ac19_a_later_fish_changed_does_not_warn_again_for_a_bad_entry() -> void:
	var source: AquariumModel = _decoded(BAD_FIXTURE)
	var holder: Array = []
	await EngineOutput.capture(func() -> void: holder.append(_ready_rig(source)))
	var rig: FishRig.Rig = holder[0]
	if rig == null:
		return
	var later: Dictionary = await EngineOutput.capture(
		func() -> void:
			for uid: String in ["b1000002", "b1000003"]:
				var changed: FishInstance = rig.model.get_fish(uid).copy()
				changed.nickname = "Renamed"
				rig.model.apply_replace_fish(changed)
			var other: FishInstance = rig.model.get_fish("b1000001").copy()
			other.nickname = "Fine"
			rig.model.apply_replace_fish(other)
	)
	(
		assert_dict(later["warnings"])
		. override_failure_message("a nickname-only change warned again: %s" % [later["warnings"]])
		. is_empty()
	)
	assert_dict(later["errors"]).is_empty()


func test_ac19_an_unknown_tank_hides_the_fish_without_a_warning() -> void:
	var source: AquariumModel = FishRig.trio()
	source.apply_set_tank_id(&"no_such_tank")
	var holder: Array = []
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void: holder.append(_ready_rig(source))
	)
	var rig: FishRig.Rig = holder[0]
	if rig == null:
		return
	assert_dict(seen["warnings"]).is_empty()
	assert_dict(seen["errors"]).is_empty()
	assert_bool(rig.view.visible).is_false()


# --- AC 16: synchronous repositioning ---


func test_ac16_a_corydoras_follows_a_substrate_change_its_undo_and_its_redo_at_once() -> void:
	var rig: FishRig.Rig = _ready_rig(
		FishRig.model(FishRig.MEDIUM, FishRig.SAND, [FishRig.fish("f1000006", Api.CORY)])
	)
	if rig == null:
		return
	var node: Node3D = FishRig.node_of(rig, "f1000006")
	assert_object(node).is_not_null()
	if node == null:
		return
	var sand_pose: Dictionary = FishRig.expected_pose(rig, "f1000006")
	assert_bool(FishRig.at_pose(node, sand_pose)).is_true()
	var colour: Color = rig.substrates.get_definition(FishRig.PEBBLES).default_colour
	var command: SetSubstrateCommand = SetSubstrateCommand.new(
		rig.model, rig.substrates, FishRig.PEBBLES, colour
	)
	assert_bool(command.do()).is_true()
	var pebble_pose: Dictionary = FishRig.expected_pose(rig, "f1000006")
	(
		assert_bool(FishRig.at_pose(node, pebble_pose))
		. override_failure_message("after do() the fish is not at the pebbles pose")
		. is_true()
	)
	var bed_top: float = 0.06 + Api.top_allowance(rig.substrates.get_definition(FishRig.PEBBLES))
	assert_float(node.position.y).override_failure_message("the fish is inside the bed").is_greater(
		bed_top
	)
	assert_float(node.position.y).is_greater(sand_pose["position"].y + 0.02)
	assert_bool(command.undo()).is_true()
	(
		assert_bool(FishRig.at_pose(node, sand_pose))
		. override_failure_message("after undo() the fish is not back at the sand pose")
		. is_true()
	)
	assert_bool(command.do()).is_true()
	(
		assert_bool(FishRig.at_pose(node, pebble_pose))
		. override_failure_message("after redo the fish is not at the pebbles pose")
		. is_true()
	)


func test_ac16_heightmap_changed_moves_every_fish_to_the_rule_before_the_call_returns() -> void:
	var rig: FishRig.Rig = _ready_rig(FishRig.trio())
	if rig == null:
		return
	var node: Node3D = FishRig.node_of(rig, "f1000006")
	if node == null:
		assert_bool(false).override_failure_message("no node").is_true()
		return
	node.position = Vector3(9.0, 9.0, 9.0)
	rig.model.apply_set_heightmap(PackedFloat32Array([0.03, 0.03, 0.03, 0.03]), Vector2i(2, 2))
	(
		assert_bool(FishRig.at_pose(node, FishRig.expected_pose(rig, "f1000006")))
		. override_failure_message("heightmap_changed did not reposition the fish")
		. is_true()
	)


func test_ac16_model_reset_moves_every_fish_to_the_rule() -> void:
	var rig: FishRig.Rig = _ready_rig(FishRig.trio())
	if rig == null:
		return
	rig.model.reset_from(FishRig.trio(FishRig.LARGE, FishRig.PEBBLES))
	await _frame()
	for uid: String in ["f1000001", "f1000003", "f1000006"]:
		(
			assert_bool(FishRig.at_pose(FishRig.node_of(rig, uid), FishRig.expected_pose(rig, uid)))
			. override_failure_message("%s is not at its pose after model_reset" % uid)
			. is_true()
		)


# --- AC 26: the pose with the real extents ---


func test_ac26_every_species_stands_at_its_derived_pose_inside_the_tank_in_every_tank() -> void:
	for tank: StringName in [FishRig.SMALL, FishRig.MEDIUM, FishRig.LARGE]:
		var rig: FishRig.Rig = _ready_rig(FishRig.trio(tank, FishRig.SAND))
		if rig == null:
			return
		var definition: TankDefinition = rig.tanks.get_definition(tank)
		var half: Vector3 = definition.interior_size_m / 2.0
		for uid: String in ["f1000001", "f1000003", "f1000006"]:
			var node: Node3D = FishRig.node_of(rig, uid)
			var pose: Dictionary = FishRig.expected_pose(rig, uid)
			(
				assert_bool(FishRig.at_pose(node, pose))
				. override_failure_message("%s in %s is not at the derived pose" % [uid, tank])
				. is_true()
			)
			if node == null:
				continue
			var box: AABB = Glb.scene_bounds_in(node.get_child(0) as Node3D, rig.view)
			var world: AABB = box
			(
				assert_bool(
					(
						world.position.x >= -half.x + 0.01 - POSE_EPS
						and world.end.x <= half.x - 0.01 + POSE_EPS
					)
				)
				. override_failure_message(
					"%s in %s: x reaches the glass, box %s" % [uid, tank, world]
				)
				. is_true()
			)
			(
				assert_bool(
					(
						world.position.z >= -half.z + 0.01 - POSE_EPS
						and world.end.z <= half.z - 0.01 + POSE_EPS
					)
				)
				. override_failure_message(
					"%s in %s: z reaches the glass, box %s" % [uid, tank, world]
				)
				. is_true()
			)
			(
				assert_bool(
					(
						world.position.y >= 0.03 - POSE_EPS
						and world.end.y <= definition.water_line_height_m + POSE_EPS
					)
				)
				. override_failure_message(
					"%s in %s: not inside the water column, box %s" % [uid, tank, world]
				)
				. is_true()
			)


# --- AC 27: tank change ---


func test_ac27_a_tank_change_that_leaves_the_fish_in_the_model_moves_every_fish_inside() -> void:
	var rig: FishRig.Rig = _ready_rig(FishRig.trio(FishRig.LARGE, FishRig.SAND))
	if rig == null:
		return
	var large_poses: Dictionary = {}
	for uid: String in ["f1000001", "f1000003", "f1000006"]:
		large_poses[uid] = FishRig.expected_pose(rig, uid)
	rig.model.apply_set_tank_id(FishRig.SMALL)
	var definition: TankDefinition = rig.tanks.get_definition(FishRig.SMALL)
	for uid: String in ["f1000001", "f1000003", "f1000006"]:
		var node: Node3D = FishRig.node_of(rig, uid)
		(
			assert_bool(FishRig.at_pose(node, FishRig.expected_pose(rig, uid)))
			. override_failure_message("%s was left at the old coordinates" % uid)
			. is_true()
		)
		if node == null:
			continue
		assert_bool(absf(node.position.x) < definition.interior_size_m.x / 2.0).is_true()
		assert_bool(absf(node.position.z) < definition.interior_size_m.z / 2.0).is_true()
		assert_bool(node.position.y < definition.water_line_height_m).is_true()
	assert_int(rig.model.get_fish_count()).is_equal(3)
	rig.model.apply_set_tank_id(FishRig.LARGE)
	for uid: String in ["f1000001", "f1000003", "f1000006"]:
		(
			assert_bool(FishRig.at_pose(FishRig.node_of(rig, uid), large_poses[uid]))
			. override_failure_message("%s did not return exactly to its large-tank pose" % uid)
			. is_true()
		)


func test_ac27_change_tank_command_do_undo_redo_keeps_nodes_and_model_in_step() -> void:
	var rig: FishRig.Rig = _ready_rig(FishRig.trio(FishRig.LARGE, FishRig.SAND))
	if rig == null:
		return
	var large_poses: Dictionary = {}
	for uid: String in ["f1000001", "f1000003", "f1000006"]:
		large_poses[uid] = FishRig.expected_pose(rig, uid)
	var command: ChangeTankCommand = ChangeTankCommand.new(rig.model, rig.tanks, FishRig.SMALL)
	assert_bool(command.do()).is_true()
	await _frame()
	# The command clears the fish of the model (#24), so the nodes follow the model.
	assert_int(rig.model.get_fish_count()).is_equal(0)
	(
		assert_int(rig.view.get_child_count())
		. override_failure_message("nodes are left behind after the tank change")
		. is_equal(0)
	)
	assert_bool(command.undo()).is_true()
	assert_int(rig.view.get_child_count()).is_equal(3)
	for uid: String in ["f1000001", "f1000003", "f1000006"]:
		(
			assert_bool(FishRig.at_pose(FishRig.node_of(rig, uid), large_poses[uid]))
			. override_failure_message("%s is not at its earlier pose after undo" % uid)
			. is_true()
		)
	assert_bool(command.do()).is_true()
	await _frame()
	assert_int(rig.view.get_child_count()).is_equal(0)
	assert_str(String(rig.model.get_tank_id())).is_equal(String(FishRig.SMALL))


# --- AC 28: fish height and the water column ---


func test_ac28_the_angelfish_in_the_small_tank_with_pebbles_has_its_fins_in_the_water() -> void:
	var rig: FishRig.Rig = _ready_rig(
		FishRig.model(FishRig.SMALL, FishRig.PEBBLES, [FishRig.fish("f1000003", Api.ANGEL)])
	)
	if rig == null:
		return
	var node: Node3D = FishRig.node_of(rig, "f1000003")
	assert_object(node).is_not_null()
	if node == null:
		return
	var box: AABB = Glb.scene_bounds_in(node.get_child(0) as Node3D, rig.view)
	(
		assert_float(box.position.y)
		. override_failure_message("the fins reach below the substrate surface (box %s)" % box)
		. is_greater_equal(0.06 - POSE_EPS)
	)
	(
		assert_float(box.end.y)
		. override_failure_message("the fins reach above the water line (box %s)" % box)
		. is_less_equal(0.25 + POSE_EPS)
	)


func test_ac28_edge_a_fish_taller_than_the_column_is_pinned_to_the_middle_with_one_warning(
) -> void:
	var giant: Resource = Api.variant_of(
		Api.ANGEL, {"id": &"giant_angelfish", "adult_length_cm": 200.0}
	)
	if giant == null:
		assert_bool(false).override_failure_message("FishSpecies is missing").is_true()
		return
	var catalog: RefCounted = Api.catalog_from([giant])
	var source: AquariumModel = FishRig.model(
		FishRig.SMALL, FishRig.SAND, [FishRig.fish("c1000001", &"giant_angelfish")]
	)
	var holder: Array = []
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void: holder.append(_ready_rig(source, catalog))
	)
	var rig: FishRig.Rig = holder[0]
	if rig == null:
		return
	var count: int = 0
	for text: String in seen["warnings"]:
		if text.begins_with("FishView:") and text.contains("c1000001"):
			count += int(seen["warnings"][text])
	(
		assert_int(count)
		. override_failure_message(
			"expected exactly one pinned warning, got %s" % [seen["warnings"]]
		)
		. is_equal(1)
	)
	var node: Node3D = FishRig.node_of(rig, "c1000001")
	assert_object(node).is_not_null()
	if node != null:
		var row: Array = FishRig.unscaled_extents(Api.ANGEL)
		var low: float = 0.03 + row[1] * 2.0
		var high: float = 0.25 - row[2] * 2.0
		assert_float(node.position.y).is_equal_approx((low + high) / 2.0, 1e-4)


func test_ac28_none_of_the_three_real_species_triggers_a_warning_in_any_tank_and_substrate(
) -> void:
	for tank: StringName in [FishRig.SMALL, FishRig.MEDIUM, FishRig.LARGE]:
		for substrate: StringName in [FishRig.SAND, FishRig.PEBBLES]:
			var source: AquariumModel = FishRig.trio(tank, substrate)
			var holder: Array = []
			var seen: Dictionary = await EngineOutput.capture(
				func() -> void: holder.append(_ready_rig(source))
			)
			(
				assert_dict(seen["warnings"])
				. override_failure_message(
					"%s with %s warns: %s" % [tank, substrate, seen["warnings"]]
				)
				. is_empty()
			)
			if holder[0] != null:
				(holder[0] as FishRig.Rig).host.queue_free()


# --- AC 29: variant change in place ---


func test_ac29_a_variant_change_updates_the_parameters_on_the_same_node() -> void:
	var rig: FishRig.Rig = _ready_rig(FishRig.trio())
	if rig == null:
		return
	var node: Node3D = FishRig.node_of(rig, "f1000003")
	assert_object(node).is_not_null()
	if node == null:
		return
	var id_before: int = node.get_instance_id()
	var child_before: int = node.get_child(0).get_instance_id()
	var position_before: Vector3 = node.position
	var basis_before: Basis = node.basis
	var phase_before: float = float(_params(node)[0]["phase"])
	var changed: FishInstance = rig.model.get_fish("f1000003").copy()
	changed.variant = 2
	rig.model.apply_replace_fish(changed)
	var node_after: Node3D = FishRig.node_of(rig, "f1000003")
	(
		assert_int(node_after.get_instance_id())
		. override_failure_message("the node was recreated")
		. is_equal(id_before)
	)
	assert_int(node.get_child(0).get_instance_id()).is_equal(child_before)
	assert_vector(node.position).is_equal(position_before)
	assert_bool(node.basis.is_equal_approx(basis_before)).is_true()
	for params: Dictionary in _params(node):
		assert_float(float(params["strength"])).is_equal(1.0)
		(
			assert_bool(
				(params["colour"] as Color).to_rgba32() == _variant_colour(Api.ANGEL, 2).to_rgba32()
			)
			. is_true()
		)
		assert_float(float(params["phase"])).is_equal_approx(phase_before, 1e-6)
	var back: FishInstance = changed.copy()
	back.variant = 0
	rig.model.apply_replace_fish(back)
	for params: Dictionary in _params(node):
		assert_float(float(params["strength"])).is_equal(0.0)


func test_ac29_a_nickname_change_leaves_the_node_untouched() -> void:
	var rig: FishRig.Rig = _ready_rig(FishRig.trio())
	if rig == null:
		return
	var node: Node3D = FishRig.node_of(rig, "f1000001")
	assert_object(node).is_not_null()
	if node == null:
		return
	var id_before: int = node.get_instance_id()
	var child_before: int = node.get_child(0).get_instance_id()
	var params_before: Array[Dictionary] = _params(node)
	var position_before: Vector3 = node.position
	var changed: FishInstance = rig.model.get_fish("f1000001").copy()
	changed.nickname = "Sparky"
	rig.model.apply_replace_fish(changed)
	assert_int(FishRig.node_of(rig, "f1000001").get_instance_id()).is_equal(id_before)
	assert_int(node.get_child(0).get_instance_id()).is_equal(child_before)
	assert_vector(node.position).is_equal(position_before)
	assert_array(_params(node)).is_equal(params_before)
	assert_int(rig.view.get_child_count()).is_equal(3)


func test_ac29_a_species_change_recreates_the_node_with_the_new_species_scene() -> void:
	var rig: FishRig.Rig = _ready_rig(FishRig.trio())
	if rig == null:
		return
	var node: Node3D = FishRig.node_of(rig, "f1000001")
	var id_before: int = node.get_instance_id() if node != null else 0
	var changed: FishInstance = rig.model.get_fish("f1000001").copy()
	changed.species_id = Api.CORY
	rig.model.apply_replace_fish(changed)
	await _frame()
	var node_after: Node3D = FishRig.node_of(rig, "f1000001")
	assert_object(node_after).is_not_null()
	if after != null:
		assert_int(node_after.get_instance_id()).is_not_equal(id_before)
		var scene: PackedScene = Api.field(Api.CORY, "scene", null) as PackedScene
		assert_str(node_after.get_child(0).scene_file_path).is_equal(scene.resource_path)
	assert_int(rig.view.get_child_count()).is_equal(3)
