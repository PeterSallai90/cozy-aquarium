// Real 3D stones of the substrate bed: gravel, coloured gravel, pebbles (#28, ADR 0011 rule 12).
// Opaque, lit, no texture; the vertex position and the depth are never written. Colour = swatch
// tint x per-stone custom data (x lightness, y hue shift in turns, z saturation + 4 x baked
// exposure 0..15, w random). Stones cast no shadows, so the self-shadowing of the pile is an
// occlusion term: light reaches a fragment from above (the exposure of the stone from the
// offline visibility pass, and the height inside the stone) or through the glass (falls off with
// the distance behind the nearest pane). That gives dark gaps between stones and a lit face at
// every pane.
shader_type spatial;
render_mode cull_back;

uniform vec4 substrate_tint : source_color = vec4(0.48, 0.42, 0.35, 1.0);
// Tank frame, set by SubstrateBedView: world position of the inner floor centre, interior half
// size (x, z), fill depth.
uniform vec3 bed_origin = vec3(0.0);
uniform vec2 bed_half_size = vec2(0.5, 0.2);
uniform float bed_top = 0.04;
// Median drawn stone size in metres: the unit of the occlusion depths.
uniform float grain_m = 0.004;
// 1: the light from above uses the stone's baked exposure (offline visibility pass) and the
// height inside the stone; 0: it falls off with the depth below the fill depth.
uniform float use_exposure : hint_range(0.0, 1.0) = 1.0;
uniform float exposure_floor : hint_range(0.0, 1.0) = 0.25;
uniform float occlusion_top_depth = 1.5;
uniform float occlusion_glass_depth = 1.6;
uniform float occlusion_floor : hint_range(0.0, 1.0) = 0.06;
uniform float glass_light : hint_range(0.0, 1.0) = 0.85;
// Wet look: the whole bed is a little darker and richer than the dry swatch, more so lower down.
uniform float wet_gain : hint_range(0.0, 1.5) = 0.8;
uniform float wet_bottom : hint_range(0.0, 1.0) = 0.85;
uniform float saturation_gain : hint_range(0.0, 2.0) = 1.1;
// Procedural mottling in stone space (stylized noise, art-style "Colouring").
uniform float speckle_strength : hint_range(0.0, 1.0) = 0.18;
uniform float speckle_frequency = 6.0;
uniform float band_strength : hint_range(0.0, 1.0) = 0.0;
uniform float stone_roughness : hint_range(0.0, 1.0) = 0.72;
uniform float stone_specular : hint_range(0.0, 1.0) = 0.3;

// Light scattered in the water: a soft fill on everything that is open to the water or to a
// pane, stronger on up-facing parts. A look value, not physics.
uniform float fill_light : hint_range(0.0, 1.0) = 0.1;
uniform vec3 fill_color : source_color = vec3(0.92, 0.95, 1.0);
// Share of the fill that also reaches the top of the bed (the lamp already lights it).
uniform float fill_top : hint_range(0.0, 1.0) = 0.3;

varying vec3 v_world;
varying vec3 v_local;
varying vec4 v_custom;
varying flat vec3 v_centre;
varying flat float v_size;

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

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(hash31(i), hash31(i + vec3(1.0, 0.0, 0.0)), f.x);
	float b = mix(hash31(i + vec3(0.0, 1.0, 0.0)), hash31(i + vec3(1.0, 1.0, 0.0)), f.x);
	float c = mix(hash31(i + vec3(0.0, 0.0, 1.0)), hash31(i + vec3(1.0, 0.0, 1.0)), f.x);
	float d = mix(hash31(i + vec3(0.0, 1.0, 1.0)), hash31(i + vec3(1.0, 1.0, 1.0)), f.x);
	return mix(mix(a, b, f.y), mix(c, d, f.y), f.z);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_local = VERTEX;
	v_custom = INSTANCE_CUSTOM;
	v_centre = MODEL_MATRIX[3].xyz;
	v_size = length(MODEL_MATRIX[0].xyz);
}

void fragment() {
	vec3 p = v_world - bed_origin;
	float seed = v_custom.w;
	vec3 c = hue_shift(substrate_tint.rgb, v_custom.y);
	float grey = dot(c, vec3(0.299, 0.587, 0.114));
	float zq = floor(v_custom.z / 4.0);
	float exposure = zq / 15.0;
	c = mix(vec3(grey), c, (v_custom.z - zq * 4.0) * saturation_gain);
	c *= v_custom.x;
	// mottling: two octaves of value noise in stone space
	vec3 q = v_local * speckle_frequency + seed * 37.0;
	float n = value_noise(q) * 0.65 + value_noise(q * 2.7 + 11.0) * 0.35;
	c *= 1.0 + (n - 0.5) * 2.0 * speckle_strength;
	// a faint lighter or darker band on some stones (river pebbles)
	vec3 dir = normalize(vec3(sin(seed * 40.0), cos(seed * 23.0) * 0.4, sin(seed * 11.0 + 1.0)));
	float along = dot(v_local, dir) - (fract(seed * 7.0) - 0.5) * 0.4;
	float band = smoothstep(0.09, 0.02, abs(along + (n - 0.5) * 0.08));
	float band_sign = fract(seed * 13.0) > 0.5 ? 1.0 : -0.7;
	c *= 1.0 + band * band_strength * band_sign * step(0.55, fract(seed * 5.0));
	c *= wet_gain * mix(wet_bottom, 1.0, clamp(p.y / max(bed_top, 0.001), 0.0, 1.0));

	float d_top = (bed_top - p.y) / grain_m;
	float d_glass = min(bed_half_size.x - abs(p.x), bed_half_size.y - abs(p.z)) / grain_m;
	float open_top = 1.0 - smoothstep(-0.25, occlusion_top_depth, d_top);
	// baked exposure: a stone that lies open is lit whatever its height; its lower half is
	// tucked between its neighbours
	float inside = (v_world.y - v_centre.y) / max(v_size * 0.5, 0.0001);
	float exposed = sqrt(exposure) * mix(exposure_floor, 1.0, smoothstep(-0.8, 0.35, inside));
	open_top = mix(open_top, exposed, use_exposure);
	float open_glass = 1.0 - smoothstep(0.05, occlusion_glass_depth, d_glass);
	float open = max(open_top, open_glass * glass_light);
	open = mix(occlusion_floor, 1.0, open * open);

	ALBEDO = clamp(c, vec3(0.0), vec3(1.0));
	float up = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y;
	float fill_open = max(open_glass, open_top * fill_top);
	EMISSION = ALBEDO * fill_color * fill_light * fill_open * (0.65 + 0.35 * up);
	AO = open;
	AO_LIGHT_AFFECT = 1.0;
	ROUGHNESS = stone_roughness;
	SPECULAR = stone_specular * open;
}
