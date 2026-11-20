extends GdUnitTestSuite
## #32 AC 11 and 12 (scene part; owner: developer, with the shader and the catalog data of the
## technical-artist): the drawn tint of PlacedItemsView. Every GeometryInstance3D of a drawn item
## carries the instance shader parameter `item_tint`: Color(r, g, b, 1) when the item has a colour
## and its definition is colourable, Color(0, 0, 0, 0) otherwise (a colour on river_stone is kept in
## the model but drawn in the original look; an off-list colour on the amphora is drawn with
## exactly that colour). The tint is set when the node is created and on item_changed; a load
## (model_reset) and an undo follow. Two amphoras of different colours share the same mesh and the
## same surface material resources, no material_override and no surface override exist, so no
## material is created per colour.
## Test decisions: "colourable" comes from the shipped clay_amphora.tres (the technical-artist
## flips it); the rotate-hold preview does not touch the tint (the value is read back unchanged).

const Rig := preload("res://tests/helpers/placement_rig.gd")
const Session := preload("res://tests/helpers/placement_session.gd")
const Api := preload("res://tests/helpers/edit_api.gd")
const Factory := preload("res://tests/helpers/factory.gd")

const PARAM := "item_tint"
const FIRST := "a0000001"
const SECOND := "a0000002"
const STONE_UID := "a0000003"
const TEAL := Color8(0x2A, 0x7F, 0x9E)
const BRICK := Color8(0xB5, 0x4A, 0x33)
const OFF_LIST := Color8(0x01, 0x02, 0x03)

var _s: Session = null


func after_test() -> void:
	Rig.close(_s)


func _open(model: AquariumModel) -> bool:
	_s = await Rig.open(self, model)
	var complete: bool = _s.placement != null and _s.view != null
	(
		assert_bool(complete)
		. override_failure_message("RoomCorner needs a Placement child with PlacedItems")
		. is_true()
	)
	return complete


func _model() -> AquariumModel:
	var model: AquariumModel = Rig.model()
	Rig.add_item(model, FIRST, Rig.AMPHORA, -0.1, 0.0)
	Rig.add_item(model, SECOND, Rig.AMPHORA, 0.1, 0.0)
	Rig.add_item(model, STONE_UID, Rig.STONE, 0.0, 0.1)
	return model


func _geometry(uid: String) -> Array[GeometryInstance3D]:
	var found: Array[GeometryInstance3D] = []
	var node: Node3D = _s.node_for(uid)
	if node == null:
		return found
	for child: Node in node.find_children("*", "GeometryInstance3D", true, false):
		found.append(child as GeometryInstance3D)
	return found


## Asserts every geometry instance of the item has the expected tint.
func _tint_is(uid: String, expected: Color) -> void:
	var list: Array[GeometryInstance3D] = _geometry(uid)
	assert_int(list.size()).override_failure_message("%s draws nothing" % uid).is_greater(0)
	for instance: GeometryInstance3D in list:
		var value: Variant = instance.get_instance_shader_parameter(PARAM)
		(
			assert_bool(value is Color)
			. override_failure_message("%s: item_tint is %s, not a Color" % [uid, value])
			. is_true()
		)
		if value is Color:
			(
				assert_bool((value as Color).is_equal_approx(expected))
				. override_failure_message("%s: item_tint %s, expected %s" % [uid, value, expected])
				. is_true()
			)


func _original(uid: String) -> void:
	_tint_is(uid, Color(0.0, 0.0, 0.0, 0.0))


func _have_commands() -> bool:
	var found: bool = Api.exists(Api.RECOLOUR) and Api.exists(Api.DELETE)
	(
		assert_bool(found)
		. override_failure_message("recolour_item_command.gd or delete_item_command.gd is missing")
		. is_true()
	)
	return found


func _set_colour(uid: String, colour: Color) -> void:
	assert_bool(_s.history.execute(Api.recolour_command(_s.model, uid, true, colour))).is_true()
	await _s.frame()


