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


# --- #23 criterion 3: in-tank fog needs the volumetric fog on and nothing foggy in the room ---


func test_23_ac03_volumetric_fog_is_enabled() -> void:
	assert_bool(_environment().volumetric_fog_enabled).is_true()


func test_23_ac03_the_global_fog_density_is_zero() -> void:
	assert_float(_environment().volumetric_fog_density).is_equal(0.0)


func test_23_ac03_the_global_fog_albedo_is_white() -> void:
	assert_bool(_environment().volumetric_fog_albedo.is_equal_approx(Color.WHITE)).is_true()


func test_23_ac03_the_global_fog_emission_is_black_with_zero_energy() -> void:
	var environment: Environment = _environment()
	assert_bool(environment.volumetric_fog_emission.is_equal_approx(Color.BLACK)).is_true()
	assert_float(environment.volumetric_fog_emission_energy).is_equal(0.0)


func test_23_ac03_anisotropy_and_the_injects_are_zero() -> void:
	var environment: Environment = _environment()
	assert_float(environment.volumetric_fog_anisotropy).is_equal(0.0)
	assert_float(environment.volumetric_fog_gi_inject).is_equal(0.0)
	assert_float(environment.volumetric_fog_ambient_inject).is_equal(0.0)


func test_23_ac03_the_sky_does_not_affect_the_fog() -> void:
	assert_float(_environment().volumetric_fog_sky_affect).is_equal(0.0)


func test_23_ac03_length_is_between_3_and_8_metres_and_detail_spread_is_in_the_engine_range(
) -> void:
	var environment: Environment = _environment()
	assert_float(environment.volumetric_fog_length).is_between(3.0, 8.0)
	assert_float(environment.volumetric_fog_detail_spread).is_between(0.5, 6.0)


func test_23_ac03_tonemap_glow_and_ambient_are_unchanged() -> void:
	var environment: Environment = _environment()
	assert_int(environment.tonemap_mode).is_equal(Environment.TONE_MAPPER_AGX)
	assert_bool(environment.glow_enabled).is_true()
	assert_float(environment.ambient_light_energy).is_equal_approx(0.28, 0.0001)
