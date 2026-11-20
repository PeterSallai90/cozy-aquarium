extends GdUnitTestSuite
## #32 AC 20 support (owner: developer), ADR 0008 Amendment 2 rule 16:
## WorldInput.is_gesture_running(tree) asks the members of the group world_gesture_sources
## (WorldInput.GESTURE_GROUP). It is true when any member that implements has_running_gesture()
## reports true; members without the method are ignored; no member means false; a freed member
## leaves the group by itself. The query is stateless: asking twice gives the same answer.

const Api := preload("res://tests/helpers/edit_api.gd")


## A world system stand-in.
class Source:
	extends Node

	var running: bool = false

	func has_running_gesture() -> bool:
		return running


func _have() -> bool:
	var found: bool = Api.is_gesture_running(get_tree()) != null
	(
		assert_bool(found)
		. override_failure_message("WorldInput.is_gesture_running(tree) is missing")
		. is_true()
	)
	return found


func _source(running: bool) -> Source:
	var source: Source = Source.new()
	source.running = running
	source.add_to_group(Api.GESTURE_GROUP)
	add_child(source)
	auto_free(source)
	return source


func test_the_group_constant_is_world_gesture_sources() -> void:
	var script: GDScript = load(Api.WORLD_INPUT) as GDScript
	var constants: Dictionary = script.get_script_constant_map()
	assert_bool(constants.has("GESTURE_GROUP")).is_true()
	assert_that(constants.get("GESTURE_GROUP")).is_equal(Api.GESTURE_GROUP)


func test_without_a_member_no_gesture_runs() -> void:
	if not _have():
		return
	assert_bool(get_tree().get_nodes_in_group(Api.GESTURE_GROUP).is_empty()).is_true()
	assert_bool(Api.is_gesture_running(get_tree()) == true).is_false()


func test_a_member_that_reports_true_makes_the_query_true() -> void:
	if not _have():
		return
	var source: Source = _source(true)
	assert_bool(Api.is_gesture_running(get_tree()) == true).is_true()
	assert_bool(Api.is_gesture_running(get_tree()) == true).is_true()
	source.running = false
	assert_bool(Api.is_gesture_running(get_tree()) == true).is_false()


func test_a_member_that_reports_false_leaves_the_query_false() -> void:
	if not _have():
		return
	_source(false)
	assert_bool(Api.is_gesture_running(get_tree()) == true).is_false()


func test_any_member_that_reports_true_wins_over_the_others() -> void:
	if not _have():
		return
	_source(false)
	_source(true)
	_source(false)
	assert_bool(Api.is_gesture_running(get_tree()) == true).is_true()


func test_a_member_without_the_method_is_ignored() -> void:
	if not _have():
		return
	var plain: Node = Node.new()
	plain.add_to_group(Api.GESTURE_GROUP)
	add_child(plain)
	auto_free(plain)
	assert_bool(Api.is_gesture_running(get_tree()) == true).is_false()
	_source(true)
	assert_bool(Api.is_gesture_running(get_tree()) == true).is_true()


func test_a_freed_member_no_longer_counts() -> void:
	if not _have():
		return
	var source: Source = _source(true)
	assert_bool(Api.is_gesture_running(get_tree()) == true).is_true()
	source.free()
	assert_bool(Api.is_gesture_running(get_tree()) == true).is_false()


func test_a_member_that_left_the_tree_no_longer_counts() -> void:
	if not _have():
		return
	var source: Source = _source(true)
	remove_child(source)
	assert_bool(Api.is_gesture_running(get_tree()) == true).is_false()
	source.free()
