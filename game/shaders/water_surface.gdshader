// Water surface of the tank (#23; docs/art-style.md "Rendering and look"). A flat plane at the
// water line: the ripple comes only from procedural normals animated by TIME, so the plane never
// leaves the water line. Seen from above it is clear with a soft fresnel reflection and lamp
// glints; seen from below (the default view looks up at it through the front glass) it is a plain,
// slightly brighter band, not the underwater look of #45. A thin, subtle meniscus line follows the
// glass; meniscus_strength 0 or meniscus_width_m 0 draws no line, and out-of-range values are
// clamped here, so they never error.
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
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.3;
uniform float surface_specular : hint_range(0.0, 1.0) = 0.15;
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
}
