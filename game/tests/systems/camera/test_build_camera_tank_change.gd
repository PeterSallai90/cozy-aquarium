# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #25 criteria 8 and 20 (camera part) (owner: developer): when the model emits tank_changed (the
## chooser, undo, redo) or model_reset (load) the build camera keeps its azimuth, re-clamps the
## elevation to the limits of the new tank, takes the new default framing distance and the new
## water-volume centre as targets, and eases there with the same damping: no jump, no reset. The
## camera height stays at or above the cabinet top on every frame of the ease. Time comes from
## BuildCamera.step with fixed frame times; the reference values come from a second room that
## shows the new tank from the start.

const Api := preload("res://tests/helpers/late_api.gd")
const Room := preload("res://tests/helpers/room_rig.gd")
const Cam := preload("res://tests/helpers/camera_rig.gd")
const Table := preload("res://tests/helpers/tank_table.gd")
const OrbitApi := preload("res://tests/helpers/orbit_api.gd")

var _model: AquariumModel = null
var _history: CommandHistory = null
var _catalog: RefCounted = null
var _viewport: SubViewport = null
var _room: Node3D = null
var _camera: Camera3D = null


func before_test() -> void:
	_history = CommandHistory.new()
	_catalog = Room.default_catalog()


func _open(id: StringName) -> bool:
	_model = Room.model_with(id)
	var rig: Dictionary = await Cam.open(self, _model)
	_viewport = rig["viewport"]
	_room = rig["room"]
	_camera = Cam.camera_of(_room)
	(
		assert_bool(_camera != null)
		. override_failure_message("the room has no BuildCamera child (Camera3D)")
		. is_true()
	)
	return _camera != null


func _change(id: StringName) -> void:
	assert_bool(_history.execute(Api.change_tank(_model, _catalog, id))).is_true()


## The default framing of a tank: the distance and the pivot of a room that starts with it.
func _reference(id: StringName) -> Dictionary:
	var rig: Dictionary = await Cam.open(self, Room.model_with(id))
	var camera: Camera3D = Cam.camera_of(rig["room"])
	if camera == null:
		return {"distance": -1.0, "pivot": Vector3.ZERO}
	return {"distance": Cam.dist(camera), "pivot": Cam.pivot(camera)}


func _water_centre() -> Vector3:
	return (_room.get_node("Tank/WaterVolume") as Node3D).global_position


# --- AC 8: the targets right after the change ---


func test_ac08_the_targets_change_at_once_and_the_view_does_not_jump() -> void:
	if not await _open(Table.MEDIUM):
		return
	Cam.set_orbit(_camera, 130.0, Cam.min_el(_camera, Table.MEDIUM), true)
	var az: float = Cam.az(_camera)
	var el: float = Cam.el(_camera)
	var dist: float = Cam.dist(_camera)
	var pivot: Vector3 = Cam.pivot(_camera)
	var position: Vector3 = _camera.global_position
	var large: Dictionary = await _reference(Table.LARGE)
	_change(Table.LARGE)
	assert_float(Cam.t_az(_camera)).is_equal_approx(130.0, Cam.ANGLE_TOLERANCE_DEG)
	assert_float(Cam.t_dist(_camera)).is_equal_approx(large["distance"], Cam.LENGTH_TOLERANCE_M)
	assert_vector(Cam.t_pivot(_camera)).is_equal_approx(large["pivot"], Vector3.ONE * 0.001)
	assert_vector(Cam.t_pivot(_camera)).is_equal_approx(_water_centre(), Vector3.ONE * 0.001)
	assert_float(Cam.t_el(_camera)).is_equal_approx(
		Cam.min_el(_camera, Table.LARGE), Cam.ANGLE_TOLERANCE_DEG
	)
	# The view itself has not moved yet.
	assert_float(Cam.az(_camera)).is_equal_approx(az, Cam.ANGLE_TOLERANCE_DEG)
	assert_float(Cam.el(_camera)).is_equal_approx(el, Cam.ANGLE_TOLERANCE_DEG)
	assert_float(Cam.dist(_camera)).is_equal_approx(dist, Cam.LENGTH_TOLERANCE_M)
	assert_vector(Cam.pivot(_camera)).is_equal_approx(pivot, Vector3.ONE * 0.001)
	assert_vector(_camera.global_position).is_equal_approx(position, Vector3.ONE * 0.001)


