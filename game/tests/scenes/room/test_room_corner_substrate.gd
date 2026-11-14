# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #28 criteria 13 and 14 (owner: developer for room_corner.gd; the layer node itself is the
## technical-artist's): the room shows the substrate of the model on the layer at the
## SubstrateAnchor. For each of the three tanks and each of the five types the tint equals the
## model colour and grain_scale, grain_shape and grain_contrast equal the catalog values of the
## type, in the same frame as substrate_changed (no frame is awaited between the Command and the
## check). The comparison is against the catalog, never against hard-coded numbers. An empty or
## unknown id shows the default look silently (ADR 0010 rule 6). The view never validates.

const Api := preload("res://tests/helpers/late_api.gd")
const Rig := preload("res://tests/helpers/room_rig.gd")
const Sub := preload("res://tests/helpers/substrate_api.gd")
const Scene := preload("res://tests/helpers/substrate_scene_rig.gd")
const Table := preload("res://tests/helpers/tank_table.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")

var _tanks: RefCounted = null
var _substrates: RefCounted = null
var _history: CommandHistory = null


func before_test() -> void:
	_tanks = Rig.default_catalog()
	_substrates = Sub.catalog()
	_history = CommandHistory.new()


func _room(model: AquariumModel) -> Node3D:
	var room: Node3D = Rig.instantiate(model, _tanks)
	add_child(room)
	auto_free(room)
	await get_tree().process_frame
	return room


func _assert_shows(room: Node3D, id: StringName, colour: Color, label: String) -> void:
	var layer: MeshInstance3D = Scene.layer_of_room(room)
	(
		assert_object(layer)
		. override_failure_message("%s: %s is missing" % [label, Scene.LAYER_IN_ROOM])
		. is_not_null()
	)
	if layer != null:
		(
			assert_str(Scene.mismatch(layer, _substrates, id, colour))
			. override_failure_message(label)
			. is_empty()
		)


## Picks a type the way the chooser does (colour from the pick helper); nothing when it is in use.
func _pick(model: AquariumModel, id: StringName) -> void:
	if model.get_substrate_id() == id:
		return
	var colour: Color = Sub.pick(
		_substrates, model.get_substrate_id(), model.get_substrate_colour(), id
	)
	assert_bool(_history.execute(Sub.command(model, _substrates, id, colour))).is_true()


# --- AC 14: all tanks, all types ---


func test_ac14_each_tank_shows_each_type_with_its_default_colour_in_the_same_frame() -> void:
	for tank_id: StringName in Table.IDS:
		var model: AquariumModel = Sub.model_with(
			Sub.SAND, Sub.default_colour(_substrates, Sub.SAND), tank_id
		)
		var room: Node3D = await _room(model)
		_assert_shows(room, Sub.SAND, model.get_substrate_colour(), "%s start" % tank_id)
		for id: StringName in [Sub.GRAVEL, Sub.PEBBLES, Sub.BLACK, Sub.COLOURED, Sub.SAND]:
			_pick(model, id)
			# No frame is awaited: the room reacts inside the signal handler.
			_assert_shows(room, id, model.get_substrate_colour(), "%s %s" % [tank_id, id])


func test_ac14_each_tank_shows_swatch_2_of_each_type_in_the_same_frame() -> void:
	for tank_id: StringName in Table.IDS:
		var model: AquariumModel = Sub.model_with(
			Sub.SAND, Sub.default_colour(_substrates, Sub.SAND), tank_id
		)
		var room: Node3D = await _room(model)
		for id: StringName in Sub.IDS:
			_pick(model, id)
			var second: Color = Sub.swatch(_substrates, id, 2)
			assert_bool(_history.execute(Sub.command(model, _substrates, id, second))).is_true()
			_assert_shows(room, id, second, "%s %s swatch 2" % [tank_id, id])


func test_ac14_the_tint_equals_the_model_colour_at_build_for_every_type_and_tank() -> void:
	for tank_id: StringName in Table.IDS:
		for id: StringName in Sub.IDS:
			var colour: Color = Sub.default_colour(_substrates, id)
			var room: Node3D = await _room(Sub.model_with(id, colour, tank_id))
			_assert_shows(room, id, colour, "%s %s at build" % [tank_id, id])


func test_ac14_undo_and_redo_move_the_look_in_the_same_frame() -> void:
	var model: AquariumModel = Sub.model_with(Sub.SAND, Sub.SAND_DEFAULT)
	var room: Node3D = await _room(model)
	_pick(model, Sub.PEBBLES)
	assert_bool(_history.undo()).is_true()
	_assert_shows(room, Sub.SAND, Sub.SAND_DEFAULT, "after undo")
	assert_bool(_history.redo()).is_true()
	_assert_shows(room, Sub.PEBBLES, model.get_substrate_colour(), "after redo")


