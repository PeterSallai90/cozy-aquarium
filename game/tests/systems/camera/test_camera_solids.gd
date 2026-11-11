# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #26 criteria 5, 11 and 17 (owner: developer): CameraSolids builds the solids and the pan box
## from the tank definition and the lamp node (game/systems/camera/camera_solids.gd, ADR 0009
## rule 1). The expected boxes come from the catalog numbers of the issue #24 table and from the
## lamp scene, not from CameraSolids.

const Cz := preload("res://tests/helpers/camera_zoom_rig.gd")
const Rig := preload("res://tests/helpers/room_rig.gd")
const Table := preload("res://tests/helpers/tank_table.gd")
const Api := preload("res://tests/helpers/late_api.gd")

const STAND_Z := 0.123
const TOLERANCE := 0.0005
const CABINET_MARGIN := 0.025


func _exists() -> bool:
	(
		assert_bool(ResourceLoader.exists(Cz.SOLIDS_PATH))
		. override_failure_message("%s is missing" % Cz.SOLIDS_PATH)
		. is_true()
	)
	return ResourceLoader.exists(Cz.SOLIDS_PATH)


func _definition(id: StringName) -> Resource:
	var definition: Resource = Rig.definition_of(id)
	assert_bool(definition != null).is_true()
	return definition


func _assert_box(actual: Variant, expected: AABB, label: String) -> void:
	var box: AABB = AABB()
	if actual is AABB:
		box = actual
	else:
		fail("%s: not an AABB: %s" % [label, actual])
		return
	(
		assert_vector(box.position)
		. override_failure_message("%s position %s, expected %s" % [label, box.position, expected])
		. is_equal_approx(expected.position, Vector3.ONE * TOLERANCE)
	)
	(
		assert_vector(box.size)
		. override_failure_message("%s size %s, expected %s" % [label, box.size, expected])
		. is_equal_approx(expected.size, Vector3.ONE * TOLERANCE)
	)


func _zero_size_definition() -> Resource:
	var definition: Resource = Rig.variant(&"tank_zero", null)
	definition.set("interior_size_m", Vector3.ZERO)
	return definition


# --- the tank box ---


func test_ac10_the_tank_box_runs_from_the_cabinet_top_to_the_rim_top_on_every_tank() -> void:
	if not _exists():
		return
	for id: StringName in Table.IDS:
		var box: Variant = Cz.solids_tank_box(_definition(id), Cz.CABINET_TOP_M, STAND_Z)
		_assert_box(box, Cz.tank_box(id, STAND_Z), "%s tank box" % id)


func test_ac10_the_tank_box_includes_glass_and_trim_and_the_air_above_the_water() -> void:
	if not _exists():
		return
	for id: StringName in Table.IDS:
		var box: Variant = Cz.solids_tank_box(_definition(id), Cz.CABINET_TOP_M, STAND_Z)
		if not box is AABB:
			fail("not an AABB")
			return
		var rim: float = Cz.CABINET_TOP_M + Table.glass(id) + Table.interior(id).y + Table.TRIM_M
		assert_float((box as AABB).end.y).is_equal_approx(rim, TOLERANCE)
		assert_float((box as AABB).end.y).is_greater(
			Cz.CABINET_TOP_M + Table.glass(id) + Table.water_line(id)
		)


func test_ac17_a_tank_box_without_volume_is_a_zero_box() -> void:
	if not _exists():
		return
	var box: Variant = Cz.solids_tank_box(_zero_size_definition(), Cz.CABINET_TOP_M, STAND_Z)
	if not box is AABB:
		fail("not an AABB")
		return
	assert_float((box as AABB).get_volume()).is_equal_approx(0.0, 0.000001)


# --- the cabinet box ---


func test_ac10_the_cabinet_box_is_the_footprint_plus_the_margin_from_the_floor_to_the_top() -> void:
	if not _exists():
		return
	for id: StringName in Table.IDS:
		var box: Variant = Cz.solids_cabinet_box(
			_definition(id), Cz.CABINET_TOP_M, CABINET_MARGIN, STAND_Z
		)
		_assert_box(box, Cz.cabinet_box(id, STAND_Z), "%s cabinet box" % id)


# --- the pan box ---


func test_ac05_the_pan_box_is_the_interior_footprint_from_the_floor_to_the_water_line() -> void:
	if not _exists():
		return
	for id: StringName in Table.IDS:
		var box: Variant = Cz.solids_pan_box(
			_definition(id), Cz.CABINET_TOP_M, STAND_Z, Vector3(0.0, 0.9, STAND_Z)
		)
		_assert_box(box, Cz.pan_box(id, STAND_Z), "%s pan box" % id)


