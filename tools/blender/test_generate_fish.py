"""Local tests for the pair swap in generate_fish.py (#115). Stdlib only, no Blender.

Not run in CI (ci.yml discovers tools/scripts only). Run from the repository root:

    python -m unittest discover -s tools/blender -p "test_*.py"

The failing rename is injected through the ``rename`` parameter of ``swap_in_pair``.
"""

from __future__ import annotations

import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import generate_fish  # noqa: E402

OLD_GLB = b"old glb"
OLD_ATLAS = b"old atlas"
NEW_GLB = b"new glb"
NEW_ATLAS = b"new atlas"
BACKUP_NAME = ".proof_fish.bak.glb"


def failing_rename(*blocked: Path):
    """A rename that raises OSError when the destination is one of ``blocked``."""
    blocked_names = {path.name for path in blocked}

    def rename(source: Path, destination: Path) -> None:
        if Path(destination).name in blocked_names:
            raise OSError(f"injected failure for {Path(destination).name}")
        os.replace(source, destination)

    return rename


class SwapInPairTest(unittest.TestCase):
    def setUp(self) -> None:
        self._temp = tempfile.TemporaryDirectory()
        self.addCleanup(self._temp.cleanup)
        self.folder = Path(self._temp.name)
        self.glb = self.folder / "proof_fish.glb"
        self.atlas = self.folder / "proof_palette_atlas.png"
        self.new_glb = self.folder / "proof_fish.tmp.glb"
        self.new_atlas = self.folder / "proof_palette_atlas.tmp.png"
        self.new_glb.write_bytes(NEW_GLB)
        self.new_atlas.write_bytes(NEW_ATLAS)

    def _write_old_pair(self) -> None:
        self.glb.write_bytes(OLD_GLB)
        self.atlas.write_bytes(OLD_ATLAS)

    def _swap(self, rename) -> None:
        generate_fish.swap_in_pair(
            self.new_glb, self.glb, self.new_atlas, self.atlas, rename=rename
        )

    def _leftovers(self) -> list[str]:
        """Names in the folder that are not the pair or the caller's own temp files."""
        own = {self.glb.name, self.atlas.name, self.new_glb.name, self.new_atlas.name}
        return sorted(p.name for p in self.folder.iterdir() if p.name not in own)

    def test_criterion_01_atlas_rename_fails_old_pair_is_restored(self) -> None:
        self._write_old_pair()
        with self.assertRaises(generate_fish.GeneratorError) as raised:
            self._swap(failing_rename(self.atlas))
        self.assertIn("proof_palette_atlas.png", str(raised.exception))
        self.assertEqual(self.glb.read_bytes(), OLD_GLB)
        self.assertEqual(self.atlas.read_bytes(), OLD_ATLAS)
        self.assertEqual(self._leftovers(), [])

    def test_criterion_02_glb_rename_fails_old_pair_is_unchanged(self) -> None:
        self._write_old_pair()
        with self.assertRaises(generate_fish.GeneratorError) as raised:
            self._swap(failing_rename(self.glb))
        self.assertIn("proof_fish.glb", str(raised.exception))
        self.assertEqual(self.glb.read_bytes(), OLD_GLB)
        self.assertEqual(self.atlas.read_bytes(), OLD_ATLAS)
        self.assertEqual(self._leftovers(), [])

    def test_criterion_03_success_replaces_both_and_leaves_no_backup(self) -> None:
        self._write_old_pair()
        self._swap(os.replace)
        self.assertEqual(self.glb.read_bytes(), NEW_GLB)
        self.assertEqual(self.atlas.read_bytes(), NEW_ATLAS)
        self.assertEqual(self._leftovers(), [])

    def test_criterion_03_success_on_a_first_run_leaves_no_backup(self) -> None:
        self._swap(os.replace)
        self.assertEqual(self.glb.read_bytes(), NEW_GLB)
        self.assertEqual(self.atlas.read_bytes(), NEW_ATLAS)
        self.assertEqual(self._leftovers(), [])

    def test_criterion_04_first_run_atlas_rename_fails_new_glb_is_deleted(self) -> None:
        with self.assertRaises(generate_fish.GeneratorError) as raised:
            self._swap(failing_rename(self.atlas))
        self.assertIn("proof_palette_atlas.png", str(raised.exception))
        self.assertFalse(self.glb.exists())
        self.assertFalse(self.atlas.exists())
        self.assertEqual(self._leftovers(), [])

    def test_criterion_01_restore_failure_keeps_the_backup_and_names_it(self) -> None:
        self._write_old_pair()
        # The atlas rename fails, then the restore of the old .glb fails too: the backup
        # rename goes to the .glb name, so block that name for the second call only.
        calls: list[str] = []

        def rename(source: Path, destination: Path) -> None:
            calls.append(Path(destination).name)
            if Path(destination).name == self.atlas.name:
                raise OSError("injected failure for the atlas")
            if Path(source).name == BACKUP_NAME:
                raise OSError("injected failure for the restore")
            os.replace(source, destination)

        with self.assertRaises(generate_fish.GeneratorError) as raised:
            self._swap(rename)
        self.assertIn(BACKUP_NAME, str(raised.exception))
        backup = self.folder / BACKUP_NAME
        self.assertTrue(backup.is_file())
        self.assertEqual(backup.read_bytes(), OLD_GLB)


if __name__ == "__main__":
    unittest.main()