func test_ac14_a_model_reset_refreshes_the_look() -> void:
	var model: AquariumModel = Sub.model_with(Sub.SAND, Sub.SAND_DEFAULT)
	var room: Node3D = await _room(model)
	var other: AquariumModel = Sub.model_with(
		Sub.COLOURED, Sub.swatch(_substrates, Sub.COLOURED, 3)
	)
	model.reset_from(other)
	_assert_shows(room, Sub.COLOURED, Sub.swatch(_substrates, Sub.COLOURED, 3), "after reset")


func test_ac14_a_loaded_non_swatch_colour_is_shown_as_it_is() -> void:
	var model: AquariumModel = Sub.model_with(Sub.SAND, Sub.NOT_A_SWATCH)
	var room: Node3D = await _room(model)
	_assert_shows(room, Sub.SAND, Sub.NOT_A_SWATCH, "non-swatch colour")


func test_ac14_the_room_never_writes_the_model() -> void:
	var model: AquariumModel = Sub.model_with(Sub.GRAVEL, Sub.NOT_A_SWATCH)
	var room: Node3D = await _room(model)
	assert_object(Scene.layer_of_room(room)).override_failure_message("no layer").is_not_null()
	assert_that(model.get_substrate_id()).is_equal(Sub.GRAVEL)
	assert_that(model.get_substrate_colour()).is_equal(Sub.NOT_A_SWATCH)


# --- ADR 0010 rule 6: the view never validates ---


func test_ac11_an_unknown_id_shows_the_default_look_silently() -> void:
	var model: AquariumModel = Sub.model_with(Sub.UNKNOWN_ID, Sub.NOT_A_SWATCH)
	var seen: Dictionary = await EngineOutput.capture_result(
		func() -> Variant: return await _room(model)
	)
	var room: Node3D = seen["result"]
	_assert_shows(room, Sub.SAND, Sub.default_colour(_substrates, Sub.SAND), "unknown id")
	assert_dict(seen["errors"]).is_empty()
	assert_dict(seen["warnings"]).is_empty()


func test_ac11_an_empty_id_shows_the_default_look_silently() -> void:
	var model: AquariumModel = Sub.model_with(&"", Color.WHITE)
	var seen: Dictionary = await EngineOutput.capture_result(
		func() -> Variant: return await _room(model)
	)
	var room: Node3D = seen["result"]
	_assert_shows(room, Sub.SAND, Sub.default_colour(_substrates, Sub.SAND), "empty id")
	assert_dict(seen["errors"]).is_empty()
	assert_dict(seen["warnings"]).is_empty()


func test_ac11_a_bare_model_shows_the_default_look_silently() -> void:
	var model: AquariumModel = Rig.model_with(Table.MEDIUM)
	var seen: Dictionary = await EngineOutput.capture_result(
		func() -> Variant: return await _room(model)
	)
	var room: Node3D = seen["result"]
	_assert_shows(room, Sub.SAND, Sub.default_colour(_substrates, Sub.SAND), "bare model")
	assert_dict(seen["errors"]).is_empty()
	assert_dict(seen["warnings"]).is_empty()


# --- AC 13: the tank change keeps the floor ---


func test_ac13_the_new_tank_shows_the_same_floor_after_a_tank_change() -> void:
	var colour: Color = Sub.swatch(_substrates, Sub.PEBBLES, 2)
	var model: AquariumModel = Sub.model_with(Sub.PEBBLES, colour, Table.SMALL)
	var room: Node3D = await _room(model)
	_assert_shows(room, Sub.PEBBLES, colour, "small")
	for target: StringName in [Table.LARGE, Table.MEDIUM, Table.SMALL]:
		assert_bool(_history.execute(Api.change_tank(model, _tanks, target))).is_true()
		await get_tree().process_frame
		assert_that(Api.call_on(room, "get_displayed_tank_id", [], &"")).is_equal(target)
		assert_that(model.get_substrate_id()).is_equal(Sub.PEBBLES)
		assert_bool(Sub.same_colour(model.get_substrate_colour(), colour)).is_true()
		_assert_shows(room, Sub.PEBBLES, colour, "after the change to %s" % target)


func test_ac13_a_substrate_change_after_a_tank_change_reaches_the_new_layer() -> void:
	var model: AquariumModel = Sub.model_with(Sub.SAND, Sub.SAND_DEFAULT, Table.SMALL)
	var room: Node3D = await _room(model)
	assert_bool(_history.execute(Api.change_tank(model, _tanks, Table.LARGE))).is_true()
	await get_tree().process_frame
	_pick(model, Sub.COLOURED)
	_assert_shows(room, Sub.COLOURED, model.get_substrate_colour(), "large after the pick")


func test_ac13_exactly_one_layer_exists_after_tank_changes() -> void:
	var model: AquariumModel = Sub.model_with(Sub.SAND, Sub.SAND_DEFAULT, Table.SMALL)
	var room: Node3D = await _room(model)
	for target: StringName in [Table.LARGE, Table.SMALL, Table.MEDIUM]:
		assert_bool(_history.execute(Api.change_tank(model, _tanks, target))).is_true()
		await get_tree().process_frame
	var found: Array[Node] = room.find_children("Substrate", "MeshInstance3D", true, false)
	assert_int(found.size()).is_equal(1)
