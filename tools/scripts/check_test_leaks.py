"""Fail if a headless test run reported leaked objects or resources at exit.

Godot prints two lines at shutdown when objects or resources are still alive. The run still
exits 0, so nothing else notices. This script scans the captured output of the test run.

Rules:
- The log is scanned line by line. A line is a leak line when it contains one of LEAK_PATTERNS
  as a case-sensitive substring. Any prefix is fine (for example "WARNING: " or the
  "godot_console : " that PowerShell adds). The counts in the line are ignored.
- A UTF-16 BOM (Windows PowerShell 5.1 Tee-Object) and a UTF-8 BOM are decoded. Other bytes
  decode as UTF-8, and stray invalid bytes are replaced instead of raising.
- A log that cannot be checked (missing, unreadable, empty, or UTF-16 without a BOM) never
  passes.

Exit codes: 0 no leak line (prints nothing), 1 one or more leak lines (printed to stderr),
2 the log is missing, empty or unreadable.

Usage: python tools/scripts/check_test_leaks.py <logfile>

See docs/dev-setup.md, "Test runs and leaks".
"""

from __future__ import annotations

import argparse
import codecs
import sys
from pathlib import Path

# Verified against Godot 4.7.2 (develop run 41735099347). Recheck both after a Godot upgrade.
LEAK_PATTERNS: tuple[str, ...] = (
    "ObjectDB instances were leaked",
    "resources still in use at exit",
)


class LogError(Exception):
    """The log cannot be checked."""


def read_log(path: Path) -> str:
    try:
        data = path.read_bytes()
    except FileNotFoundError:
        raise LogError("file not found") from None
    except OSError as error:
        raise LogError(f"unreadable ({error.strerror or error})") from None
    if data.startswith((codecs.BOM_UTF16_LE, codecs.BOM_UTF16_BE)):
        text = data.decode("utf-16", errors="replace")
    elif data.startswith(codecs.BOM_UTF8):
        text = data[len(codecs.BOM_UTF8) :].decode("utf-8", errors="replace")
    else:
        text = data.decode("utf-8", errors="replace")
    if "\x00" in text:
        raise LogError("unreadable or unknown encoding (NUL bytes, UTF-16 without a BOM?)")
    if not text.strip():
        raise LogError("file is empty")
    return text


def find_leak_lines(text: str) -> list[str]:
    return [
        line.rstrip()
        for line in text.splitlines()
        if any(pattern in line for pattern in LEAK_PATTERNS)
    ]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Fail when a test run log reports a leak.")
    parser.add_argument("logfile", type=Path, help="captured output of the test run")
    args = parser.parse_args(argv)
    path: Path = args.logfile
    try:
        lines = find_leak_lines(read_log(path))
    except LogError as error:
        print(f"Leak gate: cannot check {path}: {error}", file=sys.stderr)
        return 2
    if not lines:
        return 0
    print(f"Leak gate: {len(lines)} leak line(s) in {path}:", file=sys.stderr)
    for line in lines:
        print(line, file=sys.stderr)
    print('See docs/dev-setup.md, "Test runs and leaks".', file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
