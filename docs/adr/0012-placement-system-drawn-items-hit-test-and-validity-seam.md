# ADR 0012: Placement system: drawn items, analytic hit test, validity seam and shared item catalog

- Status: Accepted (pull request for #31; gated by `needs:owner`)
- Date: 2026-11-20
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
