"""Tests for classify_asset_license_change.py, written from the technical plan of issue #122.

The classifier decides whether a change to docs/asset-licenses.md may skip the owner gate (only
exempt own-project data-file rows) or must add needs:owner. Most tests call classify() with
in-memory logs and dict-backed readers. Readers take a repo-relative path (so a file named in the
File column as `assets/x.png` is read as game/assets/x.png, a generator as tools/...) and return
bytes, or None when the path is missing. The CLI tests build a temporary git repository.

The classifier module does not exist until the implementation lands, so it is imported in setUp:
every test then fails with a clear message instead of breaking test discovery.

Rule and criterion map (R = rule of the plan, AC = acceptance criterion of the issue):
- Unchanged and exempt (AC1): TestUnchangedAndExempt
- Third-party rows (AC2 to AC4): TestThirdPartyRows
- Reclassification (AC5): TestReclassification
- Own-row strictness (R4, AC6): TestOwnRowStrictness
- File types (R5, AC7): TestFileTypes
- Plain material check (R6, AC7): TestPlainMaterial
- Import sidecar (R7, R8): TestImportSidecar
- Which revision is read (R8, AC4): TestRevisionRead
- Non-row edits (R1, R2, AC8): TestNonRowEdits
- Malformed input (R3, R9, AC13): TestMalformedInput
- Command line (AC13): TestCommandLine
- Real log regression: TestRealLog
AC9 to AC12 (label behaviour, workflow, path rules) and AC15, AC16 are checked outside this file.

Run: python -m unittest discover -s tools/scripts -p "test_*.py"
"""

from __future__ import annotations

import dataclasses
import importlib
import re
import subprocess
import sys
import tempfile
import unittest
from collections.abc import Callable
from pathlib import Path
from types import ModuleType
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
SCRIPT = SCRIPT_DIR / "classify_asset_license_change.py"
REPO_ROOT = SCRIPT_DIR.parent.parent
LOG_PATH = "docs/asset-licenses.md"

HEADER = "| File | Source | Author | License | Link | Added |"
SEPARATOR = "| --- | --- | --- | --- | --- | --- |"
PRE = "# Asset licenses\n\nRule text before the table.\n\n"
POST = "\nClosing note after the table.\n"

AUTHOR = "Cozy Aquarium (AI, this project)"
LICENSE = "MIT (this project)"
GEN_SOURCE = (
    "Generated in-house by `tools/blender/generate_fish.py` from "
    "`tools/blender/params/x.json` (test asset)"
)
HAND_SOURCE = "Hand-written in this project (test asset)"
LINK = "https://github.com/PeterSallai90/cozy-aquarium/issues/122"
ADDED = "2026-11-09"

TOOL_FILES: dict[str, bytes] = {
    "tools/blender/generate_fish.py": b"# generator\n",
    "tools/blender/generate_room.py": b"# generator\n",
}

PLAIN_TRES = (
    '[gd_resource type="StandardMaterial3D" format=3]\n\n[resource]\n'
    'resource_name = "plain"\ntransparency = 1\n'
    "albedo_color = Color(0.86, 0.96, 0.93, 0.12)\nroughness = 0.05\n"
)
TEXTURE_TRES = (
    '[gd_resource type="StandardMaterial3D" format=3]\n\n'
    '[ext_resource type="Texture2D" uid="uid://abc123" '
    'path="res://assets/test/tex.png" id="1_tex"]\n\n'
    '[resource]\nalbedo_texture = ExtResource("1_tex")\n'
)


def cells_line(cells: list[str]) -> str:
    return "| " + " | ".join(cells) + " |"


def row(
    file_cell: str,
    source: str = GEN_SOURCE,
    author: str = AUTHOR,
    license_: str = LICENSE,
    link: str = LINK,
    added: str = ADDED,
) -> str:
    return cells_line([file_cell, source, author, license_, link, added])


def own_row(path: str, source: str = GEN_SOURCE, **kwargs: str) -> str:
    return row(f"`{path}`", source, **kwargs)


THIRD_CELLS = [
    "`assets/fonts/nunito/nunito_variable.ttf`",
    "Nunito Version 3.602, upstream `fonts/variable/Nunito[wght].ttf` at googlefonts/nunito",
    "The Nunito Project Authors",
    "SIL OFL 1.1; license text in `assets/fonts/nunito/OFL.txt`",
    "https://github.com/googlefonts/nunito",
    "2026-11-02",
]
THIRD_ROW = cells_line(THIRD_CELLS)
EXISTING_OWN = own_row("assets/fish/proof_fish.glb")
EXISTING_OWN_2 = own_row("assets/fish/proof_palette_atlas.png")
BASE_ROWS = [THIRD_ROW, EXISTING_OWN]
NEW_GLB = "assets/fish/new_fish.glb"


def make_log(
    rows: list[str],
    pre: str = PRE,
    header: str = HEADER,
    sep: str = SEPARATOR,
    post: str = POST,
) -> str:
    return pre + header + "\n" + sep + "\n" + "\n".join(rows) + "\n" + post


def files_of(extra: dict[str, bytes | str] | None = None) -> dict[str, bytes]:
    """Tool files plus extra entries (repo-relative paths; str values are UTF-8 encoded)."""
    out = dict(TOOL_FILES)
    for path, content in (extra or {}).items():
        out[path] = content.encode("utf-8") if isinstance(content, str) else content
    return out


def game_files(extra: dict[str, bytes | str]) -> dict[str, bytes]:
    """Like files_of, but keys are File-column paths (relative to game/)."""
    return files_of({"game/" + path: content for path, content in extra.items()})


def reader(files: dict[str, bytes]) -> Callable[[str], bytes | None]:
    return lambda path: files.get(path)


def read_disk(path: str) -> bytes | None:
    target = REPO_ROOT / path
    return target.read_bytes() if target.is_file() else None


class ClassifierCase(unittest.TestCase):
    """Loads the classifier lazily and offers verdict helpers."""

    mod: ModuleType

    def setUp(self) -> None:
        sys.path.insert(0, str(SCRIPT_DIR))
        try:
            self.mod = importlib.import_module("classify_asset_license_change")
        except ModuleNotFoundError as err:
            self.fail(f"tools/scripts/classify_asset_license_change.py is missing: {err}")
        finally:
            sys.path.remove(str(SCRIPT_DIR))

    def classify_logs(
        self,
        old_log: str | None,
        new_log: str | None,
        old_files: dict[str, bytes] | None = None,
        new_files: dict[str, bytes] | None = None,
    ) -> Any:
        return self.mod.classify(
            old_log,
            new_log,
            reader(old_files if old_files is not None else files_of()),
            reader(new_files if new_files is not None else files_of()),
        )

    def classify_rows(
        self,
        old_rows: list[str],
        new_rows: list[str],
        old_files: dict[str, bytes] | None = None,
        new_files: dict[str, bytes] | None = None,
        **new_log_kw: Any,
    ) -> Any:
        return self.classify_logs(
            make_log(old_rows), make_log(new_rows, **new_log_kw), old_files, new_files
        )

    def add_row(
        self, new_row: str, extra_files: dict[str, bytes | str] | None = None, **kw: Any
    ) -> Any:
        """Verdict for adding one row to BASE_ROWS; extra_files are File-column paths."""
        return self.classify_rows(
            BASE_ROWS, [*BASE_ROWS, new_row], new_files=game_files(extra_files or {}), **kw
        )

    def assert_exempt(self, verdict: Any, msg: str = "") -> None:
        self.assertTrue(verdict.exempt, f"expected exempt, got {verdict!r} {msg}")

    def assert_unchanged(self, verdict: Any) -> None:
        self.assertTrue(verdict.unchanged, f"expected unchanged, got {verdict!r}")

    def assert_gate(self, verdict: Any, msg: str = "") -> None:
        self.assertFalse(verdict.exempt, f"expected gate, got {verdict!r} {msg}")
        self.assertFalse(verdict.unchanged, f"expected gate, got {verdict!r} {msg}")
        self.assertTrue(verdict.reasons, f"a gate verdict needs a reason line {msg}")


