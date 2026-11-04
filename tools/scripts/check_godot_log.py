"""Fail a CI step when the Godot output holds output nobody explained.

The engine exits 0 on many problems (leaks at exit, script errors, missing resources), so this
gate scans the captured output of a step. This module is the one home of every pattern, the
step rules and the allowlist.

Rules, per cleaned line (colour codes removed, trailing whitespace removed):
- A leak line (LEAK_PATTERNS, case-sensitive substring, any prefix, any count) is a finding in
  every step, also inside a test case.
- An engine line is a line with an error or warning token followed by a colon, at the start of
  the line or after whitespace. It is a finding unless the step rule excuses it.
- A line that matches nothing (bare parsing messages, backtrace lines) is ignored.
- A finding whose line contains the substring of an ALLOWLIST entry is dropped.

Steps (see RULES):
- import-first: the first import of a fresh checkout. The pinned set of 10 known lines
  (FIRST_IMPORT_PINNED, owner decision on #93) is excused, up to its counts.
- import, export, smoke: every engine line is a finding.
- test: engine lines inside a test case window are owned by GdUnit4 and not flagged. A window
  opens at the STARTED line of a test and closes at the end line of the same test. A window
  that never closes is a finding and excuses nothing.

A UTF-16 BOM (Windows PowerShell 5.1 Tee-Object) and a UTF-8 BOM are decoded. Other bytes
decode as UTF-8 and stray invalid bytes are replaced. A log that cannot be checked never passes.

Exit codes: 0 no finding (prints nothing), 1 findings (printed to stderr), 2 cannot check (log
missing, empty or unreadable, or an invalid allowlist entry).

Usage: python tools/scripts/check_godot_log.py --step <step> <logfile>

See docs/dev-setup.md, "Engine output gate (test runs and leaks)".
"""

from __future__ import annotations

import argparse
import codecs
import re
import sys
from dataclasses import dataclass
from pathlib import Path

# Verified against Godot 4.7.2 (develop CI run 41866332449, 8eefb63). Recheck after an upgrade.
LEAK_PATTERNS: tuple[str, ...] = (
    "ObjectDB instances were leaked",
    "resources still in use at exit",
)

ENGINE_TOKENS: tuple[str, ...] = ("SCRIPT ERROR", "ERROR", "WARNING")

# Any prefix ("godot_console : ", indentation); the token must be followed by a colon.
ENGINE_LINE: re.Pattern[str] = re.compile(r"(?:^|\s)(?:" + "|".join(ENGINE_TOKENS) + r"):")

# CSI sequences (colours, styles, cursor moves, clear screen) are removed before any match.
ANSI_ESCAPE: re.Pattern[str] = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")

# Verified against GdUnit4 6.2.2 on Godot 4.7.2 (run 41866332449: 796 STARTED, 796 end lines).
# After ANSI stripping there can be no space before the status (cursor move), hence \s*.
TEST_STARTED: re.Pattern[str] = re.compile(
    r"^\s*(?P<suite>res://\S+?\.gd) > (?P<test>\S.*?)\s*STARTED$"
)
TEST_ENDED: re.Pattern[str] = re.compile(
    r"^\s*(?P<suite>res://\S+?\.gd) > (?P<test>\S.*?)\s*"
    r"(?:PASSED|FAILED(?: \(retry \d+\))?|SKIPPED|FLAKY \(\d+ retries\)|WARNING|ERROR)"
    r"\s+\d+(?:h|min|s|ms)(?: \d+(?:min|s|ms))*$"
)

ISSUE_LINK: re.Pattern[str] = re.compile(
    r"^https://github\.com/PeterSallai90/cozy-aquarium/issues/\d+$"
)


@dataclass(frozen=True)
class PinnedLine:
    shape: re.Pattern[str]
    max_count: int


def _pinned(body: str, max_count: int) -> PinnedLine:
    return PinnedLine(re.compile(r"(?:^|\s)ERROR: " + body + r"$"), max_count)


_HASH = r"[0-9a-f]{32}"
_FONT = r"(?:nunito_variable|noto_sans_variable)"
_FONT_PATH = r"(?:nunito/nunito_variable|noto_sans/noto_sans_variable)"
_THEME = r"res://ui/theme/cozy_theme\.tres"

# The first import of a fresh checkout prints these 10 lines (theme and font import order).
# Verified against CI runs 41735099347 (3220097) and 41866332449 (8eefb63), both jobs, identical
# 10 lines. Owner decision on #93: the set may not grow without an owner OK. Missing lines pass.
FIRST_IMPORT_PINNED: tuple[PinnedLine, ...] = (
    _pinned(rf"Cannot open file 'res://\.godot/imported/{_FONT}\.ttf-{_HASH}\.fontdata'\.", 2),
    _pinned(
        rf"Failed loading resource: res://\.godot/imported/{_FONT}\.ttf-{_HASH}\.fontdata\.", 2
    ),
    _pinned(rf"Failed loading resource: res://assets/fonts/{_FONT_PATH}\.ttf\.", 2),
    _pinned(
        rf"{_THEME}:7 - Parse Error: \[ext_resource\] referenced non-existent resource at: "
        r"res://assets/fonts/noto_sans/noto_sans_variable\.ttf\.",
        2,
    ),
    _pinned(rf"Failed loading resource: {_THEME}\.", 1),
    _pinned(rf"Error loading custom project theme '{_THEME}'", 1),
)


