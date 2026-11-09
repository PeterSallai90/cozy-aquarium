// Shared water functions (#23, ADR 0007 rule 3; reused by B12b caustics, #126).
// No uniforms live here: every value is a named parameter of the shader that includes this file.
//
// Units: metres. All functions work in the local frame of a box centred on the origin, which is
// the WaterVolume frame (scale one), so local distances are metres.

#define WATER_NO_HIT vec2(1.0e20, -1.0e20)

// Ray against the box [-half_size, half_size]. Returns (t_entry, t_exit) along the normalised
// direction. The entry is clamped to the ray origin (t >= 0), so a camera inside the water (#45)
// gets entry 0. No hit gives t_entry > t_exit.
vec2 water_ray_box(vec3 origin, vec3 direction, vec3 half_size) {
	vec3 side = step(vec3(0.0), direction) * 2.0 - 1.0;
	vec3 inv_dir = 1.0 / (side * max(abs(direction), vec3(1.0e-6)));
	vec3 t_low = (-half_size - origin) * inv_dir;
	vec3 t_high = (half_size - origin) * inv_dir;
	vec3 t_min = min(t_low, t_high);
	vec3 t_max = max(t_low, t_high);
	float t_entry = max(max(t_min.x, t_min.y), t_min.z);
	float t_exit = min(min(t_max.x, t_max.y), t_max.z);
	if (t_exit < max(t_entry, 0.0)) {
		return WATER_NO_HIT;
	}
	return vec2(max(t_entry, 0.0), t_exit);
}

// Path length through the water: from the clamped entry to the nearer of the box exit and the
// opaque scene depth along the same ray. An opaque object in front of the water gives 0.
float water_path_length(vec2 entry_exit, float scene_distance) {
	float t_end = min(entry_exit.y, scene_distance);
	return max(t_end - entry_exit.x, 0.0);
}

// Beer-Lambert absorption, 0 (no path) to 1 (opaque water).
float water_absorption(float path_m, float absorption_per_m) {
	return 1.0 - exp(-max(absorption_per_m, 0.0) * max(path_m, 0.0));
}

// Per-channel transmittance of clear water over a path. tint_linear is the colour that light keeps
// after travelling reference_m through the water at full strength; strength scales the effect
// (0 = colourless water, 1 = full tint at the reference distance). Red falls first, so the result
// shifts to blue-green with distance.
vec3 water_transmittance(vec3 tint_linear, float strength, float path_m, float reference_m) {
	vec3 keep = clamp(tint_linear, vec3(0.001), vec3(1.0));
	float exponent = clamp(strength, 0.0, 1.0) * max(path_m, 0.0) / max(reference_m, 0.001);
	return pow(keep, vec3(exponent));
}

// Distance from a local x/z point to the nearest wall of a box with the given full x/z size.
// Negative outside the box.
float water_distance_to_wall(vec2 local_xz, vec2 size_xz) {
	vec2 to_wall = size_xz * 0.5 - abs(local_xz);
	return min(to_wall.x, to_wall.y);
}
