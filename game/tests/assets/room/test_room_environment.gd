extends GdUnitTestSuite
## #22 criterion 12 (environment), owner: technical-artist. Ranges, so tuning inside them needs no
## test change. Tuned tonemap and glow values belong to later area:render issues (BA decision
## Q11b): everything except the switches stays at the Godot default.

const PATH := "res://scenes/room/room_environment.tres"


func _environment() -> Environment:
	var exists: bool = ResourceLoader.exists(PATH)
	assert_bool(exists).override_failure_message("environment missing: %s" % PATH).is_true()
	if not exists:
		return Environment.new()
	var environment: Environment = load(PATH) as Environment
	assert_object(environment).is_not_null()
	return environment if environment != null else Environment.new()


func test_ac12_ambient_light_comes_from_a_colour() -> void:
	assert_int(_environment().ambient_light_source).is_equal(Environment.AMBIENT_SOURCE_COLOR)


func test_ac12_ambient_energy_is_between_005_and_030() -> void:
	assert_float(_environment().ambient_light_energy).is_between(0.05, 0.30)


func test_ac12_ambient_colour_luminance_is_at_most_035() -> void:
	assert_float(_environment().ambient_light_color.get_luminance()).is_less_equal(0.35)


func test_ac12_tonemap_mode_is_agx() -> void:
	assert_int(_environment().tonemap_mode).is_equal(Environment.TONE_MAPPER_AGX)


func test_ac12_glow_is_enabled() -> void:
	assert_bool(_environment().glow_enabled).is_true()


func test_ac12_tuned_values_stay_at_the_godot_defaults() -> void:
	var environment: Environment = _environment()
	var defaults: Environment = Environment.new()
	assert_float(environment.tonemap_exposure).is_equal(defaults.tonemap_exposure)
	assert_float(environment.tonemap_white).is_equal(defaults.tonemap_white)
	assert_float(environment.glow_intensity).is_equal(defaults.glow_intensity)
	assert_float(environment.glow_hdr_threshold).is_equal(defaults.glow_hdr_threshold)
