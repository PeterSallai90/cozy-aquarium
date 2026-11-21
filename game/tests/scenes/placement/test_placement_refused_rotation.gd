# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #33 AC 15 and 16 (owner: developer): a rotation of the selected item that the footprint rule
## would refuse (owner decision 1b with 2b, BA decisions on #33).
## Press: the first step is judged when the key goes down. Refused: no command, no history entry, no
## item_changed, the model and drawn angle stay, the selection stays and the refusal cue plays once;
## a tap released before the first repeat does nothing more (no command, no second cue).
## Hold (2b): the repeats are never checked; the drawn item shows the pending angle every tick even
## through a neighbour or the glass, and a hold never plays a cue per repeat. The release judges the
## final angle: valid (or equal to the start) is one command as in #31; invalid is no command, the
## drawn item snaps back to the model angle at once and the cue plays once more (a gesture has at
## most one cue at the press and one at the release). A cancelled hold, the ghost and an item that
## is not selected never cue. The cue is the selection glow rising and falling once over
## REFUSAL_CUE_DURATION_S and is cancelled by model_reset, a tank swap, removal, deselect and
## photo-mode blocking. An item that is already invalid turns freely, with no cue (AC 16).
## Fixtures (medium tank, 0.60 x 0.30 m, branch 28 x 7 cm, stone 11 x 8 cm):
## - refused: branch FIRST at (0, 0.0752), stone SECOND at (0, 0). The branch lies 0.2 mm off the
##   stone; 15 degrees (also 1 degree and -15) swings its end into the stone, 60 degrees goes
##   through the glass, 180 degrees is the same footprint and valid again.
## - hold: branch FIRST at (0, 0), stone SECOND at (0, 0.1). 15 degrees is valid, 30 and 45 are not,
##   180 is valid again.
## Test decisions: the cue state and strength are read from the drawn items (view) and cross-checked
## on the overlay material of the marked meshes; strengths are asserted at steps of 0.05 s after
## the cue started (the plan's table), the last step by value only (float rounding at the end).

const Rig := preload("res://tests/helpers/placement_rig.gd")
const Session := preload("res://tests/helpers/placement_session.gd")
const Api := preload("res://tests/helpers/placement_api.gd")
const Recorder := preload("res://tests/helpers/signal_recorder.gd")
const ModelState := preload("res://tests/helpers/model_state.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")

const FIRST := "a0000001"
const SECOND := "a0000002"
const SELECTION_MATERIAL := "res://scenes/tank/items/item_selection_material.tres"
const BASE: float = 0.7
const TOLERANCE: float = 0.0001
const ANGLE_TOLERANCE := 0.05
const TABLE: Array[float] = [0.7, 0.8, 0.873205, 0.9, 0.873205, 0.8]
## Addendum 2 table, steps 0 to 5 of 0.05 s: fresnel_power, glow_colour green and blue (red stays
## 1.0) and glow_lift green and blue (red stays 0.0).
const POWER: Array[float] = [1.6, 1.05, 0.647372, 0.5, 0.647372, 1.05]
const COLOUR_G: Array[float] = [0.86, 0.86, 0.86, 0.570086, 0.45, 0.570086]
const COLOUR_B: Array[float] = [0.62, 0.62, 0.62, 0.464437, 0.40, 0.464437]
const LIFT_G: Array[float] = [0.0, 0.212132, 0.3, 0.212132, 0.0, 0.0]
const LIFT_B: Array[float] = [0.0, 0.190919, 0.27, 0.190919, 0.0, 0.0]

var _s: Session = null
var _events: Recorder = null


func after_test() -> void:
	Rig.close(_s)


func _open(model: AquariumModel) -> bool:
	_s = await Rig.open(self, model)
	var complete: bool = _s.placement != null and _s.view != null and _s.ghost != null
	(
		assert_bool(complete)
		. override_failure_message(
			"RoomCorner needs a Placement child with the children PlacedItems and Ghost"
		)
		. is_true()
	)
	return complete


func _select(uid: String) -> bool:
	_s.click(_s.screen_of_item(uid))
	assert_str(_s.selected_uid()).is_equal(uid)
	_events = Recorder.new()
	_events.watch(_s.model)
	return _s.selected_uid() == uid


