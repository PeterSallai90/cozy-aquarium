extends GdUnitTestSuite
## #22 criteria 10 (in lamp space) and 12 (key light) for lamp.tscn (owner: technical-artist).
## Lamp space: the origin is the centre of the bracket contact plane, the plane that rests on the
## trim top, +Y up, front +Z. Placed on the tank, lamp-space y = 0 is tank-local y = 0.36.

const Glb := preload("res://tests/helpers/glb_mesh_checks.gd")

const SCENE_PATH := "res://scenes/room/lamp.tscn"
const BAR_LENGTH := 0.58
const BAR_DEPTH := 0.06
const TRIM_OUTER_X := 0.305
const TRIM_INNER_X := 0.295

var _root: Node3D = null


func after_test() -> void:
	if _root != null and is_instance_valid(_root):
		_root.free()
	_root = null


func _open() -> bool:
	var exists: bool = ResourceLoader.exists(SCENE_PATH)
	assert_bool(exists).override_failure_message("lamp scene missing: %s" % SCENE_PATH).is_true()
	if not exists:
		return false
	var scene: PackedScene = load(SCENE_PATH) as PackedScene
	assert_object(scene).is_not_null()
	if scene == null:
		return false
	_root = scene.instantiate() as Node3D
	assert_object(_root).is_not_null()
	return _root != null


func _mesh(wanted: String) -> MeshInstance3D:
	var instance: MeshInstance3D = Glb.find_mesh(_root, wanted)
	assert_object(instance).override_failure_message("mesh %s missing" % wanted).is_not_null()
	return instance


func _light() -> SpotLight3D:
	var light: SpotLight3D = _root.get_node_or_null("KeyLight") as SpotLight3D
	assert_object(light).override_failure_message("KeyLight SpotLight3D missing").is_not_null()
	return light


# --- AC 10 ---


func test_ac10_lamp_scene_has_the_bar_and_the_brackets() -> void:
	if not _open():
		return
	assert_object(_root.get_node_or_null("lamp")).is_instanceof(MeshInstance3D)
	assert_object(_root.get_node_or_null("lamp_brackets")).is_instanceof(MeshInstance3D)


func test_ac10_bar_is_058_by_006_m() -> void:
	if not _open():
		return
	var bar: AABB = Glb.bounds_in(_mesh("lamp"), _root)
	assert_float(bar.size.x).is_equal_approx(BAR_LENGTH, Glb.MM)
	assert_float(bar.size.z).is_equal_approx(BAR_DEPTH, Glb.MM)


func test_ac10_bar_lowest_point_is_at_or_above_the_trim_top() -> void:
	if not _open():
		return
	var bar: AABB = Glb.bounds_in(_mesh("lamp"), _root)
	assert_float(bar.position.y).is_greater_equal(-Glb.MM)


func test_ac10_brackets_rest_on_the_trim_top_and_reach_the_side_trims() -> void:
	if not _open():
		return
	var points: PackedVector3Array = Glb.vertices_in(_mesh("lamp_brackets"), _root)
	assert_int(points.size()).is_greater(0)
	if points.is_empty():
		return
	var box: AABB = Glb.bounds_in(_mesh("lamp_brackets"), _root)
	assert_float(box.position.y).is_equal_approx(0.0, Glb.MM)
	var feet_left: int = 0
	var feet_right: int = 0
	for point: Vector3 in points:
		if point.y > box.position.y + Glb.MM:
			continue
		if absf(point.x) < TRIM_INNER_X - Glb.MM or absf(point.x) > TRIM_OUTER_X + Glb.MM:
			continue
		if point.x < 0.0:
			feet_left += 1
		else:
			feet_right += 1
	assert_int(feet_left).is_greater(0)
	assert_int(feet_right).is_greater(0)


func test_ac10_whole_lamp_has_no_front_skirt_and_fits_the_tank_width() -> void:
	if not _open():
		return
	var whole: AABB = Glb.scene_bounds(_root)
	assert_float(whole.size.z).is_less_equal(BAR_DEPTH + Glb.MM)
	assert_float(whole.size.x).is_less_equal(0.61 + Glb.MM)
	assert_float(whole.position.y).is_greater_equal(-Glb.MM)


func test_ac10_lamp_scene_root_has_no_script() -> void:
	if _open():
		assert_object(_root.get_script()).is_null()


# --- AC 12 (key light) ---


func test_ac12_key_light_is_a_shadow_casting_spot_light_under_the_lamp() -> void:
	if not _open():
		return
	var light: SpotLight3D = _light()
	if light == null:
		return
	assert_bool(light.shadow_enabled).is_true()
	assert_bool(light.visible).is_true()
	assert_object(light.get_parent()).is_equal(_root)


func test_ac12_key_light_colour_is_warm() -> void:
	if not _open():
		return
	var light: SpotLight3D = _light()
	if light == null:
		return
	assert_float(light.light_color.r).is_equal_approx(1.0, 0.0001)
	assert_float(light.light_color.g).is_between(0.64, 0.80)
	assert_float(light.light_color.b).is_between(0.32, 0.58)


func test_ac12_key_light_has_energy_and_points_down() -> void:
	if not _open():
		return
	var light: SpotLight3D = _light()
	if light == null:
		return
	assert_float(light.light_energy).is_greater(0.0)
	var forward: Vector3 = -light.transform.basis.z
	assert_float(forward.y).is_less(-0.9)
