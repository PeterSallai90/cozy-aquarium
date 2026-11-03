"""Tests for issue #80: guards against Godot editor and editorconfig side effects.

Acceptance criteria covered here:
- AC1: EditorconfigTest (sections, entries and order of .editorconfig).
- AC3 to AC6: CheckProjectSettingsTest (exit codes, stderr lines, edge cases of the script).
- AC7: PreCommitHookTest (properties of the local hook, existing hooks unchanged).
- AC9: DevSetupDocTest (docs/dev-setup.md names every required line).
AC2 is a manual git diff check. AC8 lives in the GdUnit suites. AC10 is the full run.

The script module is imported lazily so that a missing script fails the script tests only, and
the .editorconfig, hook and doc tests fail for their own reason.

There is deliberately no test that runs the script on the real game/project.godot: that would make
CI run the check, and docs/dev-setup.md says it does not. The GdUnit tests guard the real file.

Run: python -m unittest discover -s tools/scripts -p "test_*.py"
"""

from __future__ import annotations

import contextlib
import importlib
import io
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import ModuleType

SCRIPTS_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPTS_DIR.parents[1]
SCRIPT = SCRIPTS_DIR / "check_project_settings.py"

FALLBACK_LINE = 'locale/fallback="en"'
RENDERER_LINE = 'renderer/rendering_method="forward_plus"'

BASELINE = (
    "; Engine configuration file.\n"
    "\n"
    "config_version=5\n"
    "\n"
    "[application]\n"
    "\n"
    'config/name="Cozy Aquarium"\n'
    "\n"
    "[rendering]\n"
    "\n"
    f"{RENDERER_LINE}\n"
    "\n"
    "[internationalization]\n"
    "\n"
    'locale/translations=PackedStringArray("res://localization/en.po")\n'
    f"{FALLBACK_LINE}\n"
)

STDERR_LINE_PATTERN = re.compile(r'^.+: \[[^\]]+\] \S+: .+; expected line: \S+=".*"$')


def load_script() -> ModuleType:
    return importlib.import_module("check_project_settings")


class CheckProjectSettingsTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)

    def write(self, content: str | bytes) -> None:
        path = self.root / "game" / "project.godot"
        path.parent.mkdir(parents=True, exist_ok=True)
        data = content.encode("utf-8") if isinstance(content, str) else content
        path.write_bytes(data)

    def run_check(self) -> tuple[int, str, str]:
        module = load_script()
        out = io.StringIO()
        err = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code: int = module.check(self.root)
        return code, out.getvalue(), err.getvalue()

    def assert_problem(self, stderr: str, section: str, key: str, line: str) -> None:
        self.assertIn("game/project.godot", stderr)
        self.assertIn(f"[{section}]", stderr)
        self.assertIn(key, stderr)
        self.assertIn(f"expected line: {line}", stderr)

    # AC3

    def test_ac3_complete_file_exits_0_and_prints_nothing(self) -> None:
        self.write(BASELINE)
        code, out, err = self.run_check()
        self.assertEqual(code, 0)
        self.assertEqual(err, "")
        self.assertEqual(out, "")

    def test_ac3_spaces_around_equals_are_accepted(self) -> None:
        text = BASELINE.replace(FALLBACK_LINE, 'locale/fallback = "en"')
        text = text.replace(RENDERER_LINE, 'renderer/rendering_method = "forward_plus"')
        self.write(text)
        code, _, err = self.run_check()
        self.assertEqual(code, 0)
        self.assertEqual(err, "")

    def test_ac3_crlf_line_endings_are_accepted(self) -> None:
        self.write(BASELINE.replace("\n", "\r\n"))
        code, _, err = self.run_check()
        self.assertEqual(code, 0)
        self.assertEqual(err, "")

    def test_ac3_utf8_bom_is_accepted(self) -> None:
        self.write(b"\xef\xbb\xbf" + BASELINE.encode("utf-8"))
        code, _, err = self.run_check()
        self.assertEqual(code, 0)
        self.assertEqual(err, "")

    # AC4

    def test_ac4_missing_fallback_exits_1_with_the_line_to_add_back(self) -> None:
        self.write(BASELINE.replace(f"{FALLBACK_LINE}\n", ""))
        code, _, err = self.run_check()
        self.assertEqual(code, 1)
        self.assert_problem(err, "internationalization", "locale/fallback", FALLBACK_LINE)

    # AC5

    def test_ac5_missing_renderer_exits_1_with_the_line_to_add_back(self) -> None:
        self.write(BASELINE.replace(f"{RENDERER_LINE}\n", ""))
        code, _, err = self.run_check()
        self.assertEqual(code, 1)
        self.assert_problem(err, "rendering", "renderer/rendering_method", RENDERER_LINE)

    # AC6

    def test_ac6_wrong_value_exits_1(self) -> None:
        self.write(BASELINE.replace(FALLBACK_LINE, 'locale/fallback="hu"'))
        code, _, err = self.run_check()
        self.assertEqual(code, 1)
        self.assert_problem(err, "internationalization", "locale/fallback", FALLBACK_LINE)

    def test_ac6_missing_section_exits_1(self) -> None:
        self.write(BASELINE.split("[internationalization]")[0])
        code, _, err = self.run_check()
        self.assertEqual(code, 1)
        self.assert_problem(err, "internationalization", "locale/fallback", FALLBACK_LINE)

    def test_ac6_line_under_the_wrong_section_exits_1(self) -> None:
        text = BASELINE.replace(f"{FALLBACK_LINE}\n", "")
        text = text.replace(f"{RENDERER_LINE}\n", f"{RENDERER_LINE}\n{FALLBACK_LINE}\n")
        self.write(text)
        code, _, err = self.run_check()
        self.assertEqual(code, 1)
        self.assert_problem(err, "internationalization", "locale/fallback", FALLBACK_LINE)

    def test_ac6_duplicate_with_correct_last_value_passes(self) -> None:
        self.write(BASELINE.replace(FALLBACK_LINE, f'locale/fallback="hu"\n{FALLBACK_LINE}'))
        code, _, err = self.run_check()
        self.assertEqual(code, 0)
        self.assertEqual(err, "")

    def test_ac6_duplicate_with_wrong_last_value_fails(self) -> None:
        self.write(BASELINE.replace(FALLBACK_LINE, f'{FALLBACK_LINE}\nlocale/fallback="hu"'))
        code, _, err = self.run_check()
        self.assertEqual(code, 1)
        self.assert_problem(err, "internationalization", "locale/fallback", FALLBACK_LINE)

    def test_ac6_both_lines_missing_gives_one_stderr_line_per_problem(self) -> None:
        text = BASELINE.replace(f"{FALLBACK_LINE}\n", "").replace(f"{RENDERER_LINE}\n", "")
        self.write(text)
        code, _, err = self.run_check()
        self.assertEqual(code, 1)
        lines = [line for line in err.splitlines() if line.strip()]
        self.assertEqual(len(lines), 2)
        self.assert_problem(err, "rendering", "renderer/rendering_method", RENDERER_LINE)
        self.assert_problem(err, "internationalization", "locale/fallback", FALLBACK_LINE)

    def test_ac6_every_stderr_line_has_the_documented_form(self) -> None:
        cases = [
            BASELINE.replace(f"{FALLBACK_LINE}\n", "").replace(f"{RENDERER_LINE}\n", ""),
            BASELINE.replace(FALLBACK_LINE, 'locale/fallback="hu"'),
            BASELINE.split("[internationalization]")[0],
        ]
        for index, text in enumerate(cases):
            with self.subTest(case=index):
                self.write(text)
                code, _, err = self.run_check()
                self.assertEqual(code, 1)
                lines = [line for line in err.splitlines() if line.strip()]
                self.assertGreaterEqual(len(lines), 1)
                for line in lines:
                    self.assertRegex(line, STDERR_LINE_PATTERN)

    def test_ac6_missing_file_exits_2_with_the_path(self) -> None:
        code, _, err = self.run_check()
        self.assertEqual(code, 2)
        self.assertIn("game/project.godot", err)

    def test_ac6_invalid_utf8_exits_2(self) -> None:
        self.write(BASELINE.encode("utf-8") + b"\xff\xfe\xfa\n")
        code, _, err = self.run_check()
        self.assertEqual(code, 2)
        self.assertIn("game/project.godot", err)

    def test_ac6_multi_line_value_does_not_raise_a_false_alarm(self) -> None:
        action = (
            "[input]\n"
            "\n"
            "move_left={\n"
            '"deadzone": 0.5,\n'
            '"events": [Object(InputEventKey,"resource_local_to_scene":false,'
            '"keycode":0,"physical_keycode":65)\n'
            "]\n"
            "}\n"
            "\n"
        )
        self.write(BASELINE.replace("[rendering]", action + "[rendering]"))
        code, _, err = self.run_check()
        self.assertEqual(code, 0)
        self.assertEqual(err, "")

    def run_script(self) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--root", str(self.root)],
            capture_output=True,
            text=True,
            check=False,
        )

    def test_ac3_script_run_on_a_complete_file_exits_0_silently(self) -> None:
        self.write(BASELINE)
        result = self.run_script()
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stderr, "")

    def test_ac6_script_run_on_a_missing_file_exits_2_without_traceback(self) -> None:
        result = self.run_script()
        self.assertEqual(result.returncode, 2)
        self.assertNotIn("Traceback", result.stderr)
        self.assertIn("game/project.godot", result.stderr)

    def test_ac6_script_run_on_a_missing_line_exits_1_without_traceback(self) -> None:
        self.write(BASELINE.replace(f"{FALLBACK_LINE}\n", ""))
        result = self.run_script()
        self.assertEqual(result.returncode, 1)
        self.assertNotIn("Traceback", result.stderr)
        self.assertIn(FALLBACK_LINE, result.stderr)


