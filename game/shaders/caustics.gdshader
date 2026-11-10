// Lamp caustics on the surfaces inside the tank water (#126, ADR 0007 Amendment 1 rule 6;
// docs/art-style.md "Rendering and look": slow animated projected pattern, up-facing surfaces
// first, fading with depth and in shade).
//
// Technique: a box the size of the water volume, drawn on its back faces with the depth test off,
// like the depth tint. Each pixel reads the opaque depth once, rebuilds that surface point in the
// WaterVolume frame and keeps it only when it lies inside the water box (1 mm tolerance, less than
// half of the thinnest glass), inside the lamp cone and inside the lamp range. Frame, trim,
// cabinet, room wall and anything above the water line are outside the box and get nothing; glass
// is not in the depth buffer and gets nothing either. For a kept point the normal comes from four
// neighbouring depth samples, and the weight is up-facing x depth below the water surface along
// the lamp axis x soft cone edge x soft range end.
//
// Pattern: generated here, no image. Two layers of animated cellular (Worley edge) noise projected
// along the lamp axis in the WaterVolume frame, so it is anchored to the tank and never slides
// when the camera orbits. Every cell point turns on a circle a whole number of times per cycle,
// so the animation repeats exactly after 1 / caustic_speed seconds with no jump.
//
// Output: blend_mul with 1 + caustic light, so the caustic brightens what the opaque pass already
// lit; dark or shaded surfaces gain proportionally less. Checked on Godot 4.7.2 Forward+: the
// HDR colour buffer keeps a multiply factor above 1 (no clamp), so this needs no additive pass.
//
// render_priority -3 (below the depth tint, the water surface and the glass). Reads the depth
// texture, never the screen texture or the normal-roughness buffer. No light(), no shadows.
shader_type spatial;
render_mode blend_mul, cull_front, unshaded, depth_draw_never, depth_test_disabled,
		shadows_disabled, fog_disabled;

#include "res://shaders/water_common.gdshaderinc"

// Box tolerance in metres: at most 1 mm (ADR 0007 Amendment 1, technical plan of #126).
#define CAUSTIC_BOX_TOLERANCE_M 0.001
// Share of the cone half-angle and of the range over which the weight fades to zero.
#define CAUSTIC_EDGE_FADE 0.8
// Up-facing weight is zero once the normal points this far down.
#define CAUSTIC_DOWN_LIMIT 0.2
// Smallest |lamp_direction.y| used for the depth along the lamp axis.
#define CAUSTIC_MIN_AXIS_Y 0.2
// Second pattern layer: cell frequency factor and rotation (radians) against the first layer.
#define CAUSTIC_LAYER2_FREQUENCY 1.4
#define CAUSTIC_LAYER2_ROTATION 0.7
// Warp of the pattern coordinates in cell units (bends the straight cell edges).
#define CAUSTIC_WARP 0.18

// --- Look values (technical-artist). The three caustic values come per instance from
// WaterCausticSettings; this material holds no copy of them. ---

// Colour of the caustic light, multiplied onto the lit surface (white keeps the lamp colour).
uniform vec4 caustic_color : source_color = vec4(1.0, 0.97, 0.9, 1.0);
// Brightness added at the brightest line on a flat floor at the water surface, at intensity 1.
uniform float caustic_peak_gain : hint_range(0.0, 4.0) = 1.5;
// Weight of a vertical face against a flat floor (0 to 0.25, the BA limit).
uniform float caustic_side_weight : hint_range(0.0, 0.25) = 0.25;
// Distance along the lamp axis below the water surface over which the weight falls to 1/e.
uniform float caustic_depth_falloff_m : hint_range(0.05, 2.0) = 0.45;
// Line sharpness: 1 = soft and wide, higher = thinner lines.
uniform float caustic_sharpness : hint_range(0.5, 6.0) = 2.0;
// Edge width of the cell lines in cell units (wider = softer and more spread).
uniform float caustic_line_width : hint_range(0.05, 0.8) = 0.45;

