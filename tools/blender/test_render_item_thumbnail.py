"""Local tests for the item thumbnail script (#153): argument parsing, the item id rule, the output
path, the framing maths, the PNG measurement and the all-or-nothing write. Stdlib only, no Blender.
Not run in CI (ci.yml discovers tools/scripts only). Run from the repository root:

    python -m unittest discover -s tools/blender -p "test_*.py"

Contract fixed by these tests (technical-artist implements it in render_item_thumbnail.py; the
module must import without Blender, ``bpy`` is imported lazily inside the render part):

- ``validate_id(item_id) -> str`` returns the id, or raises ``blender_common.GeneratorError`` with
  a message that holds ``repr(item_id)``. The rule is the one of ItemCatalog.is_valid_id (#152):
  ``fullmatch`` of ``[a-z][a-z0-9_]{0,47}`` and not a Windows device name (con, prn, aux, nul,
  com1 to com9, lpt1 to lpt9). VALID_IDS and INVALID_IDS below are the list of
  game/tests/helpers/item_api.gd; a test reads that file and compares, so the lists cannot drift.
- ``parse_args(argv) -> argparse.Namespace`` reads the part of argv after ``--``: ``--model``
  (Path, required), ``--id`` (str, required), ``--out`` (Path, default DEFAULT_OUT, which is
  game/assets/items/thumbnails). A missing or unknown argument exits with a non-zero SystemExit.
- ``output_path(out_dir, item_id) -> Path`` is ``out_dir / f"{item_id}.png"`` after validate_id.
- ``view_basis(azimuth_deg, elevation_deg) -> (right, up, toward_camera)``: unit vectors, in the
  Blender frame (model front is -Y, Z up), ``right x up == toward_camera``. Azimuth 0, elevation 0
  looks along +Y; a positive azimuth moves the camera toward +X; a positive elevation looks down.
- ``fit_frame(points, azimuth_deg, elevation_deg, size_px=256, margin_px=16) -> Framing`` (frozen
  dataclass with target, camera_location, ortho_scale, clip_start, clip_end, basis). Orthographic:
  the box of the projected points is the box of the silhouette. Its longer side is
  ``size_px - 2 * margin_px`` pixels and its centre is the frame centre; ``ortho_scale`` is
  ``long * size_px / (size_px - 2 * margin_px)``. No points, a NaN or infinite coordinate, or a
  silhouette of zero size (a point, an edge-on line) raise GeneratorError.
- ``to_pixels(framing, point) -> (x, y)`` in the default 256 px frame, x right, y down.
- ``measure_png(path) -> PngFacts`` with width, height, bit_depth, colour_type, corner_alphas
  (top left, top right, bottom left, bottom right), alpha_box ``(x0, y0, x1, y1)`` as inclusive
  pixel indices of the pixels with alpha above 0 (or None), long_side (``max(x1 - x0 + 1,
  y1 - y0 + 1)``) and centre (``((x0 + x1 + 1) / 2, (y0 + y1 + 1) / 2)``, the frame centre is
  128, 128). All five PNG row filters decode. Only 8-bit RGBA is decoded; other types are
  reported. An interlaced or non-PNG file raises GeneratorError.
- The script reuses blender_common.write_group and main (no second implementation).

Not testable without Blender (manual part of the test report, by the technical-artist in the PR):
AC 1 on the real render (size, mode, corner alpha via the script's printed line), AC 2 (two
SHA-256 hashes of two runs), AC 3 on the six preview models, AC 4 (a glb with its own camera,
light and world, and a two-mesh glb), the Blender side of AC 5 and 6 (missing file, a non-glb
file, only an empty or hidden mesh, a read-only folder, exit codes and messages) and AC 8 (the
review checklist).
"""

from __future__ import annotations

import ast
import contextlib
import io
import math
import re
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
REPO = TOOLS.parent.parent
sys.path.insert(0, str(TOOLS))

import blender_common  # noqa: E402
import render_item_thumbnail as thumb  # noqa: E402

ITEM_API = REPO / "game" / "tests" / "helpers" / "item_api.gd"

