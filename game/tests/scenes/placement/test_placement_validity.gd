extends GdUnitTestSuite
## #33 AC 12, 13 and 17 (owner: developer): what the player sees and commits with the new validity
## rule, in the real room with the Placement child.
## AC 12: for a grid of spots and rotations on each tank, the ghost is shown exactly when
## PlacementRules.allows() says so, and a left click places exactly then (no command, no history
## entry and the pick stays when it does not). AC 13: a drag released over a spot that is not valid
## cancels with the model, the history and the drawn item as they were; a valid drop still commits.
## AC 17 (scene part): with 100 items a pointer move creates no drawn node, no command and no
## history entry (the counting catalog is in test_placement_rules_lookups.gd).
## Test decisions: the model of the grid has a stone at (-0.1, 0) and an amphora at (0.1, 0.05) so
## that overlaps are in the grid; a placed item is undone again after each click, so every spot is
## judged against the same model; the candidate is the river_stone at the ground point of the
## pointer with the rotation of the ghost.

const Rig := preload("res://tests/helpers/placement_rig.gd")
const Session := preload("res://tests/helpers/placement_session.gd")
const Api := preload("res://tests/helpers/placement_api.gd")
const Fx := preload("res://tests/helpers/validity_fixtures.gd")
const Recorder := preload("res://tests/helpers/signal_recorder.gd")
const ModelState := preload("res://tests/helpers/model_state.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")

const FIRST := "a0000001"
const SECOND := "a0000002"
const X_FRACTIONS: Array[float] = [-0.95, -0.6, -0.25, 0.1, 0.45, 0.8, 0.98]
const Z_FRACTIONS: Array[float] = [-0.9, -0.3, 0.3, 0.9]
## Comma taps before each round: rotations 0, 30 and 90 degrees.
const TAPS: Array[int] = [0, 2, 4]

var _s: Session = null


func after_test() -> void:
	Rig.close(_s)


func _open(model: AquariumModel = null, elevation: float = Rig.TOP_ELEVATION_DEG) -> bool:
	_s = await Rig.open(self, model, elevation)
	var complete: bool = _s.placement != null and _s.view != null and _s.ghost != null
	(
		assert_bool(complete)
		. override_failure_message(
			"RoomCorner needs a Placement child with the children PlacedItems and Ghost"
		)
		. is_true()
	)
	return complete


func _grid_model(tank: StringName) -> AquariumModel:
	var model: AquariumModel = Rig.model(tank)
	Rig.add_item(model, FIRST, Rig.STONE, -0.1, 0.0)
	Rig.add_item(model, SECOND, Rig.AMPHORA, 0.1, 0.05, 20.0)
	return model


## Ghost visible, allows() and the outcome of a click for every spot of the grid on one tank.
func _check_grid(tank: StringName) -> void:
	if not await _open(_grid_model(tank)):
		return
	var rules: RefCounted = Api.rules()
	var interior: Vector3 = Fx.interior(tank)
	var shown_count: int = 0
	var hidden_count: int = 0
	_s.pick(Rig.STONE)
	for taps: int in TAPS:
		for tap_index: int in taps:
			_s.tap(KEY_COMMA)
		for x_fraction: float in X_FRACTIONS:
			for z_fraction: float in Z_FRACTIONS:
				var spot: Vector2 = Vector2(
					interior.x / 2.0 * x_fraction, interior.z / 2.0 * z_fraction
				)
				var at: Vector2 = _s.screen_of(spot.x, spot.y)
				_s.move(at)
				var ground: Vector3 = _s.ground_local(at)
				var rotation_deg: float = _s.ghost_rotation()
				var candidate: PlacedItem = Fx.item(
					"c0000001", Rig.STONE, ground.x, ground.z, rotation_deg
				)
				var valid: bool = Fx.ok(rules, _s.model, candidate)
				var label: String = "%s rot %s spot %s" % [tank, rotation_deg, spot]
				(
					assert_bool(_s.ghost_shown())
					. override_failure_message(
						"%s: ghost visible must equal allows %s" % [label, valid]
					)
					. is_equal(valid)
				)
				var count_before: int = _s.model.get_item_count()
				var undo_before: int = _s.history.get_undo_count()
				_s.click(at)
				var placed: bool = _s.model.get_item_count() == count_before + 1
				(
					assert_bool(placed)
					. override_failure_message(
						"%s: the click outcome must equal allows %s" % [label, valid]
					)
					. is_equal(valid)
				)
				if placed:
					shown_count += 1
					assert_int(_s.history.get_undo_count()).is_equal(undo_before + 1)
					assert_bool(_s.history.undo()).is_true()
				else:
					hidden_count += 1
					assert_int(_s.history.get_undo_count()).is_equal(undo_before)
				assert_str(_s.picked_id()).is_equal(String(Rig.STONE))
				assert_int(_s.model.get_item_count()).is_equal(count_before)
	(
		assert_int(shown_count)
		. override_failure_message("%s: no valid spot in the grid" % tank)
		. is_greater(0)
	)
	(
		assert_int(hidden_count)
		. override_failure_message("%s: no invalid spot in the grid" % tank)
		. is_greater(0)
	)