func test_ac08_the_elevation_is_re_clamped_to_the_limit_of_the_new_tank() -> void:
	if not await _open(Table.MEDIUM):
		return
	# The medium tank allows -10 degrees; the large one only about -9.979 at its distance.
	Cam.set_orbit(_camera, 0.0, -10.0, true)
	assert_float(Cam.t_el(_camera)).is_equal_approx(-10.0, Cam.ANGLE_TOLERANCE_DEG)
	_change(Table.LARGE)
	var lowest: float = Cam.min_el(_camera, Table.LARGE)
	assert_float(lowest).is_equal_approx(-9.979, Cam.ANGLE_TOLERANCE_DEG)
	assert_float(Cam.t_el(_camera)).is_equal_approx(lowest, Cam.ANGLE_TOLERANCE_DEG)
	Cam.settle(_camera)
	assert_float(Cam.el(_camera)).is_equal_approx(lowest, Cam.ANGLE_TOLERANCE_DEG)


func test_ac08_an_elevation_that_is_still_allowed_is_kept_and_not_reset() -> void:
	if not await _open(Table.LARGE):
		return
	Cam.set_orbit(_camera, 200.0, 40.0, true)
	_change(Table.SMALL)
	assert_float(Cam.t_el(_camera)).is_equal_approx(40.0, Cam.ANGLE_TOLERANCE_DEG)
	assert_float(Cam.t_az(_camera)).is_equal_approx(200.0, Cam.ANGLE_TOLERANCE_DEG)
	Cam.settle(_camera)
	assert_float(Cam.el(_camera)).is_equal_approx(40.0, Cam.ANGLE_TOLERANCE_DEG)
	assert_float(Cam.az(_camera)).is_equal_approx(200.0, Cam.ANGLE_TOLERANCE_DEG)


func test_ac08_the_unwrapped_azimuth_is_kept_exactly() -> void:
	if not await _open(Table.MEDIUM):
		return
	Cam.drag(_viewport, Vector2(-4000.0, 0.0))
	var start: float = Cam.t_az(_camera)
	_change(Table.SMALL)
	assert_float(Cam.t_az(_camera)).is_equal_approx(start, Cam.ANGLE_TOLERANCE_DEG)


func test_ac08_the_pivot_follows_the_water_centre_of_every_tank() -> void:
	if not await _open(Table.MEDIUM):
		return
	for id: StringName in [Table.LARGE, Table.SMALL, Table.MEDIUM]:
		_change(id)
		assert_vector(Cam.t_pivot(_camera)).is_equal_approx(_water_centre(), Vector3.ONE * 0.001)
		Cam.settle(_camera)
		assert_vector(Cam.pivot(_camera)).is_equal_approx(_water_centre(), Vector3.ONE * 0.001)


# --- AC 8: the ease ---


func test_ac08_the_camera_converges_to_the_targets_with_the_azimuth_unchanged() -> void:
	if not await _open(Table.MEDIUM):
		return
	Cam.set_orbit(_camera, 130.0, 25.0, true)
	var large: Dictionary = await _reference(Table.LARGE)
	_change(Table.LARGE)
	Cam.settle(_camera)
	assert_float(Cam.az(_camera)).is_equal_approx(130.0, Cam.ANGLE_TOLERANCE_DEG)
	assert_float(Cam.el(_camera)).is_equal_approx(25.0, Cam.ANGLE_TOLERANCE_DEG)
	assert_float(Cam.dist(_camera)).is_equal_approx(large["distance"], Cam.LENGTH_TOLERANCE_M)
	assert_vector(Cam.pivot(_camera)).is_equal_approx(large["pivot"], Vector3.ONE * 0.001)
	var expected: Vector3 = (
		Cam.pivot(_camera) + OrbitApi.offset(130.0, 25.0, large["distance"] as float)
	)
	assert_vector(_camera.global_position).is_equal_approx(expected, Vector3.ONE * 0.002)


