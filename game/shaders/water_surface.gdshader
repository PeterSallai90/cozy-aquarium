// Water surface of the tank (#23; docs/art-style.md "Rendering and look"). A flat plane at the
// water line: the ripple comes only from procedural normals animated by TIME, so the plane never
// leaves the water line. Seen from above it is clear with a soft fresnel reflection and a small,
// rippled lamp glint (custom light(), #128); seen from below (the default view looks up at it
// through the front glass) it is a plain, slightly brighter band, not the underwater look of #45.
// A thin, subtle meniscus line follows the glass; meniscus_strength 0 or meniscus_width_m 0 draws
// no line, and out-of-range values are clamped here, so they never error.
// render_priority -1 (above the depth tint, below the glass). No screen texture.
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

#include "res://shaders/water_common.gdshaderinc"

#define MENISCUS_WIDTH_MAX_M 0.006

// Top side: body colour, opacity face-on and the extra opacity of the fresnel reflection.
uniform vec4 surface_color : source_color = vec4(0.78, 0.92, 0.94, 1.0);
uniform float surface_opacity : hint_range(0.0, 0.5) = 0.06;
uniform vec4 surface_reflection_color : source_color = vec4(0.62, 0.66, 0.78, 1.0);
uniform float surface_reflection_strength : hint_range(0.0, 1.0) = 0.35;
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.15;
uniform float surface_specular : hint_range(0.0, 1.0) = 0.3;
// Lamp light on the top side (#128). The lamp hangs a few centimetres above the water, so its
// direct light is very strong there. surface_light_diffuse scales the direct (Lambert) lamp light
// on the top side: a clear water film scatters almost none of it, and full diffuse paints a wide
// bright disc under the lamp. The lamp glint is a narrow GGX highlight (surface_roughness,
// surface_specular, broken up by the ripple) that is soft-capped at glint_max. The cap is scaled
// with the opacity, so the glint as seen does not grow where the fresnel reflection makes the
// surface more opaque (grazing views). The underside and the meniscus line keep full diffuse; the
// underside keeps the plain highlight.
uniform float surface_light_diffuse : hint_range(0.0, 1.0) = 0.0;
uniform float glint_max : hint_range(0.0, 50.0) = 15.0;
// Underside, seen from below through the front glass.
uniform vec4 underside_color : source_color = vec4(0.70, 0.86, 0.90, 1.0);
uniform float underside_opacity : hint_range(0.0, 1.0) = 0.22;
uniform float underside_brightness : hint_range(0.0, 1.0) = 0.12;
// Ripple: tiny, calm, normals only.
uniform float ripple_strength : hint_range(0.0, 1.0) = 0.2;
uniform float ripple_cells_per_m : hint_range(5.0, 120.0) = 45.0;
uniform float ripple_speed : hint_range(0.0, 0.5) = 0.06;
// Meniscus at the glass. The width slider ends one float step below 6 mm, because 0.006 itself is
// stored as 0.00600000005 in 32-bit floats; the clamp below still allows the full 6 mm.
uniform float meniscus_strength : hint_range(0.0, 1.0) = 0.3;
uniform float meniscus_width_m : hint_range(0.0, 0.0059999996, 0.0001) = 0.003;
uniform vec4 meniscus_color : source_color = vec4(0.88, 0.96, 0.97, 1.0);

// Full water box size in metres, set per tank by TankWater.build().
instance uniform vec3 water_size_m = vec3(0.0);

varying vec3 v_local_position;
// Written in fragment(), read in light(): 1.0 on the top side, 0.0 on the underside; the scale of
// the direct diffuse light; the glint cap scale surface_opacity / ALPHA.
varying float v_top_side;
varying float v_diffuse_scale;
varying float v_glint_cap_scale;

void vertex() {
	v_local_position = VERTEX;
}

// Gradient (d/dx, d/dz) of a sum of four slow directional waves, in waves per cell.
vec2 ripple_gradient(vec2 p, float t) {
	const vec2 DIRS[4] = vec2[4](
		vec2(0.96, 0.28), vec2(-0.42, 0.91), vec2(-0.83, -0.56), vec2(0.21, -0.98));
	const float FREQ[4] = float[4](1.0, 1.37, 0.71, 1.83);
	const float SPEED[4] = float[4](1.0, -0.83, 0.61, -1.21);
	vec2 gradient = vec2(0.0);
	for (int i = 0; i < 4; i++) {
		float k = FREQ[i] * 6.2831853;
		float phase = dot(DIRS[i], p) * k + t * SPEED[i] * 6.2831853;
		gradient += DIRS[i] * k * cos(phase) / FREQ[i];
	}
	return gradient * 0.25;
}

