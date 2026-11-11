# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #26 criteria 11, 15 and 17 (owner: developer): the room gives the build camera its pan box and
## its solids. The lamp zone (medium tank, 0.6x, pivot at the rim, azimuth 90, elevations 5 to 20
## degrees), a missing or hidden lamp, a room without a tank, and the walls that are not obstacles.
## The expected solids are built from the catalog numbers and the lamp scene (CameraZoomRig), not
## from CameraSolids.

const Cz := preload("res://tests/helpers/camera_zoom_rig.gd")
const Cam := preload("res://tests/helpers/camera_rig.gd")
const Api := preload("res://tests/helpers/late_api.gd")
const Rig := preload("res://tests/helpers/room_rig.gd")
const Glb := preload("res://tests/helpers/glb_mesh_checks.gd")
const Table := preload("res://tests/helpers/tank_table.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")
const OrbitApi := preload("res://tests/helpers/orbit_api.gd")

const LAMP_ELEVATIONS: Array[float] = [5.0, 8.0, 10.0, 11.0, 12.0, 15.0, 20.0]
## One elevation of the lamp zone where only the lamp holds the camera (above the tank solid).
const LAMP_ONLY_ELEVATION := 10.0
const VARIANT_ID := &"tank_variant_lamp"

var _viewport: SubViewport = null
var _room: Node3D = null
var _camera: Camera3D = null
var _default: float = 0.0
var _home: Vector3 = Vector3.ZERO


func _bind(viewport: SubViewport, room: Node3D) -> bool:
	_viewport = viewport
	_room = room
	_camera = Cam.camera_of(room)
	if _camera == null:
		fail("the room has no BuildCamera")
		return false
	Cam.freeze(room)
	_default = Cam.t_dist(_camera)
	_home = Cam.t_pivot(_camera)
	return Cz.require_api(self, _camera)


func _open_medium() -> bool:
	var rig: Dictionary = await Cz.open_tank(self, Table.MEDIUM)
	if not rig["ok"]:
		return false
	return _bind(rig["viewport"], rig["room"])


## The room of a catalog with one variant of the medium tank, built while the engine output is
## captured. Returns false when it logged anything.
func _open_variant(definition: Resource, size: Vector2i = Cam.SIZE_16_9) -> bool:
	var catalog: RefCounted = Api.catalog_from([definition])
	var model: AquariumModel = Rig.model_with(definition.get("id"))
	var viewport: SubViewport = SubViewport.new()
	viewport.size = size
	add_child(viewport)
	auto_free(viewport)
	var made: Array[Node3D] = []
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void:
			var room: Node3D = Rig.instantiate(model, catalog)
			viewport.add_child(room)
			made.append(room)
			await get_tree().process_frame
	)
	assert_dict(seen["errors"]).is_empty()
	assert_dict(seen["warnings"]).is_empty()
	assert_dict(seen["script_errors"]).is_empty()
	return _bind(viewport, made[0])


## The medium tank as a variant with its own id; the tank scene is the default one.
func _variant() -> Resource:
	var definition: Resource = Rig.variant(VARIANT_ID, Rig.default_definition().get("scene"))
	return definition


func _lamp_pivot() -> Vector3:
	var pan: AABB = Cz.pan_box(Table.MEDIUM, Cz.stand_z(_room))
	return Vector3(pan.position.x, pan.end.y, pan.get_center().z)


func _lamp_zone_pose(elevation: float, distance: float) -> void:
	Cz.pose(_camera, 90.0, elevation, distance, _lamp_pivot())


# --- AC 11: the lamp zone ---


func test_ac11_the_pivot_at_the_rim_is_the_top_of_the_pan_box() -> void:
	if not await _open_medium():
		return
	assert_float(_lamp_pivot().y).is_equal_approx(1.085, 0.0005)
	assert_float(_default).is_equal_approx(0.924, 0.01)


func test_ac11_in_the_lamp_zone_the_camera_is_outside_the_lamp_box_and_feet_plus_margin() -> void:
	if not await _open_medium():
		return
	var boxes: Array[AABB] = Cz.solids(_room, Table.MEDIUM)
	var lamp: Array[AABB] = Cz.lamp_boxes(_room)
	assert_int(lamp.size()).is_greater_equal(2)
	var failures: PackedStringArray = PackedStringArray()
	for elevation: float in LAMP_ELEVATIONS:
		_lamp_zone_pose(elevation, Cz.zoom_in_distance(_default))
		failures.append_array(Cz.pose_failures(_camera, boxes, "el %s" % elevation))
		if Cz.inside_any(lamp, Cz.margin(), _camera.global_position):
			failures.append("el %s: inside the lamp plus margin" % elevation)
	assert_array(failures).override_failure_message(Cz.summary(failures)).is_empty()


