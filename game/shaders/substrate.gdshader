// Substrate floor of the tank (#28; docs/art-style.md "Hardscape and substrate" and "Colouring";
// technical plan of #28, visual layer). One shared opaque, lit material for all five substrate
// types; the type look comes per instance from the catalog through SubstrateLayer.apply_look().
//
// Technique: procedural stylised grains, no image. One 3x3 cellular (Voronoi) evaluation gives
// the grain under each pixel (its random values, the distance to the grain centre and to the
// joint with the next grain); one value-noise lookup adds a soft low-frequency mottle across the
// bed. Grain coordinates are the layer's local x and z in metres divided by grain_scale, so a
// grain has the same real size in all three tanks and is anchored to the tank (it never slides
// when the camera orbits).
//
// Grain shapes (same numbers as SubstrateDefinition.GrainShape):
// - 0 SPECKLE (sand): small grains with faint joints, a few odd grains (dark specks on light sand,
//   light specks on dark sand), rare glints and a soft rippled surface.
// - 1 ANGULAR (natural gravel): irregular polygon grains, one tilted facet and a shaded rim per
//   grain, dark gaps of varying width, a per-grain brown and grey mix.
// - 2 ROUND (pebbles, coloured gravel): packed oval stones lit as low domes (gentle on top, steep
//   at the rim), dark gaps between them and a light sheen on top.
// grain_contrast scales the per-grain tone and hue spread, the odd grains and the mottle; the
// joints and the relief belong to the shape.
//
// Relief is shading only (BA decisions Q1 and Q13 of #28): the normal is perturbed and the joints
// are darkened; the mesh is never displaced, so the top face stays at the inner floor and items
// placed at y = 0 never sink into the stones.
//
// Anti-aliasing: the grain detail (per-grain tone, joints, relief, glints) fades out once a grain
// covers less than about one and a half pixels, before it can shimmer, and leaves the mean tone
// and the mottle. Caustics (#126) and the depth tint (#23) need nothing here: this is an opaque,
// up-facing surface in the depth buffer inside the water box.
//
// Per pixel: one 3x3 cellular pass (9 hashes) and one value-noise lookup (4 hashes); no texture
// fetch, no screen, depth or normal-roughness read.
shader_type spatial;
render_mode cull_back;

#define SHAPE_SPECKLE 0
#define SHAPE_ANGULAR 1
#define SHAPE_ROUND 2

// Smallest grain size in metres the pattern accepts (guards a zero or negative grain_scale).
#define MIN_GRAIN_M 0.0005
// Footprint of one pixel in grains at which the grain detail starts and ends fading out.
#define DETAIL_FADE_START 0.45
#define DETAIL_FADE_END 1.1
// Grain centre jitter inside its cell, per shape: random sand, irregular gravel, packed stones.
#define JITTER_SPECKLE 0.9
#define JITTER_ANGULAR 0.9
#define JITTER_ROUND 0.7
// Stretch of the round stones along one random axis per stone (1 = circular): small round
// grains (coloured gravel) stay nearly round, river pebbles are clearly oval.
#define OVAL_STRETCH_SMALL 1.15
#define OVAL_STRETCH_LARGE 1.5
#define OVAL_SMALL_GRAIN_M 0.006
#define OVAL_LARGE_GRAIN_M 0.015
// Gap width per grain: the shape's joint width times a random factor in this range.
#define GAP_MIN_FACTOR 0.6
#define GAP_MAX_FACTOR 1.5
// Stone radius range in grains (gravel and round stones): the corners of a grain beyond its
// radius fall into the gap, which opens the dark pockets where three stones meet.
#define ANGULAR_RADIUS_MIN 0.6
#define ANGULAR_RADIUS_MAX 0.8
#define ROUND_RADIUS_MIN 0.66
#define ROUND_RADIUS_MAX 0.8
// Soft width of the stone outline, in grains.
#define OUTLINE_SOFTNESS 0.07
// Width of the shaded rim of a gravel grain, in grains, and its darkening.
#define RIM_WIDTH 0.22
#define RIM_DARKNESS 0.22
// Darkening of the rim of a round stone where it meets its neighbours (contact shadow).
#define ROUND_RIM_DARKNESS 0.35
// Ambient occlusion in the gaps between gravel grains and round stones.
#define GAP_OCCLUSION 0.75
// Size of the low-frequency mottle in grains, and its smallest size in metres.
#define MOTTLE_GRAINS 7.0
#define MOTTLE_MIN_M 0.025
// Sand ripple wavelength in grains, its direction (radians) and its slope.
#define RIPPLE_GRAINS 24.0
#define RIPPLE_ANGLE 0.45
#define RIPPLE_SLOPE 0.07
// Share of the joint darkening kept as an even mean tone once the grain detail has faded out.
#define JOINT_MEAN_SHARE 0.3
// Sand: share of odd grains and their tone at grain_contrast 1 on light and on dark sand; tints
// with a luminance below ODD_DARK_TINT_LUMA count as dark.
#define ODD_SHARE 0.18
#define ODD_TONE_ON_LIGHT 0.3
#define ODD_TONE_ON_DARK 2.4
#define ODD_DARK_TINT_LUMA 0.08
// Sand: share of grains that glint and their roughness.
#define GLINT_SHARE 0.025
#define GLINT_ROUGHNESS 0.45
// Per-grain warm or cool shift at grain_contrast 1.
#define HUE_RANGE 0.08