func _select_refused() -> bool:
	var model: AquariumModel = Rig.model()
	Rig.add_item(model, FIRST, Rig.BRANCH, 0.0, 0.0752, 0.0)
	Rig.add_item(model, SECOND, Rig.STONE, 0.0, 0.0, 0.0)
	if not await _open(model):
		return false
	return _select(FIRST)


func _select_hold() -> bool:
	var model: AquariumModel = Rig.model()
	Rig.add_item(model, FIRST, Rig.BRANCH, 0.0, 0.0, 0.0)
	Rig.add_item(model, SECOND, Rig.STONE, 0.0, 0.1, 0.0)
	if not await _open(model):
		return false
	return _select(FIRST)


func _time_for(ticks: int, fine: bool = false) -> float:
	var interval: float = Api.tuning("FINE_REPEAT_INTERVAL_S" if fine else "REPEAT_INTERVAL_S")
	return Api.tuning("REPEAT_DELAY_S") + (ticks - 1) * interval + interval * 0.5


func _gap(actual: float, expected: float) -> float:
	return absf(wrapf(actual - expected, -180.0, 180.0))


func _drawn_is(deg: float) -> void:
	(
		assert_float(_gap(_s.drawn_yaw(FIRST), deg))
		. override_failure_message("drawn angle %s, expected %s" % [_s.drawn_yaw(FIRST), deg])
		. is_less(ANGLE_TOLERANCE)
	)


func _changed_count() -> int:
	var count: int = 0
	for event_name: String in _events.names():
		if event_name == "item_changed":
			count += 1
	return count


## The meshes of the selected item that carry the mark.
func _marked_meshes() -> Array[GeometryInstance3D]:
	var meshes: Array[GeometryInstance3D] = []
	var node: Node3D = _s.node_for(FIRST)
	if node == null:
		return meshes
	for found: Node in node.find_children("*", "GeometryInstance3D", true, false):
		var mesh: GeometryInstance3D = found as GeometryInstance3D
		if mesh.material_overlay != null:
			meshes.append(mesh)
	return meshes


## The fresnel_strength on the marked meshes, read from their overlay material; MISSING_NUMBER
## while no mesh is marked.
func _overlay_strength() -> float:
	var meshes: Array[GeometryInstance3D] = _marked_meshes()
	if meshes.is_empty():
		return Api.MISSING_NUMBER
	var material: ShaderMaterial = meshes[0].material_overlay as ShaderMaterial
	return float(material.get_shader_parameter("fresnel_strength"))


## A uniform of the overlay material of the first marked mesh (or of its next_pass, for the
## glow_lift of a two-pass cue); null while nothing is marked.
func _overlay_uniform(uniform_name: String) -> Variant:
	var meshes: Array[GeometryInstance3D] = _marked_meshes()
	if meshes.is_empty():
		return null
	var material: ShaderMaterial = meshes[0].material_overlay as ShaderMaterial
	var value: Variant = material.get_shader_parameter(uniform_name)
	if value == null and material.next_pass is ShaderMaterial:
		value = (material.next_pass as ShaderMaterial).get_shader_parameter(uniform_name)
	return value


func _assert_untouched(model_deg: float = 0.0) -> void:
	assert_int(_s.history.get_undo_count()).is_equal(0)
	assert_int(_changed_count()).is_equal(0)
	assert_float(_s.model.get_item(FIRST).rotation_y).is_equal(model_deg)
	_drawn_is(model_deg)
	assert_str(_s.selected_uid()).is_equal(FIRST)


func _assert_cue_only_at_the_base() -> void:
	assert_bool(_s.cue_active()).is_false()
	assert_float(_s.mark_strength()).is_equal_approx(BASE, TOLERANCE)


# --- AC 15 (a): the key press ---


