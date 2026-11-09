# ADR 0005: Camera field of view reference and default framing

- Status: Accepted (#22 merged); rule 3 amended by
  [ADR 0006](0006-default-framing-vertical-fit.md) (vertical fit for tall tanks, #24)
- Date: 2026-11-08
- Decision log reference: none (D7 is unchanged); clarifies the "Default view" and "Field of view"
  rows of the camera specification in docs/architecture.md
- Issue: #22 (B11, placeholder camera); used by #25 (B14 orbit camera and reset), the B15 camera
  issue, the camera settings (field of view slider, 40–70°) and photo mode

## Context

The camera specification gives a field of view of 50° and a default view in which the tank width
fills about 85% of the screen, but it does not say whether 50° is horizontal or vertical, nor how
the framing behaves on different aspect ratios. #22 builds the first camera (a placeholder) and
its acceptance criterion 9 checks the 85% share at 16:9, 16:10, 4:3 and 21:9 with the tank and the
cabinet top fully on screen. B14 inherits the formula as its reset target, and the settings slider
will store a field of view value in `user://settings.cfg`; once players have that value, its
meaning is hard to change.

Geometry check for the medium tank (exterior 0.61 x 0.31 m, 0.365 m high with the trim, pivot at
the centre of the water volume, 5° elevation, 85% share): with a horizontal field of view the
front glass top and bottom project to about +0.92 and -0.89 of the half screen height at 16:9,
but to +1.20 and -1.17 at 21:9. On any screen wider than about 1.9:1 a 0.61 x 0.365 m tank cannot
fill 85% of the width and stay fully on screen, whatever field of view is chosen.

## Decision

1. **The field of view is horizontal.** Every field of view value in the game (the 50° default,
   the 40–70° settings range, photo mode) is the horizontal angle at a 16:9 reference aspect.
   Godot: `Camera3D.fov` with `keep_aspect = KEEP_WIDTH`.
2. **Screens wider than 16:9 keep the 16:9 vertical angle.** For an aspect ratio up to 16:9 the
   camera uses `KEEP_WIDTH` with the horizontal angle (the picture grows taller on 16:10 and 4:3).
   Above 16:9 it switches to `KEEP_HEIGHT` with the vertical angle that the horizontal angle gives
   at 16:9 (`2·atan(tan(fov/2)·9/16)`, 29.5° for 50°), so ultrawide screens show more room at the
   sides and the tank keeps its 16:9 size on screen. The camera re-applies this rule when the
   viewport size changes.
3. **Default framing formula.** The camera looks at the pivot (centre of the tank's water volume)
   from the front at the default elevation. Its distance from the pivot is
   `d = W / (2·s·tan(fov/2)) + (D/2)·cos(elevation)`, where `W` and `D` are the exterior glass width
   and depth of the tank from the catalog (interior plus two glass thicknesses; the cosmetic frame
   trim is not counted) and `s` is the width share (0.85). At aspect ratios up to 16:9 the front
   glass then fills exactly `s` of the screen width, measured between the front corners at pivot
   height; above 16:9 it fills `s·(16/9)/aspect` (64.8% at 21:9). The formula is a pure function in
   `game/systems/camera/camera_framing.gd`; the starting values are named constants. Amended by
   [ADR 0006](0006-default-framing-vertical-fit.md): the distance is the larger of this width
   distance and the distance that keeps the tank, its trim and the cabinet front edge on screen.

## Alternatives considered

- **Vertical field of view (Godot's default `KEEP_HEIGHT`).** The 85% share would then hold only at
  one aspect ratio, and on 4:3 the tank would overflow the screen (113% of the width).
- **Horizontal field of view on every aspect ratio.** Keeps 85% everywhere but cuts off the top of
  the tank and the cabinet on 21:9, which breaks the "tank fully on screen" part of the default
  view.
- **Changing the distance per aspect ratio instead of the projection.** Equivalent on screen, but
  it makes the zoom limits (0.6x to 2.5x the default distance) depend on the window shape.

## Consequences

- #22 acceptance criterion 9 holds as written at 16:9, 16:10 and 4:3. At 21:9 the share is 64.8%
  (within 2 percentage points) and the tank and cabinet top are fully on screen; product-ba amends
  the criterion on #22 accordingly.
- B14 reuses `CameraFraming` for its reset target and keeps the aspect rule; the zoom limits stay
  multiples of the default distance, which does not depend on the window shape.
- The camera settings issue labels the slider as the horizontal field of view and applies the
  same aspect rule.
- Photo mode uses the same rule, so a picture taken on an ultrawide screen shows more of the room,
  not less of the tank.
