extends GdUnitTestSuite
## #26 criterion 13 and ADR 0009 rule 5 (owner: developer): a push-out is immediate, but a release
## (the obstruction ends, for example at a tank swap or the lamp edge) eases. In a frame that
## follows a held frame the shown distance may fall by at most damp_factor x the gap to the new
## held distance, and the camera is never inside a solid.

const Cz := preload("res://tests/helpers/camera_zoom_rig.gd")
const Cam := preload("res://tests/helpers/camera_rig.gd")
const Api := preload("res://tests/helpers/late_api.gd")
const Room := preload("res://tests/helpers/room_rig.gd")
const Table := preload("res://tests/helpers/tank_table.gd")
const OrbitApi := preload("res://tests/helpers/orbit_api.gd")

const SLACK_M := 0.002

## The largest raise measured per frame class, printed by each case.
var _largest: Dictionary = {}


func _shown(camera: Camera3D) -> float:
	return (camera.global_position - Cam.pivot(camera)).length()


## Steps `frames` frames and returns the failures of the release rule and of the solids.
func _frames(
	camera: Camera3D, room: Node3D, id: StringName, frames: int, label: String
) -> PackedStringArray:
	var boxes: Array[AABB] = Cz.solids(room, id)
	var factor: float = OrbitApi.damp_factor(Cz.FRAME_S, OrbitApi.setting("damping_time_s"))
	var failures: PackedStringArray = PackedStringArray()
	var previous: float = _shown(camera)
	var was_held: bool = Cz.is_held(camera)
	var release_run: int = 0
	_largest = {Cz.STEADY: 0.0, Cz.RELEASE: 0.0, Cz.NEITHER: 0.0}
	for frame: int in frames:
		Cam.step(camera, Cz.FRAME_S)
		var where: String = "%s frame %d" % [label, frame]
		var frame_class: String = Cz.frame_class(camera, boxes)
		var raise_deg: float = Cz.raise_deg(camera)
		_largest[frame_class] = maxf(_largest[frame_class], raise_deg)
		release_run = release_run + 1 if frame_class == Cz.RELEASE else 0
		if raise_deg < -Cz.ANGLE_DEG:
			failures.append("%s: shown elevation lowered by %.4f degrees" % [where, raise_deg])
		if frame_class == Cz.STEADY and raise_deg > 0.1 + Cz.ANGLE_DEG:
			failures.append("%s: steady held raise %.4f degrees" % [where, raise_deg])
		if frame_class == Cz.RELEASE and raise_deg > Cz.RELEASE_RAISE_LIMIT_DEG:
			failures.append("%s: release raise %.4f degrees" % [where, raise_deg])
		if release_run > Cz.RELEASE_RUN_LIMIT_FRAMES:
			failures.append("%s: release lasts %d frames" % [where, release_run])
		if frame_class == Cz.NEITHER and absf(raise_deg) > Cz.ANGLE_DEG:
			failures.append(
				"%s: raised by %.4f degrees, neither held nor releasing" % [where, raise_deg]
			)
		if Cz.inside_any(boxes, Cz.margin(), camera.global_position):
			failures.append("%s: inside a solid" % where)
		if camera.global_position.y < Cz.CABINET_TOP_M - Cz.LENGTH_M:
			failures.append(
				(
					"%s: camera height %.5f is below the cabinet top"
					% [where, camera.global_position.y]
				)
			)
		var shown: float = _shown(camera)
		if was_held and shown < previous - SLACK_M:
			var goal: float = Cz.oracle_held(
				boxes, Cz.margin(), Cam.pivot(camera), Cz.shown_direction(camera), Cam.dist(camera)
			)
			var floor_m: float = previous - factor * (previous - goal) - SLACK_M
			if shown < floor_m:
				failures.append(
					(
						"%s: distance fell from %.4f to %.4f, the damped floor is %.4f"
						% [where, previous, shown, floor_m]
					)
				)
		previous = shown
		was_held = Cz.is_held(camera)
	print("RAISE_MAX ", label, " ", _largest)
	return failures


