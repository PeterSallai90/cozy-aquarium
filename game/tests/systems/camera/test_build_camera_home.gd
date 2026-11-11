# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #26 criteria 7, 8 and 9 (owner: developer): the Home key sets the targets to the default view
## (azimuth = the nearest multiple of 360, elevation 5 degrees, the default distance of the tank
## and the water-volume centre) and the camera eases there with the normal damping, without
## overshoot. Damping time 0 applies Home, zoom, pan and collision at once. Each test runs on all
## three tanks unless it says otherwise. Time comes from BuildCamera.step with fixed frame times.

const Cz := preload("res://tests/helpers/camera_zoom_rig.gd")
const Cam := preload("res://tests/helpers/camera_rig.gd")
const Api := preload("res://tests/helpers/late_api.gd")
const Room := preload("res://tests/helpers/room_rig.gd")
const Table := preload("res://tests/helpers/tank_table.gd")
const OrbitApi := preload("res://tests/helpers/orbit_api.gd")

var _rig: Dictionary = {}
var _viewport: SubViewport = null
var _camera: Camera3D = null
var _default: float = 0.0
var _home_pivot: Vector3 = Vector3.ZERO
var _start_position: Vector3 = Vector3.ZERO


func _open(id: StringName, damping_s: float = -1.0) -> bool:
	_rig = await Cz.open_tank(self, id)
	_viewport = _rig["viewport"]
	_camera = _rig["camera"]
	_default = _rig["default_distance"]
	_home_pivot = _rig["home_pivot"]
	if not _rig["ok"]:
		return false
	_start_position = _camera.global_position
	if damping_s >= 0.0:
		var copy: Resource = _camera.get("settings").duplicate()
		copy.set("damping_time_s", damping_s)
		_camera.set("settings", copy)
	return true


## Orbits, zooms and pans away from the default view; the camera is at the new pose at once.
func _away(azimuth: float = 100.0, elevation: float = 40.0) -> void:
	var pivot: Vector3 = _home_pivot + Vector3(0.06, 0.04, -0.03)
	Cz.pose(_camera, azimuth, elevation, _default * 0.7, pivot)


func _start_elevation() -> float:
	return Cz.default_start_elevation()


## Fails with the first problem found when a frame did not ease without overshoot.
func _ease_problem(old: Array[float], new: Array[float], goal: Array[float], dt: float) -> String:
	var factor: float = OrbitApi.damp_factor(dt, OrbitApi.setting("damping_time_s"))
	var names: Array[String] = ["azimuth", "elevation", "distance", "pivot x", "pivot y", "pivot z"]
	for index: int in names.size():
		var error: float = goal[index] - old[index]
		var left: float = goal[index] - new[index]
		var tolerance: float = Cz.ANGLE_DEG if index < 2 else Cz.LENGTH_M
		if left * error < -0.000000001:
			return (
				"%s overshoots: %s -> %s, target %s"
				% [names[index], old[index], new[index], goal[index]]
			)
		if absf(new[index] - old[index]) > factor * absf(error) + tolerance:
			return "%s moves %s of an error of %s" % [names[index], new[index] - old[index], error]
	return ""


func _eased_values() -> Array[float]:
	var pivot: Vector3 = Cam.pivot(_camera)
	return [Cam.az(_camera), Cam.el(_camera), Cam.dist(_camera), pivot.x, pivot.y, pivot.z]


func _target_values() -> Array[float]:
	var pivot: Vector3 = Cam.t_pivot(_camera)
	return [Cam.t_az(_camera), Cam.t_el(_camera), Cam.t_dist(_camera), pivot.x, pivot.y, pivot.z]


# --- AC 7: the targets and the easing ---


func test_ac07_home_sets_the_targets_to_the_default_view() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		_away()
		Cz.home_key(_viewport)
		assert_float(Cam.t_az(_camera)).is_equal_approx(0.0, Cz.ANGLE_DEG)
		assert_float(Cam.t_el(_camera)).is_equal_approx(_start_elevation(), Cz.ANGLE_DEG)
		assert_float(Cam.t_dist(_camera)).is_equal_approx(_default, Cz.LENGTH_M)
		assert_vector(Cam.t_pivot(_camera)).is_equal_approx(_home_pivot, Vector3.ONE * Cz.LENGTH_M)