// --- Per instance, set by TankCaustics (WaterVolume frame, metres). ---

// Full water box size; 0 means no output.
instance uniform vec3 water_size_m = vec3(0.0);
instance uniform vec3 lamp_position_m = vec3(0.0);
instance uniform vec3 lamp_direction = vec3(0.0, -1.0, 0.0);
// Spot half-angle in degrees, as SpotLight3D.spot_angle.
instance uniform float lamp_spot_angle_deg = 45.0;
// Spot range in metres; 0 means no output.
instance uniform float lamp_spot_range_m = 0.0;
// Mirror of the WaterCausticSettings defaults (tested): linear multiplier, cycles per second,
// cells per metre.
instance uniform float caustic_intensity = 0.4;
instance uniform float caustic_speed = 0.25;
instance uniform float caustic_scale = 25.0;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;

// Hash of a cell to two values in 0 to 1 (Dave Hoskins, hash22, MIT).
vec2 caustic_hash2(vec2 cell) {
	vec3 q = fract(vec3(cell.xyx) * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yzx + 33.33);
	return fract((q.xx + q.yz) * q.zy);
}

// One animated cellular layer: 1 on a cell edge, falling to 0 inside the cell. Each cell point
// moves on a circle one turn per cycle (clockwise or anticlockwise by the hash), so the layer is
// periodic in phase with period 1.
float caustic_layer(vec2 uv, float phase, float seed) {
	vec2 base = floor(uv);
	vec2 inside = uv - base;
	float nearest = 8.0;
	float second = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 offset = vec2(float(i), float(j));
			vec2 h = caustic_hash2(base + offset + seed);
			float turns = h.x < 0.5 ? -1.0 : 1.0;
			float angle = TAU * (turns * phase + h.y);
			vec2 point = offset + 0.5 + 0.32 * vec2(cos(angle), sin(angle));
			float d = length(point - inside);
			if (d < nearest) {
				second = nearest;
				nearest = d;
			} else if (d < second) {
				second = d;
			}
		}
	}
	float edge = 1.0 - smoothstep(0.0, caustic_line_width, second - nearest);
	return pow(edge, max(caustic_sharpness, 0.01));
}

// Caustic pattern at a local point, 0 to 1, projected along the lamp axis.
float caustic_pattern(vec3 local_point, vec3 axis) {
	vec3 helper = abs(axis.x) < 0.9 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 0.0, 1.0);
	vec3 u = normalize(cross(axis, helper));
	vec3 v = cross(u, axis);
	vec2 uv = vec2(dot(local_point, u), dot(local_point, v)) * caustic_scale;
	float phase = fract(TIME * caustic_speed);
	// Gentle periodic warp, one turn per cycle, so the cell edges bend into soft wavy lines.
	uv += CAUSTIC_WARP * vec2(sin(uv.y * 1.3 + TAU * phase), sin(uv.x * 1.1 - TAU * phase));
	float c = cos(CAUSTIC_LAYER2_ROTATION);
	float s = sin(CAUSTIC_LAYER2_ROTATION);
	vec2 uv2 = mat2(vec2(c, s), vec2(-s, c)) * uv * CAUSTIC_LAYER2_FREQUENCY;
	float first = caustic_layer(uv, phase, 0.0);
	float second = caustic_layer(uv2, phase, 17.0);
	return clamp(0.65 * first + 0.5 * second, 0.0, 1.0);
}

// Opaque surface point at a screen coordinate, in the WaterVolume frame.
vec3 caustic_local_point(vec2 uv, mat4 inv_projection, mat4 inv_view, mat3 to_local, vec3 origin) {
	float depth = textureLod(depth_texture, uv, 0.0).r;
	vec3 view = water_view_from_depth(inv_projection, uv, depth);
	vec3 world = (inv_view * vec4(view, 1.0)).xyz;
	return to_local * (world - origin);
}

