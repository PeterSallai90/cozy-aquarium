# ADR 0015: Fish swimming: pure steering model, tuning as catalog input, per-frame driver and CPU tail phase

- Status: Accepted (pull request for #35; gated by `needs:owner`)
- Date: 2026-11-23
- Decision log reference: none (no row D1 to D21 changes; D16, D18 and D20 are the guards).
  Amends ADR 0013 rules 3, 5 and 8 (see ADR 0013 Amendment 1) and the #164 label rule "no
  per-frame work". Adds five salts to the `FishHash` register of ADR 0013 rule 6.
- Issue: #35 (B24a fish behaviour); used by #168 (B24b item avoidance), #37 (feeding), #46 (pause
  fish), #44 and #45 (photo mode), #49 (performance) and #40 (12 more species)

## Context

#34 drew every fish at a resting pose derived from its uid and bent the tail in the vertex shader
from `TIME`; `FishView` had no per-frame code (ADR 0013 rule 8) and the name labels of #164 move
only on `FishView.refreshed`. #35 makes the fish swim: zones, schooling by `group_style`,
personality (D20, owner decisions of 2026-11-23: five traits, about +-20 percent, "balanced"),
a pause flag and an override seam. The BA decisions on #35 (Q1 to Q19) fix the behaviour as
measurable bounds; the ways to meet them are decided here.

Facts checked: the shader phase `TAU * f(speed) * TIME + swim_phase` jumps whenever `f` changes,
because `TIME` is large, and it cannot freeze while `TIME` runs; the per-species `swim_frequency`
and `swim_speed_scale` are set explicitly in the three species materials; no game code pauses the
scene tree; `FishCatalog.load_dir` loads every `.tres` in `res://catalog/fish`.

## Decision

1. **Derived personality, frozen.** `FishPersonality` (`game/model/fish_personality.gd`, static,
   pure) derives five traits from the uid alone, in the frozen order speed, boldness,
   sociability, idle share, depth preference, with the salts `fish.trait.speed`,
   `fish.trait.boldness`, `fish.trait.sociability`, `fish.trait.idle_share`,
   `fish.trait.depth_preference` (constants in `FishHash`, listed in that order in
   `FishPersonality.SALTS`). With `u = FishHash.unit(uid, salt)`: each factor is
   `0.80 + 0.40 * u`, the depth fraction is `(2 * u - 1) * 0.20`. These three numbers are frozen
   formula constants of `FishPersonality`, not tuning. The personality is never saved; the
   freeze rule is the one of ADR 0014 (STATE open until owner approval or the v0.1 tag, then a
   `format_version` bump with a migration).
2. **Species behaviour data in the catalog.** `FishSpecies` gains, as Mode 1 fields, the
   append-only enum `GroupStyle { UNSET = 0, SOLITARY = 1, TIGHT_SCHOOL = 2, LOOSE_GROUP = 3,
   FORAGING_GROUP = 4 }` and `group_style`, `idle_share`, `dart_interval_min_s`,
   `dart_interval_max_s`, `dart_duration_min_s`, `dart_duration_max_s`, `turn_rate_max_deg_s`,
   `pitch_limit_deg`, `nose_down_bias_deg`; all default to 0 or UNSET. These fields are never
   dropped or renamed (as the Mode 2 fields). `schooling` stays and equals
   `group_style in [TIGHT_SCHOOL, FORAGING_GROUP]` (catalog test).
3. **Global tuning is one catalog resource.** `FishSwimTuning` (`game/catalog/fish_swim_tuning.gd`,
   a Resource) with `game/catalog/behaviour/fish_swim_tuning.tres` holds every global tuning
   value: k (top speed factor), cruise speed fraction, acceleration and yaw-acceleration ramp
   times, idle episode lengths, dart speed fraction and minimum dart gap, catch-up distance,
   band margin, recovery speed factor and ramp, stuck rule numbers, pinned drift, the maximum
   substep and the maximum frame delta, and one `FishGroupStyleTuning` sub-resource per
   `GroupStyle` value (cohesion, alignment, spacing in body lengths). It does not live in
   `catalog/fish/` because `FishCatalog.load_dir` reads every `.tres` there. This is the "one
   place" of the BA decisions Q3 and Q19: catalog data, an input, never a literal in the steering
   code.