func test_ac07_the_default_pivot_is_the_water_volume_centre() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		var centre: Vector3 = (_rig["room"].get_node("Tank/WaterVolume") as Node3D).global_position
		_away()
		Cz.home_key(_viewport)
		assert_vector(Cam.t_pivot(_camera)).is_equal_approx(centre, Vector3.ONE * Cz.LENGTH_M)


func test_ac07_home_does_not_move_the_camera_at_once() -> void:
	if not await _open(Table.MEDIUM):
		return
	_away()
	var position: Vector3 = _camera.global_position
	Cz.home_key(_viewport)
	assert_vector(_camera.global_position).is_equal_approx(position, Vector3.ONE * 0.000001)
	assert_float(Cam.az(_camera)).is_equal_approx(100.0, Cz.ANGLE_DEG)


func test_ac07_every_frame_moves_toward_the_targets_without_overshoot() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		_away()
		Cz.home_key(_viewport)
		var problems: PackedStringArray = PackedStringArray()
		for frame: int in 240:
			var old: Array[float] = _eased_values()
			Cam.step(_camera, Cz.FRAME_S)
			var problem: String = _ease_problem(old, _eased_values(), _target_values(), Cz.FRAME_S)
			if not problem.is_empty():
				problems.append("%s frame %d: %s" % [id, frame, problem])
		assert_array(problems).override_failure_message(Cz.summary(problems)).is_empty()


func test_ac07_a_long_frame_also_eases_without_overshoot() -> void:
	if not await _open(Table.LARGE):
		return
	_away()
	Cz.home_key(_viewport)
	var problems: PackedStringArray = PackedStringArray()
	for frame: int in 12:
		var old: Array[float] = _eased_values()
		Cam.step(_camera, 0.1, 0.1)
		var problem: String = _ease_problem(old, _eased_values(), _target_values(), 0.1)
		if not problem.is_empty():
			problems.append("frame %d: %s" % [frame, problem])
	assert_array(problems).override_failure_message(Cz.summary(problems)).is_empty()


func test_ac07_after_settling_the_pose_equals_the_default_view() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		_away()
		Cz.home_key(_viewport)
		Cam.settle(_camera)
		assert_float(Cam.az(_camera)).is_equal_approx(0.0, Cz.ANGLE_DEG)
		assert_float(Cam.el(_camera)).is_equal_approx(_start_elevation(), Cz.ANGLE_DEG)
		assert_float(Cam.dist(_camera)).is_equal_approx(_default, Cz.LENGTH_M)
		assert_vector(Cam.pivot(_camera)).is_equal_approx(_home_pivot, Vector3.ONE * Cz.LENGTH_M)


func test_ac07_after_settling_the_framing_of_the_default_view_is_restored() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		_away()
		Cz.home_key(_viewport)
		Cam.settle(_camera)
		assert_vector(_camera.global_position).is_equal_approx(_start_position, Vector3.ONE * 0.002)
		var expected: Vector3 = Api.camera_position(_home_pivot, _default, _start_elevation())
		assert_vector(_camera.global_position).is_equal_approx(expected, Vector3.ONE * 0.002)
		assert_array(Cam.basis_failures(_camera, _home_pivot)).is_empty()


func test_ac07_home_works_from_the_zoom_and_pan_limits() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		Cz.wheel(_viewport, true, Cz.HUGE)
		Cz.pan(_viewport, Vector2(-Cz.HUGE, Cz.HUGE))
		Cam.set_orbit(_camera, -300.0, 85.0, false)
		Cam.step(_camera, 0.3)
		Cz.home_key(_viewport)
		Cam.settle(_camera)
		assert_float(Cam.dist(_camera)).is_equal_approx(_default, Cz.LENGTH_M)
		assert_vector(Cam.pivot(_camera)).is_equal_approx(_home_pivot, Vector3.ONE * Cz.LENGTH_M)
		assert_float(Cam.el(_camera)).is_equal_approx(_start_elevation(), Cz.ANGLE_DEG)
		assert_float(Cam.az(_camera)).is_equal_approx(Cam.t_az(_camera), Cz.ANGLE_DEG)


