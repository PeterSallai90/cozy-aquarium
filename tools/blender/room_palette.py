"""Shared palette atlas of the room, the cabinet, the lamp and the tank frame (#22).

Stdlib only, so the generators and the local unittests can import it outside Blender.

- One atlas for the four assets (technical plan of #22):
  ``game/assets/room/room_palette_atlas.png``, written by ``generate_room.py``. The tank frame
  uses the same cells through this module.
- 8 x 8 cells of 16 px (128 x 128 px, inside the 256 px limit of docs/art-style.md), one flat
  colour per cell, row 0 at the top of the PNG. Godot samples it with UV2 (glTF TEXCOORD_1) and a
  nearest filter; every face of UV1 collapses onto the centre of one cell.
- Row 7 (the bottom row, Godot UV2.y >= ``EMISSIVE_V_MIN``) holds the emissive cells. The palette
  shader (``game/shaders/palette_atlas.gdshader``) lights them through its ``emission_from_v``
  parameter; no other row emits.
- Colours are impressions of the mood board palette words (docs/mood-board.md): "warm brown"
  wood, "dusk violet" room, "rose-gold lamp glow". The values are sRGB.
"""

from __future__ import annotations

import struct
import zlib

GRID = 8
CELL_PX = 16
EMISSIVE_ROW = 7
EMISSIVE_V_MIN = EMISSIVE_ROW / GRID

# Named cells: (column, row from the top).
WOOD_SHADOW = (0, 0)  # plinth, the recessed kick board
WOOD_CARCASS = (1, 0)  # cabinet sides and the carcass front behind the door gap
WOOD_DOOR = (2, 0)  # door panels
WOOD_TOP = (3, 0)  # cabinet top slab
WALL = (0, 1)  # dusk violet walls
FLOOR = (1, 1)  # deep plum-brown floor
SKIRTING = (2, 1)  # muted light violet skirting board
FLOOR_EDGE = (3, 1)  # cut-away edge of the floor slab
TRIM = (0, 2)  # tank rim trim, satin near-black
LAMP_BODY = (1, 2)  # lamp bar housing
LAMP_BRACKET = (2, 2)  # lamp feet
KNOB = (3, 2)  # muted rose-gold brass door knobs
GLASS = (4, 2)  # pale green glass (the placeholder glass material does not sample the atlas)
LAMP_LED = (0, EMISSIVE_ROW)  # warm LED diffuser under the lamp bar

PALETTE: tuple[tuple[int, ...], ...] = (
    # row 0: warm brown woods, dark to light (cells 4 to 7 are a spare lighter ramp)
    (0x2E1C14, 0x5E3A28, 0x6E4430, 0x7C4D34, 0x93603F, 0xA8744E, 0xBE8C63, 0xD3A87F),
    # row 1: room (wall, floor, skirting, slab edge), then a spare dusk ramp
    (0x5A4A78, 0x3E2E36, 0x7A6C90, 0x2A1E26, 0x2E2640, 0x3A3150, 0x584C70, 0x7A6E92),
    # row 2: tank trim, lamp, brass knob, glass, then spare neutrals
    (0x18181D, 0x26262C, 0x34343C, 0xB8875C, 0xBFDCD2, 0x4A4A52, 0x6E6E76, 0x9A9AA2),
    # rows 3 to 6: spare ramps (unused in #22, kept so a new cell needs no new atlas size)
    (0x2C3E50, 0x3E5C70, 0x5A8096, 0x7FA6B8, 0x2F4A3A, 0x46694F, 0x648C68, 0x8AB08A),
    (0x5A2E2E, 0x7E4040, 0xA45C52, 0xC88068, 0x6A5A3A, 0x8C7A50, 0xB09C6C, 0xD2C090),
    (0x202020, 0x404040, 0x606060, 0x808080, 0xA0A0A0, 0xC0C0C0, 0xE0E0E0, 0xF4F0E8),
    (0x3A2A40, 0x544060, 0x705880, 0x8C74A0, 0x40302A, 0x5C463A, 0x7A6050, 0x987C68),
    # row 7: emissive cells (warm LED, then spares)
    (0xFFE4C4, 0xFFD2A8, 0xFFC08C, 0xFFF0DC, 0xFFE4C4, 0xFFD2A8, 0xFFC08C, 0xFFF0DC),
)


def atlas_png() -> bytes:
    """128 x 128 px, 8-bit RGB, row 0 at the top; deterministic (no Blender colour management)."""
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
