"""Local tests for the room generator and the shared helpers (#22, AC 8). Stdlib only, no
Blender. Not run in CI (ci.yml discovers tools/scripts only). Run from the repository root:

    python -m unittest discover -s tools/blender -p "test_*.py"

Contract fixed by these tests (technical-artist implements it):

- ``generate_room.load_params(path: Path) -> dict`` raises ``blender_common.GeneratorError`` with a
  message naming the offending key. Keys tested here: cabinet_width_m, cabinet_depth_m,
  cabinet_height_m, wall_gap_m (0.02 .. 0.05), skirting_height_m (0.08 .. 0.10), wall_height_m
  (about 2.4), lamp_bar_length_m, lamp_bar_depth_m. The file may hold more keys (floor and wall
  extents, wall side, door insets, bracket size); unknown and missing keys are rejected.
- ``blender_common.swap_in_group(moves, rename=os.replace)``: ``moves`` is a list of
  ``(new_path, final_path)``. All-or-nothing: after a failed rename every final path holds its old
  bytes (or does not exist when it did not before), and no stray file is left. Raises
  ``GeneratorError`` naming the failed file.
- ``room_palette.atlas_png() -> bytes`` returns a deterministic PNG.
- ``tools/blender/params/room.json`` holds the values of the issue.
"""

from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from collections.abc import Callable
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import blender_common  # noqa: E402
import generate_room  # noqa: E402
import room_palette  # noqa: E402

PARAMS = Path(__file__).resolve().parent / "params" / "room.json"
PNG_MAGIC = bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
RANGED = {
    "cabinet_width_m": (-1.0, 0.0, 9.0),
    "cabinet_depth_m": (-1.0, 0.0, 9.0),
    "cabinet_height_m": (-1.0, 0.0, 9.0),
    "wall_gap_m": (0.0, 0.01, 0.06, 0.5),
    "skirting_height_m": (0.0, 0.07, 0.11, 0.5),
    "wall_height_m": (0.0, 1.0, 10.0),
    "lamp_bar_length_m": (-1.0, 0.0, 9.0),
    "lamp_bar_depth_m": (-1.0, 0.0, 9.0),
}


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
            generate_room.load_params(self._write(data))
        for word in words:
            self.assertIn(word, str(raised.exception))

    def test_ac08_committed_file_has_the_issue_values(self) -> None:
        params = generate_room.load_params(PARAMS)
        self.assertAlmostEqual(params["cabinet_width_m"], 0.66)
        self.assertAlmostEqual(params["cabinet_depth_m"], 0.36)
        self.assertAlmostEqual(params["cabinet_height_m"], 0.75)
        self.assertAlmostEqual(params["wall_height_m"], 2.4, delta=0.1)
        self.assertAlmostEqual(params["lamp_bar_length_m"], 0.58)
        self.assertAlmostEqual(params["lamp_bar_depth_m"], 0.06)
        self.assertGreaterEqual(params["wall_gap_m"], 0.02)
        self.assertLessEqual(params["wall_gap_m"], 0.05)
        self.assertGreaterEqual(params["skirting_height_m"], 0.08)
        self.assertLessEqual(params["skirting_height_m"], 0.10)

    def test_ac08_each_ranged_key_out_of_range_is_rejected_with_its_name(self) -> None:
        for key, values in RANGED.items():
            for bad in values:
                with self.subTest(key=key, value=bad):
                    data = dict(self.base)
                    data[key] = bad
                    self._rejects(data, key)

    def test_ac08_non_number_is_rejected_with_the_key(self) -> None:
        for key in RANGED:
            for bad in ("0.6", None, True):
                with self.subTest(key=key, value=bad):
                    data = dict(self.base)
                    data[key] = bad
                    self._rejects(data, key)

    def test_ac08_each_missing_key_is_rejected_with_its_name(self) -> None:
        for key in self.base:
            with self.subTest(key=key):
                data = dict(self.base)
                del data[key]
                self._rejects(data, key)

    def test_ac08_unknown_key_is_rejected_with_its_name(self) -> None:
        data = dict(self.base)
        data["window_count"] = 2
        self._rejects(data, "window_count")

    def test_ac08_duplicate_key_is_rejected_with_its_name(self) -> None:
        text = PARAMS.read_text(encoding="utf-8").rstrip().rstrip("}").rstrip()
        text += ',\n  "wall_height_m": 2.5\n}\n'
        self._rejects(text, "wall_height_m")

    def test_ac08_invalid_json_and_missing_file_are_generator_errors(self) -> None:
        self._rejects("{not json")
        with self.assertRaises(blender_common.GeneratorError):
            generate_room.load_params(self.folder / "nope.json")

    def test_ac08_generator_error_is_the_shared_class(self) -> None:
        self.assertTrue(issubclass(generate_room.GeneratorError, blender_common.GeneratorError))


