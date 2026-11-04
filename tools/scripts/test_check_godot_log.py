"""Tests for issue #93: the CI engine log gate (tools/scripts/check_godot_log.py).

Acceptance criteria covered here (numbers follow the issue):
- AC1-3: ERROR:, WARNING: and SCRIPT ERROR: lines fail the import, export and smoke steps.
- AC4: clean logs exit 0 and print nothing.
- AC5/AC6: the allowlist (literal substring, reason, issue link) and its empty state.
- AC7: leak lines fail in every step, also inside a test window.
- AC8/AC9/AC9a: the test step window rule, asserted lines inside a window, bare parsing lines.
- AC11: unreadable logs and encodings (carried over from the #88 gate tests).
- AC12: usage errors.
- AC13/AC14: single home for patterns, old script and its tests gone.
- AC15a: the pinned first-import set (owner decision, option A).
- AC16-18 (unit part): ci.yml wiring.
- AC23: the smoke step.
- Encoding safety of the gate output.
Manual or CI only: AC10, AC15, AC15a (fresh checkout run), AC16/17/19 (PR run), AC18, AC24.

The script module is imported lazily so that a missing script fails each test for the same
reason: the behaviour does not exist yet.

Run: python -m unittest discover -s tools/scripts -p "test_*.py"
"""

from __future__ import annotations

import contextlib
import importlib
import io
import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import ModuleType
from unittest import mock

SCRIPTS_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPTS_DIR.parent.parent
GATE_PATH = SCRIPTS_DIR / "check_godot_log.py"
CI_YML = REPO_ROOT / ".github" / "workflows" / "ci.yml"

ESC = "\x1b"
OBJECT_PATTERN = "ObjectDB instances were leaked"
RESOURCE_PATTERN = "resources still in use at exit"
OBJECT_LINE = f"WARNING: 3 {OBJECT_PATTERN} at exit (run with --verbose for details)."
RESOURCE_LINE = f"ERROR: 7 {RESOURCE_PATTERN} (run with --verbose for details)."
# Built by concatenation so that this file does not match the AC14 search itself.
OLD_SCRIPT = "check_test" + "_leaks"
OLD_TEST = "test_" + OLD_SCRIPT

ENGINE_ERROR = "ERROR: Something went wrong in the engine"
ENGINE_WARNING = "WARNING: Something looks odd in the engine"
SCRIPT_ERROR = "SCRIPT ERROR: Parse Error: Unexpected token"
ENGINE_TOKENS = (ENGINE_ERROR, ENGINE_WARNING, SCRIPT_ERROR)

SUITE = "res://tests/a/test_a.gd"
VALID_ISSUE = "https://github.com/PeterSallai90/cozy-aquarium/issues/93"

HASH_A = "0123456789abcdef0123456789abcdef"
HASH_B = "fedcba9876543210fedcba9876543210"
HASH_C = "aaaaaaaabbbbbbbbccccccccdddddddd"
HASH_D = "11112222333344445555666677778888"
THEME = "res://ui/theme/cozy_theme.tres"
PINNED_LINES = [
    f"ERROR: Cannot open file 'res://.godot/imported/nunito_variable.ttf-{HASH_A}.fontdata'.",
    f"ERROR: Cannot open file 'res://.godot/imported/noto_sans_variable.ttf-{HASH_B}.fontdata'.",
    f"ERROR: Failed loading resource: res://.godot/imported/nunito_variable.ttf-{HASH_A}.fontdata.",
    f"ERROR: Failed loading resource: res://.godot/imported/noto_sans_variable.ttf-{HASH_B}.fontdata.",
    "ERROR: Failed loading resource: res://assets/fonts/nunito/nunito_variable.ttf.",
    "ERROR: Failed loading resource: res://assets/fonts/noto_sans/noto_sans_variable.ttf.",
    f"ERROR: {THEME}:7 - Parse Error: [ext_resource] referenced non-existent resource at: "
    "res://assets/fonts/noto_sans/noto_sans_variable.ttf.",
    f"ERROR: {THEME}:7 - Parse Error: [ext_resource] referenced non-existent resource at: "
    "res://assets/fonts/noto_sans/noto_sans_variable.ttf.",
    f"ERROR: Failed loading resource: {THEME}.",
    f"ERROR: Error loading custom project theme '{THEME}'",
]
IMPORT_HEAD = "Godot Engine v4.7.2.stable.official - https://godotengine.org\n"
IMPORT_CLEAN = IMPORT_HEAD + "Importing 3 files\nDone.\n"


def load_script() -> ModuleType:
    return importlib.import_module("check_godot_log")


def started(test: str, suite: str = SUITE) -> str:
    """A STARTED marker line as GdUnit4 prints it (with colour codes)."""
    return f"{ESC}[1;36m{suite}{ESC}[0m > {test} {ESC}[1;33mSTARTED{ESC}[0m"


def ended(test: str, status: str = "PASSED", elapsed: str = "4ms", suite: str = SUITE) -> str:
    """An end marker line as GdUnit4 prints it (with colour codes)."""
    return f"{ESC}[1;36m{suite}{ESC}[0m > {test} {ESC}[1;32m{status}{ESC}[0m {elapsed}"


def block(test: str, inside: list[str] | None = None, status: str = "PASSED") -> str:
    lines = [started(test), *(inside or []), ended(test, status)]
    return "\n".join(lines) + "\n"


def test_log(*parts: str) -> str:
    head = f"{IMPORT_HEAD}Run Test Suites\n"
    tail = (
        "Statistics: 2 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 0 orphans |\n"
        "Total execution time: 1s 2ms\n"
    )
    return head + "".join(parts) + tail


CLEAN_TEST_LOG = test_log(block("test_one"), block("test_two"))

# Real shapes cut from a Godot 4.7.2 + GdUnit4 6.2.2 run: asserted engine output inside windows.
INSIDE_WINDOW_LINES = [
    "ERROR: Parse error in config file at line 3: unexpected token.",
    "   at: parse (core/io/config_file.cpp:230)",
    "WARNING: probe: warning text",
    "     at: push_warning (core/variant/variant_utility.cpp:1034)",
    f"{ESC}[1;31mSCRIPT ERROR{ESC}[0m: Parse Error: Identifier not declared in the current scope.",
    "          at: GDScript::reload (res://tests/a/probe.gd:3)",
    'ERROR: Failed to load script "res://tests/a/probe.gd" with error "Parse error".',
    "   at: load (modules/gdscript/gdscript.cpp:2917)",
]
INSIDE_WINDOW_LOG = test_log(block("test_one"), block("test_two", INSIDE_WINDOW_LINES))


class GateTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)

    def write(self, content: str | bytes, name: str = "godot.log") -> Path:
        path = self.root / name
        data = content.encode("utf-8") if isinstance(content, str) else content
        path.write_bytes(data)
        return path

    def run_gate(self, argv: list[str]) -> tuple[int, str, str]:
        module = load_script()
        out = io.StringIO()
        err = io.StringIO()
        code: int
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            try:
                code = module.main(argv)
            except SystemExit as exit_info:
                # argparse reports bad usage through SystemExit
                code = exit_info.code if isinstance(exit_info.code, int) else 1
        return code, out.getvalue(), err.getvalue()

    def run_step(self, step: str, content: str | bytes) -> tuple[int, str, str]:
        return self.run_gate(["--step", step, str(self.write(content))])

    def assert_clean(self, step: str, content: str | bytes) -> None:
        code, out, err = self.run_step(step, content)
        self.assertEqual(code, 0, f"{step}: expected a pass, got: {err}")
        self.assertEqual(out, "")
        self.assertEqual(err, "")


GENERIC_STEPS = ("import", "export", "smoke")
ALL_STEPS = ("import-first", "import", "test", "export", "smoke")


class EngineLineTest(GateTestCase):
    # AC1: ERROR lines

    def test_ac1_error_line_fails_and_is_printed_in_import_and_export(self) -> None:
        for step in GENERIC_STEPS:
            with self.subTest(step=step):
                code, _, err = self.run_step(step, IMPORT_CLEAN + ENGINE_ERROR + "\n")
                self.assertEqual(code, 1)
                self.assertIn(f"Engine log gate [{step}]: {ENGINE_ERROR}", err)

    def test_ac1_every_offending_line_is_listed_in_log_order_then_the_summary(self) -> None:
        second = "ERROR: A second problem"
        path = self.write(IMPORT_CLEAN + ENGINE_ERROR + "\nfine line\n" + second + "\n")
        code, out, err = self.run_gate(["--step", "import", str(path)])
        self.assertEqual(code, 1)
        self.assertEqual(out, "")
        first_text = f"Engine log gate [import]: {ENGINE_ERROR}"
        second_text = f"Engine log gate [import]: {second}"
        summary = f"Engine log gate [import]: 2 finding(s) in {path}"
        self.assertLess(err.index(first_text), err.index(second_text))
        self.assertLess(err.index(second_text), err.index(summary))
        self.assertTrue(err.rstrip().endswith(summary))

    def test_ac1_powershell_prefix_still_matches(self) -> None:
        line = "godot_console : " + ENGINE_ERROR
        code, _, err = self.run_step("import", IMPORT_CLEAN + line + "\n")
        self.assertEqual(code, 1)
        self.assertIn(ENGINE_ERROR, err)

    def test_ac1_ansi_coloured_line_matches_and_is_printed_without_escapes(self) -> None:
        line = f"{ESC}[1;31mERROR:{ESC}[0;91m Coloured engine problem{ESC}[0m"
        code, _, err = self.run_step("export", IMPORT_CLEAN + line + "\n")
        self.assertEqual(code, 1)
        self.assertIn("ERROR: Coloured engine problem", err)
        self.assertNotIn(ESC, err)

    def test_ac1_token_without_a_colon_is_not_an_engine_line(self) -> None:
        self.assert_clean("import", IMPORT_CLEAN + "ERROR happened somewhere\nNO WARNING here\n")

    def test_ac1_lowercase_token_is_not_an_engine_line(self) -> None:
        self.assert_clean("import", IMPORT_CLEAN + "error: not an engine line\nwarning: nor this\n")

    # AC2: WARNING lines

    def test_ac2_warning_line_fails_and_is_printed_in_import_and_export(self) -> None:
        for step in GENERIC_STEPS:
            with self.subTest(step=step):
                code, _, err = self.run_step(step, IMPORT_CLEAN + ENGINE_WARNING + "\n")
                self.assertEqual(code, 1)
                self.assertIn(f"Engine log gate [{step}]: {ENGINE_WARNING}", err)

    # AC3: SCRIPT ERROR lines

    def test_ac3_script_error_line_fails_in_import_and_export(self) -> None:
        for step in GENERIC_STEPS:
            with self.subTest(step=step):
                code, _, err = self.run_step(step, IMPORT_CLEAN + SCRIPT_ERROR + "\n")
                self.assertEqual(code, 1)
                self.assertIn(SCRIPT_ERROR, err)

    # AC4: clean logs

    def test_ac4_clean_import_export_and_smoke_logs_exit_0_and_print_nothing(self) -> None:
        for step in GENERIC_STEPS:
            with self.subTest(step=step):
                self.assert_clean(step, IMPORT_CLEAN)

    def test_ac4_clean_test_log_with_windows_exits_0_and_prints_nothing(self) -> None:
        self.assert_clean("test", CLEAN_TEST_LOG)

    def test_ac4_clean_first_import_log_exits_0(self) -> None:
        self.assert_clean("import-first", IMPORT_CLEAN)

    # AC9a: bare parsing lines

    def test_ac9a_bare_unicode_parsing_error_passes_import_step(self) -> None:
        text = IMPORT_CLEAN + "Unicode parsing error, some characters were replaced with U+FFFD\n"
        self.assert_clean("import", text)

    def test_ac9a_bare_unicode_parsing_error_passes_in_and_out_of_a_window(self) -> None:
        bare = "Unicode parsing error, some characters were replaced with U+FFFD"
        inside = test_log(block("test_one", [bare]), block("test_two"))
        outside = test_log(bare + "\n", block("test_one"), bare + "\n")
        for name, text in (("inside", inside), ("outside", outside)):
            with self.subTest(position=name):
                self.assert_clean("test", text)


