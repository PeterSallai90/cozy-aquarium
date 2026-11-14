# ADR 0010: Substrate catalog, session default and post-load normalisation

- Status: Proposed (accepted when the #28 pull request merges; gated by `needs:owner`)
- Date: 2026-11-14
- Decision log reference: none (no row in the decisions table changes); refines the "Substrate"
  and "Save/load" rows of Core systems and the "Catalog schema" section in docs/architecture.md
- Issue: #28 (B17 substrate types with colour selection); BA decisions Q2, Q3, Q4, Q11 and the
  Definition of Ready on #28; later users: #29 (sculpt), B27 save slots (the player-facing load),
  the fish and decor catalogs (#23 and later)

## Context

#28 adds the first catalog id in the save that the game must always resolve: `substrate.id`.
The model (`AquariumModel`) and the codec (`SaveCodec`) are pure data and catalog-free; the model
starts with substrate id `""` and `Color.WHITE`, and a load is all or nothing. The BA decisions
require:

- a new aquarium starts with Sand (`sand_fine`) and its catalog `default_colour`, with an empty
  undo history (Q3, AC 3);
- a save whose substrate id is empty or unknown loads as Sand with its default colour, logs one
  warning, adds no history entry and never rewrites the file (Q3, AC 11);
- a saved colour that is not a swatch of its type is kept (Q4);
- the set-substrate Command accepts only catalog swatches (Q2, AC 10);
- the five types are all chemically inert, which would equal a zero enum default (Q11).

Constraints found in the code on develop (f10082a):

- `tests/test_apply_mutator_scan.gd` forbids every `AquariumModel.apply_*` call outside
  `res://model/` (and tests). A default or normalise step in `game/catalog`, `game/scenes` or
  `game/systems` would fail it.
- `ChangeTankCommand` (game/model) already reads `TankCatalog`, so model-folder code that reads a
  catalog object (RefCounted data, no Node) is established; only `AquariumModel` and the codec are
  catalog-free.
- `docs/architecture.md` stores colours at 8 bits per channel; a catalog `Color` written with
  arbitrary floats would not compare equal to the same colour after a save and load.
- ADR 0004: an unexpected `push_warning` fails the test run. Many existing tests load saves or
  build the room with substrate ids that are not in the catalog (`fine_sand`, `sand`, `""`).

## Decision

1. **Construction, not change.** Setting the session default on a brand-new model before any
   system is connected, and normalising a freshly decoded model before it replaces the live one,
   are part of building a model, like the codec filling a fresh model. They are not changes of the
   live model, so they do not go through a Command and never touch the undo history. Every change
   of the live model's substrate after that goes through `SetSubstrateCommand`.
2. **One place writes outside a Command.** Both steps live in `game/model/substrate_setup.gd`
   (`class_name SubstrateSetup`, static functions only, no state):
   - `apply_default(model: AquariumModel, catalog: SubstrateCatalog) -> void`
   - `normalise(model: AquariumModel, catalog: SubstrateCatalog) -> bool`
   They are the only non-Command callers of `apply_set_substrate` in the game (named exceptions of
   AC 18 on #28). `tests/test_apply_mutator_scan.gd` stays unchanged. `AquariumModel` and
   `SaveCodec` stay catalog-free and unchanged.
3. **Catalog knowledge stays in the catalog.** `SubstrateCatalog` owns `DEFAULT_ID = &"sand_fine"`
   (a reference to a catalog entry, like `AquariumModel.DEFAULT_TANK_ID`), the default definition,
   the swatch tests and the pick rule (`colour_for_pick`). `SubstrateSetup` and the Command only
   ask it; neither holds a colour value.
4. **Where normalisation runs.** `SaveStore` takes an optional `SubstrateCatalog`
   (`SaveStore.new(clock, codec, substrates)`). When it has one, `load_into()` calls
   `SubstrateSetup.normalise(decoded_model, substrates)` after a successful decode and before
   `model.reset_from()`, so the live model gets exactly one `model_reset` and no
   `substrate_changed`, the history is cleared as before and the file is never written. Codec-level
   and store-level tests that pass no catalog keep their arbitrary ids and their golden files.
   Every game-side construction of a `SaveStore` that loads a save (the player-facing load of B27)
   passes the catalog; the B27 plan must carry a test for it.
5. **Fallback rule.** `normalise` replaces an empty or unknown id with `DEFAULT_ID` and that
   type's `default_colour`, logs exactly one `push_warning` that contains
   `SubstrateSetup: unknown substrate id` and the offending id, and returns true. A known id keeps
   its colour, swatch or not (a missing colour decodes to `Color.WHITE` and is kept). It never
   adds history entries.
6. **The view never validates.** The room shows the look of the model's substrate; for an empty or
   unknown id it shows the default type with its default colour and logs nothing. The warning
   belongs to `normalise` only, so a load warns once and room tests with catalog-free models stay
   silent.
7. **Catalog colours are 8-bit exact.** Every `default_colour` and swatch in a substrate `.tres` is
   an exact 8-bit colour (it survives `#RRGGBB` encoding unchanged; enforced by a catalog test).
   Swatch matching and the Command's "same as current" test compare colours with
   `Color.to_rgba32()`, the same precision as the save file.
8. **Enum sentinel for Mode 2 catalog enums.** A Mode 2 enum whose correct value can be its first
   value starts with `UNSET = 0` (`SubstrateDefinition.WaterEffect`: `UNSET = 0, INERT = 1,
   RAISES_SLIGHTLY = 2, RAISES = 3`), so "filled" is testable as "not UNSET". Enum values are stored
   as integers in `.tres` files: they are never renumbered; new values are only appended (for
   example a later `LOWERS_SLIGHTLY = 4`). New catalog schemas follow the same rule for new Mode 2
   enums; existing enums are not changed by this ADR.

## Alternatives considered

- **Default and normalise in `SubstrateCatalog` (game/catalog), as the Q3 example named them.**
  Rejected: it needs an exception in `tests/test_apply_mutator_scan.gd`, and it moves model writes
  into the catalog folder. The decision keeps the substance of Q3 (catalog knowledge in the
  catalog, model and codec catalog-free) with a stronger invariant: `apply_*` stays inside
  `game/model`.
- **Default inside `AquariumModel` (start with `sand_fine`).** Rejected: hard-codes catalog data in
  the model (CLAUDE.md) and breaks the Q3 decision and `test_aquarium_model.gd`.
- **Normalise in the codec.** Rejected: the codec is catalog-free and its golden files would
  change; the format does not change.
- **Fallback in the view only (as the tank id does today in `RoomCorner`).** Rejected for the
  substrate: the chooser and the Command would then work on an id that has no catalog entry, and
  the BA decision requires the model to show `sand_fine` after load. The tank id keeps its current
  view fallback; moving it to a normalise step is a possible later issue, not part of #28.
- **Required catalog argument in `SaveStore`.** Rejected for now: every existing store test would
  change, and no game code loads a save yet. Point 4 makes B27 responsible.

## Consequences

- One new model-folder file with two static functions; `AquariumModel`, `SaveCodec`, the save
  format, `format_version` and the golden save files do not change.
- The undo history stays empty after start and after load; the first player edit is the first
  entry.
- A forgotten catalog in a future load path would skip the fallback silently. B27 must test it;
  the room still shows the default look, so the player never sees a broken floor.
- The 8-bit rule and the enum rule apply to every later catalog colour and Mode 2 enum that is
  compared with saved data or tested for "filled".