class TestVerdict(ClassifierCase):
    def test_verdict_is_a_frozen_dataclass_with_the_three_fields(self) -> None:
        verdict = self.classify_logs(make_log(BASE_ROWS), make_log(BASE_ROWS))
        self.assertTrue(dataclasses.is_dataclass(verdict))
        names = {field.name for field in dataclasses.fields(verdict)}
        self.assertTrue({"exempt", "unchanged", "reasons"} <= names)
        with self.assertRaises(dataclasses.FrozenInstanceError):
            verdict.exempt = True


class TestUnchangedAndExempt(ClassifierCase):
    """AC1 logic: own data-file rows skip the gate."""

    def test_ac1_identical_log_is_unchanged(self) -> None:
        self.assert_unchanged(self.classify_rows(BASE_ROWS, BASE_ROWS))

    def test_ac1_adding_an_own_data_row_is_exempt_per_extension(self) -> None:
        for ext in (".glb", ".png", ".ogg", ".wav", ".mp3"):
            with self.subTest(ext=ext):
                path = f"assets/test/new_file{ext}"
                verdict = self.add_row(own_row(path), {path: b"data"})
                self.assert_exempt(verdict)

    def test_ac1_adding_a_hand_written_plain_tres_is_exempt(self) -> None:
        path = "assets/tank/materials/plain.tres"
        verdict = self.add_row(own_row(path, HAND_SOURCE), {path: PLAIN_TRES})
        self.assert_exempt(verdict)

    def test_ac1_hand_written_source_is_exempt_for_a_png(self) -> None:
        path = "assets/test/hand.png"
        self.assert_exempt(self.add_row(own_row(path, HAND_SOURCE), {path: b"png"}))

    def test_ac1_editing_the_source_text_of_an_exempt_row_is_exempt(self) -> None:
        edited = own_row("assets/fish/proof_fish.glb", GEN_SOURCE + ", regenerated")
        verdict = self.classify_rows(
            BASE_ROWS,
            [THIRD_ROW, edited],
            new_files=game_files({"assets/fish/proof_fish.glb": b"glb"}),
        )
        self.assert_exempt(verdict)

    def test_ac4_deleting_an_exempt_glb_row_is_exempt(self) -> None:
        self.assert_exempt(self.classify_rows(BASE_ROWS, [THIRD_ROW]))

    def test_ac1_adding_two_exempt_rows_is_exempt(self) -> None:
        a = own_row("assets/test/a.png")
        b = own_row("assets/test/b.png")
        verdict = self.classify_rows(
            BASE_ROWS,
            [*BASE_ROWS, a, b],
            new_files=game_files({"assets/test/a.png": b"x", "assets/test/b.png": b"x"}),
        )
        self.assert_exempt(verdict)


class TestThirdPartyRows(ClassifierCase):
    """AC2 to AC4: any third-party row change gates."""

    def test_ac2_adding_a_third_party_row_gates(self) -> None:
        other = THIRD_ROW.replace("nunito_variable.ttf", "other.ttf")
        self.assert_gate(self.add_row(other, {"assets/fonts/nunito/other.ttf": b"ttf"}))

    def test_ac3_one_exempt_and_one_third_party_row_gates(self) -> None:
        other = THIRD_ROW.replace("nunito_variable.ttf", "other.ttf")
        exempt = own_row("assets/test/a.png")
        verdict = self.classify_rows(
            BASE_ROWS,
            [*BASE_ROWS, exempt, other],
            new_files=game_files({"assets/test/a.png": b"x", "assets/fonts/nunito/other.ttf": b"x"}),
        )
        self.assert_gate(verdict)

    def test_ac4_changing_each_cell_of_a_third_party_row_gates(self) -> None:
        names = ["File", "Source", "Author", "License", "Link", "Added"]
        old_cells = THIRD_CELLS
        for index, name in enumerate(names):
            with self.subTest(cell=name):
                cells = list(old_cells)
                cells[index] = cells[index] + " changed"
                new_row = cells_line(cells)
                self.assertNotEqual(new_row, THIRD_ROW)
                verdict = self.classify_rows(
                    BASE_ROWS,
                    [new_row, EXISTING_OWN],
                    new_files=game_files({"assets/fonts/nunito/nunito_variable.ttf": b"x"}),
                )
                self.assert_gate(verdict)

    def test_ac4_deleting_a_third_party_row_gates(self) -> None:
        self.assert_gate(self.classify_rows(BASE_ROWS, [EXISTING_OWN]))

    def test_ac2_third_party_row_with_url_in_source_gates(self) -> None:
        path = "assets/test/url.png"
        source = "Generated in-house by `tools/blender/generate_fish.py` https://example.com/x"
        self.assert_gate(self.add_row(own_row(path, source), {path: b"x"}))


class TestReclassification(ClassifierCase):
    """AC5: changing which side of the own/third-party line a row sits on gates."""

    def test_ac5_own_to_non_own_through_each_cell_gates(self) -> None:
        cases = {
            "author": {"author": "Someone Else"},
            "license": {"license_": "CC0 1.0"},
            "source": {"source": "Downloaded from a website"},
        }
        for name, change in cases.items():
            with self.subTest(change=name):
                edited = own_row("assets/fish/proof_fish.glb", **change)
                verdict = self.classify_rows(
                    BASE_ROWS,
                    [THIRD_ROW, edited],
                    new_files=game_files({"assets/fish/proof_fish.glb": b"glb"}),
                )
                self.assert_gate(verdict)

    def test_ac5_non_own_to_own_gates(self) -> None:
        old_row = own_row("assets/fish/proof_fish.glb", author="Kenney")
        new_row = own_row("assets/fish/proof_fish.glb")
        verdict = self.classify_rows(
            [THIRD_ROW, old_row],
            [THIRD_ROW, new_row],
            new_files=game_files({"assets/fish/proof_fish.glb": b"glb"}),
        )
        self.assert_gate(verdict)

    def test_ac5_third_party_row_relabelled_as_own_gates(self) -> None:
        old_row = row(
            "`assets/test/x.png`",
            "Kenney pack",
            "Kenney",
            "CC0",
            "https://kenney.nl",
            "2026-11-01",
        )
        new_row = own_row("assets/test/x.png")
        verdict = self.classify_rows(
            [THIRD_ROW, old_row],
            [THIRD_ROW, new_row],
            new_files=game_files({"assets/test/x.png": b"x"}),
        )
        self.assert_gate(verdict)


