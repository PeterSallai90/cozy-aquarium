"""Local tests for the tank generator (#22 AC 8, #24 AC 14 and 23): parameter validation, the three
committed parameter files and the deterministic mesh data. Stdlib only, no Blender. Not run in CI
(ci.yml discovers tools/scripts only); the GdUnit test test_tank_params_match_catalog.gd guards the
parameter files against the catalog in CI. Run from the repository root:

    python -m unittest discover -s tools/blender -p "test_*.py"

Contract fixed by these tests (technical-artist implements it):

- ``generate_tank.load_params(path: Path) -> dict`` validates the file before any Blender work and
  raises ``blender_common.GeneratorError`` with a message that names the offending key.
- Keys: interior_length_m, interior_height_m, interior_depth_m, glass_thickness_m, trim_size_m (one
  value for trim width and trim height; it replaces trim_width_m and trim_height_m, which are now
  unknown keys). Unknown or missing keys, duplicate keys, wrong types and values outside the range
  are rejected; trim_size_m must be at least glass_thickness_m and below a quarter of
  interior_depth_m, and the message names trim_size_m.
- ``tools/blender/params/tank_<id>.json`` holds each tank: tank_small_1 (0.40 x 0.27 x 0.25 m,
  glass 4 mm), tank_medium_1 (0.60 x 0.35 x 0.30 m, glass 5 mm) and tank_large_1
  (1.00 x 0.52 x 0.40 m, glass 8 mm), trim 1 cm on all three. No other tank_*.json exists.
- ``build_glass(params)`` and ``build_frame(params)`` return deterministic MeshData; the frame is
  trim_size_m wide and trim_size_m tall. Together at most 10,000 triangles.
- Not testable without Blender (manual, in the test report): running the generator without
  arguments regenerates every tank glb.
"""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import blender_common  # noqa: E402
import generate_tank  # noqa: E402

PARAMS_DIR = Path(__file__).resolve().parent / "params"
PARAMS = PARAMS_DIR / "tank_medium_1.json"
KEYS = (
    "interior_length_m",
    "interior_height_m",
    "interior_depth_m",
    "glass_thickness_m",
    "trim_size_m",
)
TANKS = {
    "tank_small_1": (0.40, 0.27, 0.25, 0.004),
    "tank_medium_1": (0.60, 0.35, 0.30, 0.005),
    "tank_large_1": (1.00, 0.52, 0.40, 0.008),
}
TRIM = 0.01


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
            generate_tank.load_params(self._write(data))
        for word in words:
            self.assertIn(word, str(raised.exception))

    def test_ac08_committed_file_has_the_medium_tank_values(self) -> None:
        params = generate_tank.load_params(PARAMS)
        self.assertAlmostEqual(params["interior_length_m"], 0.60)
        self.assertAlmostEqual(params["interior_height_m"], 0.35)
        self.assertAlmostEqual(params["interior_depth_m"], 0.30)
        self.assertAlmostEqual(params["glass_thickness_m"], 0.005)
        self.assertAlmostEqual(params["trim_size_m"], 0.01)

    def test_ac08_committed_file_has_exactly_the_documented_keys(self) -> None:
        self.assertEqual(sorted(self.base), sorted(KEYS))

    def test_ac08_each_key_out_of_range_is_rejected_with_its_name(self) -> None:
        for key in KEYS:
            for bad in (-1.0, 0.0, 50.0):
                with self.subTest(key=key, value=bad):
                    data = dict(self.base)
                    data[key] = bad
                    self._rejects(data, key)

    def test_ac08_non_number_is_rejected_with_the_key(self) -> None:
        for key in KEYS:
            for bad in ("0.6", None, True, [0.6]):
                with self.subTest(key=key, value=bad):
                    data = dict(self.base)
                    data[key] = bad
                    self._rejects(data, key)

    def test_ac08_missing_key_is_rejected_with_its_name(self) -> None:
        for key in KEYS:
            with self.subTest(key=key):
                data = dict(self.base)
                del data[key]
                self._rejects(data, key)

    def test_ac08_unknown_key_is_rejected_with_its_name(self) -> None:
        data = dict(self.base)
        data["glass_colour"] = 1.0
        self._rejects(data, "glass_colour")

    def test_ac08_duplicate_key_is_rejected_with_its_name(self) -> None:
        text = PARAMS.read_text(encoding="utf-8").rstrip().rstrip("}").rstrip()
        text += ',\n  "glass_thickness_m": 0.006\n}\n'
        self._rejects(text, "glass_thickness_m")

    def test_ac23_trim_narrower_than_the_glass_is_rejected_naming_trim_size(self) -> None:
        data = dict(self.base)
        data["glass_thickness_m"] = 0.008
        data["trim_size_m"] = 0.004
        self._rejects(data, "trim_size_m")

    def test_ac23_trim_at_a_quarter_of_the_depth_is_rejected_naming_trim_size(self) -> None:
        data = dict(self.base)
        data["interior_depth_m"] = 0.20
        data["trim_size_m"] = 0.05  # exactly a quarter of the depth
        self._rejects(data, "trim_size_m")
        data["trim_size_m"] = 0.049
        self.assertAlmostEqual(generate_tank.load_params(self._write(data))["trim_size_m"], 0.049)

    def test_ac23_trim_equal_to_the_glass_thickness_is_accepted(self) -> None:
        data = dict(self.base)
        data["glass_thickness_m"] = 0.01
        data["trim_size_m"] = 0.01
        self.assertAlmostEqual(generate_tank.load_params(self._write(data))["trim_size_m"], 0.01)

    def test_ac23_the_old_trim_keys_are_unknown_keys(self) -> None:
        for old in ("trim_width_m", "trim_height_m"):
            with self.subTest(key=old):
                data = dict(self.base)
                data[old] = 0.01
                self._rejects(data, old)

    def test_ac23_a_file_with_only_the_old_trim_keys_is_rejected_naming_trim_size(self) -> None:
        data = dict(self.base)
        del data["trim_size_m"]
        data["trim_width_m"] = 0.01
        data["trim_height_m"] = 0.01
        self._rejects(data, "trim_size_m")

    def test_ac08_invalid_json_and_missing_file_are_generator_errors(self) -> None:
        self._rejects("{not json")
        with self.assertRaises(blender_common.GeneratorError):
            generate_tank.load_params(self.folder / "nope.json")

    def test_ac08_non_object_top_level_is_rejected(self) -> None:
        self._rejects("[1, 2]")

    def test_ac08_generator_error_is_the_shared_class(self) -> None:
        self.assertTrue(issubclass(generate_tank.GeneratorError, blender_common.GeneratorError))


