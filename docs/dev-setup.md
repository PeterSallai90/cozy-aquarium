# Developer setup notes

## Purpose

Workflow notes for contributors that cannot go into CLAUDE.md.

## Godot editor and `game/project.godot`

Opening and saving the project in the Godot 4.7.2 editor removes settings whose values equal
Godot's defaults. The game still works, because the defaults are the same. Two lines must stay
written explicitly anyway. They are the ones listed in `REQUIRED_SETTINGS` in
`tools/scripts/check_project_settings.py`:

- `renderer/rendering_method="forward_plus"` under `[rendering]` (pins decision D6, Forward+)
- `locale/fallback="en"` under `[internationalization]` (required by #18)

They are restored, never changed.

## Restore

- Run `git checkout -- game/project.godot` when nothing else in the file should be kept.
- Otherwise add the missing line back by hand under its section.

Then run `python tools/scripts/check_project_settings.py`. It exits 0 and prints nothing when
both lines are present, and prints one line per problem otherwise.

## What protects what

- The local pre-commit hook `check-project-settings` runs the script, but only when
  `game/project.godot` is staged. `git commit --no-verify`, or a clone without
  `pre-commit install`, skips it. The first run builds the hook environment once; if the Python
  behind pre-commit changes, run `pre-commit clean`.
- CI does not run pre-commit or the script. CI runs the GdUnit tests `test_project_settings.gd`
  and `test_localization_setup.gd`, which fail with a "restore this line" message.
- CI runs `tools/scripts/check_godot_log.py` on the output of the two imports, "Run tests" and
  the export, and boots the exported Windows build on a Windows runner (the `smoke-windows` job)
  and gates its output. Locally, run the commands in "Engine output gate (test runs and leaks)"
  and "Run the smoke check locally".

## Engine output gate (test runs and leaks)

A headless Godot run must end with no leaked objects, no leaked resources and no engine errors or
warnings nobody explained. CI runs `tools/scripts/check_godot_log.py --step <step> <log>` on the
output of each Godot step and fails the job on a finding. The script holds every pattern, the
step rules and the allowlist.

### What each step fails on

| Step | CI step | Fails on |
| --- | --- | --- |
| `import-first` | "Check first import output" | A leak line, or any `ERROR:`, `WARNING:` or script error line, except the pinned first-import set |
| `import` | "Check import output" | A leak line, or any `ERROR:`, `WARNING:` or script error line |
| `test` | "Check test output" | A leak line anywhere, or an engine line outside a test case (see below) |
| `export` | "Check export output" | Same as `import` |
| `smoke` | "Check smoke output" | Same as `import` |

CI imports the project twice. The first run of a fresh checkout is gated by `import-first`, the
second by `import`. A line matches when it contains the token followed by a colon, with any
prefix (for example the `godot_console : ` that PowerShell adds). A bare `Unicode parsing error`
line is not an engine line.

### Test step: test case windows

GdUnit4 already fails a test for an engine error it did not expect, and prints the asserted ones.
So in the `test` step, engine lines between the `STARTED` line of a test and its end line
(`PASSED`, `FAILED`, ...) are not flagged. Every engine line outside such a window is a finding,
and so is a window that never ends (crashed or truncated run, or a different test ending first).
An unterminated window excuses nothing. Leak lines are findings also inside a window.

Known limits: output of `before_test()` and `after_test()` that lands inside a window is not
seen. After a `FAILED` test, GdUnit4's report block can add findings; fix the failing test first.

### Allowlist

`ALLOWLIST` in the script is empty and stays empty unless the owner agrees. An entry is a literal,
case-sensitive substring (not a regex) of the line, a reason, and a link to an issue of this
repository. An empty or whitespace-only substring, a substring that is an engine token (`ERROR:`,
`WARNING:`, `SCRIPT ERROR:`) or part of one, with or without surrounding whitespace, or a
missing reason or issue link makes every gate step exit 2. Matching uses the substring as
written, including its spaces. A test checks that `len(ALLOWLIST) == 0`.

### Pinned first-import set

On a fresh checkout the first import prints 10 known error lines (the theme and the fonts are
imported in the wrong order; the second import is clean). `FIRST_IMPORT_PINNED` lists their
exact shapes with a maximum count each; only the 32-character hash varies. An extra copy beyond a
line's count or a line for a different font file is a finding; pinned lines that are
missing from the log pass (there is no minimum count). The set may not grow without an owner OK
(owner decision on #93). It exists only for the `import-first` step.

### Rule for test writers

When a test connects a lambda or a Callable to a signal of any object, including model signals
and the EventBus, nothing the lambda captures may lead back to the emitter. That covers the
emitter itself, an object that holds the emitter, and any longer chain that ends at the emitter.
This is a reference cycle (emitter, connection, lambda, emitter). RefCounted objects in a cycle
are never freed, and neither are the scripts they keep alive.

Safe options:

- Capture a `WeakRef` (`weakref(obj)`) and call `get_ref()` inside the handler.
- Disconnect the handler in cleanup that runs even when the test fails, for example
  `after_test()`. Code placed after the assertions does not count: a failed assertion skips it.

```gdscript
var service: LanguageService = _service()
var service_ref: WeakRef = weakref(service)
var seen: Array = []
service.language_changed.connect(
	func(_code: String) -> void:
		seen.append((service_ref.get_ref() as LanguageService).get_last_save_error())
)
```

This is a test-writing rule, not a game-code rule. `CLAUDE.md` is not changed.

### Expected engine messages

GdUnit4 runs with `gdunit4/report/godot/push_error=true` in `game/project.godot`. Any
`push_error`, `push_warning` or engine error (for example a ConfigFile parse error) that a test
does not assert fails that test.

- A test that triggers an expected message asserts it where it happens, with
  `assert_error(...).is_push_error(...)` or `.is_push_warning(...)`.
- When one call logs several messages, or the same message more than once, use
  `tests/helpers/engine_output.gd` (`EngineOutput.capture`): assert each text and its exact count.
  A count alone is not enough.
- Asserted messages still appear in the console output. That is expected.
- Never assert with an empty or match-anything text, and never turn reporting off for a test.
- Output outside test cases (suite hooks, scan, exit) is not seen by GdUnit4; the test step of the gate
  handles it. See `docs/adr/0004-engine-output-policy.md`.

### Run the gate locally

The gate reads the log file after the run. `test.log` is a git-ignored local scratch file.
The import logs go to the temp folder.

Import (a fresh checkout needs the project imported twice; gate both logs):

```powershell
godot_console --headless --path game --import *>&1 | Tee-Object "$env:TEMP\godot-import-first.log"; python tools/scripts/check_godot_log.py --step import-first "$env:TEMP\godot-import-first.log"
godot_console --headless --path game --import *>&1 | Tee-Object "$env:TEMP\godot-import.log"; python tools/scripts/check_godot_log.py --step import "$env:TEMP\godot-import.log"
```

```bash
godot_console --headless --path game --import 2>&1 | tee "${TMPDIR:-/tmp}/godot-import-first.log"; python tools/scripts/check_godot_log.py --step import-first "${TMPDIR:-/tmp}/godot-import-first.log"
godot_console --headless --path game --import 2>&1 | tee "${TMPDIR:-/tmp}/godot-import.log"; python tools/scripts/check_godot_log.py --step import "${TMPDIR:-/tmp}/godot-import.log"
```

Tests:

PowerShell:

```powershell
godot_console --headless --path game -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests --ignoreHeadlessMode *>&1 | Tee-Object test.log; python tools/scripts/check_godot_log.py --step test test.log
```

In PowerShell the gate's exit code replaces `$LASTEXITCODE`, so read the test result from the
GdUnit summary line. Windows PowerShell 5.1 writes `test.log` as UTF-16; the gate decodes it.
If a long line is ever wrapped and missed, use PowerShell 7 (`pwsh`).

Git Bash / Linux (on Linux the binary may be `godot`):

```bash
set -o pipefail; godot_console --headless --path game -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests --ignoreHeadlessMode 2>&1 | tee test.log; python tools/scripts/check_godot_log.py --step test test.log
```

Export (CI command, for reference; it needs the export templates):

```bash
set -o pipefail; godot --headless --path game --export-release "Windows Desktop" ../build/windows/CozyAquarium.exe 2>&1 | tee "$RUNNER_TEMP/godot-export.log"; python3 tools/scripts/check_godot_log.py --step export "$RUNNER_TEMP/godot-export.log"
```

Gate exit codes: 0 clean (prints nothing), 1 findings (one stderr line each, then a summary),
2 cannot check (log missing, empty or unreadable, or an invalid allowlist entry). When several
CI steps are red, read the first failed one.

### The two leak lines

Godot prints these at shutdown:

```text
WARNING: 8 ObjectDB instances were leaked at exit (run with --verbose for details).
ERROR: 4 resources still in use at exit (run with --verbose for details).
```

The first counts leaked objects. The second counts resources, such as scripts, that those
objects keep alive. The counts do not matter to the gate: any such line fails it. The match is
case-sensitive and the patterns live in one place, `LEAK_PATTERNS` in the script.

### Find the leaking test

1. Rerun the Godot command with `--verbose` added. It lists the leaked instances.
2. Bisect: run single suites with `-a res://tests/<folder or file>` until one suite still prints
   the leak lines, then narrow it to the test.

GdUnit4's orphan check reports orphan Nodes only, so it does not see RefCounted or script leaks.
This gate covers those.

## Run the smoke check locally

CI boots the exported Windows build (`build/windows/CozyAquarium.exe`) headless for 120 frames
and gates its output with the `smoke` step. First make the export: see "Export (CI command, for
reference)" above (it needs the export templates). Then, in PowerShell:

```powershell
& build\windows\CozyAquarium.exe --headless --quit-after 120 *>&1 | Tee-Object "$env:TEMP\godot-smoke.log"
$game = $LASTEXITCODE
python tools/scripts/check_godot_log.py --step smoke "$env:TEMP\godot-smoke.log"
```

Read `$game` before the gate runs anything else, because the gate's exit code replaces
`$LASTEXITCODE`. Exit codes: the game must exit 0; the gate exits 0 (clean), 1 (findings) or 2
(cannot check). The quit value 120 matches CI. The `smoke` step is import-like: any leak line,
`ERROR:`, `WARNING:` or script error line is a finding, and the allowlist is empty.

## Vendored fonts

Files under `game/assets/fonts/` stay byte-identical to upstream. `.editorconfig` switches off
trimming and final-newline handling there, and the pre-commit whitespace hooks exclude the
folder. Do not "fix" line 21 of `OFL.txt`.
