// Shared fish math (#34, ADR 0013 rule 5 with Amendment 1). Included by fish.gdshader.
// No uniforms live here: every value is a named parameter of the shader that includes this file.
// Since #35 (ADR 0013 Amendment 1, ADR 0015) the shader keeps no clock: the tail phase is advanced
// on the CPU by FishView (FishTailPhase) and arrives as the current phase in swim_phase, so a
// speed change bends the phase rate, never the phase, and a paused fish keeps its tail pose.
// The CPU twin game/tests/helpers/fish_shader_twin.gd mirrors these functions, and
// test_fish_shader.gd pins the eight constant lines below to the twin: a change of a formula or a
// constant changes the look, needs `needs:owner` and an update of ADR 0013.
//
// Units: model space of the unscaled fish (1.0 = standard length, front +Z). Colours are linear
// RGB (Godot converts `source_color` and instance Color values before the shader reads them).

// Swim bend: the weight grows from s = SWIM_BEND_START (front 20 percent still) to SWIM_BEND_FULL.
const float SWIM_BEND_START = 0.2;
const float SWIM_BEND_FULL = 1.2;
// Share of the amplitude and of the frequency left at swim speed 0 (a resting fish still breathes).
const float SWIM_REST_AMPLITUDE = 0.15;
// Not read by the shader since #35: it sets the CPU phase rate, mirrored by FishTailPhase
// REST_FREQUENCY (test_fish_tail_phase.gd pins the two to each other).
const float SWIM_REST_FREQUENCY = 0.4;
// Phase lag along the body (radians per body length): the wave runs from the head to the tail.
const float SWIM_WAVE_K = 4.0;
// Linear luminance that maps to k = 1 in the variant tint.
const float TINT_LUMA_REF = 0.35;
// Roughness of the eye at full glint, and the emission share of the painted dot.
const float EYE_GLINT_ROUGHNESS = 0.1;
const float EYE_DOT_EMISSION = 0.3;

// Rec. 709 luminance of a linear colour.
float fish_luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// Lateral (x) offset of a vertex at model-space z. s = 0.5 - z: 0 at the snout, 1 at the tail base,
// above 1 on the tail fin. The largest offset of a vertex over a beat is a * w(s).
// swim_phase is the current tail phase in radians; at constant speed the CPU advances it by
// TAU * swim_frequency * mix(SWIM_REST_FREQUENCY, 1, speed) per second, which gives exactly the
// #34 wave. The amplitude uses the same clamped speed as the CPU phase rate.
float fish_bend_x(
		float vertex_z,
		float swim_phase,
		float swim_speed,
		float swim_amplitude,
		float swim_speed_scale) {
	float s = 0.5 - vertex_z;
	float speed = clamp(swim_speed * swim_speed_scale, 0.0, 1.0);
	float w = smoothstep(SWIM_BEND_START, SWIM_BEND_FULL, s);
	float a = swim_amplitude * mix(SWIM_REST_AMPLITUDE, 1.0, speed);
	return a * w * sin(swim_phase - SWIM_WAVE_K * s);
}

// Replace-style variant tint. body = mask alpha * (1 - eye) * (1 - vertex alpha); strength 0 returns
// c unchanged bit for bit (mix with 0), so variant 0 is the untinted fish.
vec3 fish_tint(vec3 c, float body, vec3 tint_colour, float strength, float keep) {
	float k = mix(1.0, clamp(fish_luma(c) / TINT_LUMA_REF, 0.0, 2.0), keep);
	return mix(c, tint_colour * k, clamp(strength, 0.0, 1.0) * body);
}

// Angle-dependent stripe shimmer: colour_a looked at head on, colour_b at a glancing angle.
// region = mask R * (1 - eye).
vec3 fish_shimmer(
		vec3 c,
		float normal_dot_view,
		float power,
		vec3 colour_a,
		vec3 colour_b,
		float strength,
		float region) {
	float g = pow(1.0 - clamp(normal_dot_view, 0.0, 1.0), power);
	return mix(c, mix(colour_a, colour_b, g), clamp(strength, 0.0, 1.0) * region);
}

// Eye band of the unfiltered B value: 0 none, 1 pupil, 2 iris ring, 3 painted dot.
int fish_eye_band(float b) {
	return int(round(b * 3.0));
}