func test_ac11_the_lamp_really_holds_the_camera_at_about_ten_degrees() -> void:
	if not await _open_medium():
		return
	var lamp: Array[AABB] = Cz.lamp_boxes(_room)
	var requested: float = Cz.zoom_in_distance(_default)
	_lamp_zone_pose(LAMP_ONLY_ELEVATION, requested)
	var target_wanted: Vector3 = (
		_lamp_pivot() + OrbitApi.offset(90.0, LAMP_ONLY_ELEVATION, requested)
	)
	assert_bool(Cz.inside_any(lamp, Cz.margin(), target_wanted, 0.001)).is_true()
	assert_bool(Cz.inside_any(lamp, Cz.margin(), _camera.global_position)).is_false()
	assert_bool(Cz.is_held(_camera)).is_true()
	assert_float(Cz.held_dist(_camera)).is_greater(requested + 0.01)
	var tank: Array[AABB] = [Cz.tank_box(Table.MEDIUM, Cz.stand_z(_room))]
	assert_bool(Cz.inside_any(tank, Cz.margin(), target_wanted, 0.001)).is_false()


func test_ac11_at_85_degrees_over_the_tank_the_camera_is_above_the_lamp_and_not_held() -> void:
	if not await _open_medium():
		return
	var lamp: Array[AABB] = Cz.lamp_boxes(_room)
	var top: float = -INF
	for box: AABB in lamp:
		top = maxf(top, box.end.y)
	_lamp_zone_pose(85.0, Cz.zoom_in_distance(_default))
	assert_float(_camera.global_position.y).is_greater_equal(top + Cz.margin() - Cz.LENGTH_M)
	assert_bool(Cz.is_held(_camera)).is_false()
	assert_float(Cz.held_dist(_camera)).is_equal_approx(Cam.dist(_camera), Cz.LENGTH_M)
	assert_float(Cam.el(_camera)).is_equal_approx(85.0, Cz.ANGLE_DEG)


func test_ac11_a_camera_asked_into_the_lamp_is_held_outside_it_on_every_tank() -> void:
	var hits: int = 0
	for id: StringName in Table.IDS:
		var rig: Dictionary = await Cz.open_tank(self, id)
		if not rig["ok"]:
			return
		var room: Node3D = rig["room"]
		var camera: Camera3D = rig["camera"]
		var lamp: Array[AABB] = Cz.lamp_boxes(room)
		assert_int(lamp.size()).is_greater_equal(2)
		var pan: AABB = Cz.pan_box(id, Cz.stand_z(room))
		var pivot: Vector3 = Vector3(pan.position.x, pan.end.y, pan.get_center().z)
		var requested: float = Cz.zoom_in_distance(rig["default_distance"])
		Cz.pose(camera, 90.0, LAMP_ONLY_ELEVATION, requested, pivot)
		var wanted: Vector3 = pivot + OrbitApi.offset(90.0, LAMP_ONLY_ELEVATION, requested)
		if Cz.inside_any(lamp, Cz.margin(), wanted, 0.001):
			hits += 1
			assert_bool(Cz.is_held(camera)).is_true()
			assert_bool(Cz.inside_any(lamp, Cz.margin(), camera.global_position)).is_false()
	assert_int(hits).is_greater_equal(1)


# --- AC 11: no lamp solid ---


func _held_in_the_lamp_zone() -> bool:
	_lamp_zone_pose(LAMP_ONLY_ELEVATION, Cz.zoom_in_distance(_default))
	return Cz.is_held(_camera)


func _assert_no_lamp_solid() -> void:
	assert_bool(_held_in_the_lamp_zone()).is_false()
	assert_float(Cz.held_dist(_camera)).is_equal_approx(Cam.dist(_camera), Cz.LENGTH_M)
	assert_array(Cam.basis_failures(_camera, Cam.pivot(_camera))).is_empty()


func test_ac11_the_real_room_holds_the_camera_in_the_lamp_zone_as_the_baseline() -> void:
	if not await _open_medium():
		return
	assert_bool(_held_in_the_lamp_zone()).is_true()


func test_ac11_a_room_whose_lamp_scene_is_missing_has_no_lamp_solid_and_no_error() -> void:
	var definition: Resource = _variant()
	definition.set("lamp_scene", null)
	if not await _open_variant(definition):
		return
	_assert_no_lamp_solid()


func test_ac11_a_room_whose_tank_has_no_lamp_mount_has_no_lamp_solid_and_no_error() -> void:
	var definition: Resource = _variant()
	var scene: PackedScene = definition.get("scene")
	var tank: Node = scene.instantiate()
	var mount: Node = tank.get_node_or_null("lamp_mount")
	assert_bool(mount != null).is_true()
	if mount != null:
		tank.remove_child(mount)
		mount.free()
	var packed: PackedScene = PackedScene.new()
	assert_int(packed.pack(tank)).is_equal(OK)
	tank.free()
	definition.set("scene", packed)
	if not await _open_variant(definition):
		return
	_assert_no_lamp_solid()


