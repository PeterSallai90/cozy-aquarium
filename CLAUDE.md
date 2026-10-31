# Cozy Aquarium – rules for AI contributors

## Product
Cozy 3D aquarium builder for PC. Mode 1 (cozy builder) only. Mode 2 (simulation) is future work:
never implement it, but keep its catalog fields intact. Read docs/vision.md and docs/glossary.md.
Mode 2 is called "simulation mode" in the docs; "survival mode" refers to the same mode; the final
name is decided later. Treat both names as Mode 2.

## Tech
- Godot 4.7.2, standard build, GDScript only, Forward+ renderer.
- gdtoolkit 4.5.0 (gdformat, gdlint); same version in .pre-commit-config.yaml and ci.yml.
- Static typing everywhere: typed variables, parameters and return values. No untyped `var x = ...`
  unless the type is inferred with `:=`.
- Project root is /game. Run Godot as `godot_console --headless --path game`.

## Architecture rules
- The aquarium model (game/model) is pure data. No Node references in it.
- Every change to the model goes through a Command with do() and undo().
- Systems communicate through model signals or the EventBus autoload, never by direct reference.
- Catalog data lives in game/catalog as .tres resources. Never hard-code species or item data.
- Every visible string uses tr()/tr_n() with a key; add the key to en.po AND hu.po.
- Text files are UTF-8, LF line endings.

## Assets
- Low-poly style. Triangle budgets and colouring:

  | Asset | Triangle budget | Colouring |
  | --- | --- | --- |
  | Fish | 300–800 | Vertex colours or a shared palette texture; pattern masks for colour variants |
  | Plants | 200–1,500 | Palette texture; sway in a vertex shader |
  | Rocks, wood, decor | 100–600 | Palette texture; colour tint parameter |
  | Tank, cabinet, room | 500–3,000 | Palette texture |

- Flat shading or soft low-poly shading; no photographic textures.
- One shared palette texture (a small gradient atlas) for most models keeps the look consistent and
  draw calls low.
- Colour customization works through shader parameters, never through duplicate models.
- Fish swim through a vertex shader; no skeletal rigs in the MVP.
- Generate assets with tools/blender scripts where possible.
- Any third-party asset needs a row in docs/asset-licenses.md in the same PR.

## Workflow
- One issue = one branch = one pull request. Branch name: <issue-number>-<short-slug>.
- Read the issue's acceptance criteria first; ask in the issue if anything is unclear.
- Write or update GdUnit4 tests for every acceptance criterion that can be tested automatically.
- Before opening a PR run: gdformat --check, gdlint, and the full test suite headless.
- PR description: link the issue ("Closes #N"), list what changed, how to playtest, known limits.
- Never commit to main. Never change CLAUDE.md, CI workflows or the Godot version without an issue
  that explicitly asks for it.

## Commands
- Tests:   godot_console --headless --path game -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests
- Lint:    gdlint game && gdformat --check game
- Import:  godot_console --headless --path game --import
