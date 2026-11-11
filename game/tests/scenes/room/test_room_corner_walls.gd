# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #25 criteria 17 to 20 (owner: developer): the wall cutaway of the room. The camera position alone
## decides: behind the back wall plane (z below -0.215 m) the back wall is hidden, behind the left
## wall plane (x below -0.85 m) the left wall is hidden, at any elevation. The test places the
## camera at synthetic poses (azimuth and elevation at the default distance, per tank), checks the
## actual camera position against the plane first, and then steps the WallCutaway node with the
## actual camera position until the fade (0.2 s) has settled. No pixel assertion. The node is
## reached by name (WallCutaway) and by method (step, is_hidden_target, get_alpha, is_wall_rendered)
## with the wall ids &"back" and &"left"; see tests/helpers/camera_rig.gd.

const Api := preload("res://tests/helpers/late_api.gd")
const Room := preload("res://tests/helpers/room_rig.gd")
const Cam := preload("res://tests/helpers/camera_rig.gd")
const Table := preload("res://tests/helpers/tank_table.gd")
const Glb := preload("res://tests/helpers/glb_mesh_checks.gd")
const OrbitApi := preload("res://tests/helpers/orbit_api.gd")
const ModelState := preload("res://tests/helpers/model_state.gd")

const BACK := &"back"
const LEFT := &"left"
## Half of the hysteresis band: inside it the old state stays.
const HALF_BAND_M := 0.025

var _model: AquariumModel = null
var _history: CommandHistory = null
var _catalog: RefCounted = null
var _viewport: SubViewport = null
var _room: Node3D = null
var _camera: Camera3D = null
var _walls: Node = null


func before_test() -> void:
	_history = CommandHistory.new()
	_catalog = Room.default_catalog()


func _open(id: StringName) -> bool:
	_model = Room.model_with(id)
	var rig: Dictionary = await Cam.open(self, _model)
	_viewport = rig["viewport"]
	_room = rig["room"]
	_camera = Cam.camera_of(_room)
	_walls = Cam.walls_of(_room)
	(
		assert_bool(_camera != null)
		. override_failure_message("the room has no BuildCamera child (Camera3D)")
		. is_true()
	)
	(
		assert_bool(_walls != null)
		. override_failure_message("the room has no WallCutaway child")
		. is_true()
	)
	return _camera != null and _walls != null


func _hidden_target(id: StringName) -> bool:
	return _walls.call("is_hidden_target", id)


func _alpha(id: StringName) -> float:
	return _walls.call("get_alpha", id)


func _rendered(id: StringName) -> bool:
	return _walls.call("is_wall_rendered", id)


func _wall_mesh(id: StringName) -> MeshInstance3D:
	return Glb.find_mesh(_room, "BackWall" if id == BACK else "SideWall")


## Behind the plane by more than the hysteresis half band, so the pose is a real test pose.
func _assert_behind(id: StringName) -> void:
	var distance: float = _plane_distance(id)
	(
		assert_float(distance)
		. override_failure_message(
			(
				"pose is not behind the %s wall plane: camera %s, distance %s"
				% [id, _camera.global_position, distance]
			)
		)
		. is_less(-HALF_BAND_M)
	)


func _assert_in_front(id: StringName) -> void:
	var distance: float = _plane_distance(id)
	(
		assert_float(distance)
		. override_failure_message(
			(
				"pose is not in front of the %s wall plane: camera %s, distance %s"
				% [id, _camera.global_position, distance]
			)
		)
		. is_greater(0.0)
	)


func _plane_distance(id: StringName) -> float:
	if id == BACK:
		return _camera.global_position.z - Cam.BACK_PLANE_Z_M
	return _camera.global_position.x - Cam.LEFT_PLANE_X_M


