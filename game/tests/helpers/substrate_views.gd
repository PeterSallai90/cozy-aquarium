extends RefCounted
## The camera views of the #28 budget (technical plan v3, 1.4 and ADR 0011 rule 17): the default
## camera and the eight close-ups, defined once for the headless estimate and for the measure
## script (tests/measure/substrate_budget_measure.gd). All poses are tank-local: x across, y up
## from the inner floor, z towards the front glass. h is the fill depth S of the type, z_f the front
## inner glass plane, o the outer face of the front pane, g the glass thickness of the tank.

const Table := preload("res://tests/helpers/tank_table.gd")

const DEFAULT_VIEW := "default"
## The eight close-up views in the order of the plan.
const CLOSE_UPS: Array[String] = [
	"glass_close_front",
	"glass_close_back",
	"glass_close_left",
	"glass_close_right",
	"glass_35",
	"top_35",
	"top_12",
	"corner",
]
## Horizontal field of view in degrees at 16:9, near plane, far plane, as the build camera.
const FOV_DEG: float = 50.0
const NEAR_M: float = 0.03
const FAR_M: float = 100.0
const ASPECT: float = 16.0 / 9.0
## The room's default framing (RoomCorner constants): elevation, width share.
const DEFAULT_ELEVATION_DEG: float = 5.0
const DEFAULT_WIDTH_SHARE: float = 0.85


## Camera position and target of a close-up view for the tank and fill depth, or an empty
## dictionary for an unknown name.
static func close_up(view_name: String, tank_id: StringName, fill_depth_m: float) -> Dictionary:
	var interior: Vector3 = Table.interior(tank_id)
	var g: float = Table.glass(tank_id)
	var h: float = fill_depth_m
	var z_f: float = interior.z / 2.0
	var o: float = z_f + g
	var half_x: float = interior.x / 2.0
	match view_name:
		"glass_close_front":
			return _pose(Vector3(0.1, 0.8 * h, o + 0.12), Vector3(0.1, 0.42 * h, z_f))
		"glass_close_back":
			return _pose(Vector3(-0.1, 0.8 * h, -o - 0.12), Vector3(-0.1, 0.42 * h, -z_f))
		"glass_close_left":
			return _pose(Vector3(-half_x - g - 0.12, 0.8 * h, 0.0), Vector3(-half_x, 0.42 * h, 0.0))
		"glass_close_right":
			return _pose(Vector3(half_x + g + 0.12, 0.8 * h, 0.0), Vector3(half_x, 0.42 * h, 0.0))
		"glass_35":
			return _pose(Vector3(0.1, h + 0.045, o + 0.35), Vector3(0.1, 0.45 * h, z_f))
		"top_35":
			return _pose(Vector3(0.1, h + 0.35, 0.02), Vector3(0.1, h, -0.03))
		"top_12":
			return _pose(Vector3(0.1, h + 0.12, 0.12), Vector3(0.1, h, 0.04))
		"corner":
			return _pose(
				Vector3(-half_x - 0.22, h + 0.1, o + 0.22),
				Vector3(-half_x + 0.06, 0.5 * h, z_f - 0.06)
			)
	return {}


## The default camera: the pivot at half the water line above the floor, 5 degrees of elevation,
## the distance that makes the exterior width fill 85 % of the screen (CameraFraming).
static func default_view(tank_id: StringName) -> Dictionary:
	var exterior: Vector3 = Table.exterior(tank_id)
	var pivot: Vector3 = Vector3(0.0, Table.water_line(tank_id) / 2.0, 0.0)
	var distance: float = CameraFraming.default_distance(
		exterior.x, exterior.z, FOV_DEG, DEFAULT_ELEVATION_DEG, DEFAULT_WIDTH_SHARE
	)
	var position: Vector3 = CameraFraming.camera_position(pivot, distance, DEFAULT_ELEVATION_DEG)
	return _pose(position, pivot)


## {"position": Vector3, "target": Vector3} of a named view ("default" or a close-up).
static func pose_of(view_name: String, tank_id: StringName, fill_depth_m: float) -> Dictionary:
	if view_name == DEFAULT_VIEW:
		return default_view(tank_id)
	return close_up(view_name, tank_id, fill_depth_m)


## Every view name, the default camera first.
static func all_names() -> Array[String]:
	var names: Array[String] = [DEFAULT_VIEW]
	names.append_array(CLOSE_UPS)
	return names


static func transform_of(pose: Dictionary) -> Transform3D:
	var position: Vector3 = pose["position"]
	var target: Vector3 = pose["target"]
	var forward: Vector3 = (target - position).normalized()
	var up: Vector3 = Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.999 else Vector3.BACK
	return Transform3D(Basis.looking_at(forward, up), position)


## The six frustum planes in tank space with outward normals (a point is inside when it is not
## over any plane), the convention of Camera3D.get_frustum(): left, right, top, bottom, near, far.
static func frustum(pose: Dictionary) -> Array[Plane]:
	var tan_h: float = tan(deg_to_rad(FOV_DEG) / 2.0)
	var tan_v: float = tan_h / ASPECT
	var camera: Transform3D = transform_of(pose)
	var local: Array[Plane] = [
		Plane(Vector3(-1.0, 0.0, tan_h).normalized(), 0.0),
		Plane(Vector3(1.0, 0.0, tan_h).normalized(), 0.0),
		Plane(Vector3(0.0, 1.0, tan_v).normalized(), 0.0),
		Plane(Vector3(0.0, -1.0, tan_v).normalized(), 0.0),
		Plane(Vector3(0.0, 0.0, 1.0), -NEAR_M),
		Plane(Vector3(0.0, 0.0, -1.0), FAR_M),
	]
	var result: Array[Plane] = []
	for plane: Plane in local:
		result.append(camera * plane)
	return result


## A Camera3D with the build camera's lens at the pose (not yet in the tree).
static func make_camera(pose: Dictionary) -> Camera3D:
	var camera: Camera3D = Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = FOV_DEG
	camera.near = NEAR_M
	camera.far = FAR_M
	camera.transform = transform_of(pose)
	return camera


static func inside(planes: Array[Plane], point: Vector3) -> bool:
	for plane: Plane in planes:
		if plane.is_point_over(point):
			return false
	return true


static func _pose(position: Vector3, target: Vector3) -> Dictionary:
	return {"position": position, "target": target}
