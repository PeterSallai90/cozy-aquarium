# ADR 0014: Derived default fish name and the add and remove fish commands

- Status: Accepted (pull request for #36; gated by `needs:owner`)
- Date: 2026-11-23
- Decision log reference: none (no row D1 to D21 changes). Implements the naming half of D20
  ("every fish has a name") as decided on #17 (Q20) and #36 (Q10, Q11, Q12); adds one salt to the
  `FishHash` salt register of ADR 0013 rule 6.
- Issue: #36 (B25a add and remove fish UI); used by #164 (B25b name labels), #69 (B44 renaming),
  #35 (B24 personality salts) and any save format migration that touches fish names

## Context

D20 says every fish has a name. The #17 decision (Q20) keeps the save language-neutral: a new
fish stores an empty `nickname`, and the shown name is derived from the uid when the nickname is
empty. Once a save exists that relies on a derived name, changing the formula, the salt, the list
length or the list order silently renames fish in existing saves. The decision is therefore hard
to reverse and needs a written contract that the golden test and the reviewer can point to.

#36 also brings the first real fish commands. Until now only test helpers in
`game/tests/helpers/commands/` added and removed fish.

## Decision

1. **Pure default-name function.** `FishDefaultName` (`game/model/fish_default_name.gd`, static,
   pure, no Node, no `tr()`):
   - `const COUNT: int = 30`, `const KEY_PREFIX: String = "fish.default_name."`;
   - `static func index_for_unit(unit: float) -> int` returns
     `clampi(floori(unit * COUNT), 0, COUNT - 1) + 1` (1 to 30; `FishHash.unit` is in [0, 1),
     the clamp only guards the top edge);
   - `static func key_at(index: int) -> String` returns `KEY_PREFIX + "%02d" % index`;
   - `static func key_for(uid: String) -> String` returns
     `key_at(index_for_unit(FishHash.unit(uid, FishHash.SALT_DEFAULT_NAME)))`;
   - `static func all_keys() -> PackedStringArray` returns the 30 keys in order 01 to 30.
2. **Salt.** `FishHash.SALT_DEFAULT_NAME = "fish.name.default"`. The `fish.name.` family is
   reserved for names; #35 and later issues pick salts outside it, and no salt is ever reused for
   a second purpose.
3. **Shown name.** `nickname` when it is not empty, else `tr(FishDefaultName.key_for(uid))`. The
   translation happens in the presentation layer (`FishNameText`, `game/ui/fish/`), so a derived
   name follows the game language and a typed nickname does not. Duplicate names are allowed.
   Nothing is written into the model or the save; the save format does not change.
4. **Freeze.** The list (count, key order, salt, formula) is frozen at the earlier of the owner's
   approval comment on #36 or #164, or the v0.1 tag on main. Before that, an edit is legal only
   with the golden test updated in the same pull request and the words "pre-release name list
   edit" in its description. The golden test (`game/tests/model/test_fish_default_name_golden.gd`)
   carries the rule and a `STATE:` line (`open until owner approval or v0.1 tag`, later
   `frozen <date>`). After the freeze only typo or grammar fixes of a `.po` text are allowed; any
   other change needs a `format_version` bump whose migration first writes the old derived name
   into `nickname`.
5. **Fish commands.** `AddFishCommand` and `RemoveFishCommand` in `game/model/` follow the
   Command rules:
   - `AddFishCommand.new(model, fish)` receives the complete `FishInstance` (rule 3). The caller
     builds it with `static func make_fish(uid, species, rng) -> FishInstance`: `species_id` from
     `species.id`, `variant` from `rng.randi_range(0, n - 1)` over `colour_variants.size()` (0
     when the list is empty), empty `nickname`. Only the id and the variant count are read, never
     a Mode 2 field. The uid comes from `UidGenerator.generate(model)` in the caller. do() refuses
     a null fish, an empty uid or a uid in use with the model untouched, so the history records
     nothing; it appends at the end on the first do() and re-inserts at the same index on redo.
   - `RemoveFishCommand.new(model, uid)` records the instance and its index in do() and
     re-inserts the same instance at that index in undo(); an unknown uid is refused.

## Alternatives considered

- **Store the default name in `nickname` on add.** Simple, but the name would be frozen in the
  language of the moment and would need no formula; rejected by the #17 decision (language-neutral
  saves, no new field).
- **Choose the name in the UI with `randi()`.** Not repeatable across load; rejected.
- **Reuse a resting-pose salt.** Couples name and position: two fish at the same x would share a
  name pattern; rejected by ADR 0013 rule 6 (one salt per use).
- **Keep the test helper commands as the real ones.** They carry test counters and have no
  `class_name`; the real commands live in `game/model/` with the other commands.

## Consequences

- #164 labels and #69 renaming reuse `FishNameText.shown_name()`; neither changes the formula.
- A list edit after the freeze is a save format change with a migration, never a quiet edit.
- The 30 keys exist only at run time and are listed in `game/localization/extra_keys.txt`.
- The test helper commands stay for the history tests; their preload constants in
  `game/tests/model/test_command_history.gd` are renamed so they do not shadow the new global
  classes.
