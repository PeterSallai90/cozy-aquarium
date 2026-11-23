# ADR 0013: Fish presentation: species schema, mask RGBA layout, shader contract and derived resting pose

- Status: Accepted (pull request for #34; gated by `needs:owner`)
- Date: 2026-11-21
- Decision log reference: none (no row D1 to D21 changes; D18 is the guard). Fills the
  "Catalog schema (Mode 2 ready)" block and refines the "Fish animation" row of Core systems in
  docs/architecture.md; adds one function to the `SubstrateSurface` contract of ADR 0011 rule 4.
- Issue: #34 (B23 fish catalog with 3 species and swim shader); used by #35 (behaviour), #36 (add
  and remove fish UI), #37 (feeding), #40 (15 species), #49 (performance) and #62 (golden scene)

## Context

#34 brings the first real fish: the `FishSpecies` schema, three species, three generated models
with mask textures, one fish shader and a presentation node. Owner decisions on the issue fix the
look: the eye is a pupil, an iris ring (angelfish only) and a painted highlight dot plus a specular
glint; the neon stripe has a true angle-dependent shimmer; a colour variant is a tint over a body
region marked in the free alpha channel of the fish mask (option A); the story is not split.

These choices are hard to reverse: every species of #40 is authored against the mask layout, every
shipped variant colour is frozen by a snapshot, the parameter names go into docs/art-style.md, and
the save file must never gain a fish position without a format bump. The BA decisions left the
numbers (bands, clearance, zones, bend amplitudes, shimmer threshold, tint blend, draw-call budget)
to the architect.

Facts checked: the save stores only `uid`, `species_id`, `variant`, `nickname` per fish; Godot's
texture importer bleeds colour into transparent texels by default (`process/fix_alpha_border`) and
switches 3D-used textures to VRAM compression by default (`detect_3d/compress_to`); a spatial
shader has one set of render modes, so one material per species means one cull mode for both
surfaces; the #21 proof fish already renders body and fins with one shader under
`cull_disabled, depth_prepass_alpha`; Godot 4.7.2 converts a `Color` instance parameter to linear
before the shader reads it (ADR 0012 Amendment 1, measured in `scenes/dev/item_tint_preview`).

## Decision

1. **Schema.** `FishSpecies` (`game/catalog/fish_species.gd`) follows the schema block of
   docs/architecture.md, plus `scientific_name: String` (Latin binomial, data, never a key, never
   in a `.po` or `.pot` file). Enums start with `UNSET = 0` and are only appended:
   `Zone { UNSET, TOP, MIDDLE, BOTTOM }`, `Temperament { UNSET, PEACEFUL, SEMI_AGGRESSIVE,
   AGGRESSIVE }`, `Light { UNSET, LOW, MODERATE, HIGH }`; every field defaults to its empty value
   so a forgotten field fails the catalog test. `colour_variants` is append-only (a saved fish
   stores `variant` as an index) and guarded by the snapshot test against
   `game/tests/data/colour_variants_frozen.json`. `FishCatalog` (`game/catalog/fish_catalog.gd`)
   mirrors `ItemCatalog`: `load_dir("res://catalog/fish")`, `from_definitions()`,
   `get_definition()`, `get_ids()`, `get_skipped()`.
2. **Species scene.** `FishSpecies.scene` is a wrapper `game/assets/fish/scenes/<id>.tscn` (root
   `Node3D`, identity transform, no script) that instances `game/assets/fish/<id>.glb`. The `.glb`
   import maps both glTF materials (`body`, `fin`) to the one species material
   `game/assets/fish/materials/<id>.tres` through `_subresources` `use_external`, as the decor
   items do. The `.glb` keeps its glTF material flags (`fin` double-sided, `body` single-sided),
   which the model test reads from the glTF JSON.
