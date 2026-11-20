"""Local tests for the decor generator and its palette (#157, AC 5, 6, 8, 10 and 22). Stdlib only,
no Blender. Not run in CI (ci.yml discovers tools/scripts only). Run from the repository root:

    python -m unittest discover -s tools/blender -p "test_*.py"

Group that makes this file pass: technical-artist (stage 1).

Contract fixed by these tests (the technical-artist implements it; the plan of #157 leaves the
names open where marked "decision"):

- ``generate_decor.load_params(path: Path) -> dict`` loads ``tools/blender/params/decor.json`` and
  raises ``blender_common.GeneratorError`` with a message naming the offending key (missing,
  unknown, duplicate, non-number, out of range). Decision, the key names: sizes in cm named
  ``<item>_<axis>_cm`` for stone, branch and amphora with axis width (x), height (y) and depth (z)
  (``stone_width_cm`` ... ``amphora_depth_cm``), plus ``stone_seed``, plus the three AC 22 keys of
  plan section 2.3: ``amphora_opening_cm`` (>= 3.5), ``amphora_inside_depth_cm`` (>= 8.0) and
  ``amphora_wall_cm`` (0.5 to 0.7). Every ``*_cm`` size must be above 0.
- ``generate_decor.build_river_stone(params)``, ``build_driftwood_branch(params)`` and
  ``build_clay_amphora(params)`` return a ``blender_common.MeshData`` in metres, glTF frame
  (x width, y up, z depth, front +Z); bounds equal the sizes, the lowest point is y = 0 and the x/z
  bounding box is centred on the origin. Deterministic.
- ``decor_palette`` has ``PALETTE``, ``atlas_png() -> bytes`` (deterministic PNG), ``cell_uv`` and
  the cells ``STONE_GRANITE = (0, 0)``, ``WOOD_DRIFT = (1, 0)`` and ``TERRACOTTA = (2, 0)``
  (column, row from the top; shipped cells never move).
- ``blender_common.write_group`` accepts output names with a subfolder (``models/a.glb``) in an
  existing sub-folder: success writes both folders, a failure leaves the old group in place, and
  no temp file stays behind in either folder. Flat names behave as before.
- Amphora checks (AC 22), measured on the mesh itself and not on the parameters: the surface is
  closed and consistently wound (every directed edge once, its reverse once), one connected
  component, positive volume (outward winding), the narrowest inner diameter measured by rays
  from the axis is at least 3.5 cm and the inside depth (rim top to the inner floor) at least
  8 cm.
- Branch check (Q20): no cross-section (a plane x = const, outside the 1.5 cm of each rounded
  end) has its lowest point at or above 2 cm, so no gap a fish can enter exists under it.
"""

from __future__ import annotations

import colorsys
import json
import math
import sys
import tempfile
import unittest
from collections.abc import Callable
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import blender_common  # noqa: E402
import decor_palette  # noqa: E402
import generate_decor  # noqa: E402

PARAMS = Path(__file__).resolve().parent / "params" / "decor.json"
PNG_MAGIC = bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
# item -> (width x, height y, depth z) in metres, the footprint table of the issue
SIZES_M = {
    "stone": (0.11, 0.06, 0.08),
    "branch": (0.28, 0.08, 0.07),
    "amphora": (0.09, 0.14, 0.08),
}
SIZE_KEYS = {
    f"{item}_{axis}_cm": value * 100.0
    for item, sizes in SIZES_M.items()
    for axis, value in zip(("width", "height", "depth"), sizes, strict=True)
}
CAVITY_RANGES = {
    # key: (values below or above the limit that must be rejected, a valid value)
    "amphora_opening_cm": ((0.0, 3.0, 3.49), 3.8),
    "amphora_inside_depth_cm": ((0.0, 5.0, 7.99), 8.5),
    "amphora_wall_cm": ((0.0, 0.3, 0.49, 0.71, 1.5), 0.6),
}
TRIANGLES_MIN = 300
TRIANGLES_MAX = 1500
SNAP = 7  # decimals when welding vertices by position


