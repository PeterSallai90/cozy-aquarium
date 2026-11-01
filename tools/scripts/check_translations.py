"""Check the translation files of the game (no Godot needed).

The text home of the key convention is docs/architecture.md (Language handling). The constants
below are the code home of the same rules; tools/scripts/generate_pot.py imports them.

Checks, each an ERROR line (with path:line where there is one); any error means exit code 1:
1. game/localization/messages.pot exists (en.po and hu.po too).
2. messages.pot, en.po, hu.po and extra_keys.txt are strict UTF-8 without BOM and without CR.
3. No parse errors, no duplicate msgid within a file, no msgctxt.
4. Every pot key follows the key convention; a plural entry has msgid_plural == key + ".plural".
5. Each .po has the right Language, Plural-Forms and Content-Type headers, and no fuzzy header.
6. Every pot key is in every .po, as the same kind (singular or plural), with non-empty text,
   not fuzzy; en.po never holds an identity entry (msgstr == msgid).
7. A .po key that is not in messages.pot is stale.
8. messages.pot is byte-identical to what generate_pot.py would write now.

Usage: python tools/scripts/check_translations.py [--root REPO_ROOT]
"""

from __future__ import annotations

import argparse
import ast
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

LOCALIZATION_DIR = Path("game/localization")
TEMPLATE_FILE = "messages.pot"
LANGUAGE_FILES = ("en.po", "hu.po")
EXTRA_KEYS_FILE = "extra_keys.txt"

# The one code home of the key convention (docs/architecture.md, Language handling, has the text).
ALLOWED_AREAS: tuple[str, ...] = (
    "menu",
    "save",
    "settings",
    "language",
    "tank",
    "fish",
    "item",
    "ui",
    "photo",
    "datetime",
    "number",
    "unit",
)
KEY_PATTERN = re.compile(r"[a-z0-9_]+(?:\.[a-z0-9_]+)+\Z")
PLURAL_SUFFIX = ".plural"
PLURAL_FORMS = "nplurals=2; plural=(n != 1);"
UTF8_BOM = b"\xef\xbb\xbf"


def key_error(key: str) -> str | None:
    """Return why `key` breaks the convention, or None when it is valid."""
    if not KEY_PATTERN.match(key):
        return "must be lower case, dot separated, with at least two segments of a-z 0-9 _"
    segments = key.split(".")
    if segments[0] not in ALLOWED_AREAS:
        return f"unknown area '{segments[0]}' (allowed: {', '.join(ALLOWED_AREAS)})"
    if segments[-1] == "plural":
        return "the last segment 'plural' is reserved for the msgid_plural of a key"
    return None


@dataclass
class Entry:
    """One gettext entry. `fields` maps msgctxt, msgid, msgid_plural, msgstr, msgstr[n] to text."""

    line: int
    flags: list[str] = field(default_factory=list)
    fields: dict[str, str] = field(default_factory=dict)

    @property
    def msgid(self) -> str | None:
        return self.fields.get("msgid")

    @property
    def msgid_plural(self) -> str | None:
        return self.fields.get("msgid_plural")

    @property
    def is_plural(self) -> bool:
        return "msgid_plural" in self.fields or "msgstr[0]" in self.fields

    @property
    def plural_forms(self) -> list[str]:
        return sorted(name for name in self.fields if name.startswith("msgstr["))


def _unquote(text: str) -> str:
    """Decode one quoted gettext string, including C-style escapes."""
    value = ast.literal_eval(text)
    if not isinstance(value, str):
        raise ValueError(f"not a string literal: {text}")
    return value


