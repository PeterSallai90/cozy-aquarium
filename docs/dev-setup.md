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
- CI runs `tools/scripts/check_test_leaks.py` on the output of "Run tests". Locally, run the
  commands in "Test runs and leaks".

## Test runs and leaks

A headless test run must end with no leaked objects and no leaked resources. CI fails the test
job when the output of "Run tests" contains a leak line.

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
- Output outside test cases (suite hooks, scan, exit) is not seen by GdUnit4; the log gate (#93)
  handles it. See `docs/adr/0004-engine-output-policy.md`.

### Run the gate locally

The gate reads the log file after the run. `test.log` is a git-ignored local scratch file.

PowerShell:

```powershell
godot_console --headless --path game -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests --ignoreHeadlessMode *>&1 | Tee-Object test.log; python tools/scripts/check_test_leaks.py test.log
```

In PowerShell the gate's exit code replaces `$LASTEXITCODE`, so read the test result from the
GdUnit summary line. Windows PowerShell 5.1 writes `test.log` as UTF-16; the gate decodes it.
If a long line is ever wrapped and missed, use PowerShell 7 (`pwsh`).

Git Bash / Linux (on Linux the binary may be `godot`):

```bash
set -o pipefail; godot_console --headless --path game -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests --ignoreHeadlessMode 2>&1 | tee test.log; python tools/scripts/check_test_leaks.py test.log
```

Gate exit codes: 0 clean, 1 leak line found (printed to stderr), 2 log missing, empty or
unreadable.

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

## Vendored fonts

Files under `game/assets/fonts/` stay byte-identical to upstream. `.editorconfig` switches off
trimming and final-newline handling there, and the pre-commit whitespace hooks exclude the
folder. Do not "fix" line 21 of `OFL.txt`.
