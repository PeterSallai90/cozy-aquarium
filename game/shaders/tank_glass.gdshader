// Tank glass (#23; docs/art-style.md "the front glass is a thin pane with a slightly green edge
// tint and soft reflections"). Thin transparent panes: almost clear face-on, a fresnel reflection
// that grows at grazing angles, and a green tint on the cut edges. The room has no sky, so the
// reflection is a named fake colour, not a reflection probe. No screen texture, no refraction.
//
// Cut edges: the glass mesh is five plain boxes around the interior box (tools/blender/
// generate_tank.py, unchanged). A point of a pane face lies outside the interior box along one
// axis; a point of a cut edge (the visible end of a pane, where the side pane meets the front
// pane, and the front edge of the bottom pane) lies outside along two axes. That band is exactly
// one glass thickness wide, so the green line never gets wider than the glass. The tint itself is
// one fixed parameter for every tank and is not scaled by the thickness (BA decision on #23).
// glass_interior_size_m is the interior box of the glass mesh, set on the Glass node; zero turns
// the edge tint off. render_priority 0 (above the depth tint and the water surface).
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_never, shadows_disabled;

#define EDGE_EPSILON_M 0.0004

// Glass has no diffuse colour: face-on it only takes away a little light (glass_opacity), and the
// fresnel reflection adds the fake room reflection on top, so the glass never looks milky.
uniform float glass_opacity : hint_range(0.0, 0.2) = 0.025;
uniform vec4 glass_edge_tint : source_color = vec4(0.42, 0.70, 0.56, 1.0);
uniform float glass_edge_opacity : hint_range(0.0, 1.0) = 0.6;
uniform float glass_edge_brightness : hint_range(0.0, 1.0) = 0.12;
// Fake reflection of the dim room: colour, strength at a grazing angle and the fresnel falloff.
uniform vec4 glass_reflection_color : source_color = vec4(0.70, 0.66, 0.80, 1.0);
uniform float glass_reflection_strength : hint_range(0.0, 1.0) = 0.22;
uniform float glass_reflection_power : hint_range(1.0, 8.0) = 5.0;
uniform float glass_roughness : hint_range(0.0, 1.0) = 0.3;
uniform float glass_specular : hint_range(0.0, 1.0) = 0.1;

// Interior box of this glass mesh in metres (x width, y height, z depth); origin on the inner
// floor centre.
instance uniform vec3 glass_interior_size_m = vec3(0.0);

varying vec3 v_local_position;

void vertex() {
	v_local_position = VERTEX;
}

float cut_edge(vec3 p) {
	vec3 size = glass_interior_size_m;
	if (min(min(size.x, size.y), size.z) <= 0.0) {
		return 0.0;
	}
	vec2 half_xz = size.xz * 0.5 + EDGE_EPSILON_M;
	float outside = step(half_xz.x, abs(p.x)) + step(half_xz.y, abs(p.z));
	outside += step(EDGE_EPSILON_M, -p.y);
	return step(1.5, outside);
}

void fragment() {
	float facing = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float fresnel = 0.04 + 0.96 * pow(1.0 - facing, glass_reflection_power);
	float reflection = clamp(fresnel * glass_reflection_strength, 0.0, 1.0);
	float body = clamp(glass_opacity / max(facing, 0.25), 0.0, 1.0);
	float edge = cut_edge(v_local_position);

	// The blend scales the emitted colour by ALPHA, so dividing by it makes the reflection additive.
	float alpha = clamp(body + reflection, 0.001, 1.0);
	vec3 emitted = glass_reflection_color.rgb * reflection / alpha;
	float edge_alpha = max(alpha, glass_edge_opacity);
	vec3 edge_emitted = glass_edge_tint.rgb * glass_edge_brightness / max(edge_alpha, 0.001);

	ALBEDO = mix(vec3(0.0), glass_edge_tint.rgb * 0.2, edge);
	ALPHA = mix(alpha, edge_alpha, edge);
	EMISSION = mix(emitted, edge_emitted, edge);
	ROUGHNESS = glass_roughness;
	SPECULAR = glass_specular;
}
