extends GdUnitTestSuite
## #35 FishView as the per-frame driver (owner: developer; BA decisions Q14, Q15, Q16 and Q18, ADR
## 0013 Amendment 1, ADR 0015 rule 8): pose transforms and the shader speed update every frame while
## fish swim and are not paused (advance(delta) is what _process calls; the rig sets manual_stepping
## so tests step by hand); each pose node keeps exactly one child (the species scene); swim_speed is
## the real speed over the species top speed, clamped to 1, and 0 at rest; the tail phase is
## continuous (a frame never advances it by more than TAU * swim_frequency * delta); paused freezes
## the transforms and the tail pose and resumes without a jump; the three EventBus relay signals
## reach the simulation; adding or removing a fish (also by undo and redo) moves no other fish by
## more than top speed times one step; fish are upright, never rolled and head-first; model_reset
## and a load restart every fish at its resting pose with fresh state; position and personality are
## never saved. Test decisions: positions are the only window on the steering from here (the view
## has no state getter), so the speed is estimated from the displacement of the node per step; the
## shader speed must be within 0.08 of that estimate (the speed changes by at most 0.042 of top
## speed per step); FishView warnings stay once per build while stepping.

const Api := preload("res://tests/helpers/fish_api.gd")
const Swim := preload("res://tests/helpers/fish_swim_api.gd")
const FishRig := preload("res://tests/helpers/fish_view_rig.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")
const SaveFixtures := preload("res://tests/helpers/save_fixtures.gd")

const STEP := 1.0 / 60.0
const TRIO: Array[String] = ["f1000001", "f1000003", "f1000006"]
const SPEED_TOLERANCE := 0.08


func after_test() -> void:
	if EventBus.has_signal("fish_pause_requested"):
		EventBus.emit_signal("fish_pause_requested", false)


func _rig(source: AquariumModel = null, catalog: RefCounted = null) -> FishRig.Rig:
	var rig: FishRig.Rig = FishRig.open(self, source if source != null else FishRig.trio(), catalog)
	assert_object(rig.view).override_failure_message("FishView is missing").is_not_null()
	if rig.view == null or not rig.view.has_method("advance"):
		assert_bool(false).override_failure_message("FishView has no advance(delta)").is_true()
		return null
	return rig


func _top(id: StringName) -> float:
	var length: float = float(Api.field(id, "adult_length_cm", 0.0)) / 100.0
	return float(Api.field(id, "swim_speed", 0.0)) * Swim.TOP_SPEED_K * length


func _param(node: Node3D, parameter: String) -> float:
	var instances: Array[GeometryInstance3D] = FishRig.geometry(node)
	if instances.is_empty():
		return Api.MISSING_NUMBER
	return float(instances[0].get_instance_shader_parameter(parameter))


func _positions(rig: FishRig.Rig) -> Dictionary:
	var result: Dictionary = {}
	for entry: FishInstance in rig.model.get_fish_list():
		var node: Node3D = FishRig.node_of(rig, entry.uid)
		if node != null:
			result[entry.uid] = node.position
	return result


func test_35_advance_moves_the_pose_nodes_and_each_keeps_exactly_one_child() -> void:
	var rig: FishRig.Rig = _rig()
	if rig == null:
		return
	var prior: Dictionary = _positions(rig)
	var children: Dictionary = {}
	for uid: String in TRIO:
		children[uid] = FishRig.node_of(rig, uid).get_child(0).get_instance_id()
	FishRig.advance(rig, 20.0)
	for uid: String in TRIO:
		var node: Node3D = FishRig.node_of(rig, uid)
		(
			assert_float(node.position.distance_to(prior[uid]))
			. override_failure_message("%s did not move in 20 s" % uid)
			. is_greater(0.01)
		)
		assert_int(node.get_child_count()).is_equal(1)
		assert_int(node.get_child(0).get_instance_id()).is_equal(children[uid])
	assert_int(rig.view.get_child_count()).is_equal(3)


func test_35_poses_moved_is_emitted_once_per_advance_and_not_by_model_signals() -> void:
	var rig: FishRig.Rig = _rig()
	if rig == null:
		return
	(
		assert_bool(rig.view.has_signal("poses_moved"))
		. override_failure_message("FishView has no poses_moved signal")
		. is_true()
	)
	if not rig.view.has_signal("poses_moved"):
		return
	var counter: Array[int] = [0]
	rig.view.connect("poses_moved", func() -> void: counter[0] += 1)
	FishRig.advance(rig, 1.0)
	assert_int(counter[0]).is_equal(60)
	counter[0] = 0
	rig.model.apply_insert_fish(FishRig.fish("f1000010", Api.NEON), 3)
	rig.model.apply_set_tank_id(FishRig.LARGE)
	assert_int(counter[0]).override_failure_message("a model signal emitted poses_moved").is_equal(
		0
	)


