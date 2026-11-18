// Sand grains of the substrate bed as ray-cast ellipsoids (#28, ADR 0011 rules 6 and 12).
// Each grain is one camera-facing quad. The fragment shader intersects the view ray with the
// ellipsoid of the grain, discards the misses and shades with the true surface normal. A grain is
// therefore a real 3D surface with a correct silhouette and a round outline at any size on
// screen, at two triangles per grain. The instance basis is rotation x ellipsoid semi-axes, so
// the grain is the unit sphere in instance space. Custom data: x lightness, y hue shift (turns),
// z saturation + 4 x baked exposure, w random.
//
// This is the only shader of the bed that writes the vertex position (the quad is turned to the
// camera) and so the depth: a grain keeps the depth of its camera-facing disc at the front of
// the grain, not a depth per pixel (per-pixel depth cost up to 3.7 ms in the look spike, because
// the GPU can then no longer reject hidden pixels early). Shape, normal and lighting are those of
// the ellipsoid, and grains still hide each other in the right order.
shader_type spatial;
render_mode cull_disabled, skip_vertex_transform;

uniform vec4 substrate_tint : source_color = vec4(0.91, 0.85, 0.69, 1.0);
uniform vec3 bed_origin = vec3(0.0);
uniform vec2 bed_half_size = vec2(0.5, 0.2);
uniform float bed_top = 0.03;
uniform float grain_m = 0.0015;
uniform float use_exposure : hint_range(0.0, 1.0) = 1.0;
uniform float exposure_floor : hint_range(0.0, 1.0) = 0.35;
uniform float occlusion_top_depth = 1.6;
uniform float occlusion_glass_depth = 1.5;
uniform float occlusion_floor : hint_range(0.0, 1.0) = 0.1;
uniform float glass_light : hint_range(0.0, 1.0) = 0.9;
uniform float wet_gain : hint_range(0.0, 1.5) = 0.8;
uniform float wet_bottom : hint_range(0.0, 1.0) = 0.88;
uniform float saturation_gain : hint_range(0.0, 2.0) = 1.0;
uniform float grain_roughness : hint_range(0.0, 1.0) = 0.6;
uniform float grain_specular : hint_range(0.0, 1.0) = 0.35;
uniform float bump_strength : hint_range(0.0, 1.0) = 0.25;
// Soft shading: grains are translucent quartz, so the dark side is lifted a little.
uniform float wrap : hint_range(0.0, 1.0) = 0.3;
// Top grains only: grains thin out between fade_begin and fade_end (metres from the camera).
uniform float fade_begin = 1000.0;
uniform float fade_end = 1001.0;
// Top tiles are shared by many cells. With 1 the tone of a grain is drawn again from a hash of
// its position in the bed, from the same spread as the instance data (tone_spread, glint_share,
// glint_gain: the tone values of the look), so repeated tiles never repeat their tone pattern.
uniform float world_hash_tint = 0.0;
uniform float tone_spread : hint_range(0.0, 0.5) = 0.08;
uniform float glint_share : hint_range(0.0, 0.2) = 0.03;
uniform float glint_gain : hint_range(1.0, 2.5) = 1.15;
// How much of the colour of a light the grains take: 1 = all of it, 0 = only its brightness
// (black sand must read black, not brown, under the warm lamp).
uniform float lamp_tint : hint_range(0.0, 1.0) = 1.0;

// Light scattered in the water: a soft fill on everything that is open to the water or to a
// pane, stronger on up-facing parts. A look value, not physics.
uniform float fill_light : hint_range(0.0, 1.0) = 0.1;
uniform vec3 fill_color : source_color = vec3(0.92, 0.95, 1.0);
// Share of the fill that also reaches the top of the bed (the lamp already lights it).
uniform float fill_top : hint_range(0.0, 1.0) = 0.3;

varying flat vec3 v_centre;
varying flat vec3 v_inv0;
varying flat vec3 v_inv1;
varying flat vec3 v_inv2;
varying flat vec4 v_custom;
varying flat vec3 v_world_centre;
varying flat float v_radius;
varying float v_specular;

vec3 hue_shift(vec3 c, float turns) {
	float a = turns * 6.2831853;
	vec3 k = vec3(0.57735);
	float ca = cos(a);
	return c * ca + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - ca);
}

