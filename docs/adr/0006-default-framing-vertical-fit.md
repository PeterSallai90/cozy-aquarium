# ADR 0006: Default framing keeps a tall tank fully on screen (vertical fit)

- Status: Accepted (owner decision 2026-11-09 on #24: option A, "Camera backs off")
- Date: 2026-11-09
- Decision log reference: none (D7 is unchanged); amends rule 3 of
  [ADR 0005](0005-camera-fov-reference-and-default-framing.md) and the "Default view" row of the
  camera specification in docs/architecture.md
- Issue: #24 (B13, three tank sizes); used by #25 (B14 reset target), photo mode and the camera
  settings issue

## Context

ADR 0005 fixes the default view: the exterior glass width fills 85% of the screen width at aspect
ratios up to 16:9, and the tank and the front edge of the cabinet top stay fully on screen. It was
checked only on the medium tank (exterior 0.61 x 0.31 m, 0.365 m high with the trim), whose
proportions leave room above and below at 16:9.

#24 adds a small tank, interior 0.40 x 0.27 x 0.25 m, exterior 0.408 x 0.258 m, 0.284 m high with
the trim, on the same 0.75 m cabinet, and a large tank, exterior 1.016 x 0.416 m, 0.538 m high with
the trim. Projected with the ADR 0005 formula (50 degree horizontal field of view, 5 degree
elevation, pivot at the centre of the water volume), in units of the half screen height (inside
the screen means between -1 and +1):

| Tank | Aspect | Trim top | Cabinet top front edge | Share that fits |
| --- | --- | --- | --- | --- |
| Small | 16:9 | +1.089 | -1.080 | 78% |
| Small | 16:10 | +0.980 | -0.972 | 85% |
| Small | 4:3 | +0.817 | -0.810 | 85% |
| Medium | 16:9 | +0.916 | -0.929 | 85% |
| Large | 16:9 | +0.791 | -0.827 | 85% |

At 16:9, the most common aspect, the small tank cannot fill 85% of the width and keep its rim
trim and the cabinet front edge on screen. #24 acceptance criterion 13 asks for both, and the BA
decision on review item 13 says the 85% is never lowered silently: a change of the default view is
an owner call.

## Decision (option A, chosen by the owner)

Rule 3 of ADR 0005 is extended. The default distance is the larger of two distances:

1. the width distance of ADR 0005, `d_w = W / (2·s·tan(fov/2)) + (D/2)·cos(elevation)` with
   `s = 0.85`;
2. the fit distance `d_v`: the smallest distance at which the tank exterior including the rim
   trim and the front edge of the cabinet top lie inside the vertical field of view at the 16:9
   reference aspect, with a margin of 2% of the half screen height.

`d = max(d_w, d_v)`. The rule is a pure function in `game/systems/camera/camera_framing.gd`
(`CameraFraming`), computed from catalog values only (exterior size, trim size, cabinet margin,
cabinet top height); the 2% margin is a named constant. Rules 1 and 2 of ADR 0005 (horizontal
field of view, wider screens keep the 16:9 vertical angle) are unchanged, so above 16:9 the
picture keeps the 16:9 framing.

Result: medium and large keep exactly 85% (the width distance wins); the small tank fills about
77% of the width at 16:9 and smaller aspect ratios, and is fully on screen with its cabinet edge.
Zoom limits (B14/B15) stay multiples of the default distance.

## Alternatives considered

- **B: keep 85% for every tank and accept the cut.** At 16:9 the top of the small tank's trim and
  the front edge of its cabinet top fall about 8 to 9% of the half screen height outside the
  picture. #24 AC 13 would be relaxed for the small tank at 16:9. No code change.
- **C: change the small tank's proportions** (for example a lower interior height or a longer
  tank). A realism and naming question for the domain BA and the owner; the nano 40 x 25 x 25 cm
  reference would be lost.
- **D: a per-tank framing share in the catalog.** Works, but is a hand-tuned number per tank that
  must be re-checked whenever a tank or the cabinet changes; option A derives the same result.

## Consequences

- #24 AC 13 reads: the exterior width fills 85% within 2 percentage points unless the vertical fit
  needs a smaller share; then the tank, its trim and the cabinet front edge are fully on screen
  with the 2% margin and the share is what the fit gives (about 77% for the small tank at 16:9).
- The "Default view" row of the camera specification in docs/architecture.md gets the same
  clause and links this ADR; ADR 0005 notes that its rule 3 is amended here.
- B14 reuses the same function for its reset target; a future tank shape (D13) is framed by the
  same rule without new numbers.
- Options B, C and D were not chosen; the small tank keeps its nano proportions and the catalog
  gets no framing field.
