# Developer handoff #35 (branch 35-fish-behaviour)

WIP commit: see `git log -1` on the branch (message starts "WIP #35:"). Earlier commits: 70bfdc7, 1384a8f, 1d5cfdb, 62083c4, b0720a4.

## Done (plan section 2, group B)
- Catalog: FishSpecies.GroupStyle + behaviour fields (3 species filled); FishSwimTuning / FishGroupStyleTuning + catalog/behaviour/fish_swim_tuning.tres.
- Model: FishPersonality, FishHash trait salts, FishZones.fill_range / hard_limits; surface_source is now a static-method callable (a lambda kept in a test static caused a segfault at shutdown, exit 139).
- systems/fish: FishSwimSim, FishSwimMember, FishSwimNeighbours (all pairs, every 0.05 s), FishSwimParams, FishSwimWorld, FishSwimLimits, FishSwimState, FishSwimRecovery.
- Presentation: FishView (advance, poses_moved, manual_stepping, EventBus relay, recovery on world change), FishLabelView (poses_moved), FishTailPhase, EventBus 3 signals.
- ADR 0015 got an "Implementation notes" section.
- Checks passing at last run: gdlint, gdformat, pot --check, check_translations, asset licences, import log, analyser guard (exit 0, run before the last tuning edits).

## Not done / open
- Angelfish crowd feel (20 angels, large tank) cannot meet mean cruise >= 0.35: personal space (one body length, 12 cm) in about 80x18x20 cm. Measured 0.01 to 0.19 depending on braking strictness; weakening braking reaches 0.3 but breaks the 60-fish separation test. Needs an owner/BA tuning decision (fewer fish in the test, smaller personal space for large fish, or lower bound).
- Tests failing for that reason: feel angel 1/60 and 1/144, global bounds, speed order (angel BL/s), depth-preference angel (r near 0).
- seams `a_target_outside_the_tank_is_clamped...` was failing at the last run (final x 1 cm short of the 3 cm tolerance during the override hop); hop radius was just lowered 0.5 -> 0.4 BL (detour_radius_bl), not re-run. Check it and test_fish_swim_stuck still pass.
- Last tuning edit in progress was school tuning: tetra cohesion 4.0 / spacing 1.2 made tetra crowd worse (0.286), REVERTED to cohesion 3.0 / spacing 1.3. With that, the 8-tetra / 4-angel school gap is 2.24 - 1.50 = 0.74 (needs >= 0.75): fails by 0.01. Try tetra spacing 1.25 or alignment, or angel spacing; re-check tetra crowd (needs mean cruise >= 0.359 so BL/s >= 1.4) and separation.
- No full-suite run with the final values. Suite time measured earlier: 14 min 19 s to 14 min 57 s versus 8 min 57 s baseline (+5.5 to 6 min). The 10-minute runs: about 26 s each at 1/60 and 56 to 64 s each at 1/144 (6 runs), plus extremes.
- fish_swim_sim.gd is 988 lines (gdlint max 1000): extract before adding more.

## Last results (patched helper, `-c`)
Full suite 3838 cases: only the feel angel group, seams hop test and (before the depth-restore fix) tetra depth correlation failed. systems/fish per-suite: seams 13/13, stuck 5/5, recovery 7/7, schooling 12/12 (before last tuning), separation 3/3, smoothness ok, zones ok except the mound test before jitter 0.05 (fixed: diff 0.013).

## Test helper bug (dispute / report to code-reviewer)
game/tests/helpers/fish_swim_runs.gd: `(result["x"] as PackedFloat64Array).append(...)` appends to a COPY, so all result arrays stay empty and every Runs-based feel/zones assertion reads 0 or indexes out of range. Fix: `var list: PackedFloat64Array = result[key]; list.append(v)`. Patch: .claude/state/handoff/35/fish_swim_runs_helper_fix.patch (apply locally with `git apply`; it leaves trailing whitespace, run gdformat; I did NOT commit it, tests are not mine to edit). Without it the feel tests cannot pass.

## Tuning set (all in catalog/fish_swim_tuning.gd defaults and behaviour/fish_swim_tuning.tres)
cruise_speed_fraction 0.6 (plan 0.47), turn_slow 60 to 150 deg floor 0.75, clear_stop_factor 1.1, brake_safety 0.92, spacing_weight 16 cap 3, cohesion_weight 3, follow_target_chance 1.0, avoid_weight 3, wander_height_jitter 0.05, depth_restore_weight 1.5, contact_still_fraction 0.095, contact_follow_fraction 0.4, give_way 1.0 s / 1.5 s / 0.5. Styles: tight cohesion 3 alignment 1 spacing 1.3 view 6; loose cohesion 0.25 alignment 0.2 spacing 4.0 view 10; foraging unchanged.
Bounds met (150 to 600 s explore runs): tetra, corydoras crowds, singles incl. extremes (tetra extreme-high 0.71 vs 0.72, thin), separation (worst pair 0.38 s), schooling except the 0.01 gap above.

## Next steps
1. Re-run quick suites: seams, stuck, recovery, schooling, separation, scenes/tank/fish.
2. Fix the school gap (see above), re-check tetra crowd 10-min cruise and separation.
3. Apply helper patch locally, run systems/fish and then the full suite once; revert the patch; report the angel crowd as infeasible with the numbers above.
4. Report suite time growth; ask for needs:owner (visible change: swimming fish).

## Pitfalls
- Vector3 is float32: clamps need _EDGE_EPSILON; recovery plateau 0.999 of cap; wrapf snaps near PI (wrap yaw manually).
- Bash heredocs with backticks or quotes broke; use the Write tool for scripts. Never run git checkout/stash experiments on the tree.
- `-c` flag is needed for GdUnit to continue after a failure. New class_name needs a `--import` first.
- Scratch tools (explore.gd, school.gd, depth.gd, dbg*.gd) are in the session scratchpad, not committed.
