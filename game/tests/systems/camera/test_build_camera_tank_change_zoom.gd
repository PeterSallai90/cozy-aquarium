# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #26 criterion 16 (owner: developer): a tank change (chooser, undo, redo, load) while the camera
## is orbited, zoomed and panned. Zoom and pan are deliberately not kept: the pivot and the
## distance ease to the water-volume centre and the default distance of the new tank, the azimuth
## is kept, the elevation is re-clamped, and the camera is never inside a solid of the new tank at
## any frame. The pan box and the zoom limits are the ones of the new tank afterwards.

const Cz := preload("res://tests/helpers/camera_zoom_rig.gd")
const Cam := preload("res://tests/helpers/camera_rig.gd")
const Api := preload("res://tests/helpers/late_api.gd")
const Room := preload("res://tests/helpers/room_rig.gd")
const Table := preload("res://tests/helpers/tank_table.gd")
const OrbitApi := preload("res://tests/helpers/orbit_api.gd")

const PAIRS: Array = [
	[&"tank_medium_1", &"tank_large_1"],
	[&"tank_large_1", &"tank_small_1"],
	[&"tank_small_1", &"tank_medium_1"],
	[&"tank_large_1", &"tank_medium_1"],
]

var _model: AquariumModel = null
var _history: CommandHistory = null
var _catalog: RefCounted = null
var _rig: Dictionary = {}
var _viewport: SubViewport = null
var _room: Node3D = null
var _camera: Camera3D = null
var _default: float = 0.0


func before_test() -> void:
	_history = CommandHistory.new()
	_catalog = Room.default_catalog()


func _open(id: StringName) -> bool:
	_model = Room.model_with(id)
	_rig = await Cz.open(self, _model, Cam.SIZE_16_9, id)
	_viewport = _rig["viewport"]
	_room = _rig["room"]
	_camera = _rig["camera"]
	_default = _rig["default_distance"]
	return _rig["ok"]


func _change(id: StringName) -> void:
	assert_bool(_history.execute(Api.change_tank(_model, _catalog, id))).is_true()


## Orbited, zoomed and panned: the camera is at the pose at once.
func _away(azimuth: float, elevation: float) -> void:
	var pan: AABB = Cz.pan_box(_rig["id"], Cz.stand_z(_room))
	var pivot: Vector3 = Cz.box_corner(pan, true, false, false) - Vector3(0.02, 0.0, 0.0)
	Cz.pose(_camera, azimuth, elevation, _default * 0.7, pivot)


func _reference(id: StringName) -> Dictionary:
	return await Cz.open_tank(self, id)


## The failures of `frames` frames after a change to `id`: inside a solid of the new tank.
func _ease_failures(id: StringName, frames: int) -> PackedStringArray:
	var boxes: Array[AABB] = Cz.solids(_room, id)
	var failures: PackedStringArray = PackedStringArray()
	for frame: int in frames:
		Cam.step(_camera, Cz.FRAME_S)
		failures.append_array(Cz.pose_failures(_camera, boxes, "to %s frame %d" % [id, frame]))
	return failures


func _assert_new_targets(id: StringName, azimuth: float) -> void:
	var reference: Dictionary = await _reference(id)
	assert_float(Cam.t_az(_camera)).is_equal_approx(azimuth, Cz.ANGLE_DEG)
	assert_float(Cam.t_dist(_camera)).is_equal_approx(reference["default_distance"], Cz.LENGTH_M)
	assert_vector(Cam.t_pivot(_camera)).is_equal_approx(
		reference["home_pivot"], Vector3.ONE * Cz.LENGTH_M
	)
	var above: float = Cam.t_pivot(_camera).y - Table.CABINET_TOP_M
	var lowest: float = OrbitApi.min_elevation(
		OrbitApi.setting("min_elevation_limit_deg"), above, Cam.t_dist(_camera)
	)
	assert_float(Cam.t_el(_camera)).is_greater_equal(lowest - Cz.ANGLE_DEG)


func test_ac16_the_chooser_change_eases_pivot_and_distance_and_keeps_the_azimuth() -> void:
	for pair: Array in PAIRS:
		if not await _open(pair[0]):
			return
		_away(130.0, 30.0)
		_change(pair[1])
		await _assert_new_targets(pair[1], 130.0)
		assert_float(Cam.t_el(_camera)).is_equal_approx(30.0, Cz.ANGLE_DEG)
		var failures: PackedStringArray = _ease_failures(pair[1], 150)
		assert_array(failures).override_failure_message(Cz.summary(failures)).is_empty()
		var reference: Dictionary = await _reference(pair[1])
		assert_float(Cam.dist(_camera)).is_equal_approx(reference["default_distance"], Cz.LENGTH_M)
		assert_vector(Cam.pivot(_camera)).is_equal_approx(
			reference["home_pivot"], Vector3.ONE * Cz.LENGTH_M
		)
		assert_float(Cam.az(_camera)).is_equal_approx(130.0, Cz.ANGLE_DEG)