func test_35_the_swim_speed_follows_the_real_speed_and_is_clamped_to_one() -> void:
	var rig: FishRig.Rig = _rig()
	if rig == null:
		return
	var previous: Dictionary = _positions(rig)
	var highest: Dictionary = {}
	var checked: int = 0
	for _index: int in 120 * 60:
		rig.view.call("advance", STEP)
		for uid: String in TRIO:
			var node: Node3D = FishRig.node_of(rig, uid)
			var species: StringName = rig.model.get_fish(uid).species_id
			var estimate: float = node.position.distance_to(previous[uid]) / STEP / _top(species)
			var shown: float = _param(node, "swim_speed")
			(
				assert_bool(shown >= 0.0 and shown <= 1.0)
				. override_failure_message("swim_speed %.3f is outside 0 to 1" % shown)
				. is_true()
			)
			if absf(shown - minf(estimate, 1.0)) > SPEED_TOLERANCE:
				(
					assert_float(shown)
					. override_failure_message(
						"%s swim_speed %.3f against the real %.3f" % [uid, shown, estimate]
					)
					. is_equal_approx(minf(estimate, 1.0), SPEED_TOLERANCE)
				)
				return
			previous[uid] = node.position
			highest[uid] = maxf(highest.get(uid, 0.0), shown)
			checked += 1
	assert_int(checked).is_equal(3 * 120 * 60)
	for uid: String in TRIO:
		assert_float(highest[uid]).override_failure_message("%s never swims fast" % uid).is_greater(
			0.5
		)


func test_35_the_tail_phase_is_continuous_for_every_species() -> void:
	var rig: FishRig.Rig = _rig()
	if rig == null:
		return
	var last: Dictionary = {}
	for uid: String in TRIO:
		last[uid] = _param(FishRig.node_of(rig, uid), "swim_phase")
		assert_float(last[uid]).is_equal_approx(
			TAU * Api.expected_unit(uid, "fish.swim.phase"), 1e-5
		)
	for _index: int in 30 * 60:
		rig.view.call("advance", STEP)
		for uid: String in TRIO:
			var species: StringName = rig.model.get_fish(uid).species_id
			var material: ShaderMaterial = (
				load("res://assets/fish/materials/%s.tres" % species) as ShaderMaterial
			)
			var beat: float = TAU * float(material.get_shader_parameter("swim_frequency")) * STEP
			var phase: float = _param(FishRig.node_of(rig, uid), "swim_phase")
			var advanced: float = fposmod(phase - last[uid], TAU)
			if advanced > beat + 1e-5 or advanced < beat * 0.4 - 1e-5:
				(
					assert_float(advanced)
					. override_failure_message(
						"%s tail phase advanced %.4f, the beat is %.4f" % [uid, advanced, beat]
					)
					. is_between(beat * 0.4 - 1e-5, beat + 1e-5)
				)
				return
			last[uid] = phase


func test_35_a_hitch_advances_the_phase_by_at_most_the_beat_of_half_a_second() -> void:
	var rig: FishRig.Rig = _rig()
	if rig == null:
		return
	var uid: String = "f1000001"
	var node: Node3D = FishRig.node_of(rig, uid)
	var prior: float = _param(node, "swim_phase")
	var position: Vector3 = node.position
	rig.view.call("advance", 0.5)
	var material: ShaderMaterial = (
		load("res://assets/fish/materials/neon_tetra.tres") as ShaderMaterial
	)
	var beat: float = TAU * float(material.get_shader_parameter("swim_frequency")) * 0.5
	var moved: float = fposmod(_param(node, "swim_phase") - prior, TAU)
	assert_bool(moved <= beat + 1e-5 or beat >= TAU).is_true()
	assert_float(node.position.distance_to(position)).is_less_equal(
		_top(Api.NEON) * 1.2 * 0.5 + 1e-6
	)


# --- pause and the EventBus relay ---


