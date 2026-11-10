// Tank glass (#23; docs/art-style.md "the front glass is a thin pane with a slightly green edge
// tint and soft reflections"). Thin transparent panes: almost clear face-on, a fresnel reflection
// that grows at grazing angles, and a green tint on the cut edges. The room has no sky, so the
// reflection is a named fake colour, not a reflection probe. No screen texture, no refraction.
//
// Cut edges: the glass mesh is five plain boxes around the interior box (tools/blender/
// generate_tank.py, unchanged). The bottom pane covers the whole footprint, the front and back
// panes run over the full outer length, and the side panes sit between them, so each vertical
// corner of the tank is a square column of glass that belongs to the front or back pane. A face
// is classed by its own plane (the dominant axis of its local normal) and its position in that
// plane (#129):
// - Vertical corner column: a face on an x or z plane (the outer face, the pane end, or the side
//   pane end face behind the front or back pane) whose position on the other horizontal axis lies
//   outside the interior (no 0.4 mm epsilon there, only COLUMN_TOLERANCE_M). The whole column
//   then reads as one green band from the inner corner to the outer corner, so no clear sliver of
//   glass shows the room between the water and the band. Off-axis the band is as wide as the
//   projected column (up to the thickness x 1.414; owner decision on #129, amending #23 AC13).
//   One green layer per ray: an outer face stays plain glass where the view ray goes on to the
//   side pane end face behind it, which paints the green instead, so the corner colour equals
//   the single-face green.
// - Everything else (the floor, the bottom pane, the pane tops under the trim): a point outside
//   the interior box along two axes, y counted only below the floor. That keeps the front edge of
//   the bottom pane as before and never paints the floor or the inner faces.
// EDGE_EPSILON_M only absorbs the vertex compression of the plane a face lies on. The column test
// on the other axis is exact, except on faces that point out of the interior: there it allows
// COLUMN_TOLERANCE_M, because the imported vertices on the interior line sit up to 0.015 mm
// inside it (16-bit compression), so a side pane end face starts there and an exact test would
// leave a sub-pixel clear strip that turns a whole pixel column dark when a pixel centre lands in
// it. Both are geometric tolerances, not look values. The tint itself is
// one fixed parameter for every tank and is not scaled by the thickness (BA decision on #23).
// glass_interior_size_m is the interior box of the glass mesh, set on the Glass node; zero turns
// the edge tint off. render_priority 0 (above the depth tint and the water surface). cull_back is
// load-bearing: the side pane end face and the front pane inner face share a plane with opposite
// normals.
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_never, shadows_disabled;

#define EDGE_EPSILON_M 0.0004
#define COLUMN_TOLERANCE_M 0.00002

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
// Model-space face normal. The boxes are flat-shaded with axis-aligned faces, so its dominant
// component names the plane the face lies on.
varying flat vec3 v_local_normal;

void vertex() {
	v_local_position = VERTEX;
	v_local_normal = NORMAL;
}

// True when the view ray, continued from a point p on an outer face of a corner column, reaches
// the side pane end face behind it (on the plane |z| = half z, inside the column, within the side
// pane height). That face paints the green for this ray, so the outer face must not add a second
// layer. `pane` is the column width, read from the outer face's own offset (every pane has the
// same thickness).
bool end_face_behind(vec3 p, vec3 ray, vec3 half_size, float pane) {
	if (abs(ray.z) < 1e-6) {
		return false;
	}
	float t = (sign(p.z) * half_size.z - p.z) / ray.z;
	if (t <= 0.0) {
		return false;
	}
	vec3 hit = p + ray * t;
	float across = hit.x * sign(p.x);
	return across > half_size.x - COLUMN_TOLERANCE_M && across <= half_size.x + pane && hit.y >= 0.0
			&& hit.y <= 2.0 * half_size.y;
}

float cut_edge(vec3 p, vec3 n, vec3 view, mat4 inv_view, mat4 model) {
	vec3 size = glass_interior_size_m;
	if (min(min(size.x, size.y), size.z) <= 0.0) {
		return 0.0;
	}
	vec3 half_size = size * 0.5;
	vec3 an = abs(n);
	if (an.y < max(an.x, an.z)) {
		// A face on an x or z plane: a is its own axis, b the other horizontal axis.
		bool on_x = an.x >= an.z;
		float p_a = on_x ? abs(p.x) : abs(p.z);
		float half_a = on_x ? half_size.x : half_size.z;
		float p_b = on_x ? abs(p.z) : abs(p.x);
		float half_b = on_x ? half_size.z : half_size.x;
		bool outer = p_a > half_a + EDGE_EPSILON_M;
		bool boundary = abs(p_a - half_a) <= EDGE_EPSILON_M;
		// Only a face that points out of the interior (an outer face, a pane end, a side pane end
		// face) can have its own compressed edge on the interior line; an inner face keeps the
		// exact test, so it never paints green straight over the water.
		bool outward = (on_x ? n.x * p.x : n.z * p.z) > 0.0;
		float tolerance = outward ? COLUMN_TOLERANCE_M : 0.0;
		if ((outer || boundary) && p_b > half_b - tolerance) {
			if (outer) {
				vec3 ray = inverse(mat3(model)) * (mat3(inv_view) * -view);
				if (end_face_behind(p, ray, half_size, p_a - half_a)) {
					return 0.0;
				}
			}
			return 1.0;
		}
	}
	vec2 half_xz = half_size.xz + EDGE_EPSILON_M;
	float outside = step(half_xz.x, abs(p.x)) + step(half_xz.y, abs(p.z));
	outside += step(EDGE_EPSILON_M, -p.y);
	return step(1.5, outside);
}

void fragment() {
	float facing = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float fresnel = 0.04 + 0.96 * pow(1.0 - facing, glass_reflection_power);
	float reflection = clamp(fresnel * glass_reflection_strength, 0.0, 1.0);
	float body = clamp(glass_opacity / max(facing, 0.25), 0.0, 1.0);
	float edge = cut_edge(
			v_local_position, v_local_normal, VIEW, INV_VIEW_MATRIX, MODEL_MATRIX);

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