func test_ac13_a_held_camera_released_by_a_tank_swap_eases_in_without_a_pop() -> void:
	var model: AquariumModel = Room.model_with(Table.LARGE)
	var history: CommandHistory = CommandHistory.new()
	var rig: Dictionary = await Cz.open(self, model, Cam.SIZE_16_9, Table.LARGE)
	if not rig["ok"]:
		return
	var room: Node3D = rig["room"]
	var camera: Camera3D = rig["camera"]
	var pan: AABB = Cz.pan_box(Table.LARGE, Cz.stand_z(room))
	var pivot: Vector3 = (
		Cz.box_corner(pan, true, false, false) + Vector3(0.0, pan.size.y / 2.0, pan.size.z / 2.0)
	)
	Cz.pose(camera, 270.0, 5.0, Cz.zoom_in_distance(rig["default_distance"]), pivot)
	Cam.settle(camera)
	assert_bool(Cz.is_held(camera)).is_true()
	var catalog: RefCounted = Room.default_catalog()
	assert_bool(history.execute(Api.change_tank(model, catalog, Table.SMALL))).is_true()
	var failures: PackedStringArray = _frames(camera, room, Table.SMALL, 120, "large to small")
	assert_array(failures).override_failure_message(Cz.summary(failures)).is_empty()


func test_ac13_a_held_camera_panned_across_the_lamp_edge_eases_without_a_pop() -> void:
	var rig: Dictionary = await Cz.open_tank(self, Table.MEDIUM)
	if not rig["ok"]:
		return
	var room: Node3D = rig["room"]
	var camera: Camera3D = rig["camera"]
	var pan: AABB = Cz.pan_box(Table.MEDIUM, Cz.stand_z(room))
	var start: Vector3 = Vector3(pan.position.x, pan.end.y, pan.get_center().z)
	Cz.pose(camera, 90.0, 10.0, Cz.zoom_in_distance(rig["default_distance"]), start)
	Cam.settle(camera)
	assert_bool(Cz.is_held(camera)).is_true()
	var failures: PackedStringArray = PackedStringArray()
	for x: float in [pan.position.x + 0.15, pan.get_center().x, pan.end.x, pan.position.x]:
		Cz.set_pivot(camera, Vector3(x, pan.end.y, pan.get_center().z), false)
		failures.append_array(_frames(camera, room, Table.MEDIUM, 90, "lamp edge x %.2f" % x))
	assert_array(failures).override_failure_message(Cz.summary(failures)).is_empty()


## A held camera at the lowest elevation, pivot at a floor corner of the tank, released by a swap.
func _swap_failures(
	from_id: StringName, to_id: StringName, azimuth: float, high_x: bool
) -> PackedStringArray:
	var model: AquariumModel = Room.model_with(from_id)
	var history: CommandHistory = CommandHistory.new()
	var rig: Dictionary = await Cz.open(self, model, Cam.SIZE_16_9, from_id)
	if not rig["ok"]:
		return PackedStringArray(["camera API missing"])
	var room: Node3D = rig["room"]
	var camera: Camera3D = rig["camera"]
	var pan: AABB = Cz.pan_box(from_id, Cz.stand_z(room))
	var corner: Vector3 = Cz.box_corner(pan, high_x, false, false)
	Cz.pose(camera, azimuth, -90.0, Cz.zoom_in_distance(rig["default_distance"]), corner)
	Cam.settle(camera)
	assert_bool(Cz.is_held(camera)).is_true()
	assert_float(camera.global_position.y).is_greater_equal(Cz.CABINET_TOP_M - Cz.LENGTH_M)
	var catalog: RefCounted = Room.default_catalog()
	assert_bool(history.execute(Api.change_tank(model, catalog, to_id))).is_true()
	return _frames(camera, room, to_id, 150, "%s to %s az %s" % [from_id, to_id, azimuth])


func test_ac13_a_release_at_the_lowest_elevation_never_sinks_below_the_cabinet_top_right_corner(
) -> void:
	var failures: PackedStringArray = await _swap_failures(Table.LARGE, Table.SMALL, 270.0, true)
	assert_array(failures).override_failure_message(Cz.summary(failures)).is_empty()


func test_ac13_a_release_at_the_lowest_elevation_never_sinks_below_the_cabinet_top_left_corner(
) -> void:
	var failures: PackedStringArray = await _swap_failures(Table.LARGE, Table.SMALL, 90.0, false)
	assert_array(failures).override_failure_message(Cz.summary(failures)).is_empty()


func test_ac13_a_release_from_large_to_medium_never_sinks_below_the_cabinet_top() -> void:
	var failures: PackedStringArray = await _swap_failures(Table.LARGE, Table.MEDIUM, 270.0, true)
	assert_array(failures).override_failure_message(Cz.summary(failures)).is_empty()
