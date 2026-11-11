# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #22 criteria 9 and 13 and #24 criterion 13 (owner: developer): the default camera framing at
## several aspect ratios for each tank (ADR 0005, ADR 0006 option A "Camera backs off") and a clean
## load. The default distance is the larger of the width distance (85% of the screen width) and
## the vertical-fit distance (tank exterior, rim trim and the front edge of the cabinet top inside
## the 16:9 vertical field of view with a 2% margin of the half screen height). Medium and large
## keep 85%; the small tank backs off to about 77% at 16:9 (and keeps that distance at 16:10 and
## 4:3). The room lives in a SubViewport so the aspect ratio can be chosen per test. The fit is
## measured on the real camera; the function name in CameraFraming is the developer's choice.

const Api := preload("res://tests/helpers/late_api.gd")
const Rig := preload("res://tests/helpers/room_rig.gd")
const Glb := preload("res://tests/helpers/glb_mesh_checks.gd")
const Table := preload("res://tests/helpers/tank_table.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")

const WIDE_REFERENCE := 16.0 / 9.0
const SHARE_TOLERANCE := 0.02
const FIT_MARGIN := 0.02
const FIT_TOLERANCE := 0.01
const SMALL_SHARE_AT_16_9 := 0.77
const ASPECT_SIZES: Array[Vector2i] = [
	Vector2i(1920, 1080), Vector2i(1920, 1200), Vector2i(1600, 1200)
]

var _viewport: SubViewport = null
var _room: Node3D = null


func _open(size: Vector2i, id: StringName = Table.MEDIUM) -> void:
	(
		assert_bool(ResourceLoader.exists(Rig.ROOM_SCENE))
		. override_failure_message("room scene missing: %s" % Rig.ROOM_SCENE)
		. is_true()
	)
	if _viewport != null and is_instance_valid(_viewport):
		_viewport.free()
	_viewport = SubViewport.new()
	_viewport.size = size
	add_child(_viewport)
	auto_free(_viewport)
	_room = Rig.instantiate(Rig.model_with(id), Rig.default_catalog())
	_viewport.add_child(_room)
	await get_tree().process_frame


func _camera() -> Camera3D:
	return _room.get_node("BuildCamera") as Camera3D


func _tank() -> Node3D:
	return _room.get_node("Tank") as Node3D


func _expected_share(size: Vector2i) -> float:
	var aspect: float = float(size.x) / float(size.y)
	if aspect <= WIDE_REFERENCE + 0.0001:
		return Api.room_constant("CAMERA_WIDTH_SHARE")
	return Api.room_constant("CAMERA_WIDTH_SHARE") * WIDE_REFERENCE / aspect


## Share of the screen width between the front corners of the exterior glass at pivot height.
func _measured_share(size: Vector2i, id: StringName) -> float:
	var exterior: Vector3 = Table.exterior(id)
	var pivot_y: float = Table.water_line(id) / 2.0
	var left: Vector2 = _camera().unproject_position(
		_tank().transform * Vector3(-exterior.x / 2.0, pivot_y, exterior.z / 2.0)
	)
	var right: Vector2 = _camera().unproject_position(
		_tank().transform * Vector3(exterior.x / 2.0, pivot_y, exterior.z / 2.0)
	)
	return absf(right.x - left.x) / float(size.x)


## The points that must stay on screen: the eight corners of the tank exterior including the rim
## trim, and the two front corners of the cabinet top.
func _framed_points(id: StringName) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var exterior: Vector3 = Table.exterior(id)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			for y: float in [-Table.glass(id), Table.interior(id).y + Table.TRIM_M]:
				var corner: Vector3 = Vector3(sx * exterior.x / 2.0, y, sz * exterior.z / 2.0)
				points.append(_tank().transform * corner)
	var cabinet: AABB = Glb.scene_bounds_in(_room.get_node("Cabinet") as Node3D, _room)
	for sx: float in [-1.0, 1.0]:
		points.append(Vector3(sx * cabinet.end.x, cabinet.end.y, cabinet.end.z))
	return points


## The largest |y| of the framed points in units of the half screen height (0 = centre, 1 = edge).
func _worst_vertical(size: Vector2i, id: StringName) -> float:
	var worst: float = 0.0
	for point: Vector3 in _framed_points(id):
		var screen: Vector2 = _camera().unproject_position(point)
		worst = maxf(worst, absf(screen.y - size.y / 2.0) / (size.y / 2.0))
	return worst


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