class LoadParamsTest(unittest.TestCase):
    def setUp(self) -> None:
        self._temp = tempfile.TemporaryDirectory()
        self.addCleanup(self._temp.cleanup)
        self.folder = Path(self._temp.name)
        self.base: dict = json.loads(PARAMS.read_text(encoding="utf-8"))

    def _write(self, data: dict | str) -> Path:
        path = self.folder / "params.json"
        text = data if isinstance(data, str) else json.dumps(data)
        path.write_text(text, encoding="utf-8")
        return path

    def _rejects(self, data: dict | str, *words: str) -> None:
        with self.assertRaises(blender_common.GeneratorError) as raised:
            generate_decor.load_params(self._write(data))
        for word in words:
            self.assertIn(word, str(raised.exception))

    def test_ac05_committed_file_loads_and_has_the_sizes_of_the_issue(self) -> None:
        params = generate_decor.load_params(PARAMS)
        for key, value in SIZE_KEYS.items():
            with self.subTest(key=key):
                self.assertAlmostEqual(params[key], value, places=9)

    def test_ac22_the_three_cavity_keys_exist_and_meet_the_limits(self) -> None:
        params = generate_decor.load_params(PARAMS)
        self.assertGreaterEqual(params["amphora_opening_cm"], 3.5)
        self.assertGreaterEqual(params["amphora_inside_depth_cm"], 8.0)
        self.assertGreaterEqual(params["amphora_wall_cm"], 0.5)
        self.assertLessEqual(params["amphora_wall_cm"], 0.7)

    def test_ac22_a_cavity_value_outside_the_limit_is_rejected_with_its_name(self) -> None:
        for key, (bad_values, _good) in CAVITY_RANGES.items():
            for bad in bad_values:
                with self.subTest(key=key, value=bad):
                    data = dict(self.base)
                    data[key] = bad
                    self._rejects(data, key)

    def test_ac22_a_valid_cavity_value_is_accepted(self) -> None:
        for key, (_bad, good) in CAVITY_RANGES.items():
            with self.subTest(key=key):
                data = dict(self.base)
                data[key] = good
                params = generate_decor.load_params(self._write(data))
                self.assertAlmostEqual(params[key], good)

    def test_ac22_a_missing_cavity_key_is_rejected_with_its_name(self) -> None:
        for key in CAVITY_RANGES:
            with self.subTest(key=key):
                data = dict(self.base)
                del data[key]
                self._rejects(data, key)

    def test_ac05_a_size_that_is_zero_or_negative_is_rejected_with_its_name(self) -> None:
        for key in SIZE_KEYS:
            for bad in (0.0, -1.0):
                with self.subTest(key=key, value=bad):
                    data = dict(self.base)
                    data[key] = bad
                    self._rejects(data, key)

    def test_ac05_a_non_number_size_or_cavity_value_is_rejected_with_its_name(self) -> None:
        for key in list(SIZE_KEYS) + list(CAVITY_RANGES):
            for bad in ("6", None, True, [1]):
                with self.subTest(key=key, value=bad):
                    data = dict(self.base)
                    data[key] = bad
                    self._rejects(data, key)

    def test_ac05_each_missing_key_is_rejected_with_its_name(self) -> None:
        for key in self.base:
            with self.subTest(key=key):
                data = dict(self.base)
                del data[key]
                self._rejects(data, key)

    def test_ac05_an_unknown_key_is_rejected_with_its_name(self) -> None:
        data = dict(self.base)
        data["window_count"] = 2
        self._rejects(data, "window_count")

    def test_ac05_a_duplicate_key_is_rejected_with_its_name(self) -> None:
        text = PARAMS.read_text(encoding="utf-8").rstrip().rstrip("}").rstrip()
        text += ',\n  "amphora_wall_cm": 0.6\n}\n'
        self._rejects(text, "amphora_wall_cm")

    def test_ac05_invalid_json_and_a_missing_file_are_generator_errors(self) -> None:
        self._rejects("{not json")
        with self.assertRaises(blender_common.GeneratorError):
            generate_decor.load_params(self.folder / "nope.json")


