extends GdUnitTestSuite
## #27 criteria 1 to 5, 9 and 10 (owner: tester): the consolidated camera limit suite. One named
## test per criterion of the camera epic (docs/architecture.md), run for every tank of the catalog
## (res://catalog/tanks), with the shared invariant checker of camera_invariants.gd.
##
## Input is simulated headless: through the BuildCamera API and through synthetic
## InputEventMouseButton, InputEventMouseMotion and InputEventKey objects pushed into the
## SubViewport with push_input(), which reaches _unhandled_input and _input as the engine would.
## Focus loss uses notification() on the camera. No OS input is used; the run needs
## --ignoreHeadlessMode (issue #27, comment 1).
##
## Numbers come from camera_settings.tres, the catalog and OrbitMath; the only literals are the
## poses of the story (azimuth 750, 85 degrees, 3 turns) and the two mutations of criterion 10.
## Limits are asserted on the target, the transform rules on the displayed camera (BA decision Q4).
## Covered elsewhere and not repeated: test_ac08_an_exact_tie_goes_to_the_higher_multiple (Home
## tie), test_ac20_events_that_arrive_while_the_window_is_unfocused_change_nothing (unfocused
## Home), test_ac01_a_wheel_event_with_factor_zero_is_treated_as_one and
## test_ac13_a_release_outside_the_viewport_ends_the_drag.

const Lim := preload("res://tests/helpers/camera_limit_rig.gd")
const Inv := preload("res://tests/helpers/camera_invariants.gd")
const Cz := preload("res://tests/helpers/camera_zoom_rig.gd")
const Cam := preload("res://tests/helpers/camera_rig.gd")
const Table := preload("res://tests/helpers/tank_table.gd")
const Eo := preload("res://tests/helpers/engine_output.gd")

const ANGLE: float = 0.01
const LENGTH: float = 0.001
const TOP_LIMIT_DEG: float = 85.0
const FAR_AZIMUTH_DEG: float = 750.0
const TURNS: int = 3
const TURN_MOTIONS: int = 120
const WIDENED_ELEVATION_DEG: float = -30.0
const WIDENED_ZOOM_FACTOR: float = 0.3
const HOME_FRAME_TIMES: Array[float] = [1.0 / 60.0, 0.5]
const FOCUS_NOTIFICATIONS: Array[bool] = [false, true]

var _rigs: Array[Lim.TankRig] = []
var _failures: PackedStringArray = PackedStringArray()


func before() -> void:
	_rigs = await Lim.open_all(self)


func before_test() -> void:
	var failures: PackedStringArray = PackedStringArray()
	for rig: Lim.TankRig in _rigs:
		failures.append_array(Lim.reset(rig))
	_assert_clean(failures)
	_failures = PackedStringArray()


func after_test() -> void:
	# The production resource is cached and shared: a test that changed it instead of a duplicate
	# would leak into every later suite. These are the committed values of camera_settings.tres.
	var settings: CameraSettings = Lim.production_settings()
	assert_float(settings.min_elevation_limit_deg).is_equal(-10.0)
	assert_float(settings.max_elevation_deg).is_equal(85.0)
	assert_float(settings.zoom_min_factor).is_equal(0.6)
	assert_float(settings.zoom_max_factor).is_equal(2.5)
	assert_float(settings.damping_time_s).is_equal(0.15)


# --- helpers ---


func _assert_clean(failures: PackedStringArray) -> void:
	assert_bool(failures.is_empty()).override_failure_message(Cz.summary(failures)).is_true()


func _limit() -> float:
	return Lim.production_settings().min_elevation_limit_deg


func _floor_at(rig: Lim.TankRig, distance_m: float) -> float:
	return OrbitMath.min_elevation_deg(_limit(), rig.home_pivot.y - Lim.cabinet_top(), distance_m)


func _label(name: String, rig: Lim.TankRig) -> String:
	return "%s tank=%s" % [name, rig.id]


func _far_pose(rig: Lim.TankRig) -> void:
	var camera: BuildCamera = rig.camera
	var settings: CameraSettings = Lim.production_settings()
	camera.set_target_pivot(Cz.box_corner(rig.water, true, false, true), true)
	camera.set_target_distance_m(settings.zoom_min_factor * rig.default_distance, true)
	camera.set_orbit(FAR_AZIMUTH_DEG, settings.min_elevation_limit_deg, true)
	camera.step(0.0)