class AllowlistTest(GateTestCase):
    def entry(self, **changes: str) -> object:
        module = load_script()
        values = {
            "substring": "Something went wrong in the engine",
            "reason": "Known engine quirk, tracked on the linked issue",
            "issue": VALID_ISSUE,
        }
        values.update(changes)
        return module.AllowEntry(**values)

    def test_ac5_a_valid_entry_lets_the_matching_line_pass(self) -> None:
        module = load_script()
        path = self.write(IMPORT_CLEAN + ENGINE_ERROR + "\n")
        with mock.patch.object(module, "ALLOWLIST", (self.entry(),)):
            code, out, err = self.run_gate(["--step", "import", str(path)])
        self.assertEqual((code, out, err), (0, "", ""))

    def test_ac5_the_same_log_fails_with_the_empty_allowlist(self) -> None:
        module = load_script()
        path = self.write(IMPORT_CLEAN + ENGINE_ERROR + "\n")
        with mock.patch.object(module, "ALLOWLIST", ()):
            code, _, _ = self.run_gate(["--step", "import", str(path)])
        self.assertEqual(code, 1)

    def test_ac5_an_entry_only_covers_the_lines_it_matches(self) -> None:
        module = load_script()
        other = "ERROR: Something else entirely"
        path = self.write(IMPORT_CLEAN + ENGINE_ERROR + "\n" + other + "\n")
        with mock.patch.object(module, "ALLOWLIST", (self.entry(),)):
            code, _, err = self.run_gate(["--step", "import", str(path)])
        self.assertEqual(code, 1)
        self.assertIn(other, err)
        self.assertNotIn(f"gate [import]: {ENGINE_ERROR}", err)

    def test_ac5_an_entry_applies_in_every_step(self) -> None:
        module = load_script()
        with mock.patch.object(module, "ALLOWLIST", (self.entry(),)):
            for step in ("import", "export", "smoke"):
                with self.subTest(step=step):
                    code, out, err = self.run_step(step, IMPORT_CLEAN + ENGINE_ERROR + "\n")
                    self.assertEqual((code, out, err), (0, "", ""))
            code, _, _ = self.run_step("test", test_log(ENGINE_ERROR + "\n"))
            self.assertEqual(code, 0)

    def test_ac5_the_substring_is_literal_and_not_a_regex(self) -> None:
        module = load_script()
        path = self.write(IMPORT_CLEAN + ENGINE_ERROR + "\n")
        with mock.patch.object(module, "ALLOWLIST", (self.entry(substring="Something.*engine"),)):
            code, _, _ = self.run_gate(["--step", "import", str(path)])
        self.assertEqual(code, 1)

    def test_ac5_the_substring_is_case_sensitive(self) -> None:
        module = load_script()
        path = self.write(IMPORT_CLEAN + ENGINE_ERROR + "\n")
        entry = self.entry(substring="SOMETHING WENT WRONG")
        with mock.patch.object(module, "ALLOWLIST", (entry,)):
            code, _, _ = self.run_gate(["--step", "import", str(path)])
        self.assertEqual(code, 1)

    def test_ac5_a_valid_entry_has_no_problems(self) -> None:
        module = load_script()
        self.assertEqual(module.validate_allowlist((self.entry(),)), [])

    def invalid_entries(self) -> dict[str, object]:
        return {
            "empty reason": self.entry(reason=""),
            "whitespace reason": self.entry(reason="  \t "),
            "issue number only": self.entry(issue="#93"),
            "pull request url": self.entry(
                issue="https://github.com/PeterSallai90/cozy-aquarium/pull/93"
            ),
            "another repository": self.entry(
                issue="https://github.com/PeterSallai90/other-repo/issues/93"
            ),
            "issue url without a number": self.entry(
                issue="https://github.com/PeterSallai90/cozy-aquarium/issues/"
            ),
            "empty issue": self.entry(issue=""),
            "empty substring": self.entry(substring=""),
            "whitespace substring": self.entry(substring="   "),
            "bare ERROR token": self.entry(substring="ERROR:"),
            "bare WARNING token": self.entry(substring="WARNING:"),
            "bare SCRIPT ERROR token": self.entry(substring="SCRIPT ERROR:"),
            "part of an engine token": self.entry(substring="ERROR"),
        }

    def test_ac5_validate_allowlist_rejects_every_unexplained_or_match_all_entry(self) -> None:
        module = load_script()
        for name, entry in self.invalid_entries().items():
            with self.subTest(entry=name):
                problems = module.validate_allowlist((entry,))
                self.assertGreaterEqual(len(problems), 1)

    def test_ac5_main_exits_2_and_names_the_problem_for_an_invalid_entry(self) -> None:
        module = load_script()
        path = self.write(IMPORT_CLEAN)
        for name, entry in self.invalid_entries().items():
            with self.subTest(entry=name):
                with mock.patch.object(module, "ALLOWLIST", (entry,)):
                    code, _, err = self.run_gate(["--step", "import", str(path)])
                self.assertEqual(code, 2)
                self.assertIn("invalid allowlist entry 0", err)

    def test_ac5_an_invalid_entry_fails_every_step_even_on_a_clean_log(self) -> None:
        module = load_script()
        bad = self.entry(reason="")
        for step in ALL_STEPS:
            with self.subTest(step=step):
                path = self.write(IMPORT_CLEAN)
                with mock.patch.object(module, "ALLOWLIST", (bad,)):
                    code, _, _ = self.run_gate(["--step", step, str(path)])
                self.assertEqual(code, 2)

    def test_ac5_the_allowlist_is_validated_before_the_log_is_read(self) -> None:
        module = load_script()
        with mock.patch.object(module, "ALLOWLIST", (self.entry(reason=""),)):
            code, _, err = self.run_gate(["--step", "import", str(self.root / "missing.log")])
        self.assertEqual(code, 2)
        self.assertIn("invalid allowlist entry", err)

    # AC6: empty allowlist

    def test_ac6_the_shipped_allowlist_is_empty(self) -> None:
        # Adding an entry needs the owner's OK: editing this test brings it to the owner.
        module = load_script()
        self.assertEqual(len(module.ALLOWLIST), 0)

    def test_ac6_the_shipped_allowlist_validates(self) -> None:
        module = load_script()
        self.assertEqual(module.validate_allowlist(module.ALLOWLIST), [])


