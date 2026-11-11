# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #26 criteria 4, 5 and 6 (owner: developer): the middle-drag pans the pivot "grab the world"
## style, in the screen plane, pixel based, clamped per axis to the interior footprint and the
## water volume height; the cabinet rule raises the elevation when the pan lowers the pivot. The
## expected movement is built from the real camera basis and projection, not from CameraMoves.
## Time comes from BuildCamera.step with fixed frame times.

const Cz := preload("res://tests/helpers/camera_zoom_rig.gd")
const Cam := preload("res://tests/helpers/camera_rig.gd")
const Table := preload("res://tests/helpers/tank_table.gd")
const OrbitApi := preload("res://tests/helpers/orbit_api.gd")

const BOX_TOLERANCE := 0.00001

var _rig: Dictionary = {}
var _viewport: SubViewport = null
var _camera: Camera3D = null
var _default: float = 0.0
var _box: AABB = AABB()
var _id: StringName = &""


func _open(id: StringName, size: Vector2i = Cam.SIZE_16_9) -> bool:
	_id = id
	_rig = await Cz.open_tank(self, id, size)
	_viewport = _rig["viewport"]
	_camera = _rig["camera"]
	_default = _rig["default_distance"]
	if _rig["ok"]:
		_box = Cz.pan_box(id, Cz.stand_z(_rig["room"]))
	return _rig["ok"]


func _in_box(point: Vector3) -> bool:
	var grown: AABB = _box.grow(BOX_TOLERANCE)
	return grown.has_point(point)


func _on_boundary(point: Vector3) -> bool:
	for axis: int in 3:
		if (
			absf(point[axis] - _box.position[axis]) < BOX_TOLERANCE
			or absf(point[axis] - _box.end[axis]) < BOX_TOLERANCE
		):
			return true
	return false


func _lowest() -> float:
	var above: float = Cam.t_pivot(_camera).y - Table.CABINET_TOP_M
	return OrbitApi.min_elevation(
		OrbitApi.setting("min_elevation_limit_deg"), above, Cam.t_dist(_camera)
	)


# --- AC 4: direction and size ---


func test_ac04_the_first_pan_in_the_default_view_matches_the_formula() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		var before: Vector3 = Cam.t_pivot(_camera)
		var relative: Vector2 = Vector2(36.0, -18.0)
		var expected: Vector3 = Cz.expected_pan(_camera, relative, Cam.t_dist(_camera))
		Cz.pan(_viewport, relative)
		assert_vector(Cam.t_pivot(_camera) - before).is_equal_approx(expected, Vector3.ONE * 0.0002)


func test_ac04_the_scale_is_the_vertical_field_of_view_of_the_real_camera() -> void:
	if not await _open(Table.MEDIUM):
		return
	# 16:9 with the horizontal 50 degrees: tan(25 degrees) x 9/16, about 0.2623.
	assert_float(Cz.real_tan_half_vfov(_camera)).is_equal_approx(0.2623, 0.0001)
	var before: Vector3 = Cam.t_pivot(_camera)
	Cz.pan(_viewport, Vector2(72.0, 0.0))
	var moved: float = (Cam.t_pivot(_camera) - before).length()
	# 72 px of 720 px is one tenth of the height: 0.1 x 2 x distance x 0.2623.
	assert_float(moved).is_equal_approx(0.1 * 2.0 * _default * 0.2623, 0.0003)


func test_ac04_a_drag_to_the_right_moves_the_pivot_along_minus_camera_right() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		var basis: Basis = _camera.global_transform.basis
		var before: Vector3 = Cam.t_pivot(_camera)
		Cz.pan(_viewport, Vector2(30.0, 0.0))
		var moved: Vector3 = Cam.t_pivot(_camera) - before
		assert_float(moved.dot(basis.x)).is_less(-0.001)
		assert_float(moved.dot(basis.y)).is_equal_approx(0.0, 0.0002)


func test_ac04_a_drag_down_moves_the_pivot_along_plus_camera_up() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		var basis: Basis = _camera.global_transform.basis
		var before: Vector3 = Cam.t_pivot(_camera)
		Cz.pan(_viewport, Vector2(0.0, 30.0))
		var moved: Vector3 = Cam.t_pivot(_camera) - before
		assert_float(moved.dot(basis.y)).is_greater(0.001)
		assert_float(moved.dot(basis.x)).is_equal_approx(0.0, 0.0002)


