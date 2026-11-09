"""Local tests for the room generator and the shared helpers (#22, AC 8; #24, AC 10, 12 and 14).
Stdlib only, no Blender. Not run in CI (ci.yml discovers tools/scripts only). Run from the
repository root:

    python -m unittest discover -s tools/blender -p "test_*.py"

Contract fixed by these tests (technical-artist implements it):

- ``generate_room.load_params(path: Path) -> dict`` raises ``blender_common.GeneratorError`` with a
  message naming the offending key. room.json holds the room and the furniture style only (#24 plan
  section 4): cabinet_width_m, cabinet_depth_m, lamp_bar_length_m and lamp_foot_span_m are dropped
  (unknown keys now) and back_wall_distance_m (0.215, room origin to the inner face of the back
  wall) is added. Keys tested here: cabinet_height_m, wall_gap_m (0.02 .. 0.05), skirting_height_m
  (0.08 .. 0.10), wall_height_m (about 2.4), lamp_bar_depth_m, back_wall_distance_m. Unknown and
  missing keys are rejected.
- ``generate_room.params_for_tank(room_params: dict, tank_params: dict) -> dict`` returns the
  merged, validated dictionary for one tank (tank_params as returned by
  ``generate_tank.load_params``). Derived with exterior = interior + 2 x glass on x and z:
  cabinet_width_m = exterior x + 0.05, cabinet_depth_m = exterior z + 0.05, lamp_bar_length_m =
  exterior x - 0.03, lamp_foot_span_m = exterior x - trim_size_m. It raises GeneratorError naming
  the key when a validator fails (for example the lamp feet no longer stand outside the bar ends).
  ``build_cabinet``, ``build_lamp`` and ``build_room`` are deterministic and each glb stays at most
  10,000 triangles for every tank.
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
import generate_tank  # noqa: E402
import room_palette  # noqa: E402

PARAMS_DIR = Path(__file__).resolve().parent / "params"
PARAMS = PARAMS_DIR / "room.json"
DROPPED = ("cabinet_width_m", "cabinet_depth_m", "lamp_bar_length_m", "lamp_foot_span_m")
# tank -> (cabinet width, cabinet depth, lamp bar length, lamp foot span), metres
FURNITURE = {
    "tank_small_1": (0.458, 0.308, 0.378, 0.398),
    "tank_medium_1": (0.66, 0.36, 0.58, 0.60),
    "tank_large_1": (1.066, 0.466, 0.986, 1.006),
}
PNG_MAGIC = bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
RANGED = {
    "cabinet_height_m": (-1.0, 0.0, 9.0),
    "wall_gap_m": (0.0, 0.01, 0.06, 0.5),
    "skirting_height_m": (0.0, 0.07, 0.11, 0.5),
    "wall_height_m": (0.0, 1.0, 10.0),
    "lamp_bar_depth_m": (-1.0, 0.0, 9.0),
    "back_wall_distance_m": (-1.0, 0.0, 9.0),
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
        self.assertAlmostEqual(params["cabinet_height_m"], 0.75)
        self.assertAlmostEqual(params["wall_height_m"], 2.4, delta=0.1)
        self.assertAlmostEqual(params["lamp_bar_depth_m"], 0.06)
        self.assertAlmostEqual(params["back_wall_distance_m"], 0.215)
        self.assertAlmostEqual(params["side_wall_offset_m"], 0.85)
        self.assertGreaterEqual(params["wall_gap_m"], 0.02)
        self.assertLessEqual(params["wall_gap_m"], 0.05)
        self.assertGreaterEqual(params["skirting_height_m"], 0.08)
        self.assertLessEqual(params["skirting_height_m"], 0.10)

    def test_ac12_the_furniture_keys_that_follow_the_tank_are_not_in_room_json(self) -> None:
        for key in DROPPED:
            with self.subTest(key=key):
                self.assertNotIn(key, self.base)
                data = dict(self.base)
                data[key] = 0.5
                self._rejects(data, key)

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


def tank_params(name: str) -> dict:
    return generate_tank.load_params(PARAMS_DIR / f"{name}.json")


class FurnitureForTankTest(unittest.TestCase):
    def setUp(self) -> None:
        self.room = generate_room.load_params(PARAMS)

    def _merged(self, name: str) -> dict:
        return generate_room.params_for_tank(self.room, tank_params(name))

    def test_ac10_the_derived_furniture_values_of_the_three_tanks(self) -> None:
        for name, (width, depth, bar, span) in FURNITURE.items():
            with self.subTest(tank=name):
                merged = self._merged(name)
                self.assertAlmostEqual(merged["cabinet_width_m"], width, places=6)
                self.assertAlmostEqual(merged["cabinet_depth_m"], depth, places=6)
                self.assertAlmostEqual(merged["lamp_bar_length_m"], bar, places=6)
                self.assertAlmostEqual(merged["lamp_foot_span_m"], span, places=6)

    def test_ac10_the_cabinet_overhangs_the_tank_by_2_5_cm_on_every_side(self) -> None:
        for name in FURNITURE:
            with self.subTest(tank=name):
                tank = tank_params(name)
                merged = self._merged(name)
                glass = tank["glass_thickness_m"]
                exterior_x = tank["interior_length_m"] + 2 * glass
                exterior_z = tank["interior_depth_m"] + 2 * glass
                overhang_x = (merged["cabinet_width_m"] - exterior_x) / 2
                self.assertAlmostEqual(overhang_x, 0.025, places=6)
                overhang_z = (merged["cabinet_depth_m"] - exterior_z) / 2
                self.assertAlmostEqual(overhang_z, 0.025, places=6)

    def test_ac12_the_lamp_bar_is_3_cm_shorter_than_the_exterior_and_6_cm_deep(self) -> None:
        for name in FURNITURE:
            with self.subTest(tank=name):
                tank = tank_params(name)
                merged = self._merged(name)
                exterior_x = tank["interior_length_m"] + 2 * tank["glass_thickness_m"]
                self.assertAlmostEqual(merged["lamp_bar_length_m"], exterior_x - 0.03, places=6)
                self.assertAlmostEqual(merged["lamp_bar_depth_m"], 0.06, places=6)
                self.assertAlmostEqual(
                    merged["lamp_foot_span_m"], exterior_x - tank["trim_size_m"], places=6
                )

    def test_ac10_the_cabinet_mesh_has_the_derived_footprint_and_the_075_height(self) -> None:
        for name, (width, depth, _bar, _span) in FURNITURE.items():
            with self.subTest(tank=name):
                low, high = generate_room.build_cabinet(self._merged(name)).bounds()
                self.assertAlmostEqual(high[0] - low[0], width, places=6)
                self.assertAlmostEqual(high[2] - low[2], depth, places=6)
                self.assertAlmostEqual(high[1] - low[1], 0.75, places=6)
                self.assertAlmostEqual(low[1], 0.0, places=6)

    def test_ac12_the_lamp_bar_mesh_has_the_derived_length(self) -> None:
        for name, (_width, _depth, bar, _span) in FURNITURE.items():
            with self.subTest(tank=name):
                meshes = generate_room.build_lamp(self._merged(name))
                low, high = meshes["lamp"].bounds()
                self.assertAlmostEqual(high[0] - low[0], bar, places=6)

    def test_ac14_every_furniture_mesh_and_the_room_are_within_the_triangle_budget(self) -> None:
        for name in FURNITURE:
            with self.subTest(tank=name):
                merged = self._merged(name)
                cabinet = generate_room.build_cabinet(merged).triangle_count()
                lamp = sum(m.triangle_count() for m in generate_room.build_lamp(merged).values())
                self.assertLessEqual(cabinet, 10000)
                self.assertLessEqual(lamp, 10000)
        room = sum(m.triangle_count() for m in generate_room.build_room(self.room).values())
        self.assertLessEqual(room, 10000)

    def test_ac14_the_meshes_are_deterministic(self) -> None:
        for name in FURNITURE:
            with self.subTest(tank=name):
                first = generate_room.build_cabinet(self._merged(name))
                second = generate_room.build_cabinet(self._merged(name))
                self.assertEqual(first.vertices, second.vertices)
                self.assertEqual(first.faces, second.faces)
                lamp_a = generate_room.build_lamp(self._merged(name))
                lamp_b = generate_room.build_lamp(self._merged(name))
                for key in lamp_a:
                    self.assertEqual(lamp_a[key].vertices, lamp_b[key].vertices)
        room_a = generate_room.build_room(self.room)
        room_b = generate_room.build_room(self.room)
        for key in room_a:
            self.assertEqual(room_a[key].vertices, room_b[key].vertices)

    def test_ac10_the_room_is_one_fixed_asset_whatever_the_tank(self) -> None:
        meshes = generate_room.build_room(self.room)
        low, high = meshes["BackWall"].bounds()
        # glTF frame: the wall plane is at z = -back_wall_distance_m, the same for every tank.
        self.assertAlmostEqual(low[2], -0.215, places=6)
        self.assertAlmostEqual(high[2], -0.215, places=6)

    def test_ac12_a_trim_too_wide_for_the_lamp_feet_is_rejected_naming_the_foot_span(self) -> None:
        tank = tank_params("tank_small_1")
        tank["trim_size_m"] = 0.025
        with self.assertRaises(blender_common.GeneratorError) as raised:
            generate_room.params_for_tank(self.room, tank)
        self.assertIn("lamp_foot_span_m", str(raised.exception))

    def test_ac10_a_tank_that_leaves_the_side_wall_too_close_is_rejected(self) -> None:
        tank = tank_params("tank_large_1")
        tank["interior_length_m"] = 1.50
        with self.assertRaises(blender_common.GeneratorError) as raised:
            generate_room.params_for_tank(self.room, tank)
        self.assertIn("side_wall_offset_m", str(raised.exception))


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
