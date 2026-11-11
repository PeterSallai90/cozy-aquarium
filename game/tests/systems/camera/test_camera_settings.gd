extends GdUnitTestSuite
## #25 scope (owner: developer): limits, damping, drag speed and repeat interval live in one camera
## settings resource at res://systems/camera/camera_settings.tres, with the starting values of the
## issue. The technical plan also puts the key steps, the frame-time cap and the wall fade there.

const OrbitApi := preload("res://tests/helpers/orbit_api.gd")


func _settings() -> Resource:
	var resource: Resource = OrbitApi.settings()
	(
		assert_bool(resource != null)
		. override_failure_message("%s is missing" % OrbitApi.SETTINGS_RESOURCE)
		. is_true()
	)
	return resource


func test_the_settings_script_and_resource_exist() -> void:
	assert_bool(ResourceLoader.exists(OrbitApi.SETTINGS_PATH)).is_true()
	assert_bool(ResourceLoader.exists(OrbitApi.SETTINGS_RESOURCE)).is_true()


func test_the_resource_uses_the_camera_settings_script() -> void:
	var resource: Resource = _settings()
	if resource == null:
		return
	assert_object(resource.get_script()).is_equal(load(OrbitApi.SETTINGS_PATH))


func test_starting_values_of_the_orbit_limits() -> void:
	if _settings() == null:
		return
	assert_float(OrbitApi.setting("min_elevation_limit_deg")).is_equal_approx(-10.0, 0.0001)
	assert_float(OrbitApi.setting("max_elevation_deg")).is_equal_approx(85.0, 0.0001)


func test_starting_values_of_damping_drag_and_repeat() -> void:
	if _settings() == null:
		return
	assert_float(OrbitApi.setting("damping_time_s")).is_equal_approx(0.15, 0.0001)
	assert_float(OrbitApi.setting("drag_deg_per_viewport_height")).is_equal_approx(180.0, 0.0001)
	assert_float(OrbitApi.setting("key_repeat_interval_s")).is_equal_approx(0.25, 0.0001)
	assert_float(OrbitApi.setting("max_frame_time_s")).is_equal_approx(0.1, 0.0001)


func test_starting_values_of_the_key_steps() -> void:
	if _settings() == null:
		return
	assert_float(OrbitApi.setting("azimuth_step_deg")).is_equal_approx(45.0, 0.0001)
	assert_float(OrbitApi.setting("elevation_step_deg")).is_equal_approx(5.0, 0.0001)


func test_starting_values_of_the_wall_fade() -> void:
	if _settings() == null:
		return
	assert_float(OrbitApi.setting("wall_fade_time_s")).is_equal_approx(0.2, 0.0001)
	assert_float(OrbitApi.setting("wall_hysteresis_band_m")).is_equal_approx(0.05, 0.0001)


# --- #26 (owner: developer): zoom, pan and collision settings ---


func test_26_starting_values_of_zoom_and_pan() -> void:
	if _settings() == null:
		return
	assert_float(OrbitApi.setting("zoom_min_factor")).is_equal_approx(0.6, 0.0001)
	assert_float(OrbitApi.setting("zoom_max_factor")).is_equal_approx(2.5, 0.0001)
	assert_float(OrbitApi.setting("zoom_step_factor")).is_equal_approx(0.9, 0.0001)
	assert_float(OrbitApi.setting("pan_speed")).is_equal_approx(1.0, 0.0001)


func test_26_starting_values_of_the_collision_margin_and_the_near_plane() -> void:
	if _settings() == null:
		return
	assert_float(OrbitApi.setting("collision_margin_m")).is_equal_approx(0.05, 0.0001)
	assert_float(OrbitApi.setting("camera_near_m")).is_equal_approx(0.03, 0.0001)


func test_ac21_the_collision_margin_is_at_least_1_3_times_the_near_plane() -> void:
	if _settings() == null:
		return
	var margin: float = OrbitApi.setting("collision_margin_m")
	var near: float = OrbitApi.setting("camera_near_m")
	assert_float(near).is_greater(0.0)
	assert_float(margin).is_greater_equal(1.3 * near)


func test_26_the_zoom_limits_are_ordered_and_the_step_zooms_in() -> void:
	if _settings() == null:
		return
	var low: float = OrbitApi.setting("zoom_min_factor")
	var high: float = OrbitApi.setting("zoom_max_factor")
	var step: float = OrbitApi.setting("zoom_step_factor")
	assert_float(low).is_greater(0.0)
	assert_float(low).is_less(1.0)
	assert_float(high).is_greater(1.0)
	assert_float(step).is_greater(0.0)
	assert_float(step).is_less(1.0)