func test_ac15a_a_refused_press_keeps_the_angles_the_selection_and_plays_one_cue() -> void:
	if not await _select_refused():
		return
	var position_before: Vector3 = _s.local_position(_s.node_for(FIRST))
	_s.key(KEY_COMMA, true)
	_drawn_is(0.0)
	assert_float(_s.model.get_item(FIRST).rotation_y).is_equal(0.0)
	assert_int(_s.cue_count()).is_equal(1)
	assert_bool(_s.cue_active()).is_true()
	assert_str(_s.selected_uid()).is_equal(FIRST)
	assert_int(_s.history.get_undo_count()).is_equal(0)
	assert_int(_changed_count()).is_equal(0)
	# The cue is a glow, not a movement.
	assert_vector(_s.local_position(_s.node_for(FIRST))).is_equal_approx(
		position_before, Vector3(0.0005, 0.0005, 0.0005)
	)


func test_ac15a_a_tap_released_before_the_first_repeat_does_nothing_more() -> void:
	if not await _select_refused():
		return
	_s.key(KEY_COMMA, true)
	_s.step(0.05)
	_s.key(KEY_COMMA, false)
	assert_bool(_s.holding()).is_false()
	_assert_untouched()
	assert_int(_s.cue_count()).is_equal(1)
	_s.step(1.0)
	assert_int(_s.cue_count()).is_equal(1)
	_assert_cue_only_at_the_base()
	assert_array(_s.selection_timeline).is_equal(["selected:%s" % FIRST])


func test_ac15a_the_other_direction_and_the_fine_step_are_refused_the_same_way() -> void:
	if not await _select_refused():
		return
	_s.tap(KEY_PERIOD)
	assert_int(_s.cue_count()).is_equal(1)
	_assert_untouched()
	_s.step(1.0)
	_s.tap(KEY_COMMA, KEY_MASK_SHIFT)
	assert_int(_s.cue_count()).is_equal(2)
	_assert_untouched()
	_s.step(1.0)
	_s.tap(KEY_PERIOD, KEY_MASK_SHIFT)
	assert_int(_s.cue_count()).is_equal(3)
	_assert_untouched()


func test_ac15a_the_refusal_leaves_the_model_as_it_was() -> void:
	if not await _select_refused():
		return
	var state_before: Dictionary = ModelState.snapshot(_s.model)
	_s.tap(KEY_COMMA)
	_s.step(0.5)
	assert_dict(ModelState.snapshot(_s.model)).is_equal(state_before)


# --- AC 15 (d): the cue ---


func test_ac15d_the_glow_follows_the_table_at_fixed_steps_and_ends_at_the_base() -> void:
	if not await _select_refused():
		return
	_assert_cue_only_at_the_base()
	_s.tap(KEY_COMMA)
	for index: int in TABLE.size():
		if index > 0:
			_s.step(0.05)
		var label: String = "after %d steps of 0.05 s" % index
		(
			assert_float(_s.mark_strength())
			. override_failure_message("%s: view strength %s" % [label, _s.mark_strength()])
			. is_equal_approx(TABLE[index], TOLERANCE)
		)
		(
			assert_float(_overlay_strength())
			. override_failure_message("%s: overlay strength %s" % [label, _overlay_strength()])
			. is_equal_approx(TABLE[index], TOLERANCE)
		)
		if index < TABLE.size() - 1:
			assert_bool(_s.cue_active()).override_failure_message(label).is_true()
	_s.step(Api.tuning("REFUSAL_CUE_DURATION_S") - 0.05 * (TABLE.size() - 1) + 0.02)
	_assert_cue_only_at_the_base()
	assert_float(_overlay_strength()).is_equal_approx(BASE, TOLERANCE)


