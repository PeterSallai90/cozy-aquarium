# Cozy Aquarium

A free, cozy 3D aquarium builder for PC. Build and rebuild a home aquarium — tank, substrate, plants,
decorations — and stock it with real freshwater fish. The game is written by AI contributors under a
human product owner.

## Status

Pre-alpha: milestone M0 Foundation. The repository contains the project skeleton and an empty Godot
project; gameplay arrives with the M1 "First playable" issues.

## Tech

- Godot 4.7.2 (standard build), statically typed GDScript, Forward+ renderer
- GdUnit4 for tests, gdtoolkit (`gdlint`, `gdformat`) for linting and formatting
- Blender, driven by Python scripts, for stylized assets (rules in [docs/art-style.md](docs/art-style.md))
- Git LFS for binary assets; GitHub Actions for CI; itch.io for releases

## Repository layout

| Path | Contents |
| --- | --- |
| `game/` | The Godot project (`project.godot`): catalog, model, systems, scenes, shaders, UI, assets, localization, tests |
| `tools/blender/` | Python scripts that generate stylized assets |
| `tools/scripts/` | Helper scripts (export, screenshot, pseudo-localization, CI checks) |
| `docs/` | Architecture guide, art style guide, ADRs, asset license log |
| `.github/` | Issue templates, pull request template, workflows |

## Getting started

1. Set up the development environment as described in
   [docs/architecture.md](docs/architecture.md#windows-11-development-environment-setup).
2. Install the pre-commit hooks once: `pre-commit install`.
3. Open the project: `godot --path game`, or import it headless with
   `godot_console --headless --path game --import`.

## Contributing

Every change starts as an issue and lands through a pull request. AI contributors follow
[CLAUDE.md](CLAUDE.md). Third-party assets must be logged in
[docs/asset-licenses.md](docs/asset-licenses.md).

## License

Code is released under the [MIT License](LICENSE). Third-party assets keep their own licenses, listed
in [docs/asset-licenses.md](docs/asset-licenses.md).