class LeakTest(GateTestCase):
    # AC7: leaks fail everywhere

    def test_ac7_each_leak_line_fails_the_test_step_outside_a_window(self) -> None:
        for line in (OBJECT_LINE, RESOURCE_LINE):
            with self.subTest(line=line):
                code, _, err = self.run_step("test", CLEAN_TEST_LOG + line + "\n")
                self.assertEqual(code, 1)
                self.assertIn(line, err)

    def test_ac7_each_leak_line_fails_the_test_step_inside_a_window(self) -> None:
        for line in (OBJECT_LINE, RESOURCE_LINE):
            with self.subTest(line=line):
                code, _, err = self.run_step("test", test_log(block("test_one", [line])))
                self.assertEqual(code, 1)
                self.assertIn(line, err)

    def test_ac7_each_pattern_without_a_prefix_fails(self) -> None:
        for bare in (OBJECT_PATTERN, RESOURCE_PATTERN):
            with self.subTest(pattern=bare):
                code, _, err = self.run_step("test", f"{bare}\n")
                self.assertEqual(code, 1)
                self.assertIn(bare, err)

    def test_ac7_powershell_prefix_still_matches(self) -> None:
        line = "godot_console : " + OBJECT_LINE
        code, _, err = self.run_step("test", CLEAN_TEST_LOG + line + "\n")
        self.assertEqual(code, 1)
        self.assertIn(OBJECT_LINE, err)

    def test_ac7_counts_do_not_matter(self) -> None:
        for count in (1, 8, 12345):
            with self.subTest(count=count):
                code, _, _ = self.run_step("test", f"WARNING: {count} {OBJECT_PATTERN} at exit\n")
                self.assertEqual(code, 1)

    def test_ac7_leak_line_without_trailing_newline_fails(self) -> None:
        code, _, _ = self.run_step("test", CLEAN_TEST_LOG + OBJECT_LINE)
        self.assertEqual(code, 1)

    def test_ac7_lowercase_and_uppercase_variants_pass(self) -> None:
        for variant in (
            "objectdb instances were leaked at exit",
            "4 RESOURCES STILL IN USE AT EXIT",
        ):
            with self.subTest(variant=variant):
                self.assert_clean("test", CLEAN_TEST_LOG + variant + "\n")

    def test_ac7_leak_lines_fail_every_step(self) -> None:
        for step in ALL_STEPS:
            for line in (OBJECT_LINE, RESOURCE_LINE):
                with self.subTest(step=step, line=line):
                    code, _, err = self.run_step(step, IMPORT_CLEAN + line + "\n")
                    self.assertEqual(code, 1)
                    self.assertIn(line, err)

    def test_ac7_a_line_matching_both_patterns_is_reported_once(self) -> None:
        line = f"{OBJECT_PATTERN} and {RESOURCE_PATTERN}"
        code, _, err = self.run_step("test", line + "\n")
        self.assertEqual(code, 1)
        self.assertEqual(err.count(line), 1)
        self.assertIn("1 finding(s)", err)

    def test_ac7_leak_patterns_constant_holds_exactly_the_two_strings(self) -> None:
        module = load_script()
        self.assertEqual(tuple(module.LEAK_PATTERNS), (OBJECT_PATTERN, RESOURCE_PATTERN))


