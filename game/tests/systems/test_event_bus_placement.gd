extends GdUnitTestSuite
## #31 AC 15, 19, 20 and hand-forward 2 (owner: developer): the three new EventBus relay signals
## (ADR 0012 rule 7): item_pick_clear_requested (no arguments), item_selected(uid: String) and
## item_selection_cleared (no arguments). They are plain relays: the bus never emits them itself.
## Test decision: the plan says to extend test_event_bus_autoload.gd with the signal list; the
## existing suites keep their assertions untouched, so the new checks live in this new file.

var _bus: Node = null


func before_test() -> void:
	_bus = get_tree().root.get_node_or_null("EventBus")


func _info(signal_name: String) -> Dictionary:
	for info: Dictionary in _bus.get_signal_list():
		if info["name"] == signal_name:
			return info
	return {}


func _args(signal_name: String) -> Array:
	var info: Dictionary = _info(signal_name)
	(
		assert_bool(not info.is_empty())
		. override_failure_message("EventBus.%s is missing" % signal_name)
		. is_true()
	)
	return info.get("args", [])


func test_item_pick_clear_requested_has_no_arguments() -> void:
	var args: Array = _args("item_pick_clear_requested")
	assert_int(args.size()).is_equal(0)
	assert_bool(_bus.has_signal("item_pick_clear_requested")).is_true()


func test_item_selected_carries_the_uid_as_a_string() -> void:
	var args: Array = _args("item_selected")
	assert_int(args.size()).is_equal(1)
	if args.size() == 1:
		assert_int((args[0] as Dictionary)["type"]).is_equal(TYPE_STRING)


func test_item_selection_cleared_has_no_arguments() -> void:
	var args: Array = _args("item_selection_cleared")
	assert_int(args.size()).is_equal(0)
	assert_bool(_bus.has_signal("item_selection_cleared")).is_true()


func test_the_new_signals_are_plain_relays_that_reach_a_listener_in_order() -> void:
	for signal_name: String in [
		"item_pick_clear_requested", "item_selected", "item_selection_cleared"
	]:
		if not _bus.has_signal(signal_name):
			assert_bool(false).override_failure_message("%s is missing" % signal_name).is_true()
			return
	var timeline: Array[String] = []
	_bus.connect("item_pick_clear_requested", func() -> void: timeline.append("request"))
	_bus.connect("item_selected", func(uid: String) -> void: timeline.append("selected:%s" % uid))
	_bus.connect("item_selection_cleared", func() -> void: timeline.append("cleared"))
	assert_array(timeline).is_empty()
	_bus.emit_signal("item_selected", "a0000001")
	_bus.emit_signal("item_selection_cleared")
	_bus.emit_signal("item_pick_clear_requested")
	assert_array(timeline).is_equal(["selected:a0000001", "cleared", "request"])