class PaletteTest(unittest.TestCase):
    def colour(self, cell: tuple[int, int]) -> tuple[float, float, float]:
        column, row = cell
        rgb = decor_palette.PALETTE[row][column]
        return colorsys.rgb_to_hsv(
            ((rgb >> 16) & 0xFF) / 255.0, ((rgb >> 8) & 0xFF) / 255.0, (rgb & 0xFF) / 255.0
        )

    def test_ac10_atlas_png_is_a_png(self) -> None:
        self.assertEqual(decor_palette.atlas_png()[:8], PNG_MAGIC)

    def test_ac10_atlas_png_is_byte_identical_across_two_calls(self) -> None:
        self.assertEqual(decor_palette.atlas_png(), decor_palette.atlas_png())

    def test_ac08_the_three_cells_are_fixed_and_different(self) -> None:
        self.assertEqual(decor_palette.STONE_GRANITE, (0, 0))
        self.assertEqual(decor_palette.WOOD_DRIFT, (1, 0))
        self.assertEqual(decor_palette.TERRACOTTA, (2, 0))
        colours = {
            decor_palette.PALETTE[row][column]
            for column, row in (
                decor_palette.STONE_GRANITE,
                decor_palette.WOOD_DRIFT,
                decor_palette.TERRACOTTA,
            )
        }
        self.assertEqual(len(colours), 3)

    def test_ac08_the_stone_is_grey_saturation_at_most_0_25(self) -> None:
        _h, s, _v = self.colour(decor_palette.STONE_GRANITE)
        self.assertLessEqual(s, 0.25)

    def test_ac08_the_branch_is_warm_brown_hue_15_to_40_degrees_value_at_most_0_6(self) -> None:
        h, _s, v = self.colour(decor_palette.WOOD_DRIFT)
        self.assertGreaterEqual(h * 360.0, 15.0)
        self.assertLessEqual(h * 360.0, 40.0)
        self.assertLessEqual(v, 0.6)

    def test_ac08_the_amphora_is_more_saturated_than_the_stone_and_the_branch(self) -> None:
        amphora = self.colour(decor_palette.TERRACOTTA)[1]
        self.assertGreater(amphora, self.colour(decor_palette.STONE_GRANITE)[1])
        self.assertGreater(amphora, self.colour(decor_palette.WOOD_DRIFT)[1])

    def test_ac08_cell_uv_is_the_cell_centre(self) -> None:
        u, v = decor_palette.cell_uv((2, 0))
        self.assertAlmostEqual(u, 2.5 / 8)
        self.assertAlmostEqual(v, 1.0 - 0.5 / 8)


# --- mesh helpers (independent of the generator internals) ---

Vec = tuple[float, float, float]


def welded(mesh: blender_common.MeshData) -> list[tuple[int, ...]]:
    """Faces as loops of vertex ids, vertices welded by rounded position."""
    ids: dict[tuple[float, ...], int] = {}
    lookup: list[int] = []
    for point in mesh.vertices:
        key = tuple(round(c, SNAP) for c in point)
        lookup.append(ids.setdefault(key, len(ids)))
    return [tuple(lookup[i] for i in face) for face in mesh.faces]


def triangles(mesh: blender_common.MeshData) -> list[tuple[Vec, Vec, Vec]]:
    result = []
    for face in mesh.faces:
        for k in range(1, len(face) - 1):
            result.append((mesh.vertices[face[0]], mesh.vertices[face[k]], mesh.vertices[face[k + 1]]))
    return result


def sub(a: Vec, b: Vec) -> Vec:
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def cross(a: Vec, b: Vec) -> Vec:
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def dot(a: Vec, b: Vec) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def ray_hit(origin: Vec, direction: Vec, tri: tuple[Vec, Vec, Vec]) -> float | None:
    """Moeller-Trumbore, distance along ``direction`` or None."""
    edge1 = sub(tri[1], tri[0])
    edge2 = sub(tri[2], tri[0])
    pvec = cross(direction, edge2)
    det = dot(edge1, pvec)
    if abs(det) < 1e-14:
        return None
    inv = 1.0 / det
    tvec = sub(origin, tri[0])
    u = dot(tvec, pvec) * inv
    if u < -1e-9 or u > 1.0 + 1e-9:
        return None
    qvec = cross(tvec, edge1)
    v = dot(direction, qvec) * inv
    if v < -1e-9 or u + v > 1.0 + 1e-9:
        return None
    distance = dot(edge2, qvec) * inv
    return distance if distance > 1e-9 else None


