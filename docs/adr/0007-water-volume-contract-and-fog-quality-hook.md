# ADR 0007: Water volume contract, single fog settings place and depth tint pass

- Status: Accepted (accepted when the #23 pull request merges; gated by `needs:owner`)
- Date: 2026-11-09; Amendment 1 (#126): 2026-11-10
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
   Amendment 1 adds `Caustics` below `DepthTint` (full order: Caustics -3, DepthTint -2,
   Surface -1, Glass 0).

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

## Amendment 1 (#126, B12b caustics)

- Status: Proposed, same gate as the ADR (`needs:owner` on the #126 pull request). No row of the
  decisions table changes; rules 1 to 4 above stay in force.

### Context

#126 adds caustics: a slow generated light pattern on the surfaces under the lamp, inside the water
only, clipped by the lamp cone and range, with three values (`caustic_intensity`,
`caustic_speed`, `caustic_scale`) in one place. The BA decisions on #126 forbid a texture asset
and a screen-texture read, require intensity 0 or no lamp to hide the effect at no cost, and leave
the technique and the draw order to the architect.

### Decision

5. **Caustics node.** `Caustics` is the fourth child of `WaterVolume`: a `MeshInstance3D` with the
   script `TankCaustics` (`game/scenes/tank/tank_caustics.gd`), a `BoxMesh` the size of the water
   volume (identity transform, sized by `TankWater.build()` like `DepthTint`), material
   `game/assets/tank/materials/caustics.tres`, shader `game/shaders/caustics.gdshader`, no shadow.
   The node bounds are the water bounds; the lamp cone and range are clipped in the shader.
6. **Technique: depth-reading box, no texture.** Like `DepthTint`, the box draws its back faces
   with the depth test off and reads only the depth texture (`hint_depth_texture`). Per pixel it
   rebuilds the opaque surface point in the `WaterVolume` frame and its normal from neighbouring
   depth samples, and keeps only points inside the water box. The pattern is generated in the
   shader (animated cellular noise, periodic in time), projected along the lamp axis in the
   `WaterVolume` frame, so it is anchored to the tank and does not move with the camera. The weight
   is up-facing x depth below the water surface along the lamp axis x soft spot cone x soft range.
   The result brightens what is already drawn (`blend_mul` with a factor of 1 plus the caustic
   light), so dark or shaded surfaces get proportionally less. No screen texture, no normal-
   roughness buffer, no image file, no extra light, no Decal and no viewport.
7. **Draw order.** `caustics.tres` has `render_priority = -3`: under `DepthTint` (-2), `Surface`
   (-1) and `Glass` (0), so the player always sees the caustics through them.
8. **Lamp data by value.** The room owns the lamp. After it places the lamp it calls
   `TankWater.set_key_light(light: SpotLight3D)` (null when there is no lamp or no `KeyLight`);
   `TankWater` passes it to `TankCaustics`, which copies position, direction, `spot_angle` and
   `spot_range` into the `WaterVolume` frame as instance shader parameters and keeps no reference
   to the light. A tank, cabinet or lamp swap frees the tank with its `Caustics` and builds a new
   one, as for the other water nodes.
9. **One caustic settings place.** The three caustic values are named properties of a separate
   resource `WaterCausticSettings` (`game/scenes/tank/water_caustic_settings.gd` and `.tres`),
   not of `WaterFogSettings`: fog and caustics change for different reasons, and the fog
   `applied` signal also re-applies process-wide froxel globals. `apply()` clamps (one warning
   when anything was out of range) and emits `applied`; only the displayed `TankCaustics` listens.
   The values reach the shader as instance shader parameters, so `caustics.tres` and the tank
   scenes hold no copy. A quality level (#81) writes this resource and calls `apply()`.
10. **Off costs nothing.** `caustic_intensity` 0, no lamp, or an unbuilt water volume sets
    `Caustics.visible = false`, so the box is not drawn at all.

### Alternatives considered

- **Decal fed by a generated texture.** An animated pattern needs a `SubViewport` render per frame
  (an extra pass and a texture), and a Decal cannot clip by the lamp cone or by the water box
  exactly. Rejected.
- **Projector texture on a second SpotLight3D.** Needs a texture, lights the cabinet, frame and
  room inside the cone unless every mesh gets cull layers, and doubles the lamp cost. Rejected.
- **Caustic code in every substrate, decor and plant material.** Touches every material and every
  later asset issue; no single node to hide. Rejected.
- **Normal-roughness buffer for the normal.** Exact normals, but it is a screen buffer read that
  the BA decision keeps out; the depth-neighbour normal is enough for a faint effect. Rejected for
  #126; may be revisited with a measurement.
- **Extend `WaterFogSettings`.** Fewer files, but couples two effects and makes a caustic change
  re-apply the froxel globals. Rejected.

### Consequences

- The transparent order is Caustics -3, DepthTint -2, Surface -1, Glass 0; a later water pass picks
  a free value and amends this ADR.
- #45 reuses `Caustics`, `TankCaustics` and `WaterCausticSettings` for the camera inside the water;
  the shader has no camera-position logic.
- Glass panes are transparent and not in the depth buffer, so they receive no caustics; only opaque
  surfaces inside the water box do (substrate, decor, plants, fish, the AC10 stand-in strip).
- Known limit: no shadow-map occlusion, so a caustic may show under an overhang the lamp shades;
  the multiply blend keeps it weaker there.