class TestOwnRowStrictness(ClassifierCase):
    """R4 and AC6: the own row must match exactly."""

    def gate_added(self, new_row: str, path: str = "assets/test/x.png", msg: str = "") -> None:
        self.assert_gate(self.add_row(new_row, {path: b"x"}), msg)

    def test_ac6_source_with_url_or_marker_gates(self) -> None:
        markers = [
            "https://example.com",
            "http://example.com",
            "HTTP://EXAMPLE.COM",
            "://",
            "www.example.com",
            "license",
            "licence",
            "Copyright",
            "© 2026",
            "CC0",
            "CC-BY",
            "cc by",
            "third-party",
            "third party",
            "upstream",
            "Kenney",
            "freesound",
            "poly haven",
            "polyhaven",
            "ambientCG",
            "sketchfab",
            "opengameart",
            "itch.io",
            "Quaternius",
        ]
        for marker in markers:
            with self.subTest(marker=marker):
                for base in (GEN_SOURCE, HAND_SOURCE):
                    source = f"{base} using {marker} input"
                    self.gate_added(own_row("assets/test/x.png", source))

    def test_ac6_author_near_misses_gate(self) -> None:
        near = [
            AUTHOR + ".",
            AUTHOR[:-1],
            AUTHOR.lower(),
            AUTHOR.upper(),
            "By " + AUTHOR,
            AUTHOR + " and others",
            AUTHOR.replace("Cozy ", "Cozy  "),
            "Cozy Aquarium (AI, this  project)",
        ]
        for value in near:
            with self.subTest(author=value):
                self.gate_added(own_row("assets/test/x.png", author=value))

    def test_ac6_license_near_misses_gate(self) -> None:
        near = [
            LICENSE + ".",
            LICENSE[:-1],
            LICENSE.lower(),
            "mit (this project)",
            "The " + LICENSE,
            LICENSE + " or later",
            LICENSE.replace("MIT ", "MIT  "),
            "MIT",
        ]
        for value in near:
            with self.subTest(license=value):
                self.gate_added(own_row("assets/test/x.png", license_=value))

    def test_ac6_source_prefix_with_different_case_gates(self) -> None:
        sources = [
            GEN_SOURCE.replace("Generated", "generated"),
            GEN_SOURCE.replace("in-house", "In-House"),
            HAND_SOURCE.replace("Hand-written", "hand-written"),
            HAND_SOURCE.replace("Hand-written", "Hand written"),
            "Made in-house by `tools/blender/generate_fish.py`",
            "Some other text",
        ]
        for source in sources:
            with self.subTest(source=source):
                self.gate_added(own_row("assets/test/x.png", source))

    def test_ac6_generated_without_a_tools_path_gates(self) -> None:
        sources = [
            "Generated in-house by the pipeline",
            "Generated in-house by tools/blender/generate_fish.py",
            "Generated in-house by `scripts/generate_fish.py`",
            "Generated in-house by ``",
            "Generated in-house by `blender/generate_fish.py`",
        ]
        for source in sources:
            with self.subTest(source=source):
                self.gate_added(own_row("assets/test/x.png", source))

    def test_ac6_generated_with_a_missing_tools_path_gates(self) -> None:
        source = "Generated in-house by `tools/blender/does_not_exist.py` (test)"
        self.gate_added(own_row("assets/test/x.png", source))

    def test_ac6_a_tools_path_that_only_exists_at_the_old_revision_gates_an_added_row(
        self,
    ) -> None:
        path = "assets/test/x.png"
        source = "Generated in-house by `tools/blender/old_only.py` (test)"
        old_files = files_of({"tools/blender/old_only.py": b"x"})
        verdict = self.classify_rows(
            BASE_ROWS,
            [*BASE_ROWS, own_row(path, source)],
            old_files=old_files,
            new_files=game_files({path: b"x"}),
        )
        self.assert_gate(verdict)

    def test_ac6_link_outside_this_repository_gates(self) -> None:
        links = [
            "https://github.com/other/repo/issues/1",
            "https://github.com/PeterSallai90/other-repo/issues/1",
            "http://github.com/PeterSallai90/cozy-aquarium/issues/1",
            "https://github.com/PeterSallai90/cozy-aquarium/pulls/1",
            "https://github.com/PeterSallai90/cozy-aquarium/issues/abc",
            "https://github.com/PeterSallai90/cozy-aquarium",
            "https://github.com/PeterSallai90/cozy-aquarium/issues/1/extra",
            "https://example.com",
        ]
        for link in links:
            with self.subTest(link=link):
                self.gate_added(own_row("assets/test/x.png", link=link))

    def test_ac6_link_to_a_pull_request_of_this_repository_is_exempt(self) -> None:
        link = "https://github.com/PeterSallai90/cozy-aquarium/pull/123"
        verdict = self.add_row(own_row("assets/test/x.png", link=link), {"assets/test/x.png": b"x"})
        self.assert_exempt(verdict)

    def test_ac6_malformed_added_date_gates(self) -> None:
        for added in ("2026-1-08", "08-11-2026", "yesterday", "20261108", "2026-11-08T10:00"):
            with self.subTest(added=added):
                self.gate_added(own_row("assets/test/x.png", added=added))


class TestFileTypes(ClassifierCase):
    """R5 and AC7: only data-file extensions under assets/ are exempt."""

    def test_ac7_own_rows_with_other_file_types_or_paths_gate(self) -> None:
        cells = [
            "`assets/test/x.gd`",
            "`assets/test/x.gdshader`",
            "`assets/test/x.tscn`",
            "`assets/test/x.res`",
            "`assets/test/x.material`",
            "`assets/test/x.txt`",
            "`assets/test/x.ttf`",
            "`assets/test/x`",
            "`assets/test/x.PNG`",
            "`assets/test/x.GLB`",
            "`addons/x/`",
            "`addons/x.png`",
            "`scenes/x.png`",
            "`assets/../x.png`",
            "`assets/test/../x.png`",
            "`assets//x.png`",
            "`assets/*.png`",
            "`assets/test/`",
            "`assets/test x.png`",
            "assets/test/x.png",
            "`assets/test/a.png` `assets/test/b.png`",
            "`assets/test/x.png` and more",
            "``",
        ]
        for cell in cells:
            with self.subTest(file=cell):
                files: dict[str, bytes | str] = {}
                for part in re.findall(r"`([^`]*)`", cell) + [cell.strip("`")]:
                    files[part] = b"data"
                verdict = self.add_row(row(cell, HAND_SOURCE), files)
                self.assert_gate(verdict)

    def test_ac7_added_row_whose_file_is_missing_at_head_gates(self) -> None:
        self.assert_gate(self.add_row(own_row("assets/test/missing.png"), {}))

    def test_ac7_added_row_whose_file_exists_only_at_the_old_revision_gates(self) -> None:
        path = "assets/test/only_old.png"
        verdict = self.classify_rows(
            BASE_ROWS,
            [*BASE_ROWS, own_row(path)],
            old_files=game_files({path: b"x"}),
            new_files=files_of(),
        )
        self.assert_gate(verdict)

    def test_ac7_deleting_an_own_code_row_gates(self) -> None:
        for ext in (".gd", ".gdshader", ".tscn", ".res"):
            with self.subTest(ext=ext):
                path = f"assets/test/x{ext}"
                old = [*BASE_ROWS, own_row(path, HAND_SOURCE)]
                verdict = self.classify_rows(
                    old, BASE_ROWS, old_files=game_files({path: b"x"}), new_files=files_of()
                )
                self.assert_gate(verdict)

    def test_ac7_data_file_in_a_nested_assets_folder_is_exempt(self) -> None:
        path = "assets/audio/music/loop-01_a.ogg"
        self.assert_exempt(self.add_row(own_row(path), {path: b"ogg"}))