// --- Look values (technical-artist), the same for every type. The per-type values are the
// four instance uniforms below; this material holds no copy of them. ---

// Roughness of sand grains, of a gravel facet, and of the top of a round stone.
uniform float speckle_roughness : hint_range(0.0, 1.0) = 0.9;
uniform float angular_roughness : hint_range(0.0, 1.0) = 0.75;
uniform float round_roughness : hint_range(0.0, 1.0) = 0.6;
// Specular amount of the whole floor (lower keeps the lamp from washing the grains out).
uniform float substrate_specular : hint_range(0.0, 1.0) = 0.35;
// Darkening of the gaps between grains, per shape.
uniform float speckle_joint_darkness : hint_range(0.0, 1.0) = 0.2;
uniform float angular_joint_darkness : hint_range(0.0, 1.0) = 0.65;
uniform float round_joint_darkness : hint_range(0.0, 1.0) = 0.85;
// Mean gap width as a share of a grain, per shape.
uniform float speckle_joint_width : hint_range(0.01, 0.5) = 0.1;
uniform float angular_joint_width : hint_range(0.01, 0.5) = 0.09;
uniform float round_joint_width : hint_range(0.01, 0.5) = 0.12;
// Slope of a gravel facet and of the rim of a round stone (normal tilt, shading only).
uniform float facet_slope : hint_range(0.0, 1.5) = 0.55;
uniform float dome_slope : hint_range(0.0, 1.5) = 0.8;
// Per-grain tone spread and mottle spread at grain_contrast 1.
uniform float grain_tone_range : hint_range(0.0, 1.0) = 0.7;
uniform float mottle_range : hint_range(0.0, 1.0) = 0.12;
// Per-grain move towards grey at grain_contrast 1 (the brown and grey mix of natural gravel).
uniform float grey_mix : hint_range(0.0, 1.0) = 0.6;

// --- Per instance, set by SubstrateLayer.apply_look() from the catalog. The defaults are neutral
// placeholders, not catalog values. ---

// Substrate colour (the model colour: a catalog swatch, or a kept non-swatch save colour).
instance uniform vec4 substrate_tint : source_color = vec4(0.8, 0.78, 0.72, 1.0);
// Apparent grain size in metres.
instance uniform float grain_scale = 0.004;
// 0 SPECKLE, 1 ANGULAR, 2 ROUND.
instance uniform int grain_shape = 0;
// 0..1: strength of the per-grain tone and hue spread, the odd grains and the mottle.
instance uniform float grain_contrast = 0.3;

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

// Integer xorshift-multiply mix of one value (own code; the two multipliers are the published
// constants of Chris Wellons' public-domain "lowbias32" finaliser).
uint substrate_mix(uint value) {
	uint h = value;
	h ^= h >> 16u;
	h *= 0x7FEB352Du;
	h ^= h >> 15u;
	h *= 0x846CA68Bu;
	h ^= h >> 16u;
	return h;
}

// Four values in 0 to 1 for an integer cell.
vec4 substrate_hash4(vec2 cell) {
	uvec2 q = uvec2(ivec2(floor(cell)) + ivec2(65536));
	uint a = substrate_mix(q.x * 0x9E3779B1u + substrate_mix(q.y));
	uint b = substrate_mix(a ^ 0x68E31DA4u);
	uint c = substrate_mix(b ^ 0xB5297A4Du);
	uint d = substrate_mix(c ^ 0x1B56C4E9u);
	return vec4(float(a), float(b), float(c), float(d)) / 4294967295.0;
}

