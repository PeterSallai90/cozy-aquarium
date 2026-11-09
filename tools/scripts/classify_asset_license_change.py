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
import json
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
TRES_FORBIDDEN = ("script", "shader", '.gd"', ".gdshader")
KEY_VALUE_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_/]* = .+")
MATERIAL_PATH_RE = re.compile(r"res://assets/[A-Za-z0-9_./-]+\.tres")
IMPORTED_PATH_RE = re.compile(r"res://\.godot/imported/[A-Za-z0-9_.-]+")
QUOTED_RE = re.compile(r'"[^"\n]*"')
IMPORTED_KEYS = (("[remap]", "path"), ("[deps]", "dest_files"))
MULTI_LINE_KEYS = (("[params]", "_subresources"), ("[remap]", "metadata"))
TEXTURE_EXT_RE = re.compile(
    r'\[ext_resource type="(Texture2D|CompressedTexture2D)"( uid="uid://[a-z0-9]+")?'
    r' path="res://assets/[A-Za-z0-9_./-]+\.png"( id="[A-Za-z0-9_]+")?\]'
)
SECTION_RE = re.compile(r"\[[a-z_]+\]")
SIDECAR_LINE_RE = re.compile(r"([A-Za-z0-9_./-]+)=(.*)")

SCENE_PARAMS = frozenset(
    """nodes/root_type nodes/root_name nodes/root_script
    mesh_library/use_node_names_as_mesh_names array_mesh/deduplicate_surfaces
    nodes/apply_root_scale nodes/root_scale nodes/import_as_skeleton_bones
    nodes/use_name_suffixes nodes/use_node_type_suffixes meshes/ensure_tangents
    meshes/generate_lods meshes/create_shadow_meshes meshes/light_baking
    meshes/lightmap_texel_size meshes/force_disable_compression skins/use_named_skins
    animation/import animation/fps animation/trimming animation/remove_immutable_tracks
    animation/import_rest_as_RESET import_script/path materials/extract
    materials/extract_format materials/extract_path _subresources gltf/naming_version
    gltf/embedded_image_handling gltf/texture_map_mode""".split()
)
TEXTURE_PARAMS = frozenset(
    """compress/mode compress/high_quality compress/lossy_quality compress/uastc_level
    compress/rdo_quality_loss compress/hdr_compression compress/normal_map
    compress/channel_pack mipmaps/generate mipmaps/limit roughness/mode roughness/src_normal
    process/channel_remap/red process/channel_remap/green process/channel_remap/blue
    process/channel_remap/alpha process/fix_alpha_border process/premult_alpha
    process/normal_map_invert_y process/hdr_as_srgb process/hdr_clamp_exposure
    process/size_limit detect_3d/compress_to""".split()
)
OGG_PARAMS = frozenset("loop loop_offset bpm beat_count bar_beats".split())
WAV_PARAMS = frozenset(
    """force/8_bit force/mono force/max_rate force/max_rate_hz edit/trim edit/normalize
    edit/loop_mode edit/loop_begin edit/loop_end compress/mode""".split()
)
# extension -> (expected importer, allowed [params] keys)
IMPORTERS: dict[str, tuple[str, frozenset[str]]] = {
    ".glb": ("scene", SCENE_PARAMS),
    ".png": ("texture", TEXTURE_PARAMS),
    ".ogg": ("oggvorbisstr", OGG_PARAMS),
    ".wav": ("wav", WAV_PARAMS),
    ".mp3": ("mp3", OGG_PARAMS),
}
MATERIAL_ENTRY_KEYS = {
    "use_external/enabled": bool,
    "use_external/path": str,
    "use_external/fallback_path": str,
}

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


def scan_fragment(fragment: str) -> tuple[int, bool, bool]:
    """Scan one line of a sidecar value.

    Returns (net opening minus closing brackets outside double-quoted strings, whether a
    ; or # comment marker appears outside a string, whether the line ends inside a string).
    """
    depth = 0
    comment = False
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
        elif char in ";#":
            comment = True
        elif char in "{[(":
            depth += 1
        elif char in "}])":
            depth -= 1
    return depth, comment, in_string