VALID_IDS = [
    "a",
    "rock_1",
    "driftwood_large",
    "moss_ball",
    "a2345678901234567890123456789012345678901234567x",
]
INVALID_IDS = [
    "",
    "Rock",
    "1rock",
    "_rock",
    "rock-1",
    "rock 1",
    "rock.png",
    "rock/x",
    "rock\n",
    "a23456789012345678901234567890123456789012345678x",
    "con",
    "nul",
    "aux",
    "prn",
    "com1",
    "lpt9",
    "rocké",
]
# Valid although they start with a device name (test_item_catalog_skips.gd).
NEAR_MISS_IDS = ["console", "nullable", "com10", "auxiliary", "prn_a", "lpt0"]
DEVICE_NAMES = (
    ["con", "prn", "aux", "nul"]
    + [f"com{i}" for i in range(1, 10)]
    + [f"lpt{i}" for i in range(1, 10)]
)

AZIMUTH = 35.0
ELEVATION = 25.0


def _box(centre: tuple[float, float, float], size: tuple[float, float, float]) -> list:
    cx, cy, cz = centre
    hx, hy, hz = (s / 2 for s in size)
    return [
        (cx + sx * hx, cy + sy * hy, cz + sz * hz)
        for sx in (-1, 1)
        for sy in (-1, 1)
        for sz in (-1, 1)
    ]


def _dot(a, b) -> float:
    return sum(x * y for x, y in zip(a, b, strict=True))


def _cross(a, b):
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


# --- synthetic PNG writer (the test's own encoder) ---


def _chunk(kind: bytes, data: bytes) -> bytes:
    crc = zlib.crc32(kind + data) & 0xFFFFFFFF
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", crc)


def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def _filter_row(kind: int, row: bytes, prior: bytes, bpp: int) -> bytes:
    out = bytearray()
    for i, value in enumerate(row):
        left = row[i - bpp] if i >= bpp else 0
        up = prior[i]
        up_left = prior[i - bpp] if i >= bpp else 0
        if kind == 0:
            predicted = 0
        elif kind == 1:
            predicted = left
        elif kind == 2:
            predicted = up
        elif kind == 3:
            predicted = (left + up) // 2
        else:
            predicted = _paeth(left, up, up_left)
        out.append((value - predicted) & 0xFF)
    return bytes([kind]) + bytes(out)


def encode_png(
    pixels: list,
    filters: list[int] | None = None,
    colour_type: int = 6,
    interlace: int = 0,
) -> bytes:
    """RGBA rows (or RGB rows when colour_type is 2), one filter type per row (default None)."""
    height, width = len(pixels), len(pixels[0])
    bpp = 4 if colour_type == 6 else 3
    raw = bytearray()
    prior = bytes(width * bpp)
    for y, row_pixels in enumerate(pixels):
        row = bytes(c for p in row_pixels for c in p[:bpp])
        kind = filters[y % len(filters)] if filters else 0
        raw += _filter_row(kind, row, prior, bpp)
        prior = row
    ihdr = struct.pack(">IIBBBBB", width, height, 8, colour_type, 0, 0, interlace)
    return (
        b"\x89PNG\r\n\x1a\n"
        + _chunk(b"IHDR", ihdr)
        + _chunk(b"IDAT", zlib.compress(bytes(raw)))
        + _chunk(b"IEND", b"")
    )


def frame(size: int = 256, block: tuple[int, int, int, int] | None = None, corners=None) -> list:
    """Transparent square with an opaque block (x0, y0, x1, y1 inclusive) and optional corners."""
    rows = [[(0, 0, 0, 0)] * size for _ in range(size)]
    if block:
        x0, y0, x1, y1 = block
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                rows[y][x] = (200, 120, 40, 255)
    if corners:
        for (x, y), alpha in corners.items():
            rows[y][x] = (10, 20, 30, alpha)
    return rows


