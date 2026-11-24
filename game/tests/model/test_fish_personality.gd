extends GdUnitTestSuite
## #35 personality and individual variation, D20 (owner: developer): FishPersonality derives five
## traits, in the frozen order speed, boldness, sociability, idle share, depth preference, from the
## uid alone with the FishHash salts fish.trait.* (BA decisions Q11 to Q13, ADR 0015 rule 1). Each
## of the first four is a factor 0.80 + 0.40 * u, the depth preference fraction is (2 * u - 1) *
## 0.20. The expected values here come from the independent FNV-1a of fish_api.gd (expected_unit),
## never from the implementation. The frozen values are in test_fish_personality_golden.gd. Test
## decisions: the class is reached late-bound (fish_swim_api.gd); uids come from a
## RandomNumberGenerator seeded 12345 so the 1,000-uid runs are the same on every run.

const Api := preload("res://tests/helpers/fish_swim_api.gd")
const FishApi := preload("res://tests/helpers/fish_api.gd")
const Rig := preload("res://tests/helpers/fish_swim_rig.gd")
const ViewRig := preload("res://tests/helpers/fish_view_rig.gd")

const SAMPLE := 1000
const SPREAD_MIN := 0.70
const FACTOR_LOW := 0.80
const FACTOR_HIGH := 1.20
const DEPTH_LIMIT := 0.20


func _have() -> bool:
	var found: bool = Api.script_of(Api.PERSONALITY_PATH) != null
	assert_bool(found).override_failure_message("FishPersonality is missing").is_true()
	return found


func _expected(uid: String) -> PackedFloat64Array:
	var result: PackedFloat64Array = PackedFloat64Array()
	for index: int in Api.TRAIT_SALTS.size():
		var unit: float = FishApi.expected_unit(uid, Api.TRAIT_SALTS[index])
		if index < 4:
			result.append(0.80 + 0.40 * unit)
		else:
			result.append((2.0 * unit - 1.0) * 0.20)
	return result


func test_35_a_personality_has_exactly_five_traits_in_the_frozen_order() -> void:
	if not _have():
		return
	var made: Object = Api.personality("f1000001")
	assert_object(made).is_not_null()
	var array: PackedFloat64Array = Api.traits("f1000001")
	assert_int(array.size()).is_equal(5)
	assert_int(Api.TRAIT_NAMES.size()).is_equal(5)
	for index: int in mini(array.size(), 5):
		(
			assert_float(float(made.get(Api.TRAIT_NAMES[index])))
			. override_failure_message(
				"trait %s is not to_array()[%d]" % [Api.TRAIT_NAMES[index], index]
			)
			. is_equal(array[index])
		)


func test_35_the_salts_are_the_five_frozen_strings_in_order() -> void:
	if not _have():
		return
	var salts: Array = Api.constant(Api.PERSONALITY_PATH, "SALTS", [])
	assert_array(salts).is_equal(Array(Api.TRAIT_SALTS))


func test_35_the_formula_constants_are_the_frozen_numbers() -> void:
	if not _have():
		return
	assert_float(Api.constant(Api.PERSONALITY_PATH, "FACTOR_MIN", -1.0)).is_equal_approx(
		0.80, 1e-12
	)
	assert_float(Api.constant(Api.PERSONALITY_PATH, "FACTOR_SPAN", -1.0)).is_equal_approx(
		0.40, 1e-12
	)
	assert_float(Api.constant(Api.PERSONALITY_PATH, "DEPTH_SPAN", -1.0)).is_equal_approx(
		0.20, 1e-12
	)


func test_35_the_traits_follow_the_formulas_for_1000_seeded_uids() -> void:
	if not _have():
		return
	for uid: String in Rig.uids(SAMPLE):
		var got: PackedFloat64Array = Api.traits(uid)
		var want: PackedFloat64Array = _expected(uid)
		assert_int(got.size()).is_equal(5)
		if got.size() != 5:
			return
		for index: int in 5:
			if absf(got[index] - want[index]) > 1e-9:
				(
					assert_float(got[index])
					. override_failure_message("%s trait %d" % [uid, index])
					. is_equal_approx(want[index], 1e-9)
				)
				return


func test_35_every_trait_lies_inside_its_range_over_1000_seeded_uids() -> void:
	if not _have():
		return
	for uid: String in Rig.uids(SAMPLE):
		var got: PackedFloat64Array = Api.traits(uid)
		if got.size() != 5:
			assert_int(got.size()).is_equal(5)
			return
		for index: int in 4:
			if got[index] < FACTOR_LOW or got[index] >= FACTOR_HIGH:
				(
					assert_float(got[index])
					. override_failure_message(
						"%s factor %d is outside 0.80 to 1.20" % [uid, index]
					)
					. is_between(FACTOR_LOW, FACTOR_HIGH - 1e-12)
				)
				return
		if got[4] < -DEPTH_LIMIT or got[4] >= DEPTH_LIMIT:
			(
				assert_float(got[4])
				. override_failure_message("%s depth fraction is outside -0.20 to 0.20" % uid)
				. is_between(-DEPTH_LIMIT, DEPTH_LIMIT - 1e-12)
			)
			return


