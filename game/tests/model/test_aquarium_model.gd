# gdlint: disable=max-public-methods
extends GdUnitTestSuite

const Factory := preload("res://tests/helpers/factory.gd")
const ModelState := preload("res://tests/helpers/model_state.gd")
const SignalRecorder := preload("res://tests/helpers/signal_recorder.gd")
const ErrorContains := preload("res://tests/helpers/error_contains.gd")
const SetTankCommand := preload("res://tests/helpers/commands/set_tank_command.gd")

const FIXED_CLOCK := "2026-10-27T18:00:00Z"


func _model() -> AquariumModel:
	return AquariumModel.new(FIXED_CLOCK)


func _watched(model: Object) -> SignalRecorder:
	var recorder: SignalRecorder = SignalRecorder.new()
	recorder.watch(model)
	return recorder


func _filled_model() -> AquariumModel:
	var model: AquariumModel = _model()
	model.apply_set_name("Reef")
	model.apply_set_tank_id(&"tank_60")
	model.apply_set_substrate(&"sand", Color(0.8, 0.7, 0.5))
	model.apply_set_heightmap(PackedFloat32Array([0.0, 0.01, 0.02, 0.03]), Vector2i(2, 2))
	for uid: String in ["a0000001", "a0000002", "a0000003"]:
		model.apply_insert_item(Factory.item(uid), model.get_item_count())
	for uid: String in ["f0000001", "f0000002"]:
		model.apply_insert_fish(Factory.fish(uid, &"guppy", 2, "Bubbles"), model.get_fish_count())
	return model


# --- schema and defaults -------------------------------------------------------------------


func test_new_model_has_schema_fields() -> void:
	var model: AquariumModel = _model()
	assert_int(typeof(model.get_aquarium_name())).is_equal(TYPE_STRING)
	assert_int(typeof(model.get_tank_id())).is_equal(TYPE_STRING_NAME)
	assert_int(typeof(model.get_substrate_id())).is_equal(TYPE_STRING_NAME)
	assert_int(typeof(model.get_substrate_colour())).is_equal(TYPE_COLOR)
	assert_int(typeof(model.get_heightmap())).is_equal(TYPE_PACKED_FLOAT32_ARRAY)
	assert_int(typeof(model.get_heightmap_size())).is_equal(TYPE_VECTOR2I)
	assert_int(typeof(model.get_created())).is_equal(TYPE_STRING)
	assert_int(typeof(model.get_modified())).is_equal(TYPE_STRING)
	assert_array(model.get_items()).is_empty()
	assert_array(model.get_fish_list()).is_empty()


func test_placed_item_fields_and_defaults() -> void:
	var item: PlacedItem = PlacedItem.new()
	assert_str(item.uid).is_equal("")
	assert_int(typeof(item.catalog_id)).is_equal(TYPE_STRING_NAME)
	assert_vector(item.position).is_equal(Vector3.ZERO)
	assert_float(item.rotation_y).is_equal(0.0)
	assert_float(item.scale).is_equal(1.0)
	assert_bool(item.has_colour).is_false()
	assert_that(item.colour).is_equal(Color.WHITE)


func test_fish_instance_fields_and_defaults() -> void:
	var fish: FishInstance = FishInstance.new()
	assert_str(fish.uid).is_equal("")
	assert_int(typeof(fish.species_id)).is_equal(TYPE_STRING_NAME)
	assert_int(fish.variant).is_equal(0)
	assert_str(fish.nickname).is_equal("")


func test_placed_item_copy_copies_every_field() -> void:
	var item: PlacedItem = Factory.coloured_item("a1b2c3d4", Color(0.1, 0.2, 0.3, 0.4))
	var copy: PlacedItem = item.copy()
	assert_bool(is_same(copy, item)).is_false()
	assert_str(copy.uid).is_equal("a1b2c3d4")
	assert_that(copy.catalog_id).is_equal(item.catalog_id)
	assert_vector(copy.position).is_equal(item.position)
	assert_float(copy.rotation_y).is_equal(item.rotation_y)
	assert_float(copy.scale).is_equal(item.scale)
	assert_bool(copy.has_colour).is_true()
	assert_that(copy.colour).is_equal(Color(0.1, 0.2, 0.3, 0.4))
	copy.position = Vector3.ONE
	assert_vector(item.position).is_not_equal(Vector3.ONE)