def first_hit(origin: Vec, direction: Vec, tris: list[tuple[Vec, Vec, Vec]]) -> float | None:
    hits = [h for h in (ray_hit(origin, direction, t) for t in tris) if h is not None]
    return min(hits) if hits else None


def signed_volume(mesh: blender_common.MeshData) -> float:
    total = 0.0
    for a, b, c in triangles(mesh):
        total += dot(a, cross(b, c)) / 6.0
    return total


class MeshCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.params = generate_decor.load_params(PARAMS)
        cls.meshes = {
            "stone": generate_decor.build_river_stone(cls.params),
            "branch": generate_decor.build_driftwood_branch(cls.params),
            "amphora": generate_decor.build_clay_amphora(cls.params),
        }


class CommonMeshTest(MeshCase):
    def test_ac06_each_mesh_has_300_to_1500_triangles(self) -> None:
        for name, mesh in self.meshes.items():
            with self.subTest(item=name):
                self.assertGreaterEqual(mesh.triangle_count(), TRIANGLES_MIN)
                self.assertLessEqual(mesh.triangle_count(), TRIANGLES_MAX)

    def test_ac05_the_bounds_equal_the_issue_sizes_exactly(self) -> None:
        for name, mesh in self.meshes.items():
            with self.subTest(item=name):
                low, high = mesh.bounds()
                for axis in range(3):
                    self.assertAlmostEqual(high[axis] - low[axis], SIZES_M[name][axis], places=6)

    def test_ac05_the_lowest_point_is_y_zero_and_the_footprint_is_centred(self) -> None:
        for name, mesh in self.meshes.items():
            with self.subTest(item=name):
                low, high = mesh.bounds()
                self.assertAlmostEqual(low[1], 0.0, places=6)
                self.assertAlmostEqual((low[0] + high[0]) / 2.0, 0.0, places=6)
                self.assertAlmostEqual((low[2] + high[2]) / 2.0, 0.0, places=6)

    def test_ac05_the_stone_and_the_amphora_stand_on_a_flat_base(self) -> None:
        for name in ("stone", "amphora"):
            with self.subTest(item=name):
                on_ground = {
                    (round(p[0], SNAP), round(p[2], SNAP))
                    for p in self.meshes[name].vertices
                    if p[1] < 1e-6
                }
                self.assertGreaterEqual(len(on_ground), 3)

    def test_ac10_two_builds_give_equal_meshes(self) -> None:
        builders: dict[str, Callable[[dict], blender_common.MeshData]] = {
            "stone": generate_decor.build_river_stone,
            "branch": generate_decor.build_driftwood_branch,
            "amphora": generate_decor.build_clay_amphora,
        }
        for name, build in builders.items():
            with self.subTest(item=name):
                first = build(self.params)
                second = build(self.params)
                self.assertEqual(first.vertices, second.vertices)
                self.assertEqual(first.faces, second.faces)

    def test_ac10_a_changed_stone_seed_gives_another_stone(self) -> None:
        other = dict(self.params)
        other["stone_seed"] = int(self.params["stone_seed"]) + 1
        changed = generate_decor.build_river_stone(other)
        self.assertNotEqual(changed.vertices, self.meshes["stone"].vertices)