class CommittedTanksTest(unittest.TestCase):
    def _load(self, name: str) -> dict:
        return generate_tank.load_params(PARAMS_DIR / f"{name}.json")

    def test_ac14_there_is_one_parameter_file_per_tank_and_no_other(self) -> None:
        found = sorted(path.stem for path in PARAMS_DIR.glob("tank_*.json"))
        self.assertEqual(found, sorted(TANKS))

    def test_ac14_each_file_holds_the_issue_values_and_the_documented_keys(self) -> None:
        for name, (length, height, depth, glass) in TANKS.items():
            with self.subTest(tank=name):
                params = self._load(name)
                self.assertEqual(sorted(params), sorted(KEYS))
                self.assertAlmostEqual(params["interior_length_m"], length)
                self.assertAlmostEqual(params["interior_height_m"], height)
                self.assertAlmostEqual(params["interior_depth_m"], depth)
                self.assertAlmostEqual(params["glass_thickness_m"], glass)
                self.assertAlmostEqual(params["trim_size_m"], TRIM)

    def test_ac14_the_old_medium_parameter_file_is_gone(self) -> None:
        self.assertFalse((PARAMS_DIR / "tank_medium_60l.json").exists())


class MeshTest(unittest.TestCase):
    def _meshes(self, name: str):  # noqa: ANN202
        params = generate_tank.load_params(PARAMS_DIR / f"{name}.json")
        return params, generate_tank.build_glass(params), generate_tank.build_frame(params)

    def test_ac14_each_tank_is_within_the_triangle_budget(self) -> None:
        for name in TANKS:
            with self.subTest(tank=name):
                _, glass, frame = self._meshes(name)
                total = glass.triangle_count() + frame.triangle_count()
                self.assertGreater(total, 0)
                self.assertLessEqual(total, 10000)

    def test_ac14_the_mesh_data_is_deterministic(self) -> None:
        for name in TANKS:
            with self.subTest(tank=name):
                _, glass_a, frame_a = self._meshes(name)
                _, glass_b, frame_b = self._meshes(name)
                self.assertEqual(glass_a.vertices, glass_b.vertices)
                self.assertEqual(glass_a.faces, glass_b.faces)
                self.assertEqual(frame_a.vertices, frame_b.vertices)
                self.assertEqual(frame_a.faces, frame_b.faces)

    def test_ac23_the_frame_is_trim_size_wide_and_tall_and_flush_with_the_glass(self) -> None:
        for name, (length, _height, depth, glass_t) in TANKS.items():
            with self.subTest(tank=name):
                params, _, frame = self._meshes(name)
                low, high = frame.bounds()
                outer_x = length / 2.0 + glass_t
                outer_z = depth / 2.0 + glass_t
                self.assertAlmostEqual(high[0], outer_x, places=6)
                self.assertAlmostEqual(low[0], -outer_x, places=6)
                self.assertAlmostEqual(high[2], outer_z, places=6)
                self.assertAlmostEqual(high[1] - low[1], params["trim_size_m"], places=6)
                xs = {round(v[0], 6) for v in frame.vertices}
                self.assertIn(round(outer_x - params["trim_size_m"], 6), xs)

    def test_ac23_the_frame_follows_trim_size_m_not_a_constant(self) -> None:
        params = generate_tank.load_params(PARAMS)
        params["trim_size_m"] = 0.02
        frame = generate_tank.build_frame(params)
        low, high = frame.bounds()
        self.assertAlmostEqual(high[1] - low[1], 0.02, places=6)
        xs = {round(v[0], 6) for v in frame.vertices}
        self.assertIn(round(0.30 + 0.005 - 0.02, 6), xs)

    def test_ac14_the_exterior_matches_interior_plus_glass(self) -> None:
        for name, (length, _height, depth, glass_t) in TANKS.items():
            with self.subTest(tank=name):
                _, glass, _ = self._meshes(name)
                low, high = glass.bounds()
                self.assertAlmostEqual(high[0] - low[0], length + 2 * glass_t, places=6)
                self.assertAlmostEqual(high[2] - low[2], depth + 2 * glass_t, places=6)


if __name__ == "__main__":
    unittest.main()
