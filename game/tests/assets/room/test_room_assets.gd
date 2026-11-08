extends GdUnitTestSuite
## #22 criteria 7 (asset part), 8 for the cabinet, room and lamp assets (owner: technical-artist).
## Mesh names inside room_corner.glb are part of the contract these tests fix: Floor, BackWall,
## SideWall and Skirting (Blender object names become node names). Room space: the origin is the
## floor point under the tank centre, +Y up, +Z front.

const Glb := preload("res://tests/helpers/glb_mesh_checks.gd")
const LfsGuard := preload("res://tests/helpers/lfs_guard.gd")

const ROOM_PATH := "res://assets/room/room_corner.glb"
const CABINET_PATH := "res://assets/room/cabinet.glb"
const LAMP_PATH := "res://assets/room/lamp.glb"
const ATLAS_PATH := "res://assets/room/room_palette_atlas.png"
const CABINET_SIZE := Vector3(0.66, 0.75, 0.36)

var _root: Node3D = null


func after_test() -> void:
	if _root != null and is_instance_valid(_root):
		_root.free()
	_root = null


func _open(path: String) -> bool:
	var opened: Dictionary = Glb.open_glb(path)
	assert_str(String(opened["problem"])).is_empty()
	_root = opened["root"]
	return _root != null


func _expect(failures: PackedStringArray) -> void:
	assert_str("\n".join(failures)).is_empty()


func _part(wanted: String) -> AABB:
	var instance: MeshInstance3D = Glb.find_mesh(_root, wanted)
	assert_object(instance).override_failure_message("mesh %s missing" % wanted).is_not_null()
	return Glb.bounds_in(instance, _root)


# --- AC 8 ---


func test_ac08_cabinet_glb_budget_uv_layers_normals_and_import_flags() -> void:
	_expect(Glb.asset_failures(CABINET_PATH))


func test_ac08_room_glb_budget_uv_layers_normals_and_import_flags() -> void:
	_expect(Glb.asset_failures(ROOM_PATH))


func test_ac08_lamp_glb_budget_uv_layers_normals_and_import_flags() -> void:
	_expect(Glb.asset_failures(LAMP_PATH))


func test_ac08_palette_atlas_is_a_real_png_with_several_flat_colours() -> void:
	assert_str(LfsGuard.problem(ATLAS_PATH, LfsGuard.PNG_MAGIC)).is_empty()
	var image: Image = Image.new()
	var error: int = image.load_png_from_buffer(FileAccess.get_file_as_bytes(ATLAS_PATH))
	assert_int(error).is_equal(OK)
	if error != OK:
		return
	assert_int(image.get_width()).is_equal(image.get_height())
	assert_int(image.get_width()).is_greater_equal(16)
	var seen: Dictionary = {}
	for y: int in image.get_height():
		for x: int in image.get_width():
			seen[image.get_pixel(x, y).to_html()] = true
	assert_int(seen.size()).is_greater_equal(4)


func test_ac08_every_room_mesh_uses_the_shared_palette_material_and_atlas() -> void:
	for path: String in [CABINET_PATH, ROOM_PATH, LAMP_PATH]:
		if not _open(path):
			continue
		for instance: MeshInstance3D in Glb.mesh_instances(_root):
			for surface: int in instance.mesh.get_surface_count():
				var material: ShaderMaterial = (
					instance.get_active_material(surface) as ShaderMaterial
				)
				assert_object(material).is_not_null()
				if material == null:
					continue
				assert_str(material.resource_path).ends_with("room_palette.tres")
				var atlas: Texture2D = material.get_shader_parameter("palette_atlas") as Texture2D
				assert_object(atlas).is_not_null()
				if atlas != null:
					assert_str(atlas.resource_path).ends_with("room_palette_atlas.png")
		_root.free()
		_root = null


# --- cabinet (AC 7, asset part) ---


func test_ac07_cabinet_footprint_height_and_origin() -> void:
	if not _open(CABINET_PATH):
		return
	var box: AABB = Glb.scene_bounds(_root)
	assert_float(box.size.x).is_equal_approx(CABINET_SIZE.x, Glb.MM)
	assert_float(box.size.z).is_equal_approx(CABINET_SIZE.z, Glb.MM)
	assert_float(box.end.y).is_equal_approx(CABINET_SIZE.y, Glb.MM)
	assert_float(box.position.y).is_equal_approx(0.0, Glb.MM)
	assert_float(box.get_center().x).is_equal_approx(0.0, Glb.MM)
	assert_float(box.get_center().z).is_equal_approx(0.0, Glb.MM)


