# Substrate rendering research: real 3D sand, gravel and pebbles seen through glass

- Status: research notes for #28 (B17). This is input for the architect, the technical-artist and
  the owner. It is not a decision and not an ADR.
- Date: 2026-11-14
- Scope: real-time rendering of a 3 to 6 cm aquarium substrate bed (sand, black sand, natural
  gravel, coloured gravel, river pebbles) in Godot 4.7.2, Forward+, GDScript only, standard build.
  The bed must look real from the front and sides through the glass (12 to 100 cm) and from above.
- Inputs: issue #28 (owner decisions 6881104623, 6882290813, 6882527863, Story v3.1, domain notes v2,
  technical plan v2, the technical-artist performance spike), `docs/art-style.md`,
  `docs/architecture.md` (D18), the tank catalog in `game/catalog/tanks`, the camera in
  `game/scenes/room/room_corner.gd`.

Estimates in this document are marked "estimate". Counts are computed from the sizes below. GPU
numbers are extrapolated from the one measurement we have (the spike) and must be measured on a
mid-range GPU before a budget is fixed.

---

## 1. Summary

**What failed and why.** The rejected version showed a textured block with a thin skin of 4-triangle
grains. Four things gave it away. The block's side wall filled the whole band behind the glass.
No stone could sit between the block and the glass, because the wall was 0.5 mm inside the glass.
4-triangle grains read as pyramids once they are bigger than about 10 px on screen. And the top
surface was a flat texture with grains bedded into it. Through the glass, the eye reads a bed as
real when it sees stones stacked on stones with dark gaps between them. A painted wall does not
pass that test.

**Recommended direction ("visible shell, hidden dark core").**

1. **Stone types (natural gravel, coloured gravel, pebbles): physically settled pack tiles.**
   - A Blender script drops real stones into small boxes with rigid-body physics and bakes the
     resting transforms into reusable tiles: interior tiles that repeat at the edges, glass tiles
     settled against a wall, and corner tiles.
   - Godot assembles the bed from the tiles at run time, deterministically. It then crops to the
     fill depth and adds per-stone tint variation.
   - Only stones that can be seen are kept: the top 1 to 2 layers and 2 to 3 layers at each glass
     face. A dark, untextured core sits behind and below them. It is only ever seen as shadow
     through the gaps, which is how a real bed looks.
   - Stones get authored LOD meshes with smooth normals (rock-style hard edges allowed on natural
     gravel). Near chunks draw the detailed mesh; far chunks draw a 4 to 8 triangle mesh.
2. **Sand and black sand: the same settled tiles for the band against the glass and the top rim.**
   - The grains are drawn as ray-cast ellipsoid "impostor" grains: a tiny proxy mesh plus a
     fragment shader that draws a perfectly round grain and writes depth. A grain is round at
     26 px on screen as well as at 2 px, at constant cost.
   - The top uses a dense layer of real grains only near the camera (chunked visibility ranges).
     Farther away a fine-grain shader surface with sparse real accent grains and glints takes over.