class IdRuleTest(unittest.TestCase):
    def test_valid_ids_are_accepted(self) -> None:
        for item_id in VALID_IDS + NEAR_MISS_IDS:
            with self.subTest(item_id=item_id):
                self.assertEqual(thumb.validate_id(item_id), item_id)

    def test_invalid_ids_are_rejected_and_named_in_the_message(self) -> None:
        for item_id in INVALID_IDS:
            with self.subTest(item_id=item_id):
                with self.assertRaises(blender_common.GeneratorError) as caught:
                    thumb.validate_id(item_id)
                self.assertIn(repr(item_id), str(caught.exception))

    def test_every_device_name_is_rejected(self) -> None:
        for name in DEVICE_NAMES:
            with self.subTest(name=name):
                with self.assertRaises(blender_common.GeneratorError):
                    thumb.validate_id(name)

    def test_length_limit_is_48_characters(self) -> None:
        self.assertEqual(len(VALID_IDS[-1]), 48)
        self.assertEqual(len(INVALID_IDS[9]), 49)

    def test_python_lists_equal_the_gdscript_lists(self) -> None:
        text = ITEM_API.read_text(encoding="utf-8")

        def literals(name: str) -> list[str]:
            block = re.search(rf"const {name}[^=]*=\s*\[(.*?)\]", text, re.DOTALL)
            self.assertIsNotNone(block, f"{name} not found in item_api.gd")
            found = re.findall(r'"((?:[^"\\]|\\.)*)"', block.group(1))
            return [ast.literal_eval(f'"{item}"') for item in found]

        self.assertEqual(literals("VALID_IDS"), VALID_IDS)
        self.assertEqual(literals("INVALID_IDS"), INVALID_IDS)


class ArgsAndPathTest(unittest.TestCase):
    BLENDER = ["blender", "--background", "--python", "render_item_thumbnail.py", "--"]

    def _parse(self, *args: str):
        return thumb.parse_args(self.BLENDER + list(args))

    def test_model_id_and_out_are_read_after_the_double_dash(self) -> None:
        args = self._parse("--model", "rock.glb", "--id", "rock_1", "--out", "somewhere")
        self.assertEqual(args.model, Path("rock.glb"))
        self.assertIsInstance(args.model, Path)
        self.assertEqual(args.id, "rock_1")
        self.assertEqual(args.out, Path("somewhere"))
        self.assertIsInstance(args.out, Path)

    def test_out_defaults_to_the_thumbnail_folder(self) -> None:
        args = self._parse("--model", "rock.glb", "--id", "rock_1")
        self.assertEqual(args.out, thumb.DEFAULT_OUT)
        self.assertEqual(args.out, REPO / "game" / "assets" / "items" / "thumbnails")

    def test_missing_arguments_exit_non_zero(self) -> None:
        cases = [[], ["--model", "a.glb"], ["--id", "rock_1"], ["--model", "a.glb", "--id"]]
        for case in cases:
            with self.subTest(case=case):
                with contextlib.redirect_stderr(io.StringIO()):
                    with self.assertRaises(SystemExit) as caught:
                        self._parse(*case)
                self.assertNotIn(caught.exception.code, (0, None))

    def test_unknown_argument_exits_non_zero(self) -> None:
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as caught:
                self._parse("--model", "a.glb", "--id", "rock_1", "--bogus", "1")
        self.assertNotIn(caught.exception.code, (0, None))

    def test_output_path_is_folder_slash_id_png(self) -> None:
        out = Path("some") / "folder"
        self.assertEqual(thumb.output_path(out, "rock_1"), out / "rock_1.png")

    def test_output_path_rejects_a_bad_id(self) -> None:
        for item_id in ("Rock", "rock/x", "con", ""):
            with self.subTest(item_id=item_id):
                with self.assertRaises(blender_common.GeneratorError):
                    thumb.output_path(Path("out"), item_id)


