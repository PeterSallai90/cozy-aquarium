"""Local tests for the substrate bake scripts (#28 AC 37 and 42): the pure parts of
``bake_substrate.py`` (packed flags, file format, header, size classes, parameters) and of
``substrate_stones.py`` (deterministic stone parameters, LOD triangle caps), and the committed
data files. Stdlib only, no Blender, no numpy. Not run in CI (ci.yml discovers tools/scripts
only); the GdUnit suites test_substrate_bake_data.gd and test_substrate_grain_assets.gd guard the
committed files in CI. Run from the repository root:

    python -m unittest discover -s tools/blender -p "test_*.py"

Not testable without Blender (manual, in the test report): the rigid-body settling, the visibility
pass and the glb export.
"""

from __future__ import annotations

import json
import random
import re
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import bake_substrate  # noqa: E402
import blender_common  # noqa: E402
import substrate_stones  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
BAKE_DIR = REPO / "game" / "assets" / "substrate" / "bake"
ASSEMBLER = REPO / "game" / "scenes" / "tank" / "substrate" / "substrate_assembler.gd"
# Packing range of the drawn sizes in metres per type (#28 AC 29 and 30).
PACKING_M = {
    "sand_fine": (0.001, 0.0025),
    "gravel_natural": (0.002, 0.006),
    "gravel_coloured": (0.003, 0.0065),
    "pebbles_river": (0.012, 0.032),
}
FILL_DEPTH_M = {
    "sand_fine": 0.03,
    "gravel_natural": 0.04,
    "gravel_coloured": 0.04,
    "pebbles_river": 0.06,
}
DATA_FILES = (
    "sand.bin",
    "gravel_natural.bin",
    "gravel_coloured.bin",
    "pebbles_river_tank_small_1.bin",
    "pebbles_river_tank_medium_1.bin",
    "pebbles_river_tank_large_1.bin",
)
# LOD0 cap and last LOD cap in triangles per stone class (#28 AC 37).
TRIANGLE_CAPS = {"angular": (64, 6), "round": (100, 6), "pebble": (640, 80)}


class PackedFlagsTest(unittest.TestCase):
    def test_ac42_the_bits_are_variant_above_pane_behind_and_exposure(self) -> None:
        self.assertEqual(bake_substrate.pack_flags(0, False, False, False, 0), 0)
        self.assertEqual(bake_substrate.pack_flags(5, False, False, False, 0), 5)
        self.assertEqual(bake_substrate.pack_flags(0, True, False, False, 0), 16)
        self.assertEqual(bake_substrate.pack_flags(0, False, True, False, 0), 32)
        self.assertEqual(bake_substrate.pack_flags(0, False, False, True, 0), 64)
        self.assertEqual(bake_substrate.pack_flags(0, False, False, False, 1), 128)
        self.assertEqual(bake_substrate.pack_flags(15, True, True, True, 15), 0x7FF)

    def test_ac42_pack_and_unpack_round_trip(self) -> None:
        for variant in (0, 3, 15):
            for exposure in (0, 7, 15):
                for bits in range(8):
                    flags = (bool(bits & 1), bool(bits & 2), bool(bits & 4))
                    packed = bake_substrate.pack_flags(variant, *flags, exposure)
                    self.assertEqual(
                        bake_substrate.unpack_flags(packed),
                        {
                            "variant": variant,
                            "above": flags[0],
                            "pane": flags[1],
                            "behind": flags[2],
                            "exposure": exposure,
                        },
                    )
                    self.assertEqual(packed & ~0x7FF, 0)

    def test_ac42_a_variant_or_exposure_out_of_range_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            bake_substrate.pack_flags(16, True, False, False, 0)
        with self.assertRaises(ValueError):
            bake_substrate.pack_flags(0, True, False, False, 16)

    def test_ac42_the_packed_value_survives_a_float32(self) -> None:
        import struct

        packed = bake_substrate.pack_flags(15, True, True, True, 15)
        self.assertEqual(int(struct.unpack("<f", struct.pack("<f", float(packed)))[0]), packed)