class TestStepWindowTest(GateTestCase):
    # AC8: outside a window every engine line fails

    def positions(self, line: str) -> dict[str, str]:
        return {
            "before the first test": test_log(line + "\n", block("test_one")),
            "between two tests": test_log(block("test_one"), line + "\n", block("test_two")),
            "after the last test": test_log(block("test_one"), line + "\n"),
        }

    def test_ac8_engine_lines_outside_a_window_fail_and_are_printed(self) -> None:
        for line in ENGINE_TOKENS:
            for name, text in self.positions(line).items():
                with self.subTest(line=line, position=name):
                    code, _, err = self.run_step("test", text)
                    self.assertEqual(code, 1)
                    self.assertIn(f"Engine log gate [test]: {line}", err)

    # AC9: asserted lines inside a window are owned by GdUnit4

    def test_ac9_asserted_engine_output_inside_windows_passes_the_test_step(self) -> None:
        self.assert_clean("test", INSIDE_WINDOW_LOG)

    def test_ac9_the_same_output_fails_import_and_export(self) -> None:
        for step in ("import", "export"):
            with self.subTest(step=step):
                code, _, err = self.run_step(step, INSIDE_WINDOW_LOG)
                self.assertEqual(code, 1)
                self.assertIn("ERROR: Parse error in config file", err)
                self.assertIn("WARNING: probe: warning text", err)

    # window rule

    def test_window_closes_on_every_status(self) -> None:
        for status in (
            "PASSED",
            "FAILED",
            "FAILED (retry 2)",
            "SKIPPED",
            "FLAKY (2 retries)",
            "WARNING",
            "ERROR",
        ):
            with self.subTest(status=status):
                text = test_log(block("test_one", [ENGINE_ERROR], status), ENGINE_WARNING + "\n")
                code, _, err = self.run_step("test", text)
                self.assertEqual(code, 1)
                # the line inside the window is dropped, the one after it is a finding
                self.assertIn(ENGINE_WARNING, err)
                self.assertNotIn(ENGINE_ERROR, err)
                self.assertNotIn("unterminated", err)

    def test_window_closes_with_any_elapsed_time_format(self) -> None:
        for elapsed in ("6ms", "1s 23ms", "1min 2s 3ms", "1h 2min 3s 4ms"):
            with self.subTest(elapsed=elapsed):
                text = test_log(
                    "\n".join([started("test_one"), ENGINE_ERROR, ended("test_one", "PASSED", elapsed)])
                    + "\n"
                )
                self.assert_clean("test", text)

    def test_markers_without_a_space_before_the_status_still_work(self) -> None:
        # GdUnit4 moves the cursor (ESC[nG) instead of printing a space for short paths.
        short = "res://t.gd"
        start = f"{short} > test_x{ESC}[60GSTARTED"
        end = f"{short} > test_x{ESC}[60GPASSED 4ms"
        self.assert_clean("test", test_log(f"{start}\n{ENGINE_ERROR}\n{end}\n"))

    def test_marker_lines_are_never_findings(self) -> None:
        text = test_log(block("test_one", status="WARNING"), block("test_two", status="ERROR"))
        self.assert_clean("test", text)

    def test_test_names_with_spaces_and_parameters_are_matched(self) -> None:
        name = "test_value (param: 1, 2)"
        self.assert_clean("test", test_log(block(name, [ENGINE_ERROR])))

    def test_each_test_has_its_own_window(self) -> None:
        text = test_log(block("test_one", [ENGINE_ERROR]), block("test_two", [ENGINE_WARNING]))
        self.assert_clean("test", text)

    def test_unterminated_window_at_end_of_log_fails_and_reports_held_lines(self) -> None:
        start = started("test_crash")
        text = test_log(f"{start}\n{ENGINE_ERROR}\n")
        text = text.split("Statistics:")[0]  # a truncated log: no end line, no summary
        code, _, err = self.run_step("test", text)
        self.assertEqual(code, 1)
        self.assertIn("unterminated test window", err)
        self.assertIn(f"{SUITE} > test_crash", err)
        self.assertIn(ENGINE_ERROR, err)
        self.assertNotIn(ESC, err)

    def test_unterminated_window_suppresses_nothing(self) -> None:
        text = f"{started('test_crash')}\n{ENGINE_ERROR}\n{ENGINE_WARNING}\n{SCRIPT_ERROR}\n"
        code, _, err = self.run_step("test", text)
        self.assertEqual(code, 1)
        for line in ENGINE_TOKENS:
            self.assertIn(line, err)
        self.assertIn("4 finding(s)", err)

    def test_second_started_before_the_end_line_is_an_unterminated_window(self) -> None:
        text = test_log(
            f"{started('test_one')}\n{ENGINE_ERROR}\n{block('test_two')}"
        )
        code, _, err = self.run_step("test", text)
        self.assertEqual(code, 1)
        self.assertIn("unterminated test window", err)
        self.assertIn(f"{SUITE} > test_one", err)
        self.assertIn(ENGINE_ERROR, err)

    def test_end_line_of_a_different_test_does_not_close_the_window(self) -> None:
        text = test_log(f"{started('test_one')}\n{ENGINE_ERROR}\n{ended('test_other')}\n")
        code, _, err = self.run_step("test", text)
        self.assertEqual(code, 1)
        self.assertIn("unterminated test window", err)
        self.assertIn(ENGINE_ERROR, err)

    def test_end_line_of_the_same_test_in_another_suite_does_not_close_the_window(self) -> None:
        other_suite = "res://tests/b/test_b.gd"
        text = test_log(
            f"{started('test_one')}\n{ENGINE_ERROR}\n{ended('test_one', suite=other_suite)}\n"
        )
        code, _, err = self.run_step("test", text)
        self.assertEqual(code, 1)
        self.assertIn("unterminated test window", err)

    def test_stray_end_line_without_an_open_window_is_ignored(self) -> None:
        text = test_log(block("test_one"), ended("test_stray") + "\n", block("test_two"))
        self.assert_clean("test", text)

    def test_findings_are_listed_in_log_order(self) -> None:
        text = test_log(
            ENGINE_ERROR + "\n",
            block("test_one"),
            ENGINE_WARNING + "\n",
            f"{started('test_two')}\n",
        )
        code, _, err = self.run_step("test", text)
        self.assertEqual(code, 1)
        self.assertLess(err.index(ENGINE_ERROR), err.index(ENGINE_WARNING))
        self.assertLess(err.index(ENGINE_WARNING), err.index("unterminated"))
        self.assertIn("3 finding(s)", err)

    def test_window_rule_applies_only_to_the_test_step(self) -> None:
        text = test_log(block("test_one", [ENGINE_ERROR]))
        for step in ("import", "export", "smoke", "import-first"):
            with self.subTest(step=step):
                code, _, _ = self.run_step(step, text)
                self.assertEqual(code, 1)


