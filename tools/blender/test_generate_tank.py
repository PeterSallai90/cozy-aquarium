"""Local tests for the tank generator (#22, AC 8): parameter validation and the committed
parameter file. Stdlib only, no Blender. Not run in CI (ci.yml discovers tools/scripts only).
Run from the repository root:

    python -m unittest discover -s tools/blender -p "test_*.py"

Contract fixed by these tests (technical-artist implements it):

- ``generate_tank.load_params(path: Path) -> dict`` validates the file before any Blender work and
  raises ``blender_common.GeneratorError`` with a message that names the offending key.
- Keys: interior_length_m, interior_height_m, interior_depth_m, glass_thickness_m, trim_width_m,
  trim_height_m. Unknown or missing keys, duplicate keys, wrong types and values outside the
  range are rejected; trim_width_m must be at least glass_thickness_m.
- ``tools/blender/params/tank_medium_60l.json`` holds the medium tank (0.60 x 0.35 x 0.30 m,
  glass 5 mm, trim 1 cm x 1 cm).
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

PARAMS = Path(__file__).resolve().parent / "params" / "tank_medium_60l.json"
KEYS = (
    "interior_length_m",
    "interior_height_m",
    "interior_depth_m",
    "glass_thickness_m",
    "trim_width_m",
    "trim_height_m",
)


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
        self.assertAlmostEqual(params["trim_width_m"], 0.01)
        self.assertAlmostEqual(params["trim_height_m"], 0.01)

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

    def test_ac08_trim_narrower_than_the_glass_is_rejected_naming_trim_width(self) -> None:
        data = dict(self.base)
        data["glass_thickness_m"] = 0.008
        data["trim_width_m"] = 0.004
        self._rejects(data, "trim_width_m")

    def test_ac08_invalid_json_and_missing_file_are_generator_errors(self) -> None:
        self._rejects("{not json")
        with self.assertRaises(blender_common.GeneratorError):
            generate_tank.load_params(self.folder / "nope.json")

    def test_ac08_non_object_top_level_is_rejected(self) -> None:
        self._rejects("[1, 2]")

    def test_ac08_generator_error_is_the_shared_class(self) -> None:
        self.assertTrue(issubclass(generate_tank.GeneratorError, blender_common.GeneratorError))


if __name__ == "__main__":
    unittest.main()