func test_ac08_distance_and_pivot_ease_with_the_same_damping_as_the_orbit() -> void:
	if not await _open(Table.MEDIUM):
		return
	var start_dist: float = Cam.dist(_camera)
	var start_pivot: Vector3 = Cam.pivot(_camera)
	_change(Table.LARGE)
	var end_dist: float = Cam.t_dist(_camera)
	var end_pivot: Vector3 = Cam.t_pivot(_camera)
	Cam.step(_camera, Cam.FRAME_S)
	var factor: float = OrbitApi.damp_factor(Cam.FRAME_S, OrbitApi.setting("damping_time_s"))
	assert_float(factor).is_between(0.05, 0.95)
	var dist_fraction: float = (Cam.dist(_camera) - start_dist) / (end_dist - start_dist)
	assert_float(dist_fraction).is_equal_approx(factor, 0.02)
	var moved: Vector3 = Cam.pivot(_camera) - start_pivot
	var gap: Vector3 = end_pivot - start_pivot
	assert_float(moved.length() / gap.length()).is_equal_approx(factor, 0.02)
	assert_float(moved.normalized().dot(gap.normalized())).is_greater(0.999)


func test_ac08_the_azimuth_does_not_move_while_the_tank_change_eases() -> void:
	if not await _open(Table.MEDIUM):
		return
	Cam.set_orbit(_camera, 75.0, 12.0, true)
	_change(Table.SMALL)
	for index: int in 90:
		Cam.step(_camera, Cam.FRAME_S)
		assert_float(Cam.az(_camera)).is_equal_approx(75.0, Cam.ANGLE_TOLERANCE_DEG)


func test_ac08_the_camera_never_goes_below_the_cabinet_top_while_easing_between_tanks() -> void:
	for from_id: StringName in Table.IDS:
		for to_id: StringName in Table.IDS:
			if from_id == to_id:
				continue
			if not await _open(from_id):
				return
			Cam.set_orbit(_camera, 20.0, -90.0, true)
			Cam.drag(_viewport, Vector2(0.0, 1000000.0))
			Cam.settle(_camera)
			_change(to_id)
			for index: int in 150:
				Cam.step(_camera, Cam.FRAME_S)
				(
					assert_float(_camera.global_position.y)
					. override_failure_message(
						(
							"%s to %s: height %s on frame %s"
							% [from_id, to_id, _camera.global_position.y, index]
						)
					)
					. is_greater_equal(Cam.CABINET_TOP_M - Cam.LENGTH_TOLERANCE_M)
				)
			assert_float(Cam.el(_camera)).is_equal_approx(
				Cam.min_el(_camera, to_id), Cam.ANGLE_TOLERANCE_DEG
			)


func test_ac08_a_change_while_the_previous_ease_is_still_running_goes_to_the_latest_tank() -> void:
	if not await _open(Table.MEDIUM):
		return
	var small: Dictionary = await _reference(Table.SMALL)
	_change(Table.LARGE)
	Cam.step(_camera, 0.05)
	_change(Table.SMALL)
	assert_float(Cam.t_dist(_camera)).is_equal_approx(small["distance"], Cam.LENGTH_TOLERANCE_M)
	Cam.settle(_camera)
	assert_float(Cam.dist(_camera)).is_equal_approx(small["distance"], Cam.LENGTH_TOLERANCE_M)
	assert_vector(Cam.pivot(_camera)).is_equal_approx(small["pivot"], Vector3.ONE * 0.001)


# --- AC 8: any cause ---


