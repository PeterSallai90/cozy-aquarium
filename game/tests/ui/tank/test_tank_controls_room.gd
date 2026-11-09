extends GdUnitTestSuite
## #24 criteria 21 and 22 (owner: developer): the chooser together with the room, like Main wires
## them. The In use marker follows the tank the room displays, not the model id: Undo, Redo and a
## load (model_reset) while the chooser is open move it, and a catalog tank whose scene fails to
## load leaves the marker on the medium fallback. Node names: tests/helpers/tank_ui_rig.gd.

const Api := preload("res://tests/helpers/late_api.gd")
const Rig := preload("res://tests/helpers/room_rig.gd")
const Ui := preload("res://tests/helpers/tank_ui_rig.gd")
const Table := preload("res://tests/helpers/tank_table.gd")
const Recorder := preload("res://tests/helpers/signal_recorder.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")
const ModelState := preload("res://tests/helpers/model_state.gd")

var _saved_locale: String = ""
var _model: AquariumModel = null
var _catalog: RefCounted = null
var _history: CommandHistory = null
var _controls: Control = null
var _room: Node3D = null


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	_history = CommandHistory.new()
	_catalog = Rig.default_catalog()
	_model = Rig.model_with(Table.MEDIUM)


func after_test() -> void:
	TranslationServer.set_locale(_saved_locale)


func _build_open() -> bool:
	var rig: Dictionary = await Ui.open(self, _model, _catalog, _history)
	_room = rig["room"]
	_controls = rig["controls"]
	auto_free(_room)
	(
		assert_bool(_controls != null)
		. override_failure_message("%s is missing" % Ui.CONTROLS_SCENE)
		. is_true()
	)
	if _controls == null:
		return false
	auto_free(_controls)
	await Ui.open_chooser(self, _controls)
	return Ui.is_open(_controls)


func _wait() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


# --- AC 21: the model changes while the chooser is open ---


func test_ac21_a_change_made_elsewhere_moves_the_marker_and_keeps_the_chooser_open() -> void:
	if not await _build_open():
		return
	assert_bool(_history.execute(Api.change_tank(_model, _catalog, Table.LARGE))).is_true()
	await _wait()
	assert_bool(Ui.is_open(_controls)).is_true()
	assert_array(Ui.marked_ids(_controls)).is_equal([Table.LARGE])


func test_ac21_undo_while_open_moves_the_marker_back_and_keeps_the_chooser_open() -> void:
	if not await _build_open():
		return
	_history.execute(Api.change_tank(_model, _catalog, Table.SMALL))
	await _wait()
	assert_array(Ui.marked_ids(_controls)).is_equal([Table.SMALL])
	assert_bool(_history.undo()).is_true()
	await _wait()
	assert_bool(Ui.is_open(_controls)).is_true()
	assert_array(Ui.marked_ids(_controls)).is_equal([Table.MEDIUM])


func test_ac21_redo_while_open_moves_the_marker_forward_again() -> void:
	if not await _build_open():
		return
	_history.execute(Api.change_tank(_model, _catalog, Table.SMALL))
	_history.undo()
	await _wait()
	assert_bool(_history.redo()).is_true()
	await _wait()
	assert_bool(Ui.is_open(_controls)).is_true()
	assert_array(Ui.marked_ids(_controls)).is_equal([Table.SMALL])


func test_ac21_model_reset_while_open_refreshes_the_marker() -> void:
	if not await _build_open():
		return
	var other: AquariumModel = Rig.model_with(Table.LARGE)
	_model.reset_from(other)
	await _wait()
	assert_bool(Ui.is_open(_controls)).is_true()
	assert_array(Ui.marked_ids(_controls)).is_equal([Table.LARGE])
	assert_that(Rig.displayed_id(_room)).is_equal(Table.LARGE)


func test_ac21_model_reset_to_an_unknown_id_marks_the_displayed_fallback() -> void:
	if not await _build_open():
		return
	var other: AquariumModel = Rig.model_with(&"tank_from_the_future")
	await EngineOutput.capture(
		func() -> void:
			_model.reset_from(other)
			await _wait()
	)
	assert_array(Ui.marked_ids(_controls)).is_equal([Table.MEDIUM])
	assert_that(_model.get_tank_id()).is_equal(&"tank_from_the_future")