## All framed points are on screen at this size.
func _assert_everything_on_screen(size: Vector2i, id: StringName) -> void:
	for point: Vector3 in _framed_points(id):
		_assert_on_screen(point, size, "%s point %s" % [id, point])


## The #22 rule (medium): the width share of the aspect ratio and everything on screen.
func _assert_framing(size: Vector2i, id: StringName = Table.MEDIUM) -> void:
	(
		assert_float(_measured_share(size, id))
		. override_failure_message("width share at %s" % size)
		. is_equal_approx(_expected_share(size), SHARE_TOLERANCE)
	)
	_assert_everything_on_screen(size, id)


# --- AC 9 (#22): constants ---


func test_ac09_named_constants_hold_the_camera_spec_values() -> void:
	assert_float(Api.room_constant("CAMERA_HFOV_DEG")).is_equal_approx(50.0, 0.0001)
	assert_float(Api.room_constant("CAMERA_ELEVATION_DEG")).is_equal_approx(5.0, 0.0001)
	assert_float(Api.room_constant("CAMERA_WIDTH_SHARE")).is_equal_approx(0.85, 0.0001)
	assert_float(Api.room_constant("CAMERA_MAX_KEEP_WIDTH_ASPECT")).is_equal_approx(
		WIDE_REFERENCE, 0.0001
	)


# --- AC 9 (#22): pivot, elevation, distance (medium) ---


func test_ac09_camera_looks_at_the_water_centre_from_5_degrees_at_the_computed_distance() -> void:
	await _open(Vector2i(1920, 1080))
	var water: Node3D = _tank().get_node("WaterVolume") as Node3D
	var camera: Camera3D = _camera()
	var pivot: Vector3 = water.global_position
	var direction: Vector3 = (pivot - camera.global_position).normalized()
	assert_float(direction.y).is_equal_approx(-sin(deg_to_rad(5.0)), 0.002)
	assert_float(camera.global_position.x).is_equal_approx(pivot.x, 0.001)
	assert_float(camera.global_position.z).is_greater(pivot.z)
	var exterior: Vector3 = Table.exterior(Table.MEDIUM)
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


# --- AC 9 (#22): projection rule ---


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
	assert_float(_measured_share(Vector2i(2560, 1080), Table.MEDIUM)).is_equal_approx(
		0.648, SHARE_TOLERANCE
	)


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


# --- #24 AC 13: each tank, ADR 0006 ---


func test_ac13_the_pivot_is_the_centre_of_the_water_volume_for_each_tank() -> void:
	for id: StringName in Table.IDS:
		await _open(Vector2i(1920, 1080), id)
		var pivot: Vector3 = (_tank().get_node("WaterVolume") as Node3D).global_position
		var camera: Camera3D = _camera()
		var direction: Vector3 = (pivot - camera.global_position).normalized()
		assert_float(direction.y).override_failure_message(id).is_equal_approx(
			-sin(deg_to_rad(5.0)), 0.002
		)
		assert_float(camera.global_position.x).is_equal_approx(pivot.x, 0.001)
		var centre: Vector2 = camera.unproject_position(pivot)
		assert_float(centre.x).is_equal_approx(960.0, 1.5)
		assert_float(centre.y).is_equal_approx(540.0, 1.5)


func test_ac13_distance_is_never_below_the_width_distance_of_85_percent() -> void:
	for id: StringName in Table.IDS:
		await _open(Vector2i(1920, 1080), id)
		var exterior: Vector3 = Table.exterior(id)
		var width_distance: float = Api.default_distance(
			exterior.x,
			exterior.z,
			Api.room_constant("CAMERA_HFOV_DEG"),
			Api.room_constant("CAMERA_ELEVATION_DEG"),
			Api.room_constant("CAMERA_WIDTH_SHARE")
		)
		var pivot: Vector3 = (_tank().get_node("WaterVolume") as Node3D).global_position
		var distance: float = _camera().global_position.distance_to(pivot)
		assert_float(distance).override_failure_message(id).is_greater_equal(width_distance - 0.001)