def parse_po(text: str, label: str, errors: list[str]) -> list[Entry]:
    """Parse gettext text into entries. Obsolete "#~" entries are ignored."""
    entries: list[Entry] = []
    current: Entry | None = None
    field_name: str | None = None

    def flush() -> None:
        nonlocal current, field_name
        if current is not None:
            entries.append(current)
        current = None
        field_name = None

    for number, raw in enumerate(text.split("\n"), start=1):
        line = raw.strip()
        if not line or line.startswith("#~"):
            flush()
            continue
        if line.startswith("#"):
            if line.startswith("#,"):
                if current is None:
                    current = Entry(number)
                current.flags.extend(flag.strip() for flag in line[2:].split(","))
            field_name = None
            continue
        try:
            if line.startswith('"'):
                if current is None or field_name is None:
                    raise ValueError("string continuation without a field")
                current.fields[field_name] += _unquote(line)
                continue
            keyword, _, rest = line.partition(" ")
            if current is None:
                current = Entry(number)
            if keyword == "msgid" and "msgid" in current.fields:
                flush()
                current = Entry(number)
            if keyword not in ("msgctxt", "msgid", "msgid_plural") and not keyword.startswith(
                "msgstr"
            ):
                raise ValueError(f"unknown keyword '{keyword}'")
            current.fields[keyword] = _unquote(rest)
            field_name = keyword
        except (ValueError, SyntaxError) as error:
            errors.append(f"ERROR: {label}:{number}: {error}")
            field_name = None
    flush()
    return entries


def _header_values(header: Entry | None) -> dict[str, str]:
    values: dict[str, str] = {}
    if header is None:
        return values
    for line in header.fields.get("msgstr", "").split("\n"):
        name, separator, value = line.partition(":")
        if separator:
            values[name.strip()] = value.strip()
    return values


def _split_header(entries: list[Entry]) -> tuple[Entry | None, dict[str, list[Entry]]]:
    """Return the header entry and the other entries grouped by msgid (msgctxt entries skipped)."""
    header: Entry | None = None
    body: dict[str, list[Entry]] = {}
    for entry in entries:
        if entry.msgid == "":
            header = entry
        elif entry.msgid is not None and "msgctxt" not in entry.fields:
            body.setdefault(entry.msgid, []).append(entry)
    return header, body


def _read_text(path: Path, label: str, errors: list[str]) -> str | None:
    """Read a text file strictly: UTF-8, no BOM, no CR. Reports and returns None on a violation."""
    data = path.read_bytes()
    if data.startswith(UTF8_BOM):
        errors.append(f"ERROR: {label} must be UTF-8 without BOM.")
    elif b"\r" in data:
        errors.append(f"ERROR: {label} must use LF line endings, found CR.")
    else:
        try:
            return data.decode("utf-8")
        except UnicodeDecodeError:
            errors.append(f"ERROR: {label} is not valid UTF-8.")
    return None


def _check_template(
    entries: list[Entry], label: str, errors: list[str]
) -> dict[str, str | None]:
    """Check the pot and return its keys as msgid -> msgid_plural or None."""
    for entry in entries:
        if "msgctxt" in entry.fields:
            errors.append(f"ERROR: {label}:{entry.line}: msgctxt is not allowed")
    _, body = _split_header(entries)
    keys: dict[str, str | None] = {}
    for key, found in body.items():
        entry = found[0]
        if len(found) > 1:
            errors.append(f"ERROR: {label}:{entry.line}: duplicate key {key}")
        reason = key_error(key)
        if reason:
            errors.append(f"ERROR: {label}:{entry.line}: bad key {key}: {reason}")
        if entry.msgid_plural is not None and entry.msgid_plural != key + PLURAL_SUFFIX:
            errors.append(
                f"ERROR: {label}:{entry.line}: {key}: msgid_plural must be '{key}{PLURAL_SUFFIX}'"
            )
        keys[key] = entry.msgid_plural
    return keys


def _check_header(header: Entry | None, language: str, label: str, errors: list[str]) -> None:
    if header is None:
        errors.append(f"ERROR: {label}: missing header entry")
        return
    values = _header_values(header)
    if values.get("Language") != language:
        errors.append(f"ERROR: {label}:{header.line}: Language header must be '{language}'")
    if values.get("Plural-Forms") != PLURAL_FORMS:
        errors.append(f"ERROR: {label}:{header.line}: Plural-Forms header must be '{PLURAL_FORMS}'")
    if "charset=UTF-8" not in values.get("Content-Type", ""):
        errors.append(f"ERROR: {label}:{header.line}: Content-Type must declare charset=UTF-8")
    if "fuzzy" in header.flags:
        errors.append(f"ERROR: {label}:{header.line}: the header is flagged fuzzy")