func test_ac15d_every_uniform_follows_the_addendum_table_on_the_overlay_of_the_node() -> void:
	if not await _select_refused():
		return
	_s.tap(KEY_COMMA)
	for index: int in TABLE.size():
		if index > 0:
			_s.step(0.05)
		var label: String = "step %d" % index
		var colour: Variant = _overlay_uniform("glow_colour")
		var power: Variant = _overlay_uniform("fresnel_power")
		var lift: Variant = _overlay_uniform("glow_lift")
		assert_bool(colour is Color).override_failure_message(label + ": glow_colour").is_true()
		assert_bool(lift is Vector3).override_failure_message(label + ": glow_lift").is_true()
		if not (colour is Color and lift is Vector3):
			return
		assert_float((colour as Color).r).override_failure_message(label).is_equal_approx(
			1.0, TOLERANCE
		)
		assert_float((colour as Color).g).override_failure_message(label).is_equal_approx(
			COLOUR_G[index], TOLERANCE
		)
		assert_float((colour as Color).b).override_failure_message(label).is_equal_approx(
			COLOUR_B[index], TOLERANCE
		)
		assert_float(float(power)).override_failure_message(label).is_equal_approx(
			POWER[index], TOLERANCE
		)
		assert_float((lift as Vector3).x).override_failure_message(label).is_equal(0.0)
		assert_float((lift as Vector3).y).override_failure_message(label).is_equal_approx(
			LIFT_G[index], TOLERANCE
		)
		assert_float((lift as Vector3).z).override_failure_message(label).is_equal_approx(
			LIFT_B[index], TOLERANCE
		)
		# The view getters read the same values.
		assert_float(_s.cue_power()).override_failure_message(label).is_equal_approx(
			POWER[index], TOLERANCE
		)
		assert_float(_s.cue_lift().y).override_failure_message(label).is_equal_approx(
			LIFT_G[index], TOLERANCE
		)
		assert_float(_s.cue_colour().g).override_failure_message(label).is_equal_approx(
			COLOUR_G[index], TOLERANCE
		)
		assert_float(_s.cue_strength()).override_failure_message(label).is_equal_approx(
			TABLE[index], TOLERANCE
		)
		assert_str(_s.cue_uid()).override_failure_message(label).is_equal(FIRST)
	_s.step(0.4)
	assert_bool(_s.cue_active()).is_false()
	assert_str(_s.cue_uid()).is_equal("")
	var after_colour: Variant = _overlay_uniform("glow_colour")
	assert_bool(after_colour is Color).is_true()
	assert_float((after_colour as Color).g).is_equal_approx(COLOUR_G[0], TOLERANCE)
	assert_float(float(_overlay_uniform("fresnel_power"))).is_equal_approx(POWER[0], TOLERANCE)
	var after_lift: Variant = _overlay_uniform("glow_lift")
	(
		assert_bool(after_lift is Vector3 and (after_lift as Vector3).is_equal_approx(Vector3.ZERO))
		. is_true()
	)


func test_ac15d_the_shared_selection_material_is_never_written_and_comes_back() -> void:
	if not await _select_refused():
		return
	var shared: ShaderMaterial = load(SELECTION_MATERIAL) as ShaderMaterial
	_s.tap(KEY_COMMA)
	_s.step(0.1)
	assert_float(float(shared.get_shader_parameter("fresnel_strength"))).is_equal(BASE)
	assert_float(float(shared.get_shader_parameter("fresnel_power"))).is_equal(1.6)
	assert_bool((shared.get_shader_parameter("glow_colour") as Color).g > 0.85).is_true()
	assert_bool(shared.get_shader_parameter("glow_lift") == Vector3.ZERO).is_true()
	_s.step(1.0)
	var meshes: Array[GeometryInstance3D] = _marked_meshes()
	assert_int(meshes.size()).is_greater(0)
	for mesh: GeometryInstance3D in meshes:
		assert_str(mesh.material_overlay.resource_path).is_equal(SELECTION_MATERIAL)
	assert_float(float(shared.get_shader_parameter("fresnel_strength"))).is_equal(BASE)


func test_ac15d_the_cue_never_goes_above_the_peak() -> void:
	if not await _select_refused():
		return
	var peak: float = Api.tuning("REFUSAL_CUE_PEAK_STRENGTH")
	_s.tap(KEY_COMMA)
	for frame: int in 30:
		_s.step(1.0 / 120.0)
		assert_float(_s.mark_strength()).is_less_equal(peak + TOLERANCE)
		assert_float(_overlay_strength()).is_less_equal(peak + TOLERANCE)


func test_ac15d_a_second_refusal_restarts_the_cue_and_does_not_stack() -> void:
	if not await _select_refused():
		return
	var peak: float = Api.tuning("REFUSAL_CUE_PEAK_STRENGTH")
	_s.tap(KEY_COMMA)
	_s.step(0.15)
	assert_float(_s.mark_strength()).is_equal_approx(peak, TOLERANCE)
	_s.tap(KEY_COMMA)
	assert_int(_s.cue_count()).is_equal(2)
	assert_float(_s.mark_strength()).is_equal_approx(BASE, TOLERANCE)
	assert_bool(_s.cue_active()).is_true()
	_s.step(0.05)
	assert_float(_s.mark_strength()).is_equal_approx(TABLE[1], TOLERANCE)
	_s.tap(KEY_PERIOD)
	_s.step(0.1)
	assert_int(_s.cue_count()).is_equal(3)
	assert_float(_s.mark_strength()).is_less_equal(peak + TOLERANCE)
	_s.step(1.0)
	_assert_cue_only_at_the_base()


