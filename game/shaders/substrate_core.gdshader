// The hidden core of the substrate bed (#28, ADR 0011 rule 6): a dark, matte, untextured box
// behind the stone shell plus the floor skin. It is only ever seen through the gaps between
// stones, where it reads as shadow; it never touches a glass pane and never forms the top
// surface. One colour: the swatch tint times a dark fraction, no variation per pixel.
shader_type spatial;
render_mode cull_back;

uniform vec4 substrate_tint : source_color = vec4(0.48, 0.42, 0.35, 1.0);
// The dark fraction of the tint.
uniform float core_darkness : hint_range(0.0, 1.0) = 0.1;
// How much direct light the core takes (it sits in the shade of the shell).
uniform float core_light : hint_range(0.0, 1.0) = 0.15;
// How much of the colour of a light the core takes: 1 = all of it, 0 = only its brightness
// (black sand must not turn brown under the warm lamp).
uniform float lamp_tint : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	ALBEDO = substrate_tint.rgb * core_darkness;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	AO = core_light;
	AO_LIGHT_AFFECT = 1.0;
}

void light() {
	vec3 neutral = vec3(dot(LIGHT_COLOR, vec3(0.2126, 0.7152, 0.0722)));
	vec3 colour = mix(neutral, LIGHT_COLOR, lamp_tint);
	DIFFUSE_LIGHT += colour * ATTENUATION * max(dot(NORMAL, LIGHT), 0.0) / PI;
}
