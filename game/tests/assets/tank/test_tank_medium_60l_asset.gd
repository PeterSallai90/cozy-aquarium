extends GdUnitTestSuite
## #22 criteria 6, 8 and 14 for the tank asset (owner: technical-artist). The numbers are the ones
## the acceptance criteria state, not catalog values, so this suite runs before the catalog exists.

const Glb := preload("res://tests/helpers/glb_mesh_checks.gd")

const GLB_PATH := "res://assets/tank/tank_medium_60l.glb"
const SCENE_PATH := "res://scenes/tank/tank_medium_60l.tscn"
const INTERIOR := Vector3(0.60, 0.35, 0.30)
const GLASS := 0.005
const WATER_LINE := 0.33

var _root: Node3D = null


func after_test() -> void:
	if _root != null and is_instance_valid(_root):
		_root.free()
	_root = null


func _open_glb() -> bool:
	var opened: Dictionary = Glb.open_glb(GLB_PATH)
	assert_str(String(opened["problem"])).is_empty()
	_root = opened["root"]
	return _root != null


func _open_scene() -> bool:
	var exists: bool = ResourceLoader.exists(SCENE_PATH)
	assert_bool(exists).override_failure_message("tank scene missing: %s" % SCENE_PATH).is_true()
	if not exists:
		return false
	var scene: PackedScene = load(SCENE_PATH) as PackedScene
	assert_object(scene).is_not_null()
	if scene == null:
		return false
	_root = scene.instantiate() as Node3D
	assert_object(_root).is_not_null()
	return _root != null


func _expect(failures: PackedStringArray) -> void:
	assert_str("\n".join(failures)).is_empty()


# --- AC 6 ---


func test_ac06_interior_exterior_height_base_and_origin() -> void:
	if _open_glb():
		_expect(Glb.tank_failures(_root, INTERIOR, GLASS))


func test_ac06_no_baked_scale() -> void:
	if _open_glb():
		_expect(Glb.scale_failures(_root))


func test_ac06_front_is_plus_z_the_glass_front_pane_is_not_behind_the_origin() -> void:
	if not _open_glb():
		return
	var glass: AABB = Glb.bounds_in(Glb.find_mesh(_root, "Glass"), _root)
	assert_float(glass.end.z).is_equal_approx(0.155, Glb.MM)
	assert_float(glass.position.z).is_equal_approx(-0.155, Glb.MM)


# --- AC 8 ---


func test_ac08_tank_glb_budget_uv_layers_normals_and_import_flags() -> void:
	_expect(Glb.asset_failures(GLB_PATH))


# --- AC 14 ---


func test_ac14_scene_has_the_named_nodes_with_the_right_types() -> void:
	if not _open_scene():
		return
	assert_object(_root.get_node_or_null("Frame")).is_instanceof(MeshInstance3D)
	assert_object(_root.get_node_or_null("Glass")).is_instanceof(MeshInstance3D)
	assert_object(_root.get_node_or_null("WaterVolume")).is_instanceof(Node3D)
	assert_object(_root.get_node_or_null("SubstrateAnchor")).is_instanceof(Marker3D)
	assert_object(_root.get_node_or_null("lamp_mount")).is_instanceof(Marker3D)


func test_ac14_glass_uses_a_plain_very_transparent_placeholder_material() -> void:
	if not _open_scene():
		return
	var glass: MeshInstance3D = _root.get_node_or_null("Glass") as MeshInstance3D
	assert_object(glass).is_not_null()
	if glass == null:
		return
	assert_int(glass.mesh.get_surface_count()).is_greater(0)
	for surface: int in glass.mesh.get_surface_count():
		var material: StandardMaterial3D = glass.get_active_material(surface) as StandardMaterial3D
		assert_object(material).is_not_null()
		if material == null:
			continue
		assert_int(material.transparency).is_not_equal(BaseMaterial3D.TRANSPARENCY_DISABLED)
		assert_float(material.albedo_color.a).is_between(0.05, 0.25)


func test_ac14_water_volume_is_an_invisible_node_without_mesh_at_half_the_water_line() -> void:
	if not _open_scene():
		return
	var water: Node3D = _root.get_node_or_null("WaterVolume") as Node3D
	assert_object(water).is_not_null()
	if water == null:
		return
	assert_int(Glb.mesh_instances(water).size()).is_equal(0)
	assert_str(water.get_class()).is_equal("Node3D")
	assert_float(water.position.y).is_equal_approx(WATER_LINE / 2.0, Glb.MM)
	assert_float(water.position.x).is_equal_approx(0.0, Glb.MM)
	assert_float(water.position.z).is_equal_approx(0.0, Glb.MM)
	assert_vector(water.scale).is_equal_approx(Vector3.ONE, Vector3.ONE * 0.0001)


func test_ac14_substrate_anchor_is_at_the_inner_floor_centre() -> void:
	if not _open_scene():
		return
	var anchor: Marker3D = _root.get_node_or_null("SubstrateAnchor") as Marker3D
	assert_object(anchor).is_not_null()
	if anchor != null:
		assert_vector(anchor.position).is_equal_approx(Vector3.ZERO, Vector3.ONE * Glb.MM)


func test_ac14_lamp_mount_is_on_the_rim_at_the_top_of_the_trim() -> void:
	if not _open_scene():
		return
	var mount: Marker3D = _root.get_node_or_null("lamp_mount") as Marker3D
	assert_object(mount).is_not_null()
	if mount == null:
		return
	assert_float(mount.position.y).is_equal_approx(0.36, Glb.MM)
	assert_float(mount.position.x).is_equal_approx(0.0, Glb.MM)
	assert_float(mount.position.z).is_between(-0.10, 0.05)


func test_ac14_tank_scene_root_has_no_script() -> void:
	if _open_scene():
		assert_object(_root.get_script()).is_null()
