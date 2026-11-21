// Selection mark of a placed item (#31 AC 39, ADR 0012 rule 8; owner decision Q4: a soft glow
// mark). This is the optional "soft fresnel edge glow" of docs/art-style.md (Rendering and look:
// a fresnel term in the material, soft and subtle), never more bloom and never an environment
// change. The placement system puts the selection material on the meshes of the selected drawn
// item as material_overlay, so the mark follows every transform change of that node.
//
// The overlay draws the item's own surfaces a second time and blends glow_colour over them with
// the fresnel term as opacity: zero where a face looks at the camera, rising softly towards the
// silhouette (fresnel_power sets how soft, fresnel_strength the most it covers). Unshaded and
// premultiplied alpha: the output is dst * (1 - a) + glow_colour * a + glow_lift * fresnel with
// a = clamp(fresnel * fresnel_strength, 0, 1). With glow_lift at its zero default this equals
// the former mix blend result within 1/255 (a mix between the lit item and glow_colour, never
// brighter than the brighter of the two), so the mark of #31, #32 and #157 looks as before;
// glow_colour times fresnel_strength stays below the room environment's glow_hdr_threshold, so
// the mark adds no bloom. No shadows, no depth write (the item below has already written the same
// depth), and no screen, depth or normal texture is read.
//
// fog_disabled is part of that identity: Godot mixes the fog into the fragment colour before the
// blend, so with a premultiplied colour it would add fog * fog_amount over the whole overlay even
// where the rim opacity is zero (measured: up to 2/255 brighter item faces). Without fog on the
// overlay the item below keeps its own fog and the rim differs from the former mix blend result
// only by rim opacity * fog_amount * (fog - glow_colour), at most 1/255 in the #33 before and after
// renders.
//
// glow_lift is the brightness term of the refusal cue (#33 AC 15 d, ADR 0012 Amendment 2 rule
// 16): only the cue's runtime copy of the material sets it; the bloom guard of that curve keeps
// the brightest edge channel below the threshold.
//
// Order: render_priority -1 (set on item_selection_material.tres), the same as the water surface
// and unlike the ghost (-4). The mark is drawn after the caustics (-3) and the depth tint (-2),
// which have already shaded the item below it, so the cream rim keeps its colour instead of being
// tinted olive by the water; through the rim's partial opacity the item still shows its water
// shading. It shares -1 with the water surface (the two are sorted by depth) and stays below the
// glass (0), so the glass tint still lies over it.
shader_type spatial;
render_mode blend_premul_alpha, unshaded, cull_back, depth_draw_never, shadows_disabled, fog_disabled;

// Colour of the rim: a warm, soft cream that matches the lamp light.
uniform vec4 glow_colour : source_color = vec4(1.0, 0.86, 0.62, 1.0);
// The most the rim covers the item (at a grazing angle).
uniform float fresnel_strength : hint_range(0.0, 1.0) = 0.7;
// Falloff of the rim: higher keeps it closer to the silhouette.
uniform float fresnel_power : hint_range(0.5, 8.0) = 1.6;
// Light added at the rim, times the fresnel term: linear light, each channel 0.0 to 1.0 (no
// source_color hint, so no sRGB conversion). Zero by default: the selection mark adds nothing.
uniform vec3 glow_lift = vec3(0.0, 0.0, 0.0);

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, fresnel_power);
	float a = clamp(fresnel * fresnel_strength, 0.0, 1.0);
	ALBEDO = glow_colour.rgb * a + glow_lift * fresnel;
	ALPHA = a;
}
