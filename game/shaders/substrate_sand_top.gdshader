// The procedural sand surface of the substrate bed, under and beyond the real grains (#28,
// ADR 0011 rule 6). No texture, no parallax, the vertex position is never written. Procedural
// grains at the drawn grain size: every cell of a jittered cellular pattern is one round grain
// with its own tone, a domed normal and a soft dark gap around it; a few cells glint. The grain
// detail fades out where a cell gets smaller than about a pixel, so the far surface reads as
// soft, matte, evenly coloured sand and does not alias. Near the camera this surface lies under
// the dense layer of real grains and is only seen between them, as the next grains further down.
// The pattern lives in the space of the bed, not of a tile, so it cannot show the tile grid.
shader_type spatial;
render_mode cull_back;

uniform vec4 substrate_tint : source_color = vec4(0.91, 0.85, 0.69, 1.0);
uniform vec3 bed_origin = vec3(0.0);
uniform float grain_m = 0.0015;
uniform float wet_gain : hint_range(0.0, 1.5) = 0.8;
uniform float tone_spread : hint_range(0.0, 0.5) = 0.1;
uniform float glint_share : hint_range(0.0, 0.2) = 0.04;
uniform float glint_gain : hint_range(1.0, 2.5) = 1.16;
uniform float bump_strength : hint_range(0.0, 2.0) = 1.1;
uniform float gap_darken : hint_range(0.0, 1.0) = 0.35;
uniform float ripple_strength : hint_range(0.0, 1.0) = 0.12;
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.8;
uniform float surface_specular : hint_range(0.0, 1.0) = 0.3;
// Under the dense real grains (near the camera) the surface is in their shade.
uniform float shade_near : hint_range(0.0, 1.0) = 0.62;
uniform float shade_begin = 0.22;
uniform float shade_end = 0.36;
// How much of the colour of a light the surface takes: 1 = all of it, 0 = only its brightness.
uniform float lamp_tint : hint_range(0.0, 1.0) = 1.0;

varying vec3 v_world;
varying float v_specular;

// Hashes of a cell to values in 0 to 1. hash22 is hash22 and hash21 is hash12 (with the
// offset of hash22) from "Hash without Sine" by David Hoskins,
// https://www.shadertoy.com/view/4djSRW (Common tab), reformatted. The notice below is the
// notice of the original, quoted verbatim.
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
vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// about 1.25 cells per median grain: the pattern counts as many grains as the real layer
	vec2 uv = (v_world.xz - bed_origin.xz) / (grain_m * 0.85);
	// cells per pixel: the grain detail fades between 0.5 and 1.5 cells per pixel
	float footprint = max(length(dFdx(uv)), length(dFdy(uv)));
	float detail = 1.0 - smoothstep(0.5, 1.5, footprint);

	vec2 cell = floor(uv);
	vec2 f = fract(uv);
	float d1 = 8.0;
	vec2 nearest = vec2(0.0);
	vec2 offset = vec2(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = g + hash22(cell + g) * 0.7 + 0.15 - f;
			float d = dot(o, o);
			if (d < d1) {
				d1 = d;
				nearest = cell + g;
				offset = o;
			}
		}
	}
	d1 = sqrt(d1);
	float tone_rand = hash21(nearest + 3.7);
	float kind = hash21(nearest + 9.1);
	float size = mix(0.38, 0.62, hash21(nearest + 5.3));
	// 1 on the grain, 0 in the gap around it
	float body = 1.0 - smoothstep(size * 0.7, size * 1.15, d1);
	float tone = 1.0 + (tone_rand * 2.0 - 1.0) * tone_spread;
	float glint = step(1.0 - glint_share, kind);
	tone = mix(tone, glint_gain, glint);
	float ripple = value_noise(uv * 0.03) * 0.6 + value_noise(uv * 0.1 + 17.0) * 0.4;
	vec3 col = substrate_tint.rgb * wet_gain;
	col *= mix(1.0, tone, mix(0.3, 1.0, detail));
	col *= 1.0 + (ripple - 0.5) * ripple_strength;
	col *= mix(1.0 - gap_darken * 0.45, mix(1.0 - gap_darken, 1.0, body), detail);
	float eye_distance = length(VERTEX);
	col *= mix(shade_near, 1.0, smoothstep(shade_begin, shade_end, eye_distance));
	ALBEDO = clamp(col, vec3(0.0), vec3(1.0));

	// every grain is a little dome: the normal leans away from the grain centre
	vec2 lean = -offset / max(size, 0.2) * bump_strength * detail * body;
	vec3 n_world = normalize(vec3(lean.x, 1.0, lean.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	ROUGHNESS = mix(surface_roughness, 0.25, glint * detail);
	SPECULAR = mix(surface_specular, 0.9, glint * detail);
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