func test_ac05_the_pan_box_holds_the_default_pivot_in_its_middle() -> void:
	if not _exists():
		return
	for id: StringName in Table.IDS:
		var box: Variant = Cz.solids_pan_box(
			_definition(id), Cz.CABINET_TOP_M, STAND_Z, Vector3(0.0, 0.9, STAND_Z)
		)
		if not box is AABB:
			fail("not an AABB")
			return
		var centre: Vector3 = (box as AABB).get_center()
		assert_float(centre.x).is_equal_approx(0.0, TOLERANCE)
		assert_float(centre.z).is_equal_approx(STAND_Z, TOLERANCE)
		var water_middle: float = Cz.CABINET_TOP_M + Table.glass(id) + Table.water_line(id) / 2.0
		assert_float(centre.y).is_equal_approx(water_middle, TOLERANCE)


func test_ac17_the_pan_box_without_a_definition_collapses_to_the_pivot() -> void:
	if not _exists():
		return
	var pivot: Vector3 = Vector3(0.0, 0.95, STAND_Z)
	var box: Variant = Cz.solids_pan_box(null, Cz.CABINET_TOP_M, STAND_Z, pivot)
	_assert_box(box, AABB(pivot, Vector3.ZERO), "no definition")


func test_ac17_the_pan_box_of_a_zero_size_definition_collapses_to_the_pivot() -> void:
	if not _exists():
		return
	var pivot: Vector3 = Vector3(0.0, 0.95, STAND_Z)
	var box: Variant = Cz.solids_pan_box(_zero_size_definition(), Cz.CABINET_TOP_M, STAND_Z, pivot)
	_assert_box(box, AABB(pivot, Vector3.ZERO), "zero-size definition")


# --- the lamp boxes ---


func _open_room(id: StringName) -> Node3D:
	var rig: Dictionary = await Cz.open_tank(self, id)
	return rig["room"]


func test_ac11_the_lamp_boxes_are_one_box_per_visible_lamp_mesh_on_every_tank() -> void:
	if not _exists():
		return
	for id: StringName in Table.IDS:
		var room: Node3D = await _open_room(id)
		var lamp: Node3D = room.get_node("Lamp") as Node3D
		var boxes: Variant = Cz.solids_lamp_boxes(lamp, room.global_transform)
		var expected: Array[AABB] = Cz.lamp_boxes(room)
		assert_int(expected.size()).is_greater_equal(2)
		if not boxes is Array:
			fail("%s: lamp_boxes did not return an array" % id)
			continue
		assert_int((boxes as Array).size()).is_equal(expected.size())
		for want: AABB in expected:
			var found: bool = false
			for have: Variant in boxes:
				var box: AABB = have as AABB
				if (
					box.position.distance_to(want.position) < 0.001
					and box.size.distance_to(want.size) < 0.001
				):
					found = true
			(
				assert_bool(found)
				. override_failure_message("%s: no lamp box matches %s" % [id, want])
				. is_true()
			)


func test_ac11_the_lamp_bar_sits_just_above_the_rim() -> void:
	if not _exists():
		return
	var room: Node3D = await _open_room(Table.MEDIUM)
	var lamp: Node3D = room.get_node("Lamp") as Node3D
	var boxes: Variant = Cz.solids_lamp_boxes(lamp, room.global_transform)
	if not boxes is Array:
		fail("lamp_boxes did not return an array")
		return
	var rim: float = Cz.tank_box(Table.MEDIUM, Cz.stand_z(room)).end.y
	var bar_length: float = Table.lamp_bar_length(Table.MEDIUM)
	var bars: int = 0
	for have: Variant in boxes:
		var box: AABB = have as AABB
		if absf(box.size.x - bar_length) < 0.002:
			bars += 1
			assert_float(box.position.y).is_greater(rim)
			assert_float(box.position.y).is_less(rim + 0.05)
	assert_int(bars).is_equal(1)


func test_ac11_a_missing_lamp_gives_no_boxes() -> void:
	if not _exists():
		return
	var boxes: Variant = Cz.solids_lamp_boxes(null, Transform3D.IDENTITY)
	assert_that(boxes is Array and (boxes as Array).is_empty()).is_equal(true)


func test_ac11_a_hidden_lamp_gives_no_boxes() -> void:
	if not _exists():
		return
	var room: Node3D = await _open_room(Table.MEDIUM)
	var lamp: Node3D = room.get_node("Lamp") as Node3D
	lamp.visible = false
	var boxes: Variant = Cz.solids_lamp_boxes(lamp, room.global_transform)
	assert_that(boxes is Array and (boxes as Array).is_empty()).is_equal(true)


func test_ac11_a_lamp_with_a_hidden_parent_gives_no_boxes() -> void:
	if not _exists():
		return
	var room: Node3D = await _open_room(Table.MEDIUM)
	var lamp: Node3D = room.get_node("Lamp") as Node3D
	room.visible = false
	var boxes: Variant = Cz.solids_lamp_boxes(lamp, room.global_transform)
	assert_that(boxes is Array and (boxes as Array).is_empty()).is_equal(true)


func test_ac11_a_lamp_without_meshes_gives_no_boxes() -> void:
	if not _exists():
		return
	var empty: Node3D = Node3D.new()
	add_child(empty)
	auto_free(empty)
	var boxes: Variant = Cz.solids_lamp_boxes(empty, Transform3D.IDENTITY)
	assert_that(boxes is Array and (boxes as Array).is_empty()).is_equal(true)