func test_35_the_three_relay_signals_exist_on_the_event_bus() -> void:
	assert_bool(EventBus.has_signal("fish_pause_requested")).is_true()
	assert_bool(EventBus.has_signal("fish_override_requested")).is_true()
	assert_bool(EventBus.has_signal("fish_override_cleared")).is_true()
	var by_name: Dictionary = {}
	for info: Dictionary in EventBus.get_signal_list():
		by_name[info["name"]] = (info["args"] as Array).size()
	assert_int(by_name.get("fish_pause_requested", -1)).is_equal(1)
	assert_int(by_name.get("fish_override_requested", -1)).is_equal(2)
	assert_int(by_name.get("fish_override_cleared", -1)).is_equal(1)


func test_35_paused_freezes_the_transforms_and_the_tail_pose_and_emits_nothing() -> void:
	var rig: FishRig.Rig = _rig()
	if rig == null:
		return
	FishRig.advance(rig, 10.0)
	var counter: Array[int] = [0]
	if rig.view.has_signal("poses_moved"):
		rig.view.connect("poses_moved", func() -> void: counter[0] += 1)
	EventBus.emit_signal("fish_pause_requested", true)
	var frozen: Dictionary = {}
	for uid: String in TRIO:
		var node: Node3D = FishRig.node_of(rig, uid)
		frozen[uid] = [
			node.position, node.basis, _param(node, "swim_phase"), _param(node, "swim_speed")
		]
	FishRig.advance(rig, 5.0)
	for uid: String in TRIO:
		var node: Node3D = FishRig.node_of(rig, uid)
		var was: Array = frozen[uid]
		(
			assert_vector(node.position)
			. override_failure_message("%s moved while paused" % uid)
			. is_equal(was[0])
		)
		assert_bool(node.basis.is_equal_approx(was[1])).is_true()
		(
			assert_float(_param(node, "swim_phase"))
			. override_failure_message("the tail moves")
			. is_equal(was[2])
		)
		assert_float(_param(node, "swim_speed")).is_equal(was[3])
	assert_int(counter[0]).override_failure_message("poses_moved while paused").is_equal(0)


func test_35_resuming_continues_without_a_jump_in_the_pose_or_the_tail() -> void:
	var rig: FishRig.Rig = _rig()
	if rig == null:
		return
	FishRig.advance(rig, 10.0)
	EventBus.emit_signal("fish_pause_requested", true)
	FishRig.advance(rig, 30.0)
	EventBus.emit_signal("fish_pause_requested", false)
	for uid: String in TRIO:
		var node: Node3D = FishRig.node_of(rig, uid)
		var species: StringName = rig.model.get_fish(uid).species_id
		var position: Vector3 = node.position
		var phase: float = _param(node, "swim_phase")
		rig.view.call("advance", STEP)
		(
			assert_float(node.position.distance_to(position))
			. override_failure_message("%s jumped on resume" % uid)
			. is_less_equal(_top(species) * 1.2 * STEP + 1e-7)
		)
		var material: ShaderMaterial = (
			load("res://assets/fish/materials/%s.tres" % species) as ShaderMaterial
		)
		var beat: float = TAU * float(material.get_shader_parameter("swim_frequency")) * STEP
		assert_float(fposmod(_param(node, "swim_phase") - phase, TAU)).is_less_equal(beat + 1e-5)


func test_35_an_override_through_the_event_bus_moves_the_fish_and_clearing_it_releases_it() -> void:
	var rig: FishRig.Rig = _rig(
		FishRig.model(FishRig.LARGE, FishRig.SAND, [FishRig.fish("f1000001", Api.NEON)])
	)
	if rig == null:
		return
	var target: Vector3 = Vector3(0.3, 0.22, 0.05)
	EventBus.emit_signal("fish_override_requested", "f1000001", target)
	FishRig.advance(rig, 60.0)
	var node: Node3D = FishRig.node_of(rig, "f1000001")
	(
		assert_float(node.position.distance_to(target))
		. override_failure_message("the fish did not go to the override target")
		. is_less(0.05)
	)
	EventBus.emit_signal("fish_override_cleared", "f1000001")
	FishRig.advance(rig, 60.0)
	(
		assert_float(node.position.distance_to(target))
		. override_failure_message("the fish stayed at the cleared target")
		. is_greater(0.05)
	)