func test_ac07_cabinet_has_no_baked_scale() -> void:
	if _open(CABINET_PATH):
		_expect(Glb.scale_failures(_root))


# --- room (AC 7, asset part) ---


func test_ac07_room_has_floor_walls_and_skirting_meshes() -> void:
	if not _open(ROOM_PATH):
		return
	for wanted: String in ["Floor", "BackWall", "SideWall", "Skirting"]:
		(
			assert_object(Glb.find_mesh(_root, wanted))
			. override_failure_message("mesh %s missing" % wanted)
			. is_not_null()
		)


func test_ac07_back_wall_gap_to_the_cabinet_is_2_to_5_cm() -> void:
	if not _open(ROOM_PATH):
		return
	var wall: AABB = _part("BackWall")
	var gap: float = (-CABINET_SIZE.z / 2.0) - wall.end.z
	assert_float(gap).is_between(0.02 - Glb.MM, 0.05 + Glb.MM)


func test_ac07_side_wall_does_not_touch_the_cabinet() -> void:
	if not _open(ROOM_PATH):
		return
	var wall: AABB = _part("SideWall")
	var half: float = CABINET_SIZE.x / 2.0
	assert_bool(wall.position.x >= half or wall.end.x <= -half).is_true()


func test_ac07_walls_are_about_2_4_m_tall_standing_on_the_floor_surface() -> void:
	if not _open(ROOM_PATH):
		return
	for wanted: String in ["BackWall", "SideWall"]:
		var wall: AABB = _part(wanted)
		assert_float(wall.end.y).is_between(2.3, 2.5)
		assert_float(wall.position.y).is_less_equal(Glb.MM)


func test_ac07_skirting_is_8_to_10_cm_tall() -> void:
	if not _open(ROOM_PATH):
		return
	var skirting: AABB = _part("Skirting")
	assert_float(skirting.position.y).is_between(-Glb.MM, Glb.MM)
	assert_float(skirting.size.y).is_between(0.08 - Glb.MM, 0.10 + Glb.MM)


func test_ac07_floor_is_a_slab_with_its_surface_at_y_0_and_nothing_else_below() -> void:
	if not _open(ROOM_PATH):
		return
	var floor_box: AABB = _part("Floor")
	assert_float(floor_box.end.y).is_equal_approx(0.0, Glb.MM)
	assert_float(floor_box.size.y).is_greater_equal(0.01)
	for wanted: String in ["BackWall", "SideWall", "Skirting"]:
		var other: AABB = _part(wanted)
		assert_float(other.position.y).is_greater_equal(-Glb.MM)
	for instance: MeshInstance3D in Glb.mesh_instances(_root):
		var box: AABB = Glb.bounds_in(instance, _root)
		assert_float(box.position.y).is_greater_equal(floor_box.position.y - Glb.MM)


func test_ac07_floor_extends_at_least_10_cm_around_the_cabinet_front_and_sides() -> void:
	if not _open(ROOM_PATH):
		return
	var floor_box: AABB = _part("Floor")
	assert_float(floor_box.position.x).is_less_equal(-0.33 - 0.1)
	assert_float(floor_box.end.x).is_greater_equal(0.33 + 0.1)
	assert_float(floor_box.position.z).is_less_equal(-0.18)
	assert_float(floor_box.end.z).is_greater_equal(0.18 + 0.1)


func test_ac07_walls_use_a_back_face_culled_material() -> void:
	if not _open(ROOM_PATH):
		return
	for wanted: String in ["BackWall", "SideWall"]:
		var instance: MeshInstance3D = Glb.find_mesh(_root, wanted)
		assert_object(instance).is_not_null()
		if instance == null:
			continue
		var material: ShaderMaterial = instance.get_active_material(0) as ShaderMaterial
		assert_object(material).is_not_null()
		if material == null:
			continue
		var code: String = material.shader.code
		assert_str(code).contains("cull_back")
		assert_bool(code.contains("cull_disabled")).is_false()
