extends GdUnitTestSuite
## #34 AC 18 and 26 (owner: developer): FishHash.unit(uid, salt) is FNV-1a 32 bit over the UTF-8
## bytes of salt + ":" + uid, divided by 2^32 (ADR 0013 rule 6). The expected values come from an
## independent FNV-1a in the tests (FishApi.expected_unit), which is first checked against the
## published FNV-1a test vectors, so a wrong offset, prime or byte order fails here.

const Api := preload("res://tests/helpers/fish_api.gd")

const SALTS: PackedStringArray = [
	"fish.rest.x",
	"fish.rest.z",
	"fish.rest.y",
	"fish.rest.yaw",
	"fish.swim.phase",
	"fish.name.default"
]
const UIDS: PackedStringArray = ["f1000001", "0badf00d", "00000000", "ffffffff", "a1b2c3d4"]


func _have_hash() -> bool:
	var is_ready: bool = Api.script_of(Api.HASH_PATH) != null
	assert_bool(is_ready).override_failure_message("FishHash is missing").is_true()
	return is_ready


func test_the_reference_fnv1a_matches_the_published_vectors() -> void:
	assert_int(Api.fnv1a32("")).is_equal(0x811C9DC5)
	assert_int(Api.fnv1a32("a")).is_equal(0xE40C292C)
	assert_int(Api.fnv1a32("foobar")).is_equal(0xBF9CF968)


func test_unit_is_the_fnv1a_of_salt_colon_uid_over_2_pow_32() -> void:
	if not _have_hash():
		return
	for uid: String in UIDS:
		for salt: String in SALTS:
			(
				assert_float(Api.hash_unit(uid, salt))
				. override_failure_message("FishHash.unit(%s, %s)" % [uid, salt])
				. is_equal_approx(Api.expected_unit(uid, salt), 1e-12)
			)


func test_unit_lies_in_zero_to_one_and_is_repeatable() -> void:
	if not _have_hash():
		return
	for uid: String in UIDS:
		for salt: String in SALTS:
			var first: float = Api.hash_unit(uid, salt)
			assert_bool(first >= 0.0 and first < 1.0).is_true()
			assert_float(Api.hash_unit(uid, salt)).is_equal(first)


func test_each_salt_gives_a_different_value_for_the_same_uid() -> void:
	if not _have_hash():
		return
	for uid: String in UIDS:
		var seen: Dictionary = {}
		for salt: String in SALTS:
			seen[Api.hash_unit(uid, salt)] = true
		(
			assert_int(seen.size())
			. override_failure_message("two salts give the same value for %s" % uid)
			. is_equal(SALTS.size())
		)


func test_the_salt_is_part_of_the_hashed_text_not_a_suffix() -> void:
	if not _have_hash():
		return
	var swapped: float = Api.expected_unit("fish.rest.x", "f1000001")
	assert_bool(is_equal_approx(Api.hash_unit("f1000001", "fish.rest.x"), swapped)).is_false()


func test_36_the_default_name_salt_is_the_frozen_string() -> void:
	if not _have_hash():
		return
	assert_str(Api.constant(Api.HASH_PATH, "SALT_DEFAULT_NAME", "<missing>")).is_equal(
		"fish.name.default"
	)


func test_36_the_default_name_salt_differs_from_every_other_salt() -> void:
	var salt: String = Api.constant(Api.HASH_PATH, "SALT_DEFAULT_NAME", "<missing>")
	assert_str(salt).is_equal("fish.name.default")
	var others: int = 0
	for other: String in SALTS:
		if other != salt:
			others += 1
	assert_int(others).is_equal(SALTS.size() - 1)
	assert_int(SALTS.count(salt)).is_equal(1)


func test_36_the_default_name_family_is_reserved_for_names() -> void:
	for other: String in SALTS:
		if other != "fish.name.default":
			assert_bool(other.begins_with("fish.name.")).is_false()
