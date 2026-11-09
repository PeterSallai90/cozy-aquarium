# ADR 0007: Water volume contract, single fog settings place and depth tint pass

- Status: Proposed (accepted when the #23 pull request merges; gated by `needs:owner`)
- Date: 2026-11-09
- Decision log reference: none (no row in the decisions table changes); refines the "Water
  rendering" row of Core systems in docs/architecture.md
- Issue: #23 (B12a, water and glass shading); used by #126 (B12b caustics), #45 (underwater
  effect), #81 (graphics settings, fog quality levels) and #62 (golden scene)

## Context

#23 adds the first water rendering: a water surface, a glass material, in-tank volumetric fog and
a depth colour tint. Three later issues build on it and must not undo it:

- #126 (B12b) adds caustics as a child of the water volume, clipped to the water bounds, and reuses
  the shared water shader include.
- #45 puts the camera inside the water. Nothing in #23 may assume the camera is outside.
- #81 adds a graphics quality setting. The owner wants fog levels (off, light, medium, quality)
  there, without reworking tank scenes, shaders or tests.

Facts checked on Godot 4.7.2 headless (dummy renderer): shader code is parsed and a bad shader
prints `SHADER ERROR` and `Shader compilation failed`; `Shader.get_shader_uniform_list()` returns
the uniforms with their `hint_range`; `RenderingServer.shader_get_parameter_default()` returns
null; `FogVolume` size, shape and material are settable and readable;
`RenderingServer.environment_set_volumetric_fog_volume_size()` and
`environment_set_volumetric_fog_filter_active()` accept calls but have no getter;
per-instance shader parameters are readable through `get_instance_shader_parameter()`.

## Decision

1. **Water volume contract.** Each tank scene keeps its `WaterVolume` Node3D (script `TankWater`)
   at tank-local `(0, water_line_height_m / 2, 0)` with scale one. Its size comes only from
   `TankDefinition.get_water_volume_size_m()` at runtime; scene values are editor previews. The
   children `Surface` (water surface), `Fog` (FogVolume, box) and `DepthTint` (path-length tint
   box) are sized by `TankWater.build()`, never by scaling `WaterVolume`. B12b adds `Caustics` as
   a fourth child and reads the bounds from `TankWater`. The room calls `build()` on the tank it
   owns before adding it to the tree; no other system references the water nodes.
2. **One fog settings place.** Every fog value that costs performance or changes the look
   (volumetric fog on/off, `FogMaterial.density` and `albedo`, `volumetric_fog_length`,
   `volumetric_fog_detail_spread`, froxel volume size and depth, temporal filter) is a named
   property of one resource, `WaterFogSettings` (`game/scenes/tank/water_fog_settings.tres`).
   `apply()` clamps the values and emits `applied`; the room (environment and RenderingServer
   globals) and the current `TankWater` (its FogVolume) listen and re-apply from the resource.
   Nothing else writes these values at runtime. Values in `room_environment.tres` and the
   preview `FogMaterial` are editor mirrors and must equal the resource defaults (tested). A
   future quality level (#81) changes the resource values and calls `apply()`. Fog off means
   `Environment.volumetric_fog_enabled = false` (density 0 alone still pays the froxel cost).
   The global `Environment.volumetric_fog_density` stays 0: in-tank haze comes only from the
   bounded FogVolume.
3. **Depth tint is its own pass, not fog.** The blue-green shift and contrast loss scale with the
   path length through the water (Beer-Lambert style). A transparent box (`DepthTint`, back faces,
   reads the depth texture) intersects the view ray with the water box analytically, clamps the
   entry to the camera (so it works with the camera inside, #45) and ends at the opaque scene depth
   or the box exit. It works with fog off. The ray-box and absorption functions live in
   `game/shaders/water_common.gdshaderinc`, shared with later water shaders.
4. **Draw order and shadows.** Transparent order is fixed by `render_priority`: `DepthTint` below
   `Surface` below `Glass`. None of them casts shadows. #23 shaders read no screen texture.

## Alternatives considered

- **Tint inside the glass and surface shaders (entry-point tint).** No extra node, but each pane
  must decide whether it is the entry point of the ray, the back pane would tint twice without
  that test, and it breaks when the camera is inside the water (#45). Rejected.
- **Tint carried by the fog.** Fog density at clear-water levels is too low to carry the colour
  shift, and fog off would remove the tint. Rejected (BA decision allows it only if both hold).
- **Global `Environment.volumetric_fog_density`.** Fills the whole room with haze. Rejected (art
  style rule, owner comment on #23).
- **Fog values as constants in the tank scenes or the environment.** Three scenes plus the
  environment would need edits for each quality level. Rejected.

## Consequences

- #81 needs no change in tank scenes, shaders or tests to add fog levels; it writes the resource
  and calls `apply()`.
- #45 can switch or extend the FogVolume and reuse the depth tint without undoing #23.
- B12b has a fixed parent node and bounds API.
- Froxel values have no RenderingServer getter, so tests check them on the resource and by a
  source scan, not on the renderer.