class ViewBasisTest(unittest.TestCase):
    def test_vectors_are_unit_and_orthogonal(self) -> None:
        right, up, toward = thumb.view_basis(AZIMUTH, ELEVATION)
        for vector in (right, up, toward):
            self.assertAlmostEqual(_dot(vector, vector), 1.0, places=9)
        self.assertAlmostEqual(_dot(right, up), 0.0, places=9)
        self.assertAlmostEqual(_dot(right, toward), 0.0, places=9)
        self.assertAlmostEqual(_dot(up, toward), 0.0, places=9)

    def test_right_cross_up_is_toward_camera(self) -> None:
        right, up, toward = thumb.view_basis(AZIMUTH, ELEVATION)
        for got, want in zip(_cross(right, up), toward, strict=True):
            self.assertAlmostEqual(got, want, places=9)

    def test_zero_angles_look_at_the_model_front_along_plus_y(self) -> None:
        right, up, toward = thumb.view_basis(0, 0)
        for got, want in zip(toward, (0, -1, 0), strict=True):
            self.assertAlmostEqual(got, want, places=9)
        for got, want in zip(right, (1, 0, 0), strict=True):
            self.assertAlmostEqual(got, want, places=9)
        for got, want in zip(up, (0, 0, 1), strict=True):
            self.assertAlmostEqual(got, want, places=9)

    def test_positive_elevation_puts_the_camera_above(self) -> None:
        _, up, toward = thumb.view_basis(AZIMUTH, ELEVATION)
        self.assertAlmostEqual(toward[2], math.sin(math.radians(ELEVATION)), places=9)
        self.assertGreater(up[2], 0.0)

    def test_positive_azimuth_moves_the_camera_toward_plus_x(self) -> None:
        _, _, toward = thumb.view_basis(AZIMUTH, ELEVATION)
        self.assertGreater(toward[0], 0.0)
        self.assertLess(toward[1], 0.0)
        expected = math.sin(math.radians(AZIMUTH)) * math.cos(math.radians(ELEVATION))
        self.assertAlmostEqual(toward[0], expected, places=9)