class RequiredSettingsListTest(unittest.TestCase):
    def test_the_list_has_exactly_the_two_required_settings(self) -> None:
        module = load_script()
        entries = [(s.section, s.key, s.value) for s in module.REQUIRED_SETTINGS]
        self.assertEqual(
            entries,
            [
                ("rendering", "renderer/rendering_method", "forward_plus"),
                ("internationalization", "locale/fallback", "en"),
            ],
        )

    def test_line_renders_key_and_quoted_value(self) -> None:
        module = load_script()
        lines = [s.line for s in module.REQUIRED_SETTINGS]
        self.assertEqual(lines, [RENDERER_LINE, FALLBACK_LINE])


def parse_editorconfig(text: str) -> tuple[dict[str, str], list[tuple[str, dict[str, str]]]]:
    preamble: dict[str, str] = {}
    sections: list[tuple[str, dict[str, str]]] = []
    current = preamble
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith(("#", ";")):
            continue
        header = re.fullmatch(r"\[(.+)\]", line)
        if header:
            current = {}
            sections.append((header.group(1), current))
            continue
        key, _, value = line.partition("=")
        current[key.strip()] = value.strip()
    return preamble, sections


class EditorconfigTest(unittest.TestCase):
    def setUp(self) -> None:
        text = (REPO_ROOT / ".editorconfig").read_text(encoding="utf-8")
        self.preamble, self.sections = parse_editorconfig(text)
        self.by_header = dict(self.sections)

    def test_ac1_preamble_is_root_true(self) -> None:
        self.assertEqual(self.preamble, {"root": "true"})

    def test_ac1_sections_are_in_the_expected_order_with_fonts_last(self) -> None:
        headers = [header for header, _ in self.sections]
        self.assertEqual(
            headers,
            ["*", "*.gd", "*.{json,yml,yaml,md}", "*.{bat,cmd}", "game/assets/fonts/**"],
        )

    def test_ac1_star_section_keeps_its_four_entries(self) -> None:
        self.assertEqual(
            self.by_header["*"],
            {
                "charset": "utf-8",
                "end_of_line": "lf",
                "insert_final_newline": "true",
                "trim_trailing_whitespace": "true",
            },
        )

    def test_ac1_other_sections_are_unchanged(self) -> None:
        self.assertEqual(self.by_header["*.gd"], {"indent_style": "tab"})
        self.assertEqual(
            self.by_header["*.{json,yml,yaml,md}"],
            {"indent_style": "space", "indent_size": "2"},
        )
        self.assertEqual(self.by_header["*.{bat,cmd}"], {"end_of_line": "crlf"})

    def test_ac1_fonts_section_switches_trimming_and_final_newline_off(self) -> None:
        self.assertEqual(
            self.by_header.get("game/assets/fonts/**"),
            {"trim_trailing_whitespace": "false", "insert_final_newline": "unset"},
        )


