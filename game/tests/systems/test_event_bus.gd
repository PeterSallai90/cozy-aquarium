extends GdUnitTestSuite

const SignalRecorder := preload("res://tests/helpers/signal_recorder.gd")
const EventBusScript := preload("res://systems/event_bus.gd")
const ListenerNode := preload("res://tests/helpers/listener_node.gd")
const SetTankCommand := preload("res://tests/helpers/commands/set_tank_command.gd")

var _model: AquariumModel
var _history: CommandHistory
var _bus: Node
var _listener_calls: Array[String] = []


func before_test() -> void:
	_model = AquariumModel.new("2026-10-27T18:00:00Z")
	_history = CommandHistory.new()
	_bus = auto_free(EventBusScript.new())
	_listener_calls.clear()


func _tank(tank_id: StringName) -> Command:
	return SetTankCommand.new(_model, tank_id)


func test_bus_extends_node() -> void:
	assert_bool(_bus is Node).is_true()


func test_nothing_reemitted_before_bind() -> void:
	var recorder: SignalRecorder = SignalRecorder.new()
	recorder.watch(_bus)
	assert_bool(_history.execute(_tank(&"tank_b"))).is_true()
	assert_bool(_history.undo()).is_true()
	assert_array(recorder.events).is_empty()


func test_reemits_executed_undone_redone_and_history_changed() -> void:
	_bus.bind_history(_history)
	var recorder: SignalRecorder = SignalRecorder.new()
	recorder.watch(_bus)
	var command: Command = _tank(&"tank_b")
	assert_bool(_history.execute(command)).is_true()
	assert_array(recorder.names()).is_equal(["command_executed", "history_changed"])
	assert_bool(is_same(recorder.args_of(0)[0], command)).is_true()
	assert_array(recorder.args_of(1)).is_equal([true, false])
	recorder.clear()
	assert_bool(_history.undo()).is_true()
	assert_array(recorder.names()).is_equal(["command_undone", "history_changed"])
	assert_bool(is_same(recorder.args_of(0)[0], command)).is_true()
	assert_array(recorder.args_of(1)).is_equal([false, true])
	recorder.clear()
	assert_bool(_history.redo()).is_true()
	assert_array(recorder.names()).is_equal(["command_redone", "history_changed"])
	assert_bool(is_same(recorder.args_of(0)[0], command)).is_true()
	assert_array(recorder.args_of(1)).is_equal([true, false])


func test_clear_is_reemitted_as_history_changed() -> void:
	_bus.bind_history(_history)
	assert_bool(_history.execute(_tank(&"tank_b"))).is_true()
	var recorder: SignalRecorder = SignalRecorder.new()
	recorder.watch(_bus)
	assert_bool(_history.clear()).is_true()
	assert_array(recorder.events).is_equal([["history_changed", [false, false]]])


func test_reemission_is_synchronous() -> void:
	_bus.bind_history(_history)
	var recorder: SignalRecorder = SignalRecorder.new()
	recorder.watch(_bus)
	var ok: bool = _history.execute(_tank(&"tank_b"))
	# No await: the events must already be there when execute() returns.
	assert_bool(ok).is_true()
	assert_int(recorder.count()).is_equal(2)


func test_bus_listener_sees_new_model_and_stacks() -> void:
	_bus.bind_history(_history)
	_bus.command_executed.connect(_on_executed_record)
	assert_bool(_history.execute(_tank(&"tank_b"))).is_true()
	assert_array(_listener_calls).is_equal(["tank_b:1"])


func test_freed_listener_does_not_crash() -> void:
	_bus.bind_history(_history)
	var doomed: Node = ListenerNode.new()
	var survivor: SignalRecorder = SignalRecorder.new()
	survivor.watch(_bus)
	_bus.history_changed.connect(Callable(doomed, &"on_history_changed"))
	_bus.command_executed.connect(Callable(doomed, &"on_command"))
	doomed.free()
	assert_bool(_history.execute(_tank(&"tank_b"))).is_true()
	assert_bool(_history.undo()).is_true()
	assert_array(survivor.names()).is_equal(
		["command_executed", "history_changed", "command_undone", "history_changed"]
	)


func test_rebind_disconnects_previous_history() -> void:
	var other: CommandHistory = CommandHistory.new()
	var recorder: SignalRecorder = SignalRecorder.new()
	recorder.watch(_bus)
	_bus.bind_history(_history)
	_bus.bind_history(other)
	assert_bool(_history.execute(_tank(&"tank_b"))).is_true()
	assert_array(recorder.events).is_empty()
	assert_bool(other.execute(_tank(&"tank_c"))).is_true()
	assert_array(recorder.names()).is_equal(["command_executed", "history_changed"])


func test_bind_same_history_twice_emits_once() -> void:
	var recorder: SignalRecorder = SignalRecorder.new()
	recorder.watch(_bus)
	_bus.bind_history(_history)
	_bus.bind_history(_history)
	assert_bool(_history.execute(_tank(&"tank_b"))).is_true()
	assert_array(recorder.names()).is_equal(["command_executed", "history_changed"])


func test_unbind_stops_reemission() -> void:
	var recorder: SignalRecorder = SignalRecorder.new()
	recorder.watch(_bus)
	_bus.bind_history(_history)
	_bus.unbind_history()
	assert_bool(_history.execute(_tank(&"tank_b"))).is_true()
	assert_array(recorder.events).is_empty()


func test_unbind_without_bind_is_harmless() -> void:
	_bus.unbind_history()
	_bus.bind_history(null)
	assert_bool(_history.execute(_tank(&"tank_b"))).is_true()


func test_bind_null_unbinds() -> void:
	var recorder: SignalRecorder = SignalRecorder.new()
	recorder.watch(_bus)
	_bus.bind_history(_history)
	_bus.bind_history(null)
	assert_bool(_history.execute(_tank(&"tank_b"))).is_true()
	assert_array(recorder.events).is_empty()


func test_model_signals_are_not_relayed() -> void:
	_bus.bind_history(_history)
	var recorder: SignalRecorder = SignalRecorder.new()
	recorder.watch(_bus)
	_model.apply_set_name("Direct")
	assert_array(recorder.events).is_empty()


func _on_executed_record(_command: Command) -> void:
	_listener_calls.append("%s:%d" % [_model.get_tank_id(), _history.get_undo_count()])
