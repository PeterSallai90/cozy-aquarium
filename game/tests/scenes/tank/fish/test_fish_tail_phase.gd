extends GdUnitTestSuite
## #35 CPU tail phase (owner: developer; BA decision Q14, ADR 0013 Amendment 1, ADR 0015 rule 9):
## FishTailPhase (game/scenes/tank/fish/fish_tail_phase.gd, static and pure) advances the tail phase
## of one fish: phase = fposmod(phase + TAU * swim_frequency * mix(REST_FREQUENCY, 1,
## clamp(swim_speed
## * swim_speed_scale, 0, 1)) * delta, TAU). The phase is continuous (the advance of one frame never
##   exceeds the full-speed beat TAU * swim_frequency * delta, nor falls below the rest beat), the
##   tail stands still when the phase is not advanced (pause), and at a constant speed phase(t) =
##   phase0 + TAU * f * t, which is exactly the ADR 0013 rule 5 look of #34. Test decisions: the
##   rest frequency and the two defaults are pinned to the shader include and to the swim_frequency
##   and swim_speed_scale uniforms of fish.gdshader, so the CPU and the GPU cannot drift apart; the
##   constant-speed equivalence uses the shader twin of the real materials.

const Api := preload("res://tests/helpers/fish_swim_api.gd")
const FishApi := preload("res://tests/helpers/fish_api.gd")
const Twin := preload("res://tests/helpers/fish_shader_twin.gd")

const INCLUDE := "res://shaders/fish_common.gdshaderinc"
const SHADER := "res://shaders/fish.gdshader"
const EPS := 1e-9


func _advance(phase: float, speed: float, frequency: float, scale: float, delta: float) -> float:
	var script: GDScript = Api.script_of(Api.TAIL_PATH)
	if script == null:
		assert_bool(false).override_failure_message("FishTailPhase is missing").is_true()
		return Api.MISSING_NUMBER
	return script.call("advance", phase, speed, frequency, scale, delta)


func _have() -> bool:
	return Api.script_of(Api.TAIL_PATH) != null


func _shader_number(path: String, pattern: String) -> float:
	var found: RegExMatch = RegEx.create_from_string(pattern).search(
		FileAccess.get_file_as_string(path)
	)
	if found == null:
		return Api.MISSING_NUMBER
	return found.get_string(1).to_float()


## The wrapped distance from `before` to `after` going forward, in radians (0 to TAU).
func _forward(prior: float, later: float) -> float:
	return fposmod(later - prior, TAU)


func test_35_the_rest_frequency_is_pinned_to_the_shader_include() -> void:
	if not _have():
		assert_bool(false).override_failure_message("FishTailPhase is missing").is_true()
		return
	var from_include: float = _shader_number(
		INCLUDE, "const\\s+float\\s+SWIM_REST_FREQUENCY\\s*=\\s*(-?[0-9.]+)\\s*;"
	)
	assert_float(from_include).is_equal(0.4)
	assert_float(Api.constant(Api.TAIL_PATH, "REST_FREQUENCY", -1.0)).is_equal(from_include)
	assert_float(Twin.SWIM_REST_FREQUENCY).is_equal(from_include)


func test_35_the_default_frequency_and_speed_scale_are_pinned_to_the_shader_uniforms() -> void:
	if not _have():
		assert_bool(false).override_failure_message("FishTailPhase is missing").is_true()
		return
	var frequency: float = _shader_number(
		SHADER, "uniform\\s+float\\s+swim_frequency[^=;]*=\\s*(-?[0-9.]+)\\s*;"
	)
	var scale: float = _shader_number(
		SHADER, "uniform\\s+float\\s+swim_speed_scale[^=;]*=\\s*(-?[0-9.]+)\\s*;"
	)
	assert_float(Api.constant(Api.TAIL_PATH, "DEFAULT_FREQUENCY", -1.0)).is_equal(frequency)
	assert_float(Api.constant(Api.TAIL_PATH, "DEFAULT_SPEED_SCALE", -1.0)).is_equal(scale)
	assert_float(frequency).is_equal(1.5)
	assert_float(scale).is_equal(1.0)


func test_35_at_a_constant_speed_the_phase_is_phase0_plus_tau_f_t() -> void:
	if not _have():
		assert_bool(false).override_failure_message("FishTailPhase is missing").is_true()
		return
	for speed: float in [0.0, 0.25, 0.6, 1.0, 3.0]:
		for frequency: float in [0.8, 1.5, 2.2]:
			var phase: float = 1.234
			var elapsed: float = 0.0
			for _step: int in 600:
				phase = _advance(phase, speed, frequency, 1.0, 1.0 / 60.0)
				elapsed += 1.0 / 60.0
			var rate: float = frequency * lerpf(0.4, 1.0, clampf(speed, 0.0, 1.0))
			var want: float = fposmod(1.234 + TAU * rate * elapsed, TAU)
			(
				assert_float(absf(wrapf(phase - want, -PI, PI)))
				. override_failure_message("speed %.2f frequency %.1f" % [speed, frequency])
				. is_less_equal(1e-6)
			)


