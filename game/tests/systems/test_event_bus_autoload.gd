extends GdUnitTestSuite


func test_autoload_setting() -> void:
	var setting: String = ProjectSettings.get_setting("autoload/EventBus", "")
	assert_str(setting).is_equal("*res://systems/event_bus.gd")


func test_event_bus_node_live() -> void:
	var node: Node = get_tree().root.get_node_or_null("EventBus")
	assert_object(node).is_not_null()
	assert_bool(node is Node).is_true()
	var script: Script = node.get_script() as Script
	assert_object(script).is_not_null()
	assert_str(script.resource_path).is_equal("res://systems/event_bus.gd")


func test_event_bus_script_is_not_in_model_layer() -> void:
	assert_bool(FileAccess.file_exists("res://systems/event_bus.gd")).is_true()
	assert_bool(FileAccess.file_exists("res://model/event_bus.gd")).is_false()


func test_live_event_bus_has_the_history_api() -> void:
	var node: Node = get_tree().root.get_node_or_null("EventBus")
	assert_object(node).is_not_null()
	assert_bool(node.has_method("bind_history")).is_true()
	assert_bool(node.has_method("unbind_history")).is_true()
	for signal_name: String in [
		"command_executed", "command_undone", "command_redone", "history_changed"
	]:
		assert_bool(node.has_signal(signal_name)).override_failure_message(signal_name).is_true()