EXISTING_PRE_COMMIT = """repos:
  - repo: https://github.com/Scony/godot-gdscript-toolkit
    rev: 4.5.0          # pinned at repository creation
    hooks:
      - id: gdformat
        exclude: ^game/addons/gdUnit4/
      - id: gdlint
        exclude: ^game/addons/gdUnit4/
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: check-merge-conflict
      - id: check-yaml
      - id: check-json
      - id: end-of-file-fixer
        exclude: ^game/(addons/gdUnit4|assets/fonts)/
      - id: trailing-whitespace
        exclude: ^game/(addons/gdUnit4|assets/fonts)/
      - id: check-added-large-files
        args: ["--maxkb=500"]   # large files must go through LFS
"""


class PreCommitHookTest(unittest.TestCase):
    def setUp(self) -> None:
        text = (REPO_ROOT / ".pre-commit-config.yaml").read_text(encoding="utf-8")
        marker = "  - repo: local"
        self.has_local = marker in text
        self.before, _, self.local_block = text.partition(marker)

    def test_ac7_existing_hooks_and_font_excludes_are_unchanged(self) -> None:
        self.assertEqual(self.before, EXISTING_PRE_COMMIT)

    def test_ac7_local_repo_block_exists(self) -> None:
        self.assertTrue(self.has_local, "no 'repo: local' block in .pre-commit-config.yaml")

    def test_ac7_hook_id(self) -> None:
        self.assertIn("id: check-project-settings", self.local_block)

    def test_ac7_hook_entry_runs_the_script(self) -> None:
        match = re.search(r"^\s+entry:\s*(.+)$", self.local_block, re.MULTILINE)
        self.assertIsNotNone(match, "no entry line in the local hook")
        if match is not None:
            self.assertIn("tools/scripts/check_project_settings.py", match.group(1))

    def test_ac7_hook_language_is_python(self) -> None:
        self.assertRegex(self.local_block, r"(?m)^\s+language:\s*python\s*$")

    def test_ac7_hook_runs_only_when_project_godot_is_staged(self) -> None:
        self.assertRegex(self.local_block, r"(?m)^\s+files:\s*\^game/project\\\.godot\$\s*$")

    def test_ac7_hook_does_not_pass_filenames(self) -> None:
        self.assertRegex(self.local_block, r"(?m)^\s+pass_filenames:\s*false\s*$")


class DevSetupDocTest(unittest.TestCase):
    def read_doc(self) -> str:
        path = REPO_ROOT / "docs" / "dev-setup.md"
        self.assertTrue(path.is_file(), "docs/dev-setup.md does not exist")
        return path.read_text(encoding="utf-8")

    def test_ac9_doc_names_both_required_lines(self) -> None:
        text = self.read_doc()
        self.assertIn(RENDERER_LINE, text)
        self.assertIn(FALLBACK_LINE, text)

    def test_ac9_doc_contains_every_line_of_the_scripts_list(self) -> None:
        text = self.read_doc()
        module = load_script()
        for setting in module.REQUIRED_SETTINGS:
            with self.subTest(line=setting.line):
                self.assertIn(setting.line, text)

    def test_ac9_doc_mentions_restore_script_and_no_verify(self) -> None:
        text = self.read_doc()
        for needle in (
            "git checkout -- game/project.godot",
            "tools/scripts/check_project_settings.py",
            "--no-verify",
        ):
            with self.subTest(needle=needle):
                self.assertIn(needle, text)


if __name__ == "__main__":
    unittest.main()