func test_35_the_phase_stays_in_zero_to_tau() -> void:
	if not _have():
		assert_bool(false).override_failure_message("FishTailPhase is missing").is_true()
		return
	var phase: float = 0.0
	for _step: int in 5000:
		phase = _advance(phase, 1.0, 2.5, 1.0, 1.0 / 30.0)
		assert_bool(phase >= 0.0 and phase < TAU).is_true()


func test_35_a_frame_never_advances_the_phase_by_more_than_the_full_speed_beat() -> void:
	if not _have():
		assert_bool(false).override_failure_message("FishTailPhase is missing").is_true()
		return
	for frequency: float in [0.5, 1.5, 2.5]:
		for delta: float in [1.0 / 144.0, 1.0 / 60.0, 1.0 / 30.0, 0.5]:
			for speed: float in [0.0, 0.1, 0.5, 0.9, 1.0, 1.2, 6.0]:
				for scale: float in [0.5, 1.0, 2.0]:
					var prior: float = 5.9
					var later: float = _advance(prior, speed, frequency, scale, delta)
					var beat: float = TAU * frequency * delta
					var step: float = _forward(prior, later)
					if beat >= TAU:
						continue
					(
						assert_float(step)
						. override_failure_message(
							(
								"speed %.1f scale %.1f f %.1f delta %.4f advanced %.4f of %.4f"
								% [speed, scale, frequency, delta, step, beat]
							)
						)
						. is_less_equal(beat + EPS)
					)
					(
						assert_float(step)
						. override_failure_message("the tail beats slower than at rest")
						. is_greater_equal(beat * 0.4 - EPS)
					)


func test_35_a_speed_change_does_not_jump_the_phase() -> void:
	if not _have():
		assert_bool(false).override_failure_message("FishTailPhase is missing").is_true()
		return
	var phase: float = 0.7
	var delta: float = 1.0 / 60.0
	var beat: float = TAU * 1.5 * delta
	var speeds: Array[float] = [0.0, 0.0, 1.0, 1.0, 0.2, 0.2, 0.9, 0.0, 6.0, 0.0]
	for speed: float in speeds:
		var next: float = _advance(phase, speed, 1.5, 1.0, delta)
		assert_float(_forward(phase, next)).is_less_equal(beat + EPS)
		phase = next


func test_35_a_zero_delta_leaves_the_phase_unchanged_so_a_paused_tail_stands_still() -> void:
	if not _have():
		assert_bool(false).override_failure_message("FishTailPhase is missing").is_true()
		return
	for speed: float in [0.0, 0.5, 1.0]:
		assert_float(_advance(2.5, speed, 1.5, 1.0, 0.0)).is_equal(2.5)


func test_35_the_speed_is_clamped_before_the_scale_is_applied_to_the_beat() -> void:
	if not _have():
		assert_bool(false).override_failure_message("FishTailPhase is missing").is_true()
		return
	var one: float = _advance(0.0, 1.0, 1.5, 1.0, 0.1)
	assert_float(_advance(0.0, 6.0, 1.5, 1.0, 0.1)).is_equal_approx(one, EPS)
	assert_float(_advance(0.0, 1.0, 1.5, 3.0, 0.1)).is_equal_approx(one, EPS)
	assert_float(_advance(0.0, 0.5, 1.5, 2.0, 0.1)).is_equal_approx(one, EPS)


func test_35_at_a_constant_speed_the_cpu_phase_gives_the_34_wave_of_every_real_material() -> void:
	if not _have():
		assert_bool(false).override_failure_message("FishTailPhase is missing").is_true()
		return
	for id: StringName in FishApi.IDS:
		var path: String = "res://assets/fish/materials/%s.tres" % id
		var material: ShaderMaterial = load(path) as ShaderMaterial
		assert_object(material).override_failure_message("%s is missing" % path).is_not_null()
		if material == null:
			return
		var frequency: float = float(material.get_shader_parameter("swim_frequency"))
		var scale: float = float(material.get_shader_parameter("swim_speed_scale"))
		var amplitude: float = float(material.get_shader_parameter("swim_amplitude"))
		for speed: float in [0.0, 0.4, 1.0]:
			var phase0: float = 2.1
			var phase: float = phase0
			for step: int in 300:
				phase = _advance(phase, speed, frequency, scale, 1.0 / 60.0)
				var time: float = (step + 1) / 60.0
				for z: float in [-0.5, -0.1, 0.4]:
					var old: float = Twin.legacy_bend_x(
						z, time, phase0, speed, amplitude, frequency, scale
					)
					var now: float = Twin.bend_x(z, phase, speed, amplitude, scale)
					if absf(old - now) > 1e-6:
						(
							assert_float(now)
							. override_failure_message(
								(
									"%s speed %.1f at %.2f s differs from the #34 look"
									% [id, speed, time]
								)
							)
							. is_equal_approx(old, 1e-6)
						)
						return
