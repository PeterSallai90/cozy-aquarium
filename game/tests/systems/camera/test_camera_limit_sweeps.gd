extends GdUnitTestSuite
## #27 criteria 6, 7 and 8 (owner: tester): the sweeps of the camera limit suite. Criterion 6 zooms
## in far past the limit from 24 azimuths and 4 elevations of every catalog tank, criterion 7 does
## the same with the pivot at each of the four inner corners of the water volume, and criterion 8
## applies seeded random sequences of orbit, wheel, pan and Home events at three frame times.
## Every frame is checked by the shared invariant checker; inside loops failures are collected
## and each test asserts once at the end, with tank, azimuth, elevation, seed and frame named.
##
## Input is simulated headless: synthetic mouse and key events pushed into the SubViewport with
## push_input() (never OS input); the run needs --ignoreHeadlessMode (issue #27, comment 1).

const Lim := preload("res://tests/helpers/camera_limit_rig.gd")
const Cz := preload("res://tests/helpers/camera_zoom_rig.gd")

const AZIMUTH_STEP_DEG: int = 15
const AZIMUTH_COUNT: int = 24
const ELEVATIONS: Array[float] = [-10.0, 5.0, 45.0, 85.0]
const NOTCHES: int = 12
const SETTLE_FRAMES: int = 60
const SWEEP_BASE_SEED: int = 270000
const SWEEP_SEQUENCES: int = 150
const SWEEP_SEQUENCES_FLOOR: int = 50
const SWEEP_SEQUENCES_TARGET: int = 200
const EVENTS_PER_SEQUENCE: int = 40
const SWEEP_FRAME_TIMES: Array[float] = [1.0 / 144.0, 1.0 / 30.0, 0.5]
const ANGLE: float = 0.01
const LENGTH: float = 0.001

var _rigs: Array[Lim.TankRig] = []


func before() -> void:
	_rigs = await Lim.open_all(self)


func before_test() -> void:
	var failures: PackedStringArray = PackedStringArray()
	for rig: Lim.TankRig in _rigs:
		failures.append_array(Lim.reset(rig))
	_assert_clean(failures)


func after_test() -> void:
	# The shared production resource must keep its committed values (see test_camera_limits.gd).
	var settings: CameraSettings = Lim.production_settings()
	assert_float(settings.min_elevation_limit_deg).is_equal(-10.0)
	assert_float(settings.max_elevation_deg).is_equal(85.0)
	assert_float(settings.zoom_min_factor).is_equal(0.6)
	assert_float(settings.zoom_max_factor).is_equal(2.5)
	assert_float(settings.damping_time_s).is_equal(0.15)


func _assert_clean(failures: PackedStringArray) -> void:
	assert_bool(failures.is_empty()).override_failure_message(Cz.summary(failures)).is_true()


func _zoom_min_distance(rig: Lim.TankRig) -> float:
	return Lim.production_settings().zoom_min_factor * rig.default_distance


func test_the_sweep_size_is_within_the_decided_range() -> void:
	assert_int(SWEEP_FRAME_TIMES.size()).is_equal(3)
	assert_int(EVENTS_PER_SEQUENCE).is_equal(40)
	assert_int(SWEEP_SEQUENCES).is_greater_equal(SWEEP_SEQUENCES_FLOOR)
	assert_int(SWEEP_SEQUENCES).is_less_equal(SWEEP_SEQUENCES_TARGET)
	assert_int(AZIMUTH_COUNT * AZIMUTH_STEP_DEG).is_equal(360)
	assert_int(ELEVATIONS.size()).is_equal(4)


func test_epic_zoom_in_never_passes_through_the_glass_at_any_azimuth() -> void:
	var failures: PackedStringArray = PackedStringArray()
	for rig: Lim.TankRig in _rigs:
		for step: int in AZIMUTH_COUNT:
			for elevation: float in ELEVATIONS:
				var azimuth: float = float(step * AZIMUTH_STEP_DEG)
				var label: String = (
					"glass tank=%s azimuth=%d elevation=%d" % [rig.id, int(azimuth), int(elevation)]
				)
				for message: String in Lim.pose_home(rig, azimuth, elevation):
					failures.append("%s pose: %s" % [label, message])
				label = (
					"glass tank=%s azimuth=%d elevation=%.2f"
					% [rig.id, int(azimuth), rig.camera.get_target_elevation_deg()]
				)
				failures.append_array(Lim.drive_zoom_in(rig, label, NOTCHES, SETTLE_FRAMES))
				if absf(rig.camera.get_target_distance_m() - _zoom_min_distance(rig)) > LENGTH:
					failures.append(
						"%s: target distance %f" % [label, rig.camera.get_target_distance_m()]
					)
				if failures.size() >= Lim.FAILURE_CAP:
					break
	_assert_clean(failures)


