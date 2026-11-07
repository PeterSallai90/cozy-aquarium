// Pipeline proof only (#21). Not the fish shader: that is #34. Do not reference outside scenes/dev/proof_fish.
// Base colour from the palette atlas through UV2 (glTF TEXCOORD_1); vertex colour alpha is the fin
// translucency mask (0 = opaque body, 1 = translucent fin). Both surfaces share this shader; the fin
// material has the higher render_priority so the body is drawn first.
shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;

uniform sampler2D palette_atlas : source_color, filter_linear, repeat_disable;
uniform float fin_opacity : hint_range(0.0, 1.0) = 0.55;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.6;

void fragment() {
	ALBEDO = texture(palette_atlas, UV2).rgb;
	ALPHA = mix(1.0, fin_opacity, COLOR.a);
	ROUGHNESS = roughness_value;
}