class TestPlainMaterial(ClassifierCase):
    """R6 and AC7: a .tres is exempt only as a plain StandardMaterial3D."""

    path = "assets/tank/materials/mat.tres"

    def tres_verdict(self, content: bytes | str) -> Any:
        return self.add_row(own_row(self.path, HAND_SOURCE), {self.path: content})

    def test_ac7_room_palette_shader_material_gates(self) -> None:
        content = (REPO_ROOT / "game/assets/room/materials/room_palette.tres").read_bytes()
        self.assert_gate(self.tres_verdict(content))

    def test_ac7_real_glass_placeholder_is_exempt(self) -> None:
        content = (REPO_ROOT / "game/assets/tank/materials/glass_placeholder.tres").read_bytes()
        self.assert_exempt(self.tres_verdict(content))

    def test_ac7_standard_material_with_a_texture_png_is_exempt(self) -> None:
        self.assert_exempt(self.tres_verdict(TEXTURE_TRES))

    def test_ac7_orm_material_is_exempt(self) -> None:
        content = PLAIN_TRES.replace("StandardMaterial3D", "ORMMaterial3D")
        self.assert_exempt(self.tres_verdict(content))

    def test_ac7_compressed_texture_ext_resource_is_exempt(self) -> None:
        content = TEXTURE_TRES.replace('type="Texture2D"', 'type="CompressedTexture2D"')
        self.assert_exempt(self.tres_verdict(content))

    def test_ac7_standard_material_with_a_script_or_shader_gates(self) -> None:
        script_ext = (
            '[ext_resource type="Script" uid="uid://s1" path="res://assets/test/x.gd" '
            'id="1_s"]\n\n'
        )
        shader_ext = (
            '[ext_resource type="Shader" uid="uid://s2" '
            'path="res://shaders/palette_atlas.gdshader" id="1_s"]\n\n'
        )
        head = '[gd_resource type="StandardMaterial3D" format=3]\n\n'
        cases: dict[str, bytes | str] = {
            "script property": PLAIN_TRES + 'script = ExtResource("1_s")\n',
            "script ext_resource": head + script_ext + '[resource]\nscript = ExtResource("1_s")\n',
            "script ext_resource unused": head + script_ext + "[resource]\nroughness = 0.5\n",
            "custom type script": PLAIN_TRES + 'metadata/_custom_type_script = "uid://abc"\n',
            "sub_resource": head + '[sub_resource type="Gradient" id="g"]\n\n' + "[resource]\n",
            "shader ext_resource": head + shader_ext + "[resource]\nroughness = 0.5\n",
            "shader material": PLAIN_TRES.replace("StandardMaterial3D", "ShaderMaterial"),
            "lfs pointer": (
                "version https://git-lfs.github.com/spec/v1\n"
                "oid sha256:" + "0" * 64 + "\nsize 100\n"
            ),
            "invalid utf-8": b'[gd_resource type="StandardMaterial3D" format=3]\n\xff\xfe\n',
            "resource type": PLAIN_TRES.replace("StandardMaterial3D", "Resource"),
            "gradient type": PLAIN_TRES.replace("StandardMaterial3D", "Gradient"),
            "empty file": b"",
            "gdscript word": PLAIN_TRES + "# GDScript note\n",
            "garbage line": PLAIN_TRES + "this is not a key value line\n",
        }
        for name, content in cases.items():
            with self.subTest(case=name):
                self.assert_gate(self.tres_verdict(content), name)

    def test_review3_next_pass_gates(self) -> None:
        cases = {
            "ext_resource": PLAIN_TRES + 'next_pass = ExtResource("1_np")' + chr(10),
            "sub_resource": PLAIN_TRES + 'next_pass = SubResource("m_1")' + chr(10),
        }
        for name, content in cases.items():
            with self.subTest(case=name):
                self.assert_gate(self.tres_verdict(content), name)

    def test_ac7_ext_resource_that_is_not_a_texture_png_gates(self) -> None:
        cases = {
            "wrong type": TEXTURE_TRES.replace('type="Texture2D"', 'type="Material"'),
            "outside assets": TEXTURE_TRES.replace("res://assets/test", "res://addons/test"),
            "not png": TEXTURE_TRES.replace("tex.png", "tex.tres"),
            "no path": TEXTURE_TRES.replace('path="res://assets/test/tex.png" ', ""),
        }
        for name, content in cases.items():
            with self.subTest(case=name):
                self.assert_gate(self.tres_verdict(content), name)