func test_ac11_an_item_without_colour_has_alpha_0_so_it_draws_in_the_original_look() -> void:
	if not await _open(_model()):
		return
	_original(FIRST)
	_original(STONE_UID)


func test_ac11_a_coloured_amphora_is_drawn_with_the_stored_colour_and_alpha_1() -> void:
	var model: AquariumModel = _model()
	model.get_item(FIRST).has_colour = true
	model.get_item(FIRST).colour = TEAL
	if not await _open(model):
		return
	_tint_is(FIRST, Color(TEAL.r, TEAL.g, TEAL.b, 1.0))
	_original(SECOND)


func test_ac11_two_amphoras_of_different_colours_share_mesh_and_material_resources() -> void:
	var model: AquariumModel = _model()
	model.get_item(FIRST).has_colour = true
	model.get_item(FIRST).colour = TEAL
	model.get_item(SECOND).has_colour = true
	model.get_item(SECOND).colour = BRICK
	if not await _open(model):
		return
	_tint_is(FIRST, Color(TEAL.r, TEAL.g, TEAL.b, 1.0))
	_tint_is(SECOND, Color(BRICK.r, BRICK.g, BRICK.b, 1.0))
	var one: Array[GeometryInstance3D] = _geometry(FIRST)
	var two: Array[GeometryInstance3D] = _geometry(SECOND)
	assert_int(one.size()).is_equal(two.size())
	for index: int in one.size():
		var left: MeshInstance3D = one[index] as MeshInstance3D
		var right: MeshInstance3D = two[index] as MeshInstance3D
		assert_object(left).is_not_null()
		assert_object(left.mesh).is_same(right.mesh)
		assert_int(left.mesh.get_surface_count()).is_greater(0)
		for surface: int in left.mesh.get_surface_count():
			assert_object(left.get_active_material(surface)).is_not_null()
			assert_object(left.get_active_material(surface)).is_same(
				right.get_active_material(surface)
			)
			assert_object(left.get_surface_override_material(surface)).is_null()
			assert_object(right.get_surface_override_material(surface)).is_null()
		assert_object(left.material_override).is_null()
		assert_object(right.material_override).is_null()


func test_ac11_recolouring_creates_no_material_and_no_override() -> void:
	if not _have_commands():
		return
	if not await _open(_model()):
		return
	var before_state: Material = (_geometry(FIRST)[0] as MeshInstance3D).get_active_material(0)
	await _set_colour(FIRST, TEAL)
	await _set_colour(FIRST, BRICK)
	var mesh: MeshInstance3D = _geometry(FIRST)[0] as MeshInstance3D
	assert_object(mesh.get_active_material(0)).is_same(before_state)
	assert_object(mesh.material_override).is_null()
	assert_object(mesh.get_surface_override_material(0)).is_null()


func test_ac11_the_tint_follows_a_recolour_an_undo_a_redo_and_original_colour() -> void:
	if not _have_commands():
		return
	if not await _open(_model()):
		return
	await _set_colour(FIRST, TEAL)
	_tint_is(FIRST, Color(TEAL.r, TEAL.g, TEAL.b, 1.0))
	_original(SECOND)
	await _set_colour(FIRST, BRICK)
	_tint_is(FIRST, Color(BRICK.r, BRICK.g, BRICK.b, 1.0))
	assert_bool(_s.history.undo()).is_true()
	_tint_is(FIRST, Color(TEAL.r, TEAL.g, TEAL.b, 1.0))
	assert_bool(_s.history.undo()).is_true()
	_original(FIRST)
	assert_bool(_s.history.redo()).is_true()
	assert_bool(_s.history.redo()).is_true()
	_tint_is(FIRST, Color(BRICK.r, BRICK.g, BRICK.b, 1.0))
	(
		assert_bool(_s.history.execute(Api.recolour_command(_s.model, FIRST, false, Color.WHITE)))
		. is_true()
	)
	_original(FIRST)