class PinnedImportTest(GateTestCase):
    def import_log(self, lines: list[str]) -> str:
        return IMPORT_HEAD + "\n".join(lines) + "\nDone.\n"

    def test_ac15a_the_ten_pinned_lines_pass_the_first_import_step(self) -> None:
        self.assertEqual(len(PINNED_LINES), 10)
        self.assert_clean("import-first", self.import_log(PINNED_LINES))

    def test_ac15a_a_subset_of_the_pinned_lines_passes(self) -> None:
        self.assert_clean("import-first", self.import_log(PINNED_LINES[:3]))
        self.assert_clean("import-first", self.import_log(PINNED_LINES[-2:]))

    def test_ac15a_pinned_lines_pass_with_a_powershell_prefix(self) -> None:
        lines = ["godot_console : " + line for line in PINNED_LINES]
        self.assert_clean("import-first", self.import_log(lines))

    def test_ac15a_pinned_lines_pass_with_ansi_codes(self) -> None:
        lines = [
            line.replace("ERROR:", f"{ESC}[1;31mERROR:{ESC}[0;91m", 1) + ESC + "[0m"
            for line in PINNED_LINES
        ]
        self.assert_clean("import-first", self.import_log(lines))

    def test_ac15a_another_32_hex_hash_passes(self) -> None:
        lines = list(PINNED_LINES)
        lines[0] = lines[0].replace(HASH_A, HASH_C)
        lines[2] = lines[2].replace(HASH_A, HASH_D)
        self.assert_clean("import-first", self.import_log(lines))

    def test_ac15a_pinned_lines_plus_another_engine_line_fail_with_only_that_line(self) -> None:
        for extra in ENGINE_TOKENS:
            with self.subTest(extra=extra):
                code, _, err = self.run_step(
                    "import-first", self.import_log([*PINNED_LINES[:5], extra, *PINNED_LINES[5:]])
                )
                self.assertEqual(code, 1)
                self.assertIn(f"Engine log gate [import-first]: {extra}", err)
                self.assertIn("1 finding(s)", err)
                self.assertNotIn("cozy_theme", err)
                self.assertNotIn("nunito_variable", err)

    def test_ac15a_an_eleventh_pinned_shape_line_fails(self) -> None:
        extra = PINNED_LINES[-1]
        code, _, err = self.run_step("import-first", self.import_log([*PINNED_LINES, extra]))
        self.assertEqual(code, 1)
        self.assertIn("1 finding(s)", err)
        self.assertIn("Error loading custom project theme", err)

    def test_ac15a_a_third_copy_of_a_doubled_shape_fails(self) -> None:
        extra = PINNED_LINES[6]
        code, _, err = self.run_step("import-first", self.import_log([*PINNED_LINES, extra]))
        self.assertEqual(code, 1)
        self.assertIn("1 finding(s)", err)

    def test_ac15a_a_third_font_name_fails(self) -> None:
        line = f"ERROR: Cannot open file 'res://.godot/imported/third_font.ttf-{HASH_A}.fontdata'."
        code, _, err = self.run_step("import-first", self.import_log([line]))
        self.assertEqual(code, 1)
        self.assertIn("third_font", err)

    def test_ac15a_a_non_hex_or_wrong_length_hash_fails(self) -> None:
        for bad in ("zz" * 16, "0123456789abcdef", HASH_A + "0", HASH_A.upper()):
            with self.subTest(hash=bad):
                line = f"ERROR: Cannot open file 'res://.godot/imported/nunito_variable.ttf-{bad}.fontdata'."
                code, _, _ = self.run_step("import-first", self.import_log([line]))
                self.assertEqual(code, 1)

    def test_ac15a_a_pinned_text_with_a_different_theme_line_number_fails(self) -> None:
        line = PINNED_LINES[6].replace("cozy_theme.tres:7", "cozy_theme.tres:8")
        code, _, _ = self.run_step("import-first", self.import_log([line]))
        self.assertEqual(code, 1)

    def test_ac15a_pinned_shapes_are_only_errors_a_warning_with_the_same_text_fails(self) -> None:
        line = PINNED_LINES[8].replace("ERROR:", "WARNING:", 1)
        code, _, _ = self.run_step("import-first", self.import_log([line]))
        self.assertEqual(code, 1)

    def test_ac15a_the_ten_lines_under_the_import_step_give_ten_findings(self) -> None:
        code, _, err = self.run_step("import", self.import_log(PINNED_LINES))
        self.assertEqual(code, 1)
        self.assertIn("10 finding(s)", err)

    def test_ac15a_the_ten_lines_fail_export_and_test_steps_too(self) -> None:
        for step in ("export", "smoke"):
            with self.subTest(step=step):
                code, _, err = self.run_step(step, self.import_log(PINNED_LINES))
                self.assertEqual(code, 1)
                self.assertIn("10 finding(s)", err)
        code, _, _ = self.run_step("test", self.import_log(PINNED_LINES))
        self.assertEqual(code, 1)

    def test_ac15a_leaks_are_not_pinned_in_the_first_import_step(self) -> None:
        code, _, err = self.run_step("import-first", self.import_log([*PINNED_LINES, OBJECT_LINE]))
        self.assertEqual(code, 1)
        self.assertIn(OBJECT_LINE, err)

    def test_ac15a_the_pinned_set_is_not_an_allowlist_entry(self) -> None:
        module = load_script()
        self.assertEqual(len(module.ALLOWLIST), 0)
        self.assertEqual(sum(p.max_count for p in module.FIRST_IMPORT_PINNED), 10)


class StepRulesTest(GateTestCase):
    # AC23: smoke step and the rules table

    def test_ac23_the_rules_table_holds_exactly_the_five_steps(self) -> None:
        module = load_script()
        self.assertEqual(set(module.RULES), set(ALL_STEPS))

    def test_ac23_smoke_uses_the_same_rule_as_import_and_export(self) -> None:
        module = load_script()
        self.assertIs(module.RULES["smoke"], module.RULES["import"])
        self.assertIs(module.RULES["smoke"], module.RULES["export"])

    def test_ac23_smoke_step_is_accepted_and_fails_on_an_error_line(self) -> None:
        code, _, err = self.run_step("smoke", IMPORT_CLEAN + ENGINE_ERROR + "\n")
        self.assertEqual(code, 1)
        self.assertIn("Engine log gate [smoke]:", err)

    def test_ac23_the_step_names_the_summary_line(self) -> None:
        for step in ALL_STEPS:
            with self.subTest(step=step):
                path = self.write(IMPORT_CLEAN + OBJECT_LINE + "\n")
                _, _, err = self.run_gate(["--step", step, str(path)])
                self.assertIn(f"Engine log gate [{step}]: 1 finding(s) in {path}", err)