func test_ac04_the_formula_holds_at_other_azimuths_and_elevations() -> void:
	if not await _open(Table.LARGE):
		return
	for azimuth: float in [90.0, 215.0, 330.0]:
		for elevation: float in [5.0, 30.0, 60.0]:
			Cz.pose(_camera, azimuth, elevation, _default, _rig["home_pivot"])
			var relative: Vector2 = Vector2(24.0, 16.0)
			var expected: Vector3 = Cz.expected_pan(_camera, relative, Cam.t_dist(_camera))
			var before: Vector3 = Cam.t_pivot(_camera)
			Cz.pan(_viewport, relative)
			assert_vector(Cam.t_pivot(_camera) - before).is_equal_approx(
				expected, Vector3.ONE * 0.0003
			)


func test_ac04_azimuth_elevation_and_distance_are_unchanged_and_the_camera_looks_at_the_pivot(
) -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		Cam.set_orbit(_camera, 130.0, 30.0, true)
		var distance: float = Cam.t_dist(_camera)
		Cz.pan(_viewport, Vector2(-25.0, 15.0))
		assert_float(Cam.t_az(_camera)).is_equal_approx(130.0, Cz.ANGLE_DEG)
		assert_float(Cam.t_el(_camera)).is_equal_approx(30.0, Cz.ANGLE_DEG)
		assert_float(Cam.t_dist(_camera)).is_equal_approx(distance, Cz.LENGTH_M)
		Cam.settle(_camera)
		assert_array(Cam.basis_failures(_camera, Cam.pivot(_camera))).is_empty()
		assert_vector(Cam.pivot(_camera)).is_equal_approx(
			Cam.t_pivot(_camera), Vector3.ONE * Cz.LENGTH_M
		)
		var offset: Vector3 = _camera.global_position - Cam.pivot(_camera)
		assert_float(offset.length()).is_equal_approx(distance, Cz.LENGTH_M)


func test_ac04_at_the_zoom_limits_the_same_drag_moves_the_pivot_in_the_ratio_of_the_distances(
) -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		var relative: Vector2 = Vector2(18.0, 8.0)
		var moves: Array[float] = []
		for distance: float in [Cz.zoom_in_distance(_default), Cz.zoom_out_distance(_default)]:
			Cz.pose(_camera, 0.0, 5.0, distance, _rig["home_pivot"])
			var before: Vector3 = Cam.t_pivot(_camera)
			Cz.pan(_viewport, relative)
			moves.append((Cam.t_pivot(_camera) - before).length())
		assert_float(moves[0] / moves[1]).is_equal_approx(
			Cz.setting("zoom_min_factor") / Cz.setting("zoom_max_factor"), 0.002
		)


func test_ac04_the_pan_follows_the_viewport_height_and_not_the_width() -> void:
	if not await _open(Table.MEDIUM, Cam.SIZE_21_9):
		return
	var relative: Vector2 = Vector2(30.0, 0.0)
	var expected: Vector3 = Cz.expected_pan(_camera, relative, Cam.t_dist(_camera))
	var before: Vector3 = Cam.t_pivot(_camera)
	Cz.pan(_viewport, relative)
	assert_vector(Cam.t_pivot(_camera) - before).is_equal_approx(expected, Vector3.ONE * 0.0003)


func test_ac04_a_long_frame_gives_the_same_pan_result() -> void:
	if not await _open(Table.MEDIUM):
		return
	var before: Vector3 = Cam.t_pivot(_camera)
	Cz.pan(_viewport, Vector2(40.0, -22.0))
	var short_pan: Vector3 = Cam.t_pivot(_camera) - before
	if not await _open(Table.MEDIUM):
		return
	before = Cam.t_pivot(_camera)
	Cam.step(_camera, 0.5, 0.5)
	Cz.middle_press(_viewport)
	Cam.step(_camera, 0.1, 0.1)
	Cz.middle_motion(_viewport, Vector2(40.0, -22.0), Vector2(140.0, 78.0))
	Cam.step(_camera, 0.1, 0.1)
	Cz.middle_release(_viewport, Vector2(140.0, 78.0))
	var long_pan: Vector3 = Cam.t_pivot(_camera) - before
	assert_vector(long_pan).is_equal_approx(short_pan, Vector3.ONE * 0.00001)