func _assert_hidden(id: StringName) -> void:
	(
		assert_bool(_hidden_target(id))
		. override_failure_message("%s wall: target is shown" % id)
		. is_true()
	)
	(
		assert_float(_alpha(id))
		. override_failure_message("%s wall: alpha is not 0" % id)
		. is_equal_approx(0.0, 0.001)
	)
	assert_bool(_rendered(id)).override_failure_message("%s wall is still rendered" % id).is_false()
	var mesh: MeshInstance3D = _wall_mesh(id)
	assert_bool(mesh != null).is_true()
	if mesh != null:
		(
			assert_bool(mesh.visible)
			. override_failure_message("%s wall node is visible" % id)
			. is_false()
		)


func _assert_shown(id: StringName) -> void:
	(
		assert_bool(_hidden_target(id))
		. override_failure_message("%s wall: target is hidden" % id)
		. is_false()
	)
	(
		assert_float(_alpha(id))
		. override_failure_message("%s wall: alpha is not 1" % id)
		. is_equal_approx(1.0, 0.001)
	)
	assert_bool(_rendered(id)).override_failure_message("%s wall is not rendered" % id).is_true()
	var mesh: MeshInstance3D = _wall_mesh(id)
	assert_bool(mesh != null).is_true()
	if mesh != null:
		assert_bool(mesh.visible).override_failure_message("%s wall node is hidden" % id).is_true()
		assert_float(mesh.transparency).is_equal_approx(0.0, 0.001)


func _fade_s() -> float:
	return OrbitApi.setting("wall_fade_time_s")


# --- AC 17: the poses ---


func test_ac17_the_back_wall_is_hidden_behind_its_plane_at_every_elevation_for_every_tank() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		for elevation: float in [-10.0, 30.0, 60.0]:
			Cam.pose(_room, 180.0, elevation)
			_assert_behind(BACK)
			_assert_hidden(BACK)
			_assert_shown(LEFT)


func test_ac17_the_back_wall_is_fully_visible_in_front_of_its_plane() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		for pose: Array in [[0.0, 5.0], [0.0, 60.0], [90.0, 10.0], [315.0, 30.0]]:
			Cam.pose(_room, pose[0], pose[1])
			_assert_in_front(BACK)
			_assert_shown(BACK)


func test_ac17_the_default_view_shows_both_walls() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		_assert_shown(BACK)
		_assert_shown(LEFT)


func test_ac17_the_medium_tank_hides_the_left_wall_at_270_degrees_and_minus_5_degrees() -> void:
	if not await _open(Table.MEDIUM):
		return
	Cam.pose(_room, 270.0, -5.0)
	_assert_behind(LEFT)
	_assert_hidden(LEFT)
	_assert_shown(BACK)


func test_ac17_the_large_tank_hides_the_left_wall_at_270_degrees_and_10_degrees() -> void:
	if not await _open(Table.LARGE):
		return
	Cam.pose(_room, 270.0, 10.0)
	_assert_behind(LEFT)
	_assert_hidden(LEFT)
	_assert_shown(BACK)


func test_ac17_the_small_tank_never_gets_behind_the_left_wall_so_it_stays_visible() -> void:
	if not await _open(Table.SMALL):
		return
	for elevation: float in [-10.0, 5.0, 30.0]:
		Cam.pose(_room, 270.0, elevation)
		_assert_in_front(LEFT)
		_assert_shown(LEFT)


func test_ac17_the_left_wall_is_fully_visible_in_front_of_its_plane() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		for pose: Array in [[0.0, 5.0], [90.0, 10.0], [180.0, 30.0], [45.0, 20.0]]:
			Cam.pose(_room, pose[0], pose[1])
			_assert_in_front(LEFT)
			_assert_shown(LEFT)


func test_ac17_the_wall_state_does_not_depend_on_the_camera_being_above_the_wall_top() -> void:
	if not await _open(Table.LARGE):
		return
	# At 60 degrees the camera is far above the wall top and still behind the plane.
	Cam.pose(_room, 180.0, 60.0)
	assert_float(_camera.global_position.y).is_greater(1.5)
	_assert_behind(BACK)
	_assert_hidden(BACK)


