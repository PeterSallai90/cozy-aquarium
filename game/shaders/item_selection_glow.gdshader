// Selection mark of a placed item (#31 AC 39, ADR 0012 rule 8; owner decision Q4: a soft glow
// mark). This is the optional "soft fresnel edge glow" of docs/art-style.md (Rendering and look:
// a fresnel term in the material, soft and subtle), never more bloom and never an environment
// change. The placement system puts the selection material on the meshes of the selected drawn
// item as material_overlay, so the mark follows every transform change of that node.
//
// The overlay draws the item's own surfaces a second time and blends glow_colour over them with
// the fresnel term as opacity: zero where a face looks at the camera, rising softly towards the
// silhouette (fresnel_power sets how soft, fresnel_strength the most it covers). Unshaded and
// blend_mix, so the result is a mix between the lit item and glow_colour and never brighter than
// the brighter of the two; glow_colour times fresnel_strength stays below the room environment's
// glow_hdr_threshold, so the mark adds no bloom. No shadows, no depth write (the item below has
// already written the same depth), and no screen, depth or normal texture is read.
//
// Order: render_priority -1 (set on item_selection_material.tres), the same as the water surface
// and unlike the ghost (-4). The mark is drawn after the caustics (-3) and the depth tint (-2),
// which have already shaded the item below it, so the cream rim keeps its colour instead of being
// tinted olive by the water; through the rim's partial opacity the item still shows its water
// shading. It shares -1 with the water surface (the two are sorted by depth) and stays below the
// glass (0), so the glass tint still lies over it.
shader_type spatial;
render_mode blend_mix, unshaded, cull_back, depth_draw_never, shadows_disabled;

// Colour of the rim: a warm, soft cream that matches the lamp light.
uniform vec4 glow_colour : source_color = vec4(1.0, 0.86, 0.62, 1.0);
// The most the rim covers the item (at a grazing angle).
uniform float fresnel_strength : hint_range(0.0, 1.0) = 0.7;
// Falloff of the rim: higher keeps it closer to the silhouette.
uniform float fresnel_power : hint_range(0.5, 8.0) = 1.6;

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, fresnel_power);
	ALBEDO = glow_colour.rgb;
	ALPHA = clamp(fresnel * fresnel_strength, 0.0, 1.0);
}
