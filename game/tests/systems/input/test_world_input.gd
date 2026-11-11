extends GdUnitTestSuite
## #25 criterion 11 (helper part, ADR 0008 rule 4; owner: developer): WorldInput.is_blocked is true
## while any CanvasItem of the group world_input_blockers is visible in the tree. It is pure and
## stateless, so a blocker freed while open leaves nothing behind.

const OrbitApi := preload("res://tests/helpers/orbit_api.gd")

var _holder: Control = null


func before_test() -> void:
	_holder = Control.new()
	add_child(_holder)
	auto_free(_holder)


func _exists() -> bool:
	(
		assert_bool(OrbitApi.world_input_exists())
		. override_failure_message("%s is missing" % OrbitApi.WORLD_INPUT_PATH)
		. is_true()
	)
	return OrbitApi.world_input_exists()


func _blocker() -> Control:
	var blocker: Control = Control.new()
	blocker.add_to_group(OrbitApi.blocker_group())
	_holder.add_child(blocker)
	return blocker


func test_ac11_the_group_is_called_world_input_blockers() -> void:
	if not _exists():
		return
	assert_that(OrbitApi.blocker_group()).is_equal(&"world_input_blockers")


func test_ac11_nothing_is_blocked_without_a_blocker() -> void:
	if not _exists():
		return
	assert_that(OrbitApi.is_blocked(get_tree())).is_equal(false)


func test_ac11_a_visible_blocker_blocks() -> void:
	if not _exists():
		return
	_blocker()
	assert_that(OrbitApi.is_blocked(get_tree())).is_equal(true)


func test_ac11_a_hidden_blocker_does_not_block() -> void:
	if not _exists():
		return
	var blocker: Control = _blocker()
	blocker.hide()
	assert_that(OrbitApi.is_blocked(get_tree())).is_equal(false)
	blocker.show()
	assert_that(OrbitApi.is_blocked(get_tree())).is_equal(true)


func test_ac11_a_blocker_under_a_hidden_parent_does_not_block() -> void:
	if not _exists():
		return
	_blocker()
	_holder.hide()
	assert_that(OrbitApi.is_blocked(get_tree())).is_equal(false)


func test_ac11_one_visible_blocker_among_hidden_ones_blocks() -> void:
	if not _exists():
		return
	_blocker().hide()
	_blocker().hide()
	_blocker()
	assert_that(OrbitApi.is_blocked(get_tree())).is_equal(true)


func test_ac11_a_freed_blocker_leaves_no_block_behind() -> void:
	if not _exists():
		return
	var blocker: Control = _blocker()
	assert_that(OrbitApi.is_blocked(get_tree())).is_equal(true)
	_holder.remove_child(blocker)
	blocker.free()
	assert_that(OrbitApi.is_blocked(get_tree())).is_equal(false)


func test_ac11_a_control_outside_the_group_never_blocks() -> void:
	if not _exists():
		return
	var other: Control = Control.new()
	_holder.add_child(other)
	assert_that(OrbitApi.is_blocked(get_tree())).is_equal(false)