func test_ac11_a_room_with_a_hidden_lamp_has_no_lamp_solid_and_no_error() -> void:
	var definition: Resource = _variant()
	var lamp_scene: PackedScene = definition.get("lamp_scene")
	var lamp: Node3D = lamp_scene.instantiate() as Node3D
	lamp.visible = false
	var packed: PackedScene = PackedScene.new()
	assert_int(packed.pack(lamp)).is_equal(OK)
	lamp.free()
	definition.set("lamp_scene", packed)
	if not await _open_variant(definition):
		return
	assert_bool(_room.get_node("Lamp").is_visible_in_tree()).is_false()
	_assert_no_lamp_solid()


func test_ac11_hiding_the_lamp_node_of_a_running_room_does_not_break_the_camera() -> void:
	if not await _open_medium():
		return
	(_room.get_node("Lamp") as Node3D).visible = false
	_lamp_zone_pose(LAMP_ONLY_ELEVATION, Cz.zoom_in_distance(_default))
	for frame: int in 30:
		Cam.step(_camera, Cz.FRAME_S)
	assert_array(Cam.basis_failures(_camera, Cam.pivot(_camera))).is_empty()
	assert_float(_camera.global_position.y).is_greater_equal(Table.CABINET_TOP_M - Cz.LENGTH_M)


# --- AC 15: the walls are not obstacles ---


func test_ac15_behind_the_back_wall_the_camera_is_not_held_and_the_cutaway_hides_the_wall() -> void:
	for id: StringName in Table.IDS:
		var rig: Dictionary = await Cz.open_tank(self, id)
		if not rig["ok"]:
			return
		var room: Node3D = rig["room"]
		var camera: Camera3D = rig["camera"]
		Cam.pose(room, 180.0, 5.0)
		assert_float(camera.global_position.z).is_less(Cam.BACK_PLANE_Z_M)
		assert_bool(Cz.is_held(camera)).is_false()
		assert_float(Cz.held_dist(camera)).is_equal_approx(Cam.dist(camera), Cz.LENGTH_M)
		assert_bool(Cam.walls_of(room).call("is_hidden_target", &"back")).is_true()
		assert_float(Cam.dist(camera)).is_equal_approx(rig["default_distance"], Cz.LENGTH_M)


func test_ac15_behind_the_left_wall_the_camera_is_not_held_and_the_cutaway_hides_the_wall() -> void:
	for id: StringName in Table.IDS:
		var rig: Dictionary = await Cz.open_tank(self, id)
		if not rig["ok"]:
			return
		var room: Node3D = rig["room"]
		var camera: Camera3D = rig["camera"]
		Cam.pose(room, 270.0, 5.0)
		assert_float(camera.global_position.x).is_less(Cam.LEFT_PLANE_X_M)
		assert_bool(Cz.is_held(camera)).is_false()
		assert_float(Cz.held_dist(camera)).is_equal_approx(Cam.dist(camera), Cz.LENGTH_M)
		assert_bool(Cam.walls_of(room).call("is_hidden_target", &"left")).is_true()


func test_ac15_zoomed_out_behind_the_walls_the_camera_still_goes_where_it_is_asked() -> void:
	if not await _open_medium():
		return
	Cz.pose(_camera, 180.0, 5.0, Cz.zoom_out_distance(_default), _home)
	assert_bool(Cz.is_held(_camera)).is_false()
	assert_float((_camera.global_position - _home).length()).is_equal_approx(
		Cz.zoom_out_distance(_default), Cz.LENGTH_M
	)


# --- AC 17: no tank displayed ---


func _no_tank_definition() -> Resource:
	return Rig.variant(Rig.DEFAULT_ID, null)


func _open_without_tank() -> bool:
	var definition: Resource = _no_tank_definition()
	var catalog: RefCounted = Api.catalog_from([definition])
	var model: AquariumModel = Rig.model_with(Rig.DEFAULT_ID)
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Cam.SIZE_16_9
	add_child(viewport)
	auto_free(viewport)
	var made: Array[Node3D] = []
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void:
			var room: Node3D = Rig.instantiate(model, catalog)
			viewport.add_child(room)
			made.append(room)
			await get_tree().process_frame
	)
	# One error for the broken default tank is expected; nothing else, and no script error.
	assert_dict(seen["script_errors"]).is_empty()
	assert_dict(seen["warnings"]).is_empty()
	assert_int(seen["errors"].size()).is_less_equal(1)
	return _bind(viewport, made[0])