func test_fish_instance_copy_copies_every_field() -> void:
	var fish: FishInstance = Factory.fish("f1b2c3d4", &"guppy", 3, "Blub")
	var copy: FishInstance = fish.copy()
	assert_bool(is_same(copy, fish)).is_false()
	assert_str(copy.uid).is_equal("f1b2c3d4")
	assert_that(copy.species_id).is_equal(&"guppy")
	assert_int(copy.variant).is_equal(3)
	assert_str(copy.nickname).is_equal("Blub")


func test_new_model_defaults() -> void:
	var model: AquariumModel = _model()
	assert_str(model.get_aquarium_name()).is_equal("")
	assert_that(model.get_tank_id()).is_equal(&"")
	assert_that(model.get_substrate_id()).is_equal(&"")
	assert_that(model.get_substrate_colour()).is_equal(Color.WHITE)
	assert_int(model.get_heightmap().size()).is_equal(0)
	assert_that(model.get_heightmap_size()).is_equal(Vector2i.ZERO)
	assert_int(model.get_item_count()).is_equal(0)
	assert_int(model.get_fish_count()).is_equal(0)


func test_new_model_timestamps_injected() -> void:
	var model: AquariumModel = _model()
	assert_str(model.get_created()).is_equal(FIXED_CLOCK)
	assert_str(model.get_modified()).is_equal(FIXED_CLOCK)


func test_new_model_timestamps_from_clock() -> void:
	var before: float = Time.get_unix_time_from_system()
	var model: AquariumModel = AquariumModel.new()
	var after: float = Time.get_unix_time_from_system()
	var pattern: RegEx = RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$")
	assert_object(pattern.search(model.get_created())).is_not_null()
	assert_str(model.get_modified()).is_equal(model.get_created())
	var created: float = Time.get_unix_time_from_datetime_string(model.get_created())
	assert_float(created).is_greater_equal(before - 1.0)
	assert_float(created).is_less_equal(after + 1.0)


func test_model_records_are_not_nodes() -> void:
	var instances: Array[Variant] = [_model(), PlacedItem.new(), FishInstance.new()]
	for instance: Variant in instances:
		assert_bool(instance is Node).is_false()
		assert_bool(instance is RefCounted).is_true()


# --- names -----------------------------------------------------------------------------------


func test_names_stored_unchanged() -> void:
	var samples: Array[String] = [
		"",
		"Árvíztűrő tükörfúrógép",
		"熱帯魚 열대어 Аквариум",
		"x".repeat(10000),
	]
	for text: String in samples:
		var model: AquariumModel = _model()
		model.apply_set_name(text)
		assert_str(model.get_aquarium_name()).is_equal(text)
		var inserted: bool = model.apply_insert_fish(Factory.fish("f0000001", &"guppy", 0, text), 0)
		assert_bool(inserted).is_true()
		assert_str(model.get_fish("f0000001").nickname).is_equal(text)


# --- signals ---------------------------------------------------------------------------------


func test_apply_set_name_emits() -> void:
	var model: AquariumModel = _model()
	var recorder: SignalRecorder = _watched(model)
	model.apply_set_name("Reef")
	assert_array(recorder.events).is_equal([["name_changed", ["Reef"]]])
	assert_str(model.get_aquarium_name()).is_equal("Reef")


func test_apply_set_tank_emits() -> void:
	var model: AquariumModel = _model()
	var recorder: SignalRecorder = _watched(model)
	model.apply_set_tank_id(&"tank_60")
	assert_array(recorder.events).is_equal([["tank_changed", [&"tank_60"]]])
	assert_that(model.get_tank_id()).is_equal(&"tank_60")


func test_apply_set_substrate_emits() -> void:
	var model: AquariumModel = _model()
	var recorder: SignalRecorder = _watched(model)
	model.apply_set_substrate(&"sand", Color(0.5, 0.25, 0.125))
	assert_array(recorder.events).is_equal(
		[["substrate_changed", [&"sand", Color(0.5, 0.25, 0.125)]]]
	)
	assert_that(model.get_substrate_id()).is_equal(&"sand")
	assert_that(model.get_substrate_colour()).is_equal(Color(0.5, 0.25, 0.125))