class FileFormatTest(unittest.TestCase):
    def _records(self, count: int) -> bytes:
        import struct

        values = []
        for index in range(count):
            packed = bake_substrate.pack_flags(index % 4, True, False, False, index % 16)
            values += [0.1 * index, 0.01, -0.2, 0.0, 0.0, 0.0, 1.0, 0.004, float(packed)]
        return struct.pack(f"<{len(values)}f", *values)

    def test_ac42_encode_writes_magic_version_header_and_records(self) -> None:
        data = bake_substrate.encode({"mode": "tiles", "sets": {}}, self._records(3))
        self.assertEqual(data[:4], b"CASB")
        self.assertEqual(int.from_bytes(data[4:8], "little"), bake_substrate.FORMAT_VERSION)
        length = int.from_bytes(data[8:12], "little")
        self.assertEqual(json.loads(data[12 : 12 + length].decode("utf-8"))["mode"], "tiles")
        self.assertEqual(len(data) - 12 - length, 3 * 36)

    def test_ac42_decode_reads_what_encode_wrote(self) -> None:
        header = {"mode": "tank", "sets": {"tank": {"offset": 0, "count": 5}}}
        got_header, records = bake_substrate.decode(bake_substrate.encode(header, self._records(5)))
        self.assertEqual(got_header, header)
        self.assertEqual(len(records), 5)
        self.assertAlmostEqual(records[4][0], 0.4, places=6)
        self.assertEqual(int(records[2][8]) & bake_substrate.FLAG_BITS, bake_substrate.FLAG_ABOVE)

    def test_ac42_a_broken_file_is_rejected(self) -> None:
        good = bake_substrate.encode({"mode": "tank"}, self._records(2))
        with self.assertRaises(ValueError):
            bake_substrate.decode(b"XASB" + good[4:])
        with self.assertRaises(ValueError):
            bake_substrate.decode(good[:4] + (2).to_bytes(4, "little") + good[8:])
        with self.assertRaises(ValueError):
            bake_substrate.decode(good[:-1])
        with self.assertRaises(ValueError):
            bake_substrate.encode({}, b"\0" * 35)


class SizeClassesTest(unittest.TestCase):
    def test_ac30_the_size_classes_lie_in_the_packing_range_of_the_type(self) -> None:
        params = bake_substrate.load_params()
        for name, (low, high) in PACKING_M.items():
            stats = bake_substrate.size_statistics(params[name]["size_classes"])
            self.assertAlmostEqual(stats["smallest_m"], low, msg=name)
            self.assertAlmostEqual(stats["largest_m"], high, msg=name)
            self.assertTrue(low < stats["median_m"] < high, name)

    def test_ac30_the_median_is_the_size_at_half_of_the_shares(self) -> None:
        stats = bake_substrate.size_statistics([[1.0, 2.0, 0.25], [2.0, 4.0, 0.5], [4.0, 5.0, 0.25]])
        self.assertAlmostEqual(stats["median_m"], 3.0)
        stats = bake_substrate.size_statistics([[1.0, 3.0, 1.0]])
        self.assertAlmostEqual(stats["median_m"], 2.0)

    def test_ac30_sampled_sizes_stay_inside_the_classes_and_follow_the_seed(self) -> None:
        classes = bake_substrate.load_params()["gravel_natural"]["size_classes"]
        first = [bake_substrate.sample_size(random.Random("a"), classes) for _ in range(1)]
        rng = random.Random("a")
        sizes = [bake_substrate.sample_size(rng, classes) for _ in range(2000)]
        self.assertEqual(sizes[0], first[0])
        self.assertTrue(all(0.002 <= size <= 0.006 for size in sizes))
        small = sum(1 for size in sizes if size < 0.003) / len(sizes)
        self.assertAlmostEqual(small, 0.25, delta=0.04)