func test_ac04_the_pan_ends_on_the_release_and_later_motion_does_not_pan() -> void:
	if not await _open(Table.MEDIUM):
		return
	Cz.middle_press(_viewport)
	assert_bool(Cz.panning(_camera)).is_true()
	Cz.middle_motion(_viewport, Vector2(20.0, 0.0), Vector2(120.0, 100.0))
	Cz.middle_release(_viewport, Vector2(120.0, 100.0))
	assert_bool(Cz.panning(_camera)).is_false()
	var after: Vector3 = Cam.t_pivot(_camera)
	Cz.middle_motion(_viewport, Vector2(60.0, 40.0), Vector2(180.0, 140.0))
	assert_vector(Cam.t_pivot(_camera)).is_equal_approx(after, Vector3.ONE * 0.000001)


func test_ac04_the_left_and_right_buttons_do_not_pan() -> void:
	if not await _open(Table.MEDIUM):
		return
	var pivot: Vector3 = Cam.t_pivot(_camera)
	Cam.button(_viewport, MOUSE_BUTTON_LEFT, true)
	Cam.motion(_viewport, Vector2(60.0, 40.0), Vector2(160.0, 140.0), MOUSE_BUTTON_MASK_LEFT)
	Cam.button(_viewport, MOUSE_BUTTON_LEFT, false, Vector2(160.0, 140.0))
	Cam.drag(_viewport, Vector2(60.0, 40.0))
	assert_vector(Cam.t_pivot(_camera)).is_equal_approx(pivot, Vector3.ONE * 0.000001)
	assert_bool(Cz.panning(_camera)).is_false()


func test_ac04_the_camera_eases_to_the_new_pivot_without_a_jump() -> void:
	if not await _open(Table.MEDIUM):
		return
	var start: Vector3 = Cam.pivot(_camera)
	Cz.pan(_viewport, Vector2(60.0, 0.0))
	assert_vector(Cam.pivot(_camera)).is_equal_approx(start, Vector3.ONE * 0.000001)
	Cam.step(_camera, Cz.FRAME_S)
	var first: float = (Cam.pivot(_camera) - start).length()
	var full: float = (Cam.t_pivot(_camera) - start).length()
	assert_float(first).is_greater(0.0)
	assert_float(first).is_less(full)
	Cam.settle(_camera)
	assert_vector(Cam.pivot(_camera)).is_equal_approx(Cam.t_pivot(_camera), Vector3.ONE * 0.0002)


# --- AC 5: the pivot box ---


func test_ac05_the_default_pivot_is_the_centre_of_the_box() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		assert_vector(_rig["home_pivot"]).is_equal_approx(_box.get_center(), Vector3.ONE * 0.0005)


func test_ac05_far_drags_stop_at_the_edges_for_any_azimuth_elevation_and_zoom() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		var bad: PackedStringArray = PackedStringArray()
		for azimuth: float in [0.0, 90.0, 180.0, 270.0]:
			for elevation: float in [5.0, 30.0, 85.0]:
				for factor: float in [0.6, 1.0, 2.5]:
					Cz.pose(_camera, azimuth, elevation, _default * factor, _rig["home_pivot"])
					for relative: Vector2 in [
						Vector2(-Cz.HUGE, 0.0),
						Vector2(Cz.HUGE, 0.0),
						Vector2(0.0, -Cz.HUGE),
						Vector2(0.0, Cz.HUGE),
					]:
						Cz.pan(_viewport, relative)
						var pivot: Vector3 = Cam.t_pivot(_camera)
						var label: String = (
							"%s az %s el %s x%s %s" % [id, azimuth, elevation, factor, relative]
						)
						if not _in_box(pivot):
							bad.append("%s: pivot %s is outside the box" % [label, pivot])
						elif not _on_boundary(pivot):
							bad.append("%s: pivot %s did not reach an edge" % [label, pivot])
						Cz.set_pivot(_camera, _rig["home_pivot"], true)
		assert_array(bad).override_failure_message(Cz.summary(bad)).is_empty()


func test_ac05_a_drag_far_to_each_side_reaches_the_edge_of_the_footprint_in_the_default_view(
) -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		Cz.pan(_viewport, Vector2(-Cz.HUGE, 0.0))
		assert_float(Cam.t_pivot(_camera).x).is_equal_approx(_box.end.x, BOX_TOLERANCE)
		Cz.pan(_viewport, Vector2(Cz.HUGE, 0.0))
		assert_float(Cam.t_pivot(_camera).x).is_equal_approx(_box.position.x, BOX_TOLERANCE)


