extends GdUnitTestSuite
## #22 criteria 4 and 5 and #24 criterion 27 second half (owner: developer): unknown, empty and
## broken tanks fall back to the default tank, the model is never written, and a broken default
## still shows the room. Fixtures are built in code; the expected texts are the contract of the
## technical plan (ADR 0004, exact counts).

const Api := preload("res://tests/helpers/late_api.gd")
const Rig := preload("res://tests/helpers/room_rig.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")
const SaveFixtures := preload("res://tests/helpers/save_fixtures.gd")

const DEFAULT := &"tank_medium_1"
const STAMP := "2026-11-01T12:00:00Z"


func _warning_for(id: String) -> String:
	return 'RoomCorner: unknown tank id "%s"; showing the default tank "%s"' % [id, DEFAULT]


func _error_for(id: String) -> String:
	return (
		'RoomCorner: tank "%s" has no loadable scene; showing the default tank "%s"' % [id, DEFAULT]
	)


func _default_error() -> String:
	return (
		'RoomCorner: default tank "%s" has no loadable scene; showing the room without a tank'
		% DEFAULT
	)


## Builds the room inside capture and returns {"room", "seen"}.
func _build(model: AquariumModel, catalog: RefCounted) -> Dictionary:
	var made: Array[Node3D] = []
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void:
			var room: Node3D = Rig.instantiate(model, catalog)
			add_child(room)
			made.append(room)
	)
	var room: Node3D = made[0]
	auto_free(room)
	return {"room": room, "seen": seen}


func _assert_default_tank_shown(room: Node3D) -> void:
	assert_that(Rig.displayed_id(room)).is_equal(DEFAULT)
	var tank: Node3D = room.get_node_or_null("Tank") as Node3D
	assert_object(tank).is_not_null()
	if tank != null:
		var scene: PackedScene = Api.prop(Rig.default_definition(), "scene", null)
		var expected: String = scene.resource_path if scene != null else "<no scene>"
		assert_str(tank.scene_file_path).is_equal(expected)


func _assert_model_untouched(model: AquariumModel, original: StringName) -> void:
	assert_that(model.get_tank_id()).is_equal(original)
	var codec: SaveCodec = SaveCodec.new()
	var encoded: SaveResult = codec.encode(model, STAMP)
	assert_int(encoded.kind).is_equal(SaveResult.Kind.OK)
	var decoded: SaveResult = codec.decode(encoded.text, STAMP)
	assert_int(decoded.kind).is_equal(SaveResult.Kind.OK)
	if decoded.model != null:
		assert_that(decoded.model.get_tank_id()).is_equal(original)


func _assert_room_without_tank(room: Node3D) -> void:
	assert_object(room.get_node_or_null("Tank")).is_null()
	assert_that(Rig.displayed_id(room)).is_equal(&"")
	for root_name: String in ["Room", "Cabinet", "Lamp"]:
		assert_object(room.get_node_or_null(root_name)).is_instanceof(Node3D)
	assert_object(room.get_node_or_null("BuildCamera")).is_instanceof(Camera3D)


# --- AC 4 ---


func test_ac04_unknown_id_logs_one_warning_and_shows_the_default_tank() -> void:
	var model: AquariumModel = Rig.model_with(&"tank_60")
	var built: Dictionary = await _build(model, Rig.default_catalog())
	var seen: Dictionary = built["seen"]
	assert_dict(seen["warnings"]).is_equal({_warning_for("tank_60"): 1})
	assert_dict(seen["errors"]).is_empty()
	_assert_default_tank_shown(built["room"])


func test_ac04_unknown_id_leaves_the_model_id_and_the_saved_id_unchanged() -> void:
	var model: AquariumModel = Rig.model_with(&"tank_60")
	await _build(model, Rig.default_catalog())
	_assert_model_untouched(model, &"tank_60")


func test_ac04_empty_id_logs_one_warning_and_shows_the_default_tank() -> void:
	var model: AquariumModel = Rig.model_with(&"")
	var built: Dictionary = await _build(model, Rig.default_catalog())
	var seen: Dictionary = built["seen"]
	assert_dict(seen["warnings"]).is_equal({_warning_for(""): 1})
	assert_dict(seen["errors"]).is_empty()
	_assert_default_tank_shown(built["room"])


func test_ac04_empty_id_leaves_the_model_id_and_the_saved_id_unchanged() -> void:
	var model: AquariumModel = Rig.model_with(&"")
	await _build(model, Rig.default_catalog())
	_assert_model_untouched(model, &"")


func test_ac04_known_default_id_logs_nothing() -> void:
	var built: Dictionary = await _build(Rig.model_with(DEFAULT), Rig.default_catalog())
	var seen: Dictionary = built["seen"]
	assert_dict(seen["warnings"]).is_empty()
	assert_dict(seen["errors"]).is_empty()
	_assert_default_tank_shown(built["room"])


func test_ac04_new_model_shows_the_default_tank_without_logging() -> void:
	var built: Dictionary = await _build(AquariumModel.new(STAMP), Rig.default_catalog())
	var seen: Dictionary = built["seen"]
	assert_dict(seen["warnings"]).is_empty()
	assert_dict(seen["errors"]).is_empty()
	_assert_default_tank_shown(built["room"])


func test_ac04_the_room_never_writes_the_model_no_signal_is_emitted() -> void:
	var model: AquariumModel = Rig.model_with(&"tank_60")
	var emitted: Array[StringName] = []
	model.tank_changed.connect(func(id: StringName) -> void: emitted.append(id))
	await _build(model, Rig.default_catalog())
	assert_array(emitted).is_empty()