class TestImportSidecar(ClassifierCase):
    """R7: a sidecar that binds a script, shader or non-plain material gates the added row."""

    def sidecar_verdict(self, sidecar: bytes | str | None, ext: str = ".glb", **extra: Any) -> Any:
        path = f"assets/test/new_file{ext}"
        files: dict[str, bytes | str] = {path: b"data"}
        if sidecar is not None:
            files[path + ".import"] = sidecar
        files.update(extra)
        return self.add_row(own_row(path), files)

    @staticmethod
    def real_sidecar(name: str) -> str:
        return (REPO_ROOT / "game/assets" / name).read_text(encoding="utf-8")

    def test_r7_proof_fish_sidecar_is_exempt(self) -> None:
        self.assert_exempt(self.sidecar_verdict(self.real_sidecar("fish/proof_fish.glb.import")))

    def test_r7_png_sidecar_is_exempt(self) -> None:
        sidecar = self.real_sidecar("fish/proof_palette_atlas.png.import")
        self.assert_exempt(self.sidecar_verdict(sidecar, ".png"))

    def test_r7_no_sidecar_is_exempt(self) -> None:
        self.assert_exempt(self.sidecar_verdict(None))

    def test_r7_cabinet_sidecar_binding_room_palette_gates(self) -> None:
        palette = (REPO_ROOT / "game/assets/room/materials/room_palette.tres").read_bytes()
        verdict = self.sidecar_verdict(
            self.real_sidecar("room/cabinet.glb.import"),
            **{"assets/room/materials/room_palette.tres": palette},
        )
        self.assert_gate(verdict)

    def test_r7_non_empty_import_script_gates(self) -> None:
        sidecar = self.real_sidecar("fish/proof_fish.glb.import")
        sidecar = sidecar.replace('import_script/path=""', 'import_script/path="res://tools/x.gd"')
        self.assert_gate(self.sidecar_verdict(sidecar))

    def test_r7_root_script_that_is_not_null_gates(self) -> None:
        sidecar = self.real_sidecar("fish/proof_fish.glb.import")
        sidecar = sidecar.replace(
            "nodes/root_script=null", 'nodes/root_script="res://assets/test/x.gd"'
        )
        self.assert_gate(self.sidecar_verdict(sidecar))

    def test_r7_sidecar_mentioning_a_gd_or_gdshader_file_gates(self) -> None:
        sidecar = self.real_sidecar("fish/proof_fish.glb.import")
        for extra in ('custom="res://a/b.gd"', 'custom="res://shaders/a.gdshader"'):
            with self.subTest(extra=extra):
                self.assert_gate(self.sidecar_verdict(sidecar + extra + "\n"))

    def test_r7_lfs_pointer_sidecar_gates(self) -> None:
        pointer = "version https://git-lfs.github.com/spec/v1\noid sha256:" + "0" * 64 + "\nsize 9\n"
        self.assert_gate(self.sidecar_verdict(pointer))

    def test_r7_sidecar_with_external_plain_material_is_exempt(self) -> None:
        mat = "assets/test/materials/plain.tres"
        sidecar = self.real_sidecar("room/cabinet.glb.import").replace(
            "res://assets/room/materials/room_palette.tres", "res://" + mat
        )
        self.assert_exempt(self.sidecar_verdict(sidecar, **{mat: PLAIN_TRES}))

    def test_r7_sidecar_with_other_resource_references_gates(self) -> None:
        sidecar = self.real_sidecar("fish/proof_fish.glb.import")
        for ref in ("res://assets/test/m.res", "res://assets/test/m.material"):
            with self.subTest(ref=ref):
                self.assert_gate(self.sidecar_verdict(sidecar + f'extra_ref="{ref}"\n'))
        for ref in ("res://assets/test/s.tscn", "res://assets/test/s.scn"):
            with self.subTest(ref=ref):
                self.assert_gate(self.sidecar_verdict(sidecar + f'extra_ref="{ref}"\n'))

    def test_review1_uid_only_external_material_gates(self) -> None:
        palette = (REPO_ROOT / "game/assets/room/materials/room_palette.tres").read_bytes()
        mat = "assets/room/materials/room_palette.tres"
        cabinet = self.real_sidecar("room/cabinet.glb.import")
        uid_only = cabinet.replace(
            '"use_external/fallback_path": "res://assets/room/materials/room_palette.tres",\n',
            "",
        ).replace(
            '"use_external/path": "res://assets/room/materials/room_palette.tres"',
            '"use_external/path": "uid://ck2quutgkmq6v"',
        )
        self.assertIn("uid://ck2quutgkmq6v", uid_only)
        self.assertNotIn("room_palette.tres", uid_only)
        for ext in (".glb", ".png"):
            with self.subTest(ext=ext):
                self.assert_gate(self.sidecar_verdict(uid_only, ext, **{mat: palette}))

    def test_review1_uid_external_material_pointing_at_a_plain_material_still_gates(self) -> None:
        sidecar = self.real_sidecar("fish/proof_fish.glb.import") + (
            '_subresources={"materials": {"m": {"use_external/path": "uid://abc123"}}}\n'
        )
        self.assert_gate(self.sidecar_verdict(sidecar))

    def test_review1_any_uid_outside_the_remap_uid_line_gates(self) -> None:
        sidecar = self.real_sidecar("fish/proof_fish.glb.import")
        for extra in (
            'custom_ref="uid://abc123"',
            "custom_ref=uid://abc123",
            'dest_uid="uid://abc123"',
            'other/uid="uid://abc123"',
        ):
            with self.subTest(extra=extra):
                self.assert_gate(self.sidecar_verdict(sidecar + extra + "\n"))

    def test_review1_remap_uid_line_alone_stays_exempt(self) -> None:
        for name, ext in (
            ("fish/proof_fish.glb.import", ".glb"),
            ("fish/proof_palette_atlas.png.import", ".png"),
        ):
            with self.subTest(sidecar=name):
                sidecar = self.real_sidecar(name)
                self.assertRegex(sidecar, r'(?m)^uid="uid://[a-z0-9]+"$')
                self.assert_exempt(self.sidecar_verdict(sidecar, ext))

    def test_review2_non_empty_root_type_gates(self) -> None:
        sidecar = self.real_sidecar("fish/proof_fish.glb.import")
        for value in ("FishBody", "FishBody (fish_body.gd)", "Node3D"):
            with self.subTest(root_type=value):
                changed = sidecar.replace('nodes/root_type=""', f'nodes/root_type="{value}"')
                self.assertNotEqual(changed, sidecar)
                self.assert_gate(self.sidecar_verdict(changed))

    def test_review2_empty_or_absent_root_type_stays_exempt(self) -> None:
        sidecar = self.real_sidecar("fish/proof_fish.glb.import")
        self.assertIn('nodes/root_type=""', sidecar)
        self.assert_exempt(self.sidecar_verdict(sidecar))
        absent = sidecar.replace('nodes/root_type=""\n', "")
        self.assertNotEqual(absent, sidecar)
        self.assert_exempt(self.sidecar_verdict(absent))

    def test_r7_audio_sidecar_with_script_gates(self) -> None:
        sidecar = 'importer="wav"\nimport_script/path="res://x.gd"\n'
        for ext in (".ogg", ".wav", ".mp3"):
            with self.subTest(ext=ext):
                self.assert_gate(self.sidecar_verdict(sidecar, ext))


class TestRevisionRead(ClassifierCase):
    """R8 and AC4: added rows read head, deleted .tres rows read the old revision."""

    path = "assets/tank/materials/mat.tres"

    def test_ac4_deleting_an_exempt_tres_row_read_from_the_old_revision_is_exempt(self) -> None:
        old_rows = [*BASE_ROWS, own_row(self.path, HAND_SOURCE)]
        verdict = self.classify_rows(
            old_rows,
            BASE_ROWS,
            old_files=game_files({self.path: PLAIN_TRES}),
            new_files=files_of(),
        )
        self.assert_exempt(verdict)

    def test_ac4_deleting_a_tres_row_missing_at_both_revisions_gates(self) -> None:
        old_rows = [*BASE_ROWS, own_row(self.path, HAND_SOURCE)]
        self.assert_gate(self.classify_rows(old_rows, BASE_ROWS))

    def test_ac4_deleting_a_custom_shader_tres_row_gates(self) -> None:
        old_rows = [*BASE_ROWS, own_row(self.path, HAND_SOURCE)]
        palette = (REPO_ROOT / "game/assets/room/materials/room_palette.tres").read_bytes()
        verdict = self.classify_rows(
            old_rows,
            BASE_ROWS,
            old_files=game_files({self.path: palette}),
            new_files=files_of(),
        )
        self.assert_gate(verdict)

    def test_ac4_deleting_a_tres_row_whose_old_content_has_a_script_gates(self) -> None:
        old_rows = [*BASE_ROWS, own_row(self.path, HAND_SOURCE)]
        content = PLAIN_TRES + 'script = ExtResource("1_s")\n'
        verdict = self.classify_rows(
            old_rows, BASE_ROWS, old_files=game_files({self.path: content}), new_files=files_of()
        )
        self.assert_gate(verdict)

    def test_r8_deleting_a_glb_row_ignores_the_old_sidecar(self) -> None:
        path = "assets/test/old.glb"
        palette = (REPO_ROOT / "game/assets/room/materials/room_palette.tres").read_bytes()
        sidecar = (REPO_ROOT / "game/assets/room/cabinet.glb.import").read_bytes()
        old_files = game_files(
            {
                path: b"glb",
                path + ".import": sidecar,
                "assets/room/materials/room_palette.tres": palette,
            }
        )
        verdict = self.classify_rows(
            [*BASE_ROWS, own_row(path)], BASE_ROWS, old_files=old_files, new_files=files_of()
        )
        self.assert_exempt(verdict)

    def test_r8_added_row_reads_the_head_content_not_the_old_one(self) -> None:
        old_files = game_files({self.path: PLAIN_TRES})
        verdict = self.classify_rows(
            BASE_ROWS,
            [*BASE_ROWS, own_row(self.path, HAND_SOURCE)],
            old_files=old_files,
            new_files=game_files({self.path: PLAIN_TRES + 'script = ExtResource("1_s")\n'}),
        )
        self.assert_gate(verdict)