class UnreadableLogTest(GateTestCase):
    # AC11: never pass silently

    def test_ac11_missing_file_exits_2_and_names_the_path(self) -> None:
        for step in ALL_STEPS:
            with self.subTest(step=step):
                path = self.root / "does-not-exist.log"
                code, _, err = self.run_gate(["--step", step, str(path)])
                self.assertEqual(code, 2)
                self.assertIn(f"Engine log gate [{step}]: cannot check {path}", err)

    def test_ac11_empty_file_exits_2_and_names_the_path(self) -> None:
        for step in ALL_STEPS:
            with self.subTest(step=step):
                path = self.write(b"")
                code, _, err = self.run_gate(["--step", step, str(path)])
                self.assertEqual(code, 2)
                self.assertIn(str(path), err)

    def test_ac11_whitespace_only_file_exits_2(self) -> None:
        for step in ALL_STEPS:
            with self.subTest(step=step):
                code, _, _ = self.run_step(step, "  \n\n\t\n")
                self.assertEqual(code, 2)

    def test_ac11_directory_as_log_exits_2_and_names_the_path(self) -> None:
        for step in ALL_STEPS:
            with self.subTest(step=step):
                path = self.root / f"a-directory-{step}"
                path.mkdir()
                code, _, err = self.run_gate(["--step", step, str(path)])
                self.assertEqual(code, 2)
                self.assertIn(str(path), err)

    def test_ac11_utf16_without_bom_is_never_a_pass(self) -> None:
        for step in ALL_STEPS:
            with self.subTest(step=step):
                path = self.write(IMPORT_CLEAN.encode("utf-16-le"))
                code, _, err = self.run_gate(["--step", step, str(path)])
                self.assertEqual(code, 2)
                self.assertIn(str(path), err)

    def test_ac11_leak_failure_and_unreadable_log_differ_in_message_and_code(self) -> None:
        leak_code, _, leak_err = self.run_step("test", OBJECT_LINE + "\n")
        bad_code, _, bad_err = self.run_gate(["--step", "test", str(self.root / "nope.log")])
        self.assertEqual(leak_code, 1)
        self.assertEqual(bad_code, 2)
        self.assertNotEqual(leak_err, bad_err)

    # encodings

    def test_encoding_utf16_le_with_bom_is_decoded_and_reported(self) -> None:
        text = IMPORT_CLEAN + ENGINE_ERROR + "\n" + OBJECT_LINE + "\n"
        for step in GENERIC_STEPS:
            with self.subTest(step=step):
                code, _, err = self.run_step(step, b"\xff\xfe" + text.encode("utf-16-le"))
                self.assertEqual(code, 1)
                self.assertIn(ENGINE_ERROR, err)
                self.assertIn(OBJECT_LINE, err)

    def test_encoding_utf16_be_with_bom_is_decoded_and_reported(self) -> None:
        text = IMPORT_CLEAN + ENGINE_ERROR + "\n"
        code, _, err = self.run_step("import", b"\xfe\xff" + text.encode("utf-16-be"))
        self.assertEqual(code, 1)
        self.assertIn(ENGINE_ERROR, err)

    def test_encoding_clean_utf16_logs_exit_0(self) -> None:
        self.assert_clean("import", b"\xff\xfe" + IMPORT_CLEAN.encode("utf-16-le"))
        self.assert_clean("test", b"\xfe\xff" + CLEAN_TEST_LOG.encode("utf-16-be"))

    def test_encoding_utf8_with_bom_is_decoded_and_reported(self) -> None:
        text = ENGINE_ERROR + "\n" + IMPORT_CLEAN
        code, _, err = self.run_step("import", b"\xef\xbb\xbf" + text.encode("utf-8"))
        self.assertEqual(code, 1)
        self.assertIn(f"gate [import]: {ENGINE_ERROR}", err)

    def test_encoding_crlf_line_endings_are_reported_and_clean_logs_pass(self) -> None:
        text = (IMPORT_CLEAN + ENGINE_ERROR + "\n" + RESOURCE_LINE + "\n").replace("\n", "\r\n")
        code, _, err = self.run_step("import", text.encode("utf-8"))
        self.assertEqual(code, 1)
        self.assertIn("2 finding(s)", err)
        self.assert_clean("import", IMPORT_CLEAN.replace("\n", "\r\n").encode("utf-8"))

    def test_encoding_crlf_test_log_windows_still_close(self) -> None:
        self.assert_clean("test", INSIDE_WINDOW_LOG.replace("\n", "\r\n").encode("utf-8"))

    def test_encoding_stray_invalid_bytes_do_not_crash_or_hide_a_finding(self) -> None:
        data = b"caf\xe9 \xff\xfe broken\n" + ENGINE_ERROR.encode("utf-8") + b"\n"
        code, _, err = self.run_step("import", data)
        self.assertEqual(code, 1)
        self.assertIn(ENGINE_ERROR, err)


class UsageTest(GateTestCase):
    # AC12

    def test_ac12_no_arguments_fail_with_usage(self) -> None:
        code, _, err = self.run_gate([])
        self.assertNotEqual(code, 0)
        self.assertIn("usage", err.lower())

    def test_ac12_missing_step_fails_with_usage(self) -> None:
        code, _, err = self.run_gate([str(self.write(IMPORT_CLEAN))])
        self.assertNotEqual(code, 0)
        self.assertIn("usage", err.lower())

    def test_ac12_unknown_step_fails_with_usage(self) -> None:
        code, _, err = self.run_gate(["--step", "bogus", str(self.write(IMPORT_CLEAN))])
        self.assertNotEqual(code, 0)
        self.assertIn("usage", err.lower())

    def test_ac12_missing_log_argument_fails_with_usage(self) -> None:
        code, _, err = self.run_gate(["--step", "import"])
        self.assertNotEqual(code, 0)
        self.assertIn("usage", err.lower())

    def test_ac12_two_log_arguments_fail_with_usage(self) -> None:
        first = self.write(IMPORT_CLEAN, "one.log")
        second = self.write(IMPORT_CLEAN, "two.log")
        code, _, err = self.run_gate(["--step", "import", str(first), str(second)])
        self.assertNotEqual(code, 0)
        self.assertIn("usage", err.lower())

    def test_ac12_the_old_single_argument_form_is_no_longer_accepted(self) -> None:
        code, _, _ = self.run_gate([str(self.write(IMPORT_CLEAN))])
        self.assertNotEqual(code, 0)


class RepositoryRulesTest(unittest.TestCase):
    # AC13: single home for the patterns

    def other_sources(self) -> list[Path]:
        this_file = Path(__file__).resolve()
        scripts = [
            p
            for p in sorted(SCRIPTS_DIR.glob("*.py"))
            if p.resolve() not in (this_file, GATE_PATH.resolve())
        ]
        return scripts + sorted((REPO_ROOT / ".github" / "workflows").glob("*.yml"))

    def test_ac13_no_other_script_or_workflow_repeats_a_pattern(self) -> None:
        for source in self.other_sources():
            text = source.read_text(encoding="utf-8")
            for pattern in (OBJECT_PATTERN, RESOURCE_PATTERN, "SCRIPT ERROR:"):
                with self.subTest(file=source.name, pattern=pattern):
                    self.assertNotIn(pattern, text)

    def test_ac13_the_gate_defines_each_pattern_once(self) -> None:
        text = GATE_PATH.read_text(encoding="utf-8")
        self.assertEqual(text.count(f'"{OBJECT_PATTERN}"'), 1)
        self.assertEqual(text.count(f'"{RESOURCE_PATTERN}"'), 1)
        self.assertEqual(text.count("SCRIPT ERROR"), 1)

    def test_ac13_the_gate_docstring_does_not_quote_the_leak_patterns(self) -> None:
        text = GATE_PATH.read_text(encoding="utf-8")
        self.assertEqual(text.count(OBJECT_PATTERN), 1)
        self.assertEqual(text.count(RESOURCE_PATTERN), 1)

    # AC14: the old script is gone

    def test_ac14_the_old_script_and_its_tests_are_gone(self) -> None:
        self.assertFalse((SCRIPTS_DIR / f"{OLD_SCRIPT}.py").exists())
        self.assertFalse((SCRIPTS_DIR / f"{OLD_TEST}.py").exists())

    def test_ac14_no_tracked_file_references_the_old_script(self) -> None:
        listing = subprocess.run(
            ["git", "ls-files", "-z"],
            cwd=REPO_ROOT,
            capture_output=True,
            check=True,
        ).stdout
        needle = OLD_SCRIPT.encode("ascii")
        offenders = []
        for name in listing.split(b"\0"):
            if not name:
                continue
            path = REPO_ROOT / name.decode("utf-8")
            if path.is_file() and needle in path.read_bytes():
                offenders.append(name.decode("utf-8"))
        self.assertEqual(offenders, [])

    def test_ac14_the_gate_and_its_tests_exist(self) -> None:
        self.assertTrue(GATE_PATH.is_file())
        self.assertTrue((SCRIPTS_DIR / "test_check_godot_log.py").is_file())


