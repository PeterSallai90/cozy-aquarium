# ADR 0012: Placement system: drawn items, analytic hit test, validity seam and shared item catalog

- Status: Accepted (pull request for #31; gated by `needs:owner`)
- Date: 2026-11-20; Amendment 1 (#32): 2026-11-20; Amendment 2 (#33): 2026-11-21
- Decision log reference: none (no row D1 to D21 changes; D18 is the guard). Refines the
  "Placement" row of Core systems and the Systems layer paragraph of docs/architecture.md.
- Issue: #31 (B20 place, move and rotate items); used by #32 (delete, recolour, undo UI), #33
  (validity rules), #38 (load and autosave), #41 and #42 (more items), #44 and #45 (photo mode)
  and #49 (performance)

## Context

#31 makes placed items visible for the first time and lets the player place, select, move and
rotate them. The model can already hold items (`PlacedItem`, `item_added`, `item_removed`,
`item_changed`), the item browser (#30) emits `item_picked` and `item_pick_cleared`, and the room
(`RoomCorner`) owns the tank node, which it frees and rebuilds on every tank swap and every
`model_reset`. Items stand on the nominal substrate surface (H1, ADR 0011).

Open points handed to the architect: who loads the item catalog and when (#30 AC 23: not at game
start); how placement asks the browser to clear the pick without a reference; where drawn items
live; how the pointer finds the ground and the placed items; the seam for #33; how a held rotate
key becomes one undo step with the `Command` base class unchanged.

Facts checked: an item `.tres` references its scene and its thumbnail as `ext_resource`, so loading
the definitions loads every item scene and thumbnail. `SceneTree` calls `_unhandled_input` from the
last node in tree order to the first. ADR 0009 already chose analytic solids over physics for the
build camera.

## Decision

1. **One placement node under the room.** `Placement` (`PlacementSystem`,
   `game/systems/placement/placement_system.gd`, scene `game/systems/placement/placement.tscn`) is
   a child of `RoomCorner`. It is persistent: a tank swap or a `model_reset` never frees it. Its
   transform is the tank-local frame (origin at the centre of the inner tank floor). The room
   pushes the frame and the bed's substrate to it: `set_tank(definition, origin)` from
   `_show_tank()` before `tank_displayed` is emitted (null definition: no tank, nothing is drawn or
   handled), and `set_substrate(definition)` from `_apply_substrate()` with the same resolved
   definition the bed shows (ADR 0010 fallback included). Placement never listens to
   `substrate_changed` itself, so the drawn items, the ghost plane and the bed always agree.
2. **Drawn items.** `PlacedItems` (`PlacedItemsView`, `game/scenes/tank/items/placed_items_view.gd`)
   is a child of `Placement` and keeps one node per uid, instanced from `ItemDefinition.scene`. It
   creates, frees or updates exactly one node on `item_added`, `item_removed` or `item_changed`,
   rebuilds all in one pass on `model_reset`, and only moves nodes on `set_tank` and
   `set_substrate`. Height is `SubstrateSurface.absolute_y(...)`. An unknown `catalog_id` or a
   definition without a loadable scene draws nothing and logs nothing. The ghost and the drag
   preview (`Ghost`, `ItemGhost`, one reused instance) and the selection mark are never in this
   registry.
3. **Analytic ground point and hit test, no physics.** The pointer ray comes from
   `Viewport.get_camera_3d()` and is moved into the tank-local frame. The ground point is the
   intersection with the plane `y = SubstrateSurface.height_at(...)` (`GroundRay`, pure; parallel,
   from below, behind the camera or not finite gives no point). Selection hit-tests oriented
   boxes: each drawn item stores the local AABB of its visual meshes once at creation, and
   `ItemHitTest` (pure) runs a slab test of the ray in each item's frame; the smallest distance
   wins, ties go to the lower model index. No collision shapes, no physics bodies, no physics
   frame: tests are deterministic and headless, the cost is one O(n) pass per press, nothing per
   frame. #33 checks footprints as oriented rectangles from `footprint_cm` (analytic, no collision
   shapes); photo mode (#45) may reuse the stored bounds.
4. **Validity seam for #33.** `PlacementRules` (`game/model/placement_rules.gd`, pure, no Node)
   answers `allows(model, candidate, before) -> bool` (`before` is null for a placement). The
   commands call it in `do()`; the placement system calls the same method for the ghost and the
   drop, so what is shown and what is committed agree. #31 rule: finite values, centre inside the
   interior rectangle of the model's tank (edges inclusive); a change that keeps the position
   (rotation only) skips the position check, so items of old saves outside the interior can still
   be turned. #33 replaces the body of `allows` and may add constructor arguments (for example the
   item catalog); the commands do not change.
5. **Commands.** `PlaceItemCommand(model, item, rules)` receives the complete `PlacedItem` (uid
   generated when the command is created, Command rule 3), appends it and redoes at the same
   index. `TransformItemCommand(model, uid, position, rotation_y, rules)` stores the instance before
   and after and swaps through `apply_replace_item`; it serves both the drop of a drag (position and
   rotation) and the release of a rotate hold (rotation only). The `Command` base class and
   `CommandHistory` stay unchanged. A hold is merged before any command exists: `RotateHold`
   (`game/systems/placement/rotate_hold.gd`, pure, driven by `step(delta_s)`) keeps the pending
   angle in the view and yields one final angle at the release.
6. **One shared item catalog, loaded on first need.** `ItemCatalogSource`
   (`game/catalog/item_catalog_source.gd`, RefCounted) holds one `ItemCatalog` per session and
   loads it on the first `get_catalog()` call; it counts loads. `main.gd` creates it and hands the
   same instance to `TankControls` (for the browser) and to `RoomCorner` (for placement); this is
   injection of a shared read-only service, like the model, not a reference between systems.
   Placement calls `get_catalog()` only when the model holds an item or a pick arrives, so a start
   with an empty model loads nothing. Scenes and thumbnails load with the definitions; that cost is
   paid on first need, so #30 AC 23 stays as written. A save with items (#38) loads the catalog at
   that moment, which is its first need. If 100 real items make this load hitch (#49), a later
   issue may change how thumbnails are referenced; the source keeps the call sites stable.
7. **EventBus contract.** New signals: `item_pick_clear_requested` (placement asks; the browser
   answers with its existing `clear_pick()`, which emits `item_pick_cleared` once when there was a
   pick), `item_selected(uid: String)` and `item_selection_cleared`. The browser is the only owner
   of the pick; placement mirrors it from `item_picked` and `item_pick_cleared` only. The placement
   system is the only owner of the selection: `item_selected` fires when the selected uid changes
   (also from one item straight to another, with no `item_selection_cleared` between),
   `item_selection_cleared` once when it becomes empty. #32 mirrors the selection from these
   signals; if it ever needs to set the selection, it adds a request signal.
8. **Look resources.** The ghost and the drag preview are the item's own meshes with the ghost
   material as `material_override`; the selection mark is the selection material as
   `material_overlay` on the meshes of the selected drawn item, so it follows every transform
   change of that node. Neither casts shadows, neither changes the environment. Shaders live in
   `game/shaders/`, the two material resources in `game/scenes/tank/items/`.

## Alternatives considered

- **Physics bodies and `intersect_ray` for selection.** Needs a collision shape per item and a
  physics frame before a hit is seen; tests get timing-dependent and 100 bodies cost memory for a
  check that runs once per click.
- **Drawn items under the `Tank` node.** The room frees the tank on every swap and `model_reset`;
  the order of the two `model_reset` handlers would decide whether items survive.
- **Placement as a child of `Main`.** It would need the tank frame from the room through a new
  signal or a reference; the room already pushes the bed its data the same way.
- **Load the item catalog at game start.** Breaks #30 AC 23 and charges every player for items
  they may never open.
- **Merging holds in `CommandHistory`.** Changes the B05 base class, which #16 and Q5 forbid.

## Consequences

- `RoomCorner.setup()` and `TankControls.setup()` gain optional parameters (history, item
  source); `ItemBrowser.setup()` accepts the source. Existing callers keep working.
- #32 reuses the selection signals and adds its own commands next to these two; #33 changes only
  `PlacementRules`; #41 plants with another atlas extend the ghost material; #44 blocks placement
  through `world_input_blockers` (ADR 0008 Amendment 1).
- docs/architecture.md: the Placement row and the Systems paragraph describe this design.

## Amendment 1 (#32, delete, recolour and the drawn tint)

- Status: Accepted (pull request for #32; gated by `needs:owner`). No row of the decisions table
  changes; rules 1 to 8 stay in force.
- Date: 2026-11-20

### Decision

9. **Two more commands.** `DeleteItemCommand(model, uid)` records the instance and its index in
   `do()` and re-inserts that same instance at that index in `undo()` (Command rule 4).
   `RecolourItemCommand(model, uid, has_colour, colour)` swaps in a copy with the new colour state
   through `apply_replace_item` and puts the old instance back on undo; clearing sets
   `has_colour = false` and the `PlacedItem` default colour. Both refuse a missing uid; the
   recolour also refuses a request equal to the current state (`has_colour` equal and, when true,
   equal by `to_rgba32()`). Both are catalog-free like the codec: whether an item may be recoloured
   is checked by the caller.
10. **Placement owns item edits.** Placement runs the delete and the recolour, from the Delete key
    (ADR 0008 Amendment 2 rule 12) and from two EventBus requests the HUD emits:
    `item_delete_requested` and `item_colour_requested(has_colour: bool, colour: Color)`. Both act
    on the current selection only (no uid travels, so a stale HUD never edits another item); the
    recolour also needs `colourable = true` in the item's definition. Deleting the selected item
    clears the selection through the existing `item_removed` handler.
11. **The tint is a per-instance shader parameter.** The decor material
    (`assets/items/materials/decor_palette.tres`) uses `shaders/decor_item.gdshader`, which declares
    `instance uniform vec4 item_tint` (alpha 0: the original look, unchanged; alpha 1: tinted with
    the rgb colour). `PlacedItemsView` sets it with `set_instance_shader_parameter` on every
    `GeometryInstance3D` of a drawn node when the node is created and on `item_changed`, never per
    frame: `Color(colour, 1)` when the definition is colourable and the item has a colour, else
    alpha 0. Mesh and material resources stay shared; no material is created or duplicated per
    colour or per item, so the draw cost does not depend on the number of colours in use.
    `shaders/palette_atlas.gdshader` (room, cabinet, lamp, tank frame) does not change. The ghost
    and the drag preview stay untinted.

### Consequences

- Undo of a tank swap (`ChangeTankCommand`) restores the old tank id, then the heightmap, then
  re-inserts the same item and fish instances at their old indices, so positions, rotations,
  scales and colours come back exactly; placement rules are not consulted. Redo clears them again.
- Later colourable items (#42) only set `colourable` and `colour_swatches` and use the decor
  material; plants with another atlas (#41) declare the same `item_tint` uniform if they are ever
  colourable.

## Amendment 2 (#33, placement validity and the refused rotation)

- Status: Accepted (pull request for #33; gated by `needs:owner`). No row of the decisions table
  changes. Rule 4 is amended by rules 13 and 14 below: its #31 body (centre inside the interior)
  and the `_same_spot` shortcut are replaced. Rules 1 to 3 and 5 to 11 stay in force.
- Date: 2026-11-21
- Sources: #33 acceptance criteria, the BA decisions on review Q1 to Q12, the owner decisions on
  Q6 (option 1b with 2b) and on the height rule.

### Context

#33 gives `PlacementRules.allows` its real body: the oriented footprint inside the interior, no
overlap with other items, the interior height and, for rocks and ornaments, the water line. The
rule needs three things the #31 seam did not have: the item definitions (footprint and category),
the substrate definition of the model and the surface height under the item. The owner chose a
visible cue for a refused rotation of the selected item (Q6, 1b with 2b), which #31 did not have.

### Decision

12. **What the rules are given.** `PlacementRules.new(tanks: TankCatalog, items:
    ItemCatalogSource, substrates: SubstrateCatalog)`. The three are the shared read-only catalog
    services the room already holds. `RoomCorner` creates the rules with the same instances it
    uses itself; it resolves a missing item source to one new `ItemCatalogSource` before it hands
    that one instance to both the rules and `PlacementSystem.setup`, so the bed, the drawn items,
    the ghost and the commands read the same data. Everything else comes from the model passed to
    `allows`: the tank id, the substrate id, the heightmap and the items. The rules keep no state
    between calls, hold no Node and never touch the `EventBus`; `get_catalog()` is called inside
    `allows` only, so the item catalog still loads on first need (rule 6), and the file access of
    that first load stays in the catalog layer. Any of the three missing gives `false`, with no
    log. The substrate definition is `SubstrateCatalog.resolve(id)`: the definition of the id,
    else the default (ADR 0010), else null (then `false`). `RoomCorner._apply_substrate` uses the
    same method, so the rules never judge another bed than the one shown. The surface is
    `SubstrateSurface.height_at(...)` at the item origin (x, z), flat until #29.
13. **The rule.** One tolerance, `PlacementRules.TOLERANCE_M = 0.0001` (0.1 mm), widens every
    limit. The footprint of an item is the rectangle `footprint_cm.x` by `footprint_cm.z`, times
    the item scale, divided by 100, centred on (position.x, position.z) and turned by `rotation_y`
    exactly as the drawn node is turned (`Node3D.rotation.y = deg_to_rad(rotation_y)`): its local
    x axis is (cos a, -sin a) and its local z axis is (sin a, cos a) in (x, z). A candidate is valid
    when all of these hold, checked in this order (cheap first):
    a. every number is finite; the candidate's definition exists; every component of
       `footprint_cm` is above 0 and finite; the scale is above 0 and finite; |position.y| is at
       most the tolerance (in Mode 1 every item rests on the substrate);
    b. bounds: every corner satisfies |x| <= interior.x / 2 + tolerance and
       |z| <= interior.z / 2 + tolerance;
    c. height: top = surface at the origin + `footprint_cm.y` x scale / 100 and
       top <= interior.y + tolerance; for `Category.ROCK` and `Category.ORNAMENT` also
       top <= `water_line_height_m` + tolerance (both limits are absolute heights above the tank
       floor);
    d. overlap: for every model item whose uid is not `before.uid`, the separating axis test on
       the four edge normals of the two rectangles; the pair overlaps only when the penetration
       depth on every one of the four axes is greater than the tolerance, so touching edge to edge
       or corner to corner is valid. A model item blocks nothing when its definition is unknown,
       its footprint or scale fails the checks of (a), or its position or rotation is not finite.
    Cost: one catalog lookup for the candidate and one per other model item in a check that
    passes; a refusal may stop early. No array or object is created per item (scalars only).
14. **Rotation in place replaces `_same_spot`.** `allows(model, candidate, before)` first runs
    rule 13 on the candidate. When that fails, `before` is not null, `candidate.position ==
    before.position` (exact; the placement system passes the model position unchanged) and the
    candidate's rotation is finite, the answer is `true` exactly when `before` itself fails rule 13
    in the current model: an item that is already invalid by any rule may turn to any finite
    angle, so an old save never traps the player. Any change of position, a drag drop with a
    rotation included, gets rule 13 only. Nothing calls the rules on load, `model_reset`, a tank
    swap, a substrate change or an undo or redo of `ChangeTankCommand` (Amendment 1); items are
    never moved, clipped or removed by them.
15. **Refused rotations and refused drops (owner Q6: 1b with 2b; owner decision on refused
    moves).** The placement system asks the same `allows` at three moments; for a and b it passes
    the item's model position, so rule 14 applies:
    a. the press of a rotate key on the selected item: when the first step is refused, the drawn
       item keeps its model angle, the refusal cue plays once, and the hold still runs, so a long
       hold shows the pending angles of its repeats from the first repeat on;
    b. the release of a hold that made at least one repeat, when the final angle differs from the
       model angle: refused means no command, the drawn item snaps back to its model angle at once
       and the cue plays once; allowed means one `TransformItemCommand` as in #31. A release with
       no repeat after a refused press runs nothing and plays no second cue.
    No check runs during the hold: its pending angle may show the item through a neighbour or the
    glass (2b). The drawn selected item is not a ghost, so the #31 rule "no ghost on an invalid
    spot" is unchanged for the ghost and the drag preview. This supersedes #31 AC 41 case (e)
    ("no validity rule applies at the release") for a hold that ends on a refused angle; its other
    parts (selection kept, cancel cases, one undo step, no command when the final angle equals the
    start) stay. A cancelled hold, a valid rotation and the ghost get no cue.
    c. the release of a drag (owner decision after the first preview, #33 AC 13): when the
       release has a ground point, is not over a panel, is not at the same spot with the same
       angle (that is a click, handled first, as in #31) and the candidate (position and the
       previewed rotation) is refused, the move is cancelled as before and the cue plays once on
       the dragged item, selected or not; it does not change the selection. Esc, a right click,
       focus loss, a modal dialog, photo mode, `model_reset`, removal of the item and a release
       with no ground point are plain cancellations with no cue. The ground plane has no edges, so
       a release whose ground point lies outside the interior rectangle
       (`PlacementRules.is_point_inside` false, edges inside) also counts as pointing outside the
       tank: it is cancelled with no cue. A point inside whose footprint still pokes through the
       glass is a refused drop and cues. A click with a pick on an invalid spot gets no cue.
16. **The refusal cue: a brightness flash that turns coral, on a runtime material copy**
    (revised twice after the owner's preview of PR #161: a soft coral red pulse with a clear
    brightness peak that changes both brightness and colour on every item colour, dark red and
    salmon included; the owner accepted a shader change in this pull request).
    - Shader: `item_selection_glow.gdshader` gains one uniform, `glow_lift` (vec3, linear light,
      each channel 0 to 1, default `vec3(0.0)`), added at the rim times the fresnel term. The
      blend becomes premultiplied: output = destination x (1 - a) + `glow_colour` x a +
      `glow_lift` x fresnel, with a = clamp(fresnel x `fresnel_strength`, 0, 1). At the default
      lift the output equals today's `blend_mix` result, so the selection mark of #31, #32 and
      #157 looks exactly as before; the technical-artist proves it with before and after renders.
      `item_selection_material.tres` stores `glow_lift = Vector3(0, 0, 0)`. The shader also gets
      `fog_disabled`: Godot mixes fog into the fragment colour before the blend, so the
      premultiplied colour picked up fog even at zero rim opacity; the item below keeps its own fog.
    - Curve: `RefusalCue` (`game/systems/placement/refusal_cue.gd`, pure, `step(delta_s)`) gives
      three half-sine envelopes over `REFUSAL_CUE_DURATION_S` 0.30 s: the rim envelope on
      [0, 0.30) drives `fresnel_strength` (0.7 to `REFUSAL_CUE_PEAK_STRENGTH` 0.90) and
      `fresnel_power` (1.6 to `REFUSAL_CUE_PEAK_FRESNEL_POWER` 0.5); the lift envelope on
      [0, 0.20) drives `glow_lift` (0 to `REFUSAL_CUE_LIFT` (0, 0.30, 0.27)); the colour envelope
      on [0.10, 0.30) drives `glow_colour` (cream to `REFUSAL_CUE_COLOUR` (1.0, 0.45, 0.40)). So the
      rim first widens and brightens (peak at 0.10 s), then turns coral (peak at 0.20 s) and
      fades: one pulse whose brightness change and colour change do not cancel on any item
      colour. The bases are read from `item_selection_material.tres` and never written.
    - No bloom: at every 5 ms step the brightest channel of linear `glow_colour` x strength +
      `glow_lift` stays at most 0.921, below `glow_hdr_threshold` 1.0; the lift has no red, so
      red items are never pushed over. The exact constants, the 0.05 s table and the visibility
      minimums are in the #33 plan addendum and in `PlacementTuning`.
    - `PlacedItemsView` owns one cue and one runtime copy of the selection material (made once,
      never per frame or per item) and writes the four uniforms at each step. The same curve plays
      on an unselected dragged item (the copy is set as `material_overlay` and removed at the
      end); on the marked item the shared selection material goes back at the end. A new refusal
      restarts the cue at t = 0 on its item (a cue on another item ends first). The cue is
      cancelled by a change of the selection, hidden feedback (photo mode, modal dialogs),
      `model_reset`, `set_tank` and the removal of its item. The owner judges the look on the
      pull request preview.

### Consequences

- `footprint_cm` gets a second reader: Mode 1 placement validity reads width, height and depth;
  Mode 2 keeps its meaning (the real size, never tuned for placement). docs/architecture.md,
  Catalog schema, names the exception; the `ItemDefinition` comment says so on the field, so the
  "stored, never shown or used in Mode 1" headings stay.
- #29 (sculpted bed) decides whether the footprint then uses the highest surface point under it;
  until then rule 12 reads the origin.
- A later stacking issue replaces the substrate surface in rule 13c by the height of the part an
  item rests on; that needs a height profile per item, more than `footprint_cm.y`.
- #38 (load and autosave) never calls `allows`; legacy invalid items load unchanged.
- #49 measures the cost: rule 13 is O(n) per ghost frame with n at most 100 (D18).