func _corners(rig: Lim.TankRig) -> Array[Vector3]:
	var y: float = rig.home_pivot.y
	var corners: Array[Vector3] = []
	for high_x: bool in [false, true]:
		for high_z: bool in [false, true]:
			var corner: Vector3 = Cz.box_corner(rig.water, high_x, false, high_z)
			corner.y = y
			corners.append(corner)
	return corners


func _targets(camera: BuildCamera) -> Array[float]:
	var pivot: Vector3 = camera.get_target_pivot()
	return [
		camera.get_target_azimuth_deg(),
		camera.get_target_elevation_deg(),
		camera.get_target_distance_m(),
		pivot.x,
		pivot.y,
		pivot.z
	]


func _targets_changed(first: Array[float], second: Array[float]) -> bool:
	for index: int in first.size():
		var tolerance: float = ANGLE if index < 2 else LENGTH
		if absf(first[index] - second[index]) > tolerance:
			return true
	return false


func test_epic_zoom_in_with_the_pivot_at_the_glass_edge_never_passes_through_the_glass() -> void:
	var failures: PackedStringArray = PackedStringArray()
	for rig: Lim.TankRig in _rigs:
		var camera: BuildCamera = rig.camera
		for corner: Vector3 in _corners(rig):
			for step: int in AZIMUTH_COUNT:
				for elevation: float in ELEVATIONS:
					var azimuth: float = float(step * AZIMUTH_STEP_DEG)
					var label: String = (
						"edge tank=%s corner=%s azimuth=%d elevation=%d"
						% [rig.id, corner, int(azimuth), int(elevation)]
					)
					camera.set_target_pivot(corner, true)
					camera.set_target_distance_m(rig.default_distance, true)
					camera.set_orbit(azimuth, elevation, true)
					camera.step(0.0)
					Lim.record(rig, failures, label + " pose", Lim.AFTER_EVENT)
					Lim.notch_in(rig, label, failures, NOTCHES)
					var after_notches: Array[float] = _targets(camera)
					Lim.settle(rig, SETTLE_FRAMES, failures, label, NOTCHES)
					if _targets_changed(after_notches, _targets(camera)):
						failures.append("%s: collision changed a target" % label)
					var looking: Vector3 = -camera.global_transform.basis.z
					var to_pivot: Vector3 = camera.get_pivot() - camera.global_position
					var gap_deg: float = rad_to_deg(looking.angle_to(to_pivot))
					if gap_deg > ANGLE:
						failures.append(
							"%s: the view misses the pivot by %f degrees" % [label, gap_deg]
						)
					if failures.size() >= Lim.FAILURE_CAP:
						break
	_assert_clean(failures)


func _random_sequences(frame_time_index: int) -> void:
	var failures: PackedStringArray = PackedStringArray()
	var dt: float = SWEEP_FRAME_TIMES[frame_time_index]
	for tank_index: int in _rigs.size():
		var rig: Lim.TankRig = _rigs[tank_index]
		var size: Vector2 = Vector2(rig.viewport.size)
		for sequence_index: int in SWEEP_SEQUENCES:
			failures.append_array(Lim.reset(rig))
			var seed_value: int = Lim.sequence_seed(
				SWEEP_BASE_SEED, tank_index, frame_time_index, sequence_index
			)
			var rng: RandomNumberGenerator = RandomNumberGenerator.new()
			rng.seed = seed_value
			var events: Array[Dictionary] = Lim.sequence(rng, size, EVENTS_PER_SEQUENCE)
			var label: String = (
				"seed=%d tank=%s dt=%.5f seq=%d" % [seed_value, rig.id, dt, sequence_index]
			)
			failures.append_array(Lim.run_sequence(rig, events, dt, label))
			if failures.size() >= Lim.FAILURE_CAP:
				break
	_assert_clean(failures)


func test_limits_hold_in_random_sequences_at_144_fps() -> void:
	_random_sequences(0)


func test_limits_hold_in_random_sequences_at_30_fps() -> void:
	_random_sequences(1)


func test_limits_hold_in_random_sequences_with_half_second_frames() -> void:
	# No segment sweep between two frames: the ADR promises the pose, not the path (Q12).
	_random_sequences(2)