4. **Pure steering model in the fish behaviour system.** `game/systems/fish/` holds RefCounted
   classes without any Node reference: `FishSwimSim` (the simulation of all fish of one tank),
   `FishSwimParams` (per-fish inputs from species, personality, tuning and extents),
   `FishSwimWorld` (tank interior, water line, surface `Callable`, grain allowance),
   `FishSwimLimits` (hard limits, band at (x, z) through `FishZones`, nearest valid point) and
   `FishSwimState` (read-only result per fish). The model contains no species or tuning literal.
   Randomness comes from an injected `RandomNumberGenerator`; time from `step(delta)`.
5. **Kinematics.** A fish moves along its travel direction (yaw, travel pitch) at a scalar speed,
   so it is head-first by construction; the body pitch is the travel pitch minus the nose-down
   bias while foraging, clamped to the pitch limit; roll is never set
   (`basis = Basis(UP, yaw) * Basis(RIGHT, -pitch)`, nose up positive). Speed, yaw rate and yaw
   acceleration are capped from the tuning and the species fields; the speed cap applies to the
   final speed after all steering terms. `step(delta)` ignores `delta <= 0`, clamps `delta` to
   the maximum frame delta (0.5 s) and splits it into `ceil(delta / max_substep)` equal substeps
   (max substep 1/60 s), so 1/30 s steps equal two 1/60 s steps and a hitch never breaks a cap.