func test_ac16_zoom_and_pan_are_not_kept() -> void:
	if not await _open(Table.MEDIUM):
		return
	_away(0.0, 5.0)
	var zoomed: float = Cam.t_dist(_camera)
	var panned: Vector3 = Cam.t_pivot(_camera)
	_change(Table.LARGE)
	assert_float(Cam.t_dist(_camera)).is_not_equal(zoomed)
	assert_vector(Cam.t_pivot(_camera)).is_not_equal(panned)
	var reference: Dictionary = await _reference(Table.LARGE)
	assert_float(Cam.t_dist(_camera)).is_equal_approx(reference["default_distance"], Cz.LENGTH_M)


func test_ac16_the_change_at_the_lowest_elevation_never_enters_a_solid() -> void:
	for pair: Array in PAIRS:
		if not await _open(pair[0]):
			return
		Cz.pose(_camera, 270.0, -90.0, _default * 0.6, _rig["home_pivot"])
		_change(pair[1])
		var failures: PackedStringArray = _ease_failures(pair[1], 150)
		assert_array(failures).override_failure_message(Cz.summary(failures)).is_empty()


func test_ac16_a_camera_that_was_zoomed_out_far_comes_back_without_entering_a_solid() -> void:
	for pair: Array in PAIRS:
		if not await _open(pair[0]):
			return
		Cz.pose(_camera, 90.0, 20.0, _default * 2.5, _rig["home_pivot"])
		_change(pair[1])
		var failures: PackedStringArray = _ease_failures(pair[1], 150)
		assert_array(failures).override_failure_message(Cz.summary(failures)).is_empty()


func test_ac16_undo_and_redo_do_the_same() -> void:
	if not await _open(Table.MEDIUM):
		return
	_away(200.0, 25.0)
	_change(Table.LARGE)
	Cam.settle(_camera)
	_away_again(Table.LARGE, 200.0, 25.0)
	assert_bool(_history.undo()).is_true()
	await _assert_new_targets(Table.MEDIUM, 200.0)
	var failures: PackedStringArray = _ease_failures(Table.MEDIUM, 150)
	assert_array(failures).override_failure_message(Cz.summary(failures)).is_empty()
	_away_again(Table.MEDIUM, 200.0, 25.0)
	assert_bool(_history.redo()).is_true()
	await _assert_new_targets(Table.LARGE, 200.0)
	failures = _ease_failures(Table.LARGE, 150)
	assert_array(failures).override_failure_message(Cz.summary(failures)).is_empty()


func _away_again(id: StringName, azimuth: float, elevation: float) -> void:
	var pan: AABB = Cz.pan_box(id, Cz.stand_z(_room))
	var pivot: Vector3 = Cz.box_corner(pan, false, false, true) + Vector3(0.02, 0.0, -0.02)
	Cz.pose(_camera, azimuth, elevation, Cam.t_dist(_camera) * 0.8, pivot)


func test_ac16_a_load_does_the_same() -> void:
	if not await _open(Table.MEDIUM):
		return
	_away(75.0, 15.0)
	_model.reset_from(Room.model_with(Table.SMALL))
	await _assert_new_targets(Table.SMALL, 75.0)
	var failures: PackedStringArray = _ease_failures(Table.SMALL, 150)
	assert_array(failures).override_failure_message(Cz.summary(failures)).is_empty()


func test_ac16_after_the_change_the_pan_box_and_the_zoom_limits_are_those_of_the_new_tank() -> void:
	if not await _open(Table.SMALL):
		return
	_away(0.0, 5.0)
	_change(Table.LARGE)
	Cam.settle(_camera)
	var reference: Dictionary = await _reference(Table.LARGE)
	var default_large: float = reference["default_distance"]
	Cz.wheel(_viewport, true, Cz.HUGE)
	assert_float(Cam.t_dist(_camera)).is_equal_approx(
		Cz.zoom_in_distance(default_large), Cz.LENGTH_M
	)
	Cz.wheel(_viewport, false, Cz.HUGE)
	assert_float(Cam.t_dist(_camera)).is_equal_approx(
		Cz.zoom_out_distance(default_large), Cz.LENGTH_M
	)
	var box: AABB = Cz.pan_box(Table.LARGE, Cz.stand_z(_room))
	Cz.pan(_viewport, Vector2(-Cz.HUGE, Cz.HUGE))
	assert_bool(box.grow(0.00001).has_point(Cam.t_pivot(_camera))).is_true()
	assert_float(Cam.t_pivot(_camera).x).is_equal_approx(box.end.x, 0.00001)
	Cz.pan(_viewport, Vector2(Cz.HUGE, -Cz.HUGE))
	assert_float(Cam.t_pivot(_camera).x).is_equal_approx(box.position.x, 0.00001)
