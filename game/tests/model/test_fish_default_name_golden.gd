extends GdUnitTestSuite
## #36 default fish name (owner: developer): the derived default name is frozen by this file.
##
## FREEZE RULE (BA decision Q11, ADR 0014). The name list is frozen at the earlier of (a) the owner
## writing on issue #36 or #164 that the list is approved, or (b) the v0.1 tag on main.
## STATE: open until owner approval or v0.1 tag
## While the STATE line says "open", the owner may add, remove, reorder or reword names; the same
## pull request then updates this file (COUNT, the key list, the uid-to-key table) and its
## description says "pre-release name list edit". The pull request that records the owner approval
## (or the v0.1 release pull request) changes the line to "STATE: frozen <date>". After that only
## typo and grammar fixes of a text in a .po are allowed; replacing a name, changing COUNT, the key
## order, the salt or the formula is a break that needs a format_version bump with a migration. A
## reviewer rejects any change of this file's expectations while the line says frozen.
##
## The table values were computed once with the reference FNV-1a of fish_api.gd:
## index = min(floor(fnv1a32("fish.name.default:" + uid) / 2^32 * 30), 29) + 1.
## Test decisions: the model class is reached late-bound (fish_edit_api.gd); the distribution uses
## 3000 uids from a seeded UidGenerator, so the counts are the same on every run.

const Edit := preload("res://tests/helpers/fish_edit_api.gd")
const Api := preload("res://tests/helpers/fish_api.gd")

const SELF_PATH := "res://tests/model/test_fish_default_name_golden.gd"
const SALT := "fish.name.default"
const KEY_COUNT := 30
const SEED := 20261123
const SAMPLE := 3000
const FUZZ := 1000
## The largest double below 1.0 and the largest 32-bit hash value over 2^32.
const BELOW_ONE := 1.0 - 1.1102230246251565e-16
const HASH_MAX := 4294967295.0 / 4294967296.0

const GOLDEN: Dictionary[String, String] = {
	"00000000": "fish.default_name.26",
	"ffffffff": "fish.default_name.07",
	"f1000001": "fish.default_name.21",
	"0badf00d": "fish.default_name.30",
	"a1b2c3d4": "fish.default_name.12",
	"00000001": "fish.default_name.26",
	"12345678": "fish.default_name.04",
	"deadbeef": "fish.default_name.23",
	"cafebabe": "fish.default_name.19",
	"0a0b0c0d": "fish.default_name.01",
	"7fffffff": "fish.default_name.27",
	"80000000": "fish.default_name.29",
	"b16b00b5": "fish.default_name.01",
	"a0000001": "fish.default_name.01",
	"e0e0e0e0": "fish.default_name.17",
	"3c3c3c3c": "fish.default_name.11",
}

var _saved_locale: String = ""


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()


func after_test() -> void:
	TranslationServer.set_locale(_saved_locale)


func _have() -> bool:
	var found: bool = Edit.exists(Edit.DEFAULT_NAME)
	(
		assert_bool(found)
		. override_failure_message("game/model/fish_default_name.gd is missing")
		. is_true()
	)
	return found


func _expected_keys() -> PackedStringArray:
	var keys: PackedStringArray = PackedStringArray()
	for number: int in range(1, KEY_COUNT + 1):
		keys.append("fish.default_name.%02d" % number)
	return keys


func _uids(count: int) -> PackedStringArray:
	var generator: UidGenerator = UidGenerator.new(SEED)
	var uids: PackedStringArray = PackedStringArray()
	for i: int in count:
		uids.append(generator.generate(null))
	return uids


func test_36_the_state_line_and_freeze_rule_are_recorded_in_this_file() -> void:
	var text: String = FileAccess.get_file_as_string(SELF_PATH)
	var has_state: bool = (
		text.contains("STATE: open until owner approval or v0.1 tag")
		or text.contains("STATE: frozen ")
	)
	assert_bool(has_state).is_true()
	assert_bool(text.contains("FREEZE RULE")).is_true()


func test_36_the_list_has_30_names() -> void:
	if not _have():
		return
	assert_int(Edit.count()).is_equal(KEY_COUNT)


func test_36_all_keys_are_01_to_30_in_order() -> void:
	if not _have():
		return
	assert_array(Array(Edit.all_keys())).is_equal(Array(_expected_keys()))


func test_36_key_at_formats_two_digits_with_the_prefix() -> void:
	if not _have():
		return
	assert_str(Edit.key_at(1)).is_equal("fish.default_name.01")
	assert_str(Edit.key_at(9)).is_equal("fish.default_name.09")
	assert_str(Edit.key_at(30)).is_equal("fish.default_name.30")