func test_ac12_ghost_allows_and_the_click_agree_on_the_small_tank() -> void:
	await _check_grid(Fx.SMALL)


func test_ac12_ghost_allows_and_the_click_agree_on_the_medium_tank() -> void:
	await _check_grid(Fx.MEDIUM)


func test_ac12_ghost_allows_and_the_click_agree_on_the_large_tank() -> void:
	await _check_grid(Fx.LARGE)


func test_ac12_over_an_item_no_ghost_a_click_places_nothing_and_the_pick_stays() -> void:
	if not await _open(_grid_model(Fx.MEDIUM)):
		return
	_s.pick(Rig.STONE)
	var over: Vector2 = _s.screen_of(-0.1, 0.0)
	_s.move(over)
	assert_bool(_s.ghost_shown()).is_false()
	var state_before: Dictionary = ModelState.snapshot(_s.model)
	_s.click(over)
	assert_dict(ModelState.snapshot(_s.model)).is_equal(state_before)
	assert_int(_s.history.get_undo_count()).is_equal(0)
	assert_str(_s.picked_id()).is_equal(String(Rig.STONE))
	# The spot beside it shows the ghost and places.
	var beside: Vector2 = _s.screen_of(0.0, -0.1)
	_s.move(beside)
	assert_bool(_s.ghost_shown()).is_true()
	_s.click(beside)
	assert_int(_s.model.get_item_count()).is_equal(3)


func test_ac12_a_spot_with_a_gap_beside_an_item_shows_the_ghost() -> void:
	var model: AquariumModel = Rig.model()
	Rig.add_item(model, FIRST, Rig.STONE, 0.0, 0.0)
	if not await _open(model):
		return
	_s.pick(Rig.STONE)
	# The pointer sits 0.12 m from the stone centre: 1 cm clear of the touching distance 0.11.
	var at: Vector2 = _s.screen_of(0.12, 0.0)
	_s.move(at)
	assert_bool(_s.ghost_shown()).is_true()
	_s.click(at)
	assert_int(_s.model.get_item_count()).is_equal(2)


func test_ac12_an_invalid_spot_logs_no_error_and_no_warning() -> void:
	if not await _open(_grid_model(Fx.MEDIUM)):
		return
	_s.pick(Rig.STONE)
	var over: Vector2 = _s.screen_of(-0.1, 0.0)
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void:
			_s.move(over)
			_s.click(over)
			_s.move(_s.screen_of(0.29, 0.0))
			_s.click(_s.screen_of(0.29, 0.0))
	)
	assert_dict(seen["errors"]).is_empty()
	assert_dict(seen["warnings"]).is_empty()


# --- AC 13 ---


func _pair() -> AquariumModel:
	var model: AquariumModel = Rig.model()
	Rig.add_item(model, FIRST, Rig.STONE, -0.15, 0.0)
	Rig.add_item(model, SECOND, Rig.STONE, 0.05, 0.0)
	return model


func _drag_first_to(target: Vector2) -> void:
	_s.press(_s.screen_of_item(FIRST))
	_s.move(target)


func test_ac13_a_drag_over_an_overlap_hides_the_preview_and_the_release_cancels() -> void:
	if not await _open(_pair()):
		return
	var state_before: Dictionary = ModelState.snapshot(_s.model)
	var drawn_before: Vector3 = _s.local_position(_s.node_for(FIRST))
	var target: Vector2 = _s.screen_of(0.07, 0.0)
	_drag_first_to(target)
	assert_bool(_s.dragging()).is_true()
	assert_bool(_s.ghost_shown()).is_false()
	assert_vector(_s.local_position(_s.node_for(FIRST))).is_equal_approx(
		drawn_before, Vector3(0.0005, 0.0005, 0.0005)
	)
	_s.release(target)
	assert_bool(_s.dragging()).is_false()
	assert_bool(_s.ghost_shown()).is_false()
	assert_dict(ModelState.snapshot(_s.model)).is_equal(state_before)
	assert_int(_s.history.get_undo_count()).is_equal(0)
	assert_vector(_s.local_position(_s.node_for(FIRST))).is_equal_approx(
		drawn_before, Vector3(0.0005, 0.0005, 0.0005)
	)