func _default_view_failures(rig: Lim.TankRig, label: String) -> PackedStringArray:
	var camera: BuildCamera = rig.camera
	var failures: PackedStringArray = PackedStringArray()
	var home_azimuth: float = 360.0 * floorf(FAR_AZIMUTH_DEG / 360.0 + 0.5)
	if absf(camera.get_target_azimuth_deg() - home_azimuth) > ANGLE:
		failures.append("%s: target azimuth %f" % [label, camera.get_target_azimuth_deg()])
	if absf(camera.get_azimuth_deg() - home_azimuth) > ANGLE:
		failures.append("%s: azimuth %f" % [label, camera.get_azimuth_deg()])
	var start: float = RoomCorner.CAMERA_ELEVATION_DEG
	if absf(camera.get_target_elevation_deg() - start) > ANGLE:
		failures.append("%s: target elevation %f" % [label, camera.get_target_elevation_deg()])
	if absf(camera.get_elevation_deg() - start) > ANGLE:
		failures.append("%s: elevation %f" % [label, camera.get_elevation_deg()])
	for distance: float in [
		camera.get_target_distance_m(), camera.get_distance_m(), camera.get_held_distance_m()
	]:
		if absf(distance - rig.default_distance) > LENGTH:
			failures.append("%s: distance %f is not the default" % [label, distance])
	for pivot: Vector3 in [camera.get_target_pivot(), camera.get_pivot()]:
		if pivot.distance_to(rig.home_pivot) > LENGTH:
			failures.append("%s: pivot %s is not home" % [label, pivot])
	return failures


# --- guards ---


func test_the_tank_catalog_has_at_least_three_tanks() -> void:
	var ids: Array[StringName] = Lim.tank_ids()
	assert_int(ids.size()).is_greater_equal(Lim.MIN_TANKS)
	assert_int(_rigs.size()).is_equal(ids.size())
	for id: StringName in Table.IDS:
		assert_bool(ids.has(id)).is_true()


func test_the_solid_oracle_has_tank_cabinet_and_lamp_boxes_and_matches_the_table() -> void:
	for rig: Lim.TankRig in _rigs:
		assert_int(rig.solids.size()).is_greater_equal(4)
		assert_float(rig.water.size.y).is_equal_approx(rig.definition.water_line_height_m, 0.000001)
		if not Table.IDS.has(rig.id):
			continue
		var table_solids: Array[AABB] = Cz.solids(rig.room, rig.id)
		assert_int(rig.solids.size()).is_equal(table_solids.size())
		for index: int in mini(rig.solids.size(), table_solids.size()):
			var mine: AABB = rig.solids[index]
			var theirs: AABB = table_solids[index]
			assert_bool(mine.position.distance_to(theirs.position) <= LENGTH).is_true()
			assert_bool(mine.size.distance_to(theirs.size) <= LENGTH).is_true()


# --- criterion 1 and 2: the elevation floor ---


func test_epic_orbit_down_stops_at_minus_10_and_stays_above_cabinet() -> void:
	# The floor is the higher of the story limit and the cabinet-limited angle (BA decision on
	# criterion 1): -10 for the small and medium tank, about -9.979 for the large one.
	var failures: PackedStringArray = PackedStringArray()
	for rig: Lim.TankRig in _rigs:
		var label: String = _label("floor drag", rig)
		failures.append_array(Lim.drive_floor_drag(rig, label))
		var expected: float = _floor_at(rig, rig.default_distance)
		var camera: BuildCamera = rig.camera
		if absf(camera.get_target_elevation_deg() - expected) > ANGLE:
			failures.append(
				"%s: target %f, expected %f" % [label, camera.get_target_elevation_deg(), expected]
			)
		if absf(camera.get_target_elevation_deg() - camera.get_min_elevation_deg()) > ANGLE:
			failures.append("%s: target is not get_min_elevation_deg()" % label)
		if camera.get_target_elevation_deg() < _limit() - ANGLE:
			failures.append(
				"%s: target %f is below the limit" % [label, camera.get_target_elevation_deg()]
			)
		if absf(expected - _limit()) > 0.05:
			failures.append(
				"%s: expected floor %f is not within 0.05 of the limit" % [label, expected]
			)
	_assert_clean(failures)