func test_ac13_medium_and_large_keep_the_width_distance_exactly() -> void:
	for id: StringName in [Table.MEDIUM, Table.LARGE]:
		await _open(Vector2i(1920, 1080), id)
		var exterior: Vector3 = Table.exterior(id)
		var width_distance: float = Api.default_distance(
			exterior.x,
			exterior.z,
			Api.room_constant("CAMERA_HFOV_DEG"),
			Api.room_constant("CAMERA_ELEVATION_DEG"),
			Api.room_constant("CAMERA_WIDTH_SHARE")
		)
		var pivot: Vector3 = (_tank().get_node("WaterVolume") as Node3D).global_position
		(
			assert_float(_camera().global_position.distance_to(pivot))
			. override_failure_message(id)
			. is_equal_approx(width_distance, 0.001)
		)


func test_ac13_medium_and_large_fill_85_percent_of_the_width_at_16_9_16_10_and_4_3() -> void:
	for id: StringName in [Table.MEDIUM, Table.LARGE]:
		for size: Vector2i in ASPECT_SIZES:
			await _open(size, id)
			(
				assert_float(_measured_share(size, id))
				. override_failure_message("%s width share at %s" % [id, size])
				. is_equal_approx(0.85, SHARE_TOLERANCE)
			)


func test_ac13_every_tank_trim_and_cabinet_front_edge_are_on_screen_at_16_9_16_10_and_4_3() -> void:
	for id: StringName in Table.IDS:
		for size: Vector2i in ASPECT_SIZES:
			await _open(size, id)
			_assert_everything_on_screen(size, id)


func test_ac13_every_tank_keeps_the_2_percent_margin_at_16_9() -> void:
	for id: StringName in Table.IDS:
		await _open(Vector2i(1920, 1080), id)
		(
			assert_float(_worst_vertical(Vector2i(1920, 1080), id))
			. override_failure_message("%s is closer than 2%% to the top or bottom edge" % id)
			. is_less_equal(1.0 - FIT_MARGIN + 0.002)
		)


func test_ac13_the_small_tank_backs_off_below_85_percent_to_about_77_percent_at_16_9() -> void:
	await _open(Vector2i(1920, 1080), Table.SMALL)
	var share: float = _measured_share(Vector2i(1920, 1080), Table.SMALL)
	assert_float(share).is_less(0.85 - 0.01)
	assert_float(share).is_equal_approx(SMALL_SHARE_AT_16_9, SHARE_TOLERANCE)


func test_ac13_the_small_tank_backs_off_no_further_than_needed_it_touches_the_margin() -> void:
	await _open(Vector2i(1920, 1080), Table.SMALL)
	(
		assert_float(_worst_vertical(Vector2i(1920, 1080), Table.SMALL))
		. override_failure_message(
			"the trim top or the cabinet front edge must sit on the 2% margin"
		)
		. is_equal_approx(1.0 - FIT_MARGIN, FIT_TOLERANCE)
	)


func test_ac13_the_small_tank_keeps_its_16_9_distance_at_16_10_and_4_3() -> void:
	await _open(Vector2i(1920, 1080), Table.SMALL)
	var reference: float = _measured_share(Vector2i(1920, 1080), Table.SMALL)
	for size: Vector2i in [Vector2i(1920, 1200), Vector2i(1600, 1200)]:
		await _open(size, Table.SMALL)
		(
			assert_float(_measured_share(size, Table.SMALL))
			. override_failure_message("small share at %s" % size)
			. is_equal_approx(reference, 0.005)
		)


# --- AC 13 (#22): a clean load ---


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
	assert_that(Rig.displayed_id(made[0])).is_equal(Table.MEDIUM)
	assert_dict(seen["errors"]).is_empty()
	assert_dict(seen["warnings"]).is_empty()


func test_ac13_every_tank_enters_the_tree_without_logging() -> void:
	for id: StringName in Table.IDS:
		var made: Array[Node3D] = []
		var seen: Dictionary = await EngineOutput.capture(
			func() -> void:
				var room: Node3D = Rig.instantiate(Rig.model_with(id), Rig.default_catalog())
				add_child(room)
				made.append(room)
				await get_tree().process_frame
		)
		auto_free(made[0])
		assert_that(Rig.displayed_id(made[0])).is_equal(id)
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
	assert_that(Rig.displayed_id(made[0])).is_equal(Table.MEDIUM)


func test_ac13_exactly_one_camera_is_active_and_it_is_the_build_camera() -> void:
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
	assert_str(String(_camera().name)).is_equal("BuildCamera")