# --- AC 5 ---


func test_ac05_scene_null_logs_one_error_and_shows_the_default_tank() -> void:
	var broken: Resource = Rig.variant(&"tank_broken", null)
	var catalog: RefCounted = Api.catalog_from([Rig.default_definition(), broken])
	var model: AquariumModel = Rig.model_with(&"tank_broken")
	var built: Dictionary = await _build(model, catalog)
	var seen: Dictionary = built["seen"]
	assert_dict(seen["errors"]).is_equal({_error_for("tank_broken"): 1})
	assert_dict(seen["warnings"]).is_empty()
	_assert_default_tank_shown(built["room"])
	_assert_model_untouched(model, &"tank_broken")


func test_ac05_scene_with_a_non_node3d_root_logs_one_error_and_shows_the_default_tank() -> void:
	var broken: Resource = Rig.variant(&"tank_wrong_root", Rig.wrong_root_scene())
	var catalog: RefCounted = Api.catalog_from([Rig.default_definition(), broken])
	var model: AquariumModel = Rig.model_with(&"tank_wrong_root")
	var built: Dictionary = await _build(model, catalog)
	var seen: Dictionary = built["seen"]
	assert_dict(seen["errors"]).is_equal({_error_for("tank_wrong_root"): 1})
	assert_dict(seen["warnings"]).is_empty()
	_assert_default_tank_shown(built["room"])
	_assert_model_untouched(model, &"tank_wrong_root")


func test_ac05_broken_default_too_logs_two_errors_and_shows_the_room_without_a_tank() -> void:
	var broken: Resource = Rig.variant(&"tank_broken", null)
	var default_broken: Resource = Rig.variant(DEFAULT, null)
	var catalog: RefCounted = Api.catalog_from([default_broken, broken])
	var model: AquariumModel = Rig.model_with(&"tank_broken")
	var built: Dictionary = await _build(model, catalog)
	var seen: Dictionary = built["seen"]
	assert_dict(seen["errors"]).is_equal({_error_for("tank_broken"): 1, _default_error(): 1})
	assert_dict(seen["warnings"]).is_empty()
	_assert_room_without_tank(built["room"])
	_assert_model_untouched(model, &"tank_broken")


func test_ac05_requested_default_that_is_broken_logs_only_the_default_error() -> void:
	var default_broken: Resource = Rig.variant(DEFAULT, null)
	var catalog: RefCounted = Api.catalog_from([default_broken])
	var model: AquariumModel = Rig.model_with(DEFAULT)
	var built: Dictionary = await _build(model, catalog)
	var seen: Dictionary = built["seen"]
	assert_dict(seen["errors"]).is_equal({_default_error(): 1})
	assert_dict(seen["warnings"]).is_empty()
	_assert_room_without_tank(built["room"])
	_assert_model_untouched(model, DEFAULT)


func test_ac05_default_with_a_non_node3d_root_shows_the_room_without_a_tank() -> void:
	var default_broken: Resource = Rig.variant(DEFAULT, Rig.wrong_root_scene())
	var catalog: RefCounted = Api.catalog_from([default_broken])
	var built: Dictionary = await _build(Rig.model_with(DEFAULT), catalog)
	var seen: Dictionary = built["seen"]
	assert_dict(seen["errors"]).is_equal({_default_error(): 1})
	_assert_room_without_tank(built["room"])


func test_ac05_unknown_id_and_missing_default_logs_the_warning_and_the_default_error() -> void:
	var catalog: RefCounted = Api.catalog_from([])
	var model: AquariumModel = Rig.model_with(&"tank_60")
	var built: Dictionary = await _build(model, catalog)
	var seen: Dictionary = built["seen"]
	assert_dict(seen["warnings"]).is_equal({_warning_for("tank_60"): 1})
	assert_dict(seen["errors"]).is_equal({_default_error(): 1})
	_assert_room_without_tank(built["room"])
	_assert_model_untouched(model, &"tank_60")


# --- #24 AC 27: a save from before the rename ---


func test_ac27_a_save_holding_the_old_medium_id_shows_medium_with_one_warning_and_keeps_the_id(
) -> void:
	var dir: String = SaveFixtures.make_dir("tank_old_id")
	var path: String = dir.path_join("old.json")
	var store: SaveStore = SaveStore.new()
	var old_model: AquariumModel = Rig.model_with(&"tank_medium_60l")
	assert_bool(store.save(old_model, path).is_ok()).is_true()
	var loaded: AquariumModel = AquariumModel.new(STAMP)
	assert_bool(store.load_into(path, loaded, CommandHistory.new()).is_ok()).is_true()
	assert_that(loaded.get_tank_id()).is_equal(&"tank_medium_60l")
	var built: Dictionary = await _build(loaded, Rig.default_catalog())
	var seen: Dictionary = built["seen"]
	# No alias (owner decision 2026-11-09): the #22 unknown-id rule, one warning, not an error.
	assert_dict(seen["warnings"]).is_equal({_warning_for("tank_medium_60l"): 1})
	assert_dict(seen["errors"]).is_empty()
	_assert_default_tank_shown(built["room"])
	_assert_model_untouched(loaded, &"tank_medium_60l")
	SaveFixtures.remove_dir(dir)
	SaveFixtures.remove_root_if_empty()


func test_ac27_the_old_id_is_not_in_the_catalog_so_nothing_aliases_it() -> void:
	assert_object(Api.definition_of(Rig.default_catalog(), &"tank_medium_60l")).is_null()
