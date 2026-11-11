# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #26 criteria 3, 10, 12, 13, 14 and 22 (owner: developer): the build camera never rests inside
## the tank (base to rim top with glass, trim and the air gap), the cabinet or the lamp, each plus
## the collision margin, never below the cabinet top, and collision never changes the target pose.
## The representative set of the issue (3 tanks, azimuth 0/90/180/270, elevation lowest/5/30/85,
## zoom 0.6x/1x, pivot at the centre and two opposite corners of its box) is checked at every
## stepped frame against an oracle built from the catalog numbers and the lamp scene, not from
## CameraSolids (ADR 0009 rule 2: the box grown by the margin, the boundary is outside).
## The exhaustive sweep, the Home and the zoom-through-glass regressions belong to #27.

const Cz := preload("res://tests/helpers/camera_zoom_rig.gd")
const Cam := preload("res://tests/helpers/camera_rig.gd")
const Table := preload("res://tests/helpers/tank_table.gd")
const OrbitApi := preload("res://tests/helpers/orbit_api.gd")

const AZIMUTHS: Array[float] = [0.0, 90.0, 180.0, 270.0]
## -90 stands for "the lowest allowed elevation" (the camera clamps it).
const ELEVATIONS: Array[float] = [-90.0, 5.0, 30.0, 85.0]
const ZOOMS: Array[float] = [0.6, 1.0]
const RAISE_LIMIT_DEG := 0.1
const ORACLE_TOLERANCE_M := 0.0015

var _rig: Dictionary = {}
var _viewport: SubViewport = null
var _camera: Camera3D = null
var _room: Node3D = null
var _default: float = 0.0
var _boxes: Array[AABB] = []
var _pan: AABB = AABB()
var _id: StringName = &""


func _open(id: StringName) -> bool:
	_id = id
	_rig = await Cz.open_tank(self, id)
	_viewport = _rig["viewport"]
	_camera = _rig["camera"]
	_room = _rig["room"]
	_default = _rig["default_distance"]
	if not _rig["ok"]:
		return false
	_boxes = Cz.solids(_room, id)
	_pan = Cz.pan_box(id, Cz.stand_z(_room))
	# The oracle must be the real thing: a tank, a cabinet and the lamp bar with its brackets.
	assert_int(_boxes.size()).is_greater_equal(4)
	return true


func _pivots() -> Array[Vector3]:
	return [
		_rig["home_pivot"],
		Cz.box_corner(_pan, false, false, false),
		Cz.box_corner(_pan, true, true, true),
	]


func _targets() -> Dictionary:
	return {
		"az": Cam.t_az(_camera),
		"el": Cam.t_el(_camera),
		"dist": Cam.t_dist(_camera),
		"pivot": Cam.t_pivot(_camera),
	}


func _same_targets(before: Dictionary, label: String) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	if absf(Cam.t_az(_camera) - before["az"]) > 0.000001:
		failures.append("%s: target azimuth changed" % label)
	if absf(Cam.t_el(_camera) - before["el"]) > 0.000001:
		failures.append("%s: target elevation changed to %s" % [label, Cam.t_el(_camera)])
	if absf(Cam.t_dist(_camera) - before["dist"]) > 0.000001:
		failures.append("%s: target distance changed" % label)
	if Cam.t_pivot(_camera).distance_to(before["pivot"]) > 0.000001:
		failures.append("%s: target pivot changed" % label)
	return failures