# --- AC 18: back in front, independence, the top view ---


func test_ac18_the_back_wall_returns_when_the_camera_comes_back_in_front() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		Cam.pose(_room, 180.0, 30.0)
		_assert_hidden(BACK)
		Cam.pose(_room, 0.0, 5.0)
		_assert_in_front(BACK)
		_assert_shown(BACK)


func test_ac18_the_left_wall_returns_when_the_camera_comes_back_in_front() -> void:
	if not await _open(Table.LARGE):
		return
	Cam.pose(_room, 270.0, 10.0)
	_assert_hidden(LEFT)
	Cam.pose(_room, 0.0, 5.0)
	_assert_in_front(LEFT)
	_assert_shown(LEFT)


func test_ac18_the_walls_are_independent() -> void:
	if not await _open(Table.LARGE):
		return
	Cam.pose(_room, 180.0, 10.0)
	_assert_hidden(BACK)
	_assert_shown(LEFT)
	Cam.pose(_room, 270.0, 10.0)
	_assert_shown(BACK)
	_assert_hidden(LEFT)
	Cam.pose(_room, 225.0, 10.0)
	_assert_behind(BACK)
	_assert_behind(LEFT)
	_assert_hidden(BACK)
	_assert_hidden(LEFT)
	Cam.pose(_room, 0.0, 5.0)
	_assert_shown(BACK)
	_assert_shown(LEFT)


func test_ac18_at_85_degrees_both_walls_are_visible_from_every_side() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		for azimuth: float in [0.0, 90.0, 180.0, 225.0, 270.0, 315.0]:
			Cam.pose(_room, azimuth, 85.0)
			_assert_in_front(BACK)
			_assert_in_front(LEFT)
			_assert_shown(BACK)
			_assert_shown(LEFT)


func test_ac18_orbiting_all_the_way_round_hides_and_shows_each_wall_in_turn() -> void:
	if not await _open(Table.LARGE):
		return
	var seen_back_hidden: bool = false
	var seen_left_hidden: bool = false
	for turn: int in 25:
		Cam.pose(_room, turn * 15.0, 10.0)
		var back_hidden: bool = _plane_distance(BACK) < -HALF_BAND_M
		var left_hidden: bool = _plane_distance(LEFT) < -HALF_BAND_M
		seen_back_hidden = seen_back_hidden or back_hidden
		seen_left_hidden = seen_left_hidden or left_hidden
		if back_hidden or _plane_distance(BACK) > HALF_BAND_M:
			assert_bool(_rendered(BACK)).is_equal(not back_hidden)
		if left_hidden or _plane_distance(LEFT) > HALF_BAND_M:
			assert_bool(_rendered(LEFT)).is_equal(not left_hidden)
	assert_bool(seen_back_hidden).is_true()
	assert_bool(seen_left_hidden).is_true()


# --- the fade ---


func test_the_wall_fades_out_linearly_and_is_not_rendered_after_the_fade_time() -> void:
	if not await _open(Table.MEDIUM):
		return
	Cam.set_orbit(_camera, 180.0, 30.0, true)
	var fade: float = _fade_s()
	Cam.step_walls(_room, Cam.FRAME_S)
	assert_bool(_hidden_target(BACK)).is_true()
	assert_float(_alpha(BACK)).is_equal_approx(1.0 - Cam.FRAME_S / fade, 0.01)
	assert_bool(_rendered(BACK)).is_true()
	assert_float(_wall_mesh(BACK).transparency).is_equal_approx(1.0 - _alpha(BACK), 0.01)
	Cam.step_walls(_room, fade / 2.0 - Cam.FRAME_S)
	assert_float(_alpha(BACK)).is_equal_approx(0.5, 0.02)
	Cam.step_walls(_room, fade / 2.0 + 0.05)
	assert_float(_alpha(BACK)).is_equal_approx(0.0, 0.0001)
	assert_bool(_rendered(BACK)).is_false()