func test_ac05_a_drag_far_up_and_down_stops_between_the_floor_and_the_water_line() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		Cz.pan(_viewport, Vector2(0.0, Cz.HUGE))
		assert_float(Cam.t_pivot(_camera).y).is_equal_approx(_box.end.y, BOX_TOLERANCE)
		Cz.pan(_viewport, Vector2(0.0, -Cz.HUGE))
		assert_float(Cam.t_pivot(_camera).y).is_equal_approx(_box.position.y, BOX_TOLERANCE)


func test_ac05_one_very_large_delta_is_clamped_like_many_small_ones() -> void:
	if not await _open(Table.MEDIUM):
		return
	Cz.middle_press(_viewport)
	Cz.middle_motion(_viewport, Vector2(-1.0e9, 1.0e9), Vector2(100.0, 100.0))
	Cz.middle_release(_viewport)
	var at_once: Vector3 = Cam.t_pivot(_camera)
	assert_bool(_in_box(at_once)).is_true()
	if not await _open(Table.MEDIUM):
		return
	Cz.middle_press(_viewport)
	for step: int in 400:
		Cz.middle_motion(_viewport, Vector2(-40.0, 40.0), Vector2(100.0, 100.0))
	Cz.middle_release(_viewport)
	assert_vector(Cam.t_pivot(_camera)).is_equal_approx(at_once, Vector3.ONE * BOX_TOLERANCE)
	assert_vector(at_once).is_equal_approx(_corner_up_left(), Vector3.ONE * BOX_TOLERANCE)


## The corner of the default view where a drag left and down ends (azimuth 0, elevation 5):
## +X, +Y (camera up) and -Z (the camera up vector leans away from the viewer).
func _corner_up_left() -> Vector3:
	return Cz.box_corner(_box, true, true, false)


func test_ac05_a_diagonal_drag_ends_in_the_corner() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		Cz.pan(_viewport, Vector2(-Cz.HUGE, Cz.HUGE))
		assert_vector(Cam.t_pivot(_camera)).is_equal_approx(
			_corner_up_left(), Vector3.ONE * BOX_TOLERANCE
		)
		Cz.pan(_viewport, Vector2(Cz.HUGE, -Cz.HUGE))
		assert_vector(Cam.t_pivot(_camera)).is_equal_approx(
			Cz.box_corner(_box, false, false, true), Vector3.ONE * BOX_TOLERANCE
		)


func test_ac05_a_drag_into_an_edge_slides_along_it_on_the_free_axis() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		Cz.pan(_viewport, Vector2(-Cz.HUGE, 0.0))
		var at_edge: Vector3 = Cam.t_pivot(_camera)
		assert_float(at_edge.x).is_equal_approx(_box.end.x, BOX_TOLERANCE)
		var relative: Vector2 = Vector2(-200.0, 20.0)
		var expected: Vector3 = Cz.expected_pan(_camera, relative, Cam.t_dist(_camera))
		Cz.pan(_viewport, relative)
		var after: Vector3 = Cam.t_pivot(_camera)
		assert_float(after.x).is_equal_approx(_box.end.x, BOX_TOLERANCE)
		assert_float(after.y - at_edge.y).is_equal_approx(expected.y, 0.0002)
		assert_float(after.y).is_greater(at_edge.y)


func test_ac05_the_pivot_is_inside_the_box_at_every_frame_of_the_ease() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		Cam.set_orbit(_camera, 215.0, 30.0, true)
		var bad: PackedStringArray = PackedStringArray()
		var drags: Array[Vector2] = [
			Vector2(-Cz.HUGE, Cz.HUGE), Vector2(Cz.HUGE, 0.0), Vector2(0.0, -Cz.HUGE)
		]
		for relative: Vector2 in drags:
			Cz.pan(_viewport, relative)
			for frame: int in 90:
				Cam.step(_camera, Cz.FRAME_S)
				if not _in_box(Cam.pivot(_camera)):
					bad.append("%s frame %d: pivot %s" % [id, frame, Cam.pivot(_camera)])
				if not _in_box(Cam.t_pivot(_camera)):
					bad.append("%s frame %d: target %s" % [id, frame, Cam.t_pivot(_camera)])
		assert_array(bad).override_failure_message(Cz.summary(bad)).is_empty()


