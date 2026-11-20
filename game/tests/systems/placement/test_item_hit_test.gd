extends GdUnitTestSuite
## #31 AC 19 and 39 (owner: developer): ItemHitTest.nearest(origin, direction, entries), static and
## pure. Each entry is a Dictionary {"transform": Transform3D, "aabb": AABB} (the item frame in
## tank-local space and its local visual bounds; test decision, the plan names "the item transform
## plus its local AABB"). A slab test runs in the item frame; the smallest distance of at least 0
## wins, a tie goes to the lower index, no hit gives -1. A box behind the origin is no hit.

const Api := preload("res://tests/helpers/placement_api.gd")

## A branch-like box: 28 cm long in x, 7 cm high, 8 cm deep.
const BRANCH_BOX := AABB(Vector3(-0.14, 0.0, -0.04), Vector3(0.28, 0.07, 0.08))
const FORWARD := Vector3(0.0, 0.0, -1.0)


func _have() -> bool:
	(
		assert_bool(Api.exists(Api.HIT))
		. override_failure_message("res://systems/placement/item_hit_test.gd is missing")
		. is_true()
	)
	return Api.exists(Api.HIT)


func _entry(origin: Vector3, yaw_deg: float = 0.0) -> Dictionary:
	var basis: Basis = Basis(Vector3.UP, deg_to_rad(yaw_deg))
	return {"transform": Transform3D(basis, origin), "aabb": BRANCH_BOX}


func test_ac19_a_ray_through_one_box_hits_it() -> void:
	if not _have():
		return
	var entries: Array = [_entry(Vector3.ZERO)]
	assert_int(Api.nearest(Vector3(0.05, 0.03, 1.0), FORWARD, entries)).is_equal(0)


func test_ac19_the_nearest_box_wins_whatever_the_list_order() -> void:
	if not _have():
		return
	var near: Dictionary = _entry(Vector3(0.0, 0.0, 0.3))
	var far: Dictionary = _entry(Vector3(0.0, 0.0, -0.3))
	var origin: Vector3 = Vector3(0.0, 0.03, 1.0)
	assert_int(Api.nearest(origin, FORWARD, [near, far])).is_equal(0)
	assert_int(Api.nearest(origin, FORWARD, [far, near])).is_equal(1)


func test_ac19_a_tie_goes_to_the_lower_index() -> void:
	if not _have():
		return
	var entries: Array = [
		_entry(Vector3.ZERO), _entry(Vector3.ZERO), _entry(Vector3(0.0, 0.0, -0.5))
	]
	assert_int(Api.nearest(Vector3(0.0, 0.03, 1.0), FORWARD, entries)).is_equal(0)


func test_ac19_a_ray_beside_every_box_hits_nothing() -> void:
	if not _have():
		return
	var entries: Array = [_entry(Vector3.ZERO)]
	assert_int(Api.nearest(Vector3(0.5, 0.03, 1.0), FORWARD, entries)).is_equal(-1)
	assert_int(Api.nearest(Vector3(0.0, 0.5, 1.0), FORWARD, entries)).is_equal(-1)


func test_ac19_no_entries_gives_minus_one() -> void:
	if not _have():
		return
	assert_int(Api.nearest(Vector3(0.0, 0.03, 1.0), FORWARD, [])).is_equal(-1)


func test_ac19_a_box_behind_the_origin_is_not_hit() -> void:
	if not _have():
		return
	var entries: Array = [_entry(Vector3(0.0, 0.0, 2.0))]
	assert_int(Api.nearest(Vector3(0.0, 0.03, 1.0), FORWARD, entries)).is_equal(-1)


func test_ac19_a_rotated_box_is_hit_in_its_own_frame() -> void:
	if not _have():
		return
	var flat: Array = [_entry(Vector3.ZERO, 0.0)]
	var turned: Array = [_entry(Vector3.ZERO, 90.0)]
	var beside: Vector3 = Vector3(0.1, 0.03, 1.0)
	# Unrotated, x = 0.1 is inside the 28 cm length; turned by 90 degrees the length runs along z.
	assert_int(Api.nearest(beside, FORWARD, flat)).is_equal(0)
	assert_int(Api.nearest(beside, FORWARD, turned)).is_equal(-1)
	# Turned, a ray along x through the long axis hits.
	assert_int(Api.nearest(Vector3(1.0, 0.03, 0.1), Vector3(-1.0, 0.0, 0.0), turned)).is_equal(0)
	assert_int(Api.nearest(Vector3(1.0, 0.03, 0.1), Vector3(-1.0, 0.0, 0.0), flat)).is_equal(-1)


func test_ac19_a_box_is_hit_at_its_position_not_at_the_origin() -> void:
	if not _have():
		return
	var entries: Array = [_entry(Vector3(0.3, 0.0, 0.1))]
	assert_int(Api.nearest(Vector3(0.3, 0.03, 1.0), FORWARD, entries)).is_equal(0)
	assert_int(Api.nearest(Vector3(0.0, 0.03, 1.0), FORWARD, entries)).is_equal(-1)