func test_ac08_undo_and_redo_move_the_targets_like_the_chooser() -> void:
	if not await _open(Table.MEDIUM):
		return
	var medium: Dictionary = await _reference(Table.MEDIUM)
	var large: Dictionary = await _reference(Table.LARGE)
	Cam.set_orbit(_camera, 300.0, 15.0, true)
	_change(Table.LARGE)
	Cam.settle(_camera)
	assert_float(Cam.dist(_camera)).is_equal_approx(large["distance"], Cam.LENGTH_TOLERANCE_M)
	assert_bool(_history.undo()).is_true()
	assert_float(Cam.t_az(_camera)).is_equal_approx(300.0, Cam.ANGLE_TOLERANCE_DEG)
	assert_float(Cam.t_dist(_camera)).is_equal_approx(medium["distance"], Cam.LENGTH_TOLERANCE_M)
	assert_vector(Cam.t_pivot(_camera)).is_equal_approx(medium["pivot"], Vector3.ONE * 0.001)
	assert_float(Cam.dist(_camera)).is_equal_approx(large["distance"], Cam.LENGTH_TOLERANCE_M)
	Cam.settle(_camera)
	assert_float(Cam.dist(_camera)).is_equal_approx(medium["distance"], Cam.LENGTH_TOLERANCE_M)
	assert_bool(_history.redo()).is_true()
	assert_float(Cam.t_dist(_camera)).is_equal_approx(large["distance"], Cam.LENGTH_TOLERANCE_M)
	assert_vector(Cam.t_pivot(_camera)).is_equal_approx(large["pivot"], Vector3.ONE * 0.001)
	assert_float(Cam.t_az(_camera)).is_equal_approx(300.0, Cam.ANGLE_TOLERANCE_DEG)


func test_ac08_a_model_reset_moves_the_targets_like_a_load() -> void:
	if not await _open(Table.MEDIUM):
		return
	var large: Dictionary = await _reference(Table.LARGE)
	Cam.set_orbit(_camera, 210.0, 35.0, true)
	_model.reset_from(Room.model_with(Table.LARGE))
	assert_float(Cam.t_az(_camera)).is_equal_approx(210.0, Cam.ANGLE_TOLERANCE_DEG)
	assert_float(Cam.t_dist(_camera)).is_equal_approx(large["distance"], Cam.LENGTH_TOLERANCE_M)
	assert_vector(Cam.t_pivot(_camera)).is_equal_approx(large["pivot"], Vector3.ONE * 0.001)
	assert_float(Cam.t_el(_camera)).is_equal_approx(35.0, Cam.ANGLE_TOLERANCE_DEG)
	Cam.settle(_camera)
	assert_float(Cam.dist(_camera)).is_equal_approx(large["distance"], Cam.LENGTH_TOLERANCE_M)


func test_ac08_a_reset_to_the_same_tank_changes_nothing_visible() -> void:
	if not await _open(Table.MEDIUM):
		return
	Cam.set_orbit(_camera, 210.0, 35.0, true)
	var position: Vector3 = _camera.global_position
	_model.reset_from(Room.model_with(Table.MEDIUM))
	Cam.settle(_camera)
	assert_float(Cam.t_az(_camera)).is_equal_approx(210.0, Cam.ANGLE_TOLERANCE_DEG)
	assert_float(Cam.t_el(_camera)).is_equal_approx(35.0, Cam.ANGLE_TOLERANCE_DEG)
	assert_vector(_camera.global_position).is_equal_approx(position, Vector3.ONE * 0.002)


# --- the camera keeps working after a change ---


func test_ac08_the_orbit_keeps_working_after_a_tank_change() -> void:
	if not await _open(Table.MEDIUM):
		return
	_change(Table.LARGE)
	Cam.drag(_viewport, Vector2(0.0, 1000000.0))
	assert_float(Cam.t_el(_camera)).is_equal_approx(
		Cam.min_el(_camera, Table.LARGE), Cam.ANGLE_TOLERANCE_DEG
	)
	Cam.drag(_viewport, Vector2(0.0, -1000000.0))
	assert_float(Cam.t_el(_camera)).is_equal_approx(Cam.MAX_ELEVATION_DEG, 0.01)
	var start: float = Cam.t_az(_camera)
	Cam.tap(_viewport, KEY_Q)
	assert_float(Cam.t_az(_camera)).is_equal_approx(start + 45.0, Cam.ANGLE_TOLERANCE_DEG)