func test_epic_orbit_down_when_zoomed_out_stops_at_the_cabinet_limited_elevation() -> void:
	var failures: PackedStringArray = PackedStringArray()
	var settings: CameraSettings = Lim.production_settings()
	for rig: Lim.TankRig in _rigs:
		var label: String = _label("floor drag at max zoom", rig)
		var camera: BuildCamera = rig.camera
		var far: float = settings.zoom_max_factor * rig.default_distance
		camera.set_target_distance_m(far, true)
		camera.step(0.0)
		failures.append_array(Lim.drive_floor_drag(rig, label))
		var expected: float = _floor_at(rig, far)
		var target: float = camera.get_target_elevation_deg()
		if absf(target - expected) > ANGLE:
			failures.append("%s: target %f, expected %f" % [label, target, expected])
		if target <= settings.min_elevation_limit_deg + ANGLE:
			failures.append("%s: target %f reached the story limit" % [label, target])
		if target >= settings.max_elevation_deg:
			failures.append("%s: target %f is at the top limit" % [label, target])
		if absf(target - camera.get_min_elevation_deg()) > ANGLE:
			failures.append("%s: target is not get_min_elevation_deg()" % label)
	_assert_clean(failures)


# --- criterion 3: the top limit ---


func test_epic_orbit_at_85_keeps_dragging_and_never_flips() -> void:
	var failures: PackedStringArray = PackedStringArray()
	var settings: CameraSettings = Lim.production_settings()
	for rig: Lim.TankRig in _rigs:
		var label: String = _label("top limit", rig)
		var camera: BuildCamera = rig.camera
		var height: float = float(rig.viewport.size.y)
		Cam.drag(rig.viewport, Vector2(0.0, -Lim.DRAG_HEIGHTS * height))
		Lim.record(rig, failures, label, Lim.AFTER_EVENT)
		var degrees_per_motion: float = float(TURNS) * 360.0 / float(TURN_MOTIONS)
		var motion_px: float = degrees_per_motion / settings.drag_deg_per_viewport_height * height
		Cam.right_press(rig.viewport)
		for index: int in TURN_MOTIONS:
			Cam.motion(rig.viewport, Vector2(motion_px, -0.5 * height))
			Lim.record(rig, failures, label, Lim.AFTER_EVENT)
			Lim.frame(rig, Lim.FRAME_S, failures, label, index)
		Cam.right_release(rig.viewport)
		Lim.settle(rig, 90, failures, label, TURN_MOTIONS)
		if absf(camera.get_target_elevation_deg() - TOP_LIMIT_DEG) > ANGLE:
			failures.append("%s: target elevation %f" % [label, camera.get_target_elevation_deg()])
		if camera.get_elevation_deg() > TOP_LIMIT_DEG + ANGLE:
			failures.append("%s: displayed elevation %f" % [label, camera.get_elevation_deg()])
		var turned: float = camera.get_target_azimuth_deg()
		if absf(turned - float(TURNS) * 360.0) > ANGLE:
			failures.append("%s: azimuth %f after %d turns" % [label, turned, TURNS])
		if camera.global_transform.basis.y.y <= 0.0:
			failures.append("%s: the up vector points down" % label)
	_assert_clean(failures)


# --- criterion 4 and 5: Home ---


func _home_case(rig: Lim.TankRig, dt: float) -> PackedStringArray:
	var camera: BuildCamera = rig.camera
	var label: String = "home tank=%s dt=%.4f" % [rig.id, dt]
	var failures: PackedStringArray = PackedStringArray()
	failures.append_array(Lim.reset(rig))
	_far_pose(rig)
	Lim.record(rig, failures, label, Lim.AFTER_EVENT)
	var pose_before: Transform3D = camera.global_transform
	var start: Array[float] = _eased(camera)
	Cz.home_key(rig.viewport)
	if camera.global_transform != pose_before:
		failures.append("%s: the camera moved before the first step" % label)
	var targets: Array[float] = _targets(camera)
	var damping: float = Lim.production_settings().damping_time_s
	var share: float = OrbitMath.damp_factor(dt, damping)
	var previous: Array[float] = start
	var frames: int = maxi(1, ceili(10.0 * damping / dt))
	for index: int in frames:
		camera.step(dt)
		Lim.record(rig, failures, label, index)
		var now: Array[float] = _eased(camera)
		for axis: int in now.size():
			var tolerance: float = 0.001
			var gap_before: float = targets[axis] - previous[axis]
			var gap_now: float = targets[axis] - now[axis]
			if absf(gap_now) > absf(gap_before) + tolerance:
				failures.append("%s frame %d value %d: the gap grew" % [label, index, axis])
			if gap_now * (targets[axis] - start[axis]) < -tolerance:
				failures.append("%s frame %d value %d: overshoot" % [label, index, axis])
			if index == 0 and absf(now[axis] - previous[axis]) > share * absf(gap_before) + 0.01:
				failures.append("%s: value %d moved more than the easing share" % [label, axis])
		previous = now
	failures.append_array(_default_view_failures(rig, label))
	return failures


