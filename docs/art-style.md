# Art style guide

## Purpose and status

This is the single source of truth for the art style of Cozy Aquarium: shading, triangle budgets,
colouring, rendering and look, and the quality bar. `CLAUDE.md` and `docs/architecture.md` only
point here.

- The values come from the owner decisions on issue #60. Decision D5 reads "Stylized, cozy, simple
  shapes with rich lighting"; see [ADR 0002](adr/0002-visual-style.md).
- This guide refines the "stylized low-poly" wording in [ADR 0001](adr/0001-engine.md). That ADR
  stays as written, because an ADR records the decision as it was made then.
- Most of the quality comes from lighting and shaders, not from geometry. The budgets below are a
  style limit and a memory limit; the performance target is D18 (see Triangle budgets).

How to read this guide:

- **Rule** is binding. A pull request that breaks a rule is rejected, or the rule is changed first.
- **Guideline** is advice. Deviate when there is a reason and say why in the issue or pull request.
- **hand-made only** marks anything that a Blender script, a mask, vertex colours or a shader
  parameter cannot produce. Every statement without that mark can be met procedurally.
- A rule changes only through an issue. A change to D5 needs a new ADR.

## Shading

- **Rule:** organic shapes (fish, plants, driftwood) use smooth normals.
- **Rule:** hard edges are allowed only on rocks and on furniture (tank frame, cabinet, room
  props). A hard edge means split normals along feature edges (Blender: smooth by angle, or mark
  sharp). It is not the same as faceted flat shading.
- **Rule:** no faceted flat shading on any other asset.
- **Rule:** fins and thin leaves are thin double-sided surfaces (back faces are rendered), so smooth
  normals do not turn them into thick blobs.
- **Guideline:** on fish, spend triangles on the silhouette first (tail and dorsal fin outline),
  then on the head and body curve.

### Species and item readability

- **Rule:** each species issue lists 2 to 3 "must stay recognisable" features (silhouette,
  proportion, colour or pattern). Recognition comes from these, not from triangle count. Examples:
  - neon tetra: iridescent blue-green lateral stripe above a red lower half, about 3.5 cm;
  - betta: long flowing fins, long-fin form with fins about 1.5 to 2 times the body length;
  - guppy: large fan tail on males;
  - angelfish: tall triangular body, trailing fins;
  - corydoras: flat belly, barbels, hugs the bottom;
  - discus: round disc body.
- **Rule:** the model is scaled from the catalog field `adult_length_cm`, never baked to a
  stylized size, and the relative sizes and body proportions between species stay true.
- **Guideline:** cozy exaggeration (slightly larger eyes, a rounder head) is fine.
- **Rule:** decor, hardscape and plants are authored at real size in centimetres, so a rock or a
  piece of wood looks right beside a 3 to 5 cm fish.
- **Rule:** no geometry below the substrate line.

## Triangle budgets

The budget applies to the LOD0 mesh of one catalog item (for a plant that is repeated with a
MultiMesh, one instance or one clump).

| Category | Budget (triangles) | Hero limit (2x the upper end) |
| --- | --- | --- |
| Fish | 800–2,500 | 5,000 |
| Plants | 300–3,000 (MultiMesh where repeated) | 6,000 |
| Rocks and wood | 300–1,500 | 3,000 |
| Hero decor | 2,000–5,000 | 10,000 |
| Tank, cabinet and room | 2,000–10,000 | 20,000 |

- **Rule:** the upper end of a budget is a hard limit. The budgets are upper limits; they are not
  targets.
- **Guideline:** the lower end of a budget is the point below which the shape tends to look
  faceted.
- **Rule:** repeated plants, carpets and grass use `MultiMeshInstance3D`.
- **Rule:** D18 wins over the budgets. D18 is 60 fish and 100 decor items at 60 FPS on a
  mid-range PC. A budget that would break D18 is not accepted.
- **Rule:** the worst-case tank triangle total at the D18 load is "to be measured (#49)". Issue
  #49 records it and confirms or lowers the budgets.
- For orientation only (informal estimate, not a limit): about 0.4 to 0.5 million triangles at the
  D18 load with every item at the top of its range. Real tanks will be much lower.
- **Rule:** a hero piece may use up to 2x its category budget (the hero limit column). The species
  or item issue that introduces it states that it is a hero piece and gives its triangle count.
