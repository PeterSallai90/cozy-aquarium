// Opaque shader of the placed decor items (#32): the output of palette_atlas.gdshader (#22, #157)
// plus one per-instance colour, so a recoloured item needs no material of its own (docs/art-style.md,
// "Colouring": colour customization through shader parameters; ADR 0012 Amendment 1).
// The base colour comes from the decor atlas through UV2 (glTF TEXCOORD_1, one texel per face,
// nearest filter). vertex_shade multiplies it by the vertex colour RGB (the linear shade the
// generator bakes: crevice darkening, grain, the contact shade at the foot and the dark inside of
// the amphora). Back faces are culled.
// item_tint is set per GeometryInstance3D by PlacedItemsView, never in the material:
// - alpha 0 (the default): the original look, exactly the palette_atlas.gdshader output;
// - alpha 1: the atlas colour is replaced by the tint colour. The tint is the 8-bit sRGB swatch
//   colour as stored in the catalog, set as a Color; Godot 4.7.2 converts a Color instance
//   parameter to linear before the shader reads it (measured with the "calibrate" job of
//   scenes/dev/item_tint_preview: equal to a StandardMaterial3D albedo of the same Color), so the
//   shader uses it as it is and must not convert it again. The vertex shade still multiplies it,
//   so form shading, the rim and the dark interior stay; it is not a multiply on top of the
//   terracotta. A tinted surface is a glaze: glaze_roughness replaces the roughness (fired,
//   unglazed clay is matt, a glaze has a soft sheen).
shader_type spatial;
render_mode cull_back;

uniform sampler2D palette_atlas : source_color, filter_nearest, repeat_disable;
uniform float roughness : hint_range(0.0, 1.0) = 0.75;
uniform float specular_amount : hint_range(0.0, 1.0) = 0.5;
uniform float emission_from_v : hint_range(0.0, 1.0) = 1.0;
uniform float emission_energy : hint_range(0.0, 16.0) = 0.0;
uniform float vertex_shade : hint_range(0.0, 1.0) = 0.0;
// Roughness of a tinted (glazed) surface; only used where item_tint.a > 0.
uniform float glaze_roughness : hint_range(0.0, 1.0) = 0.45;

instance uniform vec4 item_tint = vec4(0.0, 0.0, 0.0, 0.0);

void fragment() {
	float tint = clamp(item_tint.a, 0.0, 1.0);
	vec3 colour = texture(palette_atlas, UV2).rgb;
	if (tint > 0.0) {
		colour = mix(colour, item_tint.rgb, tint);
	}
	ALBEDO = colour * mix(vec3(1.0), COLOR.rgb, vertex_shade);
	ROUGHNESS = mix(roughness, glaze_roughness, tint);
	SPECULAR = specular_amount;
	EMISSION = colour * emission_energy * step(emission_from_v, UV2.y);
}