func _eased(camera: BuildCamera) -> Array[float]:
	var pivot: Vector3 = camera.get_pivot()
	return [camera.get_azimuth_deg(), camera.get_elevation_deg(), pivot.x, pivot.y, pivot.z]


func _targets(camera: BuildCamera) -> Array[float]:
	var pivot: Vector3 = camera.get_target_pivot()
	return [
		camera.get_target_azimuth_deg(),
		camera.get_target_elevation_deg(),
		pivot.x,
		pivot.y,
		pivot.z
	]


func test_epic_home_returns_smoothly_to_the_default_front_view() -> void:
	var failures: PackedStringArray = PackedStringArray()
	for rig: Lim.TankRig in _rigs:
		for dt: float in HOME_FRAME_TIMES:
			failures.append_array(_home_case(rig, dt))
	_assert_clean(failures)


func test_epic_home_without_smoothing_reaches_the_default_view_in_the_same_frame() -> void:
	var failures: PackedStringArray = PackedStringArray()
	for rig: Lim.TankRig in _rigs:
		var label: String = _label("home without smoothing", rig)
		var camera: BuildCamera = rig.camera
		var instant: CameraSettings = Lim.production_settings().duplicate() as CameraSettings
		instant.damping_time_s = 0.0
		camera.settings = instant
		_far_pose(rig)
		Cz.home_key(rig.viewport)
		Lim.frame(rig, Lim.FRAME_S, failures, label, 0)
		failures.append_array(_default_view_failures(rig, label))
		# The far-pose zoom-in without smoothing obeys the invariants in the same frame.
		_far_pose(rig)
		camera.set_target_distance_m(rig.default_distance, true)
		Lim.notch_in(rig, label + " zoom", failures)
	_assert_clean(failures)


func test_home_works_again_after_the_window_focus_returns() -> void:
	var failures: PackedStringArray = PackedStringArray()
	for rig: Lim.TankRig in _rigs:
		var label: String = _label("home after focus", rig)
		var camera: BuildCamera = rig.camera
		Cz.focus_out(camera)
		_far_pose(rig)
		var far: Array[float] = _targets(camera)
		Cz.home_key(rig.viewport)
		if _targets(camera) != far:
			failures.append("%s: Home changed the targets while unfocused" % label)
		Cz.focus_in(camera)
		Cz.home_key(rig.viewport)
		Lim.settle(rig, 90, failures, label)
		failures.append_array(_default_view_failures(rig, label))
	_assert_clean(failures)


# --- criterion 9: failure and edge cases ---


func test_negative_wheel_factors_count_as_one_notch_and_keep_the_limits() -> void:
	var failures: PackedStringArray = PackedStringArray()
	var step: float = Lim.production_settings().zoom_step_factor
	for rig: Lim.TankRig in _rigs:
		for factor: float in [-1.0, -2.5]:
			var label: String = "%s factor=%s" % [_label("negative wheel", rig), factor]
			failures.append_array(Lim.reset(rig))
			var camera: BuildCamera = rig.camera
			Cz.wheel(rig.viewport, true, factor)
			Lim.record(rig, failures, label, Lim.AFTER_EVENT)
			var once: float = rig.default_distance * step
			if absf(camera.get_target_distance_m() - once) > LENGTH:
				failures.append(
					"%s: distance %f, expected %f" % [label, camera.get_target_distance_m(), once]
				)
			Lim.settle(rig, 30, failures, label)
			Cz.wheel(rig.viewport, true)
			Lim.record(rig, failures, label, Lim.AFTER_EVENT)
			var twice: float = rig.default_distance * step * step
			if absf(camera.get_target_distance_m() - twice) > LENGTH:
				failures.append(
					(
						"%s: next notch gave %f, expected %f"
						% [label, camera.get_target_distance_m(), twice]
					)
				)
	_assert_clean(failures)