class BranchTest(MeshCase):
    def lowest_at(self, x: float) -> float | None:
        """Lowest y where the plane x = const cuts the mesh, None when it misses."""
        lowest: float | None = None
        for tri in triangles(self.meshes["branch"]):
            for a, b in ((tri[0], tri[1]), (tri[1], tri[2]), (tri[2], tri[0])):
                if (a[0] - x) * (b[0] - x) > 0.0 or a[0] == b[0]:
                    continue
                t = (x - a[0]) / (b[0] - a[0])
                y = a[1] + t * (b[1] - a[1])
                lowest = y if lowest is None else min(lowest, y)
        return lowest

    def test_q20_no_cross_section_has_a_gap_of_2_cm_under_it(self) -> None:
        low, high = self.meshes["branch"].bounds()
        x = low[0] + 0.015
        checked = 0
        while x <= high[0] - 0.015:
            lowest = self.lowest_at(x)
            with self.subTest(x_cm=round((x - low[0]) * 100.0, 1)):
                self.assertIsNotNone(lowest)
                self.assertLess(lowest if lowest is not None else 1.0, 0.02)
            checked += 1
            x += 0.01
        self.assertGreaterEqual(checked, 20)


class AmphoraTest(MeshCase):
    def setUp(self) -> None:
        self.mesh = self.meshes["amphora"]

    def test_ac22_the_surface_is_closed_and_consistently_wound(self) -> None:
        edges: dict[tuple[int, int], int] = {}
        for loop in welded(self.mesh):
            for k, a in enumerate(loop):
                b = loop[(k + 1) % len(loop)]
                edges[(a, b)] = edges.get((a, b), 0) + 1
        self.assertTrue(edges)
        for (a, b), count in edges.items():
            with self.subTest(edge=(a, b)):
                self.assertEqual(count, 1, "a directed edge is used more than once")
                self.assertEqual(edges.get((b, a), 0), 1, "the edge has no opposite partner")

    def test_ac22_the_mesh_is_one_connected_component(self) -> None:
        parent: dict[int, int] = {}

        def find(i: int) -> int:
            parent.setdefault(i, i)
            while parent[i] != i:
                parent[i] = parent[parent[i]]
                i = parent[i]
            return i

        for loop in welded(self.mesh):
            for a in loop[1:]:
                parent[find(a)] = find(loop[0])
        self.assertEqual(len({find(i) for i in list(parent)}), 1)

    def test_ac22_the_winding_is_outward_the_volume_is_positive(self) -> None:
        self.assertGreater(signed_volume(self.mesh), 0.0)

    def test_ac22_the_inside_depth_is_at_least_8_cm(self) -> None:
        tris = triangles(self.mesh)
        _low, high = self.mesh.bounds()
        rim = high[1]
        # straight down along the axis, nudged off the exact axis (the base fans meet there)
        hit = first_hit((0.0003, rim + 0.01, 0.0004), (0.0, -1.0, 0.0), tris)
        self.assertIsNotNone(hit, "the opening is closed: no inner floor below the rim")
        floor = rim + 0.01 - (hit if hit is not None else 0.0)
        self.assertGreaterEqual(rim - floor, 0.08 - 1e-6)

    def test_ac22_the_narrowest_inner_diameter_is_at_least_3_5_cm(self) -> None:
        tris = triangles(self.mesh)
        _low, high = self.mesh.bounds()
        rim = high[1]
        hit = first_hit((0.0003, rim + 0.01, 0.0004), (0.0, -1.0, 0.0), tris)
        self.assertIsNotNone(hit)
        floor = rim + 0.01 - (hit if hit is not None else 0.0)
        narrowest = math.inf
        steps = 40
        for step in range(steps + 1):
            y = floor + 0.001 + (rim - 0.0005 - floor - 0.001) * step / steps
            for k in range(32):
                angle = 2.0 * math.pi * k / 32.0
                direction = (math.cos(angle), 0.0, math.sin(angle))
                opposite = (-direction[0], 0.0, -direction[2])
                near = first_hit((0.0, y, 0.0), direction, tris)
                far = first_hit((0.0, y, 0.0), opposite, tris)
                self.assertIsNotNone(near, f"no inner wall at y={y:.4f}")
                self.assertIsNotNone(far, f"no inner wall at y={y:.4f}")
                if near is not None and far is not None:
                    narrowest = min(narrowest, near + far)
        self.assertGreaterEqual(narrowest, 0.035 - 1e-6)