3. **One shader, one material per species, four instance parameters.** `game/shaders/fish.gdshader`
   with its math in `game/shaders/fish_common.gdshaderinc`; `render_mode cull_disabled,
   depth_prepass_alpha` (the #21 proof setup). Per species (material): the mask, the atlas, region,
   eye, shimmer, fin, bend and surface values. Per fish (`instance uniform`):
   `variant_tint_colour`, `variant_tint_strength`, `swim_phase`, `swim_speed`. Fish do not cast
   shadows (`cast_shadow` off; fish shadows are out of scope).
4. **Mask RGBA layout** (`game/assets/fish/<id>_mask.png`, 256 x 256 px, RGBA8, sampled with UV0):
   - R = pattern region 1, G = pattern region 2: 0..255 coverage, a soft edge of at most 2 texels
     allowed; read with the linear, mipmapped sampler.
   - B = eye bands, written hard: 0 none, 85 pupil, 170 iris ring, 255 painted dot (tolerance 20).
     Read only with `texelFetch` at mip level 0 (nearest texel, never filtered) and decoded as
     `band = int(round(b * 3.0))`, so no filter can turn the edge between two bands into a third.
   - A = tintable body region, written hard: 0 not body, 255 body (tolerance 20); never on an eye
     texel, never on a fin island.
   - The mask is linear data (no `source_color`). Import: `compress/mode=0` (lossless),
     `mipmaps/generate=true`, `process/fix_alpha_border=false`, `process/premult_alpha=false`,
     `detect_3d/compress_to=0`, `process/size_limit=0`, channel remap identity; mip level 0 of the
     imported texture equals the PNG texel for texel.
5. **Shader math** (fixed here; the tester's CPU twin mirrors it, and a test pins the constants in
   the include):
   - Bend, model space, `s = 0.5 - VERTEX.z` (0 at the snout, 1 at the tail base, above 1 on the
     tail fin): `speed = clamp(swim_speed * swim_speed_scale, 0, 1)`,
     `w = smoothstep(0.2, 1.2, s)`, `a = swim_amplitude * mix(0.15, 1.0, speed)`,
     `f = swim_frequency * mix(0.4, 1.0, speed)`,
     `VERTEX.x += a * w * sin(TAU * f * TIME + swim_phase - 4.0 * s)`. Lateral only; the largest
     displacement of a vertex over time is `a * w(s)`.
   - Regions: `c = atlas(UV2)`, `c = mix(c, region_r_colour, m.r)`, `c = mix(c, region_g_colour,
     m.g)`.
   - Variant tint (replace-style): `body = m.a * (1 - eye) * (1 - COLOR.a)`,
     `k = mix(1, clamp(luma(c) / 0.35, 0, 2), variant_tint_keep)`,
     `c = mix(c, tint * k, clamp(variant_tint_strength, 0, 1) * body)`, luma with Rec. 709 weights
     in linear space. Variant 0 has strength 0, so its result is the untinted colour bit for bit.
   - Shimmer: `g = pow(1 - clamp(dot(NORMAL, VIEW), 0, 1), shimmer_power)`,
     `c = mix(c, mix(shimmer_colour_a, shimmer_colour_b, g), clamp(shimmer_strength, 0, 1) * m.r
     * (1 - eye))`.
   - Eye: pupil `eye_colour`, iris `eye_iris_colour`, dot
     `mix(eye_colour, eye_highlight_colour, eye_highlight_strength)` with emission
     `eye_highlight_colour * eye_highlight_strength * 0.3`; glint
     `ROUGHNESS = mix(roughness, 0.1, eye * eye_glint_strength)`,
     `SPECULAR = mix(specular_amount, 1.0, eye * eye_glint_strength)`.
   - Fins: `ALPHA = mix(1, fin_opacity, COLOR.a)`,
     `BACKLIGHT = transmission_color * transmission_strength * COLOR.a`.
   - Order: atlas, regions, tint, shimmer, eye.
6. **Derived resting pose, never stored.** A fish's pose is a pure function of (uid, species
   extents and zone, tank interior, water line, substrate surface). Hash: FNV-1a 32 bit over the
   UTF-8 bytes of `salt + ":" + uid`, divided by 2^32 (`FishHash`). Salts `fish.rest.x`,
   `fish.rest.z`, `fish.rest.y`, `fish.rest.yaw` for the pose and `fish.swim.phase` for the swim
   phase. The phase is not frozen and not saved; #35 derives its frozen personality with its own
   salt and never reuses these. x and z lie in the interior shrunk by the scaled horizontal radius
   plus 1 cm (0 when that range is empty), y comes from the zone helper, yaw is `TAU * unit`.
7. **Zone helper.** `FishZones` (`game/model/fish_zones.gd`, static, pure) gives the origin range
   at a tank-local (x, z) from a surface `Callable` that it calls on every query: column
   `H = water_line - 0.03 - S`, bands of H at 0..0.25 (BOTTOM), 0.25..0.75 (MIDDLE), 0.75..1
   (TOP); lower limit `S + extent_below`, for BOTTOM `S + max(0.01, extent_below) +
   grain_allowance`; upper limit `water_line - extent_above`; a too-small column pins the origin
   to the middle of the feasible span and reports it. The grain allowance is the u of ADR 0011
   rule 5 by grain shape, from the new `SubstrateSurface.top_allowance(definition)` (sand 1.5,
   angular gravel 3, round gravel 3.25, pebbles 16 mm). A BOTTOM fish rests at the lower limit.