class TestNonRowEdits(ClassifierCase):
    """R1, R2 and AC8: every change to the log outside single rows gates."""

    def with_exempt_row(self, **new_log_kw: Any) -> Any:
        """Add an exempt row (valid by itself) plus a non-row edit given as make_log arguments."""
        new_row = own_row("assets/test/a.png")
        return self.classify_rows(
            BASE_ROWS,
            [*BASE_ROWS, new_row],
            new_files=game_files({"assets/test/a.png": b"x"}),
            **new_log_kw,
        )

    def test_ac8_the_exempt_row_alone_is_exempt(self) -> None:
        self.assert_exempt(self.with_exempt_row())

    def test_ac8_prose_before_the_table_gates(self) -> None:
        self.assert_gate(self.with_exempt_row(pre=PRE + "One more rule.\n\n"))

    def test_ac8_prose_after_the_table_gates(self) -> None:
        self.assert_gate(self.with_exempt_row(post=POST + "Added prose.\n"))

    def test_ac8_prose_edit_without_any_row_change_gates(self) -> None:
        self.assert_gate(self.classify_rows(BASE_ROWS, BASE_ROWS, pre=PRE + "Edited.\n\n"))

    def test_ac8_column_header_edit_gates(self) -> None:
        header = HEADER.replace("Source", "Origin")
        self.assert_gate(self.with_exempt_row(header=header))

    def test_ac8_separator_edit_gates(self) -> None:
        self.assert_gate(self.with_exempt_row(sep="|---|---|---|---|---|---|"))

    def test_ac8_header_that_is_not_the_required_header_gates(self) -> None:
        header = "| File | Source | Author | License | Link |"
        sep = "| --- | --- | --- | --- | --- |"
        old = make_log(BASE_ROWS, header=header, sep=sep)
        new = make_log([*BASE_ROWS, own_row("assets/test/a.png")], header=header, sep=sep)
        self.assert_gate(self.classify_logs(old, new, new_files=game_files({"assets/test/a.png": b"x"})))

    def test_ac8_swapping_two_exempt_rows_gates(self) -> None:
        rows = [THIRD_ROW, EXISTING_OWN, EXISTING_OWN_2]
        swapped = [THIRD_ROW, EXISTING_OWN_2, EXISTING_OWN]
        self.assert_gate(self.classify_rows(rows, swapped))

    def test_ac8_reordering_with_a_simultaneous_exempt_add_gates(self) -> None:
        rows = [THIRD_ROW, EXISTING_OWN, EXISTING_OWN_2]
        new_row = own_row("assets/test/a.png")
        verdict = self.classify_rows(
            rows,
            [THIRD_ROW, EXISTING_OWN_2, EXISTING_OWN, new_row],
            new_files=game_files({"assets/test/a.png": b"x"}),
        )
        self.assert_gate(verdict)

    def test_ac8_whitespace_only_edit_of_an_exempt_row_gates(self) -> None:
        edits = {
            "extra padding": EXISTING_OWN.replace("| Cozy", "|  Cozy"),
            "trailing space": EXISTING_OWN + " ",
            "leading space": " " + EXISTING_OWN,
            "tab": EXISTING_OWN.replace("| Cozy", "|\tCozy"),
            "missing padding": EXISTING_OWN.replace("| Cozy", "|Cozy"),
            "double space in source": EXISTING_OWN.replace("Generated in-house", "Generated  in-house"),
        }
        for name, edited in edits.items():
            with self.subTest(edit=name):
                self.assertNotEqual(edited, EXISTING_OWN)
                verdict = self.classify_rows(
                    BASE_ROWS,
                    [THIRD_ROW, edited],
                    new_files=game_files({"assets/fish/proof_fish.glb": b"x"}),
                )
                self.assert_gate(verdict)

    def test_ac8_blank_line_inside_the_table_gates(self) -> None:
        new = make_log([THIRD_ROW, EXISTING_OWN, "", own_row("assets/test/a.png")])
        verdict = self.classify_logs(
            make_log(BASE_ROWS), new, new_files=game_files({"assets/test/a.png": b"x"})
        )
        self.assert_gate(verdict)

    def test_ac8_blank_line_inside_the_old_table_gates(self) -> None:
        old = make_log([THIRD_ROW, "", EXISTING_OWN])
        new = make_log([THIRD_ROW, "", EXISTING_OWN, own_row("assets/test/a.png")])
        verdict = self.classify_logs(old, new, new_files=game_files({"assets/test/a.png": b"x"}))
        self.assert_gate(verdict)

    def test_ac8_a_second_table_gates(self) -> None:
        second = "\nSecond table:\n\n" + HEADER + "\n" + SEPARATOR + "\n" + EXISTING_OWN_2 + "\n"
        self.assert_gate(self.with_exempt_row(post=POST + second))

    def test_ac8_final_newline_removed_gates(self) -> None:
        self.assert_gate(self.with_exempt_row(post=POST.rstrip("\n")))

    def test_ac8_crlf_line_endings_gate(self) -> None:
        new = make_log([*BASE_ROWS, own_row("assets/test/a.png")]).replace("\n", "\r\n")
        verdict = self.classify_logs(
            make_log(BASE_ROWS), new, new_files=game_files({"assets/test/a.png": b"x"})
        )
        self.assert_gate(verdict)

    def test_ac8_crlf_in_both_versions_gates(self) -> None:
        old = make_log(BASE_ROWS).replace("\n", "\r\n")
        new = make_log([*BASE_ROWS, own_row("assets/test/a.png")]).replace("\n", "\r\n")
        verdict = self.classify_logs(old, new, new_files=game_files({"assets/test/a.png": b"x"}))
        self.assert_gate(verdict)

    def test_ac8_duplicate_row_gates(self) -> None:
        self.assert_gate(self.classify_rows(BASE_ROWS, [*BASE_ROWS, EXISTING_OWN]))

    def test_ac8_duplicate_file_in_two_rows_gates(self) -> None:
        other_date = own_row("assets/fish/proof_fish.glb", added="2026-11-10")
        verdict = self.classify_rows(
            BASE_ROWS,
            [*BASE_ROWS, other_date],
            new_files=game_files({"assets/fish/proof_fish.glb": b"x"}),
        )
        self.assert_gate(verdict)

    def test_ac8_row_edit_plus_prose_edit_gates(self) -> None:
        edited = own_row("assets/fish/proof_fish.glb", GEN_SOURCE + ", regenerated")
        verdict = self.classify_rows(
            BASE_ROWS,
            [THIRD_ROW, edited],
            new_files=game_files({"assets/fish/proof_fish.glb": b"x"}),
            post=POST + "More.\n",
        )
        self.assert_gate(verdict)

    def test_ac8_rows_with_no_table_at_all_gate(self) -> None:
        self.assert_gate(self.classify_logs(make_log(BASE_ROWS), PRE + POST))


