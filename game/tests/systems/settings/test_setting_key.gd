extends GdUnitTestSuite
## AC 14: a typed key definition; a wrong type gets the default, a number out of range is clamped.

const SettingsRig := preload("res://tests/helpers/settings_rig.gd")


func _key(
	value_type: int, default_value: Variant, min_value: float = NAN, max_value: float = NAN
) -> RefCounted:
	var made: RefCounted = SettingsRig.key(
		"s", "k", value_type, default_value, min_value, max_value
	)
	assert_object(made).override_failure_message("SettingKey is missing").is_not_null()
	return made


func test_the_definition_keeps_its_fields() -> void:
	var made: RefCounted = _key(TYPE_FLOAT, 0.5, 0.0, 1.0)
	if made == null:
		return
	assert_str(made.section).is_equal("s")
	assert_str(made.key).is_equal("k")
	assert_int(made.value_type).is_equal(TYPE_FLOAT)
	assert_float(made.default_value).is_equal(0.5)
	assert_bool(made.has_range).is_true()
	assert_float(made.min_value).is_equal(0.0)
	assert_float(made.max_value).is_equal(1.0)
	assert_str(made.id()).is_equal("s/k")


func test_a_key_without_a_range_has_none() -> void:
	var made: RefCounted = _key(TYPE_STRING, "x")
	if made == null:
		return
	assert_bool(made.has_range).is_false()


func test_a_value_of_the_right_type_in_range_is_kept() -> void:
	var made: RefCounted = _key(TYPE_FLOAT, 0.5, 0.0, 1.0)
	if made == null:
		return
	assert_float(made.coerce(0.25)).is_equal(0.25)
	assert_float(made.coerce(0.0)).is_equal(0.0)
	assert_float(made.coerce(1.0)).is_equal(1.0)


func test_a_wrong_type_gets_the_default() -> void:
	var made: RefCounted = _key(TYPE_FLOAT, 0.5, 0.0, 1.0)
	if made == null:
		return
	for bad: Variant in ["loud", true, [0.2], {"a": 1}, null, Vector2(1, 1)]:
		var result: Variant = made.coerce(bad)
		assert_float(result).override_failure_message("for %s" % [bad]).is_equal(0.5)


func test_an_int_is_accepted_for_a_float_key_and_converted() -> void:
	var made: RefCounted = _key(TYPE_FLOAT, 0.5, 0.0, 10.0)
	if made == null:
		return
	var result: Variant = made.coerce(3)
	assert_int(typeof(result)).is_equal(TYPE_FLOAT)
	assert_float(result).is_equal(3.0)


func test_nan_and_infinity_get_the_default() -> void:
	var made: RefCounted = _key(TYPE_FLOAT, 0.5, 0.0, 1.0)
	if made == null:
		return
	for bad: float in [NAN, INF, -INF]:
		assert_float(made.coerce(bad)).override_failure_message("for %s" % bad).is_equal(0.5)


func test_a_float_out_of_range_is_clamped_at_both_ends() -> void:
	var made: RefCounted = _key(TYPE_FLOAT, 0.5, 0.0, 1.0)
	if made == null:
		return
	assert_float(made.coerce(7.5)).is_equal(1.0)
	assert_float(made.coerce(-3.0)).is_equal(0.0)
	assert_float(made.coerce(5)).is_equal(1.0)


func test_an_int_key_clamps_and_rejects_a_float() -> void:
	var made: RefCounted = _key(TYPE_INT, 5, 1.0, 10.0)
	if made == null:
		return
	assert_int(made.coerce(7)).is_equal(7)
	assert_int(made.coerce(99)).is_equal(10)
	assert_int(made.coerce(-4)).is_equal(1)
	assert_int(made.coerce(2.5)).is_equal(5)
	assert_int(made.coerce("7")).is_equal(5)
	assert_int(made.coerce(true)).is_equal(5)


func test_a_bool_key_accepts_only_a_bool() -> void:
	var made: RefCounted = _key(TYPE_BOOL, true)
	if made == null:
		return
	assert_bool(made.coerce(false)).is_false()
	assert_bool(made.coerce(0)).is_true()
	assert_bool(made.coerce("false")).is_true()


func test_a_string_key_accepts_only_a_string() -> void:
	var made: RefCounted = _key(TYPE_STRING, "calm")
	if made == null:
		return
	assert_str(made.coerce("busy")).is_equal("busy")
	assert_str(made.coerce(3)).is_equal("calm")
	assert_str(made.coerce(null)).is_equal("calm")


func test_accepts_checks_the_type_only() -> void:
	var made: RefCounted = _key(TYPE_FLOAT, 0.5, 0.0, 1.0)
	var whole: RefCounted = _key(TYPE_INT, 5, 1.0, 10.0)
	if made == null or whole == null:
		return
	assert_bool(made.accepts(0.2)).is_true()
	assert_bool(made.accepts(1)).is_true()
	assert_bool(made.accepts(7.5)).is_true()
	assert_bool(made.accepts("x")).is_false()
	assert_bool(made.accepts(true)).is_false()
	assert_bool(whole.accepts(3)).is_true()
	assert_bool(whole.accepts(1.5)).is_false()
	assert_bool(whole.accepts("3")).is_false()
