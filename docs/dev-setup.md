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

## Vendored fonts

Files under `game/assets/fonts/` stay byte-identical to upstream. `.editorconfig` switches off
trimming and final-newline handling there, and the pre-commit whitespace hooks exclude the
folder. Do not "fix" line 21 of `OFL.txt`.