func test_apply_set_heightmap_emits() -> void:
	var model: AquariumModel = _model()
	var recorder: SignalRecorder = _watched(model)
	var values: PackedFloat32Array = PackedFloat32Array([0.0, 0.5, 1.0, 1.5, 2.0, 2.5])
	model.apply_set_heightmap(values, Vector2i(3, 2))
	assert_array(recorder.events).is_equal([["heightmap_changed", [Rect2i(0, 0, 3, 2)]]])
	assert_that(model.get_heightmap()).is_equal(values)
	assert_that(model.get_heightmap_size()).is_equal(Vector2i(3, 2))


func test_apply_insert_item_emits_uid_and_index() -> void:
	var model: AquariumModel = _model()
	model.apply_insert_item(Factory.item("a0000001"), 0)
	var recorder: SignalRecorder = _watched(model)
	var ok: bool = model.apply_insert_item(Factory.item("a0000002"), 0)
	assert_bool(ok).is_true()
	assert_array(recorder.events).is_equal([["item_added", ["a0000002", 0]]])
	assert_str(model.get_items()[0].uid).is_equal("a0000002")
	assert_str(model.get_items()[1].uid).is_equal("a0000001")


func test_apply_remove_item_emits_uid_and_old_index() -> void:
	var model: AquariumModel = _filled_model()
	var recorder: SignalRecorder = _watched(model)
	var ok: bool = model.apply_remove_item("a0000002")
	assert_bool(ok).is_true()
	assert_array(recorder.events).is_equal([["item_removed", ["a0000002", 1]]])
	assert_int(model.get_item_count()).is_equal(2)
	assert_object(model.get_item("a0000002")).is_null()


func test_apply_replace_item_emits() -> void:
	var model: AquariumModel = _filled_model()
	var recorder: SignalRecorder = _watched(model)
	var replacement: PlacedItem = model.get_item("a0000002").copy()
	replacement.rotation_y = 90.0
	var ok: bool = model.apply_replace_item(replacement)
	assert_bool(ok).is_true()
	assert_array(recorder.events).is_equal([["item_changed", ["a0000002", 1]]])
	assert_bool(is_same(model.get_item_at(1), replacement)).is_true()
	assert_int(model.get_item_count()).is_equal(3)


func test_apply_insert_fish_emits_uid_and_index() -> void:
	var model: AquariumModel = _model()
	model.apply_insert_fish(Factory.fish("f0000001"), 0)
	var recorder: SignalRecorder = _watched(model)
	var ok: bool = model.apply_insert_fish(Factory.fish("f0000002"), 1)
	assert_bool(ok).is_true()
	assert_array(recorder.events).is_equal([["fish_added", ["f0000002", 1]]])


func test_apply_remove_fish_emits_uid_and_old_index() -> void:
	var model: AquariumModel = _filled_model()
	var recorder: SignalRecorder = _watched(model)
	var ok: bool = model.apply_remove_fish("f0000001")
	assert_bool(ok).is_true()
	assert_array(recorder.events).is_equal([["fish_removed", ["f0000001", 0]]])
	assert_int(model.get_fish_count()).is_equal(1)


func test_apply_replace_fish_emits() -> void:
	var model: AquariumModel = _filled_model()
	var recorder: SignalRecorder = _watched(model)
	var replacement: FishInstance = model.get_fish("f0000002").copy()
	replacement.nickname = "Nemo"
	var ok: bool = model.apply_replace_fish(replacement)
	assert_bool(ok).is_true()
	assert_array(recorder.events).is_equal([["fish_changed", ["f0000002", 1]]])
	assert_str(model.get_fish_at(1).nickname).is_equal("Nemo")


func test_signals_are_emitted_synchronously() -> void:
	var model: AquariumModel = _model()
	var recorder: SignalRecorder = _watched(model)
	model.apply_set_name("Now")
	assert_int(recorder.count()).is_equal(1)
	model.apply_insert_item(Factory.item("a0000001"), 0)
	assert_int(recorder.count()).is_equal(2)


# --- apply_ failures -------------------------------------------------------------------------


