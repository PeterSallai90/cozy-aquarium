// Depth colour tint of the tank water (#23, ADR 0007 rule 3; docs/art-style.md "Depth colour tint").
// Drawn on the back faces of a box the size of the water volume. Each pixel intersects its view ray
// with the water box, ends the path at the opaque scene depth or the box exit, and multiplies what
// lies behind by the Beer-Lambert transmittance of that path: red fades first, so the far side of
// the tank turns slightly blue-green and darker while the front stays true. The tint therefore
// scales with the path length through the water, is zero for objects in front of the glass, works
// with the volumetric fog off and with the camera inside the water (#45). Absorption only: the
// soft scattering haze is the FogVolume's job.
// render_priority -2 (below the water surface and the glass). Reads the depth texture, never the
// screen texture.
shader_type spatial;
render_mode blend_mul, cull_front, unshaded, depth_draw_never, depth_test_disabled,
		shadows_disabled, fog_disabled;

#include "res://shaders/water_common.gdshaderinc"

// Colour that the light keeps after depth_tint_reference_m of water at full strength.
uniform vec4 depth_tint_color : source_color = vec4(0.55, 0.80, 0.85, 1.0);
// 0 = colourless water, 1 = the full tint colour at the reference distance.
uniform float depth_tint_strength : hint_range(0.0, 1.0) = 0.25;
// Path length through the water at which depth_tint_strength is reached, in metres.
uniform float depth_tint_reference_m : hint_range(0.1, 2.0) = 0.35;

// Full water box size in metres, set per tank by TankWater.build().
instance uniform vec3 water_size_m = vec3(0.0);

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;

varying vec3 v_local_position;
varying vec3 v_camera_local;

void vertex() {
	v_local_position = VERTEX;
	v_camera_local = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
}

void fragment() {
	vec3 transmittance = vec3(1.0);
	if (min(min(water_size_m.x, water_size_m.y), water_size_m.z) > 0.0) {
		vec3 direction = normalize(v_local_position - v_camera_local);
		vec2 entry_exit = water_ray_box(v_camera_local, direction, water_size_m * 0.5);
		float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
		vec4 scene_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
		float scene_distance = length(scene_view.xyz / scene_view.w);
		float path_m = water_path_length(entry_exit, scene_distance);
		transmittance = water_transmittance(
				depth_tint_color.rgb, depth_tint_strength, path_m, depth_tint_reference_m);
	}
	ALBEDO = transmittance;
	ALPHA = 1.0;
}