@dataclass(frozen=True)
class AllowEntry:
    substring: str  # literal, case-sensitive, not a regex
    reason: str
    issue: str  # https://github.com/PeterSallai90/cozy-aquarium/issues/<n>


# Adding an entry needs the owner's OK. Each entry needs a reason and an issue link.
ALLOWLIST: tuple[AllowEntry, ...] = ()


@dataclass(frozen=True)
class StepRule:
    engine_scope: str  # "everywhere" | "outside_test_windows"
    pinned: tuple[PinnedLine, ...] = ()


GENERIC = StepRule("everywhere")
RULES: dict[str, StepRule] = {
    "import-first": StepRule("everywhere", FIRST_IMPORT_PINNED),
    "import": GENERIC,
    "test": StepRule("outside_test_windows"),
    "export": GENERIC,
    "smoke": GENERIC,  # registered for #94; same rule as import and export
}


class LogError(Exception):
    """The log cannot be checked."""


def validate_allowlist(entries: tuple[AllowEntry, ...]) -> list[str]:
    """Return the problems of the entries; each is prefixed with the entry index."""
    problems: list[str] = []
    token_texts = [token + ":" for token in ENGINE_TOKENS]
    for index, entry in enumerate(entries):
        if not entry.substring.strip():
            problems.append(f"{index}: substring is empty")
        elif any(entry.substring in text for text in token_texts):
            problems.append(f"{index}: substring matches every engine line")
        if not entry.reason.strip():
            problems.append(f"{index}: reason is empty")
        if not ISSUE_LINK.match(entry.issue):
            problems.append(f"{index}: issue is not a link to an issue of this repository")
    return problems


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


def clean(line: str) -> str:
    return ANSI_ESCAPE.sub("", line).rstrip()


def scan(text: str, step: str, allowlist: tuple[AllowEntry, ...] | None = None) -> list[str]:
    """Return the finding texts in log order."""
    entries = ALLOWLIST if allowlist is None else allowlist
    rule = RULES[step]
    findings: list[tuple[int, str]] = []
    counts: list[int] = [0] * len(rule.pinned)
    window: tuple[str, str] | None = None
    window_start: tuple[int, str] = (0, "")
    held: list[tuple[int, str]] = []

    def flush_unterminated() -> None:
        findings.append((window_start[0], f"unterminated test window: {window_start[1]}"))
        findings.extend(held)

    for index, raw in enumerate(text.splitlines()):
        line = clean(raw)
        if any(pattern in line for pattern in LEAK_PATTERNS):
            findings.append((index, line))
            continue
        if rule.engine_scope == "outside_test_windows":
            started = TEST_STARTED.match(line)
            if started:
                if window is not None:
                    flush_unterminated()
                window = (started["suite"], started["test"])
                window_start = (index, line)
                held = []
                continue
            ended = TEST_ENDED.match(line)
            if ended:
                if window is not None and (ended["suite"], ended["test"]) != window:
                    flush_unterminated()
                window = None
                held = []
                continue
        if not ENGINE_LINE.search(line):
            continue
        used = False
        for position, pinned in enumerate(rule.pinned):
            if counts[position] < pinned.max_count and pinned.shape.search(line):
                counts[position] += 1
                used = True
                break
        if used:
            continue
        if window is not None:
            held.append((index, line))
        else:
            findings.append((index, line))
    if window is not None:
        flush_unterminated()
    findings.sort(key=lambda item: item[0])
    return [
        text_line
        for _, text_line in findings
        if not any(entry.substring in text_line for entry in entries)
    ]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Fail a CI step on unexplained engine output.")
    parser.add_argument(
        "--step", required=True, choices=sorted(RULES), help="the step that made the log"
    )
    parser.add_argument("logfile", type=Path, help="captured output of the step")
    args = parser.parse_args(argv)
    step: str = args.step
    path: Path = args.logfile
    if hasattr(sys.stderr, "reconfigure"):
        sys.stderr.reconfigure(errors="backslashreplace")
    prefix = f"Engine log gate [{step}]:"
    problems = validate_allowlist(ALLOWLIST)
    if problems:
        for problem in problems:
            print(f"{prefix} invalid allowlist entry {problem}", file=sys.stderr)
        return 2
    try:
        findings = scan(read_log(path), step)
    except LogError as error:
        print(f"{prefix} cannot check {path}: {error}", file=sys.stderr)
        return 2
    if not findings:
        return 0
    for finding in findings:
        print(f"{prefix} {finding}", file=sys.stderr)
    print(f"{prefix} {len(findings)} finding(s) in {path}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
