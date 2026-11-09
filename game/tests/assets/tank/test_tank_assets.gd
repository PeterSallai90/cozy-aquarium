# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #24 criteria 11 and 14 (and #22 criteria 6, 8 and 14 for the medium tank, now tank_medium_1) for
## the tank glb and scene of each of the three tanks (owner: technical-artist). The numbers are the
## ones the issue table states, not catalog values, so this suite runs before the catalog exists;
## test_tank_matches_asset.gd compares the same assets with the catalog. Trim is 0.01 m for all
## three (owner decision, catalog field trim_size_m).

const Glb := preload("res://tests/helpers/glb_mesh_checks.gd")
const Table := preload("res://tests/helpers/tank_table.gd")

var _root: Node3D = null


func after_test() -> void:
	if _root != null and is_instance_valid(_root):
		_root.free()
	_root = null


func _open_glb(id: StringName) -> bool:
	_free_root()
	var opened: Dictionary = Glb.open_glb(Table.glb_path(id))
	assert_str(String(opened["problem"])).is_empty()
	_root = opened["root"]
	return _root != null


func _open_scene(id: StringName) -> bool:
	_free_root()
	var path: String = Table.scene_path(id)
	var exists: bool = ResourceLoader.exists(path)
	assert_bool(exists).override_failure_message("tank scene missing: %s" % path).is_true()
	if not exists:
		return false
	var scene: PackedScene = load(path) as PackedScene
	assert_object(scene).is_not_null()
	if scene == null:
		return false
	_root = scene.instantiate() as Node3D
	assert_object(_root).is_not_null()
	return _root != null


func _free_root() -> void:
	if _root != null and is_instance_valid(_root):
		_root.free()
	_root = null


func _expect(failures: PackedStringArray, id: StringName) -> void:
	(
		assert_str("\n".join(failures))
		. override_failure_message("%s: %s" % [id, "\n".join(failures)])
		. is_empty()
	)


# --- AC 11: geometry of the glb ---


func test_ac11_interior_exterior_height_base_trim_and_origin_for_each_tank() -> void:
	for id: StringName in Table.IDS:
		if _open_glb(id):
			_expect(Glb.tank_failures(_root, Table.interior(id), Table.glass(id), Table.TRIM_M), id)


func test_ac11_no_baked_scale_for_each_tank() -> void:
	for id: StringName in Table.IDS:
		if _open_glb(id):
			_expect(Glb.scale_failures(_root), id)


func test_ac11_the_glass_spans_the_exterior_depth_centred_on_the_origin() -> void:
	for id: StringName in Table.IDS:
		if not _open_glb(id):
			continue
		var half_z: float = Table.interior(id).z / 2.0 + Table.glass(id)
		var glass: AABB = Glb.bounds_in(Glb.find_mesh(_root, "Glass"), _root)
		assert_float(glass.end.z).override_failure_message(id).is_equal_approx(half_z, Glb.MM)
		assert_float(glass.position.z).override_failure_message(id).is_equal_approx(-half_z, Glb.MM)


func test_ac11_the_exterior_height_with_trim_is_interior_plus_glass_plus_trim() -> void:
	for id: StringName in Table.IDS:
		if not _open_glb(id):
			continue
		var whole: AABB = Glb.scene_bounds(_root)
		var expected: float = Table.interior(id).y + Table.glass(id) + Table.TRIM_M
		assert_float(whole.size.y).override_failure_message(id).is_equal_approx(expected, Glb.MM)


# --- AC 14: budget, UV layers, import flags (art rules) ---


func test_ac14_each_tank_glb_is_within_the_triangle_budget_has_two_uv_layers_and_import_flags(
) -> void:
	for id: StringName in Table.IDS:
		_expect(Glb.asset_failures(Table.glb_path(id)), id)


# --- AC 11: the scene contract of #22 AC 14 ---


func test_ac11_scene_has_the_named_nodes_with_the_right_types() -> void:
	for id: StringName in Table.IDS:
		if not _open_scene(id):
			continue
		assert_object(_root.get_node_or_null("Frame")).is_instanceof(MeshInstance3D)
		assert_object(_root.get_node_or_null("Glass")).is_instanceof(MeshInstance3D)
		assert_object(_root.get_node_or_null("WaterVolume")).is_instanceof(Node3D)
		assert_object(_root.get_node_or_null("SubstrateAnchor")).is_instanceof(Marker3D)
		assert_object(_root.get_node_or_null("lamp_mount")).is_instanceof(Marker3D)