func test_ac15d_play_refusal_cue_is_a_no_op_for_an_item_that_is_not_selected() -> void:
	if not await _select_refused():
		return
	Api.call_on(_s.view, "play_refusal_cue", [SECOND], null)
	assert_int(_s.cue_count()).is_equal(0)
	assert_bool(_s.cue_active()).is_false()
	Api.call_on(_s.view, "play_refusal_cue", ["ffffffff"], null)
	assert_int(_s.cue_count()).is_equal(0)
	Api.call_on(_s.view, "play_refusal_cue", [FIRST], null)
	assert_int(_s.cue_count()).is_equal(1)


func test_ac15d_play_refusal_cue_is_a_no_op_while_the_mark_is_hidden() -> void:
	if not await _select_refused():
		return
	var blocker: Control = _s.make_blocker()
	_s.set_blocked(blocker, true)
	Api.call_on(_s.view, "play_refusal_cue", [FIRST], null)
	assert_int(_s.cue_count()).is_equal(0)
	assert_bool(_s.cue_active()).is_false()
	_s.set_blocked(blocker, false)
	Api.call_on(_s.view, "play_refusal_cue", [FIRST], null)
	assert_int(_s.cue_count()).is_equal(1)


# --- AC 15 (b): the hold ---


func test_ac15b_a_hold_through_the_neighbour_shows_the_pending_angle_and_snaps_back() -> void:
	if not await _select_refused():
		return
	var peak: float = Api.tuning("REFUSAL_CUE_PEAK_STRENGTH")
	_s.key(KEY_COMMA, true)
	assert_int(_s.cue_count()).is_equal(1)
	_drawn_is(0.0)
	# First repeat: start plus all steps so far (the refused first step included), through the
	# stone, 0.2 mm off the branch.
	_s.step(_time_for(1))
	assert_bool(_s.holding()).is_true()
	_drawn_is(30.0)
	_s.step(_time_for(3) - _time_for(1))
	_drawn_is(60.0)
	# Nothing in the model, no command, no signal while the key is down; no cue per repeat.
	assert_float(_s.model.get_item(FIRST).rotation_y).is_equal(0.0)
	assert_int(_s.history.get_undo_count()).is_equal(0)
	assert_int(_changed_count()).is_equal(0)
	assert_int(_s.cue_count()).is_equal(1)
	assert_str(_s.selected_uid()).is_equal(FIRST)
	# The release judges 60 degrees (through the glass): snap back at once and one more cue.
	_s.key(KEY_COMMA, false)
	assert_bool(_s.holding()).is_false()
	_drawn_is(0.0)
	assert_int(_s.cue_count()).is_equal(2)
	assert_bool(_s.cue_active()).is_true()
	assert_float(_s.mark_strength()).is_equal_approx(BASE, TOLERANCE)
	_assert_untouched()
	_s.step(0.15)
	assert_float(_s.mark_strength()).is_equal_approx(peak, TOLERANCE)
	_s.step(1.0)
	_assert_cue_only_at_the_base()
	assert_int(_s.cue_count()).is_equal(2)


func test_ac15b_the_hold_after_a_refused_press_ends_on_a_valid_angle_with_one_command() -> void:
	if not await _select_refused():
		return
	_s.key(KEY_COMMA, true)
	assert_int(_s.cue_count()).is_equal(1)
	# The press and 11 repeats are 12 steps of 15 degrees: 180, the same footprint, valid again.
	_s.step(_time_for(11))
	_drawn_is(180.0)
	_s.key(KEY_COMMA, false)
	assert_int(_s.history.get_undo_count()).is_equal(1)
	assert_float(_s.model.get_item(FIRST).rotation_y).is_equal_approx(180.0, 0.001)
	assert_int(_changed_count()).is_equal(1)
	_drawn_is(180.0)
	assert_str(_s.selected_uid()).is_equal(FIRST)
	# One cue only: the press. The release was valid.
	assert_int(_s.cue_count()).is_equal(1)
	assert_bool(_s.history.undo()).is_true()
	assert_float(_s.model.get_item(FIRST).rotation_y).is_equal(0.0)


