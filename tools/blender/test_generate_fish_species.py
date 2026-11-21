"""Local tests for the species mode of generate_fish.py (#34 AC 11). Needs Blender on PATH.

Not run in CI (ci.yml discovers tools/scripts only; Blender is not installed there). Run from the
repository root, the tests are skipped when Blender is not on PATH:

    python -m unittest discover -s tools/blender -p "test_generate_fish_species.py"

Contract tested (technical plan of #34, group T1): ``--species <id>`` reads
``tools/blender/params/<id>.json`` and writes ``<id>.glb``, ``<id>_mask.png`` and the shared
``fish_palette_atlas.png`` into the folder of ``--out`` (a ``.glb`` path, as in #21). Two runs to
temporary folders give identical files. An unknown species id, a missing parameter file and an
unknown key in it exit non-zero with a ``generate_fish: error:`` message that names the cause, and
leave every committed file untouched. ``--params`` still overrides the parameter file, so the
failure cases need no new committed files.
"""

from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "blender" / "generate_fish.py"
PARAMS_DIR = ROOT / "tools" / "blender" / "params"
ASSET_DIR = ROOT / "game" / "assets" / "fish"
SPECIES = ("neon_tetra", "angelfish", "bronze_corydoras")
ATLAS = "fish_palette_atlas.png"
PREFIX = "generate_fish: error:"
TIMEOUT_SECONDS = 600


def _blender() -> str | None:
    return shutil.which("blender")


def _digest(folder: Path) -> dict[str, str]:
    """SHA-256 of every file below ``folder`` by relative path (empty when it does not exist)."""
    result: dict[str, str] = {}
    if folder.is_dir():
        for path in sorted(folder.rglob("*")):
            if path.is_file():
                result[path.relative_to(folder).as_posix()] = hashlib.sha256(
                    path.read_bytes()
                ).hexdigest()
    return result


@unittest.skipUnless(_blender(), "Blender is not on PATH")
class SpeciesModeTest(unittest.TestCase):
    def setUp(self) -> None:
        self._temp = tempfile.TemporaryDirectory()
        self.addCleanup(self._temp.cleanup)
        self.temp = Path(self._temp.name)

    def _run(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        command = [
            str(_blender()),
            "--background",
            "--python",
            str(SCRIPT),
            "--",
            *arguments,
        ]
        return subprocess.run(
            command,
            capture_output=True,
            text=True,
            cwd=ROOT,
            timeout=TIMEOUT_SECONDS,
            check=False,
        )

    def _committed(self) -> tuple[dict[str, str], dict[str, str]]:
        return _digest(ASSET_DIR), _digest(PARAMS_DIR)

    def _generate(self, species: str, folder: Path) -> subprocess.CompletedProcess[str]:
        folder.mkdir(parents=True, exist_ok=True)
        return self._run("--species", species, "--out", str(folder / f"{species}.glb"))

    def test_criterion_11_two_runs_for_each_species_give_identical_files(self) -> None:
        for species in SPECIES:
            first = self.temp / f"{species}_a"
            second = self.temp / f"{species}_b"
            for folder in (first, second):
                result = self._generate(species, folder)
                self.assertEqual(result.returncode, 0, f"{species}: {result.stderr[-2000:]}")
            expected = {f"{species}.glb", f"{species}_mask.png", ATLAS}
            self.assertTrue(
                expected <= set(_digest(first)), f"{species}: wrote only {sorted(_digest(first))}"
            )
            for name in expected:
                data = (first / name).read_bytes()
                self.assertGreater(len(data), 0, f"{species}: {name} is empty")
                self.assertEqual(data, (second / name).read_bytes(), f"{species}: {name} differs")

    def test_criterion_11_generating_to_a_temporary_folder_leaves_committed_files_alone(
        self,
    ) -> None:
        before = self._committed()
        result = self._generate("neon_tetra", self.temp / "out")
        self.assertEqual(result.returncode, 0, result.stderr[-2000:])
        self.assertEqual(self._committed(), before)

    def test_criterion_11_an_unknown_species_id_fails_names_it_and_changes_nothing(self) -> None:
        before = self._committed()
        result = self._generate("no_such_fish", self.temp / "out")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(PREFIX, result.stderr)
        self.assertIn("no_such_fish", result.stderr)
        self.assertEqual(self._committed(), before)
        self.assertEqual(_digest(self.temp / "out"), {})

    def test_criterion_11_a_missing_params_file_fails_names_it_and_changes_nothing(self) -> None:
        before = self._committed()
        missing = self.temp / "missing_params.json"
        out = self.temp / "out"
        out.mkdir()
        result = self._run(
            "--species", "neon_tetra", "--params", str(missing), "--out", str(out / "neon_tetra.glb")
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(PREFIX, result.stderr)
        self.assertIn("missing_params.json", result.stderr)
        self.assertEqual(self._committed(), before)
        self.assertEqual(_digest(out), {})

    def test_criterion_11_an_unknown_key_in_the_params_fails_names_it_and_changes_nothing(
        self,
    ) -> None:
        before = self._committed()
        source = PARAMS_DIR / "neon_tetra.json"
        self.assertTrue(source.is_file(), f"{source} is missing")
        data = json.loads(source.read_text(encoding="utf-8"))
        data["bogus_key_for_test"] = 1
        broken = self.temp / "broken_params.json"
        broken.write_text(json.dumps(data), encoding="utf-8")
        out = self.temp / "out"
        out.mkdir()
        result = self._run(
            "--species", "neon_tetra", "--params", str(broken), "--out", str(out / "neon_tetra.glb")
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(PREFIX, result.stderr)
        self.assertIn("bogus_key_for_test", result.stderr)
        self.assertEqual(self._committed(), before)
        self.assertEqual(_digest(out), {})

    def test_criterion_11_the_proof_default_still_needs_no_species(self) -> None:
        """The #21 interface (--params, --out, no --species) is unchanged: proof files stay put."""
        before = self._committed()
        out = self.temp / "proof"
        out.mkdir()
        result = self._run("--out", str(out / "proof_fish.glb"))
        self.assertEqual(result.returncode, 0, result.stderr[-2000:])
        self.assertEqual(self._committed(), before)
        self.assertTrue((out / "proof_fish.glb").is_file())


if __name__ == "__main__":
    unittest.main()