func test_35_the_view_listens_to_the_relay_only_while_it_lives() -> void:
	if not EventBus.has_signal("fish_pause_requested"):
		(
			assert_bool(false)
			. override_failure_message("EventBus has no fish_pause_requested")
			. is_true()
		)
		return
	var prior: int = EventBus.get_signal_connection_list("fish_pause_requested").size()
	var rig: FishRig.Rig = _rig()
	if rig == null:
		return
	assert_int(EventBus.get_signal_connection_list("fish_pause_requested").size()).is_equal(
		prior + 1
	)
	rig.host.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(EventBus.get_signal_connection_list("fish_pause_requested").size()).is_equal(prior)
	EventBus.emit_signal("fish_pause_requested", true)
	EventBus.emit_signal("fish_pause_requested", false)


# --- add, remove, undo, redo ---


func test_35_adding_and_removing_a_fish_by_command_moves_no_other_fish_by_more_than_one_step(
) -> void:
	var rig: FishRig.Rig = _rig()
	if rig == null:
		return
	FishRig.advance(rig, 20.0)
	var added: FishInstance = FishRig.fish("f1000009", Api.NEON)
	var add: Command = AddFishCommand.new(rig.model, added)
	var remove: Command = RemoveFishCommand.new(rig.model, "f1000001")
	for action: Callable in [
		func() -> void: add.do(),
		func() -> void: add.undo(),
		func() -> void: add.do(),
		func() -> void: remove.do(),
		func() -> void: remove.undo(),
	]:
		var prior: Dictionary = _positions(rig)
		action.call()
		for uid: String in prior:
			var node: Node3D = FishRig.node_of(rig, uid)
			if node != null and uid != "f1000001":
				(
					assert_vector(node.position)
					. override_failure_message("%s moved by the model change itself" % uid)
					. is_equal(prior[uid])
				)
		rig.view.call("advance", STEP)
		for uid: String in prior:
			var node: Node3D = FishRig.node_of(rig, uid)
			if node == null:
				continue
			var species: StringName = rig.model.get_fish(uid).species_id
			(
				assert_float(node.position.distance_to(prior[uid]))
				. override_failure_message("%s jumped in the frame of an add or remove" % uid)
				. is_less_equal(_top(species) * 1.2 * STEP + 1e-7)
			)
	var back: Node3D = FishRig.node_of(rig, "f1000001")
	assert_object(back).is_not_null()


func test_35_a_new_fish_appears_at_its_resting_pose_while_the_others_swim_on() -> void:
	var rig: FishRig.Rig = _rig()
	if rig == null:
		return
	FishRig.advance(rig, 10.0)
	rig.model.apply_insert_fish(FishRig.fish("f1000011", Api.ANGEL), 3)
	var node: Node3D = FishRig.node_of(rig, "f1000011")
	assert_bool(FishRig.at_pose(node, FishRig.expected_pose(rig, "f1000011"))).is_true()


# --- upright, head-first, no roll ---


func test_35_fish_are_upright_never_rolled_and_swim_head_first() -> void:
	var rig: FishRig.Rig = _rig()
	if rig == null:
		return
	var previous: Dictionary = _positions(rig)
	var turned_back: int = 0
	var moving: int = 0
	for _index: int in 60 * 60:
		rig.view.call("advance", STEP)
		for uid: String in TRIO:
			var node: Node3D = FishRig.node_of(rig, uid)
			var species: StringName = rig.model.get_fish(uid).species_id
			var basis: Basis = node.basis
			(
				assert_float(absf(basis.x.y))
				. override_failure_message("%s is rolled: %.3f" % [uid, basis.x.y])
				. is_less_equal(sin(deg_to_rad(1.0)) + 1e-6)
			)
			assert_float(basis.y.y).override_failure_message("%s is not upright" % uid).is_greater(
				0.5
			)
			assert_bool(basis.is_equal_approx(basis.orthonormalized())).is_true()
			var step: Vector3 = node.position - previous[uid]
			if step.length() / STEP > 0.1 * _top(species):
				moving += 1
				var angle: float = rad_to_deg(basis.z.angle_to(step))
				if angle > 30.0:
					turned_back += 1
			previous[uid] = node.position
	assert_int(moving).is_greater(1000)
	assert_int(turned_back).override_failure_message("a fish swam tail-first or sideways").is_equal(
		0
	)


# --- load, reset, not saved ---


