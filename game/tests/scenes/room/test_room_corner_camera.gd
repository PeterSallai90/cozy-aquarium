extends GdUnitTestSuite
## #22 criteria 9 and 13 (owner: developer): the placeholder camera framing at several aspect
## ratios (ADR 0005 and the BA decision on AC 9) and a clean load. The room lives in a SubViewport
## so the aspect ratio can be chosen per test.

const Api := preload("res://tests/helpers/late_api.gd")
const Rig := preload("res://tests/helpers/room_rig.gd")
const Glb := preload("res://tests/helpers/glb_mesh_checks.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")

const WIDE_REFERENCE := 16.0 / 9.0
const SHARE_TOLERANCE := 0.02
const CABINET_TOP_FRONT := Vector3(0.33, 0.75, 0.18)

var _viewport: SubViewport = null
var _room: Node3D = null


func _open(size: Vector2i) -> void:
	(
		assert_bool(ResourceLoader.exists(Rig.ROOM_SCENE))
		. override_failure_message("room scene missing: %s" % Rig.ROOM_SCENE)
		. is_true()
	)
	_viewport = SubViewport.new()
	_viewport.size = size
	add_child(_viewport)
	auto_free(_viewport)
	_room = Rig.instantiate(AquariumModel.new(), Rig.default_catalog())
	_viewport.add_child(_room)
	await get_tree().process_frame


func _camera() -> Camera3D:
	return _room.get_node("PlaceholderCamera") as Camera3D


func _tank() -> Node3D:
	return _room.get_node("Tank") as Node3D


func _expected_share(size: Vector2i) -> float:
	var aspect: float = float(size.x) / float(size.y)
	if aspect <= WIDE_REFERENCE + 0.0001:
		return Api.room_constant("CAMERA_WIDTH_SHARE")
	return Api.room_constant("CAMERA_WIDTH_SHARE") * WIDE_REFERENCE / aspect


## Share of the screen width between the front corners of the exterior glass at pivot height.
func _measured_share(size: Vector2i) -> float:
	var exterior: Vector3 = Rig.exterior_m()
	var pivot_y: float = Rig.water_line_m() / 2.0
	var left: Vector2 = _camera().unproject_position(
		_tank().transform * Vector3(-exterior.x / 2.0, pivot_y, exterior.z / 2.0)
	)
	var right: Vector2 = _camera().unproject_position(
		_tank().transform * Vector3(exterior.x / 2.0, pivot_y, exterior.z / 2.0)
	)
	return absf(right.x - left.x) / float(size.x)


func _assert_on_screen(point: Vector3, size: Vector2i, label: String) -> void:
	var camera: Camera3D = _camera()
	(
		assert_bool(camera.is_position_behind(point))
		. override_failure_message("%s is behind the camera" % label)
		. is_false()
	)
	var screen: Vector2 = camera.unproject_position(point)
	var ok: bool = screen.x >= 0.0 and screen.x <= size.x and screen.y >= 0.0 and screen.y <= size.y
	(
		assert_bool(ok)
		. override_failure_message("%s at %s is outside the %s screen" % [label, screen, size])
		. is_true()
	)


func _assert_framing(size: Vector2i) -> void:
	(
		assert_float(_measured_share(size))
		. override_failure_message("width share at %s" % size)
		. is_equal_approx(_expected_share(size), SHARE_TOLERANCE)
	)
	var exterior: Vector3 = Rig.exterior_m()
	var trim: float = 0.01
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			for y: float in [-Rig.glass_m(), Rig.interior_m().y + trim]:
				var corner: Vector3 = Vector3(sx * exterior.x / 2.0, y, sz * exterior.z / 2.0)
				_assert_on_screen(_tank().transform * corner, size, "tank corner %s" % corner)
		_assert_on_screen(
			Vector3(sx * CABINET_TOP_FRONT.x, CABINET_TOP_FRONT.y, CABINET_TOP_FRONT.z),
			size,
			"cabinet top front corner"
		)


# --- AC 9: constants ---


func test_ac09_named_constants_hold_the_camera_spec_values() -> void:
	assert_float(Api.room_constant("CAMERA_HFOV_DEG")).is_equal_approx(50.0, 0.0001)
	assert_float(Api.room_constant("CAMERA_ELEVATION_DEG")).is_equal_approx(5.0, 0.0001)
	assert_float(Api.room_constant("CAMERA_WIDTH_SHARE")).is_equal_approx(0.85, 0.0001)
	assert_float(Api.room_constant("CAMERA_MAX_KEEP_WIDTH_ASPECT")).is_equal_approx(
		WIDE_REFERENCE, 0.0001
	)


# --- AC 9: pivot, elevation, distance ---


