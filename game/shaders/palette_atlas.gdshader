// Opaque shader for assets coloured by the shared palette atlas (#22; docs/art-style.md,
// "Generator conventions"). The base colour comes from the atlas through UV2 (glTF TEXCOORD_1):
// every face points at the centre of one atlas cell, so a nearest filter reads exactly one texel.
// Back faces are culled, which makes the single-sided room walls vanish when seen from outside
// (the dollhouse cut-away of #22). Atlas cells with UV2.y >= emission_from_v glow (the bottom row
// of the atlas, for example the LED diffuser under the lamp bar); 1.0 switches the glow off.
shader_type spatial;
render_mode cull_back;

uniform sampler2D palette_atlas : source_color, filter_nearest, repeat_disable;
uniform float roughness : hint_range(0.0, 1.0) = 0.75;
uniform float specular_amount : hint_range(0.0, 1.0) = 0.5;
uniform float emission_from_v : hint_range(0.0, 1.0) = 1.0;
uniform float emission_energy : hint_range(0.0, 16.0) = 0.0;

void fragment() {
	vec3 colour = texture(palette_atlas, UV2).rgb;
	ALBEDO = colour;
	ROUGHNESS = roughness;
	SPECULAR = specular_amount;
	EMISSION = colour * emission_energy * step(emission_from_v, UV2.y);
}