class ParametersTest(unittest.TestCase):
    def setUp(self) -> None:
        self._temp = tempfile.TemporaryDirectory()
        self.addCleanup(self._temp.cleanup)
        self.base: dict = json.loads(bake_substrate.PARAMS_PATH.read_text(encoding="utf-8"))

    def _rejects(self, data: dict, *words: str) -> None:
        path = Path(self._temp.name) / "params.json"
        path.write_text(json.dumps(data), encoding="utf-8")
        with self.assertRaises(blender_common.GeneratorError) as raised:
            bake_substrate.load_params(path)
        for word in words:
            self.assertIn(word, str(raised.exception))

    def test_ac42_the_committed_file_has_the_four_data_types_with_the_decided_depths(self) -> None:
        params = bake_substrate.load_params()
        self.assertEqual(sorted(params), sorted(FILL_DEPTH_M))
        for name, depth in FILL_DEPTH_M.items():
            self.assertAlmostEqual(params[name]["fill_depth_m"], depth, msg=name)
        self.assertEqual(params["pebbles_river"]["mode"], "tank")
        self.assertEqual(params["sand_fine"]["data_set"], "sand")
        for name in ("sand_fine", "gravel_natural", "gravel_coloured"):
            self.assertEqual(params[name]["mode"], "tiles")
            self.assertGreaterEqual(params[name]["top"]["period_m"], 0.05)

    def test_ac42_a_missing_key_is_named(self) -> None:
        del self.base["gravel_natural"]["keep"]
        self._rejects(self.base, "gravel_natural.keep")

    def test_ac42_shares_that_do_not_add_up_are_rejected(self) -> None:
        self.base["sand_fine"]["size_classes"][0][2] = 0.4
        self._rejects(self.base, "sand_fine.size_classes")

    def test_ac40_a_top_tile_below_5_cm_is_rejected(self) -> None:
        self.base["sand_fine"]["top"]["period_m"] = 0.025
        self._rejects(self.base, "sand_fine.top.period_m")

    def test_ac40_fewer_than_three_top_fills_are_rejected(self) -> None:
        self.base["gravel_coloured"]["top"]["fills"] = 2
        self._rejects(self.base, "gravel_coloured.top.fills")

    def test_ac27_a_ring_shallower_than_two_median_stones_is_rejected(self) -> None:
        self.base["gravel_natural"]["ring"]["depth_m"] = 0.005
        self._rejects(self.base, "gravel_natural.ring.depth_m")

    def test_ac42_pebbles_get_one_data_set_per_tank_and_tiles_none(self) -> None:
        params = bake_substrate.load_params()
        self.assertEqual(
            bake_substrate.data_set_name(params["pebbles_river"], "tank_small_1"),
            "pebbles_river_tank_small_1",
        )
        self.assertEqual(bake_substrate.data_set_name(params["sand_fine"], ""), "sand")
        with self.assertRaises(blender_common.GeneratorError):
            bake_substrate.data_set_name(params["pebbles_river"], "")
        with self.assertRaises(blender_common.GeneratorError):
            bake_substrate.data_set_name(params["gravel_natural"], "tank_small_1")

    def test_ac42_the_tank_interiors_come_from_the_tank_parameter_files(self) -> None:
        self.assertEqual(bake_substrate.tank_interior("tank_small_1"), (0.4, 0.25))
        self.assertEqual(bake_substrate.tank_interior("tank_medium_1"), (0.6, 0.3))
        self.assertEqual(bake_substrate.tank_interior("tank_large_1"), (1.0, 0.4))
        with self.assertRaises(blender_common.GeneratorError):
            bake_substrate.tank_interior("tank_huge_1")


class HeaderTest(unittest.TestCase):
    def _header(self, type_name: str, tank: str) -> dict:
        params = bake_substrate.load_params()[type_name]
        shapes = {"half_extents": [[0.5, 0.3, 0.4]], "axes": [[0.5, 0.3, 0.4]], "lod_triangles": [[58]]}
        settling = bake_substrate.merge_settling(
            [
                {
                    "all_at_rest": True,
                    "largest_final_speed_m_per_s": 0.0001,
                    "rest_speed_limit_m_per_s": 0.0004,
                    "removed_while_moving": 2,
                    "batches": 3,
                    "frames": 400,
                    "sim_seconds": 1.5,
                },
                {
                    "all_at_rest": True,
                    "largest_final_speed_m_per_s": 0.0003,
                    "rest_speed_limit_m_per_s": 0.0004,
                    "removed_while_moving": 1,
                    "batches": 2,
                    "frames": 300,
                },
            ]
        )
        sets = {"tank": {"offset": 0, "count": 1}}
        return bake_substrate.build_header(
            type_name, params, tank, 28, "5.2.3 LTS", shapes, sets, settling, {}
        )

    def test_ac42_the_header_records_provenance_and_the_settling_report(self) -> None:
        header = self._header("pebbles_river", "tank_small_1")
        self.assertEqual(header["packing_version"], bake_substrate.PACKING_VERSION)
        self.assertEqual(header["format"], bake_substrate.FORMAT_VERSION)
        self.assertEqual(header["mode"], "tank")
        self.assertEqual(header["tank_id"], "tank_small_1")
        self.assertEqual(header["data_set"], "pebbles_river_tank_small_1")
        self.assertAlmostEqual(header["fill_depth"], 0.06)
        self.assertEqual(header["blender_version"], "5.2.3 LTS")
        self.assertEqual(header["seed"], 28)
        self.assertTrue(any("--type pebbles_river --tank tank_small_1" in c for c in header["commands"]))
        self.assertIs(header["settling"]["all_at_rest"], True)
        self.assertAlmostEqual(header["settling"]["largest_final_speed_m_per_s"], 0.0003)
        self.assertEqual(header["settling"]["removed_while_moving"], 3)
        self.assertAlmostEqual(header["median_size_m"], 0.016 + 0.008 * 0.2 / 0.45)
        self.assertAlmostEqual(header["largest_size_m"], 0.032)

    def test_ac42_a_tile_header_carries_the_ring_and_top_layout(self) -> None:
        header = self._header("sand_fine", "")
        self.assertEqual(header["data_set"], "sand")
        self.assertEqual(header["tank_id"], "")
        self.assertGreaterEqual(header["top"]["period_m"], 0.05)
        self.assertGreaterEqual(header["ring"]["corner_m"], header["ring"]["depth_m"])
        self.assertIn("lift_m", header["top"])
        self.assertTrue(any("--type sand_fine" in c for c in header["commands"]))

    def test_ac32_the_packing_version_equals_the_assembler_constant(self) -> None:
        source = ASSEMBLER.read_text(encoding="utf-8")
        found = re.search(r"const PACKING_VERSION: int = (\d+)", source)
        self.assertIsNotNone(found)
        self.assertEqual(int(found.group(1)), bake_substrate.PACKING_VERSION)