func test_ac07_wheel_notches_during_the_easing_accumulate_on_the_current_target() -> void:
	if not await _open(Table.MEDIUM):
		return
	_away()
	Cz.home_key(_viewport)
	Cam.step(_camera, 0.05)
	Cz.wheel(_viewport, true)
	Cz.wheel(_viewport, true)
	var step: float = Cz.setting("zoom_step_factor")
	assert_float(Cam.t_dist(_camera)).is_equal_approx(_default * step * step, Cz.LENGTH_M)


func test_ac07_a_held_home_key_does_not_repeat() -> void:
	if not await _open(Table.MEDIUM):
		return
	_away()
	Cz.home_key(_viewport)
	Cam.settle(_camera)
	Cz.wheel(_viewport, true)
	Cam.key(_viewport, KEY_HOME, true, true)
	assert_float(Cam.t_dist(_camera)).is_equal_approx(
		_default * Cz.setting("zoom_step_factor"), Cz.LENGTH_M
	)


func test_ac07_home_during_a_tank_change_easing_sets_the_same_targets() -> void:
	var model: AquariumModel = Room.model_with(Table.MEDIUM)
	var history: CommandHistory = CommandHistory.new()
	var catalog: RefCounted = Room.default_catalog()
	var rig: Dictionary = await Cz.open(self, model, Cam.SIZE_16_9, Table.MEDIUM)
	if not rig["ok"]:
		return
	var camera: Camera3D = rig["camera"]
	var reference: Dictionary = await Cz.open_tank(self, Table.LARGE)
	Cam.set_orbit(camera, 100.0, 40.0, true)
	assert_bool(history.execute(Api.change_tank(model, catalog, Table.LARGE))).is_true()
	Cam.step(camera, 0.05)
	Cz.home_key(rig["viewport"])
	assert_float(Cam.t_az(camera)).is_equal_approx(0.0, Cz.ANGLE_DEG)
	assert_float(Cam.t_dist(camera)).is_equal_approx(reference["default_distance"], Cz.LENGTH_M)
	assert_vector(Cam.t_pivot(camera)).is_equal_approx(
		reference["home_pivot"], Vector3.ONE * Cz.LENGTH_M
	)
	Cam.settle(camera)
	assert_float(Cam.dist(camera)).is_equal_approx(reference["default_distance"], Cz.LENGTH_M)


# --- AC 8: the azimuth ---


func test_ac08_an_azimuth_of_750_goes_to_720_with_30_degrees_of_travel() -> void:
	if not await _open(Table.MEDIUM):
		return
	Cz.pose(_camera, 750.0, 30.0, _default, _home_pivot)
	Cz.home_key(_viewport)
	assert_float(Cam.t_az(_camera)).is_equal_approx(720.0, Cz.ANGLE_DEG)
	var lowest: float = INF
	for frame: int in 120:
		Cam.step(_camera, Cz.FRAME_S)
		lowest = minf(lowest, Cam.az(_camera))
	assert_float(lowest).is_greater_equal(720.0 - Cz.ANGLE_DEG)
	assert_float(Cam.az(_camera)).is_equal_approx(720.0, Cz.ANGLE_DEG)


func test_ac08_an_exact_tie_goes_to_the_higher_multiple() -> void:
	if not await _open(Table.MEDIUM):
		return
	Cz.pose(_camera, 540.0, 30.0, _default, _home_pivot)
	Cz.home_key(_viewport)
	assert_float(Cam.t_az(_camera)).is_equal_approx(720.0, Cz.ANGLE_DEG)
	Cz.pose(_camera, 180.0, 30.0, _default, _home_pivot)
	Cz.home_key(_viewport)
	assert_float(Cam.t_az(_camera)).is_equal_approx(360.0, Cz.ANGLE_DEG)