func test_apply_insert_rejects_duplicate_uid_across_items_and_fish() -> void:
	var model: AquariumModel = _filled_model()
	var before: Dictionary = ModelState.snapshot(model)
	var recorder: SignalRecorder = _watched(model)
	assert_bool(model.apply_insert_item(Factory.item("a0000001"), 0)).is_false()
	assert_bool(model.apply_insert_item(Factory.item("f0000001"), 0)).is_false()
	assert_bool(model.apply_insert_fish(Factory.fish("f0000002"), 0)).is_false()
	assert_bool(model.apply_insert_fish(Factory.fish("a0000003"), 0)).is_false()
	assert_dict(ModelState.snapshot(model)).is_equal(before)
	assert_array(recorder.events).is_empty()


func test_apply_insert_rejects_null_and_empty_uid() -> void:
	var model: AquariumModel = _model()
	var recorder: SignalRecorder = _watched(model)
	assert_bool(model.apply_insert_item(null, 0)).is_false()
	assert_bool(model.apply_insert_item(Factory.item(""), 0)).is_false()
	assert_bool(model.apply_insert_fish(null, 0)).is_false()
	assert_bool(model.apply_insert_fish(Factory.fish(""), 0)).is_false()
	assert_int(model.get_item_count()).is_equal(0)
	assert_int(model.get_fish_count()).is_equal(0)
	assert_array(recorder.events).is_empty()


func test_apply_insert_rejects_bad_index() -> void:
	var model: AquariumModel = _filled_model()
	var before: Dictionary = ModelState.snapshot(model)
	var recorder: SignalRecorder = _watched(model)
	assert_bool(model.apply_insert_item(Factory.item("b0000001"), -1)).is_false()
	assert_bool(model.apply_insert_item(Factory.item("b0000001"), 4)).is_false()
	assert_bool(model.apply_insert_fish(Factory.fish("b0000002"), -1)).is_false()
	assert_bool(model.apply_insert_fish(Factory.fish("b0000002"), 3)).is_false()
	assert_dict(ModelState.snapshot(model)).is_equal(before)
	assert_array(recorder.events).is_empty()
	# An index equal to the count is valid (append).
	assert_bool(model.apply_insert_item(Factory.item("b0000001"), 3)).is_true()


func test_apply_remove_unknown_returns_false() -> void:
	var model: AquariumModel = _filled_model()
	var before: Dictionary = ModelState.snapshot(model)
	var recorder: SignalRecorder = _watched(model)
	assert_bool(model.apply_remove_item("zzzzzzzz")).is_false()
	assert_bool(model.apply_remove_fish("zzzzzzzz")).is_false()
	assert_bool(model.apply_remove_item("f0000001")).is_false()
	assert_dict(ModelState.snapshot(model)).is_equal(before)
	assert_array(recorder.events).is_empty()


func test_apply_replace_unknown_returns_false() -> void:
	var model: AquariumModel = _filled_model()
	var before: Dictionary = ModelState.snapshot(model)
	var recorder: SignalRecorder = _watched(model)
	assert_bool(model.apply_replace_item(Factory.item("zzzzzzzz"))).is_false()
	assert_bool(model.apply_replace_item(null)).is_false()
	assert_bool(model.apply_replace_fish(Factory.fish("zzzzzzzz"))).is_false()
	assert_bool(model.apply_replace_fish(null)).is_false()
	assert_dict(ModelState.snapshot(model)).is_equal(before)
	assert_array(recorder.events).is_empty()


func test_model_keeps_the_instance_it_receives() -> void:
	var model: AquariumModel = _model()
	var item: PlacedItem = Factory.item("a0000001")
	var fish: FishInstance = Factory.fish("f0000001")
	model.apply_insert_item(item, 0)
	model.apply_insert_fish(fish, 0)
	assert_bool(is_same(model.get_item("a0000001"), item)).is_true()
	assert_bool(is_same(model.get_fish("f0000001"), fish)).is_true()


func test_get_lists_return_a_copy_of_the_list() -> void:
	var model: AquariumModel = _filled_model()
	var list: Array[PlacedItem] = model.get_items()
	list.clear()
	assert_int(model.get_item_count()).is_equal(3)
	var fish_list: Array[FishInstance] = model.get_fish_list()
	fish_list.clear()
	assert_int(model.get_fish_count()).is_equal(2)


# --- lookups ---------------------------------------------------------------------------------


