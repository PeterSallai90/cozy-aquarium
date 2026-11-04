"""Tests for issue #88: the CI leak gate (tools/scripts/check_test_leaks.py).

Acceptance criteria covered here:
- AC3: pattern matching (case-sensitive substring, any prefix, counts ignored, one pattern list).
- AC4: a clean log exits 0 and prints nothing.
- AC5: a missing, empty or unreadable log, and bad arguments, never pass silently.
- Encodings: UTF-16 LE with BOM (Windows PowerShell 5.1 Tee-Object), UTF-8 BOM and CRLF.
AC1/AC2 and AC10 live in the GdUnit suite run, AC6/AC7 are CI wiring, AC8/AC9 are manual.

The script module is imported lazily so that a missing script fails each test for the same
reason: the behaviour does not exist yet.

Run: python -m unittest discover -s tools/scripts -p "test_*.py"
"""

from __future__ import annotations

import contextlib
import importlib
import io
import tempfile
import unittest
from pathlib import Path
from types import ModuleType

SCRIPTS_DIR = Path(__file__).resolve().parent

OBJECT_LINE = "WARNING: 3 ObjectDB instances were leaked at exit (run with --verbose for details)."
RESOURCE_LINE = "ERROR: 7 resources still in use at exit (run with --verbose for details)."
OBJECT_PATTERN = "ObjectDB instances were leaked"
RESOURCE_PATTERN = "resources still in use at exit"

CLEAN_LOG = (
    "Godot Engine v4.7.2.stable.official - https://godotengine.org\n"
    "WARNING: Some unrelated engine warning at: shader_compile (a.cpp:12)\n"
    "Run Test Suites\n"
    "  res://tests/a/test_a.gd > test_one PASSED 4ms\n"
    "  res://tests/a/test_a.gd > test_two PASSED 3ms\n"
    "WARNING: Another warning about something else\n"
    "Statistics: 2 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 0 orphans | PASSED\n"
    "Overall Summary: 2 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 0 orphans |\n"
    "Total execution time: 1s 2ms\n"
)


def load_script() -> ModuleType:
    return importlib.import_module("check_test_leaks")


class CheckTestLeaksTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)

    def write(self, content: str | bytes, name: str = "godot-tests.log") -> Path:
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

    def run_on(self, path: Path) -> tuple[int, str, str]:
        return self.run_gate([str(path)])

    # AC3: what counts as a leak

    def test_ac3_object_leak_line_fails_and_is_printed(self) -> None:
        code, out, err = self.run_on(self.write(CLEAN_LOG + OBJECT_LINE + "\n"))
        self.assertNotEqual(code, 0)
        self.assertIn(OBJECT_LINE, out + err)

    def test_ac3_resource_leak_line_fails_and_is_printed(self) -> None:
        code, out, err = self.run_on(self.write(CLEAN_LOG + RESOURCE_LINE + "\n"))
        self.assertNotEqual(code, 0)
        self.assertIn(RESOURCE_LINE, out + err)

    def test_ac3_each_pattern_without_a_prefix_fails(self) -> None:
        for bare in (OBJECT_PATTERN, RESOURCE_PATTERN):
            with self.subTest(pattern=bare):
                code, out, err = self.run_on(self.write(f"{bare}\n"))
                self.assertNotEqual(code, 0)
                self.assertIn(bare, out + err)

    def test_ac3_powershell_prefix_still_matches(self) -> None:
        line = "godot_console : " + OBJECT_LINE
        code, out, err = self.run_on(self.write(CLEAN_LOG + line + "\n"))
        self.assertNotEqual(code, 0)
        self.assertIn(OBJECT_LINE, out + err)

    def test_ac3_counts_do_not_matter(self) -> None:
        for count in (1, 8, 12345):
            with self.subTest(count=count):
                line = f"WARNING: {count} ObjectDB instances were leaked at exit"
                code, _, _ = self.run_on(self.write(line + "\n"))
                self.assertNotEqual(code, 0)

    def test_ac3_leak_line_without_trailing_newline_fails(self) -> None:
        code, _, _ = self.run_on(self.write(CLEAN_LOG + OBJECT_LINE))
        self.assertNotEqual(code, 0)

    def test_ac3_lowercase_variant_is_not_reported(self) -> None:
        text = CLEAN_LOG + "objectdb instances were leaked at exit\n"
        code, out, err = self.run_on(self.write(text))
        self.assertEqual(code, 0)
        self.assertEqual(out + err, "")

    def test_ac3_uppercase_variant_is_not_reported(self) -> None:
        text = CLEAN_LOG + "ERROR: 4 RESOURCES STILL IN USE AT EXIT\n"
        code, out, err = self.run_on(self.write(text))
        self.assertEqual(code, 0)
        self.assertEqual(out + err, "")

    def test_ac3_leak_patterns_constant_holds_exactly_the_two_strings(self) -> None:
        module = load_script()
        self.assertEqual(tuple(module.LEAK_PATTERNS), (OBJECT_PATTERN, RESOURCE_PATTERN))

    def test_ac3_no_other_script_repeats_the_patterns(self) -> None:
        this_file = Path(__file__).resolve()
        for script in sorted(SCRIPTS_DIR.glob("*.py")):
            if script.resolve() == this_file or script.name == "check_test_leaks.py":
                continue
            text = script.read_text(encoding="utf-8")
            for pattern in (OBJECT_PATTERN, RESOURCE_PATTERN):
                self.assertNotIn(pattern, text, f"{script.name} repeats a leak pattern")

    def test_ac3_the_script_defines_each_pattern_once(self) -> None:
        text = (SCRIPTS_DIR / "check_test_leaks.py").read_text(encoding="utf-8")
        self.assertEqual(text.count(f'"{OBJECT_PATTERN}"'), 1)
        self.assertEqual(text.count(f'"{RESOURCE_PATTERN}"'), 1)

    # AC4: clean log

    def test_ac4_clean_log_exits_0_and_prints_nothing(self) -> None:
        code, out, err = self.run_on(self.write(CLEAN_LOG))
        self.assertEqual(code, 0)
        self.assertEqual(out, "")
        self.assertEqual(err, "")

    # AC5: never pass silently

    def test_ac5_missing_file_fails_and_names_the_path(self) -> None:
        path = self.root / "does-not-exist.log"
        code, out, err = self.run_on(path)
        self.assertNotEqual(code, 0)
        self.assertIn(str(path), out + err)

    def test_ac5_empty_file_fails_and_names_the_path(self) -> None:
        path = self.write(b"")
        code, out, err = self.run_on(path)
        self.assertNotEqual(code, 0)
        self.assertIn(str(path), out + err)

    def test_ac5_whitespace_only_file_fails(self) -> None:
        code, _, _ = self.run_on(self.write("  \n\n\t\n"))
        self.assertNotEqual(code, 0)

    def test_ac5_directory_as_log_fails_and_names_the_path(self) -> None:
        path = self.root / "a-directory"
        path.mkdir()
        code, out, err = self.run_on(path)
        self.assertNotEqual(code, 0)
        self.assertIn(str(path), out + err)

    def test_ac5_both_leaks_are_reported_in_log_order(self) -> None:
        text = CLEAN_LOG + OBJECT_LINE + "\nsome line between\n" + RESOURCE_LINE + "\n"
        code, out, err = self.run_on(self.write(text))
        shown = out + err
        self.assertNotEqual(code, 0)
        self.assertIn(OBJECT_LINE, shown)
        self.assertIn(RESOURCE_LINE, shown)
        self.assertLess(shown.index(OBJECT_LINE), shown.index(RESOURCE_LINE))

    def test_ac5_log_order_is_kept_when_the_resource_line_comes_first(self) -> None:
        text = RESOURCE_LINE + "\n" + OBJECT_LINE + "\n"
        _, out, err = self.run_on(self.write(text))
        shown = out + err
        self.assertLess(shown.index(RESOURCE_LINE), shown.index(OBJECT_LINE))

    def test_ac5_a_line_matching_both_patterns_is_reported_once(self) -> None:
        line = f"{OBJECT_PATTERN} and {RESOURCE_PATTERN}"
        code, out, err = self.run_on(self.write(line + "\n"))
        self.assertNotEqual(code, 0)
        self.assertEqual((out + err).count(line), 1)

    def test_ac5_leak_failure_and_unreadable_log_differ_in_their_message(self) -> None:
        leak_code, leak_out, leak_err = self.run_on(self.write(OBJECT_LINE + "\n"))
        bad_code, bad_out, bad_err = self.run_on(self.root / "nope.log")
        self.assertNotEqual(leak_code, 0)
        self.assertNotEqual(bad_code, 0)
        self.assertNotEqual(leak_out + leak_err, bad_out + bad_err)

    # Encodings

    def test_encoding_utf16_le_with_bom_is_still_reported(self) -> None:
        text = CLEAN_LOG + OBJECT_LINE + "\n" + RESOURCE_LINE + "\n"
        code, out, err = self.run_on(self.write(b"\xff\xfe" + text.encode("utf-16-le")))
        self.assertNotEqual(code, 0)
        self.assertIn(OBJECT_LINE, out + err)
        self.assertIn(RESOURCE_LINE, out + err)

    def test_encoding_utf16_be_with_bom_is_still_reported(self) -> None:
        text = CLEAN_LOG + OBJECT_LINE + "\n"
        code, out, err = self.run_on(self.write(b"\xfe\xff" + text.encode("utf-16-be")))
        self.assertNotEqual(code, 0)
        self.assertIn(OBJECT_LINE, out + err)

    def test_encoding_clean_utf16_le_log_exits_0(self) -> None:
        code, out, err = self.run_on(self.write(b"\xff\xfe" + CLEAN_LOG.encode("utf-16-le")))
        self.assertEqual(code, 0)
        self.assertEqual(out + err, "")

    def test_encoding_utf8_with_bom_is_still_reported(self) -> None:
        text = OBJECT_LINE + "\n" + CLEAN_LOG
        code, out, err = self.run_on(self.write(b"\xef\xbb\xbf" + text.encode("utf-8")))
        self.assertNotEqual(code, 0)
        self.assertIn(OBJECT_LINE, out + err)

    def test_encoding_crlf_line_endings_are_still_reported(self) -> None:
        text = (CLEAN_LOG + OBJECT_LINE + "\n" + RESOURCE_LINE + "\n").replace("\n", "\r\n")
        code, out, err = self.run_on(self.write(text.encode("utf-8")))
        self.assertNotEqual(code, 0)
        self.assertIn(OBJECT_LINE, out + err)
        self.assertIn(RESOURCE_LINE, out + err)

    def test_encoding_crlf_clean_log_exits_0(self) -> None:
        code, out, err = self.run_on(self.write(CLEAN_LOG.replace("\n", "\r\n").encode("utf-8")))
        self.assertEqual(code, 0)
        self.assertEqual(out + err, "")

    def test_encoding_stray_invalid_bytes_do_not_crash_or_hide_a_leak(self) -> None:
        data = b"caf\xe9 \xff\xfe broken\n" + OBJECT_LINE.encode("utf-8") + b"\n"
        code, out, err = self.run_on(self.write(data))
        self.assertNotEqual(code, 0)
        self.assertIn(OBJECT_LINE, out + err)

    def test_encoding_utf16_without_bom_is_never_a_pass(self) -> None:
        data = (CLEAN_LOG + OBJECT_LINE + "\n").encode("utf-16-le")
        path = self.write(data)
        code, out, err = self.run_on(path)
        self.assertNotEqual(code, 0)
        self.assertIn(str(path), out + err)

    def test_encoding_clean_utf16_without_bom_is_never_a_pass(self) -> None:
        code, _, _ = self.run_on(self.write(CLEAN_LOG.encode("utf-16-le")))
        self.assertNotEqual(code, 0)

    # Usage

    def test_usage_no_argument_fails(self) -> None:
        code, _, _ = self.run_gate([])
        self.assertNotEqual(code, 0)

    def test_usage_two_arguments_fail(self) -> None:
        first = self.write(CLEAN_LOG, "one.log")
        second = self.write(CLEAN_LOG, "two.log")
        code, _, _ = self.run_gate([str(first), str(second)])
        self.assertNotEqual(code, 0)


if __name__ == "__main__":
    unittest.main()