class StoneParametersTest(unittest.TestCase):
    def test_ac37_the_stone_parameters_are_the_same_for_the_same_seed(self) -> None:
        for name in substrate_stones.CLASSES:
            first = substrate_stones.class_parameters(name, 28)
            again = substrate_stones.class_parameters(name, 28)
            self.assertEqual(first, again, name)
            other = substrate_stones.class_parameters(name, 29)
            self.assertNotEqual(first, other, name)

    def test_ac37_each_mesh_class_has_at_least_three_variants_inside_its_shape_ranges(self) -> None:
        for name in substrate_stones.GLB_CLASSES:
            cls = substrate_stones.CLASSES[name]
            variants = substrate_stones.class_parameters(name)
            self.assertGreaterEqual(len(variants), 3, name)
            for variant in variants:
                a, b, c = variant["axes"]
                self.assertEqual(a, 1.0)
                self.assertTrue(cls["axes_b"][0] <= b <= cls["axes_b"][1], name)
                self.assertLessEqual(c, b, name)
                self.assertAlmostEqual(sum(q * q for q in variant["rotation"]), 1.0, places=9)
                for normal, _depth in variant["planes"]:
                    self.assertAlmostEqual(sum(n * n for n in normal), 1.0, places=9)

    def test_ac37_the_lod_chains_decrease_and_stay_within_the_triangle_caps(self) -> None:
        for name, (first_cap, last_cap) in TRIANGLE_CAPS.items():
            caps = substrate_stones.lod_triangle_caps(name)
            self.assertGreaterEqual(len(caps), 2, name)
            self.assertLessEqual(caps[0], first_cap, name)
            self.assertLessEqual(caps[-1], last_cap, name)
            self.assertEqual(caps, sorted(caps, reverse=True), name)
            self.assertEqual(len(set(caps)), len(caps), name)

    def test_ac37_an_unknown_class_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            substrate_stones.class_parameters("boulder")


class CommittedDataTest(unittest.TestCase):
    def test_ac42_every_committed_file_decodes_with_flags_and_a_settled_report(self) -> None:
        for file_name in DATA_FILES:
            path = BAKE_DIR / file_name
            data = path.read_bytes() if path.is_file() else b""
            if not data.startswith(b"CASB"):
                self.skipTest(f"{file_name} is missing or a Git LFS pointer")
            header, records = bake_substrate.decode(data)
            self.assertLessEqual(len(data), 1024 * 1024, file_name)
            self.assertEqual(header["packing_version"], bake_substrate.PACKING_VERSION, file_name)
            self.assertIs(header["settling"]["all_at_rest"], True, file_name)
            self.assertLessEqual(
                header["settling"]["largest_final_speed_m_per_s"],
                header["settling"]["rest_speed_limit_m_per_s"],
                file_name,
            )
            self.assertEqual(len(records), sum(s["count"] for s in header["sets"].values()))
            low, high = PACKING_M[header["type"]]
            for record in records:
                packed = int(record[8])
                self.assertNotEqual(packed & bake_substrate.FLAG_BITS, 0, file_name)
                self.assertLess(packed & bake_substrate.VARIANT_MASK, len(header["half_extents"]))
                self.assertTrue(low - 1e-6 <= record[7] <= high + 1e-6, file_name)


if __name__ == "__main__":
    unittest.main()