func test_ac21_the_marker_follows_the_displayed_tank_after_the_room_has_swapped() -> void:
	if not await _build_open():
		return
	_history.execute(Api.change_tank(_model, _catalog, Table.LARGE))
	await _wait()
	assert_that(Rig.displayed_id(_room)).is_equal(Table.LARGE)
	assert_array(Ui.marked_ids(_controls)).is_equal([Rig.displayed_id(_room)])


func test_ac21_the_chooser_does_not_change_the_model_while_following() -> void:
	if not await _build_open():
		return
	var recorder: Recorder = Recorder.new()
	recorder.watch(_model)
	_model.reset_from(Rig.model_with(Table.SMALL))
	await _wait()
	assert_array(recorder.names()).contains_exactly(["model_reset"])
	assert_int(_history.get_undo_count()).is_equal(0)


func test_ac21_a_closed_chooser_also_shows_the_current_marker_when_opened_later() -> void:
	var rig: Dictionary = await Ui.open(self, _model, _catalog, _history)
	_room = rig["room"]
	_controls = rig["controls"]
	auto_free(_room)
	if _controls == null:
		assert_bool(false).override_failure_message("%s is missing" % Ui.CONTROLS_SCENE).is_true()
		return
	auto_free(_controls)
	_history.execute(Api.change_tank(_model, _catalog, Table.LARGE))
	await _wait()
	await Ui.open_chooser(self, _controls)
	assert_array(Ui.marked_ids(_controls)).is_equal([Table.LARGE])


# --- AC 22: a catalog tank whose scene fails to load ---


func _broken_catalog() -> RefCounted:
	var broken: Resource = Rig.variant(&"tank_broken", null)
	return Api.catalog_from([Rig.default_definition(), broken])


func _error_for(id: String) -> String:
	return (
		'RoomCorner: tank "%s" has no loadable scene; showing the default tank "%s"'
		% [id, Table.MEDIUM]
	)


func test_ac22_picking_the_broken_tank_writes_its_id_with_one_history_entry() -> void:
	_catalog = _broken_catalog()
	if not await _build_open():
		return
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void:
			Ui.card(_controls, &"tank_broken").pressed.emit()
			await _wait()
	)
	assert_that(_model.get_tank_id()).is_equal(&"tank_broken")
	assert_int(_history.get_undo_count()).is_equal(1)
	assert_dict(seen["errors"]).is_equal({_error_for("tank_broken"): 1})
	assert_dict(seen["warnings"]).is_empty()


func test_ac22_the_room_shows_the_medium_fallback_and_the_marker_is_on_medium() -> void:
	_catalog = _broken_catalog()
	if not await _build_open():
		return
	await EngineOutput.capture(
		func() -> void:
			Ui.card(_controls, &"tank_broken").pressed.emit()
			await _wait()
	)
	assert_that(Rig.displayed_id(_room)).is_equal(Table.MEDIUM)
	await Ui.open_chooser(self, _controls)
	assert_array(Ui.marked_ids(_controls)).is_equal([Table.MEDIUM])


func test_ac22_undo_restores_the_previous_tank_normally() -> void:
	_catalog = _broken_catalog()
	_model = Ui.furnished_model(Table.MEDIUM)
	var before: Dictionary = ModelState.snapshot(_model)
	if not await _build_open():
		return
	# The furnished tank asks first; the dialog is answered through the Command directly here, as
	# the dialog itself is the subject of test_tank_change_dialog.gd.
	await EngineOutput.capture(
		func() -> void:
			_history.execute(Api.change_tank(_model, _catalog, &"tank_broken"))
			await _wait()
	)
	assert_that(_model.get_tank_id()).is_equal(&"tank_broken")
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void:
			_history.undo()
			await _wait()
	)
	assert_dict(seen["errors"]).is_empty()
	assert_dict(ModelState.snapshot(_model)).is_equal(before)
	assert_that(Rig.displayed_id(_room)).is_equal(Table.MEDIUM)
	assert_array(Ui.marked_ids(_controls)).is_equal([Table.MEDIUM])


func test_ac22_the_broken_tank_is_a_card_like_any_other_catalog_tank() -> void:
	_catalog = _broken_catalog()
	if not await _build_open():
		return
	assert_object(Ui.card(_controls, &"tank_broken")).is_not_null()
