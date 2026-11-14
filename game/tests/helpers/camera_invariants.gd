extends RefCounted
## The one definition of "a camera limit is violated" for the #27 limit suites and their
## meta-tests. One instance per tank: it holds the production limits, the solid oracle, the water
## volume, the cabinet top and the default distance, and check() returns the violations of one
## camera frame (empty when every invariant holds). The passing path formats no string.
##
## Limits and tolerances follow the BA decisions on #27 (Q3, Q4, Q5): limits are asserted on the
## target values, transform rules on the displayed camera; displayed elevation stays within the
## limits plus 0.01 degrees; the cabinet rule is height >= cabinet top minus 1 mm plus "outside
## the cabinet box grown by the margin" (the stricter top plus margin is never asserted).

const KIND_ELEVATION := "[elevation]"
const KIND_DISTANCE := "[distance]"
const KIND_PIVOT := "[pivot]"
const KIND_SOLID := "[solid]"
const KIND_CABINET := "[cabinet]"
const KIND_NAN := "[nan]"
const KIND_BASIS := "[basis]"

const SETTINGS_PATH := "res://systems/camera/camera_settings.tres"
const ANGLE_TOLERANCE_DEG: float = 0.01
const LENGTH_TOLERANCE_M: float = 0.001
const BASIS_TOLERANCE: float = 0.001
const FLOOR_SLAB := AABB(Vector3(-50.0, -50.0, -50.0), Vector3(100.0, 50.0, 100.0))

var _min_elevation_deg: float = 0.0
var _max_elevation_deg: float = 0.0
var _zoom_min: float = 0.0
var _zoom_max: float = 0.0
var _margin_m: float = 0.0
var _solids: Array[AABB] = []
var _water: AABB = AABB()
var _cabinet_top_y: float = 0.0
var _default_distance_m: float = 1.0
var _view_up_limit: float = 0.0


## The limits of camera_settings.tres; the loaded resource is never changed.
static func production_limits() -> Dictionary:
	var settings: CameraSettings = load(SETTINGS_PATH) as CameraSettings
	return {
		"min_elevation_deg": settings.min_elevation_limit_deg,
		"max_elevation_deg": settings.max_elevation_deg,
		"zoom_min": settings.zoom_min_factor,
		"zoom_max": settings.zoom_max_factor,
		"margin_m": settings.collision_margin_m,
	}


static func has_kind(failures: PackedStringArray, kind: String) -> bool:
	for message: String in failures:
		if message.contains(kind):
			return true
	return false


func _init(
	limits: Dictionary,
	solids: Array[AABB],
	water_volume: AABB,
	cabinet_top_y: float,
	default_distance_m: float
) -> void:
	_min_elevation_deg = limits["min_elevation_deg"]
	_max_elevation_deg = limits["max_elevation_deg"]
	_zoom_min = limits["zoom_min"]
	_zoom_max = limits["zoom_max"]
	_margin_m = limits["margin_m"]
	_solids = solids.duplicate()
	_solids.append(FLOOR_SLAB)
	_water = water_volume
	_cabinet_top_y = cabinet_top_y
	_default_distance_m = default_distance_m
	_view_up_limit = sin(deg_to_rad(_max_elevation_deg + ANGLE_TOLERANCE_DEG)) + BASIS_TOLERANCE


## The violations of the camera as it is now. Targets are checked against the limits, the
## displayed pose against the transform rules.
func check(camera: BuildCamera) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var position: Vector3 = camera.global_position
	var basis: Basis = camera.global_transform.basis
	var target_elevation: float = camera.get_target_elevation_deg()
	var elevation: float = camera.get_elevation_deg()
	var target_distance: float = camera.get_target_distance_m()
	var distance: float = camera.get_distance_m()
	var held: float = camera.get_held_distance_m()
	var pivot: Vector3 = camera.get_pivot()
	var target_pivot: Vector3 = camera.get_target_pivot()
	var scalars: Array[float] = [
		target_elevation,
		elevation,
		target_distance,
		distance,
		held,
		camera.get_target_azimuth_deg(),
		camera.get_azimuth_deg()
	]
	if not _all_finite(position, basis, pivot, target_pivot, scalars):
		out.append("%s non-finite value: position %s basis %s" % [KIND_NAN, position, basis])
		return out
	_check_elevation(out, target_elevation, elevation, position, pivot)
	_check_distance(out, target_distance, distance, held)
	if not _inside_water(target_pivot) or not _inside_water(pivot):
		out.append(
			"%s pivot %s target %s outside water %s" % [KIND_PIVOT, pivot, target_pivot, _water]
		)
	if not CameraCollision.is_clear(_solids, _margin_m - LENGTH_TOLERANCE_M, position):
		out.append("%s camera %s is inside a solid plus margin" % [KIND_SOLID, position])
	if position.y < _cabinet_top_y - LENGTH_TOLERANCE_M:
		out.append(
			(
				"%s camera height %.5f below cabinet top %.5f"
				% [KIND_CABINET, position.y, _cabinet_top_y]
			)
		)
	_check_basis(out, basis)
	return out


