# ADR 0009: Build camera collision with analytic solids and a held distance

- Status: Proposed (accepted when the #26 pull request merges; gated by `needs:owner`)
- Date: 2026-11-11; amended 2026-11-11 (rules 4 and 5: release tilt, owner decision on #26,
  option A, [comment](https://github.com/PeterSallai90/cozy-aquarium/issues/26#issuecomment-6808114113))
- Decision log reference: none (D7 is unchanged); replaces the mechanism in the "Collision" row of
  the camera specification in docs/architecture.md ("sphere cast from pivot, pulled in when
  blocked") and aligns its obstacle list with the owner decision on #26 (walls are not obstacles)
- Issue: #26 (B15 zoom, pan, collision, Home); builds on [ADR 0008](0008-world-input-routing-and-modal-blocking.md);
  used by #27 (regression matrix) and #44/#45 (photo mode, which is not bound by this ADR)

## Context

The camera specification says the build camera "never enters the glass, the cabinet or room
geometry" and describes a sphere cast from the pivot to the camera that pulls the camera in when
blocked. #26 adds zoom and pan, so the camera can come close to the tank, and showed two problems
with that text:

- The pivot is the centre of the water volume, inside the tank. A cast from the pivot starts inside
  the tank solid, and pulling the camera toward the pivot moves it into the water, which only photo
  mode may enter.
- The room walls are not obstacles: #25 lets the camera go behind the back and left walls, which the
  wall cutaway hides (owner decision A on #26).

The BA rule on #26: the target pose (azimuth, elevation, distance, pivot) is never changed by
collision; the camera is placed at `pivot + direction x d_held`, where `d_held` is the smallest
distance at least the requested one at which the camera is outside every solid plus
`collision_margin_m`. The solids are the tank (base to rim top, the open top is free above the rim
plane), the cabinet, the floor and the lamp bar with its feet. Every solid in Mode 1 is a box.

A numeric check of that rule against the three tanks found one gap: when the elevation is negative
(the camera below the pivot) and the camera is held, pushing it out along its line lowers it. With
the pivot at a back corner on the tank floor, azimuth 90 or 270, the lowest elevation and 0.6x
zoom, the held camera ends 0.6 mm (small), 1.1 mm (medium) and 1.7 mm (large) below the cabinet
top plane, which breaks the hard rule "camera height never below the cabinet top". Along that line
no point beyond the requested distance is both outside the solids and above the plane.

## Decision

1. **Solids are axis-aligned boxes in the room frame**, the same frame as the pivot. They are plain
   `AABB` values; the camera holds no node reference for collision. `CameraSolids`
   (`game/systems/camera/camera_solids.gd`, static functions) builds them:
   - tank: the exterior footprint from `TankDefinition.get_exterior_size_m()`, from the cabinet top
     to the rim top (cabinet top + glass + interior height + trim); none when no tank is displayed
     or the box has no volume;
   - cabinet: the exterior footprint plus the cabinet margin on every side, from the floor to the
     cabinet top; none without a definition;
   - lamp: one box per visible `MeshInstance3D` under the lamp node, from its mesh AABB and global
     transform, taken after the room placed the lamp at `lamp_mount`; none when the lamp node or
     `lamp_mount` is missing or the lamp is hidden;
   - floor and walls: no box (see rule 4 for the floor; walls are handled by the wall cutaway).
   `RoomCorner`, which already places tank, cabinet and lamp and already calls
   `BuildCamera.set_framing`, calls `CameraSolids` and hands the boxes and the pan box to the
   camera with `BuildCamera.set_bounds(pan_box, solids)` before `set_framing`. This is the
   scene-composition pattern of #25 (`set_framing`, `WallCutaway.add_wall`), not system-to-system
   traffic; the camera never reads the catalog or the tank scene itself.
2. **A solid plus margin is the box grown by `collision_margin_m` on every face**
   (`AABB.grow`), not a rounded box. A point on the grown boundary counts as outside. Tests use the
   same definition.
3. **Held distance by interval chaining.** For the view line `pivot + direction x t`, each grown
   box gives one open interval of `t` (slab test). Starting at the requested distance, `t` jumps to
   the exit of any interval that contains it until no interval does. With convex solids this ends
   after at most one pass per solid; a free `t` always exists for a line that is not falling (rule
   4). `CameraCollision` (`game/systems/camera/camera_collision.gd`) holds this as pure static
   functions.
4. **The cabinet top plane is a rule, not a box.** The target elevation keeps the #25 rule
   (`OrbitMath.min_elevation_deg` with the requested distance and pivot). In addition, when the held
   camera would end below the cabinet top plane, the displayed elevation (never the target) is
   raised to the lowest elevation at which the line reaches the plane only outside the footprints
   of the solids that stand on or below the plane:
   `-atan((pivot.y - cabinet_top) / r_free)`, with `r_free` the horizontal distance along the
   azimuth to leave those grown footprints. On a steady held frame this changes the view direction
   by at most 0.1 degrees (0.0955 degrees measured; pan releases stayed within it too), and it keeps both the
   hard height rule and "a held distance always exists". During a release (rule 5) a larger raise
   is allowed (owner decision on #26, option A). The floor (y = 0) is below the plane and needs no
   box.
5. **Collision wins over easing.** Each frame the held distance is computed from the displayed
   (eased) pose. A camera that must move out goes to the held distance at once, so it is never
   inside a solid at any frame; a camera that may move in (the obstruction ended, for example at a
   rim or lamp edge) eases in by `OrbitMath.damp_factor` and is held again if the eased point is
   inside a solid. Damping time 0 is instant both ways.
   **Release tilt (owner decision on #26, option A).** The eased release point can lie further out
   than the new held distance on a falling line, for example in the first frames after a tank swap
   while pivot and distance are still easing. The plane check of rule 4 then runs on the eased
   point: the displayed elevation is raised just enough to put the eased camera on the cabinet top
   plane. During a release this raise is limited only by the cabinet top plane, not by the
   0.1 degree bound of rule 4: up to 0.89 degrees was measured, for less than about 0.3 s, across
   228 tank swap cases. If the raised line at the eased distance meets a solid, the camera takes the
   held pose of that frame instead. The target elevation is never changed. The rejected option was
   an immediate release after a tank swap, a one-frame inward jump of up to about 0.25 m.
6. **Near plane.** The camera near plane is the setting `camera_near_m` (0.03 m) in
   `CameraSettings`, and `collision_margin_m` is at least 1.3 x `camera_near_m`. Godot uses a
   reversed-Z depth buffer since 4.3, so moving the near plane from 0.05 to 0.03 m costs no
   visible depth precision at room distances, and the water, glass and caustic shaders rebuild
   positions with `INV_PROJECTION_MATRIX` (no near value is hard-coded), so they need no change.
   If playtesting still shows depth trouble, the fallback is a margin of 0.06 m (tuning), not a
   larger near plane.
7. **Scope.** This ADR binds the build camera only. Photo mode (#44/#45) must collide with plants
   and decorations inside the water and may use physics shapes; it may reuse `CameraSolids` for the
   tank, cabinet and lamp.

## Alternatives considered

- **Sphere cast from the pivot (the specification text).** The pivot lies inside the tank solid,
  so the cast starts in contact, and pulling the camera toward the pivot moves it into the water.
- **Physics query (`ShapeCast3D` or `PhysicsDirectSpaceState3D.cast_motion` against
  `StaticBody3D` shapes).** A cast finds the first contact from its start, not the first free
  point beyond the requested distance, so it needs a reverse cast plus overlap checks. The bodies
  must be rebuilt on every tank swap, the result is only valid after a physics frame (tests drive
  `step()` with fixed frame times, ADR 0008 rule 6), and the shapes would share collision layers
  with the later placement raycasts. Five boxes do not need a physics engine.
- **Pull the camera in, or slide it along the solid.** Pulling in enters the water; sliding changes
  the view direction and the look-at point on every contact, which the BA rule forbids.
- **Treat the cabinet top plane as a solid half-space.** Along a falling line no free point may
  exist, so the camera would have no valid place.
- **Room walls as solids.** Removes the back views of #25 (owner chose option A on #26).

## Consequences

- The camera specification row "Collision" names the tank, the cabinet, the floor and the lamp as
  obstacles, with the held-distance rule and a link to this ADR; walls are handled by the cutaway.
- `CameraSolids` is the single place that turns catalog data and the lamp node into solids. A new
  tank shape (D13, after the three rectangular tanks) needs a new solid builder; a non-box convex
  solid only needs its own interval function in `CameraCollision`.
- The held distance may exceed 2.5x the default distance; the target distance never does.
- The cost per frame is a few slab tests (five boxes at most in Mode 1), independent of the number
  of fish and decorations, which are inside the tank solid and never collide with the build camera.