- **Rule:** there is no fixed per-scene limit on hero pieces. It depends on the tank size; D18
  and #49 remain the performance guard.
- **Rule:** an item that fits no category gets its budget in its own issue, within D18.
- **Guideline:** the budget follows fin and shape detail, not body size. A 3.5 cm tetra needs
  about 800 to 1,200 triangles; long-finned and fancy fish use more.
- **Guideline:** keep Godot's automatic mesh LOD generation on import enabled.

## Colouring

- **Rule:** most models share one palette atlas (a small gradient atlas). It keeps the look
  consistent and the draw-call count low.
- **Rule:** small per-asset gradient or mask textures are allowed. "Small" means at most
  256 x 256 px (512 x 512 px for a hero piece) and at most one gradient texture and one mask
  texture per asset.
- **Rule:** procedural stylized noise is allowed, baked into vertex colours in Blender or computed
  in the shader.
- **Rule:** no photographic textures: no texture derived from photos or scans.
- **Rule:** colour customization works through shader parameters, never through duplicate models.
  Fish colour variants are driven by the catalog field `colour_variants`.
- **Rule:** patterns (stripes, spots, bands) use mask textures or vertex colours, never extra
  geometry.

### Generator conventions

These conventions let a Blender generator script (the first one is issue #21) follow this guide
without further questions.

- **Rule:** faces that use palette colours take their colour from UVs that point into the shared
  palette atlas.
- **Rule:** fish mask texture channels: R = pattern region 1, G = pattern region 2, B = eye
  region (a dark eye with a small highlight). The colour of each region is a shader parameter.
- **Rule:** the vertex colour alpha channel is the fin translucency mask (1 = translucent fin,
  0 = opaque body). One transmission-strength shader parameter serves all species. Plants use the
  same channel for thin leaves.
- **Rule:** 1 Blender unit = 1 m. The model front faces glTF +Z (Blender -Y, Godot
  `Vector3.MODEL_FRONT`); all generators use this one front axis.
- **Rule:** fish are authored at unit body length with the origin at the body centre and scaled at
  runtime from `adult_length_cm`. Decor, plants and hardscape are authored at real size.

### Fish

- **Rule:** the eye is its own mask region (see the B channel above).
- **Guideline:** fins and tail are translucent, the body is not. Translucency is strong on betta,
  guppy, angelfish, fancy goldfish, danio and rasbora tails, and weak or none on opaque fins. Back-lit
  fins are slightly lighter and more saturated.

### Plants

- **Guideline:** yellow-green new growth to deep blue-green, with a few red or bronze species. No
  pure neon green and no uniform colour per plant.
- **Rule:** each plant has a base-to-tip gradient, darker at the base and lighter at the tip.
- **Guideline:** transmission is strong on thin leaves (vallisneria, hornwort, Amazon sword) and
  weak on thick leaves (anubias, java fern).
- **Rule:** ribbon, stem, rosette, carpet and moss plants have distinct silhouettes.

### Hardscape and substrate

These are tint ranges, not fixed colours; the colour tint parameter picks a value inside them.

- **Guideline:** rocks: grey, slate blue-grey, tan sandstone, dark basalt, with crevice darkening
  from vertex colours or procedural noise. Rocks have a clear low-frequency form.
- **Guideline:** driftwood: warm browns from light tan to near-black, with grain from a gradient or
  mask.
- **Guideline:** sand: cream to beige and dark grey. Gravel: a natural brown and grey mix.
- **Guideline:** natural hardscape stays unsaturated. Coloured decor (ruins, ship, ceramic) may be
  more saturated.

## Rendering and look

Each effect is stated in a checkable form: a named technique, its parameters exposed by name as
shader or environment parameters, and a numeric range. The owner fixed the technique but no
numbers, so the numeric range is set in that effect's own area:render issue (to be created).

| Effect | Status | Technique | Named parameters (examples) | Range set in |
| --- | --- | --- | --- | --- |
| Caustics | **Rule**: required | Slow animated projected texture, up-facing surfaces first (substrate, low decor, lower back wall); fades with depth and in shade | `caustic_intensity`, `caustic_speed`, `caustic_scale` | its area:render issue |
| Depth colour tint | **Rule**: required | Slight blue-green shift and loss of contrast and saturation with distance | `depth_tint_color`, `depth_tint_strength` | its area:render issue |
| In-tank fog | **Rule**: required | Volumetric fog limited to the water volume | `fog_density`, `fog_color` | its area:render issue |
| Bloom | **Rule**: required | Environment glow | `glow_intensity`, `glow_threshold` | its area:render issue |
| AgX tonemapping | **Rule**: required | Environment tonemapper set to AgX | `tonemap_exposure`, `tonemap_white` | its area:render issue |
| Light transmission through fins and leaves | **Rule**: required | Back-light and transmission in the material, driven by the translucency mask | `transmission_strength`, `transmission_color` | its area:render issue |
| Bubbles | **Rule**: required | GPU particles that start where bubbles occur in a real tank: an air stone or the filter outflow | `bubble_rate`, `bubble_size`, `bubble_speed` | its area:render issue |
| Floating particles | **Rule**: required | GPU particles drifting in the water column | `particle_density`, `particle_size`, `particle_drift` | its area:render issue |
| God rays | **Rule**: optional | Light shafts from the lamp | `godray_intensity` | its area:render issue |
| Colour-grading LUT | **Rule**: optional | Colour correction through a lookup table | `lut_texture`, `lut_strength` | its area:render issue |
| SSAO | **Rule**: optional | Environment ambient occlusion | `ssao_intensity` | its area:render issue |
| Soft fresnel edge glow | **Rule**: optional, soft and subtle | Fresnel term in the material | `fresnel_strength` | its area:render issue |

- **Rule:** an optional effect may be added, but is not required. The soft fresnel edge glow, if
  used, stays subtle.
- **Rule:** bubbles and floating particles appear only where they do in a real tank: bubbles from
  an air stone or the filter outflow, particles drifting in the water column.
- **Rule:** fish swim through a vertex shader; no skeletal rigs in the MVP.
- **Guideline:** the swim bend grows from an almost still head to the tail; roughly the rear 40
  percent of the body bends most.
- **Guideline:** plant sway is a vertex shader: zero at the root, growing to the tip, about 0.2 to
  0.5 Hz because tank water is calm. Stem plants sway less than ribbon leaves.
- **Guideline:** the caustic cycle is a few seconds. Caustics are softer and more spread than
  ocean caustics, because the surface is calm and shallow.
- **Guideline:** bloom is gentle: glints, lamp and caustic highlights, not haze over the whole
  tank.
- **Guideline:** depth tint is subtle, because a real tank is shallow (typically 30 to 50 cm). It
  must not hide fish colours: a neon tetra stripe stays readable at the back of the largest tank.
- **Guideline:** a warm aquarium lamp from above is the key light. The room is dim and cozy, so
  the tank is the brightest object.
- **Guideline:** the front glass is a thin pane with a slightly green edge tint and soft
  reflections; it belongs to the tank asset.
- **Guideline:** optional effects sit behind the graphics quality setting, so lower settings drop
  them first.
- **Rule:** depth tint, fog and fish colour are named shader or environment parameters only. They
  add no field to the catalog schema.

## Quality bar

- **Rule:** references (Sea of Thieves, Abzû and others) are mood and polish references only. The
  mood board lists its sources and contains no copied assets. No rule in this guide asks to
  imitate a specific game's look.
- **Rule:** the reference mood board (#61) and the golden scene (#62) are follow-up issues. No art
  PR is blocked while they do not exist.
- **Rule:** once the golden scene exists, art changes are compared against it. The code-reviewer
  compares first and escalates to the owner (`needs:owner`) only when necessary.

## Third-party and AI-generated assets

- **Rule:** CC0 packs and AI-generator outputs are adapted in Blender to this guide (budgets,
  shading, palette) before use. The licence row in `docs/asset-licenses.md` is required as before.
- Human-sculpted or AI-generated hero pieces are the only **hand-made only** path.

## Mode 2

No new catalog field, and no visual rule on Mode 2 attributes. Depth tint, fog and fish colour are
shader or environment parameters only, so a future story can reuse them.

## Where the old CLAUDE.md rules went

| Old rule in `CLAUDE.md` | Status | Now in |
| --- | --- | --- |
| Fish swim through a vertex shader; no skeletal rigs in the MVP | Kept unchanged | Rendering and look |
| Colour customization works through shader parameters, never duplicate models | Kept | Colouring |
| One shared palette texture keeps the look consistent and draw calls low | Kept, as the reason for the shared atlas | Colouring |
| The old triangle budgets and the old flat-shading rule | Dropped, replaced | Shading and Triangle budgets |
