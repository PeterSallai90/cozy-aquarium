extends GdUnitTestSuite
## #35 personality golden test (owner: developer): the derived personality is frozen by this file,
## like the default fish name of #36 (carried over from #17).
##
## FREEZE RULE (BA decision Q11 on #36, BA decisions Q11 to Q13 on #35, ADR 0014 and ADR 0015).
## The five salts, their order, the trait count, the ranges and the formulas are frozen at the
## earlier of (a) the owner writing on issue #35 that the personality is approved, or (b) the v0.1
## tag on main.
## STATE: open until owner approval or v0.1 tag
## While the STATE line says "open", the owner may change a salt, the order or a range; the same
## pull request then updates this file and its description says "pre-release personality edit".
## The pull request that records the owner approval (or the v0.1 release pull request) changes the
## line to "STATE: frozen <date>". After that, changing a salt string, the trait count or order, a
## range or a formula is a break that needs a format_version bump with a migration (#17). A reviewer
## rejects any change of this file's expectations while the line says frozen.
##
## The table pins only unitless values (never a species value such as idle share, dart interval, k
## or a cap), so owner tuning is not a frozen-format change. The values come from an independent
## reference, never from the implementation: FNV-1a 32 bit over the UTF-8 bytes of salt + ":" + uid,
## u = hash / 2^32, factor = 0.80 + 0.40 * u for the first four traits, depth fraction =
## (2 * u - 1) * 0.20. The Python script that printed the table (run once, outside Godot):
##
##   def fnv(s):
##       h = 2166136261
##       for b in s.encode("utf-8"):
##           h = ((h ^ b) * 16777619) & 0xFFFFFFFF
##       return h
##   for i, salt in enumerate(SALTS):
##       u = fnv(salt + ":" + uid) / 2**32
##       value = 0.80 + 0.40 * u if i < 4 else (2 * u - 1) * 0.20
##
## Row order: speed, boldness, sociability, idle share, depth preference. The traits do not depend
## on the species (the species id does not enter the hash, BA decision Q12).

const Api := preload("res://tests/helpers/fish_swim_api.gd")
const FishApi := preload("res://tests/helpers/fish_api.gd")

const SELF_PATH := "res://tests/model/test_fish_personality_golden.gd"
const TOLERANCE := 1e-9

const GOLDEN: Dictionary[String, Array] = {
	"00000000":
	[
		0.8036350915208459,
		1.178530373517424,
		0.9054782069288194,
		0.8749224099330605,
		-0.060526014491915706
	],
	"ffffffff":
	[
		0.8646685564890504,
		0.8675551139749587,
		0.875141320284456,
		0.9327556881122292,
		-0.14455052874982358
	],
	"f1000001":
	[
		1.1574100080877543,
		0.8810420996509493,
		0.849190587643534,
		1.154408170003444,
		-0.007016404531896114
	],
	"0badf00d":
	[
		0.8597518841736019,
		0.8201835203915835,
		1.0115432227030396,
		0.8363207621499896,
		0.16743203448131683
	],
	"a1b2c3d4":
	[
		1.0613164732232692,
		1.02593888649717,
		0.9652904606424273,
		1.0047365355305375,
		0.07777743674814702
	],
	"00000001":
	[
		0.8051976290531457,
		1.1769678359851241,
		0.9039156693965197,
		0.8733598724007607,
		-0.05896347695961595
	],
	"12345678":
	[
		1.1722741747274996,
		0.9413547919131816,
		0.8725071943365038,
		0.8877076494507492,
		0.10894339196383954
	],
	"deadbeef":
	[
		0.894499153457582,
		1.0363124140538276,
		0.8051435395143927,
		1.0000523637048901,
		-0.16329843401908875
	],
	"cafebabe":
	[
		0.9042802101932467,
		0.9082485381513834,
		0.8872665585950017,
		0.9365424415096641,
		-0.011500690784305335
	],
	"0a0b0c0d":
	[
		1.0288099793717267,
		1.1846244488842785,
		1.1172436232678593,
		0.8318064256571234,
		0.1511491544544697
	],
	"7fffffff":
	[
		0.9937721545808018,
		0.9028757713735104,
		0.8327030455693603,
		1.0915169807150962,
		-0.08374296976253391
	],
	"80000000":
	[
		0.9161399783566595,
		1.023009838256985,
		1.0609987421892584,
		0.8315057794563473,
		0.017919849976897242
	],
}