3. **If sculpting (#29) comes soon,** the top layer can be produced by a deterministic GDScript
   "drop and settle" deposition packer on a heightfield instead of tiles. It handles any sculpted
   base and any fill depth. Tiles stay for the glass bands.

**Budget implication.** The plan v2 caps (150k triangles, 40k instances) cannot buy this look. The
spike proved that: 4-triangle stones reached the cap, and only about 25 % of the gravel top was
visibly covered by stones. Suggested budget (section 9): keep the measured **1.5 ms GPU** cap.
Replace the triangle and instance caps with per-type guides of roughly **300k to 450k triangles
drawn at the worst view and 50k to 130k instances**, to be confirmed by measurement on a
mid-range GPU. A budget change is an owner decision.

---

## 2. Inputs and constraints

### 2.1 Correction: tank floor sizes

The task brief lists the floors as 0.4 x 0.27, 0.6 x 0.35 and 1.0 x 0.52 m. The catalog
(`game/catalog/tanks/*.tres`, `interior_size_m` = width, height, depth) says:

| Tank | Floor (width x depth) | Floor area | Inner height | Floor perimeter |
| --- | --- | --- | --- | --- |
| small `tank_small_1` | 0.40 x 0.25 m | 0.10 m² | 0.27 m | 1.30 m |
| medium `tank_medium_1` | 0.60 x 0.30 m | 0.18 m² | 0.35 m | 1.80 m |
| large `tank_large_1` | 1.00 x 0.40 m | 0.40 m² | 0.52 m | 2.80 m |

0.27 / 0.35 / 0.52 m are the inner heights. All counts below use the large floor of
**1.00 x 0.40 m**. If 1.0 x 0.52 m were meant, multiply the top-layer counts by 1.3.

### 2.2 Bed and grain data (Story v3.1, domain notes v2, plan v2)

| Type | Fill depth | Drawn grain (min / median / max) | Shape | Tint spread |
| --- | --- | --- | --- | --- |
| sand_fine | 3 cm | 1.0 / ~1.5 / 2.5 mm | sub-rounded blobs, aspect 1 to 1.4 | L ±8 %, hue ±3°, few glints |
| sand_black | 3 cm | 1.0 / ~1.5 / 2.5 mm | as sand | L ±8 % dark, ~5 % lighter glints |
| gravel_natural | 4 cm | 2 / ~4 / 6 mm | angular to sub-angular chips, aspect 1 to 1.6 | L ±22 %, hue ±8°, ~5 % outliers |
| gravel_coloured | 4 cm | 3 / ~5 / 6.5 mm | rounded, smooth (coated) | L ±8 %, hue ±3°, no outliers |
| pebbles_river | 6 cm | 12 / ~20 / 32 mm | flat smooth ovals, thickness 0.5 to 0.7 of width | L ±20 %, hue ±10° |

Other fixed requirements: deterministic placement (seeded by tank, type and packing version), the
colour is a runtime parameter (swatch tint, same-frame change), and the bed must reach every glass
face with no gap or base plate. Later (#29 and beyond) the player chooses the fill depth and
sculpts the bed, with gentle slopes (domain notes: deeper at the back, under 8°).

### 2.3 Camera and pixel size

`room_corner.gd` uses a horizontal FOV of 50°. At 1920 px width, one pixel covers about
0.486 mm per metre of distance. The architect's impact analysis gives about 0.6 mm per pixel for
the large tank at the default build camera.

| Grain | 12 cm (glass close-up) | 35 cm | 100 cm | Default camera, large tank |
| --- | --- | --- | --- | --- |
| sand 1.5 mm | ~26 px | ~9 px | ~3 px | ~2.5 px |
| gravel 4 mm | ~69 px | ~24 px | ~8 px | ~7 px |
| coloured gravel 5 mm | ~86 px | ~29 px | ~10 px | ~8 px |
| pebble 20 mm | ~345 px | ~118 px | ~41 px | ~33 px |

Consequences:

- At 12 cm a sand grain is as big on screen as a pebble at the default camera. Any grain that can
  come within about 30 cm of the camera needs a rounded silhouette and smooth shading there.
- At 12 cm the view through the glass is only about 11 x 6 cm. Only a few thousand grains are
  close at any moment. **Distance-based LOD is the main lever.** Almost all the bed is far from
  the camera even in a close-up.
- At the default camera, sand and gravel grains are 2 to 8 px. Shape no longer matters there;
  shading, tint variation and the absence of aliasing do.

### 2.4 Performance facts we have

- Spike (RX 6800 XT, 1080p, TAA, stand-in D18 load): about 35k instances and 144k triangles added
  0.10 to 0.12 ms. The whole frame with the bed hidden was 1.24 ms. GPU time is not the bottleneck
  at that size. The triangle cap was.
- Rough cost model (estimate, linear from the spike): about 0.8 µs per 1k triangles on the
  RX 6800 XT. A mid-range GPU (RX 6600 / RTX 3060 class) is assumed to be about 2.5 to 3 times
  slower, giving about 2 to 2.4 µs per 1k triangles. The 1.5 ms cap would then allow very roughly
  600k to 750k small triangles on a mid-range GPU before per-pixel costs. The model ignores
  per-pixel shading, fixed overheads and the very-small-triangle penalty. Measure it.
- Godot's Forward+ renderer draws opaque geometry twice: a depth prepass, then the colour pass.
  The occlusion-culling docs contrast it with the Mobile renderer, "which has no depth prepass".
  Every shadow-casting light adds more passes. Grains must not cast shadows.
- GDScript packing in the spike: 5.6 to 8 µs per instance for sand and gravel, 10 to 16 µs for
  pebbles.

### 2.5 Project rules that shape the options

- `docs/art-style.md`:
  - no photographic or scanned textures;
  - small textures (≤ 256 x 256) are allowed only as gradient or mask textures;
  - procedural noise is allowed in vertex colours or in the shader;
  - hard edges are allowed on rocks, faceted flat shading on nothing else;
  - colour customization only through shader parameters;
  - `MultiMeshInstance3D` for repeated items.
  - Consequences: photogrammetry textures are out. A baked height or normal texture is a grey zone
    ("mask texture"?) and needs an art-style check.
- CLAUDE.md: assets generated with `tools/blender` scripts where possible. Catalog data in
  `.tres`. The model stays pure data. GdUnit4 tests run **headless**, so anything that only
  exists on the GPU (compute shaders, particles) cannot be checked by the CI tests.
- Plan v2 test constraints. These are plan rules, not project rules; the architect can change
  them, but each change means editing tests:
  - shaders may not assign `VERTEX` and may not sample textures;
  - instance bases must be uniform scale;
  - 4 variants per class with triangle caps 4 / 6 / 8 / 80;
  - base walls 0.5 mm inside the glass, base top within S ± 1 mm;
  - caps of 150k triangles and 40k instances.
  - Several recommended options conflict with these (marked per option).

---

## 3. Why the previous attempt looked wrong (diagnosis)

| Symptom the owner saw | Likely cause | What avoids it |
| --- | --- | --- |
| "One block with a low quality texture" | The base volume's side walls filled the whole 3 to 6 cm band at the glass with a procedural texture. Real grains were only a thin skin. | No textured wall at the glass. Real stones stacked through the whole band; the only non-stone surface is a dark core behind at least two stone layers. |
| Pebbles look 2D | With the wall 0.5 mm inside the glass and "no vertex beyond the glass", only ~0.5 mm of a stone can be in front of the wall. The spike had to use flattened "glass plate" variants. | Remove the wall at the glass. Stones touch the glass with their outermost point and sit in front of one another, as in a real tank. |
| Sand grains look like little pyramids, too large | 4-triangle open caps with flat facets, about 26 px wide at the 12 cm close-up. Drawn size is measured by the longest AABB side of a near-square outline, so each grain covers almost twice the area of a rounder grain of the same size. Also breaks the art-style rule "no faceted flat shading". | Rounded silhouettes near the camera (LOD or ray-cast impostors), radial (spherical) normals so even a low-poly grain shades round, and rounder outlines. |
| Only shading between gravel stones | One stone per cell, bedded at least 40 % into the base: only ~25 % of the gravel top was visibly stone. The rest was base shader. | 1.3 to 2 layers of stones at different heights, resting on each other (settled), so the top is closed by stones. |
| Odd orange/brown stripes below the bed | Not diagnosed. Candidates: triplanar or noise banding on the vertical base walls, z-fighting between base walls and glass or floor, caustics on the vertical walls, the base Voronoi "stones" doubling behind real pebbles. | No large textured vertical surfaces in the recommended design. The core is dark, matte and untextured. Check caustics on vertical surfaces separately. |

Lesson for every option below: **depth cues sell realism through glass.** Those cues are occlusion
between neighbouring stones, dark gaps, contact darkening, an irregular top edge and parallax when
the camera moves. A texture, however detailed, has none of them on a flat wall.

---

## 4. Reference counts for the large tank

Formulae (estimate): surface layer ≈ area / d² for compact grains (more for overlapping layers).
Full volume ≈ bed volume × packing fraction 0.6 / grain volume. Glass band = perimeter 2.8 m ×
fill depth. Front glass only = 1.0 m × fill depth.

| Type | Top, one closed layer | Glass band, per layer, all 4 faces (front only) | Full bed volume | Visible shell (top 1.3 to 2 layers + glass 2 to 3 layers) |
| --- | --- | --- | --- | --- |
| sand 1.5 mm | ~180k to 200k | ~37k (13k) | ~4 million | ~75k glass (2 layers) + top: not affordable as a full layer, see 6.4 |
| gravel 4 mm | ~25k to 32k | ~7.0k (2.5k) | ~290k to 350k | ~55k to 80k |
| coloured gravel 5 mm | ~16k to 21k | ~4.5k (1.6k) | ~150k | ~35k to 55k |
| pebbles 20 x 14 x 8 mm | ~1.6k to 1.9k | ~0.8k (0.28k), stones seen edge-on | ~12k | ~5k (the whole volume is only ~12k) |

Notes:

- **Pebbles are cheap in count.** The whole 6 cm bed is only about 12k stones. Physically settling
  the whole volume is realistic, and dropping invisible interior stones afterwards brings it to
  about 5k.
- **Gravel is the hardest type for geometry.** It needs tens of thousands of stones that are each
  7 px at the default camera and 69 px in a close-up.
- **Sand cannot be a full grain layer everywhere** (4 million in the volume, ~200k on top). It can
  be a full grain layer at the glass (~75k grains in two layers) and near the camera on top
  (~20k to 30k grains in the 30 cm around the camera).

---

## 5. Options

Each option lists how it works, the look from the side and from above, counts for the large tank,
cost, Godot fit, tint and sculpt fit, effort, risks and sources. Effort is a rough estimate in
working days for the agent that owns the files.

### Option A. Physically settled pack tiles (Blender rigid body, baked, instanced)

**How it works**

1. A Blender script (`tools/blender/...`, run headless) generates the stone meshes (4 to 8
   variants per class) and their convex-hull collision shapes.
2. It drops stones of the type's size distribution into a box with rigid-body physics (Bullet)
   until they settle. It then reads the resting transforms (Object > Rigid Body > Bake To
   Keyframes, or read `matrix_world` at the last frame).
3. Tile kinds per class:
   - **interior tiles** that repeat at the edges, for example 4 x 4 cm for gravel, 8 x 8 cm for
     pebbles, 2 x 2 cm for sand. Edge matching is made in two stages: simulate, delete stones near
     the +x / +z edges, copy the stones near the -x / -z edges across as passive colliders, drop new
     stones into the gaps and simulate again. This is the approach of the Houdini Labs Mesh Tiler
     (copy pieces across the opposite edge).
   - **glass tiles**: one side of the box is a wall, so stones settle flat against it with their
     outermost points on the plane.
   - **corner tiles**: two walls.
4. Each tile stores per stone the variant, the transform, its layer (height rank) and a
   "visible from top / from glass" flag. The flag comes from offline ray casts from many top and
   glass directions; stones that are never hit are dropped. This is offline occlusion culling of
   the interior.
5. Tiles are baked to the full maximum depth of the type (gravel 8 cm, pebbles 8 cm, sand 5 cm per
   the Mode 2 ranges). A later player depth then only crops.
6. Stored as compact Godot resources (`PackedFloat32Array` per tile). Size: about 64 bytes per
   stone, so ~1 to 2 MB for all tiles of all classes.
7. At run time (GDScript, deterministic seed), the bed is filled with tiles:
   - random choice among 8 to 16 tiles per kind;
   - rotation by 0/90/180/270° (only 0/180° for non-square tiles);
   - per-stone variant swap within the same size class, which keeps the packing but changes the
     look;
   - per-stone tint custom data;
   - crop to the fill depth (keep the top "cap" layer, drop body stones above the target);
   - write one MultiMesh buffer per chunk and variant.

**Look.**

- *Side through the glass:* the best of all options. Real stones lean on each other and on the
  glass, with natural gaps and stacking, all the way down. Pebbles lie mostly flat with some
  tilted, as physics produces. The top edge is naturally uneven.
- *From above:* a closed, natural stone surface.
- *Risk:* visible tile repetition. A 4 cm period repeats 25 times across the large tank. 8 to 16
  tiles, rotations, variant swaps and tint keep it below notice; stochastic tile choice is the same
  idea as Wang tiles, which need fewer tiles when rotation is allowed. Seams between neighbouring
  tiles can show slight stone overlaps. These are hidden inside opaque stones; a height
  normalisation pass keeps seams from forming ridges.

**Counts (large tank, visible shell).**

| Type | Instances | Triangles, LOD mix (estimate) |
| --- | --- | --- |
| gravel | 55k to 80k | default camera ≈ instances × 5 to 6 (LOD2) ≈ 300k to 450k; a close-up adds ~2k stones at LOD0 (+60k to 80k) |
| coloured gravel | 35k to 55k | ≈ 200k to 330k |
| pebbles | ~5k | LOD0 240 / LOD1 80 / LOD2 24 → ≈ 150k to 300k |
| sand at the glass | ~75k | see Option D |

**Cost**

- *GPU (estimate):* 0.6 to 1.1 ms on a mid-range GPU for gravel at the worst view; lower for the
  other types.
- *CPU at run time:* tile assembly is copy plus one transform multiply per stone, about 1 to 3 µs
  in GDScript, so 60k stones take about 0.1 to 0.2 s. That is inside the 2 s and 4 ms-per-frame
  ceilings with chunked building.
- *Offline:* one Blender bake per class, minutes, committed as data.

**Godot fit.** Excellent. Pure GDScript, MultiMesh buffers, deterministic (the baked data is
fixed; the runtime seed only chooses tiles), and fully testable headless (all data is CPU-side).

**Tint and later depth / sculpting.**

- *Tint:* per-stone custom data plus an instance-uniform swatch tint, as today.
- *Depth:* crop the baked full-depth tiles.
- *Sculpting:* move each stone column by the height difference `h(x,z) - S`. This works for the
  gentle slopes the domain notes allow (under 8°, deeper at the back). Steep sculpted slopes would
  need re-orientation or Option B.

**Effort**

- Technical-artist: Blender tile baker plus stone LODs, about 4 to 6 days.
- Developer or technical-artist: Godot tile assembler, about 2 to 3 days.
- Tests: adapting the plan v2 packer tests.

**Risks**

- Bullet in Blender becomes slow and unstable above a few thousand bodies. One report crashed at
  ~14,000 bodies on Bake; a maintainer comment says Bullet in Blender struggles past about 1,000
  bodies. Mitigation: small tiles of 300 to 1,500 stones each.
- Bullet is unstable with very small objects and the default collision margin. Mitigation:
  simulate at 100x scale (1 unit = 1 cm) and scale down on export. This is common practice; check
  the margins in the script.
- Mirroring tiles needs negative scale, which flips the triangle winding. Avoid it or verify it
  with MultiMesh.
- Conflicts with plan v2: the base walls and base top rules, and possibly uniform scale (no
  conflict if variants are pre-shaped).
- Godot's built-in Jolt physics could do the same settling offline in a headless GDScript tool.
  Jolt is the default for new projects since 4.6. That keeps the pipeline in Godot, but CLAUDE.md
  prefers Blender scripts for asset generation.

**Sources:** Blender rigid body world and tips (bake to keyframes); Blender issue #47971 (14k
bodies); Houdini RBD grains and Labs Mesh Tiler; Substance Designer Physics Scatter (rigid-body
piles baked into tileable maps with Jolt); 80.lv battery-pile workflow; Wang tiles article
(rotation reduces tile count); Godot Jolt docs. Links in section 11.

### Option B. Runtime deposition packer for the visible shell, hidden dark core

**How it works.** A pure GDScript packer (like plan v2's `SubstratePacker`, but physically
plausible) runs a **sequential deposition** ("drop and settle") on a heightfield, in the spirit of
the Visscher-Bolsterli drop-and-roll family of random packing algorithms:

- The bed region gets a height grid at about d/4 resolution: 0.5 mm for gravel, 2 to 4 mm for
  pebbles.
- Each new stone (seeded variant, yaw, size) is placed at a seeded x, z. Its resting height is the
  height that makes its lower profile touch the grid. Optionally it rolls one or two cells
  downhill, and its tilt follows the local slope (pebbles flat side down).
- The stone's upper profile is then written into the grid.
- **Top layer:** deposit over the whole floor onto a core heightfield at S minus about one stone
  height, until the surface reaches S ± u. The top ends up closed by stones at several heights
  instead of a carpet bedded into a plane.
- **Glass bands:** deposit into a thin slab 1.5 to 2 stone diameters wide along each glass, with
  the glass as a hard wall. Stones stack from the floor up and rest on each other and on the
  glass, which gives the stacked rows through the glass.
- **Core:** a plain dark box behind and below the shell (matte, swatch tint × ~0.3, no texture,
  receives light). It is only seen through gaps as shadow, never as a wall.

Full-volume variant for pebbles: deposit the whole 6 cm volume (~12k stones) and drop stones that
cannot be seen. Simple, and the result is a real pebble bed.

**Look.**

- *Side:* close to Option A. Stacking and wall contact are right. Orientations are slightly less
  natural than physics; for example, angular chips do not interlock.
- *From above:* closed, natural.
- *Repetition:* none, because every stone is unique.

**Counts.** As Option A. Gravel 55k to 80k instances; pebbles 5k (shell) or 12k (full).

**Cost**

- *GPU:* as Option A.
- *CPU (estimate):* each stone reads and writes its footprint in the grid. Gravel at a 0.5 mm grid
  is ~64 cells per stone, roughly 15 to 40 µs per stone in GDScript. 60k stones take about 1 to
  2.5 s, which breaks the 2 s ceiling without help.
- *Mitigations:*
  - a coarser grid (1 mm, ~16 cells: about 5 to 10 µs);
  - `WorkerThreadPool` per chunk with a fixed seed per chunk; chunks need a halo or fixed seams
    to stay deterministic;
  - the session cache from plan v2;
  - pre-baking the packer output per tank and type as data, which reduces it to Option A's run
    time cost.

**Godot fit.** Good. Pure GDScript, deterministic, headless-testable. Performance needs care.

**Tint and later depth / sculpting.** Tint is as A. **Best fit for #29**: deposit onto the
sculpted core heightfield directly, any slope and any fill depth. Re-deposit only the edited
region (local rebuild).

**Effort.** About 4 to 7 days developer time (packer, slab logic, performance), plus the stone
meshes from the technical-artist.

**Risks**

- GDScript speed.
- A heightfield cannot represent overhangs: stones under the edge of a tilted pebble. These are
  invisible except at the glass, where the slab logic handles stacking.
- Less natural interlocking than physics for angular gravel.

**Sources:** Visscher-Bolsterli and drop-and-roll packing (arXiv cond-mat/0110373, reduced-dimension
packing cond-mat/0606249); plan v2 section 6 (`WorkerThreadPool` fallback).

### Option C. Pre-modelled (merged) bed meshes and tile meshes with baked inter-stone detail

**How it works**

- Bake settled packs (from A or B) in Blender into **merged meshes**: one mesh per tile or per bed
  section, with the stones joined.
- This allows things instancing cannot do:
  - remove faces that touch or face into other stones (hidden backs and undersides, often 30 to
    50 % of a stone);
  - bake **ambient occlusion per vertex between stones** (contact darkening, the strongest single
    realism cue for piles without shadows);
  - store a per-stone random value in vertex colour or UV2 for tint variation;
  - author LODs per tile.
- The merged tiles are instanced with MultiMesh (instanced pack tiles), or placed as
  MeshInstance3D sections.
- A "photogrammetry-style" variant (scan-like high-poly bed sections with baked maps, no photo
  textures) is possible as source geometry. Scanned geometry is a grey zone under the "no photo or
  scan" rule, which names textures only. The procedural route gives the same result without that
  question.

**Look**

- *Side:* as good as A, plus contact AO, which gives it the most "solid real pile" read of all
  options.
- *From above:* very good.
- *Repetition:* the same issue as A, worse, because per-stone variant swaps are impossible inside
  a merged mesh.

**Counts.** The same triangles as A minus hidden-face removal (about 30 % fewer). Instances drop
from ~60k to a few hundred tiles. Draw calls are low.

**Cost.**

- *GPU:* slightly lower than A (fewer triangles, better vertex reuse).
- *Memory:* higher. Every tile is a unique mesh, ~0.5 to 3 MB per class (estimate).
- *Load:* fast. No per-stone run time work.

**Godot fit.** Good. LOD per tile instance is natural. Godot's automatic LOD (meshoptimizer) on
merged piles of tiny stones simplifies badly (stones merge into blobs), so author the LODs or
disable auto-LOD for these meshes.

**Tint and later depth / sculpting.**

- *Tint:* via vertex-colour random value plus the swatch tint uniform.
- *Fill depth:* needs depth-layered tiles, such as separate meshes per 1 cm layer.
- *Sculpting:* needs vertex displacement in the shader (conflicts with plan v2's "no `VERTEX`
  assignment" rule) or CPU mesh rebuilds. **The weakest fit for #29.**

**Effort.** About 5 to 8 days technical-artist time (bake pipeline, face culling, AO, LOD).

**Risks.** Repetition, sculpt fit, mesh memory, and the art-style scan question if scans are used.

**Sources:** 80.lv rubble and battery-pile workflows; the Godot mesh LOD docs (LOD per node; auto
LOD can break meshes).

### Option D. Ray-cast ellipsoid grains ("impostors") for sand and small gravel

**How it works**

- Each grain is a very small proxy mesh: a camera-facing quad (2 triangles; needs a vertex shader
  billboard) or a **box or octahedron proxy** (8 to 12 triangles, no vertex shader needed).
- The fragment shader intersects the view ray with the grain's ellipsoid in object space. It
  discards pixels that miss, computes the true normal and writes `DEPTH`.
- The result is a mathematically round grain with correct intersections and occlusion against its
  neighbours, at any size on screen. A grain is as round at 26 px as at 2 px.
- Per-instance custom data gives the ellipsoid axes (aspect 1 to 1.4), lightness and hue. A small
  hashed noise can bump the normal so grains are not perfect spheres.
- This is the standard technique for molecular rendering (PyMOL sphere shader, Rerun, the
  "Basic impostor" tutorial). The Michel and Boubekeur multiscale grain renderer (CGF 2020) uses
  sphere-like impostors for the middle range of dense grain piles.

**Look**

- *Side:* round, softly shaded sand grains stacked at the glass. No pyramids, no facets.
  Combined with the settled positions from A or B, the band through the glass reads as real sand.
- *From above:* the same at the near-camera dense layer.
- *Limitations:* the shape is always a smooth ellipsoid, which is fine for sand and coated
  coloured gravel. Natural gravel (angular) and pebbles need real meshes.

**Counts.**

- Sand glass band, 2 layers: ~75k grains. With box proxies: ~75k × 12 = 0.9M triangles, but tiny
  and mostly culled. With quads: ~150k triangles.
- Near-camera top layer: 20k to 30k grains.

**Cost (estimate, must be prototyped)**

- *Vertex load:* low.
- *Pixel load:* writing `DEPTH` turns off early depth rejection for these pixels, so every covered
  pixel is shaded even if it is hidden later.
- *Worst case:* the 12 cm close-up where the grain band fills the screen. Two to three layers of
  overlap × ~2M pixels × a short ray-ellipsoid function is about 0.2 to 0.6 ms on a mid-range GPU.
- *Default camera:* grains are 2 to 3 px and cheap.

**Godot fit**

- Godot spatial shaders can write `DEPTH`; the docs require setting it in every branch once
  written.
- `INSTANCE_CUSTOM` carries per-grain data.
- Box proxies avoid `VERTEX` writes. Quads need a billboard in `vertex()`, which conflicts with the
  plan v2 rule.
- TAA works with it. Discard-based grains get anti-aliased edges over a few frames.

**Tint and later depth / sculpting.** Tint as today. Positions come from A or B, so depth and
sculpt fit are the same as theirs.

**Effort.** About 2 to 4 days technical-artist time for shader, proxy and tests.

**Risks**

- Pixel cost in close-ups.
- Possible interaction with the depth prepass. Check that a material writing `DEPTH` is correct
  in both passes.
- It is a shader trick. If the owner reads "real 3D" as "triangles", explain that each grain is
  a true 3D surface with a correct silhouette and depth, not a texture.

**Sources:** Arcsynthesis "Basic Impostor" tutorial; PyMOL sphere shader; Rerun PR 6508 (discard
disables early-Z); de Poel and Bresser "GPU-based ray casting of quadratic surfaces"; Michel and
Boubekeur 2020 and GrainViewer; Godot spatial shader reference (`DEPTH`, `INSTANCE_CUSTOM`).

### Option E. Shader surface for fine sand (procedural grain, height blend, POM, glints)

**How it works.** The top of the sand bed beyond the near-camera range is a shaded surface:

- **Grain relief:** procedural cellular (Voronoi) height at the grain scale, with grain-sized
  normal perturbation. Journey used a random normal texture drawn from a Gaussian distribution
  around the surface normal, blended into the mesh normal (nlerp), plus soft ripples. Distance
  blending fades the grain normal toward a flat matte look with distance, as the Unreal
  detail-texture docs describe and as real sand appears at 30 to 60 cm (domain notes section 5).
- **Parallax occlusion mapping (POM)** gives the top real-looking depth inside its outline. It
  needs a height field: either procedural (expensive per ray step) or a small baked height texture
  (≤ 256², rendered from the settled grain pack, not from photos).
- **Glints:**
  - Journey layered "ocean specular" plus rare, very bright glitter.
  - Deliot and Belcour (HPG 2023) count the micro-flakes that reflect toward the camera inside each
    pixel footprint. That keeps glints stable, without shimmer, at 1.5 to 5x the speed of earlier
    methods.
  - Kajs et al. (EGVE 2022) render distance-dependent glinty sand in VR: individual glints up
    close, a uniform look far away.
  - Black sand needs its ~5 % lighter glints.
- **Repetition control:** stochastic hex tiling (Mikkelsen's adaptation; an MIT Godot port exists)
  if a texture is used.

**Look**

- *From above, far:* convincing fine sand at 35 to 100 cm, the distance where real grains vanish.
- *Up close and at the glass:* POM breaks at grazing angles (stair-stepping, "swimming") and its
  silhouette stays flat. Seen through the side glass the top edge would be a ruler line. This is
  exactly what the owner rejected, so **E must never be the only representation at the glass or
  near the camera.** It is a far LOD and the "between grains" fill.

**Counts.** Zero instances. The top mesh can be a few thousand triangles.

**Cost.** One full-screen-ish layer of shading. POM with 8 to 32 steps is "very GPU-intensive" when
large on screen (estimate: 0.1 to 0.5 ms at 1080p mid-range when the top fills the screen). Use it
only beyond the near range and with few steps.

**Godot fit.** Fine in a spatial shader. A baked height texture conflicts with plan v2's "no
sampler" test and needs an art-style check (≤ 256² mask texture). Fully procedural height avoids
both but costs more per step.

**Tint and later depth / sculpting.** Tint via uniform. The surface follows any sculpted heightmap
mesh, so it is **the easiest fit for #29**.

**Effort.** About 2 to 4 days technical-artist time (grain normal, distance blend, glints; POM
optional).

**Risks.** Reads as "texture" if seen up close or at the glass; grazing-angle POM artifacts;
shimmering glints without footprint-aware filtering (TAA helps).

**Sources:** GDC 2013 "Sand Rendering in Journey"; Alan Zucconi's Journey sand series; Deliot and
Belcour 2023; Kajs et al. EGVE 2022; Tatarchuk POM (SI3D 2006); UDK POM notes; Unreal detail
texture docs; Godot stochastic hex tiling shader; JCGT hex-tiling paper.

### Option F. Ray-marched "cross-section" slab behind the glass (interior mapping for grains)

**How it works**

- The 3 to 6 cm band at each glass face is a thin box. Its shader ray-marches a procedural 3D field
  of grains (cell-noise spheres or ellipsoids with hashed tint) inside a slab a few grains deep.
- It renders true parallax, occlusion and per-grain shading as the camera moves.
- At the glass the real bed is flat by nature, because grains are pressed against a plane. So the
  classic weakness of parallax techniques, the flat silhouette, does not apply on the glass faces.
  The only silhouette is the top edge, which real grains or impostors (D) along the rim provide.

**Look**

- *Side:* potentially very good for sand: a dense band of round grains with depth and no
  repetition.
- *Stones:* weaker. Packing stones by cell noise does not produce stones resting on stones.
- *From above:* not applicable.

**Counts.** Zero instances for the band. A few dozen triangles.

**Cost (estimate).** Per-pixel. In a 12 cm close-up the band can fill a large part of the screen.
16 to 32 march steps with cell lookups is roughly 0.5 to 1.5 ms on a mid-range GPU. That is a
risk against the 1.5 ms cap. It is cheap at the default camera.

**Godot fit.** Possible in a spatial shader, writing `DEPTH` for correct intersections with fish
and decor. Not headless-testable beyond source scans.

**Tint and later depth / sculpting.** Tint via uniform. Depth and sculpting: the slab height
follows the heightmap along the glass.

**Effort.** About 3 to 6 days technical-artist time. High uncertainty.

**Risks**

- Close-up GPU cost.
- The owner may read it as "a shader, not real grains". It is the closest relative of the rejected
  approach, even if it looks far better.
- Matching its grains to the real grains on top and at the rim.

**Sources:** Inigo Quilez on ray-marched distance fields; Shane's cheap 3D Voronoi for ray marching
(Shadertoy tunnel tutorial); the POM silhouette discussion.

### Option G. Octahedral impostors and billboards for grains or tiles

**How it works.** Pre-render an object from many directions into an atlas and draw a card that
picks and blends the right views (octahedral impostors). Godot 4 addons exist ("Octahedral
Impostor LOD", a reworked "godot-imposter"; the original SIsilicon/wojtekpil addon is Godot 3).

**Assessment.**

- *Per grain:* pointless. A grain is already 4 to 80 triangles; an impostor card costs 2 triangles
  plus a texture atlas (which also breaks the plan's no-sampler rule) and gives worse parallax and
  intersections than Option D.
- *Per pack tile:* wrong parallax at the glass and from above at 12 to 100 cm, because the
  "distant object" assumption does not hold inside a tank.
- Useful only for a much larger, distant scene element. **Not recommended.**

**Sources:** Godot octahedral impostor addons (asset library 5528, SIsilicon repo).

### Option H. GPU particles as static instances; compute-shader placement

**How it works**

- *GPUParticles3D:* a particle process shader can place N grains once, using hash(INDEX) and an
  optional heightmap texture, and keep them static: particle shaders keep their last output, and
  one-shot emission with all particles spawned at once is possible. Draw passes use the grain
  mesh. No CPU packing at all.
- *Compute:* GDScript can run GLSL compute shaders through a local `RenderingDevice` (Forward+ and
  Mobile only). Since Nov 2024, `RenderingServer.multimesh_get_buffer_rd_rid()` exposes the
  MultiMesh GPU buffer, so a compute shader could write grain transforms straight into it.

**Assessment**

- Fast to generate and fits a heightmap (#29).
- Simple per-cell jitter is easy on the GPU. Physically plausible stacking (stones resting on
  stones) is sequential and does not map well to it.
- Particles have no per-instance culling, need a manual visibility AABB, and are harder to keep
  deterministic.
- **Not testable headless.** The CI runs `--headless`, which has no `RenderingDevice`, and
  `multimesh_get_transform` returns a stale CPU copy after GPU writes. All plan v2 packer tests
  would be lost.
- **Not recommended for #28.** Possibly useful later for a large decorative effect such as sand
  puffs.

**Sources:** Godot compute shader docs; forum thread on `multimesh_get_buffer_rd_rid` and the stale
CPU copy; GPUParticles3D docs and the emission-mask forum thread.

### Option I. Dense displaced heightfield mesh

A grid mesh displaced to grain-scale relief cannot make grains. Sand needs about 0.5 mm vertex
spacing: 2,000 x 800 cells ≈ 3.2 million triangles for the large tank, and it still cannot
represent rounded grains or gaps. Godot 4 has no hardware tessellation.

It is the right tool for the **low-frequency shape** of the bed: the core surface and the sculpted
heightmap of #29 at 2 to 5 mm spacing. Other options deposit on it or shade it.

**Not a grain technique.**

### Option J. Virtualized micro-geometry (Nanite-style), for reference

Unreal's Nanite renders very dense geometry with a software rasterizer for tiny triangles. Even
there, forum advice disagrees on whether it suits close-up ground detail, and Nanite displacement
shows close-range artifacts in some versions. Godot 4.7 has nothing equivalent. GDExtension and C++
are out of scope. **Not available**; listed so it is not re-researched.

### Option K. Grain clumps (multi-grain meshes)

The architect's idea. One mesh holds 10 to 30 sand grains, settled in Blender, so there are 10 to
30 times fewer instances for the same triangles. Useful for sparse top accents and for reducing
CPU packing and memory. It does not reduce triangles, and repetition inside clumps can show up
close. **A helper inside A, B or D**, not a method of its own.

---

## 6. Cross-cutting techniques (apply to every option)

### 6.1 Shading that makes small grains read right

- **Radial (spherical) normals** on low-poly grains: each normal points from the grain centre
  outwards. Even a 6 to 8 triangle grain then shades like a round pebble. The silhouette stays
  polygonal, which is invisible below ~10 px. This removes the "pyramid" look at the default
  camera at no cost, and follows the art-style rule against faceted flat shading.
- **Natural gravel** uses split normals on feature edges only (rocks may have hard edges), never
  flat-shaded facets.
- **Contact darkening without shadows:**
  - per-vertex AO baked into each variant (darker underside);
  - a per-instance "burial" factor from the packer (stones lower in the bed or deeper behind the
    glass are darker), carried in custom data;
  - merged-tile AO (Option C);
  - optionally a small-radius SSAO in the environment (screen-space, works at millimetre scale but
    affects the whole scene; tune and measure).
- **Wet look:** domain notes say real beds look slightly darker and more saturated through the
  glass and toward the bottom. That is a per-instance darkening by height, a few percent up to
  15 %.
- **Specular:** keep grains mostly matte (high roughness) to avoid specular shimmer, and add glints
  deliberately (E). Godot's screen-space roughness limiter is on by default and helps.

### 6.2 LOD, chunks and culling in Godot

- **Culling:** MultiMesh instances are never culled one by one. The whole MultiMeshInstance3D is
  drawn or culled by its AABB. The documented workaround is several MultiMeshes for different
  areas, so chunk the bed.
- **Mesh LOD:** chosen **per node** from the AABB point nearest the camera. All instances of a
  MultiMeshInstance3D use the same LOD, so chunks must be small enough (5 to 10 cm) for near and
  far chunks to differ.
- **Auto-LOD (meshoptimizer):** works on MultiMeshInstance3D but cannot simplify a 24-triangle
  stone well. Author the LODs in Blender. `ArrayMesh.add_surface_from_arrays()` takes a `lods`
  dictionary of index arrays, which allows hand-made LOD index sets sharing one vertex array
  (verify in 4.7). The alternative is separate meshes switched by visibility ranges.
- **Visibility ranges (HLOD)** work on MultiMeshInstance3D:
  - they switch a chunk between representations, for example dense near-camera sand grains and
    the shader surface far away;
  - alpha fade ("Self" / "Dependencies") forces transparent rendering during the transition;
  - "Disabled" with hysteresis margins is the cheapest;
  - a dithered fade in the grain shader (hash-based discard by distance) blends well under TAA.
- **Draw calls:** each chunk × variant × LOD is one draw call. Forum measurements show
  MultiMeshes are far cheaper on the CPU than individual MeshInstances. Keep it to a few hundred
  draws. Target: ≤ 200 to 300 active MultiMeshInstance3D nodes per bed. Plan v2 said ≤ 128. With
  LOD bands that may need raising, or use fewer variants per chunk via per-instance shape morphing
  (next bullet).
- **Shape morphing:** one base mesh per class, varied per instance by custom data (squash axes,
  bevel noise) in `vertex()`, gives unlimited variants in one MultiMesh. A forum answer uses
  exactly this to cut MultiMesh counts. It conflicts with the plan v2 rules "no `VERTEX`
  assignment" and "uniform scale"; non-uniform instance scale also needs a check that normals are
  transformed correctly.
- **Occlusion culling** (`OccluderInstance3D`) culls whole nodes by AABB. MultiMeshInstance3D
  cannot be baked as an occluder, and gains are smaller in Forward+ (depth prepass). Not useful
  for grains. Interior culling has to happen in the data (offline flags in A, a shell-only packer
  in B).
- **Camera-side culling:** chunks on the glass faces turned away from the camera can be hidden by
  camera azimuth (architect's idea). This is cheap, but the back glass is visible from above at
  steep angles, so test the camera range.

### 6.3 Anti-aliasing, tiny geometry and shadows

- **TAA** (project default) jitters each frame to capture sub-pixel detail. It is the most
  effective option against specular and shader aliasing. It adds slight blur and ghosting behind
  moving objects, and converges faster at higher frame rates. 2 to 3 px grains will still shimmer
  a little while orbiting (accepted risk R2-Q5). Larger or rounder far LODs and matte shading
  reduce it. MSAA can be added on top of TAA for sharper moving edges. FSR2 at native resolution
  is better but costs more. These are #81 settings.
- **Small triangles:** GPUs shade in 2 x 2 pixel quads, so triangles of 1 to 4 px waste most of
  their shading work. This is the strongest argument for LOD by distance (fewer, larger triangles
  far away) and for impostors (D) at the default camera.
- **Shadows:** grains do not cast shadows. Every directional shadow split redraws all casters, and
  thousands of millimetre stones add little visible shadow. Grains and the core receive shadows
  from fish, decor and rocks. Self-shadowing of the pile comes from baked AO and burial darkening.
- **Overdraw:** a Godot 4.7.2 forum case of 1 million stacked MultiMesh instances at ~50 ms turned
  out to be overdraw. Shell-only packing with interior stones removed keeps overdraw near 1 to 2.

### 6.4 Sand: grain level of detail by distance

Sand is the one type where "every visible grain is real geometry" is unaffordable everywhere
(~200k on top). It is affordable where it matters:

| Region | Representation | Large-tank count (estimate) |
| --- | --- | --- |
| Glass bands (all faces, 2 layers, settled positions) | ellipsoid impostor grains (D), or mesh LOD (near 24 to 32 triangles, far 4 to 6 with radial normals) | ~75k grains |
| Top rim along each glass (silhouette line) | real grains, ~1 cm strip | ~12k grains |
| Top, within ~30 to 35 cm of the camera | dense real grain layer via chunked visibility ranges (5 x 5 cm chunks; only a few visible at once) | ~20k to 30k grains active |
| Top, far | shader surface (E) plus sparse accent grains or clumps (15 to 30 % cover) | ~15k to 40k accents |

Total active grains about 110k to 150k instances. As impostors that is about 220k to 300k quad
triangles, or 0.9M to 1.8M box-proxy triangles, which is still cheap per triangle. As mesh LOD it
is about 350k to 500k triangles.

---

## 7. Shipping aquarium, diorama and archviz references

- **Aquarium games:**
  - Store pages show sculptable, layered substrate as a feature. Fish Game: "25 types of fully
    sculptable substrate, layer-able and in a variety of colors". Fishery: sculptable substrate.
    Aquarium Designer offers substrate choice per a review.
  - None of them publishes how the substrate is rendered. Sculptable and layered substrate
    suggests heightfield meshes with tiled or splatted textures. That is an inference, not
    verified.
  - I found no shipping aquarium title documented to render grain-level 3D substrate through
    glass, so #28 is past the genre baseline.
  - A Unity forum thread on realistic aquariums discusses depth-based effects and fog behind glass,
    not substrate.
- **Diorama and cozy games:** no public write-up was found on how Tiny Glade's pebbles and gravel
  paths are made (procedural, Bevy/WGPU; its "clutter" system is mentioned by fan guides only).
- **Archviz and offline:**
  - 3ds Max Forest Pack sand tutorials use **separate geometry per grain** for close-ups and
    displacement with much higher subdivision for extreme close-ups. The archviz rule is "real
    grains near the camera, surface further away", the same split as 6.4.
  - Substance Designer's Physics Scatter (Jolt) and Blender or Houdini rigid-body piles are the
    standard way to make realistic piles. Usually they are baked to textures; here they are kept as
    instance data.
- **Research:**
  - Meng et al. (SIGGRAPH 2015) keep grains explicit only at the finest scale and switch to
    aggregate light transport for larger scales.
  - Michel and Boubekeur (CGF 2020) render dense grain piles in real time with meshes up close,
    impostors in the middle range and points far away, plus conservative occlusion culling.
  - Both support the multiscale split recommended here.

---

## 8. Comparison

GPU and CPU numbers are estimates for the large tank, worst type of that option, mid-range GPU, to
be measured.

| Option | Side through glass | From above | Instances | Triangles drawn | GPU | CPU / build | Godot 4.7 GDScript fit | Tint swatches | Depth / sculpt (#29) | Effort | Main risk |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **A** Settled pack tiles | Excellent: real stacking to the glass | Very good | gravel 55k to 80k; pebbles ~5k | 150k to 450k by type | 0.4 to 1.1 ms | 0.1 to 0.2 s assembly; offline bake | Excellent, headless-testable | Yes | Depth: crop. Sculpt: column shift, gentle slopes | M (6 to 9 d) | Tile repetition; Bullet small-object setup |
| **B** Runtime deposition shell + dark core | Very good | Very good, no repetition | as A | as A | as A | 1 to 2.5 s unless threaded or cached | Good; speed needs work | Yes | Best: deposit on any heightmap | M to L (5 to 8 d) | GDScript speed |
| **C** Merged tile meshes + baked AO | Excellent, plus contact AO | Very good | few hundred tiles | about 30 % below A | slightly below A | fastest load | Good; author LODs | Yes (vertex id) | Weak: needs vertex displacement or rebuild | M to L (5 to 8 d) | Repetition; sculpt fit; memory |
| **D** Ellipsoid impostor grains | Excellent for sand (round, stacked) | Good near camera | sand ~110k to 150k | 0.2M to 1.8M tiny (proxy type) | 0.2 to 0.6 ms close-up | positions from A or B | Good; `DEPTH` write; box proxy avoids `VERTEX` | Yes | as A or B | S to M (2 to 4 d) | Pixel cost in close-ups; "is it real 3D" perception |
| **E** Sand shader surface (grain normal, POM, glints) | Poor alone (flat edge) | Good far, weak near | 0 | ~few k | 0.1 to 0.5 ms | none | Good; texture would break the no-sampler test | Yes | Best: shades any surface | S to M (2 to 4 d) | Reads as texture up close |
| **F** Ray-marched glass slab | Good for sand; weak for stones | n/a | 0 | tens | 0.5 to 1.5 ms close-up | none | Possible; not testable headless | Yes | Good | M to L (3 to 6 d) | GPU cost; seen as "a shader" |
| G Octahedral impostors | Poor (wrong parallax) | Poor | n/a | low | low | bake | Addons exist | Hard | Poor | M | Not suitable at this distance |
| H GPU particles / compute | as B but no stacking | OK | any | any | low | ~0 | Works on GPU; not headless-testable | Yes | Good | M | CI tests impossible; no physics |
| I Displaced heightfield | Fails for grains | Fails for grains | 0 | millions for sand | high | low | Yes | Yes | Good (as base) | S | Not a grain method |
| J Nanite-style | n/a | n/a | n/a | n/a | n/a | n/a | Not in Godot | n/a | n/a | n/a | Unavailable |
| K Clumps | as host option | as host option | ÷10 to 30 | same | same | lower | Yes | Yes | as host | S | Repetition inside clumps |

---

## 9. Recommendation per substrate type and suggested budget

### 9.1 Common structure (all types)

1. **No textured base block.** The bed is a visible shell of real grains plus a **dark, matte,
   untextured core**. The core sits at least two stone layers behind each glass and at least one
   stone height below the top. Remove the base side walls at the glass; stones touch the glass
   (outermost point on the plane, none beyond).
2. **Positions from physically settled data.** Option A (Blender rigid-body tiles) for the glass
   bands and the top. If #29 needs sculpting before tiles are proven, use Option B for the top.
3. **Chunked LOD.** 5 to 10 cm chunks, authored LOD meshes, smooth or radial normals, grains never
   cast shadows, AO and burial darkening per instance. Dithered transitions under TAA.
4. **Tint unchanged.** Per-stone custom data (lightness, hue, outlier) × an instance-uniform swatch
   tint. Same-frame colour change, no repacking.
5. **Determinism and tests unchanged in spirit.** Baked tile data plus the seeded assembly are
   CPU-side and headless-testable. The plan v2 checks for footprint, glass contact, coverage, size
   ranges and tint statistics carry over, with new definitions for the shell and core.

### 9.2 Per type

| Type | Recommended method | Grain mesh / LODs | Instances (large) | Triangles drawn, worst view (estimate) |
| --- | --- | --- | --- | --- |
| **pebbles_river** | A: settled tiles, full 6 to 8 cm depth baked, invisible interior dropped (or B full-volume deposition) | flat ovals, smooth normals: LOD0 ~200 to 300, LOD1 ~80, LOD2 ~24 | ~5k | 150k to 300k |
| **gravel_natural** | A: settled tiles, shell only (top 1.3 to 2 layers, glass 2 to 3 layers) + dark core | sub-angular chips, split normals on feature edges: LOD0 ~32 to 48, LOD1 ~12 to 16, LOD2 ~5 to 6 | 55k to 80k | 300k to 450k |
| **gravel_coloured** | A, as natural gravel | rounded, radial or smooth normals: LOD0 ~32, LOD1 ~12, LOD2 ~6 | 35k to 55k | 200k to 330k |
| **sand_fine** | A positions at the glass + rim; D impostor grains; dense near-camera top layer via visibility ranges; E shader top far with glints; sparse accents (K clumps optional) | ellipsoid impostor (box proxy) or mesh LOD 24 to 32 / 4 to 6 with radial normals | 110k to 150k | impostor quads ~0.3M, or box proxies up to ~1.8M tiny, or mesh LOD 350k to 500k |
| **sand_black** | as sand_fine; glints stronger in relative terms, average stays dark | as sand | as sand | as sand |

Fallback for sand if D's close-up pixel cost is too high: mesh LOD grains at the glass, and/or
Option F for the band behind the first grain layer.

### 9.3 Suggested budget (for the owner and architect; replaces the 150k / 40k caps)

- **GPU:** keep **≤ 1.5 ms** added at 1080p, TAA, D18 stand-in load. Measure it on a
  **mid-range GPU** as well as the owner's RX 6800 XT. The spike measured only the faster card.
- **Triangles drawn, worst camera (default and 12 cm glass close-up):** guide of ≤ 450k for
  natural gravel and ≤ 350k for the other types. Tie the limit to the measured GPU time rather
  than a fixed count, because impostors and LOD make triangle counts a poor proxy for cost.
- **Instances:** ≤ 150k per bed (sand worst case). Instances mainly cost CPU build time and memory
  (64 bytes each: 150k ≈ 9.6 MB GPU buffer). Keep the 2 s, 33 ms and 4 ms-per-frame build ceilings
  of AC 34, using chunked assembly and the cache.
- **Draw calls:** ≤ ~300 active MultiMeshInstance3D nodes per bed.
- A lean alternative, if a mid-range measurement fails: drop gravel to top 1.3 layers plus glass
  2 layers (~50k instances, ~280k triangles) and sand to one glass layer plus impostors near the
  camera only.

### 9.4 Plan and AC items that would change (for the architect and product-ba)

Base volume walls and base-top tolerance (becomes the core rules), the triangle caps per class and
4 variants per class, the 150k / 40k caps (owner), the AC 27/28 coverage definitions (stone
footprint versus visible cover), the "no `VERTEX` / no sampler" shader scans (only if morphing,
billboards or a sand texture are chosen), uniform scale (only if morphing), the
`substrate_grains.glb` contract (LODs, glass tiles), and a new data asset: the tile resources plus
their Blender baker and licence rows.

### 9.5 Suggested next step

A one to two day **look spike** before the plan is rewritten:

- gravel_natural from Option A tiles (one interior tile set, one glass tile set) with LOD meshes
  and a dark core;
- sand_fine glass band with Option D impostors;
- both rendered at 12 cm, 35 cm, the default camera and from above, with GPU time measured on a
  mid-range card.

The owner judges the renders. Look is a look-and-feel decision, and the budget is the owner's.

---

## 10. Open questions

1. Is a baked height or normal texture (rendered from procedural grains, ≤ 256²) allowed under the
   art-style "mask texture" rule? It decides whether the sand top (E) uses POM.
2. Do ray-cast impostor grains (D) count as "real 3D stones" for the owner? They have true 3D
   silhouettes and depth but are not triangles.
3. Should the instance-shape morphing and billboards be allowed (plan rule "no `VERTEX`
   assignment")? It reduces variants and draw calls.
4. Which mid-range GPU stands in for D18 until #49? The budget must be measured on it.
5. Is a 4 to 8 cm tile repetition acceptable if invisible in renders, or is Option B (no
   repetition) required from the start?

---

## 11. Sources

### Godot

- [Optimization using MultiMeshes (Godot docs)](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html)
- [MultiMesh class reference](https://docs.godotengine.org/en/stable/classes/class_multimesh.html)
- [Visibility ranges (HLOD)](https://docs.godotengine.org/en/stable/tutorials/3d/visibility_ranges.html)
- [Mesh level of detail (LOD)](https://docs.godotengine.org/en/stable/tutorials/3d/mesh_lod.html)
- [Occlusion culling](https://docs.godotengine.org/en/stable/tutorials/3d/occlusion_culling.html)
- [3D antialiasing (4.7)](https://docs.godotengine.org/en/4.7/tutorials/3d/3d_antialiasing.html)
- [Spatial shader reference (DEPTH, INSTANCE_CUSTOM)](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html)
- [ArrayMesh class reference (add_surface_from_arrays, lods)](https://docs.godotengine.org/en/stable/classes/class_arraymesh.html)
- [Using compute shaders](https://docs.godotengine.org/en/4.4/tutorials/shaders/compute_shaders.html)
- [Using Jolt Physics (4.7)](https://docs.godotengine.org/en/4.7/tutorials/physics/using_jolt_physics.html)
- [Animating thousands of fish with MultiMeshInstance3D](https://docs.godotengine.org/en/4.7/tutorials/performance/vertex_animation/animating_thousands_of_fish.html)
- [Godot 4.0 gets global and instance shader uniforms](https://godotengine.org/article/godot-40-gets-global-and-instance-shader-uniforms)
- [Forum: multimesh_get_buffer_rd_rid and compute-written MultiMesh buffers](https://forum.godotengine.org/t/multimesh-instance-get-transform-not-updating-when-buffer-updated-in-compute-shader/116825)
- [Forum: MultiMesh vs RenderingServer instances (4.7.2)](https://forum.godotengine.org/t/multimesh-vs-renderingserver-meshinstances-for-an-extremely-high-number-of-instances/143319)
- [Forum: MultiMesh slow with 1M instances (overdraw)](https://forum.godotengine.org/t/multimesh-has-terrible-performance-with-high-instance-count/143962)
- [Forum: thousands of trees in Godot 4.7 (LOD per MultiMesh)](https://forum.godotengine.org/t/best-approach-for-rendering-a-procedurally-generated-forest-with-thousands-of-trees-in-godot-4-7/141770)
- [Forum: GPUParticles3D emission masks](https://forum.godotengine.org/t/instantiating-gpuparticles3d-using-emission-masks-or-otherwise-avoiding-cpu/127101)
- [Stochastic hex tiling shader for Godot 4 (MIT)](https://godotshaders.com/shader/stochastic-hex-tiling-mikkelsens-adaptation/)
- [Procedural Wang tiling shader for Godot](https://godotshaders.com/shader/procedural-wang-tiling-shader/)
- [Octahedral Impostor LOD (Godot asset library)](https://godotengine.org/asset-library/asset/5528)
- [Godot Octahedral Impostors (SIsilicon)](https://github.com/SIsilicon/Godot-Octahedral-Impostors)

### Sand, glints and granular rendering

- [GDC 2013: Sand Rendering in Journey (John Edwards)](https://gdcvault.com/play/1017742/Sand-Rendering-in)
- [Alan Zucconi: A Journey into Journey's sand shader (series)](https://www.alanzucconi.com/2019/10/08/journey-sand-shader-1/)
- [Alan Zucconi: Journey sand shader part 3 (sand normal)](https://www.alanzucconi.com/2019/10/08/journey-sand-shader-3/)
- [Deliot and Belcour 2023: Real-time rendering of glinty appearances (project page)](https://ggx-research.github.io/publication/2023/06/09/publication-glints.html)
- [Deliot and Belcour 2023 on arXiv](https://arxiv.org/abs/2306.05051)
- [Kajs et al. 2022: Rendering glinty granular materials in VR](https://diglib.eg.org/handle/10.2312/egve20221304)
- [Meng et al. 2015: Multi-scale modeling and rendering of granular materials](https://cs.dartmouth.edu/~wjarosz/publications/meng15granular.html)
- [Michel and Boubekeur 2020: Real-time multiscale rendering of dense dynamic stackings](https://diglib.eg.org/handle/10.1111/cgf14135)
- [GrainViewer (official implementation, MIT)](https://github.com/eliemichel/GrainViewer)
- [Immortal Redneck sand rendering devlog](https://www.moddb.com/news/take-a-look-at-immortal-rednecks-sand-rendering-devlog-4)
- [80.lv: detailed sand with Forest Pack (archviz)](https://80.lv/articles/guide-on-creating-detailed-sand-with-forest-pack)

### Parallax, impostors, small triangles

- [Tatarchuk 2006: Parallax occlusion mapping](https://faculty.digipen.edu/~gherron/references/References/SurfaceDetail/Tatarchuk-POM-SI3D06.pdf)
- [UDK: Parallax occlusion mapping notes](https://docs.unrealengine.com/udk/Three/DevelopmentKitGemsParallaxOccludedMapping.html)
- [Unreal: adding detail textures (distance blend)](https://dev.epicgames.com/documentation/unreal-engine/adding-detail-textures-to-unreal-engine-materials)
- [Arcsynthesis tutorial 13: Basic impostor (ray-cast spheres)](https://nicolbolas.github.io/oldtut/Illumination/Tutorial%2013.html)
- [PyMOL sphere impostor fragment shader](https://sources.debian.org/src/pymol/1.7.2.1-1/data/shaders/sphere.fs)
- [Rerun PR 6508 (sphere impostors, discard and early-Z)](https://github.com/rerun-io/rerun/pull/6508)
- [de Poel and Bresser: GPU-based ray casting of quadratic surfaces](https://mdpal60.net/wiki/_media/portfolio/quadrics/nico_de_poel_jaap_bresser_-_gpu_based_ray-casting_of_quadratic_surfaces.pdf)
- [Inigo Quilez: ray-marching distance fields](https://iquilezles.org/articles/raymarchingdf)
- [Jason Booth: When to make LODs (quad shading cost)](https://medium.com/@jasonbooth_86226/when-to-make-lods-c3109c35b802)
- [Beyond3D: triangle size vs performance](https://forum.beyond3d.com/threads/triangle-size-vs-performance.56073)
- [JCGT 2022: Mikkelsen, practical real-time hex-tiling](https://jcgt.org/published/0011/03/05/paper.pdf)
- [Unreal: Nanite virtualized geometry](https://dev.epicgames.com/documentation/unreal-engine/nanite-virtualized-geometry-in-unreal-engine)
- [Unreal forum: Nanite and close-up ground displacement](https://forums.unrealengine.com/t/displacement-on-landscapes-or-not/231489)

### Physics piles and packing

- [Blender manual: Rigid Body World](https://docs.blender.org/manual/en/latest/physics/rigid_body/world.html)
- [Blender manual: Rigid body tips (bake to keyframes)](https://docs.blender.org/manual/en/latest/physics/rigid_body/tips.html)
- [Blender issue #47971: crash baking ~14,000 rigid bodies](https://projects.blender.org/blender/blender/issues/47971)
- [Houdini: Grains](https://www.sidefx.com/docs/houdini/grains/about.html)
- [SideFX Labs Mesh Tiler](https://sidefxlabs.artstation.com/projects/zOaby4)
- [80.lv: Physics Scatter for Substance 3D Designer](https://80.lv/articles/simulate-physics-right-in-substance-3d-designer-with-this-tool)
- [80.lv: battery pile material with Blender rigid bodies](https://80.lv/articles/creating-batteriy-pile-material-using-blender-substance-3d-tools)
- [Game Developer: seeded exploration of Wang-tiled environments](https://gamedeveloper.com/design/seeded-exploration-of-wang-tiled-environments)
- [arXiv cond-mat/0110373: non-sequentially reorganized hard sphere deposits (Visscher-Bolsterli family)](https://arxiv.org/abs/cond-mat/0110373)
- [arXiv cond-mat/0606249: random packing with large size variations](https://ar5iv.labs.arxiv.org/html/cond-mat/0606249)

### Aquarium and similar games

- [Fish Game (Steam): sculptable, layered substrate](https://store.steampowered.com/app/1372150/Fish_Game/)
- [Fishery (Steam)](https://store.steampowered.com/app/809730/)
- [AQUASCAPING (Steam)](https://store.steampowered.com/app/1339000/AQUASCAPING)
- [Aquascapers (Steam)](https://store.steampowered.com/app/2299400)
- [Destructoid review of Aquarium Designer](https://www.destructoid.com/?p=290954)
- [Unity forum: realistic aquarium](https://discussions.unity.com/t/realistic-aquarium/673643)
