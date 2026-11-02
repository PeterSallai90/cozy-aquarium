# ADR 0003: Settings plumbing, change signal and settings screen sections

- Status: Proposed (accepted when the #20 pull request merges)
- Date: 2026-11-02
- Decision log reference: none (no row in the decisions table changes); refines the "Settings"
  row of Core systems in docs/architecture.md
- Issue: #20 (B09a); used by #81 (B09b), B14, B15 and photo mode

## Context

B07 (#18) gave the game one settings file, `user://settings.cfg`, written only through
`SettingsStore`, and one setting, the language, with its own path (`Localization.set_language`,
`EventBus.language_changed`). B09a (#20) adds the settings screen and the plumbing that every later
setting reuses: audio, graphics and controls (#81), camera (B14, B15) and photo mode. Those issues
must add keys and screen sections without new plumbing and without changing the screen shell. The
choices below are hard to reverse once several features depend on them.

## Decision

1. **Typed key definitions.** A setting is declared in code by the feature that owns it as a
   `SettingKey` (`game/systems/settings/setting_key.gd`): section, key, value type (bool, int,
   float or String), default and an optional numeric range. `SettingKey.coerce(raw)` is the only
   bad-value rule: wrong type gives the default (an int is accepted for a float key; NaN and
   infinity are a wrong type), a number outside the range is clamped. There is no central key
   registry; keys are not catalog data.
2. **One settings service, one autoload.** `SettingsService` (`game/systems/settings/`) reads
   through `SettingsStore`, keeps the effective value of each key for the session, writes one key
   per real change and emits `changed(section, key, value)` only when the value really changes.
   The autoload `Settings` (registered after `Localization`) owns the service on an injectable
   path and relays the change to `EventBus.setting_changed(section: String, key: String, value:
   Variant)`. Nothing is read eagerly or written at startup. The language stays on its B07 path
   and never uses this signal.
3. **Save failure is a query, not a new return code.** `LanguageService`, `Localization` and
   `SettingsService`/`Settings` expose `get_last_save_error() -> Error`, updated on every write
   attempt before the change signal is emitted. B07's return codes and signal order stay
   unchanged. The settings screen reads it when `EventBus.language_changed` or
   `EventBus.setting_changed` fires and shows or clears `settings.error.not_saved`.
4. **Screen sections.** A section is a scene whose root extends `SettingsSection`
   (`game/ui/settings/settings_section.gd`), which supplies `get_title()` (a `tr()` literal) and
   receives the `Localization` and `Settings` nodes from the shell. The shell builds its sections
   from `game/ui/settings/settings_sections.tres` (a `SettingsSectionList` resource: ordered
   `Array[PackedScene]`) plus any section passed to `add_section()` at run time. A later issue adds
   a section by adding its scene to that list; the shell scripts and scene do not change.

## Alternatives considered

- **Sections listed in the shell scene or script:** every later issue would edit the shell, which
  AC 4 of #20 forbids.
- **Sections register themselves in a global registry autoload:** a second autoload and
  load-order coupling for no gain over a resource list.
- **No `Settings` autoload, each feature makes its own `SettingsService`:** two services would
  hold different session values for the same key and the change signal would have no single
  source.
- **A new `save_failed` signal or a changed return code for `set_language`:** a new return code
  breaks B07's contract; an extra signal adds an ordering question between two signals for one
  change. A last-error query read in the existing change handlers has neither problem.

## Consequences

- `game/project.godot` gains the `Settings` autoload; the pull request goes through the owner gate.
- #81, B14, B15 and photo mode declare their `SettingKey` constants, read with
  `Settings.get_value(key)`, write with `Settings.set_value(key, value)`, listen to
  `EventBus.setting_changed`, and add their section scene to `settings_sections.tres`.
- Settings are global session state outside the model: no Command, no undo entry, never part of a
  save file.
- A later "restore defaults" (#81) writes each key's default through `set_value`; it needs no new
  plumbing.