func test_ac15b_a_hold_from_a_valid_press_shows_invalid_angles_and_snaps_back_with_one_cue(
) -> void:
	if not await _select_hold():
		return
	_s.key(KEY_COMMA, true)
	# The first step (15 degrees) is valid: drawn at once, no cue.
	_drawn_is(15.0)
	assert_int(_s.cue_count()).is_equal(0)
	_s.step(_time_for(2))
	assert_bool(_s.holding()).is_true()
	# Press and two repeats: 45 degrees swings the branch through the stone; no check runs.
	_drawn_is(45.0)
	assert_int(_s.cue_count()).is_equal(0)
	assert_int(_s.history.get_undo_count()).is_equal(0)
	assert_int(_changed_count()).is_equal(0)
	_s.key(KEY_COMMA, false)
	_drawn_is(0.0)
	assert_int(_s.cue_count()).is_equal(1)
	assert_bool(_s.cue_active()).is_true()
	_assert_untouched()


func test_ac15b_a_hold_from_a_valid_press_ending_on_a_valid_angle_commits_with_no_cue() -> void:
	if not await _select_hold():
		return
	_s.key(KEY_COMMA, true)
	_s.step(_time_for(11))
	_drawn_is(180.0)
	assert_int(_s.cue_count()).is_equal(0)
	_s.key(KEY_COMMA, false)
	assert_int(_s.history.get_undo_count()).is_equal(1)
	assert_float(_s.model.get_item(FIRST).rotation_y).is_equal_approx(180.0, 0.001)
	assert_int(_changed_count()).is_equal(1)
	assert_int(_s.cue_count()).is_equal(0)
	assert_bool(_s.cue_active()).is_false()


func test_ac15b_a_valid_tap_commits_one_step_and_plays_no_cue() -> void:
	if not await _select_hold():
		return
	_s.tap(KEY_COMMA)
	assert_float(_s.model.get_item(FIRST).rotation_y).is_equal_approx(15.0, 0.001)
	assert_int(_s.history.get_undo_count()).is_equal(1)
	assert_int(_changed_count()).is_equal(1)
	assert_int(_s.cue_count()).is_equal(0)
	_s.step(0.5)
	assert_int(_s.cue_count()).is_equal(0)


func test_ac15b_a_hold_that_ends_at_the_start_angle_runs_no_command_and_no_cue() -> void:
	if not await _select_hold():
		return
	_s.key(KEY_COMMA, true)
	# 24 steps of 15 degrees are a full turn: the final angle equals the start (#31).
	_s.step(_time_for(23))
	_s.key(KEY_COMMA, false)
	assert_int(_s.history.get_undo_count()).is_equal(0)
	assert_int(_changed_count()).is_equal(0)
	assert_int(_s.cue_count()).is_equal(0)
	_drawn_is(0.0)


func test_ac15b_a_refused_release_after_a_refused_press_keeps_the_hold_free_in_between() -> void:
	if not await _select_refused():
		return
	_s.key(KEY_COMMA, true)
	_s.step(_time_for(1))
	_drawn_is(30.0)
	_s.key(KEY_COMMA, false)
	_drawn_is(0.0)
	assert_int(_s.cue_count()).is_equal(2)
	# The item can still be turned later (the refusal froze nothing).
	_s.step(1.0)
	_s.key(KEY_COMMA, true)
	_s.step(_time_for(11))
	_s.key(KEY_COMMA, false)
	assert_float(_s.model.get_item(FIRST).rotation_y).is_equal_approx(180.0, 0.001)
	assert_int(_s.history.get_undo_count()).is_equal(1)


# --- no cue ---