func test_ac09_camera_looks_at_the_water_centre_from_5_degrees_at_the_computed_distance() -> void:
	await _open(Vector2i(1920, 1080))
	var water: Node3D = _tank().get_node("WaterVolume") as Node3D
	var camera: Camera3D = _camera()
	var pivot: Vector3 = water.global_position
	var direction: Vector3 = (pivot - camera.global_position).normalized()
	assert_float(direction.y).is_equal_approx(-sin(deg_to_rad(5.0)), 0.002)
	assert_float(camera.global_position.x).is_equal_approx(pivot.x, 0.001)
	assert_float(camera.global_position.z).is_greater(pivot.z)
	var exterior: Vector3 = Rig.exterior_m()
	var distance: float = Api.default_distance(
		exterior.x,
		exterior.z,
		Api.room_constant("CAMERA_HFOV_DEG"),
		Api.room_constant("CAMERA_ELEVATION_DEG"),
		Api.room_constant("CAMERA_WIDTH_SHARE")
	)
	assert_float(camera.global_position.distance_to(pivot)).is_equal_approx(distance, 0.001)
	var centre: Vector2 = camera.unproject_position(pivot)
	assert_float(centre.x).is_equal_approx(960.0, 1.5)
	assert_float(centre.y).is_equal_approx(540.0, 1.5)


# --- AC 9: projection rule ---


func test_ac09_16_9_uses_keep_width_with_the_50_degree_fov() -> void:
	await _open(Vector2i(1920, 1080))
	assert_int(_camera().keep_aspect).is_equal(Camera3D.KEEP_WIDTH)
	assert_float(_camera().fov).is_equal_approx(50.0, 0.01)


func test_ac09_wider_than_16_9_keeps_the_16_9_picture_height() -> void:
	await _open(Vector2i(2560, 1080))
	var vertical: float = rad_to_deg(2.0 * atan(tan(deg_to_rad(25.0)) * 9.0 / 16.0))
	assert_int(_camera().keep_aspect).is_equal(Camera3D.KEEP_HEIGHT)
	assert_float(_camera().fov).is_equal_approx(vertical, 0.05)


func test_ac09_framing_at_16_9() -> void:
	await _open(Vector2i(1920, 1080))
	_assert_framing(Vector2i(1920, 1080))


func test_ac09_framing_at_16_10() -> void:
	await _open(Vector2i(1920, 1200))
	_assert_framing(Vector2i(1920, 1200))


func test_ac09_framing_at_4_3() -> void:
	await _open(Vector2i(1600, 1200))
	_assert_framing(Vector2i(1600, 1200))


func test_ac09_framing_at_21_9() -> void:
	await _open(Vector2i(2560, 1080))
	_assert_framing(Vector2i(2560, 1080))
	assert_float(_measured_share(Vector2i(2560, 1080))).is_equal_approx(0.648, SHARE_TOLERANCE)


func test_ac09_framing_on_a_wider_ultrawide_screen() -> void:
	await _open(Vector2i(3440, 1440))
	_assert_framing(Vector2i(3440, 1440))


func test_ac09_framing_on_a_square_window() -> void:
	await _open(Vector2i(1000, 1000))
	_assert_framing(Vector2i(1000, 1000))


func test_ac09_resizing_the_viewport_re_applies_the_rule() -> void:
	await _open(Vector2i(1920, 1080))
	for size: Vector2i in [Vector2i(2560, 1080), Vector2i(1600, 1200), Vector2i(1366, 768)]:
		_viewport.size = size
		await get_tree().process_frame
		await get_tree().process_frame
		_assert_framing(size)


# --- AC 13 ---


func test_ac13_entering_the_tree_logs_no_error_or_warning() -> void:
	var made: Array[Node3D] = []
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void:
			var room: Node3D = Rig.instantiate(AquariumModel.new(), Rig.default_catalog())
			add_child(room)
			made.append(room)
			await get_tree().process_frame
	)
	auto_free(made[0])
	assert_bool(ResourceLoader.exists(Rig.ROOM_SCENE)).is_true()
	assert_that(Rig.displayed_id(made[0])).is_equal(&"tank_medium_60l")
	assert_dict(seen["errors"]).is_empty()
	assert_dict(seen["warnings"]).is_empty()


func test_ac13_room_without_setup_builds_from_the_defaults_without_logging() -> void:
	var made: Array[Node] = []
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void:
			var scene: PackedScene = load(Rig.ROOM_SCENE) as PackedScene
			var room: Node = scene.instantiate() if scene != null else Node3D.new()
			add_child(room)
			made.append(room)
			await get_tree().process_frame
	)
	auto_free(made[0])
	assert_dict(seen["errors"]).is_empty()
	assert_dict(seen["warnings"]).is_empty()
	assert_that(Rig.displayed_id(made[0])).is_equal(&"tank_medium_60l")


func test_ac13_exactly_one_camera_is_active_and_it_is_the_placeholder() -> void:
	await _open(Vector2i(1920, 1080))
	var current: int = 0
	var stack: Array[Node] = [_room]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Camera3D and (node as Camera3D).current:
			current += 1
		stack.append_array(node.get_children())
	assert_int(current).is_equal(1)
	assert_object(_viewport.get_camera_3d()).is_same(_camera())
	assert_str(String(_camera().name)).is_equal("PlaceholderCamera")