func test_the_wall_fades_in_linearly_when_the_camera_comes_back() -> void:
	if not await _open(Table.MEDIUM):
		return
	Cam.pose(_room, 180.0, 30.0)
	_assert_hidden(BACK)
	Cam.set_orbit(_camera, 0.0, 5.0, true)
	var fade: float = _fade_s()
	Cam.step_walls(_room, Cam.FRAME_S)
	assert_bool(_hidden_target(BACK)).is_false()
	assert_float(_alpha(BACK)).is_equal_approx(Cam.FRAME_S / fade, 0.01)
	assert_bool(_rendered(BACK)).is_true()
	Cam.step_walls(_room, fade)
	_assert_shown(BACK)


func test_a_fade_time_larger_than_the_frame_time_never_jumps_the_alpha() -> void:
	if not await _open(Table.MEDIUM):
		return
	Cam.set_orbit(_camera, 180.0, 30.0, true)
	var last: float = _alpha(BACK)
	for index: int in 30:
		Cam.step_walls(_room, Cam.FRAME_S)
		assert_float(last - _alpha(BACK)).is_less_equal(Cam.FRAME_S / _fade_s() + 0.0001)
		assert_float(_alpha(BACK)).is_greater_equal(0.0)
		last = _alpha(BACK)


# --- AC 19: no flicker ---


func _positions_changes(positions: Array[Vector3], id: StringName) -> int:
	var changes: int = 0
	var last: bool = _hidden_target(id)
	for position: Vector3 in positions:
		_walls.call("step", Cam.FRAME_S, position)
		var now: bool = _hidden_target(id)
		if now != last:
			changes += 1
		last = now
	return changes


func test_ac19_a_jitter_of_0_02_m_around_the_back_plane_changes_the_state_at_most_once() -> void:
	if not await _open(Table.MEDIUM):
		return
	var positions: Array[Vector3] = []
	for index: int in 40:
		var z: float = Cam.BACK_PLANE_Z_M + (0.02 if index % 2 == 0 else -0.02)
		positions.append(Vector3(0.0, 1.2, z))
	assert_int(_positions_changes(positions, BACK)).is_less_equal(1)
	assert_float(_alpha(BACK)).is_equal_approx(1.0, 0.0001)


func test_ac19_a_jitter_around_the_left_plane_changes_the_state_at_most_once() -> void:
	if not await _open(Table.LARGE):
		return
	var positions: Array[Vector3] = []
	for index: int in 40:
		var x: float = Cam.LEFT_PLANE_X_M + (0.02 if index % 2 == 0 else -0.02)
		positions.append(Vector3(x, 1.2, 0.5))
	assert_int(_positions_changes(positions, LEFT)).is_less_equal(1)


func test_ac19_the_hide_and_the_show_trigger_are_0_05_m_apart() -> void:
	if not await _open(Table.MEDIUM):
		return
	var plane: float = Cam.BACK_PLANE_Z_M
	_walls.call("step", Cam.FRAME_S, Vector3(0.0, 1.2, plane - 0.02))
	assert_bool(_hidden_target(BACK)).is_false()
	_walls.call("step", Cam.FRAME_S, Vector3(0.0, 1.2, plane - 0.03))
	assert_bool(_hidden_target(BACK)).is_true()
	_walls.call("step", Cam.FRAME_S, Vector3(0.0, 1.2, plane + 0.02))
	assert_bool(_hidden_target(BACK)).is_true()
	_walls.call("step", Cam.FRAME_S, Vector3(0.0, 1.2, plane + 0.03))
	assert_bool(_hidden_target(BACK)).is_false()