func test_ac11_each_root_node_is_named_after_its_tank() -> void:
	var names: Dictionary = {
		Table.SMALL: "TankSmall1", Table.MEDIUM: "TankMedium1", Table.LARGE: "TankLarge1"
	}
	for id: StringName in Table.IDS:
		if _open_scene(id):
			assert_str(String(_root.name)).is_equal(names[id])


## Superseded by #23: the plain placeholder material is gone; the glass is the tank_glass shader
## material (its parameters are tested in test_water_shaders.gd).
func test_ac11_glass_uses_the_transparent_tank_glass_shader_material() -> void:
	for id: StringName in Table.IDS:
		if not _open_scene(id):
			continue
		var glass: MeshInstance3D = _root.get_node_or_null("Glass") as MeshInstance3D
		assert_object(glass).is_not_null()
		if glass == null:
			continue
		assert_int(glass.mesh.get_surface_count()).is_greater(0)
		for surface: int in glass.mesh.get_surface_count():
			var material: ShaderMaterial = glass.get_active_material(surface) as ShaderMaterial
			assert_object(material).override_failure_message(id).is_not_null()
			if material == null:
				continue
			assert_str(material.resource_path).is_equal(
				"res://assets/tank/materials/tank_glass.tres"
			)


func test_ac11_glass_does_not_cast_shadows() -> void:
	for id: StringName in Table.IDS:
		if not _open_scene(id):
			continue
		var glass: MeshInstance3D = _root.get_node_or_null("Glass") as MeshInstance3D
		assert_object(glass).is_not_null()
		if glass != null:
			assert_int(glass.cast_shadow).override_failure_message(id).is_equal(
				GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			)


func test_ac11_water_volume_is_a_node3d_at_half_the_water_line() -> void:
	for id: StringName in Table.IDS:
		if not _open_scene(id):
			continue
		var water: Node3D = _root.get_node_or_null("WaterVolume") as Node3D
		assert_object(water).is_not_null()
		if water == null:
			continue
		assert_str(water.get_class()).is_equal("Node3D")
		assert_float(water.position.y).override_failure_message(id).is_equal_approx(
			Table.water_line(id) / 2.0, Glb.MM
		)
		assert_float(water.position.x).is_equal_approx(0.0, Glb.MM)
		assert_float(water.position.z).is_equal_approx(0.0, Glb.MM)
		assert_vector(water.scale).is_equal_approx(Vector3.ONE, Vector3.ONE * 0.0001)


func test_ac11_substrate_anchor_is_at_the_inner_floor_centre() -> void:
	for id: StringName in Table.IDS:
		if not _open_scene(id):
			continue
		var anchor: Marker3D = _root.get_node_or_null("SubstrateAnchor") as Marker3D
		assert_object(anchor).is_not_null()
		if anchor != null:
			assert_vector(anchor.position).is_equal_approx(Vector3.ZERO, Vector3.ONE * Glb.MM)


func test_ac11_lamp_mount_is_on_the_rim_at_interior_height_plus_trim_toward_the_back() -> void:
	for id: StringName in Table.IDS:
		if not _open_scene(id):
			continue
		var mount: Marker3D = _root.get_node_or_null("lamp_mount") as Marker3D
		assert_object(mount).is_not_null()
		if mount == null:
			continue
		var interior: Vector3 = Table.interior(id)
		assert_float(mount.position.y).override_failure_message(id).is_equal_approx(
			interior.y + Table.TRIM_M, Glb.MM
		)
		assert_float(mount.position.x).is_equal_approx(0.0, Glb.MM)
		# As on medium (-0.10 .. 0.05 of a half depth of 0.15): from two thirds toward the back to
		# one third toward the front of the half depth.
		var half_z: float = interior.z / 2.0
		assert_float(mount.position.z).override_failure_message(id).is_between(
			-half_z * 2.0 / 3.0, half_z / 3.0
		)


func test_ac11_tank_scene_root_has_no_script() -> void:
	for id: StringName in Table.IDS:
		if _open_scene(id):
			assert_object(_root.get_script()).is_null()