float meniscus_line(vec2 local_xz) {
	float width = clamp(meniscus_width_m, 0.0, MENISCUS_WIDTH_MAX_M);
	float strength = clamp(meniscus_strength, 0.0, 1.0);
	if (width <= 0.0 || strength <= 0.0 || min(water_size_m.x, water_size_m.z) <= 0.0) {
		return 0.0;
	}
	float to_wall = water_distance_to_wall(local_xz, water_size_m.xz);
	float band = 1.0 - clamp(to_wall / width, 0.0, 1.0);
	return band * band * strength;
}

void fragment() {
	vec2 p = v_local_position.xz * ripple_cells_per_m;
	vec2 slope = ripple_gradient(p, TIME * ripple_speed) * clamp(ripple_strength, 0.0, 1.0) * 0.15;
	NORMAL_MAP = vec3(-slope.x, -slope.y, 1.0) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;

	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = 0.02 + 0.98 * pow(1.0 - facing, 5.0);
	float meniscus = meniscus_line(v_local_position.xz);

	v_top_side = FRONT_FACING ? 1.0 : 0.0;
	if (FRONT_FACING) {
		float reflection = fresnel * surface_reflection_strength;
		float sheen = clamp(reflection * 2.0, 0.0, 1.0);
		ALBEDO = mix(surface_color.rgb, surface_reflection_color.rgb, sheen);
		ALPHA = clamp(surface_opacity + reflection, 0.0, 1.0);
		EMISSION = surface_reflection_color.rgb * reflection * 0.25;
	} else {
		ALBEDO = underside_color.rgb;
		ALPHA = clamp(underside_opacity, 0.0, 1.0);
		EMISSION = underside_color.rgb * underside_brightness;
	}
	ALBEDO = mix(ALBEDO, meniscus_color.rgb, meniscus);
	ALPHA = max(ALPHA, meniscus * 0.8);
	EMISSION += meniscus_color.rgb * meniscus * 0.2;
	ROUGHNESS = surface_roughness;
	SPECULAR = surface_specular;
	// The meniscus line keeps the full direct light it had in #23; only the open film is dimmed.
	float film_diffuse = mix(clamp(surface_light_diffuse, 0.0, 1.0), 1.0, meniscus);
	v_diffuse_scale = mix(1.0, film_diffuse, v_top_side);
	v_glint_cap_scale = clamp(surface_opacity, 0.0, 1.0) / max(ALPHA, 1.0e-4);
}

// Lambert diffuse plus GGX specular, as Godot's built-in model for a light with light_size 0
// (#128). On the top side the diffuse is scaled by surface_light_diffuse (not on the meniscus
// line) and the specular is soft-capped: cap * (1 - exp(-specular / cap)) on its brightest
// channel, hue kept.
void light() {
	float n_dot_l = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * n_dot_l * v_diffuse_scale / PI;
	if (n_dot_l > 0.0 && ROUGHNESS > 0.0) {
		vec3 half_vector = normalize(VIEW + LIGHT);
		float n_dot_h = clamp(dot(NORMAL, half_vector), 0.0, 1.0);
		float n_dot_v = clamp(dot(NORMAL, VIEW), 1.0e-4, 1.0);
		float l_dot_h = clamp(dot(LIGHT, half_vector), 0.0, 1.0);
		float alpha = ROUGHNESS * ROUGHNESS;
		float alpha2 = alpha * alpha;
		float d_term = (n_dot_h * alpha2 - n_dot_h) * n_dot_h + 1.0;
		float distribution = alpha2 / (PI * d_term * d_term);
		float visibility = 0.5 / mix(2.0 * n_dot_l * n_dot_v, n_dot_l + n_dot_v, alpha);
		float f0 = 0.16 * surface_specular * surface_specular;
		float f90 = clamp(f0 * 49.5, 0.0, 1.0);
		float fresnel = f0 + (f90 - f0) * pow(1.0 - l_dot_h, 5.0);
		vec3 specular = (
			LIGHT_COLOR * ATTENUATION * SPECULAR_AMOUNT * n_dot_l * distribution * visibility
			* fresnel
		);
		float strength = max(max(specular.r, specular.g), specular.b);
		if (v_top_side > 0.5 && strength > 0.0) {
			float cap = max(glint_max, 0.0) * v_glint_cap_scale;
			specular *= cap > 0.0 ? cap * (1.0 - exp(-strength / cap)) / strength : 0.0;
		}
		SPECULAR_LIGHT += specular;
	}
}