## Every rule of ADR 0009 at the current frame; empty when the camera is fine. `reference_el` is
## the elevation the shown elevation is compared with: the target when the pose is settled, the
## eased elevation while it is moving.
func _frame_failures(label: String, before: Dictionary, reference_el: float) -> PackedStringArray:
	var failures: PackedStringArray = Cz.pose_failures(_camera, _boxes, label)
	failures.append_array(_same_targets(before, label))
	var held: bool = Cz.is_held(_camera)
	var requested: float = Cam.dist(_camera)
	var pivot: Vector3 = Cam.pivot(_camera)
	var wanted: Vector3 = pivot + OrbitApi.offset(Cam.az(_camera), Cam.el(_camera), requested)
	if Cz.inside_any(_boxes, Cz.margin(), wanted, 0.001) and not held:
		failures.append(
			"%s: the requested point is inside a solid but the camera is not held" % label
		)
	var actual: float = (_camera.global_position - pivot).length()
	if held:
		if not Cz.inside_any(_boxes, Cz.margin(), wanted, -0.001):
			failures.append("%s: held although the requested point is free" % label)
		var expected: float = Cz.oracle_held(
			_boxes, Cz.margin(), pivot, Cz.shown_direction(_camera), requested
		)
		if absf(actual - expected) > ORACLE_TOLERANCE_M:
			failures.append(
				"%s: distance %.4f, the smallest free distance is %.4f" % [label, actual, expected]
			)
		if actual < requested - Cz.LENGTH_M:
			failures.append(
				"%s: the camera is pulled in to %.4f of %.4f" % [label, actual, requested]
			)
	elif absf(actual - requested) > Cz.LENGTH_M:
		failures.append("%s: not held but at %.4f instead of %.4f" % [label, actual, requested])
	var raise_deg: float = Cz.shown_elevation(_camera) - reference_el
	if raise_deg > RAISE_LIMIT_DEG + Cz.ANGLE_DEG or raise_deg < -Cz.ANGLE_DEG:
		failures.append("%s: shown elevation differs by %.4f degrees" % [label, raise_deg])
	if not held and absf(raise_deg) > Cz.ANGLE_DEG:
		failures.append("%s: shown elevation is raised by %.4f while not held" % [label, raise_deg])
	return failures


## Poses the camera, then checks it at once and after 10 frames.
func _pose_failures(
	label: String, azimuth: float, elevation: float, distance: float, pivot: Vector3
) -> PackedStringArray:
	Cz.pose(_camera, azimuth, elevation, distance, pivot)
	var before: Dictionary = _targets()
	var failures: PackedStringArray = _frame_failures(label, before, Cam.t_el(_camera))
	for frame: int in 10:
		Cam.step(_camera, Cz.FRAME_S)
	failures.append_array(_frame_failures(label + " later", before, Cam.t_el(_camera)))
	return failures


func _sweep(
	azimuths: Array[float], elevations: Array[float], zooms: Array[float], pivots: Array[Vector3]
) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	for pivot: Vector3 in pivots:
		for azimuth: float in azimuths:
			for elevation: float in elevations:
				for zoom: float in zooms:
					var label: String = (
						"%s az %s el %s x%s pivot %s" % [_id, azimuth, elevation, zoom, pivot]
					)
					failures.append_array(
						_pose_failures(label, azimuth, elevation, _default * zoom, pivot)
					)
	return failures


# --- AC 10 and 22: the representative set, per tank ---


func test_ac10_the_small_tank_representative_set_is_clear_of_every_solid() -> void:
	if not await _open(Table.SMALL):
		return
	var failures: PackedStringArray = _sweep(AZIMUTHS, ELEVATIONS, ZOOMS, _pivots())
	assert_array(failures).override_failure_message(Cz.summary(failures)).is_empty()


func test_ac10_the_medium_tank_representative_set_is_clear_of_every_solid() -> void:
	if not await _open(Table.MEDIUM):
		return
	var failures: PackedStringArray = _sweep(AZIMUTHS, ELEVATIONS, ZOOMS, _pivots())
	assert_array(failures).override_failure_message(Cz.summary(failures)).is_empty()


func test_ac10_the_large_tank_representative_set_is_clear_of_every_solid() -> void:
	if not await _open(Table.LARGE):
		return
	var failures: PackedStringArray = _sweep(AZIMUTHS, ELEVATIONS, ZOOMS, _pivots())
	assert_array(failures).override_failure_message(Cz.summary(failures)).is_empty()


func test_ac10_the_representative_set_holds_at_every_zoom_in_between_and_at_the_far_limit() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		var zooms: Array[float] = [
			Cz.setting("zoom_min_factor"), 0.8, 1.5, Cz.setting("zoom_max_factor")
		]
		var elevations: Array[float] = [-90.0, 20.0, 85.0]
		var failures: PackedStringArray = _sweep([45.0, 135.0, 270.0], elevations, zooms, _pivots())
		assert_array(failures).override_failure_message(Cz.summary(failures)).is_empty()


