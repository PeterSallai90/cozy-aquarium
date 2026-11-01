extends GdUnitTestSuite

const Factory := preload("res://tests/helpers/factory.gd")
const AddItemCommand := preload("res://tests/helpers/commands/add_item_command.gd")
const SetTankCommand := preload("res://tests/helpers/commands/set_tank_command.gd")
const FailingCommand := preload("res://tests/helpers/commands/failing_command.gd")

var _model: AquariumModel
var _history: CommandHistory
var _seen: Array = []


func before_test() -> void:
	_model = AquariumModel.new("2026-10-27T18:00:00Z")
	_history = CommandHistory.new()
	_seen = []


func _record_busy(_a: Variant = null, _b: Variant = null) -> void:
	_seen.append(_history.is_busy())


func test_is_busy_false_when_idle() -> void:
	assert_bool(_history.is_busy()).is_false()


func test_is_busy_true_only_inside_execute_undo_redo_clear() -> void:
	_history.executed.connect(_record_busy)
	_history.undone.connect(_record_busy)
	_history.redone.connect(_record_busy)
	_history.history_changed.connect(_record_busy)
	assert_bool(_history.execute(SetTankCommand.new(_model, &"tank_b"))).is_true()
	assert_bool(_history.is_busy()).is_false()
	assert_array(_seen).is_equal([true, true])
	_seen.clear()
	assert_bool(_history.undo()).is_true()
	assert_bool(_history.is_busy()).is_false()
	assert_array(_seen).is_equal([true, true])
	_seen.clear()
	assert_bool(_history.redo()).is_true()
	assert_bool(_history.is_busy()).is_false()
	assert_array(_seen).is_equal([true, true])
	_seen.clear()
	assert_bool(_history.clear()).is_true()
	assert_bool(_history.is_busy()).is_false()
	assert_array(_seen).is_equal([true])


func test_is_busy_true_inside_a_model_signal_handler_during_a_command() -> void:
	_model.item_added.connect(_record_busy)
	var item: PlacedItem = Factory.item("c0000001")
	assert_bool(_history.execute(AddItemCommand.new(_model, item))).is_true()
	assert_array(_seen).is_equal([true])
	_seen.clear()
	assert_bool(_history.undo()).is_true()
	_model.item_removed.connect(_record_busy)
	assert_bool(_history.redo()).is_true()
	assert_bool(_history.undo()).is_true()
	assert_array(_seen).is_equal([true, true])


func test_model_changes_outside_the_history_are_not_busy() -> void:
	_model.item_added.connect(_record_busy)
	_model.apply_insert_item(Factory.item("c0000001"), 0)
	assert_array(_seen).is_equal([false])


func test_is_busy_false_again_after_a_failed_command() -> void:
	var failing: Command = FailingCommand.new(_model)
	assert_bool(_history.execute(failing)).is_false()
	assert_bool(_history.is_busy()).is_false()
	assert_bool(_history.execute(SetTankCommand.new(_model, &"tank_b"))).is_true()
