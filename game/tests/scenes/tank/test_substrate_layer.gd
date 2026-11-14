# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #28 criterion 14, geometry and node contract (owner: technical-artist): every tank scene holds
## the substrate layer at SubstrateAnchor/Substrate. It is a SubstrateLayer (MeshInstance3D) with a
## flat PlaneMesh whose top face lies in the tank-local band [-0.5 mm, +0.1 mm] around the inner
## floor (technical plan 1.1: placed at -0.2 mm against z-fighting with the glass base, never
## raised, no displacement), covers the inner floor within 1 cm of every glass face, stays inside
## the exterior footprint, uses the shared substrate material and casts no shadow. apply_look sets
## the four instance shader parameters. Tank space is the tank scene root space; the scenes are
## tested outside the room, as TankWater tests do.

const Scene := preload("res://tests/helpers/substrate_scene_rig.gd")
const Sub := preload("res://tests/helpers/substrate_api.gd")
const Table := preload("res://tests/helpers/tank_table.gd")
const SourceScan := preload("res://tests/helpers/source_scan.gd")


## The tank scene of the id, with the layer; auto-freed. Fails once when the layer is missing.
func _layer(id: StringName) -> MeshInstance3D:
	var tank_node: Node3D = Scene.tank_scene(id)
	auto_free(tank_node)
	var layer: MeshInstance3D = Scene.layer_of_tank(tank_node)
	(
		assert_object(layer)
		. override_failure_message("%s: SubstrateAnchor/Substrate is missing" % id)
		. is_not_null()
	)
	return layer


func _root_of(layer: Node) -> Node3D:
	var node: Node = layer
	while node.get_parent() != null:
		node = node.get_parent()
	return node as Node3D


func _vertices(id: StringName) -> PackedVector3Array:
	var layer: MeshInstance3D = _layer(id)
	if layer == null:
		return PackedVector3Array()
	return Scene.vertices_in(layer, _root_of(layer))


# --- the node contract ---


func test_ac14_each_tank_has_a_substrate_layer_under_the_anchor() -> void:
	for id: StringName in Table.IDS:
		var layer: MeshInstance3D = _layer(id)
		if layer == null:
			continue
		assert_object(layer.get_parent()).is_instanceof(Marker3D)
		assert_str(String(layer.get_parent().name)).is_equal(Scene.ANCHOR)


func test_ac14_the_layer_uses_the_substrate_layer_script() -> void:
	for id: StringName in Table.IDS:
		var layer: MeshInstance3D = _layer(id)
		if layer == null:
			continue
		var script: Script = layer.get_script() as Script
		assert_object(script).override_failure_message("%s: no script" % id).is_not_null()
		if script != null:
			assert_str(script.resource_path).is_equal(Scene.LAYER_SCRIPT)
			assert_str(String(script.get_global_name())).is_equal("SubstrateLayer")


func test_ac14_the_anchor_stays_at_the_inner_floor_centre() -> void:
	for id: StringName in Table.IDS:
		var layer: MeshInstance3D = _layer(id)
		if layer == null:
			continue
		var anchor: Marker3D = layer.get_parent() as Marker3D
		assert_vector(anchor.position).is_equal_approx(Vector3.ZERO, Vector3.ONE * 1e-6)


func test_ac14_the_layer_is_one_flat_plane_mesh() -> void:
	for id: StringName in Table.IDS:
		var layer: MeshInstance3D = _layer(id)
		if layer == null:
			continue
		assert_object(layer.mesh).is_instanceof(PlaneMesh)
		if layer.mesh is PlaneMesh:
			assert_int((layer.mesh as PlaneMesh).orientation).is_equal(PlaneMesh.FACE_Y)


