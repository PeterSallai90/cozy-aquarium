extends GdUnitTestSuite
## #129 criterion 6 (owner: tester; regression guard): the inner faces of the glass mesh match the
## water box of the tank within 0.05 mm, for all three sizes. The mesh is built from the interior
## size and the water box equals the interior, so there is no gap and no step at the water wall.
## This passes on develop already; it keeps a later glass or water change from opening a gap.

const GlbChecks := preload("res://tests/helpers/glb_mesh_checks.gd")
const Water := preload("res://tests/helpers/water_rig.gd")
const Table := preload("res://tests/helpers/tank_table.gd")

const TOLERANCE_M := 0.00005


func _glass_vertices(tank_node: Node3D) -> PackedVector3Array:
	var glass: MeshInstance3D = tank_node.get_node_or_null("Glass") as MeshInstance3D
	assert_object(glass).override_failure_message("Tank/Glass missing").is_not_null()
	if glass == null:
		return PackedVector3Array()
	return GlbChecks.vertices_in(glass, tank_node)


## The inner face values on one axis: the second smallest and the second largest distinct value
## (the smallest and largest are the outer faces).
func _inner_faces(points: PackedVector3Array, axis: int) -> Vector2:
	var values: Array[float] = GlbChecks.distinct_values(points, axis)
	if values.size() < 4:
		return Vector2(INF, INF)
	return Vector2(values[1], values[values.size() - 2])


func test_ac06_the_glass_inner_faces_match_the_water_box_for_every_size() -> void:
	for id: StringName in Table.IDS:
		var tank_node: Node3D = Water.built_tank(id)
		auto_free(tank_node)
		var water: Node3D = Water.water_of(tank_node)
		assert_bool(Water.is_built(water)).override_failure_message("%s: not built" % id).is_true()
		var box: AABB = Water.bounds_of(water)
		var points: PackedVector3Array = _glass_vertices(tank_node)
		assert_int(points.size()).override_failure_message("%s: no glass" % id).is_greater(0)
		var x_faces: Vector2 = _inner_faces(points, Vector3.AXIS_X)
		var z_faces: Vector2 = _inner_faces(points, Vector3.AXIS_Z)
		var checks: Dictionary = {
			"x min": [x_faces.x, box.position.x],
			"x max": [x_faces.y, box.end.x],
			"z min": [z_faces.x, box.position.z],
			"z max": [z_faces.y, box.end.z],
		}
		for label: String in checks:
			var pair: Array = checks[label]
			(
				assert_float(float(pair[0]))
				. override_failure_message("%s: glass inner face %s vs water box" % [id, label])
				. is_equal_approx(float(pair[1]), TOLERANCE_M)
			)


func test_ac06_the_glass_inner_floor_is_at_the_water_box_bottom() -> void:
	for id: StringName in Table.IDS:
		var tank_node: Node3D = Water.built_tank(id)
		auto_free(tank_node)
		var box: AABB = Water.bounds_of(Water.water_of(tank_node))
		var points: PackedVector3Array = _glass_vertices(tank_node)
		var y_values: Array[float] = GlbChecks.distinct_values(points, Vector3.AXIS_Y)
		# The bottom pane spans y in [-g, 0]: the inner floor is the distinct value nearest to 0.
		var floor_y: float = INF
		for value: float in y_values:
			if absf(value) < absf(floor_y):
				floor_y = value
		(
			assert_float(floor_y)
			. override_failure_message("%s: glass inner floor vs water box bottom" % id)
			. is_equal_approx(box.position.y, TOLERANCE_M)
		)