func test_ac19_a_decisive_crossing_and_a_jitter_on_top_changes_the_state_once_each_way() -> void:
	if not await _open(Table.MEDIUM):
		return
	var positions: Array[Vector3] = []
	for index: int in 30:
		var z: float = 0.2 - 0.0145 * index
		positions.append(Vector3(0.0, 1.2, z + (0.01 if index % 2 == 0 else -0.01)))
	for index: int in 30:
		var z: float = -0.235 + 0.0145 * index
		positions.append(Vector3(0.0, 1.2, z + (0.01 if index % 2 == 0 else -0.01)))
	assert_int(_positions_changes(positions, BACK)).is_equal(2)


func test_ac19_the_decision_uses_the_actual_camera_position_not_the_target() -> void:
	if not await _open(Table.MEDIUM):
		return
	# The target is behind the back wall at once, the damped camera needs a while to get there.
	Cam.set_orbit(_camera, 180.0, 5.0, false)
	var states: Array[bool] = []
	for index: int in 90:
		Cam.step(_camera, Cam.FRAME_S)
		_walls.call("step", Cam.FRAME_S, _camera.global_position)
		var behind: bool = _plane_distance(BACK) < -HALF_BAND_M
		var in_front: bool = _plane_distance(BACK) > HALF_BAND_M
		if behind:
			assert_bool(_hidden_target(BACK)).is_true()
		if in_front:
			assert_bool(_hidden_target(BACK)).is_false()
		states.append(_hidden_target(BACK))
	# After one frame the damped camera is still in front: the wall is still a shown wall.
	assert_bool(states[0]).is_false()
	assert_bool(states[states.size() - 1]).is_true()
	var changes: int = 0
	for index: int in range(1, states.size()):
		if states[index] != states[index - 1]:
			changes += 1
	assert_int(changes).is_equal(1)


func test_ac19_the_wall_node_follows_the_active_camera_by_itself() -> void:
	if not await _open(Table.MEDIUM):
		return
	_walls.set_process(true)
	Cam.set_orbit(_camera, 180.0, 30.0, true)
	for index: int in 40:
		await get_tree().process_frame
	_assert_hidden(BACK)


# --- AC 20: only the walls, and a tank change behind a wall ---


func _assert_everything_else_is_untouched() -> void:
	for node_name: String in ["Cabinet", "Tank", "Lamp"]:
		var node: Node3D = _room.get_node(node_name) as Node3D
		(
			assert_bool(node.is_visible_in_tree())
			. override_failure_message("%s is hidden" % node_name)
			. is_true()
		)
		for mesh: MeshInstance3D in Glb.mesh_instances(node):
			(
				assert_bool(mesh.visible)
				. override_failure_message("%s is hidden in %s" % [mesh.name, node_name])
				. is_true()
			)
			(
				assert_float(mesh.transparency)
				. override_failure_message("%s is faded in %s" % [mesh.name, node_name])
				. is_equal(0.0)
			)
	var floor_mesh: MeshInstance3D = Glb.find_mesh(_room, "Floor")
	assert_bool(floor_mesh != null).is_true()
	if floor_mesh != null:
		assert_bool(floor_mesh.is_visible_in_tree()).is_true()
		assert_float(floor_mesh.transparency).is_equal(0.0)


func test_ac20_with_both_walls_hidden_everything_else_is_visible_and_unfaded() -> void:
	if not await _open(Table.LARGE):
		return
	Cam.pose(_room, 225.0, 10.0)
	_assert_behind(BACK)
	_assert_behind(LEFT)
	_assert_hidden(BACK)
	_assert_hidden(LEFT)
	_assert_everything_else_is_untouched()


func test_ac20_every_pose_leaves_the_floor_cabinet_tank_and_lamp_alone() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		for azimuth: float in [0.0, 90.0, 180.0, 270.0]:
			Cam.pose(_room, azimuth, 10.0)
			_assert_everything_else_is_untouched()