func test_ac11_after_a_load_each_item_is_drawn_with_its_own_tint() -> void:
	var saved: AquariumModel = _model()
	saved.get_item(FIRST).has_colour = true
	saved.get_item(FIRST).colour = TEAL
	saved.get_item(SECOND).has_colour = true
	saved.get_item(SECOND).colour = BRICK
	var encoded: SaveResult = SaveCodec.new().encode(saved, Rig.STAMP)
	var decoded: SaveResult = SaveCodec.new().decode(encoded.text, Rig.STAMP)
	assert_int(decoded.kind).is_equal(SaveResult.Kind.OK)
	if not await _open(_model()):
		return
	_original(FIRST)
	_s.model.reset_from(decoded.model)
	await _s.frame()
	_tint_is(FIRST, Color(TEAL.r, TEAL.g, TEAL.b, 1.0))
	_tint_is(SECOND, Color(BRICK.r, BRICK.g, BRICK.b, 1.0))


func test_ac12_a_colour_on_a_non_colourable_item_is_kept_but_drawn_in_the_original_look() -> void:
	var model: AquariumModel = _model()
	model.get_item(STONE_UID).has_colour = true
	model.get_item(STONE_UID).colour = TEAL
	if not await _open(model):
		return
	_original(STONE_UID)
	assert_bool(_s.model.get_item(STONE_UID).has_colour).is_true()
	assert_int(_s.model.get_item(STONE_UID).colour.to_rgba32()).is_equal(TEAL.to_rgba32())


func test_ac12_a_colour_set_on_a_non_colourable_item_later_is_still_drawn_original() -> void:
	if not await _open(_model()):
		return
	var changed: PlacedItem = _s.model.get_item(STONE_UID).copy()
	changed.has_colour = true
	changed.colour = BRICK
	assert_bool(_s.model.apply_replace_item(changed)).is_true()
	await _s.frame()
	_original(STONE_UID)


func test_ac12_a_colourable_item_with_an_off_list_colour_is_drawn_with_that_exact_colour() -> void:
	var model: AquariumModel = _model()
	model.get_item(FIRST).has_colour = true
	model.get_item(FIRST).colour = OFF_LIST
	if not await _open(model):
		return
	_tint_is(FIRST, Color(OFF_LIST.r, OFF_LIST.g, OFF_LIST.b, 1.0))


func test_ac11_the_pending_rotation_of_a_hold_does_not_change_the_tint() -> void:
	var model: AquariumModel = _model()
	model.get_item(FIRST).has_colour = true
	model.get_item(FIRST).colour = TEAL
	if not await _open(model):
		return
	_s.view.call("show_pending_rotation", FIRST, 45.0)
	_tint_is(FIRST, Color(TEAL.r, TEAL.g, TEAL.b, 1.0))
	_s.view.call("clear_pending", FIRST)
	_tint_is(FIRST, Color(TEAL.r, TEAL.g, TEAL.b, 1.0))


func test_ac11_selecting_an_item_keeps_its_tint() -> void:
	var model: AquariumModel = _model()
	model.get_item(FIRST).has_colour = true
	model.get_item(FIRST).colour = TEAL
	if not await _open(model):
		return
	_s.view.call("set_selected", FIRST)
	_tint_is(FIRST, Color(TEAL.r, TEAL.g, TEAL.b, 1.0))
	_s.view.call("set_selected", "")
	_tint_is(FIRST, Color(TEAL.r, TEAL.g, TEAL.b, 1.0))


func test_ac11_an_undone_delete_draws_the_item_again_with_its_tint() -> void:
	if not _have_commands():
		return
	var model: AquariumModel = _model()
	model.get_item(FIRST).has_colour = true
	model.get_item(FIRST).colour = TEAL
	if not await _open(model):
		return
	assert_bool(_s.history.execute(Api.delete_command(_s.model, FIRST))).is_true()
	await _s.frame()
	assert_object(_s.node_for(FIRST)).is_null()
	assert_bool(_s.history.undo()).is_true()
	await _s.frame()
	_tint_is(FIRST, Color(TEAL.r, TEAL.g, TEAL.b, 1.0))