func test_36_the_salt_string_is_frozen() -> void:
	var salt: String = Edit.constant(Edit.HASH, "SALT_DEFAULT_NAME", Edit.MISSING)
	assert_str(salt).is_equal(SALT)


func test_36_the_uid_to_key_table_is_frozen() -> void:
	if not _have():
		return
	assert_int(GOLDEN.size()).is_greater_equal(12)
	for uid: String in GOLDEN:
		(
			assert_str(Edit.key_for(uid))
			. override_failure_message("default name key of %s" % uid)
			. is_equal(GOLDEN[uid])
		)


func test_36_the_key_follows_the_hash_formula_with_the_frozen_salt() -> void:
	if not _have():
		return
	for uid: String in _uids(200):
		var unit: float = Api.expected_unit(uid, SALT)
		var index: int = mini(floori(unit * KEY_COUNT), KEY_COUNT - 1) + 1
		assert_str(Edit.key_for(uid)).is_equal("fish.default_name.%02d" % index)


func test_36_the_key_depends_on_the_uid_only_not_on_the_language() -> void:
	if not _have():
		return
	TranslationServer.set_locale("hu")
	assert_str(Edit.key_for("f1000001")).is_equal("fish.default_name.21")
	TranslationServer.set_locale("en")
	assert_str(Edit.key_for("f1000001")).is_equal("fish.default_name.21")


func test_36_every_key_is_reached_and_none_is_overused_over_3000_uids() -> void:
	if not _have():
		return
	var counts: Dictionary[String, int] = {}
	for uid: String in _uids(SAMPLE):
		var key: String = Edit.key_for(uid)
		counts[key] = counts.get(key, 0) + 1
	for key: String in _expected_keys():
		var seen: int = counts.get(key, 0)
		(
			assert_bool(seen >= 50 and seen <= 150)
			. override_failure_message("%s was chosen %d times, need 50 to 150" % [key, seen])
			. is_true()
		)
	assert_int(counts.size()).is_equal(KEY_COUNT)


func test_36_boundary_unit_zero_is_the_first_name() -> void:
	if not _have():
		return
	assert_int(Edit.index_for_unit(0.0)).is_equal(1)


func test_36_boundary_the_largest_unit_below_one_is_the_last_name_never_31() -> void:
	if not _have():
		return
	assert_int(Edit.index_for_unit(HASH_MAX)).is_equal(30)
	assert_int(Edit.index_for_unit(BELOW_ONE)).is_equal(30)


func test_36_boundary_each_step_edge_moves_to_the_next_name() -> void:
	if not _have():
		return
	assert_int(Edit.index_for_unit(1.0 / 30.0 - 1e-9)).is_equal(1)
	assert_int(Edit.index_for_unit(1.0 / 30.0 + 1e-9)).is_equal(2)
	assert_int(Edit.index_for_unit(29.0 / 30.0 + 1e-9)).is_equal(30)


func test_36_the_index_never_leaves_1_to_30_even_for_out_of_range_units() -> void:
	if not _have():
		return
	assert_int(Edit.index_for_unit(1.0)).is_equal(30)
	assert_int(Edit.index_for_unit(-0.5)).is_equal(1)


func test_36_fuzz_every_key_has_text_in_en_and_hu() -> void:
	if not _have():
		return
	var en: Translation = load("res://localization/en.po") as Translation
	var hu: Translation = load("res://localization/hu.po") as Translation
	var pattern: RegEx = RegEx.create_from_string("^fish\\.default_name\\.(\\d\\d)$")
	for uid: String in _uids(FUZZ):
		var key: String = Edit.key_for(uid)
		var found: RegExMatch = pattern.search(key)
		assert_object(found).override_failure_message("bad key %s" % key).is_not_null()
		if found == null:
			return
		var number: int = found.get_string(1).to_int()
		assert_bool(number >= 1 and number <= KEY_COUNT).is_true()
		assert_str(str(en.get_message(key))).override_failure_message("en %s" % key).is_not_empty()
		assert_str(str(hu.get_message(key))).override_failure_message("hu %s" % key).is_not_empty()


func test_36_all_30_keys_are_listed_in_extra_keys_txt() -> void:
	var listed: PackedStringArray = PackedStringArray()
	var text: String = FileAccess.get_file_as_string("res://localization/extra_keys.txt")
	for line: String in text.split("\n"):
		var trimmed: String = line.strip_edges()
		if not trimmed.is_empty() and not trimmed.begins_with("#"):
			listed.append(trimmed.split(" ")[0])
	for key: String in _expected_keys():
		(
			assert_bool(listed.has(key))
			. override_failure_message("%s is not in extra_keys.txt" % key)
			. is_true()
		)
