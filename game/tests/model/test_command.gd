extends GdUnitTestSuite

const ErrorContains := preload("res://tests/helpers/error_contains.gd")
const UnimplementedCommand := preload("res://tests/helpers/commands/unimplemented_command.gd")


func test_unimplemented_do_reports_error_and_returns_false() -> void:
	var command: Command = UnimplementedCommand.new()
	var result: Array[bool] = []
	await (
		assert_error(func() -> void: result.append(command.do()))
		. is_push_error(ErrorContains.new("not implemented"))
	)
	assert_array(result).is_equal([false])


func test_unimplemented_undo_reports_error_and_returns_false() -> void:
	var command: Command = UnimplementedCommand.new()
	var result: Array[bool] = []
	await (
		assert_error(func() -> void: result.append(command.undo()))
		. is_push_error(ErrorContains.new("not implemented"))
	)
	assert_array(result).is_equal([false])


func test_base_class_do_names_the_method_in_the_error() -> void:
	var command: Command = Command.new()
	var result: Array[bool] = []
	await (
		assert_error(func() -> void: result.append(command.do()))
		. is_push_error(ErrorContains.new("do() not implemented"))
	)


func test_base_class_undo_names_the_method_in_the_error() -> void:
	var command: Command = Command.new()
	var result: Array[bool] = []
	await (
		assert_error(func() -> void: result.append(command.undo()))
		. is_push_error(ErrorContains.new("undo() not implemented"))
	)


func test_command_is_not_a_node() -> void:
	var command: Variant = Command.new()
	assert_bool(command is Node).is_false()
	assert_bool(command is RefCounted).is_true()


func test_execute_unimplemented_command_pushes_nothing() -> void:
	var history: CommandHistory = CommandHistory.new()
	var command: Command = UnimplementedCommand.new()
	var result: Array[bool] = []
	await (
		assert_error(func() -> void: result.append(history.execute(command)))
		. is_push_error(ErrorContains.new("not implemented"))
	)
	assert_array(result).is_equal([false])
	assert_int(history.get_undo_count()).is_equal(0)
	assert_int(history.get_redo_count()).is_equal(0)
	assert_bool(history.can_undo()).is_false()
