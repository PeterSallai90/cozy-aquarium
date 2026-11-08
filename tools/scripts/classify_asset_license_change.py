#!/usr/bin/env python3
"""Decide whether a change to docs/asset-licenses.md may skip the owner gate (issue #122).

Only a change made purely of exempt rows is exempt: rows of own-project data files (generated
in-house or hand-written, no third-party input). Everything else, including every edit outside
single table rows, is a gate verdict and the workflow adds needs:owner. Anything the script cannot
classify is a gate verdict too (fail safe).

All file content is read as git data (`git show REV:path`); nothing from the pull request is
checked out, imported or executed. Standard library only, and self-contained on purpose: it does
not import check_asset_licenses.py.

Usage: python tools/scripts/classify_asset_license_change.py --repo REPO --old REV --new REV

Exit codes:
  0  prints "RESULT: unchanged" or "RESULT: exempt"
  1  prints one "GATE: <reason>" line per finding, then "RESULT: gate"
  2  prints "ERROR: <message>", then "RESULT: error" (bad arguments, git failure, any exception)

Rules R1 to R9 are described in the technical plan of issue #122 and in docs/asset-licenses.md.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from collections import Counter
from collections.abc import Callable
from dataclasses import dataclass, field
from typing import NoReturn

LOG_PATH = "docs/asset-licenses.md"
HEADER = "| File | Source | Author | License | Link | Added |"
SEPARATOR = "| --- | --- | --- | --- | --- | --- |"
AUTHOR = "Cozy Aquarium (AI, this project)"
LICENSE = "MIT (this project)"
GENERATED_RE = re.compile(r"Generated in-house by `(tools/[A-Za-z0-9_./-]+)`")
HAND_WRITTEN_PREFIX = "Hand-written in this project"
LINK_RE = re.compile(r"https://github\.com/PeterSallai90/cozy-aquarium/(issues|pull)/[0-9]+")
ADDED_RE = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}")
FILE_CELL_RE = re.compile(r"`([^`]+)`")
ASSET_PATH_RE = re.compile(r"assets/[A-Za-z0-9_./-]+")
DATA_EXTENSIONS = (".glb", ".png", ".ogg", ".wav", ".mp3")
SOURCE_MARKERS = (
    "://",
    "www.",
    "licen",
    "copyright",
    "©",
    "cc0",
    "cc-by",
    "cc by",
    "third-party",
    "third party",
    "upstream",
    "kenney",
    "freesound",
    "poly haven",
    "polyhaven",
    "ambientcg",
    "sketchfab",
    "opengameart",
    "itch.io",
    "quaternius",
)
MATERIAL_TYPES = ("StandardMaterial3D", "ORMMaterial3D")
TEXTURE_TYPES = ("Texture2D", "CompressedTexture2D")
TRES_FORBIDDEN = ("script", "shader", '.gd"', ".gdshader")
KEY_VALUE_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_/]* = .+")
RES_REF_RE = re.compile(r"res://[^\"'\s,\]\)]+")
SAFE_REF_RE = re.compile(r"[A-Za-z0-9_./-]+")
TEXTURE_EXT_RE = re.compile(
    r'\[ext_resource type="(Texture2D|CompressedTexture2D)"( uid="uid://[a-z0-9]+")?'
    r' path="res://assets/[A-Za-z0-9_./-]+\.png"( id="[A-Za-z0-9_]+")?\]'
)
SECTION_RE = re.compile(r"\[[a-z_]+\]")
SIDECAR_LINE_RE = re.compile(r"([A-Za-z0-9_./-]+)=(.*)")

Reader = Callable[[str], bytes | None]


@dataclass(frozen=True)
class Verdict:
    """Result of a classification: exempt, unchanged, or a gate with reasons."""

    exempt: bool
    unchanged: bool
    reasons: list[str] = field(default_factory=list)


def gate(*reasons: str) -> Verdict:
    return Verdict(False, False, list(reasons))


def is_lfs_pointer(data: bytes) -> bool:
    return data.startswith(b"version https://git-lfs.github.com/spec/")


# --- R1: table structure ---------------------------------------------------------------------


@dataclass(frozen=True)
class Table:
    pre: str
    post: str
    rows: list[str]


def split_table(text: str | None, label: str, problems: list[str]) -> Table | None:
    if text is None:
        problems.append(f"{LOG_PATH} is missing at the {label} revision")
        return None
    if "\r" in text:
        problems.append(f"{LOG_PATH} at the {label} revision contains a carriage return")
        return None
    if not text.endswith("\n"):
        problems.append(f"{LOG_PATH} at the {label} revision does not end with a newline")
        return None
    lines = text.split("\n")
    indexes = [i for i, line in enumerate(lines) if line.startswith("|")]
    if not indexes:
        problems.append(f"{LOG_PATH} at the {label} revision has no table")
        return None
    first, last = indexes[0], indexes[-1]
    if indexes != list(range(first, last + 1)):
        problems.append(f"{LOG_PATH} at the {label} revision has more than one table block")
        return None
    if last - first < 1 or lines[first] != HEADER or lines[first + 1] != SEPARATOR:
        problems.append(f"{LOG_PATH} at the {label} revision has an unexpected table header")
        return None
    return Table("\n".join(lines[:first]), "\n".join(lines[last + 1 :]), lines[first + 2 : last + 1])


def file_cell_of(line: str) -> str:
    parts = line.split("|")
    return parts[1].strip() if len(parts) > 2 else line


# --- R3: row parse ---------------------------------------------------------------------------


def parse_row(line: str) -> list[str] | None:
    if not (line.startswith("| ") and line.endswith(" |")):
        return None
    parts = line.split("|")
    if len(parts) != 8:
        return None
    cells: list[str] = []
    for part in parts[1:-1]:
        if len(part) < 3 or part[0] != " " or part[-1] != " ":
            return None
        inner = part[1:-1]
        if not inner or inner != inner.strip():
            return None
        cells.append(inner)
    return cells


# --- R6: plain material .tres ----------------------------------------------------------------


def plain_material_problem(data: bytes | None) -> str | None:
    """None when data is a plain StandardMaterial3D or ORMMaterial3D .tres, else the reason."""
    if data is None:
        return "material file is missing"
    if is_lfs_pointer(data):
        return "material file is an LFS pointer"
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return "material file is not valid UTF-8"
    lowered = text.lower()
    for word in TRES_FORBIDDEN:
        if word.lower() in lowered:
            return f"material file mentions {word!r}"
    lines = [line for line in text.split("\n") if line.strip()]
    if not lines:
        return "material file is empty"
    if not any(lines[0].startswith(f'[gd_resource type="{t}"') for t in MATERIAL_TYPES):
        return "material file is not a StandardMaterial3D or ORMMaterial3D"
    for number, line in enumerate(lines):
        if "next_pass" in line and re.fullmatch(r"next_pass = null", line) is None:
            return "material file sets next_pass"
        if line.startswith("["):
            if line.startswith("[ext_resource "):
                if TEXTURE_EXT_RE.fullmatch(line) is None:
                    return "material file has an ext_resource that is not a texture png"
                continue
            if number == 0 and line.startswith("[gd_resource "):
                pass
            elif line != "[resource]":
                return "material file has an unexpected section"
        elif KEY_VALUE_RE.fullmatch(line) is None:
            return "material file has a line that is not a section or key = value"
        if "res://" in line or "uid://" in line:
            return "material file references a resource outside its ext_resource lines"
    return None


# --- R7: import sidecar ----------------------------------------------------------------------


def bracket_depth(fragment: str) -> int:
    """Net count of opening minus closing brackets outside double-quoted strings."""
    depth = 0
    in_string = False
    escaped = False
    for char in fragment:
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
            depth -= 1
    return depth


def sidecar_problem(game_path: str, read_new: Reader) -> str | None:
    """None when the .import sidecar binds no script, shader or non-plain material.

    The sidecar is parsed strictly: only the exact format Godot writes is accepted (sections,
    unquoted keys without spaces, single-line values, no repeated keys). Anything else gates,
    because Godot's parser accepts many more spellings than it writes.
    """
    data = read_new(game_path + ".import")
    if data is None:
        return None
    if is_lfs_pointer(data):
        return "import sidecar is an LFS pointer"
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return "import sidecar is not valid UTF-8"
    values: dict[tuple[str, str], str] = {}
    section = ""
    depth = 0
    for line in text.split("\n"):
        if depth > 0:
            depth += bracket_depth(line)
            if depth < 0:
                return "import sidecar has unbalanced brackets"
            continue
        if not line:
            continue
        if SECTION_RE.fullmatch(line):
            section = line
            continue
        match = SIDECAR_LINE_RE.fullmatch(line)
        if match is None:
            return "import sidecar has a line in an unexpected format"
        key = (section, match.group(1))
        if key in values:
            return f"import sidecar repeats the key {match.group(1)}"
        values[key] = match.group(2)
        depth = bracket_depth(match.group(2))
        if depth < 0:
            return "import sidecar has unbalanced brackets"
    if depth != 0:
        return "import sidecar has unbalanced brackets"
    exact = {"nodes/root_type": '""', "nodes/root_script": "null", "import_script/path": '""'}
    for (_, name), value in values.items():
        if name in exact and value != exact[name]:
            return f"import sidecar sets {name}"
    if game_path.endswith(".glb") and ("[params]", "import_script/path") not in values:
        return "import sidecar has no empty import_script/path"
    rest = text
    for name, value in exact.items():
        rest = re.sub(rf"(?m)^{re.escape(name)}={re.escape(value)}$", "", rest)
    for word in ("root_type", "root_script", "import_script"):
        if word in rest:
            return f"import sidecar mentions {word} outside its exact line"
    if '.gd"' in text or ".gdshader" in text:
        return "import sidecar references a script or shader"
    rest = re.sub(r'(?m)^uid="uid://[^"\n]*"$', "", text)
    if "uid://" in rest:
        return "import sidecar references a resource by uid"
    own_source = "res://" + game_path[len("game/") :]
    for ref in RES_REF_RE.findall(text):
        if ".." in ref:
            return f"import sidecar has an unusual reference {ref}"
        if ref.startswith("res://.godot/imported/") or ref == own_source:
            continue
        rel = ref[len("res://") :]
        if rel.endswith(".tres") and SAFE_REF_RE.fullmatch(rel) is not None:
            problem = plain_material_problem(read_new("game/" + rel))
            if problem is not None:
                return f"import sidecar binds {ref}: {problem}"
            continue
        return f"import sidecar references {ref}"
    leftovers = re.sub(RES_REF_RE, "", rest)
    if "://" in leftovers:
        return "import sidecar uses another resource scheme"
    return None


# --- R4, R5, R8: judging one row -------------------------------------------------------------


def row_problem(line: str, *, added: bool, read: Reader, read_head: Reader) -> str | None:
    """None when the row is exempt, else the reason it gates.

    read reads at the row's revision (head for added rows, merge base for removed rows).
    """
    cells = parse_row(line)
    if cells is None:
        return "row is malformed"
    file_cell, source, author, license_, link, date = cells
    if author != AUTHOR:
        return "author is not the own-project author"
    if license_ != LICENSE:
        return "license is not the own-project license"
    generated = GENERATED_RE.match(source)
    if generated is None and not source.startswith(HAND_WRITTEN_PREFIX):
        return "source is neither generated in-house nor hand-written"
    lowered = source.lower()
    for marker in SOURCE_MARKERS:
        if marker in lowered:
            return f"source mentions {marker!r}"
    if generated is not None:
        tool = generated.group(1)
        if ".." in tool or read(tool) is None:
            return f"generator {tool} does not exist at the row's revision"
    if LINK_RE.fullmatch(link) is None:
        return "link is not an issue or pull request of this repository"
    if ADDED_RE.fullmatch(date) is None:
        return "added date is malformed"
    quoted = FILE_CELL_RE.fullmatch(file_cell)
    if quoted is None:
        return "file cell is not exactly one quoted path"
    path = quoted.group(1)
    if (
        ASSET_PATH_RE.fullmatch(path) is None
        or ".." in path
        or "//" in path
        or path.endswith("/")
    ):
        return "file is not a plain path under assets/"
    extension = os.path.splitext(path)[1]
    if extension != ".tres" and extension not in DATA_EXTENSIONS:
        return f"file type {extension or '(none)'} is not an exempt data type"
    game_path = "game/" + path
    if added:
        if read_head(game_path) is None:
            return "file is missing at the head revision"
    elif extension != ".tres":
        return None
    if extension == ".tres":
        problem = plain_material_problem(read(game_path))
        if problem is not None:
            return problem
    elif added:
        return sidecar_problem(game_path, read_head)
    return None


# --- classify --------------------------------------------------------------------------------


def classify(
    old_log: str | None,
    new_log: str | None,
    read_old: Reader,
    read_new: Reader,
) -> Verdict:
    """Classify the change from old_log to new_log. No git and no I/O except via the readers."""
    if old_log is not None and old_log == new_log:
        return Verdict(False, True, [])
    problems: list[str] = []
    old = split_table(old_log, "old", problems)
    new = split_table(new_log, "new", problems)
    if old is None or new is None:
        return gate(*problems)
    if old.pre != new.pre:
        problems.append("text before the table changed")
    if old.post != new.post:
        problems.append("text after the table changed")
    for label, table in (("old", old), ("new", new)):
        counts = Counter(table.rows)
        if any(count > 1 for count in counts.values()):
            problems.append(f"a row appears twice in the {label} table")
        files = Counter(file_cell_of(line) for line in table.rows)
        if any(count > 1 for count in files.values()):
            problems.append(f"a File appears in two rows of the {label} table")
    removed = Counter(old.rows) - Counter(new.rows)
    added = Counter(new.rows) - Counter(old.rows)
    kept_old = [line for line in old.rows if line not in removed]
    kept_new = [line for line in new.rows if line not in added]
    if kept_old != kept_new:
        problems.append("rows were reordered")
    for gone in removed:
        for came in added:
            same = file_cell_of(gone) == file_cell_of(came)
            if same and " ".join(gone.split()) == " ".join(came.split()):
                problems.append(f"whitespace-only edit of the row for {file_cell_of(came)}")
    if problems:
        return gate(*problems)
    for line in removed:
        problem = row_problem(line, added=False, read=read_old, read_head=read_new)
        if problem is not None:
            problems.append(f"removed row {file_cell_of(line)}: {problem}")
    for line in added:
        problem = row_problem(line, added=True, read=read_new, read_head=read_new)
        if problem is not None:
            problems.append(f"added row {file_cell_of(line)}: {problem}")
    if problems:
        return gate(*problems)
    return Verdict(True, False, [])


# --- command line ----------------------------------------------------------------------------


class ArgumentError(Exception):
    pass


class Parser(argparse.ArgumentParser):
    def error(self, message: str) -> NoReturn:
        raise ArgumentError(message)


def git_bytes(repo: str, *args: str) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        ["git", "-C", repo, *args], capture_output=True, check=False, timeout=120
    )


def resolve(repo: str, rev: str) -> str:
    if rev.startswith("-"):
        raise ValueError(f"bad revision {rev!r}")
    result = git_bytes(repo, "rev-parse", "--verify", "--quiet", rev + "^{commit}")
    if result.returncode != 0:
        raise ValueError(f"unknown revision {rev!r} in {repo!r}")
    return result.stdout.decode("utf-8").strip()


def make_reader(repo: str, sha: str) -> Reader:
    def read(path: str) -> bytes | None:
        result = git_bytes(repo, "cat-file", "blob", f"{sha}:{path}")
        return result.stdout if result.returncode == 0 else None

    return read


def decode(data: bytes | None) -> str | None:
    return None if data is None else data.decode("utf-8")


def run(argv: list[str]) -> Verdict:
    parser = Parser(add_help=False)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--old", required=True)
    parser.add_argument("--new", required=True)
    args = parser.parse_args(argv)
    old_sha = resolve(args.repo, args.old)
    new_sha = resolve(args.repo, args.new)
    read_old = make_reader(args.repo, old_sha)
    read_new = make_reader(args.repo, new_sha)
    old_bytes = read_old(LOG_PATH)
    new_bytes = read_new(LOG_PATH)
    if old_bytes is not None and old_bytes == new_bytes:
        return Verdict(False, True, [])
    try:
        old_log, new_log = decode(old_bytes), decode(new_bytes)
    except UnicodeDecodeError:
        return gate(f"{LOG_PATH} is not valid UTF-8")
    return classify(old_log, new_log, read_old, read_new)


def main(argv: list[str] | None = None) -> int:
    try:
        verdict = run(sys.argv[1:] if argv is None else argv)
    except Exception as err:  # noqa: BLE001 - every failure must end as exit 2, never 0
        print(f"ERROR: {' '.join(str(err).split()) or type(err).__name__}")
        print("RESULT: error")
        return 2
    if verdict.unchanged:
        print("RESULT: unchanged")
        return 0
    if verdict.exempt:
        print("RESULT: exempt")
        return 0
    for reason in verdict.reasons or ["unclassified change"]:
        print(f"GATE: {reason}")
    print("RESULT: gate")
    return 1


if __name__ == "__main__":
    sys.exit(main())