func test_ac14_the_layer_uses_the_shared_substrate_material() -> void:
	for id: StringName in Table.IDS:
		var layer: MeshInstance3D = _layer(id)
		if layer == null:
			continue
		var material: Material = layer.material_override
		(
			assert_object(material)
			. override_failure_message("%s: no material_override" % id)
			. is_not_null()
		)
		if material != null:
			assert_str(material.resource_path).is_equal(Scene.MATERIAL_PATH)
			assert_object(material).is_instanceof(ShaderMaterial)


func test_ac14_the_layer_casts_no_shadow_and_is_visible() -> void:
	for id: StringName in Table.IDS:
		var layer: MeshInstance3D = _layer(id)
		if layer == null:
			continue
		assert_int(layer.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		assert_bool(layer.visible).is_true()


func test_ac14_the_layer_is_a_single_node_with_no_children() -> void:
	for id: StringName in Table.IDS:
		var layer: MeshInstance3D = _layer(id)
		if layer != null:
			assert_int(layer.get_child_count()).is_equal(0)


# --- the geometry (Q1: the top face is the floor) ---


func test_ac14_the_top_face_lies_in_the_floor_band_for_each_tank() -> void:
	for id: StringName in Table.IDS:
		var vertices: PackedVector3Array = _vertices(id)
		assert_int(vertices.size()).override_failure_message("%s: no vertices" % id).is_greater(0)
		for vertex: Vector3 in vertices:
			(
				assert_float(vertex.y)
				. override_failure_message(
					"%s: vertex y %f is outside the floor band" % [id, vertex.y]
				)
				. is_between(Scene.TOP_MIN_M, Scene.TOP_MAX_M)
			)


func test_ac14_no_vertex_rises_above_the_floor() -> void:
	for id: StringName in Table.IDS:
		for vertex: Vector3 in _vertices(id):
			assert_float(vertex.y).is_less_equal(Scene.TOP_MAX_M)


func test_ac14_the_layer_is_placed_slightly_below_the_floor_never_raised() -> void:
	for id: StringName in Table.IDS:
		var layer: MeshInstance3D = _layer(id)
		if layer == null:
			continue
		assert_float(layer.position.y).is_between(Scene.TOP_MIN_M, 0.0)
		assert_float(layer.position.x).is_equal_approx(0.0, 1e-6)
		assert_float(layer.position.z).is_equal_approx(0.0, 1e-6)
		assert_bool(layer.transform.basis.is_equal_approx(Basis.IDENTITY)).is_true()


func test_ac14_the_layer_covers_the_inner_floor_within_one_centimetre_of_each_glass_face() -> void:
	for id: StringName in Table.IDS:
		var vertices: PackedVector3Array = _vertices(id)
		if vertices.is_empty():
			assert_bool(false).override_failure_message("%s: no vertices" % id).is_true()
			continue
		var inner: Vector3 = Table.interior(id)
		var low: Vector3 = vertices[0]
		var high: Vector3 = vertices[0]
		for vertex: Vector3 in vertices:
			low = low.min(vertex)
			high = high.max(vertex)
		var tolerance: float = Scene.ONE_CM
		assert_float(low.x).override_failure_message("%s: -x edge" % id).is_between(
			-inner.x * 0.5 - tolerance, -inner.x * 0.5 + tolerance
		)
		assert_float(high.x).override_failure_message("%s: +x edge" % id).is_between(
			inner.x * 0.5 - tolerance, inner.x * 0.5 + tolerance
		)
		assert_float(low.z).override_failure_message("%s: -z edge" % id).is_between(
			-inner.z * 0.5 - tolerance, -inner.z * 0.5 + tolerance
		)
		assert_float(high.z).override_failure_message("%s: +z edge" % id).is_between(
			inner.z * 0.5 - tolerance, inner.z * 0.5 + tolerance
		)


func test_ac14_the_layer_stays_inside_the_exterior_footprint() -> void:
	for id: StringName in Table.IDS:
		var outer: Vector3 = Table.exterior(id)
		for vertex: Vector3 in _vertices(id):
			assert_float(absf(vertex.x)).is_less_equal(outer.x * 0.5)
			assert_float(absf(vertex.z)).is_less_equal(outer.z * 0.5)


func test_ac14_the_plane_matches_the_catalog_interior_size_within_one_centimetre() -> void:
	for id: StringName in Table.IDS:
		var layer: MeshInstance3D = _layer(id)
		if layer == null or not layer.mesh is PlaneMesh:
			continue
		var size: Vector2 = (layer.mesh as PlaneMesh).size
		var inner: Vector3 = Table.interior(id)
		assert_float(size.x).is_between(inner.x - Scene.ONE_CM, inner.x + Scene.ONE_CM)
		assert_float(size.y).is_between(inner.z - Scene.ONE_CM, inner.z + Scene.ONE_CM)


# --- apply_look ---


func test_ac14_apply_look_sets_the_four_instance_shader_parameters() -> void:
	for id: StringName in Table.IDS:
		var layer: MeshInstance3D = _layer(id)
		if layer == null:
			continue
		(
			assert_bool(layer.has_method("apply_look"))
			. override_failure_message("%s: SubstrateLayer.apply_look is missing" % id)
			. is_true()
		)
		if not layer.has_method("apply_look"):
			continue
		var tint: Color = Color(0.25, 0.5, 0.75, 1.0)
		layer.call("apply_look", tint, 0.0125, 2, 0.4)
		assert_float(Scene.tint_of(layer).r).is_equal_approx(0.25, 1e-4)
		assert_float(Scene.tint_of(layer).g).is_equal_approx(0.5, 1e-4)
		assert_float(Scene.tint_of(layer).b).is_equal_approx(0.75, 1e-4)
		assert_float(float(Scene.parameter(layer, "grain_scale"))).is_equal_approx(0.0125, 1e-6)
		assert_int(int(Scene.parameter(layer, "grain_shape"))).is_equal(2)
		assert_float(float(Scene.parameter(layer, "grain_contrast"))).is_equal_approx(0.4, 1e-6)


func test_ac14_apply_look_overwrites_the_previous_look() -> void:
	var layer: MeshInstance3D = _layer(Table.MEDIUM)
	if layer == null or not layer.has_method("apply_look"):
		(
			assert_bool(false)
			. override_failure_message("SubstrateLayer.apply_look is missing")
			. is_true()
		)
		return
	layer.call("apply_look", Color(0.1, 0.2, 0.3, 1.0), 0.002, 0, 0.9)
	layer.call("apply_look", Color(0.9, 0.8, 0.7, 1.0), 0.02, 1, 0.1)
	assert_float(Scene.tint_of(layer).r).is_equal_approx(0.9, 1e-4)
	assert_float(float(Scene.parameter(layer, "grain_scale"))).is_equal_approx(0.02, 1e-6)
	assert_int(int(Scene.parameter(layer, "grain_shape"))).is_equal(1)
	assert_float(float(Scene.parameter(layer, "grain_contrast"))).is_equal_approx(0.1, 1e-6)


func test_ac14_the_layer_script_has_no_process_and_no_catalog_or_model_reference() -> void:
	var source: String = SourceScan.strip_comments(SourceScan.read(Scene.LAYER_SCRIPT))
	assert_str(source).override_failure_message("substrate_layer.gd is missing").is_not_empty()
	for forbidden: String in [
		"func _process", "func _physics_process", "SubstrateCatalog", "AquariumModel", "EventBus"
	]:
		(
			assert_str(source)
			. override_failure_message("substrate_layer.gd must not contain %s" % forbidden)
			. not_contains(forbidden)
		)


func test_ac14_the_layer_script_extends_mesh_instance_3d_and_names_the_class() -> void:
	var source: String = SourceScan.read(Scene.LAYER_SCRIPT)
	assert_str(source).contains("class_name SubstrateLayer")
	assert_str(source).contains("extends MeshInstance3D")
