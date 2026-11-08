extends GdUnitTestSuite
## #22 criteria 6 and 14 against the catalog (spans technical-artist and developer files): the
## generated tank agrees with the catalog entry, so params, glb and catalog cannot drift apart.

const Glb := preload("res://tests/helpers/glb_mesh_checks.gd")
const Api := preload("res://tests/helpers/late_api.gd")

const TANK_ID := &"tank_medium_60l"
const GLB_PATH := "res://assets/tank/tank_medium_60l.glb"

var _nodes: Array[Node] = []


func after_test() -> void:
	for node: Node in _nodes:
		if is_instance_valid(node):
			node.free()
	_nodes.clear()


func _definition() -> Resource:
	var definition: Resource = Api.definition_of(Api.catalog_load_dir(), TANK_ID)
	(
		assert_object(definition)
		. override_failure_message("tank_medium_60l not in catalog")
		. is_not_null()
	)
	return definition


func _scene_root(definition: Resource) -> Node3D:
	var scene: PackedScene = Api.prop(definition, "scene", null) as PackedScene
	if scene == null:
		return null
	var root: Node3D = scene.instantiate() as Node3D
	if root != null:
		_nodes.append(root)
	return root


func _glb_root() -> Node3D:
	var opened: Dictionary = Glb.open_glb(GLB_PATH)
	assert_str(String(opened["problem"])).is_empty()
	var root: Node3D = opened["root"]
	if root != null:
		_nodes.append(root)
	return root


func test_ac06_glb_geometry_matches_the_catalog_interior_and_glass() -> void:
	var definition: Resource = _definition()
	var root: Node3D = _glb_root()
	var interior: Vector3 = Api.prop(definition, "interior_size_m", Vector3.ZERO)
	var glass: float = Api.prop(definition, "glass_thickness_m", Api.MISSING_NUMBER)
	assert_vector(interior).is_not_equal(Vector3.ZERO)
	if root == null or interior == Vector3.ZERO:
		return
	assert_str("\n".join(Glb.tank_failures(root, interior, glass))).is_empty()


func test_ac06_exterior_footprint_equals_the_catalog_exterior_size() -> void:
	var definition: Resource = _definition()
	var root: Node3D = _glb_root()
	var exterior: Vector3 = Api.call_on(definition, "get_exterior_size_m", [], Vector3.ZERO)
	assert_vector(exterior).is_not_equal(Vector3.ZERO)
	if root == null or exterior == Vector3.ZERO:
		return
	var box: AABB = Glb.scene_bounds(root)
	assert_float(box.size.x).is_equal_approx(exterior.x, Glb.MM)
	assert_float(box.size.z).is_equal_approx(exterior.z, Glb.MM)
	var glass: float = Api.prop(definition, "glass_thickness_m", Api.MISSING_NUMBER)
	assert_float(box.position.y).is_equal_approx(-glass, Glb.MM)


func test_ac14_water_volume_sits_at_half_the_catalog_water_line() -> void:
	var definition: Resource = _definition()
	var root: Node3D = _scene_root(definition)
	assert_object(root).is_not_null()
	if root == null:
		return
	var water: Node3D = root.get_node_or_null("WaterVolume") as Node3D
	assert_object(water).is_not_null()
	if water != null:
		var line: float = Api.prop(definition, "water_line_height_m", Api.MISSING_NUMBER)
		assert_float(water.position.y).is_equal_approx(line / 2.0, Glb.MM)


func test_ac14_lamp_mount_is_at_the_top_of_the_trim_from_the_catalog_height() -> void:
	var definition: Resource = _definition()
	var root: Node3D = _scene_root(definition)
	assert_object(root).is_not_null()
	if root == null:
		return
	var mount: Node3D = root.get_node_or_null("lamp_mount") as Node3D
	assert_object(mount).is_not_null()
	if mount != null:
		var interior: Vector3 = Api.prop(definition, "interior_size_m", Vector3.ZERO)
		assert_float(mount.position.y).is_equal_approx(interior.y + 0.01, Glb.MM)