class PaletteTest(unittest.TestCase):
    def test_ac08_atlas_png_is_a_png(self) -> None:
        self.assertEqual(room_palette.atlas_png()[:8], PNG_MAGIC)

    def test_ac08_atlas_png_is_deterministic(self) -> None:
        self.assertEqual(room_palette.atlas_png(), room_palette.atlas_png())


def failing_rename(*blocked: Path) -> Callable[[Path, Path], None]:
    names = {path.name for path in blocked}

    def rename(source: Path, destination: Path) -> None:
        if Path(destination).name in names:
            raise OSError(f"injected failure for {Path(destination).name}")
        os.replace(source, destination)

    return rename


class SwapInGroupTest(unittest.TestCase):
    NAMES = ("cabinet.glb", "room_corner.glb", "lamp.glb", "room_palette_atlas.png")

    def setUp(self) -> None:
        self._temp = tempfile.TemporaryDirectory()
        self.addCleanup(self._temp.cleanup)
        self.folder = Path(self._temp.name)
        self.finals = [self.folder / name for name in self.NAMES]
        self.news = [self.folder / f".{name}.tmp" for name in self.NAMES]
        for index, path in enumerate(self.news):
            path.write_bytes(f"new {index}".encode())

    def _old(self) -> None:
        for index, path in enumerate(self.finals):
            path.write_bytes(f"old {index}".encode())

    def _swap(self, rename: Callable[[Path, Path], None]) -> None:
        blender_common.swap_in_group(list(zip(self.news, self.finals)), rename=rename)

    def _stray(self) -> list[str]:
        known = {p.name for p in self.finals} | {p.name for p in self.news}
        return sorted(p.name for p in self.folder.iterdir() if p.name not in known)

    def _contents(self) -> list[bytes | None]:
        return [p.read_bytes() if p.exists() else None for p in self.finals]

    def test_ac08_success_replaces_every_file_and_leaves_no_stray_file(self) -> None:
        self._old()
        self._swap(os.replace)
        self.assertEqual(self._contents(), [f"new {i}".encode() for i in range(4)])
        self.assertEqual(self._stray(), [])

    def test_ac08_success_on_a_first_run_creates_every_file(self) -> None:
        self._swap(os.replace)
        self.assertEqual(self._contents(), [f"new {i}".encode() for i in range(4)])
        self.assertEqual(self._stray(), [])

    def test_ac08_failure_on_the_last_file_restores_the_old_group(self) -> None:
        self._old()
        with self.assertRaises(blender_common.GeneratorError) as raised:
            self._swap(failing_rename(self.finals[3]))
        self.assertIn(self.finals[3].name, str(raised.exception))
        self.assertEqual(self._contents(), [f"old {i}".encode() for i in range(4)])
        self.assertEqual(self._stray(), [])

    def test_ac08_failure_on_the_second_file_restores_the_old_group(self) -> None:
        self._old()
        with self.assertRaises(blender_common.GeneratorError) as raised:
            self._swap(failing_rename(self.finals[1]))
        self.assertIn(self.finals[1].name, str(raised.exception))
        self.assertEqual(self._contents(), [f"old {i}".encode() for i in range(4)])
        self.assertEqual(self._stray(), [])

    def test_ac08_failure_on_a_first_run_leaves_no_new_file_behind(self) -> None:
        with self.assertRaises(blender_common.GeneratorError):
            self._swap(failing_rename(self.finals[3]))
        self.assertEqual(self._contents(), [None, None, None, None])
        self.assertEqual(self._stray(), [])


if __name__ == "__main__":
    unittest.main()