func test_ac20_the_wall_rule_does_not_write_the_model() -> void:
	if not await _open(Table.LARGE):
		return
	var before: Dictionary = ModelState.snapshot(_model)
	Cam.pose(_room, 225.0, 10.0)
	Cam.pose(_room, 0.0, 5.0)
	assert_dict(ModelState.snapshot(_model)).is_equal(before)


func _change(id: StringName) -> void:
	assert_bool(_history.execute(Api.change_tank(_model, _catalog, id))).is_true()


## Steps camera and walls for `frames` frames; every frame the target must equal the state of the
## actual camera position outside the band, and the alpha may only move by the fade rate.
func _follow_and_check(frames: int) -> void:
	var rate: float = Cam.FRAME_S / _fade_s() + 0.0001
	for index: int in frames:
		var back_before: float = _alpha(BACK)
		var left_before: float = _alpha(LEFT)
		Cam.step(_camera, Cam.FRAME_S)
		_walls.call("step", Cam.FRAME_S, _camera.global_position)
		for id: StringName in [BACK, LEFT]:
			var distance: float = _plane_distance(id)
			if distance < -HALF_BAND_M:
				(
					assert_bool(_hidden_target(id))
					. override_failure_message("%s should be hidden on frame %s" % [id, index])
					. is_true()
				)
			elif distance > HALF_BAND_M:
				(
					assert_bool(_hidden_target(id))
					. override_failure_message("%s should be shown on frame %s" % [id, index])
					. is_false()
				)
		assert_float(absf(_alpha(BACK) - back_before)).is_less_equal(rate)
		assert_float(absf(_alpha(LEFT) - left_before)).is_less_equal(rate)


func test_ac20_a_tank_change_behind_the_back_wall_keeps_the_state_and_fades_by_the_rate_only(
) -> void:
	if not await _open(Table.MEDIUM):
		return
	Cam.pose(_room, 180.0, 30.0)
	_assert_hidden(BACK)
	_change(Table.LARGE)
	# Right after the change the target is what the actual camera position says; no reset.
	_walls.call("step", Cam.FRAME_S, _camera.global_position)
	assert_bool(_hidden_target(BACK)).is_true()
	assert_float(_alpha(BACK)).is_equal_approx(0.0, 0.0001)
	assert_bool(_hidden_target(LEFT)).is_false()
	assert_float(_alpha(LEFT)).is_equal_approx(1.0, 0.0001)
	_follow_and_check(150)
	_assert_behind(BACK)
	_assert_hidden(BACK)
	_assert_shown(LEFT)
	_assert_everything_else_is_untouched()


func test_ac20_a_tank_change_in_front_of_the_walls_keeps_them_fully_visible() -> void:
	if not await _open(Table.MEDIUM):
		return
	_change(Table.LARGE)
	_follow_and_check(150)
	_assert_shown(BACK)
	_assert_shown(LEFT)


func test_ac20_a_tank_change_behind_the_left_wall_follows_the_camera_that_eases_away() -> void:
	if not await _open(Table.LARGE):
		return
	Cam.pose(_room, 270.0, 10.0)
	_assert_hidden(LEFT)
	_change(Table.SMALL)
	_walls.call("step", Cam.FRAME_S, _camera.global_position)
	assert_bool(_hidden_target(LEFT)).is_true()
	_follow_and_check(150)
	# The small tank is framed closer, so the camera ends in front of the left plane.
	_assert_in_front(LEFT)
	_assert_shown(LEFT)


func test_ac20_a_tank_change_while_a_fade_is_running_does_not_restart_it() -> void:
	if not await _open(Table.MEDIUM):
		return
	Cam.set_orbit(_camera, 180.0, 30.0, true)
	Cam.step_walls(_room, 0.1)
	var halfway: float = _alpha(BACK)
	assert_float(halfway).is_between(0.2, 0.8)
	_change(Table.LARGE)
	_walls.call("step", 0.0, _camera.global_position)
	assert_float(_alpha(BACK)).is_equal_approx(halfway, 0.0001)
	_follow_and_check(30)