class FramingMathTest(unittest.TestCase):
    SHAPES = {
        "tiny_2cm": ((0.0, 0.0, 0.01), (0.02, 0.02, 0.02)),
        "round_12cm": ((0.3, -0.1, 0.06), (0.12, 0.12, 0.12)),
        "large_45cm": ((0.0, 0.0, 0.06), (0.45, 0.10, 0.12)),
        "tall_5x40cm": ((0.0, 0.0, 0.2), (0.05, 0.05, 0.40)),
        "flat_15x15x2cm": ((0.0, 0.0, 0.01), (0.15, 0.15, 0.02)),
    }

    def _pixel_box(self, framing, points):
        coords = [thumb.to_pixels(framing, p) for p in points]
        xs = [c[0] for c in coords]
        ys = [c[1] for c in coords]
        return min(xs), min(ys), max(xs), max(ys)

    def test_long_side_is_224_px_and_centred_for_every_shape(self) -> None:
        for name, (centre, size) in self.SHAPES.items():
            with self.subTest(shape=name):
                points = _box(centre, size)
                framing = thumb.fit_frame(points, AZIMUTH, ELEVATION)
                x0, y0, x1, y1 = self._pixel_box(framing, points)
                self.assertAlmostEqual(max(x1 - x0, y1 - y0), 224.0, delta=1e-6)
                self.assertAlmostEqual((x0 + x1) / 2, 128.0, delta=1e-6)
                self.assertAlmostEqual((y0 + y1) / 2, 128.0, delta=1e-6)
                self.assertGreaterEqual(min(x0, y0), 16.0 - 1e-6)
                self.assertLessEqual(max(x1, y1), 240.0 + 1e-6)

    def test_the_shorter_side_is_smaller_for_a_tall_item(self) -> None:
        points = _box(*self.SHAPES["tall_5x40cm"])
        framing = thumb.fit_frame(points, AZIMUTH, ELEVATION)
        x0, y0, x1, y1 = self._pixel_box(framing, points)
        self.assertAlmostEqual(y1 - y0, 224.0, delta=1e-6)
        self.assertLess(x1 - x0, 100.0)

    def test_ortho_scale_follows_the_long_side(self) -> None:
        points = _box(*self.SHAPES["round_12cm"])
        framing = thumb.fit_frame(points, AZIMUTH, ELEVATION)
        right, up, _ = framing.basis
        du = [_dot(p, right) for p in points]
        dv = [_dot(p, up) for p in points]
        long = max(max(du) - min(du), max(dv) - min(dv))
        self.assertAlmostEqual(framing.ortho_scale, long * 256 / 224, places=9)

    def test_other_margin_changes_ortho_scale(self) -> None:
        points = _box(*self.SHAPES["round_12cm"])
        wide = thumb.fit_frame(points, AZIMUTH, ELEVATION, margin_px=16)
        tight = thumb.fit_frame(points, AZIMUTH, ELEVATION, margin_px=32)
        self.assertAlmostEqual(tight.ortho_scale / wide.ortho_scale, 224 / 192, places=9)

    def test_the_basis_is_the_same_for_every_size(self) -> None:
        expected = thumb.view_basis(AZIMUTH, ELEVATION)
        for centre, size in self.SHAPES.values():
            basis = thumb.fit_frame(_box(centre, size), AZIMUTH, ELEVATION).basis
            for got, want in zip(basis, expected, strict=True):
                for g, w in zip(got, want, strict=True):
                    self.assertAlmostEqual(g, w, places=9)

    def test_translating_the_points_does_not_change_the_pixel_box(self) -> None:
        centre, size = self.SHAPES["large_45cm"]
        base = _box(centre, size)
        moved = [(x + 3.5, y - 7.25, z + 1.0) for x, y, z in base]
        first = self._pixel_box(thumb.fit_frame(base, AZIMUTH, ELEVATION), base)
        second = self._pixel_box(thumb.fit_frame(moved, AZIMUTH, ELEVATION), moved)
        for a, b in zip(first, second, strict=True):
            self.assertAlmostEqual(a, b, delta=1e-6)

    def test_camera_is_above_the_target_and_clips_hold_every_point(self) -> None:
        points = _box(*self.SHAPES["large_45cm"])
        framing = thumb.fit_frame(points, AZIMUTH, ELEVATION)
        _, _, toward = framing.basis
        self.assertGreater(framing.camera_location[2], framing.target[2])
        self.assertGreater(framing.clip_start, 0.0)
        self.assertGreater(framing.clip_end, framing.clip_start)
        for point in points:
            offset = tuple(p - c for p, c in zip(point, framing.camera_location, strict=True))
            depth = -_dot(offset, toward)
            self.assertGreater(depth, framing.clip_start)
            self.assertLess(depth, framing.clip_end)

    def test_zero_thickness_plane_is_framed_normally(self) -> None:
        points = _box((0.0, 0.0, 0.0), (0.10, 0.10, 0.0))
        framing = thumb.fit_frame(points, AZIMUTH, ELEVATION)
        x0, y0, x1, y1 = self._pixel_box(framing, points)
        self.assertAlmostEqual(max(x1 - x0, y1 - y0), 224.0, delta=1e-6)
        self.assertAlmostEqual((x0 + x1) / 2, 128.0, delta=1e-6)
        self.assertAlmostEqual((y0 + y1) / 2, 128.0, delta=1e-6)

    def test_up_in_the_world_is_up_in_the_picture(self) -> None:
        points = _box((0.0, 0.0, 0.0), (0.1, 0.1, 0.1))
        framing = thumb.fit_frame(points, AZIMUTH, ELEVATION)
        low = thumb.to_pixels(framing, (0.0, 0.0, -0.05))
        high = thumb.to_pixels(framing, (0.0, 0.0, 0.05))
        self.assertLess(high[1], low[1])

    def test_framing_is_frozen(self) -> None:
        framing = thumb.fit_frame(_box((0, 0, 0), (0.1, 0.1, 0.1)), AZIMUTH, ELEVATION)
        with self.assertRaises(AttributeError):
            framing.ortho_scale = 1.0

    def test_points_may_be_a_generator(self) -> None:
        points = _box((0, 0, 0), (0.1, 0.1, 0.1))
        framing = thumb.fit_frame((p for p in points), AZIMUTH, ELEVATION)
        self.assertGreater(framing.ortho_scale, 0.0)


class FramingFailureTest(unittest.TestCase):
    def _fails(self, points) -> None:
        with self.assertRaises(blender_common.GeneratorError):
            thumb.fit_frame(points, AZIMUTH, ELEVATION)

    def test_no_points(self) -> None:
        self._fails([])

    def test_nan_coordinate(self) -> None:
        points = _box((0, 0, 0), (0.1, 0.1, 0.1))
        points[3] = (float("nan"), 0.0, 0.0)
        self._fails(points)

    def test_infinite_coordinate(self) -> None:
        for bad in (float("inf"), float("-inf")):
            with self.subTest(bad=bad):
                points = _box((0, 0, 0), (0.1, 0.1, 0.1))
                points[0] = (0.0, bad, 0.0)
                self._fails(points)

    def test_single_point_and_equal_points_have_zero_size(self) -> None:
        self._fails([(0.1, 0.2, 0.3)])
        self._fails([(0.1, 0.2, 0.3)] * 8)

    def test_edge_on_line_has_zero_size(self) -> None:
        _, _, toward = thumb.view_basis(AZIMUTH, ELEVATION)
        self._fails([(0.0, 0.0, 0.0), tuple(0.2 * t for t in toward)])