class TestMalformedInput(ClassifierCase):
    """R3, R9 and AC13: anything unclassifiable gates and never passes by accident."""

    def gate_added(self, new_row: str) -> None:
        self.assert_gate(self.add_row(new_row, {"assets/test/x.png": b"x"}))

    def test_ac13_added_row_with_five_cells_gates(self) -> None:
        cells = ["`assets/test/x.png`", GEN_SOURCE, AUTHOR, LICENSE, LINK]
        self.gate_added(cells_line(cells))

    def test_ac13_added_row_with_seven_cells_gates(self) -> None:
        cells = ["`assets/test/x.png`", GEN_SOURCE, AUTHOR, LICENSE, LINK, ADDED, "extra"]
        self.gate_added(cells_line(cells))

    def test_ac13_added_row_without_leading_pipe_gates(self) -> None:
        self.gate_added(own_row("assets/test/x.png")[2:])

    def test_ac13_added_row_without_trailing_pipe_gates(self) -> None:
        self.gate_added(own_row("assets/test/x.png")[:-2])

    def test_ac13_added_row_with_an_empty_cell_gates(self) -> None:
        names = ["file", "source", "author", "license", "link", "added"]
        for index, name in enumerate(names):
            with self.subTest(empty=name):
                cells = ["`assets/test/x.png`", GEN_SOURCE, AUTHOR, LICENSE, LINK, ADDED]
                cells[index] = ""
                self.gate_added("| " + " | ".join(cells) + " |")

    def test_ac13_added_row_with_a_pipe_inside_a_cell_gates(self) -> None:
        self.gate_added(own_row("assets/test/x.png", GEN_SOURCE + " a | b"))

    def test_ac13_deleted_malformed_row_gates(self) -> None:
        bad = cells_line(["`assets/test/x.png`", GEN_SOURCE, AUTHOR, LICENSE, LINK])
        self.assert_gate(self.classify_rows([*BASE_ROWS, bad], BASE_ROWS))

    def test_ac13_non_row_text_inside_the_table_block_gates(self) -> None:
        self.assert_gate(self.add_row("| just some text |"))

    def test_ac13_log_missing_at_the_new_revision_gates(self) -> None:
        self.assert_gate(self.classify_logs(make_log(BASE_ROWS), None))

    def test_ac13_log_missing_at_the_old_revision_gates(self) -> None:
        self.assert_gate(self.classify_logs(None, make_log(BASE_ROWS)))

    def test_ac13_log_missing_at_both_revisions_never_passes_as_exempt(self) -> None:
        verdict = self.classify_logs(None, None)
        self.assertFalse(verdict.exempt)

    def test_ac13_empty_logs_gate(self) -> None:
        self.assert_gate(self.classify_logs("", make_log(BASE_ROWS)))
        self.assert_gate(self.classify_logs(make_log(BASE_ROWS), ""))

    def test_ac13_a_reader_that_raises_never_yields_exempt(self) -> None:
        def boom(path: str) -> bytes | None:
            raise OSError("cannot read " + path)

        path = "assets/test/x.png"
        try:
            verdict = self.mod.classify(
                make_log(BASE_ROWS),
                make_log([*BASE_ROWS, own_row(path)]),
                reader(files_of()),
                boom,
            )
        except Exception:  # noqa: BLE001 - main() turns this into exit 2, see TestCommandLine
            return
        self.assertFalse(verdict.exempt, f"a failing reader must not give exempt: {verdict!r}")


class CliCase(ClassifierCase):
    """Builds a temporary git repository and runs the classifier as a subprocess."""

    repo: Path

    def setUp(self) -> None:
        super().setUp()
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.repo = Path(tmp.name)
        self.git("init", "-q", "-b", "main")

    def git(self, *args: str) -> str:
        result = subprocess.run(
            [
                "git",
                "-c",
                "user.name=t",
                "-c",
                "user.email=t@t",
                "-c",
                "commit.gpgsign=false",
                "-c",
                "core.autocrlf=false",
                "-C",
                str(self.repo),
                *args,
            ],
            capture_output=True,
            check=True,
        )
        return result.stdout.decode("utf-8").strip()

    def commit(self, files: dict[str, bytes | str | None], message: str = "c") -> str:
        for rel, content in files.items():
            target = self.repo / rel
            if content is None:
                target.unlink(missing_ok=True)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            data = content.encode("utf-8") if isinstance(content, str) else content
            target.write_bytes(data)
        self.git("add", "-A")
        self.git("commit", "-q", "--allow-empty", "-m", message)
        return self.git("rev-parse", "HEAD")

    def base_files(self, rows: list[str]) -> dict[str, bytes | str | None]:
        files: dict[str, bytes | str | None] = {LOG_PATH: make_log(rows)}
        files.update({path: content for path, content in TOOL_FILES.items()})
        return files

    def run_cli(self, old: str, new: str) -> subprocess.CompletedProcess[str]:
        if not SCRIPT.is_file():
            self.fail(f"{SCRIPT} is missing")
        result = subprocess.run(
            [
                sys.executable,
                "-I",
                str(SCRIPT),
                "--repo",
                str(self.repo),
                "--old",
                old,
                "--new",
                new,
            ],
            capture_output=True,
            text=True,
            encoding="utf-8",
            check=False,
        )
        out = result.stdout
        if result.returncode == 0:
            self.assertRegex(out, r"(?m)^RESULT: (exempt|unchanged)$")
        elif result.returncode == 1:
            self.assertRegex(out, r"(?m)^GATE: ")
            self.assertRegex(out, r"(?m)^RESULT: gate$")
        else:
            self.assertEqual(result.returncode, 2, out + result.stderr)
        return result