func test_35_each_of_the_five_traits_covers_at_least_70_percent_of_its_range() -> void:
	if not _have():
		return
	var low: PackedFloat64Array = PackedFloat64Array([INF, INF, INF, INF, INF])
	var high: PackedFloat64Array = PackedFloat64Array([-INF, -INF, -INF, -INF, -INF])
	for uid: String in Rig.uids(SAMPLE):
		var got: PackedFloat64Array = Api.traits(uid)
		if got.size() != 5:
			assert_int(got.size()).is_equal(5)
			return
		for index: int in 5:
			low[index] = minf(low[index], got[index])
			high[index] = maxf(high[index], got[index])
	for index: int in 5:
		var covered: float = (high[index] - low[index]) / 0.4
		(
			assert_float(covered)
			. override_failure_message(
				"%s covers %.2f of its range" % [Api.TRAIT_NAMES[index], covered]
			)
			. is_greater_equal(SPREAD_MIN)
		)


func test_35_deriving_twice_in_any_order_gives_the_same_traits() -> void:
	if not _have():
		return
	var uids: Array[String] = Rig.uids(40)
	var first: Dictionary[String, PackedFloat64Array] = {}
	for uid: String in uids:
		first[uid] = Api.traits(uid)
		assert_int(first[uid].size()).is_equal(5)
	uids.reverse()
	for uid: String in uids:
		assert_array(Array(Api.traits(uid))).is_equal(Array(first[uid]))


func test_35_two_fish_with_different_uids_differ_in_at_least_one_trait_by_more_than_2_percent(
) -> void:
	if not _have():
		return
	var uids: Array[String] = Rig.uids(101)
	for index: int in 100:
		var one: PackedFloat64Array = Api.traits(uids[index])
		var two: PackedFloat64Array = Api.traits(uids[index + 1])
		if one.size() != 5 or two.size() != 5:
			assert_int(one.size()).is_equal(5)
			return
		var largest: float = 0.0
		for trait_index: int in 5:
			largest = maxf(largest, absf(one[trait_index] - two[trait_index]))
		(
			assert_float(largest)
			. override_failure_message(
				"%s and %s differ by only %.4f" % [uids[index], uids[index + 1], largest]
			)
			. is_greater(0.02)
		)
	assert_bool(Api.traits("f1000001") != Api.traits("f1000002")).is_true()


func test_35_the_derivation_takes_the_uid_only_never_the_species() -> void:
	if not _have():
		return
	assert_int(Api.argument_count(Api.PERSONALITY_PATH, "derive")).is_equal(1)
	var made: Object = Api.personality("f1000001")
	var again: Object = Api.personality("f1000001")
	assert_array(Array(made.call("to_array"))).is_equal(Array(again.call("to_array")))


func test_35_the_personality_is_never_saved_and_the_save_format_is_unchanged() -> void:
	if not _have():
		return
	var model: AquariumModel = ViewRig.model(
		ViewRig.MEDIUM, ViewRig.SAND, [ViewRig.fish("f1000001", FishApi.NEON)]
	)
	var result: SaveResult = SaveCodec.new().encode(model, ViewRig.STAMP)
	assert_bool(result.is_ok()).is_true()
	var parsed: Dictionary = JSON.parse_string(result.text)
	assert_int(int(parsed["format_version"])).is_equal(1)
	for entry: Dictionary in parsed["fish"]:
		assert_array(entry.keys()).is_equal(["uid", "species_id", "variant", "nickname"])
	for word: String in ["trait", "personality", "boldness", "sociability"]:
		assert_bool(result.text.contains(word)).is_false()


func test_35_renaming_a_fish_does_not_change_its_traits() -> void:
	if not _have():
		return
	var prior: PackedFloat64Array = Api.traits("f1000003")
	assert_int(prior.size()).is_equal(5)
	var model: AquariumModel = ViewRig.model(
		ViewRig.MEDIUM, ViewRig.SAND, [ViewRig.fish("f1000003", FishApi.ANGEL)]
	)
	var edited: FishInstance = model.get_fish("f1000003").copy()
	edited.nickname = "Goldie"
	model.apply_replace_fish(edited)
	assert_array(Array(Api.traits("f1000003"))).is_equal(Array(prior))


func test_35_the_trait_salts_are_distinct_and_outside_the_other_salt_families() -> void:
	var seen: Dictionary[String, bool] = {}
	for salt: String in Api.TRAIT_SALTS:
		assert_bool(seen.has(salt)).is_false()
		seen[salt] = true
		assert_bool(salt.begins_with("fish.trait.")).is_true()
		assert_bool(salt.begins_with("fish.rest.")).is_false()
		assert_bool(salt.begins_with("fish.name.")).is_false()
		assert_bool(salt == "fish.swim.phase").is_false()