class MeasurePngTest(unittest.TestCase):
    def setUp(self) -> None:
        self._temp = tempfile.TemporaryDirectory()
        self.addCleanup(self._temp.cleanup)
        self.folder = Path(self._temp.name)

    def _write(self, data: bytes, name: str = "t.png") -> Path:
        path = self.folder / name
        path.write_bytes(data)
        return path

    def test_size_type_corners_and_box_of_a_centred_block(self) -> None:
        path = self._write(encode_png(frame(block=(16, 16, 239, 239))))
        facts = thumb.measure_png(path)
        self.assertEqual((facts.width, facts.height), (256, 256))
        self.assertEqual((facts.bit_depth, facts.colour_type), (8, 6))
        self.assertEqual(tuple(facts.corner_alphas), (0, 0, 0, 0))
        self.assertEqual(tuple(facts.alpha_box), (16, 16, 239, 239))
        self.assertEqual(facts.long_side, 224)
        self.assertEqual(tuple(facts.centre), (128, 128))

    def test_non_square_block_uses_the_longer_side(self) -> None:
        path = self._write(encode_png(frame(block=(100, 16, 139, 239))))
        facts = thumb.measure_png(path)
        self.assertEqual(tuple(facts.alpha_box), (100, 16, 139, 239))
        self.assertEqual(facts.long_side, 224)
        self.assertEqual(tuple(facts.centre), (120, 128))

    def test_faint_alpha_counts_and_corner_alphas_are_read_in_order(self) -> None:
        corners = {(0, 0): 1, (255, 0): 2, (0, 255): 3, (255, 255): 4}
        facts = thumb.measure_png(self._write(encode_png(frame(corners=corners))))
        self.assertEqual(tuple(facts.corner_alphas), (1, 2, 3, 4))
        self.assertEqual(tuple(facts.alpha_box), (0, 0, 255, 255))

    def test_fully_transparent_image_has_no_box(self) -> None:
        facts = thumb.measure_png(self._write(encode_png(frame())))
        self.assertIsNone(facts.alpha_box)
        self.assertEqual(tuple(facts.corner_alphas), (0, 0, 0, 0))

    def test_all_five_row_filters_decode(self) -> None:
        rows = frame(block=(30, 40, 200, 180))
        # Make the rows differ so a wrong filter shows up.
        for y in range(256):
            rows[y][7] = (y, 255 - y, (y * 7) % 256, 0)
        for kind in range(5):
            with self.subTest(filter=kind):
                path = self._write(encode_png(rows, filters=[kind]), f"f{kind}.png")
                facts = thumb.measure_png(path)
                self.assertEqual(tuple(facts.alpha_box), (30, 40, 200, 180))
        mixed = self._write(encode_png(rows, filters=[0, 1, 2, 3, 4]), "mixed.png")
        self.assertEqual(tuple(thumb.measure_png(mixed).alpha_box), (30, 40, 200, 180))

    def test_filters_decode_alpha_values_exactly(self) -> None:
        rows = frame()
        for x in range(256):
            rows[5][x] = (x, x, x, 0 if x < 100 else (x * 3) % 256 or 1)
        for kind in range(5):
            with self.subTest(filter=kind):
                path = self._write(encode_png(rows, filters=[kind]), f"a{kind}.png")
                self.assertEqual(tuple(thumb.measure_png(path).alpha_box), (100, 5, 255, 5))

    def test_rgb_png_is_reported_not_decoded(self) -> None:
        rows = [[(1, 2, 3, 255)] * 256 for _ in range(256)]
        facts = thumb.measure_png(self._write(encode_png(rows, colour_type=2)))
        self.assertEqual(facts.colour_type, 2)
        self.assertEqual((facts.width, facts.height), (256, 256))

    def test_other_size_is_reported(self) -> None:
        facts = thumb.measure_png(self._write(encode_png(frame(size=64))))
        self.assertEqual((facts.width, facts.height), (64, 64))

    def test_interlaced_png_is_an_error(self) -> None:
        path = self._write(encode_png(frame(size=8), interlace=1))
        with self.assertRaises(blender_common.GeneratorError):
            thumb.measure_png(path)

    def test_not_a_png_is_an_error(self) -> None:
        path = self._write(b"glTF" + bytes(64))
        with self.assertRaises(blender_common.GeneratorError):
            thumb.measure_png(path)