// Hash of a position to one value in 0 to 1. hash31 is adapted from hash13 of "Hash without
// Sine" by David Hoskins, https://www.shadertoy.com/view/4djSRW (Common tab): renamed, with the
// three scale constants and the offset of its hash22. The notice below is the notice of the
// original, quoted verbatim.
//
// Hash without Sine
// MIT License...
// Copyright (c)2014 David Hoskins.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
float hash31(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	mat3 model = mat3(MODEL_MATRIX);
	float radius = max(length(model[0]), max(length(model[1]), length(model[2])));
	vec3 world_centre = MODEL_MATRIX[3].xyz;
	vec3 centre = (VIEW_MATRIX * vec4(world_centre, 1.0)).xyz;
	float distance_to_eye = length(centre);
	// distance fade, dithered per grain
	float keep = 1.0;
	float fade = 1.0 - smoothstep(fade_begin, fade_end, distance_to_eye);
	if (INSTANCE_CUSTOM.w > fade) {
		keep = 0.0;
	}
	vec3 p = world_centre - bed_origin;
	// camera-facing quad that covers the bounding sphere of the grain
	float grow = 1.0 / sqrt(max(1.0 - (radius * radius) / (distance_to_eye * distance_to_eye), 0.25));
	// The disc sits at the front of the grain (pushed towards the eye by the radius), so a grain
	// that pokes out of the sand surface is not cut off by it when depth is not written.
	VERTEX = centre * (1.0 - radius / distance_to_eye) + vec3(VERTEX.xy * radius * grow * 1.02 * keep, 0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
	mat3 inv = inverse(mat3(VIEW_MATRIX) * model);
	v_inv0 = inv[0];
	v_inv1 = inv[1];
	v_inv2 = inv[2];
	v_centre = centre;
	v_custom = INSTANCE_CUSTOM;
	if (world_hash_tint > 0.5) {
		vec3 cellp = floor(p * 4000.0);
		float h1 = hash31(cellp);
		float h2 = hash31(cellp + 19.0);
		float tone = 1.0 + (h1 * 2.0 - 1.0) * tone_spread;
		tone = mix(tone, glint_gain * (1.0 + 0.04 * h1), step(1.0 - glint_share, h2));
		v_custom = vec4(tone, 0.0, INSTANCE_CUSTOM.z, INSTANCE_CUSTOM.w);
	}
	v_world_centre = world_centre;
	v_radius = radius;
}

void fragment() {
	mat3 inv = mat3(v_inv0, v_inv1, v_inv2);
	vec3 dir = normalize(VERTEX);
	vec3 o = inv * (-v_centre);
	vec3 d = inv * dir;
	float a = dot(d, d);
	float b = dot(o, d);
	float c = dot(o, o) - 1.0;
	float disc = b * b - a * c;
	if (disc < 0.0) {
		discard;
	}
	float t = (-b - sqrt(disc)) / a;
	vec3 hit = dir * t;
	vec3 n_obj = o + d * t;
	// a little surface irregularity so the grain is not a perfect bead
	float seed = v_custom.w;
	vec3 q = n_obj * 2.3 + seed * 31.0;
	vec3 bump = vec3(hash31(floor(q)), hash31(floor(q) + 7.0), hash31(floor(q) + 13.0)) - 0.5;
	n_obj = normalize(n_obj + bump * bump_strength);
	vec3 n_view = normalize(transpose(inv) * n_obj);
	n_view = normalize(mix(n_view, vec3(0.0, 0.0, 1.0), wrap * 0.35));

	NORMAL = n_view;
	LIGHT_VERTEX = hit;

	vec3 world_hit = (INV_VIEW_MATRIX * vec4(hit, 1.0)).xyz;
	vec3 p = world_hit - bed_origin;
	vec3 col = hue_shift(substrate_tint.rgb, v_custom.y);
	float grey = dot(col, vec3(0.299, 0.587, 0.114));
	float zq = floor(v_custom.z / 4.0);
	float exposure = zq / 15.0;
	col = mix(vec3(grey), col, (v_custom.z - zq * 4.0) * saturation_gain);
	col *= v_custom.x;
	col *= 1.0 + (hash31(floor(q * 1.7)) - 0.5) * 0.08;
	col *= wet_gain * mix(wet_bottom, 1.0, clamp(p.y / max(bed_top, 0.001), 0.0, 1.0));

	float d_top = (bed_top - p.y) / grain_m;
	float d_glass = min(bed_half_size.x - abs(p.x), bed_half_size.y - abs(p.z)) / grain_m;
	float open_top = 1.0 - smoothstep(-0.25, occlusion_top_depth, d_top);
	float exposed = sqrt(exposure) * mix(exposure_floor, 1.0, smoothstep(-0.8, 0.35, (world_hit.y - v_world_centre.y) / max(v_radius, 0.00001)));
	open_top = mix(open_top, exposed, use_exposure);
	float open_glass = 1.0 - smoothstep(0.05, occlusion_glass_depth, d_glass);
	float open = max(open_top, open_glass * glass_light);
	open = mix(occlusion_floor, 1.0, open * open);

	ALBEDO = clamp(col, vec3(0.0), vec3(1.0));
	float up = (INV_VIEW_MATRIX * vec4(n_view, 0.0)).y;
	float fill_open = max(open_glass, open_top * fill_top);
	EMISSION = ALBEDO * fill_color * fill_light * fill_open * (0.65 + 0.35 * up);
	AO = open;
	AO_LIGHT_AFFECT = 1.0;
	ROUGHNESS = grain_roughness;
	SPECULAR = grain_specular * open;
	v_specular = SPECULAR;
}

// Lambert diffuse and a GGX highlight, with the colour of the light pulled towards its own
// brightness by lamp_tint.
void light() {
	vec3 neutral = vec3(dot(LIGHT_COLOR, vec3(0.2126, 0.7152, 0.0722)));
	vec3 colour = mix(neutral, LIGHT_COLOR, lamp_tint);
	float n_l = max(dot(NORMAL, LIGHT), 0.0);
	DIFFUSE_LIGHT += colour * ATTENUATION * n_l / PI;
	vec3 half_way = normalize(VIEW + LIGHT);
	float n_h = max(dot(NORMAL, half_way), 0.0);
	float n_v = max(dot(NORMAL, VIEW), 0.0001);
	float alpha = max(ROUGHNESS * ROUGHNESS, 0.002);
	float alpha2 = alpha * alpha;
	float spread = n_h * n_h * (alpha2 - 1.0) + 1.0;
	float lobe = alpha2 / (PI * spread * spread);
	float k = alpha * 0.5;
	float shadowing = 0.25 / ((n_l * (1.0 - k) + k) * (n_v * (1.0 - k) + k));
	float f0 = 0.16 * v_specular * v_specular;
	float fresnel = f0 + (1.0 - f0) * pow(1.0 - max(dot(VIEW, half_way), 0.0), 5.0);
	SPECULAR_LIGHT += colour * ATTENUATION * n_l * lobe * shadowing * fresnel * SPECULAR_AMOUNT;
}
