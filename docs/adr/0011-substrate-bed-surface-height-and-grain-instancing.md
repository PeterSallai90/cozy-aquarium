# ADR 0011: Substrate bed: surface height (H1), settled baked stones and grain instancing

- Status: Proposed (accepted when the #28 pull request merges; gated by `needs:owner`)
- Date: 2026-11-15 (first draft 2026-11-14, rewritten for the look spike v2 approach)
- Decision log reference: none (no row D1 to D21 changes; D18 is the guard). Changes the meaning
  of item heights and of a flat heightmap in "Model conventions" and the save-format "Units" line
  of docs/architecture.md, without a `format_version` bump. Refines the "Substrate" and
  "Placement" rows of Core systems and the "Triangle budgets" section of docs/art-style.md.
- Issue: #28 (B17 substrate types, real 3D substrate). Owner decisions on #28:
  [6882290813](https://github.com/PeterSallai90/cozy-aquarium/issues/28#issuecomment-6882290813)
  (real 3D layer, real stones for all),
  [6882527863](https://github.com/PeterSallai90/cozy-aquarium/issues/28#issuecomment-6882527863)
  (H1, S1, no split, TAA, depths, enlarged sand; its 150k / 40k caps are replaced),
  [6901003645](https://github.com/PeterSallai90/cozy-aquarium/issues/28#issuecomment-6901003645)
  (look spike v2 approach, new budget, known defects) and
  [6901446126](https://github.com/PeterSallai90/cozy-aquarium/issues/28#issuecomment-6901446126)
  (mid-range class and factor rule, main-thread meaning of "4 ms") and
  [6901857494](https://github.com/PeterSallai90/cozy-aquarium/issues/28#issuecomment-6901857494)
  (mid-range estimate by the RTX 3060 tier, F = 3).
  Inputs: look spike v2
  ([6900725663](https://github.com/PeterSallai90/cozy-aquarium/issues/28#issuecomment-6900725663)),
  research report `docs/research/substrate-rendering.md`, Story v3.2
  ([6901087797](https://github.com/PeterSallai90/cozy-aquarium/issues/28#issuecomment-6901087797)).
  Builds on [ADR 0010](0010-substrate-catalog-defaults-and-load-normalisation.md), which stays
  unchanged.
- Later users: #29 (sculpt and player-chosen depth), #31 and #33 (placement), #34 and #35 (fish),
  #44 and #45 (photo mode), #49 (performance pass), #81 (anti-aliasing setting).

## Context

The first version of #28 drew the substrate as a flat, shaded plane. The owner rejected it: every
type must be a real 3D bed with thickness, made of individual grains or stones, with a fixed depth
per type (3 cm sand and black sand, 4 cm gravel and coloured gravel, 6 cm pebbles). A second
approach (shaded base volume with run-time jittered grains on it) was also rejected after the
preview ("one block with a low quality texture, gravel sprayed on the side").

Look spike v2 then showed an approach the owner approved: stones physically settled offline in
Blender, only the stones that can be seen are built, and a plain dark core behind them reads as
shadow. Sand grains are ray-cast ellipsoids on camera-facing quads, which the owner counts as real
3D. The spike met a budget of about 0.56 M drawn triangles at the default camera and 0.99 M at the
worst close-up, at most 0.37 ms added GPU time on an RX 6800 XT, but built the bed in one blocking
step of up to 0.87 s.

The raised visible floor still means that docs/architecture.md must say where items stand: today
positions are tank-local metres from the inner floor, heightmap values are metres above the tank
floor and an empty heightmap is flat. Items do not exist yet (#31) and no save has shipped.

## Decision

### Surface height and placement

1. **Item height reference (H1).** `PlacedItem.position.y` is the height above the substrate
   surface at the item's (x, z); 0 means "resting on the substrate". x and z keep their meaning
   (tank-local metres from the centre of the inner floor). A substrate change never moves an item
   in the model. The save format, `format_version` (1) and the golden files do not change; only the
   meaning of item y is stated. Rules for rocks bedded into the substrate belong to #31.
2. **Heightmap meaning.** Heightmap values stay absolute: metres above the tank floor (y = 0). An
   empty heightmap means flat at the fill depth of the substrate type, not flat at 0. In #28 the
   heightmap is kept and saved but neither drawn nor read for heights; #29 draws and honours it,
   decides values below 3 cm and flips the pinned test of rule 4.
3. **Fill depth is Mode 1 catalog data.** `SubstrateDefinition.fill_depth_m` holds the fixed depth
   per type. Mode 1 code outside `game/catalog/` reads it only through `SubstrateSurface`
   (rule 4). The Mode 2 field `layer_depth_default_cm` holds the same value times 100 (kept equal
   by a catalog test); no Mode 1 code reads any `layer_depth_*` field. The depth is not saved; a
   player-chosen depth later is an optional save block with a `format_version` bump, and it needs
   either one bake per depth step or another answer (#29), because the beds are poured, not cut.
4. **One source of the surface height.** `game/model/substrate_surface.gd`
   (`class_name SubstrateSurface`, static, no Node, no state):
   - `const MIN_DEPTH_M: float = 0.03`
   - `static func flat_depth(definition: SubstrateDefinition) -> float`: `fill_depth_m`, never
     below `MIN_DEPTH_M`; a null definition logs `push_error("SubstrateSurface: no substrate
     definition")` and returns `MIN_DEPTH_M`.
   - `static func height_at(definition: SubstrateDefinition, heightmap: PackedFloat32Array,
     heightmap_size: Vector2i, interior_size_m: Vector3, x: float, z: float) -> float`: in #28
     returns `flat_depth(definition)` for every input. x and z are clamped to the interior
     rectangle (NaN and infinity included) and never reach the result; the heightmap is ignored on
     purpose, exactly like the renderer. The parameters are the stable contract for #29.
   - `static func absolute_y(definition: SubstrateDefinition, heightmap: PackedFloat32Array,
     heightmap_size: Vector2i, interior_size_m: Vector3, position: Vector3) -> float`:
     `height_at(..., position.x, position.z) + position.y` (the H1 arithmetic).
   Placement, fish swim bottom, photo mode ("2 cm above the substrate surface") and the bed all
   use it. The value is the **nominal (mean) surface** of the drawn bed: the drawn top is a settled
   surface whose single stones may lie up to u above or below it (rule 5). Contact with single
   stones is a #31 / #33 concern.
5. **Measured surfaces.** For a flat bed with S = `flat_depth()`:
   - *Top height field*: per 5 mm cell over the interior, the highest point of any stone, grain or
     core in the cell (stones: transformed LOD0 vertices; sand grains: the analytic top of the
     ellipsoid). Its mean equals S within **T_mean = max(1 mm, 0.25 x median drawn grain)**
     (sand and black sand 1, gravel 1, coloured gravel 1.25, pebbles 5 mm).
   - No stone top lies above S + u, **u = max(1.5 mm, 0.5 x largest drawn grain)** (sand 1.5,
     gravel 3, coloured gravel 3.25, pebbles 16 mm). The top edge along each glass face stays in
     S +- u and its peak-to-peak is at least max(1 mm, 0.5 x median drawn grain).
   - The mean top edge along each glass face (the visible bed depth) equals S within T_mean.

### Bed structure

6. **Shell plus core, no textured block.** Under the `SubstrateAnchor` of a tank the room adds one
   `SubstrateBed` node (named `Substrate`) at run time. The flat `PlaneMesh` floor is removed. A
   bed is:
   - a **shell of real settled stones**: stones at the top and at least two stone layers deep at
     every glass face, touching the glass (outermost point within 1 mm of the inner glass plane);
     pebbles are settled to the full depth;
   - a **plain dark core** behind and under the shell: an opaque, matte box with no texture
     sampler and no per-pixel variation, its colour a fixed dark fraction of the swatch tint, its
     walls never within 2 x median drawn grain of a pane and its top never above S minus the
     median drawn grain, plus a **floor skin** of the same material over the whole interior floor
     that casts the bed shadow (so the lamp-lit cabinet top never shows between or under the
     stones). The core reads only as shadow in the gaps;
   - **drawn forms**: gravel, coloured gravel and pebbles are instanced meshes (`MultiMesh`); sand
     and black sand are ray-cast ellipsoid grains on a two-triangle camera-facing quad, each with
     its own settled position and orientation (owner decision 6901003645: these count as real 3D).
     Beyond the real-grain range near the camera (end of range 0.7 to 1.0 m) a procedural sand
     surface without texture takes over;
   - stones and grains cast no shadow; the core and floor skin do. Stones use the baked exposure as
     their own shadowing.
7. **Offline bake in Blender, committed data.** `tools/blender/bake_substrate.py` (with
   `substrate_sim.py`, `substrate_tiles.py`, `substrate_stones.py`, `substrate_visibility.py` and
   `params/substrate_bake.json`) pours stones as Bullet rigid bodies, headless, Blender 5.2 (the
   exact version and the bake seed are recorded in every output file):
   - **pebbles**: one whole-tank bake per tank size (no tiles, no repetition);
   - **gravel and coloured gravel**: settled tiles, a full-depth ring against the glass plus a thin
     settled top layer, tiles sharing pre-settled seam stones so stones rest on real neighbours
     across borders;
   - **sand** (shared by sand and black sand, which differ only in look values and seed): settled
     ring tiles at the glass and settled top tiles with an edge of at least 5 cm (the 2.5 cm spike
     tiles showed a grid from above);
   - poured to the fixed depth of the type, not cut, so the top is a natural settled surface;
   - an **offline visibility pass** gives every stone the flags *visible from above*, *visible
     through a pane* and *kept behind* (the row behind a visible stone, so a gap shows a darker
     stone, not the core) and an exposure value 0 to 15. Stones without any flag are not written.
   The bake (minutes per type) never runs in CI or a test; the game reads only the committed files.
8. **Baked data format** (`game/assets/substrate/bake/*.bin`, Git LFS, exported through the
   export presets' include filter): little-endian; 4-byte magic `CASB`; `u32` format version
   (`SubstrateBakeData.FORMAT_VERSION = 1`); `u32` byte length of a UTF-8 JSON header; the header
   (type, data-set name, mode `tank` or `tiles`, tank id for pebbles, fill depth, size classes,
   variant half extents and ellipsoid axes, set table with offset and count, tile periods and
   depths, `packing_version`, Blender version, bake seed, bake commands, settling report with
   "all at rest" and the largest final speed); then records of 9 `float32` (36 bytes): x, y, z,
   qx, qy, qz, qw, drawn size, packed integer (bits 0 to 3 variant, bit 4 visible from above,
   bit 5 visible through a pane, bit 6 kept behind, bits 7 to 10 exposure, the rest 0). Each file
   is at most 1 MB and all files together at most 3 MB. Grain meshes with their LOD chains are
   separate `.glb` files, one per stone class.

### Assembly and build

9. **Deterministic assembly.** `SubstrateAssembler.assemble(input, bake, cancel)` is a pure
   static function of a `SubstrateAssemblyInput` (tank id, substrate id, interior size, fill depth,
   grain class, chunk size, tone spreads, packing version, seed) and the read-only
   `SubstrateBakeData`. It returns `SubstrateBedData`: per 5 cm chunk and mesh variant one
   instance buffer (16 floats: 12 transform, 4 custom data: lightness factor, hue shift in turns,
   saturation plus 4 x exposure, random 0..1), the shared sand top tile buffers and their
   placements, and the core size.
   - `SubstrateAssembler.PACKING_VERSION: int = 1`. It changes whenever the output for the same
     input changes on purpose, including every re-bake; each `.bin` header carries the
     `packing_version` it was baked for and must equal the constant.
   - Seed: 32-bit FNV-1a over the UTF-8 bytes of `"<tank_id>|<substrate_id>|<PACKING_VERSION>"`.
     One `RandomNumberGenerator` seeded with it picks, in a fixed row-major order, the tile fill,
     rotation and mirror (no two edge-adjacent top tiles with the same triple), then per stone the
     tint data. No `randi()`, `randf()`, `randomize()` or `hash()` (engine-version dependent).
     The colour is never an input; a swatch change never re-assembles.
   - Buffers are never saved. The output must not depend on the thread, the timing or a cancel.
10. **Worker-thread assembly, main-thread instancing.** "4 ms CPU per frame" is main-thread time
    (owner decision 6901446126):
    - `SubstrateAssemblyJob` runs `assemble` on `WorkerThreadPool`. The worker touches only its
      arguments and new RefCounted data: no Node, no scene tree, no `load()` / `ResourceLoader`,
      no `RenderingServer`, no signals, no shared mutable state. The bake file may be read on the
      worker with `FileAccess` only. The baked data is immutable once loaded and may be read by two
      jobs at once.
    - Cancel: a `SubstrateCancelToken` (bool behind a `Mutex`) is checked at least once per chunk;
      a cancelled job returns null and writes nothing. The main thread polls
      `WorkerThreadPool.is_task_completed()` in `_process` and only then calls
      `wait_for_task_completion()`; it blocks on a running task only in "finish now" and in
      `_exit_tree`.
    - Instancing (MultiMesh creation, buffer upload, nodes) is main-thread work in steps of at most
      3 ms per frame (ceiling 4 ms per frame for poll, instancing and swap together) into a hidden
      view. The shown bed stays visible until the new view is complete; then, in one frame, the new
      view becomes visible with the current tint, the old one is hidden and `bed_swapped` is
      emitted. A new type change cancels the running job and drops the pending view.
    - Views already built in the current tank are kept hidden and swap in within one frame
      ("cached type"). Assembled data is cached per (tank id, substrate id, packing version) for
      the session (LRU, 6 entries), so a return to a tank only re-instances.
    - When no bed is shown yet (session start, load, tank change) the core and floor skin appear at
      once in the current tint and the stones at the swap frame, within 2 s.
    - "Finish now" (`SubstrateBed.finish_pending()`): waits for or runs the assembly on the calling
      thread, instances the rest and swaps in the same call. Headless tests use it; the result is
      byte-identical to the threaded path.
11. **Chunks and LOD.** Square chunks of 5 cm over the floor (each a full-height column); one
    `MultiMeshInstance3D` per chunk and mesh variant, sand top tiles one node per 5 cm cell
    sharing one `MultiMesh` per tile variant. LOD is chosen per chunk from the camera distance to
    the chunk bounds, with per-class switch distances and 5 percent hysteresis (look values), by
    swapping the mesh of the chunk's `MultiMesh`; sand top cells are shown only within the
    real-grain range. At most 800 `MultiMeshInstance3D` nodes per bed in the large tank; the LOD
    update costs at most 0.5 ms main-thread time per frame. Visibility culling is the offline
    flags (rule 7); Godot frustum-culls the chunks.
12. **Materials.** Four shaders in `game/shaders/`: `substrate_stone`, `substrate_sand_grain`,
    `substrate_sand_top`, `substrate_core`. Per-type look values live in one look resource per
    type in `game/assets/substrate/looks/` (materials, LOD distances, sand range, core fraction,
    tone spreads), referenced from the catalog definition. A bed duplicates its materials once and
    sets `substrate_tint` on the copies, so a colour change costs a few parameter writes and
    applies in the same frame; the `.tres` files are never changed at run time. **Exception to the
    shader rules:** only the sand grain shader writes `VERTEX` (the quad turned to the camera) and
    depth (the depth of the grain's front disc, not per pixel: per-pixel depth cost up to 3.7 ms in
    the spike). Stone, sand top and core shaders write neither and sample no texture.
13. **Sand is the only enlarged grain.** Sand and black sand are drawn 1.0 to 2.5 mm (real 0.2 to
    1.0 mm); every other type is drawn within 0.8 x real minimum to 1.2 x real maximum. Real sizes
    stay in the Mode 2 fields and are never set to the drawn ones (owner-accepted).
14. **Anti-aliasing.** TAA is the project default (`rendering/anti_aliasing/quality/use_taa`),
    MSAA 3D and screen-space AA off, no per-scene or per-viewport override. Selectable
    anti-aliasing and a different default are #81.

### Budget and measurement

15. **Budget** (owner decision 6901003645; large tank, 1920 x 1080, TAA, worst type, stand-in D18
    load of rule 16). Raising any ceiling is an owner decision.
    - **Added GPU time at most 1.5 ms on the mid-range class** (binding), at the default camera and
      at every close-up view of rule 17. Until a card of the class is measured, the figure is the
      added time measured on the development GPU (RX 6800 XT) times **F = 3**, so the measured
      added time on the RX 6800 XT must be at most **0.5 ms** in every listed view (default camera
      and the views of rule 17). Derivation of F under "Mid-range factor".
    - At most 0.6 M triangles drawn at the default camera and 1.0 M at each close-up view (sand
      quads count 2 each); no more in the smaller tanks.
    - At most 100,000 unique stones per bed (unique buffer entries; a shared tile buffer counts
      once; sand at most 90,000 unique ring grains plus the shared top tiles).
    - Type or tank change: longest frame at most 33 ms (median of the changes), the new bed within
      2 s, a cached type within one frame, at most 4 ms main-thread assembly and instancing per
      frame.
16. **Stand-in D18 load** (until #49 measures the real scene): in the large tank, 60 instances of
    `assets/fish/proof_fish.glb` scaled to 5 cm body length, at seeded positions (seed 28) at
    x within the interior minus 6 cm, z within the interior minus 5 cm, y 12 to 45 cm, random yaw;
    and 100 `SphereMesh` decor stand-ins (radial segments 32, rings 24), diameter 3 to 8 cm,
    opaque `StandardMaterial3D`, casting shadows, resting on the nominal surface
    (centre y = S + d / 2). Everything static.
17. **Views.** Default camera = the room's default framing (ADRs 0005, 0006). Close-up views, with
    h = S, front glass plane z_f = interior z / 2 and outer face o = z_f + glass thickness (each
    camera looks at the given target):
    - `glass_close_front`: camera (0.1, 0.8 h, o + 0.12), target (0.1, 0.42 h, z_f);
    - `glass_close_back`, `glass_close_left`, `glass_close_right`: the same 12 cm view at the
      back pane (x mirrored) and at the centre of each side pane;
    - `glass_35`: camera (0.1, h + 0.045, o + 0.35), target (0.1, 0.45 h, z_f);
    - `top_35`: camera (0.1, h + 0.35, 0.02), target (0.1, h, -0.03);
    - `top_12`: camera (0.1, h + 0.12, 0.12), target (0.1, h, 0.04);
    - `corner`: camera (-x/2 - 0.22, h + 0.1, o + 0.22), target (-x/2 + 0.06, 0.5 h, z_f - 0.06).
18. **Measurement method.**
    - Headless (CI): the drawn-triangle estimate = the sum over chunks whose bounds intersect the
      camera frustum of instances x triangles of the LOD the chunk's distance selects (sand: top
      cells in range and frustum, 2 per grain); unique stones; flags; shadow settings; node count.
    - Owner machine (`game/tests/measure/substrate_budget_measure.gd`, not headless, vsync off):
      GPU time from `RenderingServer.viewport_get_measured_render_time_gpu`, 600 warm-up frames,
      then 4 alternating pairs of 300-frame blocks bed visible / bed hidden; added time = median
      (visible) minus median (hidden); pairs must agree within 0.02 ms or the run repeats.
      Primitives from the viewport render info (visible pass), visible minus hidden; the headless
      estimate must not be more than 10 percent below it. Hitch: 10 type changes (5 types twice,
      caches cleared) and 3 tank changes, frame times, time to `bed_swapped`, main-thread
      microseconds per frame reported by the bed. The black sand colour check (AC 41) uses the
      same script with screenshots.

### Mid-range factor

The owner defined the mid-range estimate by the **RTX 3060 tier: RTX 3060, RX 5600 XT, RX 5700 XT**
(owner decision 6901857494), with F never below 3 (owner decision 6901446126). The RX 5500 XT is
not part of the tier. Sources, read on 2026-11-15:

- Tom's Hardware, "GPU benchmarks hierarchy" (rasterization, average fps):
  RX 6800 XT 111.8 / 79.6 / 42.2 and RTX 3060 12GB 61.5 / 41.9 / 22.2 at 1080p ultra / 1440p
  ultra / 4K ultra, a ratio of 1.82 to 1.90.
  https://www.tomshardware.com/reviews/gpu-hierarchy,4388.html
- TechPowerUp GPU Database (boost clock, shaders, ROPs, memory):
  RX 6800 XT 2250 MHz, 4608, 128 ROPs, 256-bit 16 Gbps;
  RX 5500 XT 1845 MHz, 1408, 32 ROPs, 128-bit 14 Gbps;
  RX 5600 XT 1560 MHz, 2304, 64 ROPs, 192-bit 12 Gbps;
  RX 5700 XT 1905 MHz, 2560, 64 ROPs, 256-bit 14 Gbps;
  RTX 3060 12 GB 1777 MHz, 3584, 48 ROPs, 192-bit 15 Gbps.
  https://www.techpowerup.com/gpu-specs/ (pages radeon-rx-6800-xt.c3694, radeon-rx-5500-xt.c3468,
  radeon-rx-5600-xt.c3474, radeon-rx-5700-xt.c3339, geforce-rtx-3060-12-gb.c3682)

Ratios RX 6800 XT / card derived from these figures:

| Card | FP32 throughput | Pixel fill | Memory bandwidth | Measured games |
| --- | --- | --- | --- | --- |
| RTX 3060 12 GB | 1.63 | 3.38 | 1.42 | 1.82 to 1.90 |
| RX 5700 XT | 2.13 | 2.36 | 1.14 | not in the source |
| RX 5600 XT | 2.89 | 2.89 | 1.78 | not in the source |
| RX 5500 XT | **3.99** | 4.88 | 2.29 | not in the source |

The worst views are fragment-bound (ray-cast sand, small dense stones), where shader throughput
(FP32) is the best single predictor between RDNA 1 and RDNA 2; the measured RTX 3060 gap (1.82 to
1.90) lies close to its FP32 ratio, not its pixel-fill ratio. The RX 6800 XT also has a 128 MB
cache that the RX 5000 cards lack, which makes the bandwidth ratio an underestimate. The slowest
card of the tier is the RX 5600 XT (FP32 and pixel-fill ratio 2.89); every derived ratio of the
tier is below 3, so the owner's floor applies: **F = 3**. The RX 5500 XT row is kept for reference
only (about 4.0 by FP32). A pixel-fill-bound view on the RTX 3060 could scale by up to about 3.4;
this is a known uncertainty of the estimate, removed only by measuring a card of the tier.

## Measured results

Look spike v2 numbers (RX 6800 XT, large tank, 1080p, TAA, stand-in load, 5 cm chunks; not the
final implementation) are kept here for comparison. The technical-artist replaces them with the
measurement of the implementation before the pull request; the tester can repeat it (AC 34).

| Item | Spike v2 (provisional) | Implementation |
| --- | --- | --- |
| GPU and driver | AMD Radeon RX 6800 XT | to be measured |
| Unique stones, worst type | 93,043 (gravel_natural) | to be measured |
| Triangles drawn, default camera, worst type | 558 k (gravel_natural) | to be measured |
| Triangles drawn, worst close-up | 993 k (gravel_natural, glass 12 cm) | to be measured |
| Added GPU, default camera, worst type | 0.22 ms (gravel_natural) | to be measured |
| Added GPU, worst close-up | 0.37 ms (sand_fine, glass 35 cm) | to be measured |
| Mid-range estimate (x F = 3) | 1.11 ms | to be measured |
| MultiMesh nodes, worst type | 640 (gravel_natural) | to be measured |
| Render-server CPU, worst type | 0.31 ms (gravel_natural) | to be measured |
| Build (one blocking step, GDScript) | 0.87 s (gravel_natural) | to be measured (threaded) |
| Type change: longest frame (median of 10), time to swap | not measured | to be measured |
| Baked data size | 103 to 373 KB per type | to be measured |

## Alternatives considered

- **H2: item y stays absolute.** A type change with another depth would bury items or leave them
  floating, or the substrate command would have to move items. Rejected by the owner.
- **H3: one depth for all types.** Contradicts "more for pebbles". Rejected by the owner.
- **Shaded base volume with run-time jittered grains** (plan v2). Rejected by the owner after the
  preview: reads as a textured block, stones do not rest on each other.
- **Run-time deposition packer for the visible shell** (research option B). No real contacts
  between stones, needs its own collision code and costs more run-time CPU than reading baked
  positions.
- **Pre-merged bed meshes** (research option C). Several MB per tank and type, no per-stone tint
  or LOD.
- **Exact per-pixel depth for sand grains.** Up to 3.7 ms at the 12 cm glass view; rejected for
  the disc depth (rule 12).
- **Textured or parallax sand surface.** Not needed: real grains near the camera, procedural
  surface beyond (no texture, no art-style question).
- **One synchronous build on the main thread.** 0.87 s blocks the frame; chunked main-thread
  assembly alone needs about 3.6 s at 4 ms per frame, over the 2 s limit.
- **10 cm chunks** (160 nodes for gravel). Coarser LOD steps push the worst close-up over 1.0 M
  triangles; 5 cm chunks are what the spike measured.
- **Godot's automatic mesh LOD.** Needs one shared vertex buffer per LOD chain; the authored hull
  LODs do not share vertices.
- **F = 4.0 (the RX 5500 XT as the slow end).** Proposed first; the owner defined the estimate by
  the RTX 3060 tier instead (decision 6901857494).

## Consequences

- Items, fish and the photo camera must ask `SubstrateSurface` for the floor; nothing may assume
  y = 0 is the visible floor. #29, #31, #33, #34, #35, #44 and #45 inherit this.
- A player-chosen depth (#29) needs a bake per depth step or another answer; a new tank size needs
  a pebble bake.
- The water box, fog, caustics (ADR 0007), world input (ADR 0008), the camera solids and pan box
  (ADR 0009) and the default framing (ADRs 0005 and 0006) do not change. Caustics and fog read the
  depth buffer; sand grains provide the depth of their front disc.
- The substrate takes a large share of the frame budget at close range (up to 1.0 M triangles);
  #49 confirms it in the full scene. With F = 3 the spike's worst view (0.37 ms) leaves 0.13 ms of
  headroom against the 0.5 ms limit on the RX 6800 XT; an RX 5500 XT class card is not covered by
  the estimate.
- The tank and cabinet assets do not change: the lamp-lit cabinet top and the bottom pane edge
  still show below and in front of the tank (out of scope of #28).
- TAA changes the look of every frame (softness, ghosting on moving fish and ripples, residual
  shimmer on the finest grains); the owner judges it at PR time.
- Memory: assembled data up to about 6 MB RAM per (tank, type) for gravel, LRU of 6 entries; built
  views of the current tank stay in video memory (about 20 MB for all five types in the large
  tank). Both are reported in the measurement.