func test_ac05_a_long_frame_keeps_the_pivot_inside_the_box() -> void:
	if not await _open(Table.LARGE):
		return
	Cz.pan(_viewport, Vector2(-Cz.HUGE, Cz.HUGE))
	for frame: int in 10:
		Cam.step(_camera, 0.5, 0.5)
		assert_bool(_in_box(Cam.pivot(_camera))).is_true()
	assert_bool(_in_box(Cam.t_pivot(_camera))).is_true()


# --- AC 6: the cabinet rule while panning ---


func test_ac06_panning_down_raises_the_target_elevation_with_the_new_limit() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		Cam.set_orbit(_camera, 0.0, -90.0, true)
		var before: float = Cam.t_el(_camera)
		assert_float(before).is_equal_approx(_lowest(), Cz.ANGLE_DEG)
		Cz.pan(_viewport, Vector2(0.0, -Cz.HUGE))
		assert_float(Cam.t_pivot(_camera).y).is_equal_approx(_box.position.y, BOX_TOLERANCE)
		var after: float = Cam.t_el(_camera)
		assert_float(after).is_equal_approx(_lowest(), Cz.ANGLE_DEG)
		assert_float(after).is_greater(before + 0.01)


func test_ac06_the_camera_height_stays_at_or_above_the_cabinet_top_while_panning_down() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		Cam.set_orbit(_camera, 0.0, -90.0, true)
		Cz.pan(_viewport, Vector2(0.0, -Cz.HUGE))
		var lowest: float = INF
		for frame: int in 240:
			Cam.step(_camera, Cz.FRAME_S)
			lowest = minf(lowest, _camera.global_position.y)
		assert_float(lowest).is_greater_equal(Table.CABINET_TOP_M - Cz.LENGTH_M)


func test_ac06_panning_up_does_not_lower_the_elevation_by_itself() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		Cam.set_orbit(_camera, 0.0, -90.0, true)
		Cz.pan(_viewport, Vector2(0.0, -Cz.HUGE))
		var raised: float = Cam.t_el(_camera)
		Cz.pan(_viewport, Vector2(0.0, Cz.HUGE))
		assert_float(Cam.t_el(_camera)).is_equal_approx(raised, Cz.ANGLE_DEG)
		Cam.settle(_camera)
		assert_float(Cam.el(_camera)).is_equal_approx(raised, Cz.ANGLE_DEG)


func test_ac06_it_holds_when_the_camera_is_held_by_collision_at_a_low_corner() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		var corner: Vector3 = Cz.box_corner(_box, true, false, false)
		Cz.pose(_camera, 270.0, -90.0, Cz.zoom_in_distance(_default), corner)
		var before: float = Cam.t_el(_camera)
		Cz.pan(_viewport, Vector2(0.0, -30.0))
		assert_float(Cam.t_el(_camera)).is_greater_equal(before - Cz.ANGLE_DEG)
		var raised: float = Cam.t_el(_camera)
		var lowest: float = INF
		for frame: int in 120:
			Cam.step(_camera, Cz.FRAME_S)
			lowest = minf(lowest, _camera.global_position.y)
		assert_float(lowest).is_greater_equal(Table.CABINET_TOP_M - Cz.LENGTH_M)
		Cz.pan(_viewport, Vector2(0.0, 30.0))
		assert_float(Cam.t_el(_camera)).is_equal_approx(raised, Cz.ANGLE_DEG)


# --- #25 regression: resize ---


func test_a_window_resize_keeps_azimuth_elevation_distance_and_pivot() -> void:
	if not await _open(Table.MEDIUM):
		return
	Cz.pose(_camera, 130.0, 30.0, _default * 0.8, _rig["home_pivot"] + Vector3(0.05, 0.02, 0.0))
	var pivot: Vector3 = Cam.t_pivot(_camera)
	_viewport.size = Cam.SIZE_4_3
	await get_tree().process_frame
	Cam.step(_camera, 0.5)
	assert_float(Cam.t_az(_camera)).is_equal_approx(130.0, Cz.ANGLE_DEG)
	assert_float(Cam.t_el(_camera)).is_equal_approx(30.0, Cz.ANGLE_DEG)
	assert_float(Cam.t_dist(_camera)).is_equal_approx(_default * 0.8, Cz.LENGTH_M)
	assert_vector(Cam.t_pivot(_camera)).is_equal_approx(pivot, Vector3.ONE * Cz.LENGTH_M)
	assert_float(Cam.dist(_camera)).is_equal_approx(_default * 0.8, Cz.LENGTH_M)