func test_35_model_reset_puts_every_fish_back_at_its_resting_pose_with_fresh_state() -> void:
	var rig: FishRig.Rig = _rig()
	if rig == null:
		return
	FishRig.advance(rig, 30.0)
	rig.model.reset_from(FishRig.trio())
	for uid: String in TRIO:
		var node: Node3D = FishRig.node_of(rig, uid)
		(
			assert_bool(FishRig.at_pose(node, FishRig.expected_pose(rig, uid)))
			. override_failure_message("%s is not at its resting pose after the reset" % uid)
			. is_true()
		)
		assert_float(_param(node, "swim_speed")).is_equal(0.0)
		assert_float(_param(node, "swim_phase")).is_equal_approx(
			TAU * Api.expected_unit(uid, "fish.swim.phase"), 1e-5
		)
	var after_reset: Dictionary = _positions(rig)
	rig.view.call("advance", STEP)
	for uid: String in TRIO:
		var species: StringName = rig.model.get_fish(uid).species_id
		(
			assert_float(FishRig.node_of(rig, uid).position.distance_to(after_reset[uid]))
			. is_less_equal(_top(species) * 0.1)
		)


func test_35_a_loaded_save_starts_every_fish_at_its_resting_pose_and_begins_to_swim() -> void:
	var text: String = FileAccess.get_file_as_string(
		"res://tests/fixtures/saves/fish_three_species_v1.json"
	)
	var result: SaveResult = SaveCodec.new().decode(text, FishRig.STAMP)
	assert_bool(result.is_ok()).is_true()
	var loaded: AquariumModel = SaveFixtures.model_of(result)
	var rig: FishRig.Rig = _rig(loaded)
	if rig == null:
		return
	var rest: Dictionary = {}
	for entry: FishInstance in rig.model.get_fish_list():
		rest[entry.uid] = FishRig.expected_pose(rig, entry.uid)
		assert_bool(FishRig.at_pose(FishRig.node_of(rig, entry.uid), rest[entry.uid])).is_true()
	FishRig.advance(rig, 10.0)
	var moved: int = 0
	for entry: FishInstance in rig.model.get_fish_list():
		if (
			FishRig.node_of(rig, entry.uid).position.distance_to(rest[entry.uid]["position"])
			> 0.005
		):
			moved += 1
	assert_int(moved).override_failure_message("the loaded fish did not begin to swim").is_greater(
		0
	)


func test_35_positions_and_personality_are_never_saved_after_10_seconds_of_swimming() -> void:
	var rig: FishRig.Rig = _rig()
	if rig == null:
		return
	var prior: SaveResult = SaveCodec.new().encode(rig.model, FishRig.STAMP)
	FishRig.advance(rig, 10.0)
	var later: SaveResult = SaveCodec.new().encode(rig.model, FishRig.STAMP)
	assert_bool(prior.is_ok() and later.is_ok()).is_true()
	assert_str(later.text).is_equal(prior.text)
	var parsed: Dictionary = JSON.parse_string(later.text)
	assert_int(int(parsed["format_version"])).is_equal(1)
	for entry: Dictionary in parsed["fish"]:
		assert_array(entry.keys()).is_equal(["uid", "species_id", "variant", "nickname"])


# --- real frames, manual stepping, warnings ---


func test_35_manual_stepping_stops_the_process_and_real_frames_move_the_tail_when_it_is_off(
) -> void:
	var manual: FishRig.Rig = _rig()
	var live: FishRig.Rig = FishRig.open(self, FishRig.trio(), null, false)
	if manual == null or live.view == null:
		return
	var rest: Dictionary = _positions(manual)
	var live_phase: float = _param(FishRig.node_of(live, "f1000001"), "swim_phase")
	for _index: int in 5:
		await get_tree().process_frame
	for uid: String in TRIO:
		(
			assert_vector(FishRig.node_of(manual, uid).position)
			. override_failure_message("a manually stepped view moved by itself")
			. is_equal(rest[uid])
		)
	(
		assert_float(_param(FishRig.node_of(live, "f1000001"), "swim_phase"))
		. override_failure_message("a live view did not advance the tail in real frames")
		. is_not_equal(live_phase)
	)


func test_35_a_pinned_warning_comes_once_per_build_and_never_while_stepping() -> void:
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
	await EngineOutput.capture(func() -> void: holder.append(_rig(source, catalog)))
	var rig: FishRig.Rig = holder[0]
	if rig == null:
		return
	var seen: Dictionary = await EngineOutput.capture(func() -> void: FishRig.advance(rig, 65.0))
	var count: int = 0
	for text: String in seen["warnings"]:
		if text.begins_with("FishView:") and text.contains("c1000001"):
			count += int(seen["warnings"][text])
	(
		assert_int(count)
		. override_failure_message("warnings while stepping: %s" % [seen["warnings"]])
		. is_equal(0)
	)
	assert_dict(seen["errors"]).is_empty()
