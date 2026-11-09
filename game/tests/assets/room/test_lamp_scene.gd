# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #22 criteria 10 (in lamp space) and 12 (key light), and #24 criterion 12 (asset part), for the
## lamp scene of each tank (owner: technical-artist). Lamp space: the origin is the centre of the
## bracket contact plane, the plane that rests on the trim top, +Y up, front +Z. Placed on the
## tank, lamp-space y = 0 is tank-local y = interior height + trim_size_m (0.01 m for all three).
## The bar is the tank exterior length minus 3 cm, by 6 cm; the numbers come from the issue table.

const Glb := preload("res://tests/helpers/glb_mesh_checks.gd")
const Table := preload("res://tests/helpers/tank_table.gd")

const BAR_DEPTH := 0.06

var _root: Node3D = null


func after_test() -> void:
	_free_root()


func _free_root() -> void:
	if _root != null and is_instance_valid(_root):
		_root.free()
	_root = null


func _open(id: StringName) -> bool:
	_free_root()
	var path: String = Table.lamp_scene_path(id)
	var exists: bool = ResourceLoader.exists(path)
	assert_bool(exists).override_failure_message("lamp scene missing: %s" % path).is_true()
	if not exists:
		return false
	var scene: PackedScene = load(path) as PackedScene
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


# --- AC 10 / AC 12 (#24): the bar and the brackets ---


func test_ac12_lamp_scene_has_the_bar_and_the_brackets() -> void:
	for id: StringName in Table.IDS:
		if not _open(id):
			continue
		assert_object(_root.get_node_or_null("lamp")).is_instanceof(MeshInstance3D)
		assert_object(_root.get_node_or_null("lamp_brackets")).is_instanceof(MeshInstance3D)


func test_ac12_bar_is_the_exterior_length_minus_3_cm_by_6_cm() -> void:
	for id: StringName in Table.IDS:
		if not _open(id):
			continue
		var bar: AABB = Glb.bounds_in(_mesh("lamp"), _root)
		assert_float(bar.size.x).override_failure_message("%s bar length" % id).is_equal_approx(
			Table.lamp_bar_length(id), Glb.MM
		)
		assert_float(bar.size.z).override_failure_message("%s bar depth" % id).is_equal_approx(
			BAR_DEPTH, Glb.MM
		)


func test_ac12_bar_lowest_point_is_at_or_above_the_trim_top() -> void:
	for id: StringName in Table.IDS:
		if not _open(id):
			continue
		var bar: AABB = Glb.bounds_in(_mesh("lamp"), _root)
		assert_float(bar.position.y).override_failure_message(id).is_greater_equal(-Glb.MM)


func test_ac12_brackets_rest_on_the_trim_top_and_reach_the_side_trims() -> void:
	for id: StringName in Table.IDS:
		if not _open(id):
			continue
		var outer_x: float = Table.exterior(id).x / 2.0
		var inner_x: float = outer_x - Table.TRIM_M
		var points: PackedVector3Array = Glb.vertices_in(_mesh("lamp_brackets"), _root)
		assert_int(points.size()).is_greater(0)
		if points.is_empty():
			continue
		var box: AABB = Glb.bounds_in(_mesh("lamp_brackets"), _root)
		assert_float(box.position.y).override_failure_message(id).is_equal_approx(0.0, Glb.MM)
		var feet_left: int = 0
		var feet_right: int = 0
		for point: Vector3 in points:
			if point.y > box.position.y + Glb.MM:
				continue
			if absf(point.x) < inner_x - Glb.MM or absf(point.x) > outer_x + Glb.MM:
				continue
			if point.x < 0.0:
				feet_left += 1
			else:
				feet_right += 1
		assert_int(feet_left).override_failure_message("%s left foot on the trim" % id).is_greater(
			0
		)
		(
			assert_int(feet_right)
			. override_failure_message("%s right foot on the trim" % id)
			. is_greater(0)
		)


func test_ac12_whole_lamp_has_no_front_skirt_and_fits_the_tank_width() -> void:
	for id: StringName in Table.IDS:
		if not _open(id):
			continue
		var whole: AABB = Glb.scene_bounds(_root)
		assert_float(whole.size.z).is_less_equal(BAR_DEPTH + Glb.MM)
		assert_float(whole.size.x).override_failure_message(id).is_less_equal(
			Table.exterior(id).x + Glb.MM
		)
		assert_float(whole.position.y).is_greater_equal(-Glb.MM)


func test_ac12_lamp_scene_root_has_no_script() -> void:
	for id: StringName in Table.IDS:
		if _open(id):
			assert_object(_root.get_script()).is_null()


func test_ac12_the_medium_lamp_keeps_the_delivered_058_bar() -> void:
	if _open(Table.MEDIUM):
		var bar: AABB = Glb.bounds_in(_mesh("lamp"), _root)
		assert_float(bar.size.x).is_equal_approx(0.58, Glb.MM)


# --- #22 AC 12: the key light of each lamp ---


func test_ac12_key_light_is_a_shadow_casting_spot_light_under_the_lamp() -> void:
	for id: StringName in Table.IDS:
		if not _open(id):
			continue
		var light: SpotLight3D = _light()
		if light == null:
			continue
		assert_bool(light.shadow_enabled).is_true()
		assert_bool(light.visible).is_true()
		assert_object(light.get_parent()).is_equal(_root)


func test_ac12_key_light_colour_is_warm() -> void:
	for id: StringName in Table.IDS:
		if not _open(id):
			continue
		var light: SpotLight3D = _light()
		if light == null:
			continue
		assert_float(light.light_color.r).is_equal_approx(1.0, 0.0001)
		assert_float(light.light_color.g).is_between(0.64, 0.80)
		assert_float(light.light_color.b).is_between(0.32, 0.58)


func test_ac12_key_light_has_energy_and_points_down() -> void:
	for id: StringName in Table.IDS:
		if not _open(id):
			continue
		var light: SpotLight3D = _light()
		if light == null:
			continue
		assert_float(light.light_energy).is_greater(0.0)
		var forward: Vector3 = -light.transform.basis.z
		assert_float(forward.y).is_less(-0.9)


func test_ac12_key_light_reaches_every_corner_of_the_inner_floor() -> void:
	# Plan section 4: the spot is tuned per tank (the large tank needs a wider or longer cone).
	for id: StringName in Table.IDS:
		if not _open(id):
			continue
		var light: SpotLight3D = _light()
		var tank_scene: PackedScene = load(Table.scene_path(id)) as PackedScene
		if light == null or tank_scene == null:
			continue
		var tank: Node3D = tank_scene.instantiate() as Node3D
		var mount: Vector3 = (tank.get_node("lamp_mount") as Node3D).position
		tank.free()
		var interior: Vector3 = Table.interior(id)
		var origin: Vector3 = light.position + Vector3(0.0, mount.y, mount.z)
		var forward: Vector3 = -light.transform.basis.z
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var corner: Vector3 = Vector3(sx * interior.x / 2.0, 0.0, sz * interior.z / 2.0)
				var offset: Vector3 = corner - origin
				var angle: float = rad_to_deg(forward.angle_to(offset))
				(
					assert_float(angle)
					. override_failure_message(
						(
							"%s: floor corner %s is %.1f degrees off the spot axis"
							% [id, corner, angle]
						)
					)
					. is_less_equal(light.spot_angle)
				)
				(
					assert_float(offset.length())
					. override_failure_message(
						"%s: floor corner %s is beyond the spot range" % [id, corner]
					)
					. is_less_equal(light.spot_range)
				)