// The neighbour difference with the smaller step, so a silhouette edge does not tilt the normal.
vec3 caustic_step(vec3 centre, vec3 forward, vec3 backward) {
	vec3 ahead = forward - centre;
	vec3 behind = centre - backward;
	return dot(ahead, ahead) < dot(behind, behind) ? ahead : behind;
}

// Weight from the surface normal: 1 facing up, caustic_side_weight vertical, 0 facing down.
float caustic_up_weight(float normal_y) {
	float side = clamp(caustic_side_weight, 0.0, 1.0);
	if (normal_y >= 0.0) {
		return side + (1.0 - side) * normal_y;
	}
	return side * (1.0 - smoothstep(0.0, CAUSTIC_DOWN_LIMIT, -normal_y));
}

void fragment() {
	float light = 0.0;
	vec3 half_size = water_size_m * 0.5;
	bool active = min(min(water_size_m.x, water_size_m.y), water_size_m.z) > 0.0
			&& lamp_spot_range_m > 0.0 && caustic_intensity > 0.0;
	if (active) {
		mat3 to_local = transpose(mat3(MODEL_MATRIX));
		vec3 origin = MODEL_MATRIX[3].xyz;
		vec3 point = caustic_local_point(
				SCREEN_UV, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX, to_local, origin);
		vec3 axis = normalize(lamp_direction);
		vec3 to_point = point - lamp_position_m;
		float lamp_distance = length(to_point);
		float cone_cos = cos(radians(clamp(lamp_spot_angle_deg, 0.1, 89.9)));
		float inner_cos = cos(radians(clamp(lamp_spot_angle_deg, 0.1, 89.9) * CAUSTIC_EDGE_FADE));
		float point_cos = dot(to_point / max(lamp_distance, 1.0e-4), axis);
		if (water_point_in_box(point, half_size, CAUSTIC_BOX_TOLERANCE_M)
				&& point_cos > cone_cos && lamp_distance < lamp_spot_range_m) {
			float w_cone = smoothstep(cone_cos, inner_cos, point_cos);
			float w_range = 1.0 - smoothstep(
					CAUSTIC_EDGE_FADE * lamp_spot_range_m, lamp_spot_range_m, lamp_distance);
			vec2 texel = 1.0 / VIEWPORT_SIZE;
			vec3 right = caustic_local_point(SCREEN_UV + vec2(texel.x, 0.0),
					INV_PROJECTION_MATRIX, INV_VIEW_MATRIX, to_local, origin);
			vec3 left = caustic_local_point(SCREEN_UV - vec2(texel.x, 0.0),
					INV_PROJECTION_MATRIX, INV_VIEW_MATRIX, to_local, origin);
			vec3 up = caustic_local_point(SCREEN_UV + vec2(0.0, texel.y),
					INV_PROJECTION_MATRIX, INV_VIEW_MATRIX, to_local, origin);
			vec3 down = caustic_local_point(SCREEN_UV - vec2(0.0, texel.y),
					INV_PROJECTION_MATRIX, INV_VIEW_MATRIX, to_local, origin);
			vec3 normal = cross(caustic_step(point, right, left), caustic_step(point, up, down));
			vec3 camera_local = to_local * (CAMERA_POSITION_WORLD - origin);
			normal = normalize(normal);
			if (dot(normal, camera_local - point) < 0.0) {
				normal = -normal;
			}
			float w_up = caustic_up_weight(normal.y);
			float axis_depth = (half_size.y - point.y) / max(-axis.y, CAUSTIC_MIN_AXIS_Y);
			float w_depth = exp(-max(axis_depth, 0.0) / max(caustic_depth_falloff_m, 0.01));
			float weight = w_up * w_depth * w_cone * w_range;
			if (weight > 0.0) {
				light = caustic_intensity * caustic_peak_gain * weight
						* caustic_pattern(point, axis);
			}
		}
	}
	ALBEDO = vec3(1.0) + caustic_color.rgb * light;
	ALPHA = 1.0;
}