func _all_finite(
	position: Vector3, basis: Basis, pivot: Vector3, target_pivot: Vector3, values: Array[float]
) -> bool:
	if not (position.is_finite() and basis.is_finite()):
		return false
	if not (pivot.is_finite() and target_pivot.is_finite()):
		return false
	for value: float in values:
		if not is_finite(value):
			return false
	return true


func _check_elevation(
	out: PackedStringArray,
	target_elevation: float,
	elevation: float,
	position: Vector3,
	pivot: Vector3
) -> void:
	var low: float = _min_elevation_deg - ANGLE_TOLERANCE_DEG
	var high: float = _max_elevation_deg + ANGLE_TOLERANCE_DEG
	if target_elevation < low or target_elevation > high:
		out.append(
			(
				"%s target elevation %.4f outside %.2f..%.2f"
				% [KIND_ELEVATION, target_elevation, low, high]
			)
		)
	if elevation < low or elevation > high:
		out.append(
			(
				"%s displayed elevation %.4f outside %.2f..%.2f"
				% [KIND_ELEVATION, elevation, low, high]
			)
		)
	var offset: Vector3 = position - pivot
	if offset.length() > 0.000001:
		var shown: float = rad_to_deg(asin(clampf(offset.y / offset.length(), -1.0, 1.0)))
		if shown < low or shown > high:
			out.append(
				"%s shown elevation %.4f outside %.2f..%.2f" % [KIND_ELEVATION, shown, low, high]
			)


func _check_distance(
	out: PackedStringArray, target_distance: float, distance: float, held: float
) -> void:
	var low: float = _zoom_min * _default_distance_m - LENGTH_TOLERANCE_M
	var high: float = _zoom_max * _default_distance_m + LENGTH_TOLERANCE_M
	if target_distance < low or target_distance > high:
		out.append(
			(
				"%s target distance %.4f outside %.4f..%.4f"
				% [KIND_DISTANCE, target_distance, low, high]
			)
		)
	if distance < low or distance > high:
		out.append(
			"%s displayed distance %.4f outside %.4f..%.4f" % [KIND_DISTANCE, distance, low, high]
		)
	if held < low:
		out.append("%s held distance %.4f below %.4f" % [KIND_DISTANCE, held, low])


func _inside_water(point: Vector3) -> bool:
	var low: Vector3 = _water.position - Vector3.ONE * LENGTH_TOLERANCE_M
	var high: Vector3 = _water.end + Vector3.ONE * LENGTH_TOLERANCE_M
	return (
		point.x >= low.x
		and point.x <= high.x
		and point.y >= low.y
		and point.y <= high.y
		and point.z >= low.z
		and point.z <= high.z
	)


func _check_basis(out: PackedStringArray, basis: Basis) -> void:
	if (
		absf(basis.x.length() - 1.0) > BASIS_TOLERANCE
		or absf(basis.y.length() - 1.0) > BASIS_TOLERANCE
		or absf(basis.z.length() - 1.0) > BASIS_TOLERANCE
	):
		out.append("%s an axis is not unit length: %s" % [KIND_BASIS, basis])
	if (
		absf(basis.x.dot(basis.y)) > BASIS_TOLERANCE
		or absf(basis.y.dot(basis.z)) > BASIS_TOLERANCE
		or absf(basis.x.dot(basis.z)) > BASIS_TOLERANCE
	):
		out.append("%s the axes are not orthogonal: %s" % [KIND_BASIS, basis])
	if basis.y.y <= 0.0:
		out.append("%s the up vector points down: %s" % [KIND_BASIS, basis.y])
	if absf((-basis.z).y) > _view_up_limit:
		out.append("%s the view direction is parallel to the up axis: %s" % [KIND_BASIS, -basis.z])
