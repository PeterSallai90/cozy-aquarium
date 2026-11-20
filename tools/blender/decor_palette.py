"""Shared palette atlas of the decor items: rocks, wood and ornaments (#157).

Stdlib only, so the generator and the local unittests can import it outside Blender.

- One atlas for every decor item: ``game/assets/items/decor_palette_atlas.png``, written by
  ``generate_decor.py``. It is not the room atlas (BA decision Q14 on #157): the room atlas
  belongs to ``generate_room.py``, and sharing it would tie the decor UVs to another generator.
- 8 x 8 cells of 16 px (128 x 128 px, inside the 256 px limit of docs/art-style.md), one flat
  colour per cell, row 0 at the top of the PNG. Godot samples it with UV2 (glTF TEXCOORD_1) and a
  nearest filter; every face of UV1 collapses onto the centre of one cell (docs/art-style.md,
  "Generator conventions").
- Rule: shipped cells never move. A new colour takes a spare cell only, so the UVs of committed
  models never shift. The spare cells hold a neutral grey until an issue fills them (#42).
- No emissive row: decor does not glow.
- One cell per surface kind. Variation (crevice darkening, grain, the dark inside of the amphora)
  comes from vertex colours, which the decor material multiplies in (``vertex_shade``).
- Colours (sRGB) and the measurable hooks of #157 AC 8, checked by the tests:
  ``STONE_GRANITE`` a calm grey granite (saturation at most 0.25, art-style rock range "grey");
  ``WOOD_DRIFT`` a warm Malaysian-driftwood brown (hue 15 to 40 degrees, value at most 0.6);
  ``TERRACOTTA`` a muted fired-clay orange-brown, more saturated than the stone and the wood and
  less saturated than the most saturated body cell of the proof fish (0.60). The exact shades are
  the owner's judgement on the pull request preview.
"""

from __future__ import annotations

import struct
import zlib

GRID = 8
CELL_PX = 16

# Named cells: (column, row from the top). Shipped cells never move.
STONE_GRANITE = (0, 0)  # river_stone: grey granite-type river cobble
WOOD_DRIFT = (1, 0)  # driftwood_branch: warm brown, barkless Malaysian-type driftwood
TERRACOTTA = (2, 0)  # clay_amphora: unglazed fired terracotta

SPARE = 0x808080  # neutral grey of the unused cells

PALETTE: tuple[tuple[int, ...], ...] = (
    # row 0: the starter set (stone, wood, terracotta), then spare cells
    (0x8A8781, 0x6E5640, 0xB0704F, SPARE, SPARE, SPARE, SPARE, SPARE),
    # rows 1 to 7: spare (kept so a new cell needs no new atlas size)
    (SPARE,) * GRID,
    (SPARE,) * GRID,
    (SPARE,) * GRID,
    (SPARE,) * GRID,
    (SPARE,) * GRID,
    (SPARE,) * GRID,
    (SPARE,) * GRID,
)


def atlas_png() -> bytes:
    """128 x 128 px, 8-bit RGB, row 0 at the top; deterministic (no Blender colour management).

    The encoder is the one of ``room_palette.atlas_png`` (copied, so the room atlas bytes cannot
    change through this module)."""
    size = GRID * CELL_PX
    rows: list[bytes] = []
    for y in range(size):
        line = bytearray()
        for x in range(size):
            rgb = PALETTE[y // CELL_PX][x // CELL_PX]
            line += bytes(((rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF))
        rows.append(b"\x00" + bytes(line))

    def chunk(tag: bytes, payload: bytes) -> bytes:
        crc = zlib.crc32(tag + payload) & 0xFFFFFFFF
        return struct.pack(">I", len(payload)) + tag + payload + struct.pack(">I", crc)

    header = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(b"".join(rows), 9))
        + chunk(b"IEND", b"")
    )


def cell_uv(cell: tuple[int, int]) -> tuple[float, float]:
    """Blender UV1 of a cell centre. The glTF exporter flips V, so Godot UV2 row = PNG row."""
    column, row = cell
    if not (0 <= column < GRID and 0 <= row < GRID):
        raise ValueError(f"atlas cell {cell} is outside the {GRID} x {GRID} grid")
    return ((column + 0.5) / GRID, 1.0 - (row + 0.5) / GRID)
