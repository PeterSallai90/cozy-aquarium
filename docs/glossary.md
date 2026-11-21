# Glossary

Being drafted with the AI BA, see [docs/architecture.md](architecture.md) for now.

**Category**: the group an item belongs to in the catalog and the item browser: Rocks, Wood, Ornaments or Plants. It comes from the item's `category` field, never from the folder it is stored in. The category follows what the item is made of; caves go in Rocks (real rock) or Ornaments (made of ceramic or resin).

**Item**: a rock, piece of wood, ornament or live plant that the player places in the tank. Every item has a catalog id (the `catalog_id` of a placed item). Fish are not items. `decor` is only the folder name for rocks, wood and ornaments; there is no category called Decoration.

**Substrate**: what covers the tank floor. Mode 1 has five types (sand, gravel, pebbles, black sand, coloured gravel); the player picks a type and one colour from its short swatch list. Each type is a real 3D bed of settled grains or stones with a fixed depth (3 cm sand, 4 cm gravel, 6 cm pebbles); items stand on its surface.

**Swatch**: one catalog colour choice of a substrate type or a colourable item. A substrate type's first swatch is its default colour; a colourable item's swatches are alternatives to its original colour.

**Original colour**: the colour of the item's own model, shown by the "Original colour" choice and never listed as a swatch.

**Footprint**: the rectangle an item covers on the floor: its catalog `footprint_cm` width (x) by depth (z), times the item's size factor, turned with the item around its origin. The origin is the centre of the footprint. `footprint_cm.y` is the item's height. Placement validity uses only this rectangle and height, never the exact mesh shape, so a round stone blocks its whole rectangle.

**Interior**: the inside of the tank glass, `interior_size_m` of the tank (width, height, depth; the glass thickness is already left out), centred on the middle of the tank floor. A placed item's footprint stays inside it, and its top stays under the interior height.

**Surface**: the nominal height of the substrate bed above the tank floor (`SubstrateSurface`), the mean top of the settled grains, not any single grain or stone. Items rest on it; an item's top is the surface at its origin plus its height.

**Touching**: two footprints, or a footprint and the glass, that share an edge or a corner without overlapping. Touching is allowed. A tolerance of 0.1 mm decides it, so exact contact is never refused by rounding; the same tolerance applies to the interior height and the water line.