func test_ac22_the_floor_corners_at_the_lowest_elevation_keep_the_camera_above_the_cabinet_top(
) -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		var corners: Array[Vector3] = []
		for high_x: bool in [false, true]:
			for high_z: bool in [false, true]:
				corners.append(Cz.box_corner(_pan, high_x, false, high_z))
		var zoom: Array[float] = [Cz.setting("zoom_min_factor")]
		var failures: PackedStringArray = _sweep([90.0, 270.0], [-90.0], zoom, corners)
		assert_array(failures).override_failure_message(Cz.summary(failures)).is_empty()
		for corner: Vector3 in corners:
			for azimuth: float in [90.0, 270.0]:
				Cz.pose(_camera, azimuth, -90.0, Cz.zoom_in_distance(_default), corner)
				var raise_deg: float = Cz.shown_elevation(_camera) - Cam.t_el(_camera)
				assert_float(raise_deg).is_less_equal(RAISE_LIMIT_DEG + Cz.ANGLE_DEG)
				assert_float(raise_deg).is_greater_equal(-Cz.ANGLE_DEG)
				assert_float(_camera.global_position.y).is_greater_equal(
					Table.CABINET_TOP_M - Cz.LENGTH_M
				)


func test_ac22_the_displayed_elevation_differs_only_while_the_camera_is_held() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		var raised: int = 0
		for pivot: Vector3 in _pivots():
			for azimuth: float in AZIMUTHS:
				Cz.pose(_camera, azimuth, -90.0, Cz.zoom_in_distance(_default), pivot)
				var raise_deg: float = Cz.shown_elevation(_camera) - Cam.t_el(_camera)
				if absf(raise_deg) > Cz.ANGLE_DEG:
					raised += 1
					assert_bool(Cz.is_held(_camera)).is_true()
				assert_float(raise_deg).is_less_equal(RAISE_LIMIT_DEG + Cz.ANGLE_DEG)
		# The raise is a rare exception, not the rule.
		assert_int(raised).is_less(6)


# --- AC 10: mid-damping and a very large wheel event ---


func test_ac10_the_camera_is_clear_at_every_frame_while_it_eases_to_a_blocked_pose() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		var failures: PackedStringArray = PackedStringArray()
		for pivot: Vector3 in [
			Cz.box_corner(_pan, true, false, false), Cz.box_corner(_pan, false, true, true)
		]:
			for azimuth: float in AZIMUTHS:
				Cz.pose(_camera, 0.0, 5.0, _default, _rig["home_pivot"])
				Cz.set_pivot(_camera, pivot, false)
				Cz.set_distance(_camera, Cz.zoom_in_distance(_default), false)
				Cam.set_orbit(_camera, azimuth, -90.0, false)
				var before: Dictionary = _targets()
				for frame: int in 90:
					Cam.step(_camera, Cz.FRAME_S)
					var label: String = "%s az %s frame %d" % [id, azimuth, frame]
					failures.append_array(_frame_failures(label, before, Cam.el(_camera)))
		assert_array(failures).override_failure_message(Cz.summary(failures)).is_empty()


func test_ac10_a_very_large_wheel_event_keeps_the_camera_clear_at_every_frame() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		var failures: PackedStringArray = PackedStringArray()
		for pivot: Vector3 in _pivots():
			for azimuth: float in [90.0, 270.0]:
				Cz.pose(_camera, azimuth, 5.0, _default, pivot)
				Cz.wheel(_viewport, true, Cz.HUGE)
				var before: Dictionary = _targets()
				assert_float(Cam.t_dist(_camera)).is_equal_approx(
					Cz.zoom_in_distance(_default), Cz.LENGTH_M
				)
				for frame: int in 90:
					Cam.step(_camera, Cz.FRAME_S)
					var label: String = "%s az %s frame %d" % [id, azimuth, frame]
					failures.append_array(_frame_failures(label, before, Cam.el(_camera)))
		assert_array(failures).override_failure_message(Cz.summary(failures)).is_empty()