func test_ac15d_a_cancelled_hold_plays_no_cue() -> void:
	if not await _select_hold():
		return
	_s.key(KEY_COMMA, true)
	_s.step(_time_for(2))
	_drawn_is(45.0)
	_s.esc()
	assert_bool(_s.holding()).is_false()
	_drawn_is(0.0)
	_s.key(KEY_COMMA, false)
	assert_int(_s.cue_count()).is_equal(0)
	assert_bool(_s.cue_active()).is_false()
	assert_int(_s.history.get_undo_count()).is_equal(0)


func test_ac15d_the_ghost_rotation_plays_no_cue() -> void:
	var model: AquariumModel = Rig.model()
	Rig.add_item(model, SECOND, Rig.STONE, 0.0, 0.0)
	if not await _open(model):
		return
	_s.pick(Rig.STONE)
	_s.move(_s.screen_of(0.0, 0.0))
	assert_bool(_s.ghost_shown()).is_false()
	_s.tap(KEY_COMMA)
	_s.tap(KEY_PERIOD)
	_s.tap(KEY_COMMA, KEY_MASK_SHIFT)
	_s.step(0.5)
	assert_int(_s.cue_count()).is_equal(0)
	assert_bool(_s.cue_active()).is_false()


func test_ac15d_a_drag_preview_rotation_plays_no_cue() -> void:
	if not await _select_hold():
		return
	_s.press(_s.screen_of_item(FIRST))
	_s.move(_s.screen_of(-0.1, -0.06))
	assert_bool(_s.dragging()).is_true()
	_s.tap(KEY_COMMA)
	_s.step(0.5)
	assert_int(_s.cue_count()).is_equal(0)
	_s.release(_s.screen_of(-0.1, -0.06))
	assert_int(_s.cue_count()).is_equal(0)


# --- the cue is cancelled ---


func _cue_running() -> bool:
	if not await _select_refused():
		return false
	_s.tap(KEY_COMMA)
	_s.step(0.05)
	assert_bool(_s.cue_active()).is_true()
	return _s.cue_active()


func _assert_cue_cancelled() -> void:
	assert_bool(_s.cue_active()).is_false()
	_s.step(0.5)
	assert_bool(_s.cue_active()).is_false()
	assert_float(_s.mark_strength()).is_less_equal(BASE + TOLERANCE)


func test_ac15d_a_model_reset_cancels_the_cue() -> void:
	if not await _cue_running():
		return
	var other: AquariumModel = Rig.model()
	Rig.add_item(other, "b0000001", Rig.AMPHORA, 0.0, 0.0)
	_s.model.reset_from(other)
	_s.step(0.0)
	_assert_cue_cancelled()


func test_ac15d_a_displayed_tank_cancels_the_cue() -> void:
	if not await _cue_running():
		return
	EventBus.tank_displayed.emit(&"tank_medium_1")
	_assert_cue_cancelled()


func test_ac15d_removing_the_item_cancels_the_cue() -> void:
	if not await _cue_running():
		return
	_s.model.apply_remove_item(FIRST)
	_s.step(0.0)
	_assert_cue_cancelled()


func test_ac15d_clearing_the_selection_cancels_the_cue() -> void:
	if not await _cue_running():
		return
	_s.esc()
	assert_str(_s.selected_uid()).is_equal("")
	_assert_cue_cancelled()


func test_ac15d_selecting_another_item_cancels_the_cue() -> void:
	if not await _cue_running():
		return
	_s.click(_s.screen_of_item(SECOND))
	assert_str(_s.selected_uid()).is_equal(SECOND)
	_assert_cue_cancelled()


func test_ac15d_photo_mode_blocking_cancels_the_cue_and_hides_the_mark() -> void:
	if not await _cue_running():
		return
	var blocker: Control = _s.make_blocker()
	_s.set_blocked(blocker, true)
	assert_bool(_s.cue_active()).is_false()
	assert_int(_marked_meshes().size()).is_equal(0)
	_s.step(0.5)
	_s.set_blocked(blocker, false)
	# The mark is back at its normal strength, no cue left over.
	assert_bool(_s.cue_active()).is_false()
	assert_int(_marked_meshes().size()).is_greater(0)
	assert_float(_overlay_strength()).is_equal_approx(BASE, TOLERANCE)


