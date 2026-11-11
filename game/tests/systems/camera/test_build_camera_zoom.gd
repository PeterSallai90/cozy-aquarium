# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #26 criteria 1, 2 and 3 and the near plane (owner: developer): the mouse wheel zooms the build
## camera toward the pivot by `zoom_step_factor` per notch, the target distance is clamped to
## 0.6x to 2.5x of the default distance of the tank, the elevation limit follows the distance, and
## the camera height never drops below the cabinet top. Each test runs on all three tanks. Time
## comes from BuildCamera.step with fixed frame times; the limits are read from the settings.

const Cz := preload("res://tests/helpers/camera_zoom_rig.gd")
const Cam := preload("res://tests/helpers/camera_rig.gd")
const Table := preload("res://tests/helpers/tank_table.gd")
const OrbitApi := preload("res://tests/helpers/orbit_api.gd")

var _rig: Dictionary = {}
var _viewport: SubViewport = null
var _camera: Camera3D = null
var _default: float = 0.0


func _open(id: StringName) -> bool:
	_rig = await Cz.open_tank(self, id)
	_viewport = _rig["viewport"]
	_camera = _rig["camera"]
	_default = _rig["default_distance"]
	return _rig["ok"]


func _step() -> float:
	return Cz.setting("zoom_step_factor")


## The lowest allowed elevation for the target pivot and distance, from the OrbitMath helper.
func _lowest() -> float:
	var above: float = Cam.t_pivot(_camera).y - Table.CABINET_TOP_M
	return OrbitApi.min_elevation(
		OrbitApi.setting("min_elevation_limit_deg"), above, Cam.t_dist(_camera)
	)


# --- AC 1: one notch and many ---


func test_ac01_one_notch_in_multiplies_the_target_distance_by_the_step_factor() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		Cz.wheel(_viewport, true)
		assert_float(Cam.t_dist(_camera)).is_equal_approx(_default * _step(), Cz.LENGTH_M)


func test_ac01_one_notch_out_multiplies_the_target_distance_by_one_over_the_step_factor() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		Cz.wheel(_viewport, false)
		assert_float(Cam.t_dist(_camera)).is_equal_approx(_default / _step(), Cz.LENGTH_M)


func test_ac01_the_camera_eases_to_the_new_distance_and_does_not_jump() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		Cz.wheel(_viewport, true)
		assert_float(Cam.dist(_camera)).is_equal_approx(_default, Cz.LENGTH_M)
		Cam.step(_camera, Cz.FRAME_S)
		assert_float(Cam.dist(_camera)).is_less(_default - 0.0001)
		assert_float(Cam.dist(_camera)).is_greater(_default * _step() + 0.0001)
		Cam.settle(_camera)
		assert_float(Cam.dist(_camera)).is_equal_approx(_default * _step(), Cz.LENGTH_M)


func test_ac01_n_notches_before_damping_settles_give_the_step_factor_to_the_power_of_n() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		for notch: int in 3:
			Cz.wheel(_viewport, true)
		assert_float(Cam.t_dist(_camera)).is_equal_approx(_default * pow(_step(), 3.0), Cz.LENGTH_M)


func test_ac01_notches_between_frames_accumulate_on_the_target_not_on_the_eased_distance() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		for notch: int in 3:
			Cz.wheel(_viewport, true)
			Cam.step(_camera, 0.03)
		assert_float(Cam.t_dist(_camera)).is_equal_approx(_default * pow(_step(), 3.0), Cz.LENGTH_M)
		Cam.settle(_camera)
		assert_float(Cam.dist(_camera)).is_equal_approx(_default * pow(_step(), 3.0), Cz.LENGTH_M)


func test_ac01_a_fractional_wheel_event_uses_the_step_factor_to_the_power_of_the_factor() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		Cz.wheel(_viewport, true, 0.5)
		assert_float(Cam.t_dist(_camera)).is_equal_approx(_default * pow(_step(), 0.5), Cz.LENGTH_M)


func test_ac01_a_fractional_wheel_event_out_uses_the_inverse_step_factor_to_the_power() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		Cz.wheel(_viewport, false, 0.5)
		assert_float(Cam.t_dist(_camera)).is_equal_approx(
			_default * pow(1.0 / _step(), 0.5), Cz.LENGTH_M
		)


func test_ac01_a_wheel_event_with_factor_zero_is_treated_as_one() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		Cz.wheel(_viewport, true, 0.0)
		assert_float(Cam.t_dist(_camera)).is_equal_approx(_default * _step(), Cz.LENGTH_M)