// Smooth value noise, 0 to 1.
float substrate_value_noise(vec2 p) {
	vec2 base = floor(p);
	vec2 f = p - base;
	vec2 w = f * f * (3.0 - 2.0 * f);
	float a = substrate_hash4(base).x;
	float b = substrate_hash4(base + vec2(1.0, 0.0)).x;
	float c = substrate_hash4(base + vec2(0.0, 1.0)).x;
	float d = substrate_hash4(base + vec2(1.0, 1.0)).x;
	return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
}

// One 3x3 cellular pass in grain units. f1 and f2: distances to the nearest and second-nearest
// grain centre; to_centre: vector from the nearest centre to p; rnd: the nearest grain's values.
void substrate_cells(
		vec2 p, float jitter, float stretch, out float f1, out float f2, out vec2 to_centre,
		out vec4 rnd) {
	vec2 base = floor(p);
	vec2 inside = p - base;
	f1 = 8.0;
	f2 = 8.0;
	to_centre = vec2(0.0);
	rnd = vec4(0.5);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 offset = vec2(float(i), float(j));
			vec4 h = substrate_hash4(base + offset);
			vec2 centre = offset + 0.5 + jitter * (h.xy - 0.5);
			vec2 delta = inside - centre;
			vec2 measured = delta;
			if (stretch > 1.0) {
				float angle = h.z * PI;
				vec2 axis = vec2(cos(angle), sin(angle));
				measured = vec2(dot(delta, axis), dot(delta, vec2(-axis.y, axis.x)) * stretch);
			}
			float d = length(measured);
			if (d < f1) {
				f2 = f1;
				f1 = d;
				to_centre = delta;
				rnd = h;
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
}

void fragment() {
	float grain = max(grain_scale, MIN_GRAIN_M);
	float contrast = clamp(grain_contrast, 0.0, 1.0);
	int shape = clamp(grain_shape, SHAPE_SPECKLE, SHAPE_ROUND);
	vec2 p = v_local.xz / grain;
	float footprint = length(fwidth(p));
	float detail = 1.0 - smoothstep(DETAIL_FADE_START, DETAIL_FADE_END, footprint);

	float jitter = JITTER_SPECKLE;
	float joint_darkness = speckle_joint_darkness;
	float joint_width = speckle_joint_width;
	if (shape == SHAPE_ANGULAR) {
		jitter = JITTER_ANGULAR;
		joint_darkness = angular_joint_darkness;
		joint_width = angular_joint_width;
	} else if (shape == SHAPE_ROUND) {
		jitter = JITTER_ROUND;
		joint_darkness = round_joint_darkness;
		joint_width = round_joint_width;
	}

	float f1;
	float f2;
	vec2 to_centre;
	vec4 rnd;
	float stretch = 1.0;
	if (shape == SHAPE_ROUND) {
		stretch = mix(OVAL_STRETCH_SMALL, OVAL_STRETCH_LARGE,
				smoothstep(OVAL_SMALL_GRAIN_M, OVAL_LARGE_GRAIN_M, grain));
	}
	substrate_cells(p, jitter, stretch, f1, f2, to_centre, rnd);
	// Distance to the joint with the next grain, in grains (half the F2 - F1 gap).
	float edge = 0.5 * (f2 - f1);
	float gap = joint_width * mix(GAP_MIN_FACTOR, GAP_MAX_FACTOR, rnd.w);
	float open = smoothstep(0.35 * gap, gap, edge);
	// Stone radius and the normalised distance from the stone centre (1 at the outline).
	float radius = 8.0;
	if (shape == SHAPE_ANGULAR) {
		radius = mix(ANGULAR_RADIUS_MIN, ANGULAR_RADIUS_MAX, rnd.w);
	} else if (shape == SHAPE_ROUND) {
		radius = mix(ROUND_RADIUS_MIN, ROUND_RADIUS_MAX, rnd.w);
	}
	open *= 1.0 - smoothstep(radius - OUTLINE_SOFTNESS, radius, f1);
	float mottle = substrate_value_noise(v_local.xz / max(grain * MOTTLE_GRAINS, MOTTLE_MIN_M));

	// Colour: tint, per-grain move towards grey and warm or cool shift, per-grain tone, mottle.
	vec3 tint = substrate_tint.rgb;
	float luma = dot(tint, vec3(0.2126, 0.7152, 0.0722));
	vec3 colour = mix(tint, vec3(luma), grey_mix * contrast * rnd.y * detail);
	float hue = HUE_RANGE * contrast * (2.0 * rnd.z - 1.0) * detail;
	colour *= vec3(1.0 + hue, 1.0, 1.0 - hue);
	// The per-grain tone only darkens (from 1 down to 1 - range), so it survives the bright lamp;
	// once the detail fades it settles on the mean.
	float grain_tone = grain_tone_range * contrast;
	float tone = mix(1.0 - 0.5 * grain_tone, 1.0 - grain_tone * rnd.x, detail)
			+ mottle_range * contrast * (2.0 * mottle - 1.0);

	// Relief: normal tilt in the layer's local frame (x, z across the floor, y up).
	vec2 tilt = vec2(0.0);
	float roughness = speckle_roughness;
	// 0 at the grain centre, 1 at its outline (the joint with the next grain or, for round stones,
	// the stone radius, whichever comes first).
	float r = f1 / max(f1 + edge, 1.0e-4);
	if (shape == SHAPE_ROUND) {
		r = clamp(max(r, f1 / radius), 0.0, 1.0);
	}
	vec2 outward = to_centre / max(length(to_centre), 1.0e-4);
	if (shape == SHAPE_ANGULAR) {
		float rim = smoothstep(gap, gap + RIM_WIDTH, edge);
		tone *= mix(1.0 - RIM_DARKNESS * JOINT_MEAN_SHARE, mix(1.0 - RIM_DARKNESS, 1.0, rim), detail);
		tilt = facet_slope * (2.0 * rnd.zy - 1.0) + 0.6 * dome_slope * (1.0 - rim) * outward;
		roughness = angular_roughness;
	} else if (shape == SHAPE_ROUND) {
		// Low dome: the slope grows with r^2, gentle on top and steep at the rim.
		tilt = 1.6 * dome_slope * r * r * outward;
		tone *= mix(1.0 - ROUND_RIM_DARKNESS * JOINT_MEAN_SHARE,
				1.0 - ROUND_RIM_DARKNESS * r * r * r, detail);
		roughness = mix(min(round_roughness + 0.3, 1.0), round_roughness, open * (1.0 - r * r));
	} else {
		tilt = 0.25 * facet_slope * (2.0 * rnd.zy - 1.0);
		float odd_tone = luma < ODD_DARK_TINT_LUMA ? ODD_TONE_ON_DARK : ODD_TONE_ON_LIGHT;
		float odd_here = rnd.w < ODD_SHARE ? 1.0 + (odd_tone - 1.0) * contrast : 1.0;
		float odd_mean = 1.0 + ODD_SHARE * (odd_tone - 1.0) * contrast;
		tone *= mix(odd_mean, odd_here, detail);
		if (rnd.z > 1.0 - GLINT_SHARE) {
			roughness = mix(speckle_roughness, GLINT_ROUGHNESS, detail);
		}
	}
	float joint = mix(1.0 - joint_darkness * JOINT_MEAN_SHARE,
			mix(1.0 - joint_darkness, 1.0, open), detail);
	colour *= max(tone, 0.0) * joint;
	// No relief in the gaps between stones: they read as an even shadow.
	tilt *= detail * (shape == SHAPE_SPECKLE ? 1.0 : open);
	if (shape == SHAPE_SPECKLE) {
		vec2 ripple_dir = vec2(cos(RIPPLE_ANGLE), sin(RIPPLE_ANGLE));
		float phase = TAU * dot(p, ripple_dir) / RIPPLE_GRAINS + 3.0 * mottle;
		tilt += RIPPLE_SLOPE * cos(phase) * ripple_dir;
	}
	vec3 local_normal = normalize(vec3(tilt.x, 1.0, tilt.y));

	ALBEDO = clamp(colour, vec3(0.0), vec3(1.0));
	ROUGHNESS = roughness;
	SPECULAR = substrate_specular;
	AO = mix(1.0, 1.0 - GAP_OCCLUSION * (1.0 - open), detail * step(0.5, float(shape)));
	NORMAL = normalize((VIEW_MATRIX * (MODEL_MATRIX * vec4(local_normal, 0.0))).xyz);
}
