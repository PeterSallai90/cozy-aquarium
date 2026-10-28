"""Fail if any translation key in messages.pot is missing from en.po or hu.po.

Keys are gettext msgids (plus msgctxt when present). The check passes with a notice while
game/localization/messages.pot does not exist yet.

Usage: python tools/scripts/check_translations.py [--root REPO_ROOT]
"""

from __future__ import annotations

import argparse
import ast
import sys
from pathlib import Path

LOCALIZATION_DIR = Path("game/localization")
TEMPLATE_FILE = "messages.pot"
LANGUAGE_FILES = ("en.po", "hu.po")

Key = tuple[str, str]  # (msgctxt, msgid)


def _unquote(text: str) -> str:
    """Decode one quoted gettext string, including C-style escapes."""
    value = ast.literal_eval(text)
    if not isinstance(value, str):
        raise ValueError(f"not a string literal: {text}")
    return value


def parse_keys(path: Path) -> set[Key]:
    """Return the (msgctxt, msgid) keys of every non-obsolete entry, skipping the header."""
    keys: set[Key] = set()
    fields: dict[str, str] = {}
    current: str | None = None

    def flush() -> None:
        msgid = fields.get("msgid")
        if msgid:
            keys.add((fields.get("msgctxt", ""), msgid))
        fields.clear()

    for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw.strip()
        if not line or line.startswith("#"):
            # Blank lines and comments (including obsolete "#~" entries) end the field in progress.
            current = None
            continue
        try:
            if line.startswith('"'):
                if current is None:
                    raise ValueError("continuation line without a keyword")
                value = _unquote(line)
                if current in fields:
                    fields[current] += value
                continue
            keyword, _, rest = line.partition(" ")
            if keyword in ("msgctxt", "msgid"):
                if keyword in fields or (keyword == "msgctxt" and "msgid" in fields):
                    flush()
                fields[keyword] = _unquote(rest)
                current = keyword
            elif keyword == "msgid_plural" or keyword.startswith("msgstr"):
                current = keyword  # translations and plurals are not part of the key
                _unquote(rest)
            else:
                raise ValueError(f"unknown keyword '{keyword}'")
        except (ValueError, SyntaxError) as error:
            raise ValueError(f"{path}:{line_number}: {error}") from error
    flush()
    return keys


def format_key(key: Key) -> str:
    context, msgid = key
    return f"{msgid} (context: {context})" if context else msgid


def check(root: Path) -> int:
    localization = root / LOCALIZATION_DIR
    template = localization / TEMPLATE_FILE
    if not template.is_file():
        print(f"{template.relative_to(root).as_posix()} not found; nothing to check.")
        return 0

    try:
        expected = parse_keys(template)
    except ValueError as error:
        print(f"ERROR: {error}")
        return 1

    failed = False
    for name in LANGUAGE_FILES:
        po_file = localization / name
        relative = po_file.relative_to(root).as_posix()
        if not po_file.is_file():
            print(f"ERROR: {relative} is missing.")
            failed = True
            continue
        try:
            missing = sorted(expected - parse_keys(po_file))
        except ValueError as error:
            print(f"ERROR: {error}")
            failed = True
            continue
        if missing:
            failed = True
            print(f"ERROR: {relative} is missing {len(missing)} key(s):")
            for key in missing:
                print(f"  {format_key(key)}")

    if failed:
        return 1
    print(f"All {len(expected)} key(s) are present in {', '.join(LANGUAGE_FILES)}.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parents[2],
        help="repository root (default: derived from this script's location)",
    )
    args = parser.parse_args()
    return check(args.root.resolve())


if __name__ == "__main__":
    sys.exit(main())