def subresources_problem(value: str, read_new: Reader) -> str | None:
    """None when the _subresources value is {} or only external plain-material bindings."""
    if "\\" in value:
        return "import sidecar _subresources contains an escape sequence"

    def no_duplicates(pairs: list[tuple[str, object]]) -> dict[str, object]:
        result: dict[str, object] = dict(pairs)
        if len(result) != len(pairs):
            raise ValueError("duplicate key")
        return result

    try:
        parsed = json.loads(value, object_pairs_hook=no_duplicates)
    except ValueError:
        return "import sidecar _subresources is not valid JSON"
    if not isinstance(parsed, dict):
        return "import sidecar _subresources is not a dictionary"
    if not parsed:
        return None
    if list(parsed) != ["materials"]:
        return "import sidecar _subresources has a category other than materials"
    materials = parsed["materials"]
    if not isinstance(materials, dict):
        return "import sidecar _subresources materials is not a dictionary"
    for entry in materials.values():
        if not isinstance(entry, dict):
            return "import sidecar _subresources has a material entry that is not a dictionary"
        for key, item in entry.items():
            expected = MATERIAL_ENTRY_KEYS.get(key)
            if expected is None or type(item) is not expected:
                return f"import sidecar _subresources material option {key} is not allowed"
            if expected is str and item:
                problem = material_path_problem(item, read_new)
                if problem is not None:
                    return f"import sidecar _subresources {key}: {problem}"
    for name in materials:
        if "res://" in name or "uid://" in name:
            return "import sidecar _subresources has a material name that looks like a path"
    return None


def material_path_problem(path: str, read_new: Reader) -> str | None:
    """None when path is, as a whole string, a plain material .tres under res://assets/."""
    if MATERIAL_PATH_RE.fullmatch(path) is None or ".." in path:
        return f"{path} is not a plain res://assets/ material path"
    problem = plain_material_problem(read_new("game/" + path[len("res://") :]))
    if problem is not None:
        return f"{path}: {problem}"
    return None


def allowlist_problem(
    game_path: str, values: dict[tuple[str, str], str], read_new: Reader
) -> str | None:
    """Check importer, [params] keys and _subresources against the known, safe set."""
    importer, allowed = IMPORTERS[os.path.splitext(game_path)[1]]
    if values.get(("[remap]", "importer")) != f'"{importer}"':
        return f"import sidecar has no importer={importer}"
    for (section, name), value in values.items():
        if section == "[params]" and name not in allowed:
            return f"import sidecar has the unknown param {name}"
        if name == "_subresources":
            if section != "[params]":
                return "import sidecar has _subresources outside [params]"
            problem = subresources_problem(value, read_new)
            if problem is not None:
                return problem
    return None


def sidecar_problem(game_path: str, read_new: Reader) -> str | None:
    """None when the .import sidecar binds no script, shader or non-plain material.

    The sidecar is parsed strictly: only the exact format Godot writes is accepted (sections,
    unquoted keys without spaces, no comments, no repeated keys, multi-line values only for
    [params] _subresources and [remap] metadata). Anything else gates,
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
    current: tuple[str, str] = ("", "")
    for line in text.split("\n"):
        if depth > 0:
            delta, comment, open_string = scan_fragment(line)
            if comment or open_string:
                return "import sidecar has a comment marker or an unterminated string"
            depth += delta
            if depth < 0:
                return "import sidecar has unbalanced brackets"
            values[current] += "\n" + line
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
        current = key
        depth, comment, open_string = scan_fragment(match.group(2))
        if comment or open_string:
            return "import sidecar has a comment marker or an unterminated string"
        if depth < 0:
            return "import sidecar has unbalanced brackets"
        if depth > 0 and key not in MULTI_LINE_KEYS:
            return f"import sidecar has a multi-line value for {match.group(1)}"
    if depth != 0:
        return "import sidecar has unbalanced brackets"
    problem = allowlist_problem(game_path, values, read_new)
    if problem is not None:
        return problem
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
    leftovers = rest
    for (key_section, name), value in values.items():
        if name == "_subresources":
            leftovers = leftovers.replace(value, "")
            continue
        for string in QUOTED_RE.findall(value):
            inner = string[1:-1]
            if "res://" not in inner:
                continue
            if "\\" in inner or ".." in inner:
                return f"import sidecar has an unusual reference {inner}"
            if inner == own_source:
                continue
            imported = any(
                key_section == sec and name.startswith(base) for sec, base in IMPORTED_KEYS
            )
            if imported and IMPORTED_PATH_RE.fullmatch(inner) is not None:
                continue
            return f"import sidecar references {inner}"
    if "res://" in QUOTED_RE.sub("", leftovers.replace("\\", "")) or "://" in leftovers.replace(
        "res://", ""
    ):
        return "import sidecar uses an unexpected resource reference or scheme"
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