func test_ac01_the_zoom_goes_toward_the_pivot_and_keeps_the_orbit() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		Cam.set_orbit(_camera, 130.0, 30.0, true)
		var pivot: Vector3 = Cam.t_pivot(_camera)
		Cz.wheel(_viewport, true, 1.0, 0, Vector2(900.0, 500.0))
		Cz.wheel(_viewport, true, 1.0, 0, Vector2(900.0, 500.0))
		Cam.settle(_camera)
		assert_vector(Cam.pivot(_camera)).is_equal_approx(pivot, Vector3.ONE * Cz.LENGTH_M)
		assert_float(Cam.az(_camera)).is_equal_approx(130.0, Cz.ANGLE_DEG)
		assert_float(Cam.el(_camera)).is_equal_approx(30.0, Cz.ANGLE_DEG)
		var offset: Vector3 = _camera.global_position - pivot
		assert_float(offset.length()).is_equal_approx(_default * _step() * _step(), Cz.LENGTH_M)


func test_ac01_the_left_mouse_button_never_zooms() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		Cam.button(_viewport, MOUSE_BUTTON_LEFT, true)
		Cam.motion(_viewport, Vector2(80.0, 40.0), Vector2(180.0, 140.0), MOUSE_BUTTON_MASK_LEFT)
		Cam.button(_viewport, MOUSE_BUTTON_LEFT, false, Vector2(180.0, 140.0))
		assert_float(Cam.t_dist(_camera)).is_equal_approx(_default, Cz.LENGTH_M)
		assert_vector(Cam.t_pivot(_camera)).is_equal_approx(
			_rig["home_pivot"], Vector3.ONE * 0.0001
		)


# --- AC 2: the limits ---


func test_ac02_scrolling_in_far_past_the_limit_stops_at_the_zoom_min_factor() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		for notch: int in 60:
			Cz.wheel(_viewport, true)
		assert_float(Cam.t_dist(_camera)).is_equal_approx(
			Cz.zoom_in_distance(_default), Cz.LENGTH_M
		)
		Cam.settle(_camera)
		assert_float(Cam.dist(_camera)).is_equal_approx(Cz.zoom_in_distance(_default), Cz.LENGTH_M)


func test_ac02_scrolling_out_far_past_the_limit_stops_at_the_zoom_max_factor() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		for notch: int in 60:
			Cz.wheel(_viewport, false)
		assert_float(Cam.t_dist(_camera)).is_equal_approx(
			Cz.zoom_out_distance(_default), Cz.LENGTH_M
		)
		Cam.settle(_camera)
		assert_float(Cam.dist(_camera)).is_equal_approx(Cz.zoom_out_distance(_default), Cz.LENGTH_M)


func test_ac02_one_event_with_a_very_large_factor_stops_at_the_limits() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		Cz.wheel(_viewport, true, Cz.HUGE)
		assert_float(Cam.t_dist(_camera)).is_equal_approx(
			Cz.zoom_in_distance(_default), Cz.LENGTH_M
		)
		Cz.wheel(_viewport, false, Cz.HUGE)
		assert_float(Cam.t_dist(_camera)).is_equal_approx(
			Cz.zoom_out_distance(_default), Cz.LENGTH_M
		)
		Cz.wheel(_viewport, true, Cz.HUGE)
		assert_float(Cam.t_dist(_camera)).is_equal_approx(
			Cz.zoom_in_distance(_default), Cz.LENGTH_M
		)


func test_ac02_the_limits_are_the_factors_of_the_default_distance_of_each_tank() -> void:
	var seen: Array[float] = []
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		seen.append(_default)
		Cz.wheel(_viewport, true, Cz.HUGE)
		assert_float(Cam.t_dist(_camera) / _default).is_equal_approx(
			Cz.setting("zoom_min_factor"), 0.0001
		)
		Cz.wheel(_viewport, false, Cz.HUGE)
		assert_float(Cam.t_dist(_camera) / _default).is_equal_approx(
			Cz.setting("zoom_max_factor"), 0.0001
		)
	# The default distances differ between the tanks (small, medium, large).
	assert_float(seen[0]).is_less(seen[1])
	assert_float(seen[1]).is_less(seen[2])


func test_ac02_the_target_distance_never_leaves_the_limits_at_any_frame() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		var low: float = Cz.zoom_in_distance(_default) - Cz.LENGTH_M
		var high: float = Cz.zoom_out_distance(_default) + Cz.LENGTH_M
		var worst: PackedStringArray = PackedStringArray()
		for frame: int in 200:
			if frame % 7 == 0:
				Cz.wheel(_viewport, frame % 14 == 0, 3.0)
			Cam.step(_camera, Cz.FRAME_S)
			for value: float in [Cam.t_dist(_camera), Cam.dist(_camera)]:
				if value < low or value > high:
					worst.append("frame %d: distance %.4f" % [frame, value])
		assert_array(worst).is_empty()


