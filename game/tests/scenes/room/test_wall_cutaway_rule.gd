extends GdUnitTestSuite
## #25 criterion 19 (rule part, owner: developer): the hysteresis of WallCutaway.next_hidden. The
## signed distance is positive in front of the wall plane (room side) and negative behind it; the
## band is 0.05 m, so the wall hides when the camera is more than 0.025 m behind the plane and
## shows again when it is more than 0.025 m in front. In between the old state stays.

const OrbitApi := preload("res://tests/helpers/orbit_api.gd")

const BAND := 0.05


func _exists() -> bool:
	(
		assert_bool(OrbitApi.wall_exists())
		. override_failure_message("%s is missing" % OrbitApi.WALL_PATH)
		. is_true()
	)
	return OrbitApi.wall_exists()


func test_ac19_behind_the_threshold_a_shown_wall_hides() -> void:
	if not _exists():
		return
	assert_that(OrbitApi.next_hidden(false, -0.026, BAND)).is_equal(true)
	assert_that(OrbitApi.next_hidden(false, -1.0, BAND)).is_equal(true)


func test_ac19_in_front_of_the_threshold_a_hidden_wall_shows() -> void:
	if not _exists():
		return
	assert_that(OrbitApi.next_hidden(true, 0.026, BAND)).is_equal(false)
	assert_that(OrbitApi.next_hidden(true, 1.0, BAND)).is_equal(false)


func test_ac19_far_from_the_plane_the_old_state_does_not_matter() -> void:
	if not _exists():
		return
	assert_that(OrbitApi.next_hidden(true, -1.0, BAND)).is_equal(true)
	assert_that(OrbitApi.next_hidden(false, 1.0, BAND)).is_equal(false)


func test_ac19_inside_the_band_the_old_state_stays() -> void:
	if not _exists():
		return
	for distance: float in [-0.024, -0.01, 0.0, 0.01, 0.024]:
		assert_that(OrbitApi.next_hidden(true, distance, BAND)).is_equal(true)
		assert_that(OrbitApi.next_hidden(false, distance, BAND)).is_equal(false)


func test_ac19_a_jitter_of_0_02_m_around_the_plane_never_changes_the_state() -> void:
	if not _exists():
		return
	for start: bool in [false, true]:
		var hidden: bool = start
		var changes: int = 0
		for index: int in 40:
			var distance: float = 0.02 if index % 2 == 0 else -0.02
			var next: Variant = OrbitApi.next_hidden(hidden, distance, BAND)
			if next != hidden:
				changes += 1
			hidden = next
		assert_int(changes).is_equal(0)


func test_ac19_crossing_the_band_decisively_changes_the_state_once_each_way() -> void:
	if not _exists():
		return
	var hidden: bool = false
	var changes: int = 0
	var path: Array[float] = []
	for index: int in 41:
		path.append(0.2 - 0.01 * index)
	for index: int in 41:
		path.append(-0.2 + 0.01 * index)
	for distance: float in path:
		var next: Variant = OrbitApi.next_hidden(hidden, distance, BAND)
		if next != hidden:
			changes += 1
		hidden = next
	assert_int(changes).is_equal(2)
	assert_bool(hidden).is_false()


func test_ac19_the_band_width_comes_from_the_argument() -> void:
	if not _exists():
		return
	assert_that(OrbitApi.next_hidden(false, -0.04, 0.2)).is_equal(false)
	assert_that(OrbitApi.next_hidden(false, -0.11, 0.2)).is_equal(true)
	assert_that(OrbitApi.next_hidden(true, 0.04, 0.2)).is_equal(true)
	assert_that(OrbitApi.next_hidden(true, 0.11, 0.2)).is_equal(false)
