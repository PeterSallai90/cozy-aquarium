// The fish shader (#34, ADR 0013 rules 3 to 5 with Amendment 1). One shader for every species, one
// ShaderMaterial per species (game/assets/fish/materials/<id>.tres) on both glTF surfaces (`body`
// and `fin`); the four per-fish values are instance uniforms set by FishView, so 60 fish share
// three materials.
//
// Inputs of the model (docs/art-style.md, "Generator conventions"):
// - UV2 (glTF TEXCOORD_1): palette atlas lookup, the base colour (never a parameter of its own);
// - UV (glTF TEXCOORD_0): the species mask. R and G are pattern regions read filtered; B holds the
//   eye bands (0 none, 85 pupil, 170 iris ring, 255 painted dot) and is read unfiltered with
//   texelFetch at mip level 0, so a filtered edge between two bands never becomes a third band;
//   A is the tintable body region (0 or 255);
// - COLOR.a: the fin translucency mask (1 = translucent fin, 0 = opaque body).
// Fragment order: atlas, regions, variant tint, shimmer, eye. The maths lives in
// fish_common.gdshaderinc and is mirrored by the CPU twin of the tests.
// Fins are never metallic and the eye is never metallic (its glint comes from SPECULAR and
// ROUGHNESS), so `metallic` acts on the body only.
shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;

// Relative to this file (game/shaders/); test_fish_shader.gd strips `//` comments, so the path
// carries no `res://` prefix.
#include "fish_common.gdshaderinc"

group_uniforms textures;
uniform sampler2D palette_atlas : source_color, filter_nearest, repeat_disable;
uniform sampler2D fish_mask : hint_default_black, filter_linear_mipmap, repeat_disable;

group_uniforms regions;
// Colour of mask region R (neon stripe base, angelfish bars, corydoras flank patch).
uniform vec3 region_r_colour : source_color = vec3(0.5, 0.5, 0.5);
// Colour of mask region G (neon red rear half, corydoras head patch).
uniform vec3 region_g_colour : source_color = vec3(0.5, 0.5, 0.5);

group_uniforms eye;
// Pupil (band 1). The painted dot (band 3) blends from it to the highlight colour.
uniform vec3 eye_colour : source_color = vec3(0.04, 0.04, 0.05);
// Iris ring (band 2); equal to eye_colour on species without a ring.
uniform vec3 eye_iris_colour : source_color = vec3(0.04, 0.04, 0.05);
uniform vec3 eye_highlight_colour : source_color = vec3(1.0, 1.0, 1.0);
// Painted highlight dot: always visible, independent of the light.
uniform float eye_highlight_strength : hint_range(0.0, 1.0) = 0.85;
// Specular glint on the whole eye region: moves as the fish turns.
uniform float eye_glint_strength : hint_range(0.0, 1.0) = 0.8;

group_uniforms fins;
uniform float transmission_strength : hint_range(0.0, 1.0) = 0.5;
uniform vec3 transmission_color : source_color = vec3(0.9, 0.95, 0.9);
uniform float fin_opacity : hint_range(0.0, 1.0) = 0.55;

group_uniforms surface;
uniform float roughness : hint_range(0.0, 1.0) = 0.45;
uniform float specular_amount : hint_range(0.0, 1.0) = 0.5;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

group_uniforms swim;
// Peak lateral tail offset at swim speed 1, in body lengths (allowed 0.06 to 0.12).
uniform float swim_amplitude : hint_range(0.0, 0.15) = 0.10;
// Tail beat in Hz at swim speed 1 (allowed 0.5 to 2.5). Not read by vertex() since #35: read by
// FishView to advance swim_phase (ADR 0013 Amendment 1).
uniform float swim_frequency : hint_range(0.0, 2.5) = 1.5;
// Scales the per-fish swim_speed (1.0 for all species); FishView uses it for the phase rate too.
uniform float swim_speed_scale : hint_range(0.0, 2.0) = 1.0;

group_uniforms shimmer;
// 0 = off (default for every species but the neon tetra).
uniform float shimmer_strength : hint_range(0.0, 1.0) = 0.0;
// Stripe colour looked at head on.
uniform vec3 shimmer_colour_a : source_color = vec3(0.15, 0.85, 0.75);
// Stripe colour at a glancing angle.
uniform vec3 shimmer_colour_b : source_color = vec3(0.12, 0.38, 0.92);
// Shapes the transition from colour a to colour b (allowed 0.5 to 8).
uniform float shimmer_power : hint_range(0.5, 8.0) = 2.0;

group_uniforms variant;
// Share of the base luminance variation kept under a variant tint (0.2 to 0.4).
uniform float variant_tint_keep : hint_range(0.0, 1.0) = 0.3;
group_uniforms;

// Per fish (FishView): the catalog colour_variants[variant] (Godot passes it linear), strength 0
// for variant 0 and 1 otherwise; swim_phase is the current tail phase in radians [0, TAU), advanced
// by FishView every frame from the uid-derived start phase; swim_speed is the clamped real speed,
// clamp(speed / species top speed, 0, 1) (ADR 0013 Amendment 1).
instance uniform vec4 variant_tint_colour = vec4(1.0, 1.0, 1.0, 1.0);
instance uniform float variant_tint_strength = 0.0;
instance uniform float swim_phase = 0.0;
instance uniform float swim_speed = 0.0;

void vertex() {
	VERTEX.x += fish_bend_x(VERTEX.z, swim_phase, swim_speed, swim_amplitude, swim_speed_scale);
}

void fragment() {
	ivec2 mask_size = textureSize(fish_mask, 0);
	ivec2 texel = clamp(ivec2(floor(UV * vec2(mask_size))), ivec2(0), mask_size - ivec2(1));
	int band = fish_eye_band(texelFetch(fish_mask, texel, 0).b);
	float eye = band > 0 ? 1.0 : 0.0;
	vec4 m = texture(fish_mask, UV);

	vec3 c = texture(palette_atlas, UV2).rgb;
	c = mix(c, region_r_colour, m.r);
	c = mix(c, region_g_colour, m.g);
	float body = m.a * (1.0 - eye) * (1.0 - COLOR.a);
	c = fish_tint(c, body, variant_tint_colour.rgb, variant_tint_strength, variant_tint_keep);
	c = fish_shimmer(
			c,
			dot(NORMAL, VIEW),
			shimmer_power,
			shimmer_colour_a,
			shimmer_colour_b,
			shimmer_strength,
			m.r * (1.0 - eye));

	vec3 emission = vec3(0.0);
	if (band == 1) {
		c = eye_colour;
	} else if (band == 2) {
		c = eye_iris_colour;
	} else if (band == 3) {
		c = mix(eye_colour, eye_highlight_colour, eye_highlight_strength);
		emission = eye_highlight_colour * eye_highlight_strength * EYE_DOT_EMISSION;
	}

	ALBEDO = c;
	EMISSION = emission;
	ALPHA = mix(1.0, fin_opacity, COLOR.a);
	BACKLIGHT = transmission_color * transmission_strength * COLOR.a;
	ROUGHNESS = mix(roughness, EYE_GLINT_ROUGHNESS, eye * eye_glint_strength);
	SPECULAR = mix(specular_amount, 1.0, eye * eye_glint_strength);
	METALLIC = metallic * (1.0 - COLOR.a) * (1.0 - eye);
}
