# ADR 0001: Engine, language and renderer

- Status: Accepted
- Date: 2026-10-27
- Decision log reference: D6 in docs/architecture.md

## Context

Cozy Aquarium is a free, stylized low-poly 3D game for PC (Windows primary, Linux and macOS as a
bonus), written almost entirely by AI agents. The engine must keep scripts, scenes, materials and UI
layouts in plain text so an agent can read, change and test them without a human using an editor GUI,
and it must run tests and exports headless in CI without license activation.

## Decision

- Engine: **Godot 4.7.2** (`4.7.2.stable.official`), standard build, not .NET.
- Language: GDScript with static typing enforced.
- Renderer: Forward+.

The pinned version is used on every development machine and in CI. `GODOT_VERSION` in
`.github/workflows/ci.yml` must match the version in this record.

## Alternatives considered

- **Unity with C#:** more ready-made assets and more C# training data, but much of the work happens
  in the editor GUI, CI needs license activation, and its licensing terms have changed repeatedly.
- **Godot with C# (.NET build):** adds the .NET toolchain for no clear gain; GDScript has the best
  engine integration and fast iteration, and static typing gives the AI compile-time feedback.
- **Mobile or Compatibility renderer:** lower requirements, but worse water, glow, volumetric fog and
  light quality. The target is PC only, so Forward+ is acceptable.

## Consequences

- Godot is free (MIT); no license costs or activation in CI.
- Scenes and resources are text (`.tscn`, `.tres`) and reviewable in pull requests.
- Forward+ needs a Vulkan, Direct3D 12 or Metal capable GPU.
- Upgrading Godot is a deliberate decision: a new ADR, a pull request that changes the version in CI,
  and a full test run.