6. **One recovery ease.** When a fish is outside its hard limits or more than the band margin
   outside its band (tank, substrate or heightmap change; later an item placed over it, #168),
   `FishSwimSim.begin_recovery(uid)` moves it on the straight segment to the nearest valid point
   with a smooth speed profile: a 0.3 s smoothstep ramp up, a plateau, a 0.3 s ramp down, plateau
   speed `d / (T - 0.3)` with `T = clamp(d / (6 * top) + 0.3, 0.6, 2.0)`; heading turns under the
   turn cap and pitch limit; speed, acceleration and head-first caps are exempt and
   `FishSwimState.recovering` is true. It runs also while paused. #168 calls the same method.
7. **Stuck rule, pause and override.** One stuck rule (intent to move, not pinned, speed below the
   tuned fraction of top speed for the tuned time: pick a new target; for an override a short
   detour, then the override again). `paused` is one flag of `FishSwimSim`; while set only
   recoveries advance. An override target is clamped to the hard limits, ignores the band, keeps
   separation and all caps, has no idle or dart; set while paused it applies on resume. The
   presentation forwards three `EventBus` relay signals to the simulation:
   `fish_pause_requested(paused: bool)`, `fish_override_requested(uid: String, target: Vector3)`
   (tank-local metres) and `fish_override_cleared(uid: String)`; #46 and #37 emit them.
8. **Per-frame driver: FishView.** `FishView` owns one `FishSwimSim`, processes only while it has
   a fish node and a tank, and in `advance(delta)` (called by `_process`, or by tests with
   `manual_stepping = true`) steps the simulation, writes each pose node transform, writes the
   tail phase and swim speed instance parameters, then emits `poses_moved` once. The child
   structure of ADR 0013 rule 8 stays. A new fish starts at its derived resting pose; a tank,
   substrate or heightmap change starts recoveries instead of placing the fish at once;
   `model_reset` rebuilds every fish at its resting pose with fresh behaviour state.
9. **CPU tail phase.** `FishTailPhase` (`game/scenes/tank/fish/fish_tail_phase.gd`, static)
   advances the phase per fish:
   `phase = fposmod(phase + TAU * swim_frequency * mix(SWIM_REST_FREQUENCY, 1, clamp(swim_speed *
   swim_speed_scale, 0, 1)) * delta, TAU)`, starting at `TAU * FishHash.unit(uid,
   "fish.swim.phase")`; `swim_frequency` and `swim_speed_scale` are read once per species from
   its ShaderMaterial. `swim_speed = clamp(speed / species top speed, 0, 1)`, so darts (up to
   1.2) and the recovery ease (up to 6) show the full-speed beat. Paused fish get no phase
   advance (frozen tail). At constant speed `phase(t) = phase0 + TAU * f * t`, which is exactly
   the #34 look.
10. **Labels follow by signal, still without `_process`.** `FishLabelView` connects
    `FishView.poses_moved` only while labels are shown and moves the existing labels to pose
    position + UP * cached offset in the same call; it keeps per uid only a float offset
    (`above_m + GAP_M`), never an extents object or a pose node.

## Implementation notes (#35)

- **Personal space.** Two layers keep fish apart. The steering avoids and brakes: a push inside
  1.25 times the sum of the half lengths, a push away from a fish whose path crosses within a
  second and a half, and a speed limit set by a fish ahead (its own speed along the heading plus
  the braking distance, stopping at the sum of the half lengths times `clear_stop_factor`). As
  the last resort and the way out of a jam, `FishSwimSim` pushes a touching pair apart each
  substep, by at most a slow drift plus a share of the fish's own motion, never beyond the fastest
  speed a fish may have; a pinned fish never moves. The push is not part of
  `FishSwimState.velocity` (the swimming motion), so head-first and the speed caps are about the
  fish's own motion; the position moves, and the jump bound still holds.
- **Stuck rule and patience.** A fish that intends to move and stays slower than 5 percent of its
  top speed for 5 seconds picks a new target (an overridden fish hops one half body length
  instead). A fish that is held back for a shorter while gains patience and creeps on through a
  blocking fish, so a ring of fish that block each other dissolves.
- **Glass.** The wish that points into the glass fades out near it, a fish steers away from the
  glass a turning radius before it, brakes so that it stops before it, and glides along it when
  its heading points only slightly into it; the hard clamp is the last resort and engages only
  for the recovery ease and the push of a touching pair.
- **Known limit (owner tuning).** 20 angelfish (12 cm, a personal space of one body length) in
  the usable water of the large tank (about 80 x 18 x 20 cm) cannot keep their personal space and
  cruise at 35 percent of their top speed at the same time. The owner decided for realistic
  stocking
  ([owner decision](https://github.com/PeterSallai90/cozy-aquarium/issues/35#issuecomment-7131489351)):
  the angelfish feel tests (1/60, 1/144, global bounds, speed order, depth-preference correlation)
  use 5 angelfish per run and 4 seeded runs, pooled into 20 per-fish values; if 5 fish cannot reach
  a mean cruise of at least 0.35, they use 4 fish per run and 5 runs. Every bound stays as decided;
  the mixed test (4 angelfish) and the 60-fish separation test are unchanged, and the tuning keeps
  the personal space. The angelfish versus tetra spacing is a ratio
  ([BA decision](https://github.com/PeterSallai90/cozy-aquarium/issues/35#issuecomment-7134412134)):
  the angelfish mean nearest-neighbour distance is at least 2 body lengths and at least 1.3 x the
  tetra mean nearest-neighbour distance (a tuning value the owner judges at pull request review).

## Alternatives considered

- **Keep `TIME` in the shader and compensate `swim_phase` on the CPU.** Needs the shader's `TIME`
  on the CPU, which Godot does not expose exactly, and still cannot freeze the tail.
- **A new instance uniform for a beat clock next to `swim_phase`.** Keeps `swim_frequency` in the
  shader, but the clock must still be wrapped by the frequency (float precision after hours), so
  the CPU needs the frequency anyway; one meaning change is simpler than a fifth uniform.
- **A separate driver node writing to FishView's pose nodes.** Breaks the read-only contract of
  #164 (nobody but FishView writes a pose node).
- **Labels with `_process` or as children of the pose nodes.** `_process` costs work while hidden
  and has no defined order against FishView; children break the pose node structure.
- **Tuning constants in the steering script.** Contradicts the catalog rule and the BA decision
  Q19 that every tuning value is an input.
- **Variable step integration.** Frame-rate independence and the hitch rule would then depend on
  the frame rate; fixed substeps make 1/30 and 1/60 identical and bound the hitch.

## Consequences

- #34 tests that expect a tank, substrate or heightmap change to move every fish to its resting
  pose at once, and the idle factor 0.35, are replaced by the #35 recovery and speed tests.
- Tests that compare a pose with `FishRestPose` after frames have passed set `manual_stepping`.
- #40 fills `group_style` and the behaviour fields for 12 species. #168 adds item obstacles to
  `FishSwimLimits` and the stuck rule, and reuses `begin_recovery`. #49 measures the frame cost of
  60 swimming fish with labels; the neighbour search (`FishSwimNeighbours`, every pair with a cheap
  distance test, repeated every `neighbour_period_s` and not every step) is the lever.
- A change of the five salts, their order or the formula constants of rule 1 is a frozen-format
  change after the freeze. A change of the tuning resource or of the species behaviour values is
  owner tuning, not a format change.
- **Depth under crowding.** The vertical part of the spacing push is scaled by `spacing_vertical_scale` (on top of `social_vertical_scale`), so a few fish with a large personal space keep the height of their depth preference instead of stacking to the band edges. A turn reversal waits `min_flip_gap_s` (0.76 s): a 0.5 s frame hitch delays the time a flip is seen by up to 0.5 s, so three flips must be more than 1.5 s apart. An override fish is sent to a goal at the glass, so it skips the wall steer-away (braking and the slide zone keep it off the glass). Wander and override goals live in `FishSwimGoals`.
