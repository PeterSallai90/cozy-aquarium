# Glossary

Being drafted with the AI BA, see [docs/architecture.md](architecture.md) for now.

**Category**: the browser group of an item: Rocks, Wood, Ornaments or Plants. It comes from the item's `category` field, never from the folder it is stored in.

**Item**: one placeable thing from the catalog: a rock, a piece of wood, an ornament (a cave, a ceramic or resin piece, a shell) or a live plant. `decor` is only the folder name for rocks, wood and ornaments; there is no category called Decoration.

**Substrate**: what covers the tank floor. Mode 1 has five types (sand, gravel, pebbles, black sand, coloured gravel); the player picks a type and one colour from its short swatch list. Each type is a real 3D bed of settled grains or stones with a fixed depth (3 cm sand, 4 cm gravel, 6 cm pebbles); items stand on its surface.

**Swatch**: one catalog colour choice of a substrate type. Each type has a short list of swatches, the first is its default colour.
