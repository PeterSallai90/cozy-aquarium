extends GdUnitTestSuite

const Factory := preload("res://tests/helpers/factory.gd")
const ModelState := preload("res://tests/helpers/model_state.gd")
const SignalRecorder := preload("res://tests/helpers/signal_recorder.gd")

const FIXED_CLOCK := "2026-10-27T18:00:00Z"


func _filled_model() -> AquariumModel:
	var model: AquariumModel = AquariumModel.new(FIXED_CLOCK)
	model.apply_set_name("Reef")
	model.apply_insert_item(Factory.item("a0000001"), 0)
	model.apply_insert_fish(Factory.fish("f0000001"), 0)
	return model


func test_set_save_times_sets_both_without_signal() -> void:
	var model: AquariumModel = _filled_model()
	var recorder: SignalRecorder = SignalRecorder.new()
	recorder.watch(model)
	model.set_save_times("2026-01-02T03:04:05Z", "2026-05-06T07:08:09Z")
	assert_str(model.get_created()).is_equal("2026-01-02T03:04:05Z")
	assert_str(model.get_modified()).is_equal("2026-05-06T07:08:09Z")
	assert_array(recorder.events).is_empty()


func test_set_save_times_changes_nothing_else() -> void:
	var model: AquariumModel = _filled_model()
	var before: Dictionary = ModelState.snapshot(model)
	model.set_save_times("2026-01-02T03:04:05Z", "2026-05-06T07:08:09Z")
	var after: Dictionary = ModelState.snapshot(model)
	assert_str(after["created"]).is_equal("2026-01-02T03:04:05Z")
	assert_str(after["modified"]).is_equal("2026-05-06T07:08:09Z")
	before["created"] = after["created"]
	before["modified"] = after["modified"]
	assert_dict(after).is_equal(before)


func test_set_save_times_does_not_validate() -> void:
	var model: AquariumModel = _filled_model()
	model.set_save_times("not a stamp", "")
	assert_str(model.get_created()).is_equal("not a stamp")
	assert_str(model.get_modified()).is_equal("")


func test_set_save_times_can_change_created_and_modified_independently() -> void:
	var model: AquariumModel = _filled_model()
	model.set_save_times(model.get_created(), "2030-01-01T00:00:00Z")
	assert_str(model.get_created()).is_equal(FIXED_CLOCK)
	assert_str(model.get_modified()).is_equal("2030-01-01T00:00:00Z")
