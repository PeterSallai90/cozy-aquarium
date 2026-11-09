extends GdUnitTestSuite
## #24 criterion 11 against the catalog (spans technical-artist and developer files), and #22
## criteria 6 and 14: for each of the three tanks the generated glb and the tank scene agree with
## the catalog entry, so params, glb and catalog cannot drift apart. The trim comes from the
## catalog field trim_size_m, never from a constant.

const Glb := preload("res://tests/helpers/glb_mesh_checks.gd")
const Api := preload("res://tests/helpers/late_api.gd")
const Table := preload("res://tests/helpers/tank_table.gd")

var _nodes: Array[Node] = []


func after_test() -> void:
	for node: Node in _nodes:
		if is_instance_valid(node):
			node.free()
	_nodes.clear()


func _definition(id: StringName) -> Resource:
	var definition: Resource = Api.definition_of(Api.catalog_load_dir(), id)
	assert_object(definition).override_failure_message("%s not in catalog" % id).is_not_null()
	return definition


func _trim(definition: Resource) -> float:
	return Api.prop(definition, "trim_size_m", Api.MISSING_NUMBER)


func _scene_root(definition: Resource) -> Node3D:
	var scene: PackedScene = Api.prop(definition, "scene", null) as PackedScene
	if scene == null:
		return null
	var root: Node3D = scene.instantiate() as Node3D
	if root != null:
		_nodes.append(root)
	return root


func _glb_root(id: StringName) -> Node3D:
	var opened: Dictionary = Glb.open_glb(Table.glb_path(id))
	assert_str(String(opened["problem"])).is_empty()
	var root: Node3D = opened["root"]
	if root != null:
		_nodes.append(root)
	return root


func test_ac11_glb_geometry_matches_the_catalog_interior_glass_and_trim() -> void:
	for id: StringName in Table.IDS:
		var definition: Resource = _definition(id)
		var root: Node3D = _glb_root(id)
		var interior: Vector3 = Api.prop(definition, "interior_size_m", Vector3.ZERO)
		var glass: float = Api.prop(definition, "glass_thickness_m", Api.MISSING_NUMBER)
		assert_vector(interior).is_not_equal(Vector3.ZERO)
		if root == null or interior == Vector3.ZERO:
			continue
		var failures: PackedStringArray = Glb.tank_failures(
			root, interior, glass, _trim(definition)
		)
		(
			assert_str("\n".join(failures))
			. override_failure_message("%s: %s" % [id, "\n".join(failures)])
			. is_empty()
		)


func test_ac11_trim_width_and_height_equal_trim_size_m_of_the_catalog_entry() -> void:
	for id: StringName in Table.IDS:
		var definition: Resource = _definition(id)
		var root: Node3D = _glb_root(id)
		var trim: float = _trim(definition)
		assert_float(trim).is_greater(0.0)
		if root == null:
			continue
		var frame: MeshInstance3D = Glb.find_mesh(root, "Frame")
		assert_object(frame).is_not_null()
		if frame == null:
			continue
		var interior: Vector3 = Api.prop(definition, "interior_size_m", Vector3.ZERO)
		var box: AABB = Glb.bounds_in(frame, root)
		assert_float(box.size.y).override_failure_message("%s trim height" % id).is_equal_approx(
			trim, Glb.MM
		)
		var points: PackedVector3Array = Glb.vertices_in(frame, root)
		var xs: Array[float] = Glb.distinct_values(points, 0)
		var outer_x: float = box.size.x / 2.0
		(
			assert_bool(Glb.has_value(xs, outer_x - trim, Glb.MM))
			. override_failure_message(
				"%s trim width on x (outer %.4f, trim %.4f)" % [id, outer_x, trim]
			)
			. is_true()
		)
		assert_float(box.position.y).is_equal_approx(interior.y, Glb.MM)


func test_ac11_exterior_footprint_equals_the_catalog_exterior_size() -> void:
	for id: StringName in Table.IDS:
		var definition: Resource = _definition(id)
		var root: Node3D = _glb_root(id)
		var exterior: Vector3 = Api.call_on(definition, "get_exterior_size_m", [], Vector3.ZERO)
		assert_vector(exterior).is_not_equal(Vector3.ZERO)
		if root == null or exterior == Vector3.ZERO:
			continue
		var box: AABB = Glb.scene_bounds(root)
		assert_float(box.size.x).is_equal_approx(exterior.x, Glb.MM)
		assert_float(box.size.z).is_equal_approx(exterior.z, Glb.MM)
		var glass: float = Api.prop(definition, "glass_thickness_m", Api.MISSING_NUMBER)
		assert_float(box.position.y).is_equal_approx(-glass, Glb.MM)


func test_ac11_water_volume_sits_at_half_the_catalog_water_line() -> void:
	for id: StringName in Table.IDS:
		var definition: Resource = _definition(id)
		var root: Node3D = _scene_root(definition)
		assert_object(root).is_not_null()
		if root == null:
			continue
		var water: Node3D = root.get_node_or_null("WaterVolume") as Node3D
		assert_object(water).is_not_null()
		if water != null:
			var line: float = Api.prop(definition, "water_line_height_m", Api.MISSING_NUMBER)
			assert_float(water.position.y).override_failure_message(id).is_equal_approx(
				line / 2.0, Glb.MM
			)


func test_ac11_lamp_mount_is_at_interior_height_plus_the_catalog_trim() -> void:
	for id: StringName in Table.IDS:
		var definition: Resource = _definition(id)
		var root: Node3D = _scene_root(definition)
		assert_object(root).is_not_null()
		if root == null:
			continue
		var mount: Node3D = root.get_node_or_null("lamp_mount") as Node3D
		assert_object(mount).is_not_null()
		if mount != null:
			var interior: Vector3 = Api.prop(definition, "interior_size_m", Vector3.ZERO)
			assert_float(mount.position.y).override_failure_message(id).is_equal_approx(
				interior.y + _trim(definition), Glb.MM
			)
