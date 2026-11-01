"""Tests for check_asset_licenses.py, one test per acceptance criterion of issue #67.

Each test builds a small fixture tree (a game/ folder and docs/asset-licenses.md) in a temporary
directory and calls check(). Assertions use the exit code and substrings only: the two-space
indented ERROR path lines, the stale WARNING line, and the absence of WARNING or ERROR lines.
They never assert the summary sentence or the ERROR header text.

AC9 is a plain run of the script on the real repository, recorded in the test report. It is not a
unit test, because a stale-row warning must not fail CI (it is cleanup lag, exit 0 by design).
AC11 and AC12 concern ci.yml and are verified by the tester outside this file.

Run: python -m unittest discover -s tools/scripts -p "test_*.py"
"""

from __future__ import annotations

import contextlib
import io
import tempfile
import unittest
from pathlib import Path

import check_asset_licenses

TABLE_HEADER = (
    "| File | Source | Author | License | Link | Added |\n"
    "| --- | --- | --- | --- | --- | --- |\n"
)


class CheckAssetLicensesTest(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root: Path = Path(tmp.name)
        (self.root / "game").mkdir()

    def write_log(self, *files: str) -> None:
        """Write docs/asset-licenses.md with one row per path; no paths gives a header-only table."""
        log = self.root / "docs" / "asset-licenses.md"
        log.parent.mkdir(parents=True, exist_ok=True)
        rows = "".join(f"| `{f}` | s | a | MIT | l | 2026-11-01 |\n" for f in files)
        log.write_text("# Asset licenses\n\nIntro.\n\n" + TABLE_HEADER + rows, encoding="utf-8")

    def touch(self, rel: str) -> None:
        path = self.root / "game" / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("x", encoding="utf-8")

    def run_check(self) -> tuple[int, list[str]]:
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = check_asset_licenses.check(self.root)
        return code, out.getvalue().splitlines()

    def assert_no_line_starting_with(self, prefix: str, lines: list[str]) -> None:
        self.assertEqual([x for x in lines if x.startswith(prefix)], [], lines)

    def test_ac01_logged_addon_folder_passes_without_warning(self) -> None:
        self.touch("addons/gdUnit4/plugin.cfg")
        self.write_log("addons/gdUnit4/")
        code, lines = self.run_check()
        self.assertEqual(code, 0, lines)
        self.assert_no_line_starting_with("WARNING", lines)
        self.assertNotIn("  addons/gdUnit4/", lines)

    def test_ac02_unlogged_addon_folder_is_reported(self) -> None:
        self.touch("addons/foo/plugin.cfg")
        self.write_log()
        code, lines = self.run_check()
        self.assertEqual(code, 1, lines)
        self.assertIn("  addons/foo/", lines)

    def test_ac03_row_without_trailing_slash_covers_addon(self) -> None:
        self.touch("addons/foo/plugin.cfg")
        self.write_log("addons/foo")
        code, lines = self.run_check()
        self.assertEqual(code, 0, lines)
        self.assert_no_line_starting_with("WARNING", lines)
        self.assertNotIn("  addons/foo/", lines)

    def test_ac04_stale_addon_row_warns_and_exits_zero(self) -> None:
        self.write_log("addons/gone/")
        code, lines = self.run_check()
        self.assertEqual(code, 0, lines)
        self.assertIn(
            "WARNING: docs/asset-licenses.md lists addons/gone/, which does not exist.", lines
        )

    def test_ac05_loose_addon_file_needs_its_own_row(self) -> None:
        self.touch("addons/readme.txt")
        self.write_log()
        code, lines = self.run_check()
        self.assertEqual(code, 1, lines)
        self.assertIn("  addons/readme.txt", lines)

    def test_ac05_loose_addon_file_with_exact_row_passes(self) -> None:
        self.touch("addons/readme.txt")
        self.write_log("addons/readme.txt")
        code, lines = self.run_check()
        self.assertEqual(code, 0, lines)
        self.assert_no_line_starting_with("WARNING", lines)

    def test_ac06_sidecar_and_gitkeep_files_are_not_reported(self) -> None:
        for name in ("plugin.cfg", "icon.png.import", "a.gd.uid", "sub/.gitkeep"):
            self.touch("addons/foo/" + name)
        self.touch("assets/x.glb.import")
        self.touch("assets/.gitkeep")
        self.write_log("addons/foo/")
        code, lines = self.run_check()
        self.assertEqual(code, 0, lines)
        self.assert_no_line_starting_with("WARNING", lines)
        self.assert_no_line_starting_with("ERROR", lines)
        for line in lines:
            for ignored in (".import", ".uid", ".gitkeep"):
                self.assertNotIn(ignored, line)

    def test_ac07_missing_addons_folder_is_fine(self) -> None:
        self.write_log()
        code, lines = self.run_check()
        self.assertEqual(code, 0, lines)
        self.assert_no_line_starting_with("ERROR", lines)
        self.assertTrue(lines, "the summary is still printed")

    def test_ac07_empty_addons_folder_is_fine(self) -> None:
        (self.root / "game" / "addons").mkdir()
        self.write_log()
        code, lines = self.run_check()
        self.assertEqual(code, 0, lines)
        self.assert_no_line_starting_with("ERROR", lines)
        self.assertTrue(lines, "the summary is still printed")

    def test_ac07_addon_folder_without_files_is_not_an_addon(self) -> None:
        (self.root / "game" / "addons" / "empty" / "sub").mkdir(parents=True)
        self.write_log()
        code, lines = self.run_check()
        self.assertEqual(code, 0, lines)
        self.assert_no_line_starting_with("ERROR", lines)
        self.assertNotIn("  addons/empty/", lines)

    def test_ac08_unlogged_asset_still_fails_with_logged_addon(self) -> None:
        self.touch("addons/foo/plugin.cfg")
        self.touch("assets/room/a.glb")
        self.write_log("addons/foo/")
        code, lines = self.run_check()
        self.assertEqual(code, 1, lines)
        self.assertIn("  assets/room/a.glb", lines)
        self.assertNotIn("  addons/foo/", lines)

    def test_ac10_missing_license_log_still_fails(self) -> None:
        self.touch("addons/foo/plugin.cfg")
        code, lines = self.run_check()
        self.assertEqual(code, 1, lines)
        self.assertIn("ERROR: docs/asset-licenses.md is missing.", lines)

    def test_ac13_folder_row_under_assets_does_not_cover_files(self) -> None:
        self.touch("assets/room/a.glb")
        self.write_log("assets/room/")
        code, lines = self.run_check()
        self.assertEqual(code, 1, lines)
        self.assertIn("  assets/room/a.glb", lines)
        self.assert_no_line_starting_with("WARNING", lines)

    def test_ac14_parent_addons_row_covers_no_addon(self) -> None:
        self.touch("addons/foo/plugin.cfg")
        self.write_log("addons/")
        code, lines = self.run_check()
        self.assertEqual(code, 1, lines)
        self.assertIn("  addons/foo/", lines)
        self.assert_no_line_starting_with("WARNING", lines)

    def test_ac14_parent_addons_row_without_slash_covers_no_addon(self) -> None:
        self.touch("addons/foo/plugin.cfg")
        self.write_log("addons")
        code, lines = self.run_check()
        self.assertEqual(code, 1, lines)
        self.assertIn("  addons/foo/", lines)
        self.assert_no_line_starting_with("WARNING", lines)

    def test_ac15_file_row_inside_addon_does_not_cover_folder(self) -> None:
        self.touch("addons/foo/plugin.cfg")
        self.touch("addons/foo/a.gd")
        self.write_log("addons/foo/plugin.cfg")
        code, lines = self.run_check()
        self.assertEqual(code, 1, lines)
        self.assertIn("  addons/foo/", lines)


if __name__ == "__main__":
    unittest.main()