func test_ac17_without_a_tank_pan_has_no_effect() -> void:
	if not await _open_without_tank():
		return
	assert_object(_room.get_node_or_null("Tank")).is_null()
	var pivot: Vector3 = Cam.t_pivot(_camera)
	Cz.pan(_viewport, Vector2(-Cz.HUGE, Cz.HUGE))
	assert_vector(Cam.t_pivot(_camera)).is_equal_approx(pivot, Vector3.ONE * 0.000001)
	Cz.pan(_viewport, Vector2(40.0, 20.0))
	assert_vector(Cam.t_pivot(_camera)).is_equal_approx(pivot, Vector3.ONE * 0.000001)
	Cam.step(_camera, 1.0)
	assert_vector(Cam.pivot(_camera)).is_equal_approx(pivot, Vector3.ONE * 0.000001)


func test_ac17_without_a_tank_zoom_works_within_the_limits_of_the_default_distance() -> void:
	if not await _open_without_tank():
		return
	assert_float(_default).is_greater(0.0)
	Cz.wheel(_viewport, true)
	assert_float(Cam.t_dist(_camera)).is_equal_approx(
		_default * Cz.setting("zoom_step_factor"), Cz.LENGTH_M
	)
	Cz.wheel(_viewport, true, Cz.HUGE)
	assert_float(Cam.t_dist(_camera)).is_equal_approx(Cz.zoom_in_distance(_default), Cz.LENGTH_M)
	Cz.wheel(_viewport, false, Cz.HUGE)
	assert_float(Cam.t_dist(_camera)).is_equal_approx(Cz.zoom_out_distance(_default), Cz.LENGTH_M)


func test_ac17_without_a_tank_the_cabinet_and_floor_rules_still_apply() -> void:
	if not await _open_without_tank():
		return
	var cabinet: Node3D = _room.get_node("Cabinet") as Node3D
	var box: AABB = Glb.scene_bounds_in(cabinet, _room)
	var boxes: Array[AABB] = [box]
	var failures: PackedStringArray = PackedStringArray()
	for azimuth: float in [0.0, 90.0, 180.0, 270.0]:
		for elevation: float in [-90.0, 5.0, 85.0]:
			Cz.pose(_camera, azimuth, elevation, Cz.zoom_in_distance(_default), _home)
			failures.append_array(
				Cz.pose_failures(_camera, boxes, "az %s el %s" % [azimuth, elevation])
			)
			for frame: int in 20:
				Cam.step(_camera, Cz.FRAME_S)
			failures.append_array(
				Cz.pose_failures(_camera, boxes, "later az %s el %s" % [azimuth, elevation])
			)
	assert_array(failures).override_failure_message(Cz.summary(failures)).is_empty()


func test_ac17_without_a_tank_home_and_the_frames_do_not_crash() -> void:
	if not await _open_without_tank():
		return
	Cz.wheel(_viewport, true, Cz.HUGE)
	Cam.set_orbit(_camera, 250.0, 40.0, false)
	Cam.step(_camera, 0.5)
	Cz.home_key(_viewport)
	Cam.settle(_camera)
	assert_float(Cam.dist(_camera)).is_equal_approx(_default, Cz.LENGTH_M)
	assert_vector(Cam.pivot(_camera)).is_equal_approx(_home, Vector3.ONE * Cz.LENGTH_M)


func test_ac17_without_any_definition_nothing_crashes() -> void:
	var catalog: RefCounted = Api.catalog_from([])
	var model: AquariumModel = Rig.model_with(&"tank_60")
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Cam.SIZE_16_9
	add_child(viewport)
	auto_free(viewport)
	var made: Array[Node3D] = []
	var seen: Dictionary = await EngineOutput.capture_all(
		func() -> void:
			var room: Node3D = Rig.instantiate(model, catalog)
			viewport.add_child(room)
			made.append(room)
			await get_tree().process_frame
	)
	assert_dict(seen["script_errors"]).is_empty()
	if not _bind(viewport, made[0]):
		return
	var pivot: Vector3 = Cam.t_pivot(_camera)
	Cz.pan(_viewport, Vector2(-Cz.HUGE, Cz.HUGE))
	assert_vector(Cam.t_pivot(_camera)).is_equal_approx(pivot, Vector3.ONE * 0.000001)
	Cz.wheel(_viewport, true, Cz.HUGE)
	Cam.settle(_camera)
	assert_float(Cam.dist(_camera)).is_equal_approx(Cz.zoom_in_distance(_default), Cz.LENGTH_M)
	assert_float(_camera.global_position.y).is_greater_equal(Table.CABINET_TOP_M - Cz.LENGTH_M)