class TestCommandLine(CliCase):
    """AC13 and the exit-code contract: 0 only with an exempt or unchanged result."""

    def test_cli_exempt_row_add_exits_0_with_result_exempt(self) -> None:
        old = self.commit(self.base_files(BASE_ROWS))
        path = "assets/test/new.png"
        new_rows = [*BASE_ROWS, own_row(path)]
        new = self.commit({LOG_PATH: make_log(new_rows), "game/" + path: b"png"})
        result = self.run_cli(old, new)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("RESULT: exempt", result.stdout)

    def test_cli_third_party_row_add_exits_1_with_a_gate_line(self) -> None:
        old = self.commit(self.base_files(BASE_ROWS))
        other = THIRD_ROW.replace("nunito_variable.ttf", "other.ttf")
        new = self.commit({LOG_PATH: make_log([*BASE_ROWS, other])})
        result = self.run_cli(old, new)
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("GATE:", result.stdout)
        self.assertIn("RESULT: gate", result.stdout)

    def test_cli_deleted_tres_row_is_read_from_the_old_revision(self) -> None:
        path = "assets/tank/materials/mat.tres"
        rows = [*BASE_ROWS, own_row(path, HAND_SOURCE)]
        files = self.base_files(rows)
        files["game/" + path] = PLAIN_TRES
        old = self.commit(files)
        new = self.commit({LOG_PATH: make_log(BASE_ROWS), "game/" + path: None})
        result = self.run_cli(old, new)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("RESULT: exempt", result.stdout)

    def test_cli_deleted_tres_row_with_a_custom_shader_gates(self) -> None:
        path = "assets/tank/materials/mat.tres"
        palette = (REPO_ROOT / "game/assets/room/materials/room_palette.tres").read_text(
            encoding="utf-8"
        )
        files = self.base_files([*BASE_ROWS, own_row(path, HAND_SOURCE)])
        files["game/" + path] = palette
        old = self.commit(files)
        new = self.commit({LOG_PATH: make_log(BASE_ROWS), "game/" + path: None})
        self.assertEqual(self.run_cli(old, new).returncode, 1)

    def test_cli_log_untouched_prints_result_unchanged(self) -> None:
        old = self.commit(self.base_files(BASE_ROWS))
        new = self.commit({"game/assets/other.txt": "x"})
        result = self.run_cli(old, new)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("RESULT: unchanged", result.stdout)

    def test_cli_reads_the_new_revision_not_the_working_tree(self) -> None:
        old = self.commit(self.base_files(BASE_ROWS))
        other = THIRD_ROW.replace("nunito_variable.ttf", "other.ttf")
        new = self.commit({LOG_PATH: make_log([*BASE_ROWS, other])})
        self.commit({LOG_PATH: make_log(BASE_ROWS)})  # working tree and HEAD differ from new
        self.assertEqual(self.run_cli(old, new).returncode, 1)

    def test_cli_added_row_with_script_bound_sidecar_gates(self) -> None:
        path = "assets/test/new.glb"
        old = self.commit(self.base_files(BASE_ROWS))
        sidecar = (REPO_ROOT / "game/assets/fish/proof_fish.glb.import").read_text(encoding="utf-8")
        sidecar = sidecar.replace('import_script/path=""', 'import_script/path="res://x.gd"')
        new = self.commit(
            {
                LOG_PATH: make_log([*BASE_ROWS, own_row(path)]),
                "game/" + path: b"glb",
                "game/" + path + ".import": sidecar,
            }
        )
        self.assertEqual(self.run_cli(old, new).returncode, 1)

    def test_cli_missing_log_at_the_new_revision_never_exits_0(self) -> None:
        old = self.commit(self.base_files(BASE_ROWS))
        new = self.commit({LOG_PATH: None})
        self.assertIn(self.run_cli(old, new).returncode, (1, 2))

    def test_cli_missing_log_at_the_old_revision_never_exits_0(self) -> None:
        old = self.commit({"README.md": "x"})
        new = self.commit(self.base_files(BASE_ROWS))
        self.assertIn(self.run_cli(old, new).returncode, (1, 2))

    def test_cli_invalid_utf8_log_never_exits_0(self) -> None:
        old = self.commit(self.base_files(BASE_ROWS))
        bad = make_log([*BASE_ROWS, own_row("assets/test/new.png")]).encode("utf-8") + b"\xff\xfe"
        new = self.commit({LOG_PATH: bad, "game/assets/test/new.png": b"x"})
        self.assertIn(self.run_cli(old, new).returncode, (1, 2))

    def test_cli_crlf_log_never_exits_0(self) -> None:
        old = self.commit(self.base_files(BASE_ROWS))
        crlf = make_log([*BASE_ROWS, own_row("assets/test/new.png")]).replace("\n", "\r\n")
        new = self.commit({LOG_PATH: crlf.encode("utf-8"), "game/assets/test/new.png": b"x"})
        self.assertIn(self.run_cli(old, new).returncode, (1, 2))

    def test_cli_unknown_revision_exits_2_with_an_error(self) -> None:
        good = self.commit(self.base_files(BASE_ROWS))
        result = self.run_cli(good, "0" * 40)
        self.assertEqual(result.returncode, 2)
        self.assertRegex(result.stdout, r"(?m)^ERROR: ")
        self.assertIn("RESULT: error", result.stdout)

    def test_cli_unknown_old_revision_exits_2(self) -> None:
        good = self.commit(self.base_files(BASE_ROWS))
        result = self.run_cli("no-such-rev", good)
        self.assertEqual(result.returncode, 2)
        self.assertIn("RESULT: error", result.stdout)

    def test_cli_repo_that_is_not_a_git_repository_exits_2(self) -> None:
        good = self.commit(self.base_files(BASE_ROWS))
        with tempfile.TemporaryDirectory() as empty:
            result = subprocess.run(
                [sys.executable, "-I", str(SCRIPT), "--repo", empty, "--old", good, "--new", good],
                capture_output=True,
                text=True,
                check=False,
            )
        self.assertEqual(result.returncode, 2, result.stdout)
        self.assertIn("RESULT: error", result.stdout)

    def test_cli_bad_arguments_exit_2(self) -> None:
        if not SCRIPT.is_file():
            self.fail(f"{SCRIPT} is missing")
        for args in ([], ["--repo", str(self.repo)], ["--old", "a", "--new", "b"]):
            with self.subTest(args=args):
                result = subprocess.run(
                    [sys.executable, "-I", str(SCRIPT), *args],
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertEqual(result.returncode, 2, result.stdout)
                self.assertNotIn("RESULT: exempt", result.stdout)
                self.assertNotIn("RESULT: unchanged", result.stdout)

    def test_cli_reads_the_diff_baseline_given_as_old_not_the_branch_tip(self) -> None:
        base = self.commit(self.base_files(BASE_ROWS))
        # A later commit removes the third-party row; classifying from base must see that deletion.
        new = self.commit({LOG_PATH: make_log([EXISTING_OWN])})
        self.assertEqual(self.run_cli(base, new).returncode, 1)
        self.assertEqual(self.run_cli(new, new).returncode, 0)


class TestRealLog(ClassifierCase):
    """Regression on the repository's current licence log and files, read from disk."""

    own_exempt = (
        "assets/fish/proof_fish.glb",
        "assets/fish/proof_palette_atlas.png",
        "assets/room/room_palette_atlas.png",
        "assets/tank/materials/glass_placeholder.tres",
    )
    own_gated = (
        "assets/room/cabinet.glb",
        "assets/room/lamp.glb",
        "assets/room/room_corner.glb",
        "assets/tank/tank_medium_60l.glb",
        "assets/room/materials/room_palette.tres",
    )

    def setUp(self) -> None:
        super().setUp()
        self.log = (REPO_ROOT / LOG_PATH).read_text(encoding="utf-8")
        lines = self.log.split("\n")
        self.rows = [line for line in lines if line.startswith("| `")]
        self.assertGreaterEqual(len(self.rows), 14)

    def row_for(self, path: str) -> str:
        matches = [r for r in self.rows if r.startswith(f"| `{path}` |")]
        self.assertEqual(len(matches), 1, path)
        return matches[0]

    def log_without(self, line: str) -> str:
        return self.log.replace(line + "\n", "", 1)

    def readd(self, path: str) -> Any:
        old_log = self.log_without(self.row_for(path))
        return self.mod.classify(old_log, self.log, read_disk, read_disk)

    def test_real_log_against_itself_is_unchanged(self) -> None:
        verdict = self.mod.classify(self.log, self.log, read_disk, read_disk)
        self.assert_unchanged(verdict)

    def test_real_own_rows_without_a_custom_shader_binding_are_exempt(self) -> None:
        for path in self.own_exempt:
            with self.subTest(path=path):
                self.assert_exempt(self.readd(path))

    def test_real_own_rows_bound_to_room_palette_gate(self) -> None:
        for path in self.own_gated:
            with self.subTest(path=path):
                self.assert_gate(self.readd(path))

    def test_real_third_party_rows_gate(self) -> None:
        third = [r for r in self.rows if AUTHOR not in r]
        self.assertGreaterEqual(len(third), 5)
        for line in third:
            with self.subTest(row=line[:60]):
                old_log = self.log_without(line)
                self.assert_gate(self.mod.classify(old_log, self.log, read_disk, read_disk))
                self.assert_gate(self.mod.classify(self.log, old_log, read_disk, read_disk))

    def test_real_deleting_exempt_rows_is_exempt(self) -> None:
        for path in self.own_exempt:
            with self.subTest(path=path):
                new_log = self.log_without(self.row_for(path))
                gone = "game/" + path

                def read_new(p: str, gone: str = gone) -> bytes | None:
                    return None if p == gone else read_disk(p)

                verdict = self.mod.classify(self.log, new_log, read_disk, read_new)
                self.assert_exempt(verdict)

    def test_real_deleting_room_palette_row_gates(self) -> None:
        path = "assets/room/materials/room_palette.tres"
        new_log = self.log_without(self.row_for(path))
        self.assert_gate(self.mod.classify(self.log, new_log, read_disk, read_disk))


if __name__ == "__main__":
    unittest.main()
