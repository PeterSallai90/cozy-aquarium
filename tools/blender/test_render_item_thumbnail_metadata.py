"""Local tests for the PNG metadata strip of the item thumbnail script (#153, AC 2). Stdlib only, no
Blender. Not run in CI (ci.yml discovers tools/scripts only). Run from the repository root:

    python -m unittest discover -s tools/blender -p "test_*.py"

Cycles writes its render statistics (render time and so on) as PNG tEXt chunks even with every
stamp flag off, so two identical renders differ in their bytes. ``strip_png_metadata`` keeps the
critical chunks and the colour chunks (sRGB, gAMA, cHRM) and drops every other ancillary chunk;
the pixel data must stay unchanged.
"""

from __future__ import annotations

import struct
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))

import blender_common  # noqa: E402
import render_item_thumbnail as thumb  # noqa: E402


def _chunk(kind: bytes, data: bytes) -> bytes:
    crc = zlib.crc32(kind + data) & 0xFFFFFFFF
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", crc)


def _png(text: bytes) -> bytes:
    """A 2 x 2 RGBA PNG with colour chunks, metadata chunks holding ``text`` and two IDAT chunks."""
    raw = b"".join(b"\x00" + bytes([10, 20, 30, 0, 40, 50, 60, 255]) for _ in range(2))
    packed = zlib.compress(raw)
    return (
        thumb.PNG_SIGNATURE
        + _chunk(b"IHDR", struct.pack(">IIBBBBB", 2, 2, 8, 6, 0, 0, 0))
        + _chunk(b"sRGB", b"\x00")
        + _chunk(b"gAMA", struct.pack(">I", 45455))
        + _chunk(b"cHRM", bytes(32))
        + _chunk(b"eXIf", b"MM\x00*" + bytes(8))
        + _chunk(b"pHYs", struct.pack(">IIB", 2834, 2834, 1))
        + _chunk(b"tEXt", b"cycles.ViewLayer.render_time\x00" + text)
        + _chunk(b"tIME", bytes(7))
        + _chunk(b"IDAT", packed[:5])
        + _chunk(b"IDAT", packed[5:])
        + _chunk(b"IEND", b"")
    )


def _kinds(data: bytes) -> list[bytes]:
    kinds = []
    offset = len(thumb.PNG_SIGNATURE)
    while offset < len(data):
        length, kind = struct.unpack(">I4s", data[offset : offset + 8])
        kinds.append(kind)
        offset += 12 + length
    return kinds


class StripPngMetadataTest(unittest.TestCase):
    def setUp(self) -> None:
        self._temp = tempfile.TemporaryDirectory()
        self.addCleanup(self._temp.cleanup)
        self.folder = Path(self._temp.name)

    def _strip(self, data: bytes, name: str = "t.png") -> bytes:
        path = self.folder / name
        path.write_bytes(data)
        thumb.strip_png_metadata(path)
        return path.read_bytes()

    def test_keeps_critical_and_colour_chunks_only(self) -> None:
        kinds = _kinds(self._strip(_png(b"00:00.27")))
        self.assertEqual(
            kinds, [b"IHDR", b"sRGB", b"gAMA", b"cHRM", b"IDAT", b"IDAT", b"IEND"]
        )

    def test_two_renders_with_different_times_become_identical(self) -> None:
        first = self._strip(_png(b"00:00.27"), "a.png")
        second = self._strip(_png(b"00:01.93"), "b.png")
        self.assertEqual(first, second)

    def test_pixels_and_measurement_are_unchanged(self) -> None:
        original = self.folder / "o.png"
        original.write_bytes(_png(b"x"))
        before = thumb.measure_png(original)
        after_path = self.folder / "s.png"
        after_path.write_bytes(_png(b"x"))
        thumb.strip_png_metadata(after_path)
        self.assertEqual(thumb.measure_png(after_path), before)
        self.assertEqual(before.alpha_box, (1, 0, 1, 1))

    def test_result_still_has_the_png_magic(self) -> None:
        self.assertTrue(self._strip(_png(b"x")).startswith(blender_common.PNG_MAGIC))

    def test_not_a_png_is_an_error(self) -> None:
        path = self.folder / "n.png"
        path.write_bytes(b"glTF" + bytes(16))
        with self.assertRaises(blender_common.GeneratorError):
            thumb.strip_png_metadata(path)


if __name__ == "__main__":
    unittest.main()