func test_ac08_the_stored_azimuth_is_not_wrapped() -> void:
	if not await _open(Table.MEDIUM):
		return
	for pair: Array in [[1085.0, 1080.0], [-725.0, -720.0], [-100.0, 0.0], [359.0, 360.0]]:
		Cz.pose(_camera, pair[0], 30.0, _default, _home_pivot)
		Cz.home_key(_viewport)
		assert_float(Cam.t_az(_camera)).is_equal_approx(pair[1], Cz.ANGLE_DEG)


func test_ac08_the_azimuth_after_a_long_drag_goes_to_the_nearest_turn_on_every_tank() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		Cam.drag(_viewport, Vector2(-2000.0, 0.0))
		var turned: float = Cam.t_az(_camera)
		assert_float(absf(turned)).is_greater(360.0)
		Cz.home_key(_viewport)
		assert_float(Cam.t_az(_camera)).is_equal_approx(
			360.0 * floorf(turned / 360.0 + 0.5), Cz.ANGLE_DEG
		)


# --- AC 9: nothing to do, and damping time 0 ---


func test_ac09_home_in_the_default_view_changes_nothing() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		var before: Array[float] = _target_values()
		Cz.home_key(_viewport)
		assert_array(_target_values()).is_equal(before)
		Cam.step(_camera, 0.5)
		assert_array(_eased_values()).is_equal(before)
		assert_vector(_camera.global_position).is_equal_approx(
			_start_position, Vector3.ONE * 0.000001
		)


func test_ac09_with_damping_time_zero_home_is_instant() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id, 0.0):
			return
		_away()
		Cz.home_key(_viewport)
		Cam.step(_camera, Cz.FRAME_S)
		assert_float(Cam.az(_camera)).is_equal_approx(0.0, Cz.ANGLE_DEG)
		assert_float(Cam.el(_camera)).is_equal_approx(_start_elevation(), Cz.ANGLE_DEG)
		assert_float(Cam.dist(_camera)).is_equal_approx(_default, Cz.LENGTH_M)
		assert_vector(Cam.pivot(_camera)).is_equal_approx(_home_pivot, Vector3.ONE * Cz.LENGTH_M)


func test_ac09_with_damping_time_zero_zoom_and_pan_are_instant() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id, 0.0):
			return
		Cz.wheel(_viewport, true)
		Cam.step(_camera, Cz.FRAME_S)
		assert_float(Cam.dist(_camera)).is_equal_approx(
			_default * Cz.setting("zoom_step_factor"), Cz.LENGTH_M
		)
		Cz.pan(_viewport, Vector2(30.0, 10.0))
		Cam.step(_camera, Cz.FRAME_S)
		assert_vector(Cam.pivot(_camera)).is_equal_approx(
			Cam.t_pivot(_camera), Vector3.ONE * Cz.LENGTH_M
		)


func test_ac09_with_damping_time_zero_the_collision_rule_still_holds() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id, 0.0):
			return
		var room: Node3D = _rig["room"]
		var boxes: Array[AABB] = Cz.solids(room, id)
		var pan: AABB = Cz.pan_box(id, Cz.stand_z(room))
		var failures: PackedStringArray = PackedStringArray()
		for corner_x: bool in [false, true]:
			for azimuth: float in [90.0, 270.0]:
				var pivot: Vector3 = Cz.box_corner(pan, corner_x, false, false)
				Cz.pose(_camera, azimuth, -90.0, Cz.zoom_in_distance(_default), pivot)
				Cam.step(_camera, Cz.FRAME_S)
				failures.append_array(Cz.pose_failures(_camera, boxes, "%s az %s" % [id, azimuth]))
				Cz.wheel(_viewport, true, Cz.HUGE)
				Cam.step(_camera, Cz.FRAME_S)
				failures.append_array(Cz.pose_failures(_camera, boxes, "%s zoomed" % id))
		assert_array(failures).override_failure_message(Cz.summary(failures)).is_empty()