func test_a_zero_or_negative_viewport_height_moves_nothing() -> void:
	# A SubViewport cannot have height 0, so the guard is asserted where the divisions are.
	var per_height: float = Lim.production_settings().drag_deg_per_viewport_height
	assert_float(OrbitMath.drag_deg(100.0, 0.0, per_height)).is_equal(0.0)
	assert_float(OrbitMath.drag_deg(100.0, -10.0, per_height)).is_equal(0.0)
	var offset: Vector3 = CameraMoves.pan_offset(Vector2(10.0, 10.0), 0.0, 1.0, 0.5, 1.0, 0.0, 0.0)
	assert_vector(offset).is_equal(Vector3.ZERO)
	offset = CameraMoves.pan_offset(Vector2(10.0, 10.0), -5.0, 1.0, 0.5, 1.0, 0.0, 0.0)
	assert_vector(offset).is_equal(Vector3.ZERO)


func _release_outside_at_the_floor() -> void:
	for rig: Lim.TankRig in _rigs:
		var label: String = _label("release outside", rig)
		var camera: BuildCamera = rig.camera
		var height: float = float(rig.viewport.size.y)
		Cam.right_press(rig.viewport)
		Cam.motion(rig.viewport, Vector2(0.0, Lim.DRAG_HEIGHTS * height), Vector2(-50.0, -50.0))
		Lim.record(rig, _failures, label, Lim.AFTER_EVENT)
		Cam.right_release(rig.viewport, Vector2(-50.0, -50.0))
		if camera.is_dragging():
			_failures.append("%s: the drag did not end" % label)
		Lim.settle(rig, 60, _failures, label)
		var floor_elevation: float = camera.get_target_elevation_deg()
		Cam.drag(rig.viewport, Vector2(0.0, -0.1 * height))
		Lim.settle(rig, 30, _failures, label, 60)
		if camera.get_target_elevation_deg() <= floor_elevation + ANGLE:
			_failures.append("%s: the next drag did not work" % label)


func test_a_release_outside_the_viewport_at_the_floor_keeps_the_limits() -> void:
	var seen: Dictionary = await Eo.capture(_release_outside_at_the_floor)
	_assert_clean(_failures)
	assert_dict(seen["errors"]).is_empty()
	assert_dict(seen["warnings"]).is_empty()


func _focus_loss_mid_drag() -> void:
	for rig: Lim.TankRig in _rigs:
		for window: bool in FOCUS_NOTIFICATIONS:
			for at_top: bool in [false, true]:
				Lim.reset(rig)
				var label: String = (
					"%s window=%s top=%s" % [_label("focus loss", rig), window, at_top]
				)
				var camera: BuildCamera = rig.camera
				var height: float = float(rig.viewport.size.y)
				var push: float = (-1.0 if at_top else 1.0) * Lim.DRAG_HEIGHTS * height
				Cam.right_press(rig.viewport)
				Cam.motion(rig.viewport, Vector2(0.0, push))
				Lim.record(rig, _failures, label, Lim.AFTER_EVENT)
				var held_elevation: float = camera.get_target_elevation_deg()
				Cz.focus_out(camera, window)
				Cam.motion(rig.viewport, Vector2(0.0, -push))
				if camera.is_dragging():
					_failures.append("%s: still dragging after focus loss" % label)
				if absf(camera.get_target_elevation_deg() - held_elevation) > ANGLE:
					_failures.append("%s: motion after focus loss moved the target" % label)
				Cz.focus_in(camera, window)
				Lim.settle(rig, 60, _failures, label)
				# A new drag away from the limit works.
				Cam.drag(rig.viewport, Vector2(0.0, -0.1 * height * signf(push)))
				if absf(camera.get_target_elevation_deg() - held_elevation) <= ANGLE:
					_failures.append("%s: the next drag did not work" % label)
				Lim.settle(rig, 30, _failures, label, 60)