8. **Presentation node.** `FishView` (`game/scenes/tank/fish/fish_view.gd`) listens to the model
   directly (`fish_added`, `fish_removed`, `fish_changed`, `tank_changed`, `substrate_changed`,
   `heightmap_changed`, `model_reset`) and repositions synchronously inside the handler. Unlike
   the placed items (ADR 0012 rule 1) it does not wait for the room to push the substrate: it
   resolves the same definitions (`TankCatalog.get_definition`, `SubstrateCatalog.resolve`), so
   the bed and the fish agree. It has no `_process`; the swim is in the vertex shader. The room
   hosts it as a persistent child in the tank frame, like `Placement`.
9. **Draw-call budget.** At most 2 surfaces per fish, each drawn in the depth prepass and the
   transparent colour pass, no shadow pass: at most 4 draw calls per fish, 240 at the D18 load of
   60 fish. #49 measures it in the real scene.

## Alternatives considered

- **Two materials per species (opaque body, transparent fins).** Cheaper body (opaque pipeline,
  SSAO), but two materials per species and two shaders or a duplicated shader; the issue asks for
  one material per species. Kept as the #49 fallback if the transparent body costs too much.
- **Linear filtering for the eye bands.** A filtered edge between pupil (85) and dot (255) reads
  as an iris (170). Two samplers of the same texture or a nearest-filtered B were the options;
  `texelFetch` needs no second uniform.
- **Per-variant atlas row or a plain multiply tint.** The atlas row breaks the
  one-colour-per-variant catalog (owner chose option A); a multiply cannot make the albino
  corydoras lighter than the wild bronze.
- **Stored fish positions.** Forbidden by the save rules without a format bump; a derived pose
  keeps undo, tank change and reload stable.
- **Grain allowance from `grain_scale`.** The ratio of u to the median grain differs by type; the
  table of ADR 0011 rule 5 is the source.

## Consequences

- #40 authors 12 more masks against this layout; a pattern mask for marble or koi, or a
  per-variant eye, is a later extension (new field or variant resource), never a change of
  `colour_variants`.
- The shared fish atlas is 4 x 4 cells; #40 may need a larger layout, under the same half-texel
  inset rule.
- The transparent body sorts per object; overlapping fish of different depth may sort wrong at
  the fin edges. Accepted for Mode 1; #49 decides.
- A change of a formula or constant in rule 5 changes the look and the CPU twin together; it needs
  `needs:owner` and an update of this ADR.
- #29 replaces `SubstrateSurface.height_at` and may refine `top_allowance`; fish code does not
  change.

## Amendment 1 (#35, swimming fish: tail phase and per-frame update)

- Status: Accepted (pull request for #35; gated by `needs:owner`). No row of the decisions table
  changes. Rules 3, 5 and 8 are amended as below; rules 1, 2, 4, 6, 7 and 9 stay in force. The
  design behind it is [ADR 0015](0015-fish-swimming-steering-model-tuning-inputs-and-per-frame-driver.md).
- Date: 2026-11-23
- Sources: #35 acceptance criteria and the BA decisions Q14 and Q15.

### Decision

10. **Rule 3, meaning of `swim_phase`.** The four instance parameters keep their names and types.
    `swim_phase` is now the current tail phase in radians in [0, TAU), advanced by `FishView`
    every frame (ADR 0015 rule 9) and starting at `TAU * FishHash.unit(uid, "fish.swim.phase")`;
    `swim_speed` is `clamp(speed / species top speed, 0, 1)` from the swimming fish, which
    replaces the #34 idle factor 0.35.
11. **Rule 5, bend phase.** The bend becomes `VERTEX.x += a * w * sin(swim_phase - 4.0 * s)`; the
    shader no longer reads `TIME`. `a` and `w` and all constants are unchanged. The frequency
    term `f = swim_frequency * mix(0.4, 1.0, speed)` moves to the CPU, where it advances the
    phase by `TAU * f * delta` per frame. At constant speed the phase is
    `swim_phase0 + TAU * f * t`, so the wave, its amplitude, frequency and shape are exactly the
    #34 look; a speed change bends the phase rate, never the phase, and a paused fish keeps its
    tail pose. `swim_frequency` and `swim_speed_scale` stay species material parameters with the
    same ranges; `FishView` reads them once per species from the material.
12. **Rule 8, per-frame update.** `FishView` keeps its role, its model signals and its child
    structure (one pose node per fish, the species scene as its only child), and gains
    per-frame code: while it has at least one fish node and a tank it processes, steps the
    steering model, writes the pose node transforms and the two swim instance parameters, and
    emits `poses_moved` once per step. A tank, substrate or heightmap change no longer puts the
    fish at their resting poses at once; it starts the recovery ease of ADR 0015 rule 6.
    `model_reset` still rebuilds every fish at its derived resting pose. The read-only contract
    for overlays gains `poses_moved`.
