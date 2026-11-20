// Ghost preview of a picked or dragged item (#31 AC 39, ADR 0012 rule 8; owner decision Q4: a soft
// see-through ghost). The placement system puts the ghost material on every mesh of the item's own
// scene as material_override and switches its shadows off; nothing else uses it.
//
// Colour: the item keeps its own colours. The base colour comes from the decor palette atlas
// through UV2 (glTF TEXCOORD_1) times the baked vertex colour shade, exactly like
// palette_atlas.gdshader with the decor material (vertex_shade 1.0). ghost_tint then pulls it a
// little towards a pale, cool white (ghost_tint_amount), so the ghost reads as a preview and not
// as a placed item. A small emission lift keeps it readable in the dim water without reaching the
// environment's glow threshold (it stays far below 1.0, so it adds no bloom).
//
// See-through: ghost_alpha everywhere, plus ghost_edge_alpha at the silhouette (a soft fresnel
// term), so the outline stays clear while the substrate shows through the body.
//
// Self-overlap: the material has a next_pass with the same shader and depth_only = true, drawn
// one render_priority earlier. That pass writes depth only (depth_draw_always, ALPHA 0), so the
// colour pass shows only the surface nearest to the camera: no darker double layers where the
// amphora handles or the branch twigs overlap the body, whatever the triangle order.
//
// Order: the colour pass uses render_priority -4 and the depth pass -5, below the caustics (-3),
// the depth tint (-2), the water surface (-1) and the glass (0). The ghost is therefore drawn
// first among the transparent tank layers, and the caustics and the depth tint (blend_mul, depth
// test off) multiply over it just as over the opaque scene, so the ghost sits in the same water
// as the placed items. Reads no screen, depth or normal texture.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back;

uniform sampler2D palette_atlas : source_color, filter_nearest, repeat_disable;
// 0 = ignore the vertex colours, 1 = multiply by them (the decor items bake their shade there).
uniform float vertex_shade : hint_range(0.0, 1.0) = 1.0;
// Opacity of the body; the substrate shows through the rest.
uniform float ghost_alpha : hint_range(0.0, 1.0) = 0.5;
// Pale colour the item colour is pulled towards, and how far (0 = the item colours unchanged).
uniform vec4 ghost_tint : source_color = vec4(0.86, 0.94, 1.0, 1.0);
uniform float ghost_tint_amount : hint_range(0.0, 1.0) = 0.15;
// Extra opacity at the silhouette and the falloff of that soft edge term.
uniform float ghost_edge_alpha : hint_range(0.0, 1.0) = 0.3;
uniform float ghost_edge_power : hint_range(0.5, 8.0) = 2.0;
// Emission as a share of the ghost colour (kept well below the glow threshold).
uniform float ghost_lift : hint_range(0.0, 0.5) = 0.05;
uniform float roughness : hint_range(0.0, 1.0) = 0.8;
// True only on the depth pre-pass in next_pass: writes depth, draws no colour.
uniform bool depth_only = false;

void fragment() {
	vec3 colour = texture(palette_atlas, UV2).rgb * mix(vec3(1.0), COLOR.rgb, vertex_shade);
	colour = mix(colour, ghost_tint.rgb, ghost_tint_amount);
	float edge = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), ghost_edge_power);
	ALBEDO = colour;
	ROUGHNESS = roughness;
	EMISSION = colour * ghost_lift;
	float alpha = clamp(ghost_alpha + edge * ghost_edge_alpha, 0.0, 1.0);
	ALPHA = depth_only ? 0.0 : alpha;
}