func test_lookup_unknown_uid() -> void:
	var model: AquariumModel = _filled_model()
	assert_object(model.get_item("nope")).is_null()
	assert_object(model.get_fish("nope")).is_null()
	assert_int(model.get_item_index("nope")).is_equal(-1)
	assert_int(model.get_fish_index("nope")).is_equal(-1)
	assert_object(model.get_item_at(-1)).is_null()
	assert_object(model.get_item_at(3)).is_null()
	assert_object(model.get_fish_at(-1)).is_null()
	assert_object(model.get_fish_at(2)).is_null()
	assert_bool(model.has_uid("nope")).is_false()
	assert_object(model.get_item("f0000001")).is_null()
	assert_object(model.get_fish("a0000001")).is_null()


func test_lookup_known_uid() -> void:
	var model: AquariumModel = _filled_model()
	assert_int(model.get_item_index("a0000003")).is_equal(2)
	assert_int(model.get_fish_index("f0000002")).is_equal(1)
	assert_str(model.get_item("a0000002").uid).is_equal("a0000002")
	assert_str(model.get_fish_at(0).uid).is_equal("f0000001")
	assert_bool(model.has_uid("a0000001")).is_true()
	assert_bool(model.has_uid("f0000002")).is_true()


# --- reset -----------------------------------------------------------------------------------


func test_reset_from_refills_same_instance() -> void:
	var model: AquariumModel = _model()
	var source: AquariumModel = AquariumModel.new("2025-01-02T03:04:05Z")
	source.apply_set_name("Loaded")
	source.apply_insert_item(Factory.coloured_item("c0000001", Color.RED), 0)
	source.apply_insert_fish(Factory.fish("d0000001", &"guppy", 1, "Kai"), 0)
	var expected: Dictionary = ModelState.snapshot(source)
	var same: AquariumModel = model
	model.reset_from(source)
	assert_bool(is_same(model, same)).is_true()
	assert_dict(ModelState.snapshot(model)).is_equal(expected)
	assert_str(model.get_created()).is_equal("2025-01-02T03:04:05Z")
	# Items are copies, not shared with the source.
	assert_bool(is_same(model.get_item("c0000001"), source.get_item("c0000001"))).is_false()


func test_reset_from_emits_only_model_reset_once() -> void:
	var model: AquariumModel = _filled_model()
	var source: AquariumModel = _filled_model()
	var recorder: SignalRecorder = _watched(model)
	model.reset_from(source)
	assert_array(recorder.events).is_equal([["model_reset", []]])


func test_reset_from_replaces_old_content() -> void:
	var model: AquariumModel = _filled_model()
	model.reset_from(AquariumModel.new("2030-01-01T00:00:00Z"))
	assert_int(model.get_item_count()).is_equal(0)
	assert_int(model.get_fish_count()).is_equal(0)
	assert_str(model.get_aquarium_name()).is_equal("")
	assert_int(model.get_heightmap().size()).is_equal(0)
	assert_str(model.get_created()).is_equal("2030-01-01T00:00:00Z")


func test_connection_survives_reset() -> void:
	var model: AquariumModel = _model()
	var recorder: SignalRecorder = _watched(model)
	model.reset_from(_filled_model())
	recorder.clear()
	model.apply_set_name("After")
	assert_array(recorder.events).is_equal([["name_changed", ["After"]]])


func test_reset_does_not_touch_history() -> void:
	var model: AquariumModel = _model()
	var history: CommandHistory = CommandHistory.new()
	var ok: bool = history.execute(SetTankCommand.new(model, &"tank_a"))
	assert_bool(ok).is_true()
	var recorder: SignalRecorder = _watched(history)
	model.reset_from(_filled_model())
	assert_bool(history.can_undo()).is_true()
	assert_int(history.get_undo_count()).is_equal(1)
	assert_array(recorder.events).is_empty()


func test_reset_from_null_errors() -> void:
	var model: AquariumModel = _filled_model()
	var before: Dictionary = ModelState.snapshot(model)
	var recorder: SignalRecorder = _watched(model)
	# The plan fixes no message for this error, so any push_error counts.
	await assert_error(func() -> void: model.reset_from(null)).is_push_error(ErrorContains.new(""))
	assert_dict(ModelState.snapshot(model)).is_equal(before)
	assert_array(recorder.events).is_empty()
