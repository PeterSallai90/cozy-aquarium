# ADR 0004: Engine output policy – no unexplained engine output

- Status: Proposed (accepted when the #91 pull request merges)
- Date: 2026-11-04
- Decision log reference: none (no row in the decisions table changes); refines the quality gates
  in docs/architecture.md
- Issue: #91 (engine output policy, issue 1 of 4); owners of later steps: #92, #93, #94. Related:
  #88 and PR #89 (test-run leak gate)

## Context

PR #89 (#88) made CI fail on the two engine leak lines of the test run. Every other engine
warning or error still passed silently. On develop 0a81a4b the test run printed 16 `push_error`
lines (all asserted), 17 ConfigFile parse errors and 80 `push_warning` lines (all deliberate,
none asserted). GdUnit4 6.2.2 ships with `push_error` reporting off, so an unexpected
`push_error` did not fail a test. The owner asked for "a general solution to handle them".

Owner decisions of 2026-11-04 (quoted in #91):

- **Strictness:** any unexpected engine WARNING or ERROR fails the build. Expected messages are
  asserted explicitly in tests.
- **Allowlist:** the log gate may have a small, reviewed allowlist. Each entry needs a reason and
  an issue link, and the target is an empty list.
- **Fresh-checkout import errors:** fix them by running `--import` twice in CI and gating only the
  second run. Do not change how the theme is applied.
- **Scope:** #91–#94 go in now, as a chore track in milestone M0 Foundation, in that order.

## Decision

1. **Rule: no unexplained engine output.** Every engine `WARNING` or `ERROR` produced by a
   pipeline step is either asserted by the test that causes it, avoided, or a reviewed allowlist
   entry. Nothing else passes.
2. **One owner per pipeline step.**

   | Step | Owner | Issue |
   | --- | --- | --- |
   | GDScript analyzer warnings in game code and tests | Analyzer settings in `game/project.godot` | #92 |
   | Test run, inside a test case | GdUnit4 (`gdunit4/report/godot/push_error=true`, `script_error` at its default `true`) | #91 |
   | Test run, everything GdUnit4 cannot see (leaks, script and parse errors, output outside a test case, the handover list below) | Test-step log gate | #93 |
   | Import | Log gate (`--import` twice, only the second run gated) | #93 |
   | Export | Log gate | #93 |
   | Boot of the exported Windows build | Log gate (smoke step) | #94 |

   This ADR names the owners; the technical details of #92–#94 are decided in those issues.
3. **Expected messages are asserted where they happen.** A deliberate message is asserted in the
   test that causes it, with `assert_error(...)` or a test helper built on GdUnit4's error
   monitor that checks each distinct text at least once and the exact count per text. A message
   is deliberate only when all four hold: the test sets up the triggering input on purpose; the
   test asserts the resulting return value or state; the text matches a known source in game
   code; the test is a failure or invalid-input case. Anything else is a defect candidate and gets
   a bug issue; it is never asserted away.
4. **No blanket suppression.** No match-anything assertion (such as an empty substring), and no
   per-test or per-suite disabling of GdUnit4 reporting.
5. **Guard.** Asserting a message must not weaken or remove the validation behind it. A test-side
   assertion never needs a game-code change; if one would, it is a separate issue.
6. **Allowlist rule.** A log gate may have a small, reviewed allowlist. Each entry has a reason
   and an issue link; the target is an empty list. #91 creates no allowlist entry.
7. **Fresh-checkout import rule.** CI runs `--import` twice and gates only the second run; how the
   theme is applied does not change (#93).

## What GdUnit4 6.2.2 captures (AC5 of #91)

Source finding (game/addons/gdUnit4, 6.2.2):

- `GodotGdErrorMonitor.GdUnitLogger` is a Godot `Logger` registered with `OS.add_logger`. Every
  message that goes through the engine's error handler reaches its `_log_error`, whether it comes
  from GDScript (`push_error`, `push_warning`) or from engine C++ (`ERR_PRINT`, `WARN_PRINT`,
  such as the ConfigFile parse error from `core/io/config_file.cpp`).
- `ERROR_TYPE_ERROR` is recorded as `PUSH_ERROR` and `ERROR_TYPE_WARNING` as `PUSH_WARNING`, both
  only when `gdunit4/report/godot/push_error` is true. `ERROR_TYPE_SCRIPT` is recorded when
  `script_error` is true. So the one key turns on all three message kinds the test run printed.
- The monitor is cleared after `before_test()` and read after the test body and after
  `after_test()`; every recorded entry that no assertion consumed becomes a test failure.
  `assert_error(...).is_push_error(text)` and `.is_push_warning(text)` consume one matching entry
  each; a ConfigFile parse error is matched with `is_push_error`.
- Not seen by GdUnit4: output in `before()`, `before_test()` and `after()`, output outside any
  test case (startup, scanning, shutdown), and engine leak lines at exit. These belong to #93.
- Asserted messages are still printed to the console. A test-step log gate cannot tell an
  asserted `WARNING:` or `ERROR:` line from an unasserted one, so #93's test step fails on such
  lines only for entries on the handover list.

Experimental confirmation: recorded by the tester on #91:
https://github.com/PeterSallai90/cozy-aquarium/issues/91#issuecomment-6631564082

### Handover list

Lines GdUnit4 cannot assert, for #93 (test, source, count): none. The tester confirmed that
GdUnit4 captures `push_warning` and ConfigFile parse errors with their full visible text, and on
develop 0a81a4b every one of the 113 lines was printed inside a test body.

## Alternatives considered

- **A log gate alone for the test run:** the log cannot show which test caused a line or whether
  the test expected it, and asserted lines are printed too; the allowlist would grow with every
  failure-case test.
- **Keep `push_error` reporting off and assert only by convention:** an unexpected `push_error`
  keeps passing, which is the gap #91 closes.
- **Silence deliberate warnings in game code:** removes useful diagnostics for players' logs and
  weakens validation; ruled out by the guard.

## Consequences

- `game/project.godot` gains one key, `gdunit4/report/godot/push_error=true`; the pull request
  goes through the owner gate.
- A new test that triggers a warning or error must assert it, or it fails. docs/dev-setup.md
  ("Test runs and leaks") states this.
- A GdUnit4 upgrade must re-check the capture behaviour above; the helper that reads the error
  monitor depends on GdUnit4 internals.
- #93 owns the test-step gate for leaks, script and parse errors, output outside test cases and
  the handover list; #92 and #94 own their steps.