func test_ac10_the_camera_may_be_above_the_rim_plane_over_the_tank() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		Cz.pose(_camera, 0.0, 85.0, Cz.zoom_in_distance(_default), _rig["home_pivot"])
		var rim: float = Cz.tank_box(id, Cz.stand_z(_room)).end.y
		assert_float(_camera.global_position.y).is_greater(rim + Cz.margin())
		assert_float(absf(_camera.global_position.x)).is_less(0.2)
		assert_bool(Cz.is_held(_camera)).is_false()
		assert_float(Cam.el(_camera)).is_equal_approx(85.0, Cz.ANGLE_DEG)


# --- AC 12: the held pose ---


func _inner_side_pose() -> Vector3:
	return (
		Cz.box_corner(_pan, true, false, false) + Vector3(0.0, _pan.size.y / 2.0, _pan.size.z / 2.0)
	)


func test_ac12_a_pivot_at_the_inner_glass_pushes_the_camera_out_along_its_line() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		var pivot: Vector3 = _inner_side_pose()
		var requested: float = Cz.zoom_in_distance(_default)
		Cz.pose(_camera, 270.0, 5.0, requested, pivot)
		var wanted: Vector3 = pivot + OrbitApi.offset(270.0, 5.0, requested)
		assert_bool(Cz.inside_any(_boxes, Cz.margin(), wanted, 0.001)).is_true()
		assert_bool(Cz.is_held(_camera)).is_true()
		var direction: Vector3 = Cz.shown_direction(_camera)
		var expected: float = Cz.oracle_held(_boxes, Cz.margin(), pivot, direction, requested)
		assert_float(Cz.held_dist(_camera)).is_equal_approx(expected, ORACLE_TOLERANCE_M)
		assert_float(Cz.held_dist(_camera)).is_greater(requested)
		assert_vector(_camera.global_position).is_equal_approx(
			pivot + direction * Cz.held_dist(_camera), Vector3.ONE * Cz.LENGTH_M
		)
		assert_bool(Cz.inside_any(_boxes, Cz.margin(), _camera.global_position)).is_false()


func test_ac12_the_view_direction_and_the_pivot_are_unchanged_by_the_hold() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		var pivot: Vector3 = _inner_side_pose()
		Cz.pose(_camera, 270.0, 5.0, Cz.zoom_in_distance(_default), pivot)
		Cam.settle(_camera)
		assert_vector(Cam.pivot(_camera)).is_equal_approx(pivot, Vector3.ONE * Cz.LENGTH_M)
		assert_array(Cam.basis_failures(_camera, pivot)).is_empty()
		assert_float(Cz.shown_elevation(_camera)).is_equal_approx(5.0, Cz.ANGLE_DEG)
		var heading: float = rad_to_deg(
			atan2(Cz.shown_direction(_camera).x, Cz.shown_direction(_camera).z)
		)
		assert_float(Cam.heading_gap(heading, 270.0)).is_less(Cz.ANGLE_DEG)


func test_ac12_the_target_getters_are_never_changed_by_the_hold() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		var pivot: Vector3 = _inner_side_pose()
		var requested: float = Cz.zoom_in_distance(_default)
		Cz.pose(_camera, 270.0, 5.0, requested, pivot)
		var before: Dictionary = _targets()
		Cam.settle(_camera)
		assert_array(_same_targets(before, "held")).is_empty()
		assert_float(Cam.t_dist(_camera)).is_equal_approx(requested, Cz.LENGTH_M)
		assert_float(Cam.t_el(_camera)).is_equal_approx(5.0, Cz.ANGLE_DEG)


func test_ac12_zooming_out_or_panning_back_follows_the_requested_pose_again() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		var pivot: Vector3 = _inner_side_pose()
		Cz.pose(_camera, 270.0, 5.0, Cz.zoom_in_distance(_default), pivot)
		assert_bool(Cz.is_held(_camera)).is_true()
		Cz.wheel(_viewport, false, Cz.HUGE)
		Cam.settle(_camera)
		assert_float(Cam.dist(_camera)).is_equal_approx(Cz.zoom_out_distance(_default), Cz.LENGTH_M)
		assert_bool(Cz.is_held(_camera)).is_false()
		assert_float(Cz.shown_elevation(_camera)).is_equal_approx(Cam.t_el(_camera), Cz.ANGLE_DEG)
		Cz.pose(_camera, 270.0, 5.0, Cz.zoom_in_distance(_default), pivot)
		Cz.set_pivot(_camera, _rig["home_pivot"], false)
		Cam.settle(_camera)
		assert_bool(Cz.is_held(_camera)).is_false()
		assert_float(Cz.shown_elevation(_camera)).is_equal_approx(Cam.t_el(_camera), Cz.ANGLE_DEG)
		assert_float(Cam.dist(_camera)).is_equal_approx(Cz.zoom_in_distance(_default), Cz.LENGTH_M)