func _have() -> bool:
	var found: bool = Api.script_of(Api.PERSONALITY_PATH) != null
	assert_bool(found).override_failure_message("FishPersonality is missing").is_true()
	return found


func test_35_the_state_line_and_freeze_rule_are_recorded_in_this_file() -> void:
	var text: String = FileAccess.get_file_as_string(SELF_PATH)
	var has_state: bool = (
		text.contains("STATE: open until owner approval or v0.1 tag")
		or text.contains("STATE: frozen ")
	)
	assert_bool(has_state).is_true()
	assert_bool(text.contains("FREEZE RULE")).is_true()


func test_35_the_five_salt_strings_are_frozen() -> void:
	var expected: Array[String] = [
		"fish.trait.speed",
		"fish.trait.boldness",
		"fish.trait.sociability",
		"fish.trait.idle_share",
		"fish.trait.depth_preference",
	]
	var from_hash: Array[String] = [
		str(Api.constant(FishApi.HASH_PATH, "SALT_TRAIT_SPEED", "<missing>")),
		str(Api.constant(FishApi.HASH_PATH, "SALT_TRAIT_BOLDNESS", "<missing>")),
		str(Api.constant(FishApi.HASH_PATH, "SALT_TRAIT_SOCIABILITY", "<missing>")),
		str(Api.constant(FishApi.HASH_PATH, "SALT_TRAIT_IDLE_SHARE", "<missing>")),
		str(Api.constant(FishApi.HASH_PATH, "SALT_TRAIT_DEPTH_PREFERENCE", "<missing>")),
	]
	assert_array(from_hash).is_equal(expected)
	assert_array(Array(Api.TRAIT_SALTS)).is_equal(expected)


func test_35_the_trait_count_the_order_and_the_salt_list_are_frozen() -> void:
	if not _have():
		return
	var salts: Array = Api.constant(Api.PERSONALITY_PATH, "SALTS", [])
	assert_int(salts.size()).is_equal(5)
	assert_array(salts).is_equal(Array(Api.TRAIT_SALTS))
	assert_int(Api.traits("f1000001").size()).is_equal(5)
	var made: Object = Api.personality("f1000001")
	var array: PackedFloat64Array = made.call("to_array")
	for index: int in mini(array.size(), 5):
		assert_float(float(made.get(Api.TRAIT_NAMES[index]))).is_equal(array[index])


func test_35_the_ranges_and_formula_constants_are_frozen() -> void:
	if not _have():
		return
	assert_float(Api.constant(Api.PERSONALITY_PATH, "FACTOR_MIN", -1.0)).is_equal(0.80)
	assert_float(Api.constant(Api.PERSONALITY_PATH, "FACTOR_SPAN", -1.0)).is_equal(0.40)
	assert_float(Api.constant(Api.PERSONALITY_PATH, "DEPTH_SPAN", -1.0)).is_equal(0.20)


func test_35_the_uid_to_traits_table_is_frozen() -> void:
	if not _have():
		return
	assert_int(GOLDEN.size()).is_greater_equal(10)
	for uid: String in GOLDEN:
		var got: PackedFloat64Array = Api.traits(uid)
		var want: Array = GOLDEN[uid]
		assert_int(got.size()).override_failure_message("trait count of %s" % uid).is_equal(5)
		if got.size() != 5:
			return
		for index: int in 5:
			(
				assert_float(got[index])
				. override_failure_message("%s %s" % [uid, Api.TRAIT_NAMES[index]])
				. is_equal_approx(float(want[index]), TOLERANCE)
			)


func test_35_the_table_follows_the_hash_formula_with_the_frozen_salts() -> void:
	for uid: String in GOLDEN:
		var want: Array = GOLDEN[uid]
		for index: int in 5:
			var unit: float = FishApi.expected_unit(uid, Api.TRAIT_SALTS[index])
			var value: float = 0.80 + 0.40 * unit if index < 4 else (2.0 * unit - 1.0) * 0.20
			(
				assert_float(value)
				. override_failure_message("table value %s %s" % [uid, Api.TRAIT_NAMES[index]])
				. is_equal_approx(float(want[index]), TOLERANCE)
			)


func test_35_the_derivation_does_not_depend_on_the_species() -> void:
	if not _have():
		return
	assert_int(Api.argument_count(Api.PERSONALITY_PATH, "derive")).is_equal(1)