OLD_PNG = encode_png(frame(size=4, block=(1, 1, 2, 2)))


class WriteSafetyTest(unittest.TestCase):
    """AC 7: the script writes through blender_common.write_group; an existing PNG survives."""

    def setUp(self) -> None:
        self._temp = tempfile.TemporaryDirectory()
        self.addCleanup(self._temp.cleanup)
        self.folder = Path(self._temp.name)
        self.final = thumb.output_path(self.folder, "rock_1")
        self.final.write_bytes(OLD_PNG)

    def _write(self, writer) -> None:
        blender_common.write_group(
            self.folder, [(self.final.name, writer, blender_common.PNG_MAGIC)]
        )

    def _assert_untouched(self) -> None:
        self.assertEqual(self.final.read_bytes(), OLD_PNG)
        self.assertEqual([p.name for p in self.folder.iterdir()], [self.final.name])

    def test_failing_writer_leaves_the_old_png_and_no_temp_file(self) -> None:
        def writer(path: Path) -> None:
            path.write_bytes(b"partial")
            raise OSError("disk full")

        with self.assertRaises(blender_common.GeneratorError):
            self._write(writer)
        self._assert_untouched()

    def test_wrong_magic_leaves_the_old_png_and_no_temp_file(self) -> None:
        with self.assertRaises(blender_common.GeneratorError):
            self._write(lambda path: path.write_bytes(b"glTF" + bytes(32)))
        self._assert_untouched()

    def test_writer_that_writes_nothing_leaves_the_old_png(self) -> None:
        with self.assertRaises(blender_common.GeneratorError):
            self._write(lambda path: None)
        self._assert_untouched()

    def test_good_writer_replaces_the_old_png_and_leaves_no_temp_file(self) -> None:
        new = encode_png(frame(size=4, block=(0, 0, 3, 3)))
        self._write(lambda path: path.write_bytes(new))
        self.assertEqual(self.final.read_bytes(), new)
        self.assertEqual([p.name for p in self.folder.iterdir()], [self.final.name])

    def test_missing_output_folder_is_an_error_and_is_not_created(self) -> None:
        missing = self.folder / "nope"
        with self.assertRaises(blender_common.GeneratorError):
            blender_common.write_group(
                missing, [("rock_1.png", lambda p: p.write_bytes(OLD_PNG), b"\x89PNG")]
            )
        self.assertFalse(missing.exists())


class ModuleShapeTest(unittest.TestCase):
    SOURCE = TOOLS / "render_item_thumbnail.py"

    def test_bpy_is_not_imported_with_the_module(self) -> None:
        code = (
            "import sys; sys.path.insert(0, sys.argv[1]); import render_item_thumbnail; "
            "sys.exit(1 if 'bpy' in sys.modules else 0)"
        )
        result = subprocess.run(
            [sys.executable, "-c", code, str(TOOLS)], capture_output=True, text=True, check=False
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_the_common_helpers_are_reused_not_copied(self) -> None:
        text = self.SOURCE.read_text(encoding="utf-8")
        for name in ("write_group", "swap_in_group", "script_args", "GeneratorError"):
            self.assertNotRegex(text, rf"(?m)^(def|class) {name}\b", name)
        self.assertTrue(callable(thumb.main))
        self.assertIs(thumb.GeneratorError, blender_common.GeneratorError)

    def test_no_import_of_bpy_at_module_level(self) -> None:
        text = self.SOURCE.read_text(encoding="utf-8")
        self.assertNotRegex(text, r"(?m)^(import bpy|from bpy|import mathutils|from mathutils)")


if __name__ == "__main__":
    unittest.main()