func test_ac12_the_camera_height_rule_holds_while_held_at_every_frame() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		var failures: PackedStringArray = PackedStringArray()
		for pivot: Vector3 in _pivots():
			for azimuth: float in [90.0, 270.0]:
				Cz.pose(_camera, azimuth, -90.0, Cz.zoom_in_distance(_default), pivot)
				for frame: int in 60:
					Cam.step(_camera, Cz.FRAME_S)
					if _camera.global_position.y < Table.CABINET_TOP_M - Cz.LENGTH_M:
						failures.append(
							(
								"%s az %s frame %d: y %.4f"
								% [id, azimuth, frame, _camera.global_position.y]
							)
						)
		assert_array(failures).override_failure_message(Cz.summary(failures)).is_empty()


# --- AC 13: no pop ---


func test_ac13_scrolling_in_while_held_does_not_move_the_camera() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		var pivot: Vector3 = _inner_side_pose()
		Cz.pose(_camera, 270.0, 5.0, Cz.zoom_in_distance(_default), pivot)
		Cam.settle(_camera)
		var previous: Vector3 = _camera.global_position
		var worst: float = 0.0
		for frame: int in 60:
			Cz.wheel(_viewport, true)
			Cam.step(_camera, Cz.FRAME_S)
			worst = maxf(worst, _camera.global_position.distance_to(previous))
			previous = _camera.global_position
		assert_float(worst).is_less(Cz.LENGTH_M)


func test_ac13_a_settled_held_camera_changes_by_less_than_a_millimetre_per_frame() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		var pivot: Vector3 = _inner_side_pose()
		Cz.pose(_camera, 270.0, 5.0, Cz.zoom_in_distance(_default), pivot)
		Cam.settle(_camera)
		var previous: Vector3 = _camera.global_position
		var worst: float = 0.0
		for frame: int in 60:
			Cam.step(_camera, Cz.FRAME_S)
			worst = maxf(worst, _camera.global_position.distance_to(previous))
			previous = _camera.global_position
		assert_float(worst).is_less(Cz.LENGTH_M)


func test_ac13_dragging_the_pivot_into_the_solid_moves_the_camera_smoothly() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		var start: Vector3 = (
			Cz.box_corner(_pan, false, false, false)
			+ Vector3(0.0, _pan.size.y / 2.0, _pan.size.z / 2.0)
		)
		Cz.pose(_camera, 270.0, 5.0, Cz.zoom_in_distance(_default), start)
		Cz.set_pivot(_camera, _inner_side_pose(), false)
		var previous: Vector3 = _camera.global_position
		var previous_pivot: Vector3 = Cam.pivot(_camera)
		var failures: PackedStringArray = PackedStringArray()
		for frame: int in 90:
			Cam.step(_camera, Cz.FRAME_S)
			var travel: float = Cam.pivot(_camera).distance_to(previous_pivot)
			var moved: float = _camera.global_position.distance_to(previous)
			if moved > 2.5 * travel + 0.002:
				failures.append("%s frame %d: camera %.4f, pivot %.4f" % [id, frame, moved, travel])
			previous = _camera.global_position
			previous_pivot = Cam.pivot(_camera)
		assert_array(failures).override_failure_message(Cz.summary(failures)).is_empty()