def _check_entry(
    entry: Entry, key: str, plural: str | None, language: str, label: str, errors: list[str]
) -> None:
    where = f"{label}:{entry.line}: {key}"
    if "fuzzy" in entry.flags:
        errors.append(f"ERROR: {where}: flagged fuzzy (Godot ignores it)")
    if plural is None:
        if entry.is_plural:
            errors.append(f"ERROR: {where}: is plural here but singular in messages.pot")
        elif not entry.fields.get("msgstr", "").strip():
            errors.append(f"ERROR: {where}: empty msgstr")
        elif language == "en" and entry.fields["msgstr"] == key:
            errors.append(f"ERROR: {where}: identity entry (msgstr equals the key)")
        return
    if entry.msgid_plural != plural or "msgstr" in entry.fields:
        errors.append(f"ERROR: {where}: must be a plural entry with msgid_plural '{plural}'")
    forms = entry.plural_forms
    if forms != ["msgstr[0]", "msgstr[1]"]:
        errors.append(f"ERROR: {where}: needs exactly msgstr[0] and msgstr[1]")
    elif any(not entry.fields[form].strip() for form in forms):
        errors.append(f"ERROR: {where}: empty plural form")


def _check_language_file(
    entries: list[Entry], language: str, label: str, keys: dict[str, str | None], errors: list[str]
) -> None:
    header, body = _split_header(entries)
    for entry in entries:
        if "msgctxt" in entry.fields:
            errors.append(f"ERROR: {label}:{entry.line}: msgctxt is not allowed")
    _check_header(header, language, label, errors)
    for key, found in body.items():
        if len(found) > 1:
            errors.append(f"ERROR: {label}:{found[0].line}: duplicate key {key}")
        if key not in keys:
            errors.append(f"ERROR: {label}:{found[0].line}: stale key {key} (not in messages.pot)")
    for key, plural in keys.items():
        if key not in body:
            errors.append(f"ERROR: {label}: missing key {key}")
        else:
            _check_entry(body[key][0], key, plural, language, label, errors)


def check(root: Path) -> int:
    """Run every check under `root`. Returns the exit code."""
    import generate_pot  # imported here: generate_pot imports this module's constants

    directory = root / LOCALIZATION_DIR
    template = directory / TEMPLATE_FILE
    if not template.is_file():
        print(f"ERROR: {template.relative_to(root).as_posix()} is missing; generate it.")
        return 1
    errors: list[str] = []
    texts: dict[str, str] = {}
    paths = [template, *(directory / name for name in LANGUAGE_FILES), directory / EXTRA_KEYS_FILE]
    for path in paths:
        label = path.relative_to(root).as_posix()
        if not path.is_file():
            if path.name != EXTRA_KEYS_FILE:
                errors.append(f"ERROR: {label} is missing.")
            continue
        text = _read_text(path, label, errors)
        if text is not None:
            texts[path.name] = text

    keys: dict[str, str | None] = {}
    if TEMPLATE_FILE in texts:
        label = template.relative_to(root).as_posix()
        keys = _check_template(parse_po(texts[TEMPLATE_FILE], label, errors), label, errors)
    for name in LANGUAGE_FILES:
        if name in texts:
            label = (directory / name).relative_to(root).as_posix()
            entries = parse_po(texts[name], label, errors)
            _check_language_file(entries, name.removesuffix(".po"), label, keys, errors)

    collected, source_errors = generate_pot.collect(root)
    errors.extend(f"ERROR: {message}" for message in source_errors)
    if not source_errors and TEMPLATE_FILE in texts:
        if generate_pot.render_pot(collected).encode("utf-8") != template.read_bytes():
            label = template.relative_to(root).as_posix()
            errors.append(
                f"ERROR: {label} is out of date; run python tools/scripts/generate_pot.py"
            )

    if errors:
        print("\n".join(errors))
        return 1
    print(f"All {len(keys)} key(s) are present in en.po, hu.po; messages.pot is up to date.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    return check(parser.parse_args().root.resolve())


if __name__ == "__main__":
    sys.exit(main())