func test_ac15d_a_valid_commit_does_not_touch_a_running_cue() -> void:
	if not await _select_hold():
		return
	# A hold that ends on 45 degrees is refused at the release: cue 1, running.
	_s.key(KEY_COMMA, true)
	_s.step(_time_for(2))
	_s.key(KEY_COMMA, false)
	assert_int(_s.cue_count()).is_equal(1)
	assert_bool(_s.cue_active()).is_true()
	_s.step(0.1)
	# A valid tap meanwhile commits and leaves the cue running, not restarted.
	_s.tap(KEY_COMMA)
	assert_int(_s.history.get_undo_count()).is_equal(1)
	assert_int(_s.cue_count()).is_equal(1)
	assert_bool(_s.cue_active()).is_true()
	_s.step(0.05)
	assert_float(_s.mark_strength()).is_greater(Api.tuning("REFUSAL_CUE_PEAK_STRENGTH") - 0.1)


# --- AC 16: items that are already invalid ---


func _select_legacy() -> bool:
	var model: AquariumModel = Rig.model()
	# 28 cm long from x 0.13 to 0.41: through the glass (0.30), already invalid.
	Rig.add_item(model, FIRST, Rig.BRANCH, 0.27, 0.0, 0.0)
	if not await _open(model):
		return false
	return _select(FIRST)


func test_ac16_an_item_through_the_glass_turns_by_a_tap_with_no_cue() -> void:
	if not await _select_legacy():
		return
	_s.tap(KEY_COMMA)
	assert_float(_s.model.get_item(FIRST).rotation_y).is_equal_approx(15.0, 0.001)
	assert_int(_s.history.get_undo_count()).is_equal(1)
	assert_int(_changed_count()).is_equal(1)
	assert_int(_s.cue_count()).is_equal(0)
	assert_bool(_s.cue_active()).is_false()
	assert_vector(_s.model.get_item(FIRST).position).is_equal(Vector3(0.27, 0.0, 0.0))
	_s.tap(KEY_COMMA, KEY_MASK_SHIFT)
	assert_float(_s.model.get_item(FIRST).rotation_y).is_equal_approx(16.0, 0.001)
	assert_int(_s.cue_count()).is_equal(0)


func test_ac16_an_item_through_the_glass_turns_by_a_hold_to_a_worse_angle() -> void:
	if not await _select_legacy():
		return
	_s.key(KEY_COMMA, true)
	_s.step(_time_for(5))
	_s.key(KEY_COMMA, false)
	# Press and 5 repeats are 6 steps: 90 degrees, 28 cm across the 30 cm tank at x 0.27 is worse
	# than before, and still allowed.
	assert_float(_s.model.get_item(FIRST).rotation_y).is_equal_approx(90.0, 0.001)
	assert_int(_s.history.get_undo_count()).is_equal(1)
	assert_int(_s.cue_count()).is_equal(0)
	assert_str(_s.selected_uid()).is_equal(FIRST)


func test_ac16_loading_never_moves_or_removes_an_item() -> void:
	if not await _select_legacy():
		return
	var other: AquariumModel = Rig.model()
	Rig.add_item(other, "b0000001", Rig.BRANCH, 0.27, 0.0, 0.0)
	Rig.add_item(other, "b0000002", Rig.STONE, 0.27, 0.0, 10.0)
	var state_before: Dictionary = ModelState.snapshot(other)
	_s.model.reset_from(other)
	_s.step(0.0)
	await _s.frame()
	assert_dict(ModelState.snapshot(_s.model)).is_equal(state_before)
	assert_int(_s.history.get_undo_count()).is_equal(0)
	assert_int(_s.drawn_count()).is_equal(2)


# --- log gate (ADR 0004) ---


func test_ac15_a_refused_press_hold_and_release_log_no_error_and_no_warning() -> void:
	if not await _select_refused():
		return
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void:
			_s.tap(KEY_COMMA)
			_s.step(0.4)
			_s.key(KEY_PERIOD, true)
			_s.step(_time_for(3))
			_s.key(KEY_PERIOD, false)
			_s.step(0.5)
			await _s.frame()
	)
	assert_dict(seen["errors"]).is_empty()
	assert_dict(seen["warnings"]).is_empty()
	assert_dict(seen["script_errors"]).is_empty()