class CiWiringTest(unittest.TestCase):
    # AC16-18 (unit part): plain text reading, no PyYAML in the lint job.

    def setUp(self) -> None:
        self.text = CI_YML.read_text(encoding="utf-8")

    def step_block(self, name: str) -> str:
        """The text of the step named `name`, up to the next step or job."""
        pattern = re.compile(
            rf"^( *)- name: {re.escape(name)}\n(.*?)(?=^\1- |^\S|^  \S|\Z)", re.M | re.S
        )
        match = pattern.search(self.text)
        self.assertIsNotNone(match, f"step '{name}' not found in ci.yml")
        assert match is not None
        return match.group(0)

    def test_ci_calls_the_gate_with_each_step(self) -> None:
        for step in ("import-first", "import", "test", "export"):
            with self.subTest(step=step):
                self.assertRegex(
                    self.text,
                    rf"check_godot_log\.py --step {re.escape(step)} \"\$RUNNER_TEMP/godot-[a-z-]+\.log\"",
                )

    def test_ci_has_the_four_check_steps_each_with_if_always(self) -> None:
        for name in (
            "Check first import output",
            "Check import output",
            "Check test output",
            "Check export output",
        ):
            with self.subTest(step=name):
                block = self.step_block(name)
                self.assertIn("if: always()", block)
                self.assertIn("check_godot_log.py", block)

    def test_ci_each_check_step_reads_the_log_of_its_own_command(self) -> None:
        expected = {
            "Check first import output": ("import-first", "godot-import-first.log"),
            "Check import output": ("import", "godot-import.log"),
            "Check test output": ("test", "godot-tests.log"),
            "Check export output": ("export", "godot-export.log"),
        }
        for name, (step, log) in expected.items():
            with self.subTest(step=name):
                block = self.step_block(name)
                self.assertIn(f"--step {step} ", block)
                self.assertIn(log, block)

    def test_ci_imports_the_project_twice_per_job(self) -> None:
        self.assertEqual(self.text.count("--headless --path game --import"), 4)
        self.assertEqual(self.text.count("godot-import-first.log"), 4)  # tee + check, 2 jobs
        self.assertEqual(self.text.count('tee "$RUNNER_TEMP/godot-import.log"'), 2)
        self.assertEqual(self.text.count("|| true"), 2)

    def test_ci_second_import_has_pipefail_and_tee(self) -> None:
        for block in re.findall(r"- name: Import project\n(.*?)(?=\n      - )", self.text, re.S):
            self.assertIn("set -o pipefail", block)
            self.assertLess(block.index("|| true"), block.index("set -o pipefail"))
            self.assertIn('tee "$RUNNER_TEMP/godot-import-first.log"', block)
            self.assertIn('tee "$RUNNER_TEMP/godot-import.log"', block)

    def test_ci_run_tests_block_still_has_pipefail_and_tee(self) -> None:
        block = self.step_block("Run tests")
        self.assertIn("set -o pipefail", block)
        self.assertIn('tee "$RUNNER_TEMP/godot-tests.log"', block)
        self.assertIn("-a res://tests --ignoreHeadlessMode", block)

    def test_ci_export_block_has_pipefail_tee_and_the_artifact_check(self) -> None:
        block = self.step_block("Export Windows build")
        self.assertIn("set -o pipefail", block)
        self.assertIn('tee "$RUNNER_TEMP/godot-export.log"', block)
        self.assertIn("test -f build/windows/CozyAquarium.exe", block)

    def test_ci_step_order_in_the_test_job(self) -> None:
        names = [
            "Import project",
            "Check first import output",
            "Check import output",
            "Run tests",
            "Check test output",
            "Check that tests ran",
        ]
        positions = [self.text.index(f"- name: {name}") for name in names]
        self.assertEqual(positions, sorted(positions))

    def test_ci_step_order_in_the_build_job(self) -> None:
        build = self.text[self.text.index("  build-windows:") :]
        names = [
            "Import project",
            "Check first import output",
            "Check import output",
            "Export Windows build",
            "Check export output",
        ]
        positions = [build.index(f"- name: {name}") for name in names]
        self.assertEqual(positions, sorted(positions))

    def test_ci_does_not_mention_the_old_script_or_step_name(self) -> None:
        self.assertNotIn(OLD_SCRIPT, self.text)
        self.assertNotIn("Check for leaks at exit", self.text)


class EncodingSafetyTest(GateTestCase):
    def test_a_finding_with_non_ascii_text_never_crashes_the_gate(self) -> None:
        path = self.write("ERROR: café � broken\n".encode("utf-8"))
        env = dict(os.environ, PYTHONIOENCODING="ascii", PYTHONUTF8="0")
        result = subprocess.run(
            [sys.executable, str(GATE_PATH), "--step", "import", str(path)],
            capture_output=True,
            env=env,
            check=False,
        )
        stderr = result.stderr.decode("ascii", errors="replace")
        self.assertEqual(result.returncode, 1, stderr)
        self.assertNotIn("Traceback", stderr)
        self.assertIn("Engine log gate [import]:", stderr)


if __name__ == "__main__":
    unittest.main()
