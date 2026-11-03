"""Fail if game/project.godot lost a setting that must stay written explicitly.

The Godot editor removes settings whose values equal Godot's defaults when it saves the project.
Two lines must stay in game/project.godot anyway (see docs/dev-setup.md):
- [rendering] renderer/rendering_method="forward_plus" (pins decision D6, Forward+)
- [internationalization] locale/fallback="en" (required by #18)

Rules:
- Lines are read like Godot's ConfigFile: key="x" and key = "x" are the same, CRLF and a UTF-8 BOM
  are accepted, and when a key appears twice the last one wins.
- Multi-line values (input actions, dictionaries) are skipped as a whole, so a continuation line
  is never mistaken for a section header or a setting.

Exit codes: 0 all required lines present (prints nothing), 1 one or more problems (one stderr
line each: <path>: [<section>] <key>: <problem>; expected line: <key>="<value>"), 2 the file is
missing or unreadable.

Usage: python tools/scripts/check_project_settings.py [--root REPO_ROOT]
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path

PROJECT_FILE = Path("game/project.godot")

_SECTION_RE = re.compile(r"^\[([^\]]+)\]\s*$")
_SETTING_RE = re.compile(r"^([A-Za-z0-9_][A-Za-z0-9_/.\-]*)\s*=\s*(.*)$")


@dataclass(frozen=True)
class RequiredSetting:
    section: str
    key: str
    value: str

    @property
    def line(self) -> str:
        return f'{self.key}="{self.value}"'


# Single source of truth for the required lines. The GdUnit constants in
# game/tests/test_project_settings.gd and game/tests/systems/localization/test_localization_setup.gd
# and docs/dev-setup.md mirror this list.
REQUIRED_SETTINGS: tuple[RequiredSetting, ...] = (
    RequiredSetting("rendering", "renderer/rendering_method", "forward_plus"),
    RequiredSetting("internationalization", "locale/fallback", "en"),
)


@dataclass
class ParsedProject:
    sections: set[str]
    values: dict[tuple[str, str], str]


def read_text(path: Path) -> str:
    return path.read_bytes().decode("utf-8-sig")


def _scan_value(text: str, depth: int, in_string: bool) -> tuple[int, bool]:
    """Track bracket depth and string state across the characters of one line."""
    escaped = False
    for char in text:
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
        elif char == '"':
            in_string = True
        elif char in "{[(":
            depth += 1
        elif char in "}])":
            depth = max(depth - 1, 0)
    return depth, in_string


def parse(text: str) -> ParsedProject:
    sections: set[str] = set()
    values: dict[tuple[str, str], str] = {}
    section = ""
    depth = 0
    in_string = False
    for line in text.splitlines():
        if depth > 0 or in_string:
            depth, in_string = _scan_value(line, depth, in_string)
            continue
        stripped = line.strip()
        if not stripped or stripped.startswith((";", "#")):
            continue
        header = _SECTION_RE.match(stripped)
        if header:
            section = header.group(1)
            sections.add(section)
            continue
        setting = _SETTING_RE.match(stripped)
        if setting:
            value = setting.group(2).strip()
            values[(section, setting.group(1))] = value
            depth, in_string = _scan_value(value, 0, False)
    return ParsedProject(sections, values)


def problems(parsed: ParsedProject, path: str) -> list[str]:
    found: list[str] = []
    for setting in REQUIRED_SETTINGS:
        expected = f'"{setting.value}"'
        actual = parsed.values.get((setting.section, setting.key))
        problem: str | None = None
        if actual is None:
            others = sorted(section for (section, key) in parsed.values if key == setting.key)
            if setting.section not in parsed.sections:
                problem = "section missing"
            elif others:
                problem = f"found under [{others[0]}] instead"
            else:
                problem = "line missing"
        elif actual != expected:
            problem = f"value is {actual}"
        if problem is not None:
            found.append(
                f"{path}: [{setting.section}] {setting.key}: {problem}; "
                f"expected line: {setting.line}"
            )
    return found


def check(root: Path) -> int:
    path = root / PROJECT_FILE
    shown = PROJECT_FILE.as_posix()
    try:
        text = read_text(path)
    except FileNotFoundError:
        print(f"{shown}: cannot read file: file not found", file=sys.stderr)
        return 2
    except (OSError, UnicodeDecodeError) as error:
        print(f"{shown}: cannot read file: {error}", file=sys.stderr)
        return 2
    found = problems(parse(text), shown)
    for message in found:
        print(message, file=sys.stderr)
    return 1 if found else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=(__doc__ or "").splitlines()[0])
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parents[2],
        help="repository root (default: derived from this script's location)",
    )
    return check(parser.parse_args().root)


if __name__ == "__main__":
    sys.exit(main())