func test_ac13_a_cancelled_drop_keeps_the_selection_as_it_was() -> void:
	if not await _open(_pair()):
		return
	# Nothing selected before: nothing selected after (#31 AC 25 and 36).
	var target: Vector2 = _s.screen_of(0.07, 0.0)
	_drag_first_to(target)
	_s.release(target)
	assert_str(_s.selected_uid()).is_equal("")
	assert_array(_s.selection_timeline).is_empty()
	# Another item selected before: it stays selected.
	_s.click(_s.screen_of_item(SECOND))
	assert_str(_s.selected_uid()).is_equal(SECOND)
	_drag_first_to(target)
	_s.release(target)
	assert_str(_s.selected_uid()).is_equal(SECOND)
	assert_int(_s.history.get_undo_count()).is_equal(0)


func test_ac13_a_drop_through_the_glass_cancels() -> void:
	if not await _open(_pair()):
		return
	var state_before: Dictionary = ModelState.snapshot(_s.model)
	var target: Vector2 = _s.screen_of(0.29, 0.0)
	_drag_first_to(target)
	assert_bool(_s.dragging()).is_true()
	assert_bool(_s.ghost_shown()).is_false()
	_s.release(target)
	assert_dict(ModelState.snapshot(_s.model)).is_equal(state_before)
	assert_int(_s.history.get_undo_count()).is_equal(0)


func test_ac13_a_drop_beside_the_neighbour_still_commits() -> void:
	if not await _open(_pair()):
		return
	var target: Vector2 = _s.screen_of(-0.2, 0.08)
	_drag_first_to(target)
	assert_bool(_s.ghost_shown()).is_true()
	_s.release(target)
	assert_int(_s.history.get_undo_count()).is_equal(1)
	assert_float(_s.model.get_item(FIRST).position.x).is_equal_approx(-0.2, 0.001)


func test_ac13_a_drag_over_the_spot_of_the_item_itself_is_not_an_overlap() -> void:
	if not await _open(_pair()):
		return
	# The dragged stone moves 4 cm; it never collides with its own start.
	var target: Vector2 = _s.screen_of(-0.19, 0.0)
	_drag_first_to(target)
	assert_bool(_s.ghost_shown()).is_true()
	_s.release(target)
	assert_int(_s.history.get_undo_count()).is_equal(1)


# --- AC 17, scene part ---


func _crowd() -> AquariumModel:
	var model: AquariumModel = Rig.model(Fx.LARGE)
	for index: int in 100:
		var column: int = index % 20
		var row: int = floori(index / 20.0)
		Rig.add_item(model, "d%07d" % index, Rig.STONE, -0.475 + 0.05 * column, -0.1 + 0.05 * row)
	return model


func test_ac17_with_100_items_a_pointer_move_creates_no_node_no_command_no_history_entry() -> void:
	if not await _open(_crowd()):
		return
	assert_int(_s.model.get_item_count()).is_equal(100)
	await _s.frame()
	assert_int(_s.drawn_count()).is_equal(100)
	_s.pick(Rig.STONE)
	_s.move(_s.screen_of(0.0, 0.0))
	var created_before: int = _s.created_count()
	var recorder: Recorder = Recorder.new()
	recorder.watch(_s.model)
	for index: int in 40:
		_s.move(_s.screen_of(-0.45 + 0.0225 * index, -0.15 + 0.0075 * index))
	assert_int(_s.created_count()).is_equal(created_before)
	assert_int(_s.drawn_count()).is_equal(100)
	assert_int(recorder.count()).is_equal(0)
	assert_int(_s.history.get_undo_count()).is_equal(0)
	assert_int(_s.model.get_item_count()).is_equal(100)


func test_ac17_with_100_items_a_refused_click_changes_nothing() -> void:
	if not await _open(_crowd()):
		return
	_s.pick(Rig.STONE)
	var at: Vector2 = _s.screen_of(0.0, 0.0)
	_s.move(at)
	assert_bool(_s.ghost_shown()).is_false()
	var created_before: int = _s.created_count()
	_s.click(at)
	assert_int(_s.model.get_item_count()).is_equal(100)
	assert_int(_s.history.get_undo_count()).is_equal(0)
	assert_int(_s.created_count()).is_equal(created_before)