func test_focus_loss_mid_drag_at_the_floor_and_at_85_keeps_the_limits() -> void:
	var seen: Dictionary = await Eo.capture(_focus_loss_mid_drag)
	_assert_clean(_failures)
	assert_dict(seen["errors"]).is_empty()
	assert_dict(seen["warnings"]).is_empty()


func _wheel_factor_events() -> void:
	for rig: Lim.TankRig in _rigs:
		for factor: float in [-1.0, -2.5, 0.0]:
			Cz.wheel(rig.viewport, false, factor)
			Cz.wheel(rig.viewport, true, factor)
			Lim.record(rig, _failures, _label("wheel factor", rig), Lim.AFTER_EVENT)


func test_odd_wheel_factors_log_no_engine_error_or_warning() -> void:
	var seen: Dictionary = await Eo.capture(_wheel_factor_events)
	_assert_clean(_failures)
	assert_dict(seen["errors"]).is_empty()
	assert_dict(seen["warnings"]).is_empty()


# --- criterion 10: the mutation check ---


## Pose of meta-test 1: the water-surface centre (the pivot height at which the cabinet rule allows
## the lowest angle) at the closest zoom, so a limit of -30 degrees is observable below -10.
func _widened_elevation_pose(rig: Lim.TankRig) -> void:
	var settings: CameraSettings = Lim.production_settings()
	var top: Vector3 = Vector3(rig.home_pivot.x, rig.water.end.y, rig.home_pivot.z)
	rig.camera.set_target_pivot(top, true)
	rig.camera.set_target_distance_m(settings.zoom_min_factor * rig.default_distance, true)
	rig.camera.set_orbit(0.0, RoomCorner.CAMERA_ELEVATION_DEG, true)
	rig.camera.step(0.0)


func test_mutation_a_widened_elevation_minimum_is_reported() -> void:
	var settings: CameraSettings = Lim.production_settings()
	for rig: Lim.TankRig in _rigs:
		var widened: CameraSettings = settings.duplicate() as CameraSettings
		widened.min_elevation_limit_deg = WIDENED_ELEVATION_DEG
		rig.camera.settings = widened
		_widened_elevation_pose(rig)
		var top_y: float = rig.camera.get_target_pivot().y
		var lowest: float = OrbitMath.min_elevation_deg(
			WIDENED_ELEVATION_DEG,
			top_y - Lim.cabinet_top(),
			settings.zoom_min_factor * rig.default_distance
		)
		# Precondition: the widened limit is observable in this pose.
		assert_float(lowest).is_less(settings.min_elevation_limit_deg - Inv.ANGLE_TOLERANCE_DEG)
		var failures: PackedStringArray = Lim.drive_floor_drag(rig, _label("mutation", rig))
		(
			assert_bool(Inv.has_kind(failures, Inv.KIND_ELEVATION))
			. override_failure_message("no elevation violation for %s" % rig.id)
			. is_true()
		)


func test_mutation_a_widened_zoom_minimum_is_reported() -> void:
	var settings: CameraSettings = Lim.production_settings()
	for rig: Lim.TankRig in _rigs:
		var widened: CameraSettings = settings.duplicate() as CameraSettings
		widened.zoom_min_factor = WIDENED_ZOOM_FACTOR
		rig.camera.settings = widened
		# 12 notches of the step factor reach about 0.28 times the default, below 0.3.
		var pose_failures: PackedStringArray = Lim.pose_home(
			rig, 0.0, RoomCorner.CAMERA_ELEVATION_DEG
		)
		assert_bool(pose_failures.is_empty()).is_true()
		var failures: PackedStringArray = Lim.drive_zoom_in(rig, _label("mutation", rig))
		(
			assert_bool(Inv.has_kind(failures, Inv.KIND_DISTANCE))
			. override_failure_message("no distance violation for %s" % rig.id)
			. is_true()
		)


func test_mutation_control_unchanged_settings_report_nothing() -> void:
	var failures: PackedStringArray = PackedStringArray()
	for rig: Lim.TankRig in _rigs:
		_widened_elevation_pose(rig)
		failures.append_array(Lim.drive_floor_drag(rig, _label("control floor", rig)))
		failures.append_array(Lim.pose_home(rig, 0.0, RoomCorner.CAMERA_ELEVATION_DEG))
		failures.append_array(Lim.drive_zoom_in(rig, _label("control zoom", rig)))
	_assert_clean(failures)