func test_ac02_the_limits_hold_from_an_orbited_and_panned_camera() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		Cam.set_orbit(_camera, 200.0, 40.0, true)
		Cz.set_pivot(_camera, _rig["home_pivot"] + Vector3(0.05, 0.03, -0.02), true)
		Cz.wheel(_viewport, true, Cz.HUGE)
		assert_float(Cam.t_dist(_camera)).is_equal_approx(
			Cz.zoom_in_distance(_default), Cz.LENGTH_M
		)
		Cz.wheel(_viewport, false, Cz.HUGE)
		assert_float(Cam.t_dist(_camera)).is_equal_approx(
			Cz.zoom_out_distance(_default), Cz.LENGTH_M
		)


# --- AC 3: the cabinet rule while zooming ---


func test_ac03_zooming_out_raises_the_target_elevation_to_the_new_lowest_elevation() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		Cam.set_orbit(_camera, 0.0, -90.0, true)
		var before: float = Cam.t_el(_camera)
		assert_float(before).is_equal_approx(_lowest(), Cz.ANGLE_DEG)
		Cz.wheel(_viewport, false, Cz.HUGE)
		var after: float = Cam.t_el(_camera)
		assert_float(after).is_equal_approx(_lowest(), Cz.ANGLE_DEG)
		assert_float(after).is_greater(before + 0.01)


func test_ac03_zooming_back_in_does_not_lower_the_elevation_by_itself() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		Cam.set_orbit(_camera, 0.0, -90.0, true)
		Cz.wheel(_viewport, false, Cz.HUGE)
		var raised: float = Cam.t_el(_camera)
		Cz.wheel(_viewport, true, Cz.HUGE)
		assert_float(Cam.t_el(_camera)).is_equal_approx(raised, Cz.ANGLE_DEG)
		Cam.settle(_camera)
		assert_float(Cam.el(_camera)).is_equal_approx(raised, Cz.ANGLE_DEG)


func test_ac03_zooming_in_never_lowers_an_elevation_that_is_still_allowed() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		Cam.set_orbit(_camera, 0.0, 12.0, true)
		Cz.wheel(_viewport, true, Cz.HUGE)
		assert_float(Cam.t_el(_camera)).is_equal_approx(12.0, Cz.ANGLE_DEG)


func test_ac03_the_camera_height_never_drops_below_the_cabinet_top_while_zooming_out() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		Cam.set_orbit(_camera, 0.0, -90.0, true)
		Cz.wheel(_viewport, false, Cz.HUGE)
		var lowest: float = INF
		for frame: int in 240:
			Cam.step(_camera, Cz.FRAME_S)
			lowest = minf(lowest, _camera.global_position.y)
		assert_float(lowest).is_greater_equal(Table.CABINET_TOP_M - Cz.LENGTH_M)


func test_ac03_the_camera_height_stays_above_the_cabinet_top_at_every_frame_of_a_zoom_in() -> void:
	for id: StringName in Table.IDS:
		if not await _open(id):
			return
		Cam.set_orbit(_camera, 0.0, -90.0, true)
		var lowest: float = INF
		for frame: int in 240:
			if frame % 10 == 0:
				Cz.wheel(_viewport, frame % 20 == 0)
			Cam.step(_camera, Cz.FRAME_S)
			lowest = minf(lowest, _camera.global_position.y)
		assert_float(lowest).is_greater_equal(Table.CABINET_TOP_M - Cz.LENGTH_M)


# --- modifiers ---


func test_ac19_the_wheel_with_ctrl_alt_shift_or_meta_does_not_zoom() -> void:
	if not await _open(Table.MEDIUM):
		return
	for modifier: int in Cz.MASK_ALL:
		Cz.wheel(_viewport, true, 1.0, modifier)
		Cz.wheel(_viewport, false, 1.0, modifier)
		assert_float(Cam.t_dist(_camera)).is_equal_approx(_default, Cz.LENGTH_M)
	Cz.wheel(_viewport, true)
	assert_float(Cam.t_dist(_camera)).is_equal_approx(_default * _step(), Cz.LENGTH_M)


# --- near plane ---


func test_ac17_the_camera_near_plane_is_the_setting() -> void:
	if not await _open(Table.MEDIUM):
		return
	assert_float(_camera.near).is_equal_approx(Cz.setting("camera_near_m"), 0.000001)