func test_ac13_the_camera_leaves_the_held_distance_by_at_most_the_damp_factor_of_the_gap() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		var pivot: Vector3 = _inner_side_pose()
		Cz.pose(_camera, 270.0, 5.0, Cz.zoom_in_distance(_default), pivot)
		Cam.settle(_camera)
		Cz.wheel(_viewport, false, Cz.HUGE)
		var goal: float = Cz.zoom_out_distance(_default)
		var factor: float = OrbitApi.damp_factor(Cz.FRAME_S, OrbitApi.setting("damping_time_s"))
		var previous: float = (_camera.global_position - Cam.pivot(_camera)).length()
		var failures: PackedStringArray = PackedStringArray()
		for frame: int in 120:
			Cam.step(_camera, Cz.FRAME_S)
			var shown: float = (_camera.global_position - Cam.pivot(_camera)).length()
			var moved: float = absf(shown - previous)
			if moved > factor * (goal - previous) + 0.003:
				failures.append(
					"%s frame %d: moved %.4f of a gap of %.4f" % [id, frame, moved, goal - previous]
				)
			if Cz.inside_any(_boxes, Cz.margin(), _camera.global_position):
				failures.append("%s frame %d: inside a solid" % [id, frame])
			previous = shown
		assert_array(failures).override_failure_message(Cz.summary(failures)).is_empty()


func test_ac13_with_damping_time_zero_the_camera_is_at_the_held_position_at_once() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		var copy: Resource = _camera.get("settings").duplicate()
		copy.set("damping_time_s", 0.0)
		_camera.set("settings", copy)
		var pivot: Vector3 = _inner_side_pose()
		Cz.pose(_camera, 270.0, 5.0, Cz.zoom_in_distance(_default), pivot)
		var direction: Vector3 = Cz.shown_direction(_camera)
		var expected: float = Cz.oracle_held(
			_boxes, Cz.margin(), pivot, direction, Cz.zoom_in_distance(_default)
		)
		Cam.step(_camera, Cz.FRAME_S)
		assert_float((_camera.global_position - pivot).length()).is_equal_approx(
			expected, ORACLE_TOLERANCE_M
		)
		assert_bool(Cz.inside_any(_boxes, Cz.margin(), _camera.global_position)).is_false()


# --- AC 14: the default view at 0.6x is not held ---


func test_ac14_at_the_default_view_the_displayed_elevation_equals_the_target_exactly() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		assert_bool(Cz.is_held(_camera)).is_false()
		assert_float(Cz.shown_elevation(_camera)).is_equal_approx(Cam.t_el(_camera), 0.0001)
		assert_float(Cam.el(_camera)).is_equal(Cam.t_el(_camera))


func test_ac14_zooming_to_the_minimum_from_the_default_view_is_not_held() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		Cz.wheel(_viewport, true, Cz.HUGE)
		var failures: PackedStringArray = PackedStringArray()
		for frame: int in 120:
			Cam.step(_camera, Cz.FRAME_S)
			if Cz.is_held(_camera):
				failures.append("%s frame %d: held" % [id, frame])
			failures.append_array(Cz.pose_failures(_camera, _boxes, "%s frame %d" % [id, frame]))
		assert_array(failures).override_failure_message(Cz.summary(failures)).is_empty()
		assert_float(Cam.dist(_camera)).is_equal_approx(Cz.zoom_in_distance(_default), Cz.LENGTH_M)
		assert_float(Cz.held_dist(_camera)).is_equal_approx(Cam.dist(_camera), Cz.LENGTH_M)
		assert_float(Cz.shown_elevation(_camera)).is_equal_approx(Cam.t_el(_camera), 0.0001)


func test_ac14_at_the_minimum_zoom_the_camera_is_outside_the_glass_trim_cabinet_and_lamp() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		Cz.pose(_camera, 0.0, 5.0, Cz.zoom_in_distance(_default), _rig["home_pivot"])
		var z: float = Cz.stand_z(_room)
		var front: float = Cz.cabinet_box(id, z).end.z
		assert_float(_camera.global_position.z).is_greater(front + Cz.margin())
		assert_float(_camera.global_position.z).is_greater(Cz.tank_box(id, z).end.z + Cz.margin())
		assert_bool(Cz.inside_any(_boxes, Cz.margin(), _camera.global_position)).is_false()
		assert_float(_camera.global_position.y).is_greater_equal(
			Table.CABINET_TOP_M + 0.166 - Cz.LENGTH_M
		)