class WriteGroupSubfolderTest(unittest.TestCase):
    def setUp(self) -> None:
        self._temp = tempfile.TemporaryDirectory()
        self.addCleanup(self._temp.cleanup)
        self.folder = Path(self._temp.name)
        (self.folder / "models").mkdir()

    @staticmethod
    def writer(data: bytes) -> Callable[[Path], None]:
        return lambda path: path.write_bytes(data)

    @staticmethod
    def failing(path: Path) -> None:
        raise OSError("injected failure")

    def outputs(self, last: Callable[[Path], None] | None = None) -> list:
        return [
            ("models/a.glb", self.writer(b"glTF new a"), blender_common.GLB_MAGIC),
            ("models/b.glb", self.writer(b"glTF new b"), blender_common.GLB_MAGIC),
            (
                "atlas.png",
                last or self.writer(b"\x89PNG new atlas"),
                blender_common.PNG_MAGIC,
            ),
        ]

    def files(self) -> list[str]:
        return sorted(
            str(p.relative_to(self.folder)).replace("\\", "/")
            for p in self.folder.rglob("*")
            if p.is_file()
        )

    def old(self) -> None:
        (self.folder / "models" / "a.glb").write_bytes(b"glTF old a")
        (self.folder / "models" / "b.glb").write_bytes(b"glTF old b")
        (self.folder / "atlas.png").write_bytes(b"\x89PNG old atlas")

    def test_ac10_success_writes_both_folders_and_leaves_no_temp_file(self) -> None:
        self.old()
        blender_common.write_group(self.folder, self.outputs())
        self.assertEqual((self.folder / "models" / "a.glb").read_bytes(), b"glTF new a")
        self.assertEqual((self.folder / "models" / "b.glb").read_bytes(), b"glTF new b")
        self.assertEqual((self.folder / "atlas.png").read_bytes(), b"\x89PNG new atlas")
        self.assertEqual(self.files(), ["atlas.png", "models/a.glb", "models/b.glb"])

    def test_ac10_a_first_run_creates_every_file(self) -> None:
        blender_common.write_group(self.folder, self.outputs())
        self.assertEqual(self.files(), ["atlas.png", "models/a.glb", "models/b.glb"])

    def test_ac10_a_failure_on_the_last_file_keeps_the_old_group_and_leaves_no_temp_file(
        self,
    ) -> None:
        self.old()
        with self.assertRaises(blender_common.GeneratorError):
            blender_common.write_group(self.folder, self.outputs(last=self.failing))
        self.assertEqual((self.folder / "models" / "a.glb").read_bytes(), b"glTF old a")
        self.assertEqual((self.folder / "models" / "b.glb").read_bytes(), b"glTF old b")
        self.assertEqual((self.folder / "atlas.png").read_bytes(), b"\x89PNG old atlas")
        self.assertEqual(self.files(), ["atlas.png", "models/a.glb", "models/b.glb"])

    def test_ac10_a_broken_last_file_keeps_the_old_group_and_leaves_no_temp_file(self) -> None:
        self.old()
        with self.assertRaises(blender_common.GeneratorError):
            blender_common.write_group(self.folder, self.outputs(last=self.writer(b"not a png")))
        self.assertEqual((self.folder / "models" / "a.glb").read_bytes(), b"glTF old a")
        self.assertEqual((self.folder / "atlas.png").read_bytes(), b"\x89PNG old atlas")
        self.assertEqual(self.files(), ["atlas.png", "models/a.glb", "models/b.glb"])

    def test_ac10_a_failure_on_the_first_run_leaves_nothing_behind(self) -> None:
        with self.assertRaises(blender_common.GeneratorError):
            blender_common.write_group(self.folder, self.outputs(last=self.failing))
        self.assertEqual(self.files(), [])

    def test_ac10_flat_names_still_work(self) -> None:
        blender_common.write_group(
            self.folder,
            [("flat.png", self.writer(b"\x89PNG flat"), blender_common.PNG_MAGIC)],
        )
        self.assertEqual((self.folder / "flat.png").read_bytes(), b"\x89PNG flat")
        self.assertEqual(self.files(), ["flat.png"])


if __name__ == "__main__":
    unittest.main()
