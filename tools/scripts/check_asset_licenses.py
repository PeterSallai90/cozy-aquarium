"""Fail if a file in game/assets/ or an addon in game/addons/ has no row in docs/asset-licenses.md.

The File column holds paths relative to game/, for example assets/room/cabinet_01.glb.
Godot sidecar files (*.import, *.uid) and .gitkeep placeholders are not assets.

Rules:
- Files under game/assets/ need one row each.
- An addon is an immediate subfolder of game/addons/ that holds at least one real file. One
  row for the folder covers it (for example addons/gdUnit4/; the trailing slash is optional).
  A loose file directly in game/addons/ needs its own row.
- A row covers only the exact path it names: no parent or prefix matching.
- A row is stale only if its path does not exist under game/. A stale row is a WARNING and
  does not fail the check.

Usage: python tools/scripts/check_asset_licenses.py [--root REPO_ROOT]
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

GAME_DIR = Path("game")
ASSETS_DIR = GAME_DIR / "assets"
ADDONS_DIR = GAME_DIR / "addons"
LICENSE_LOG = Path("docs/asset-licenses.md")
IGNORED_NAMES = {".gitkeep"}
IGNORED_SUFFIXES = {".import", ".uid"}


def _cells(line: str) -> list[str]:
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def _clean_path(cell: str) -> str:
    path = cell.strip().strip("`").replace("\\", "")
    for prefix in ("./", "game/"):
        path = path.removeprefix(prefix)
    return path


def logged_files(log: Path) -> set[str]:
    files: set[str] = set()
    file_column: int | None = None
    for line in log.read_text(encoding="utf-8").splitlines():
        if not line.lstrip().startswith("|"):
            if file_column is not None and files:
                break
            continue
        cells = _cells(line)
        if file_column is None:
            if "File" in cells:
                file_column = cells.index("File")
            continue
        if all(set(cell) <= set(":- ") for cell in cells):
            continue
        if file_column < len(cells) and cells[file_column]:
            files.add(_clean_path(cells[file_column]))
    return files


def _is_unit_file(path: Path) -> bool:
    return (
        path.is_file()
        and path.name not in IGNORED_NAMES
        and path.suffix not in IGNORED_SUFFIXES
    )


def asset_files(root: Path) -> set[str]:
    assets = root / ASSETS_DIR
    if not assets.is_dir():
        return set()
    return {
        path.relative_to(root / GAME_DIR).as_posix()
        for path in assets.rglob("*")
        if _is_unit_file(path)
    }


def addon_items(root: Path) -> set[str]:
    addons = root / ADDONS_DIR
    if not addons.is_dir():
        return set()
    items: set[str] = set()
    for child in addons.iterdir():
        rel = child.relative_to(root / GAME_DIR).as_posix()
        if child.is_dir():
            if any(_is_unit_file(p) for p in child.rglob("*")):
                items.add(rel + "/")
        elif _is_unit_file(child):
            items.add(rel)
    return items


def _is_covered(item: str, logged: set[str]) -> bool:
    if item.endswith("/"):
        return item in logged or item.removesuffix("/") in logged
    return item in logged


def check(root: Path) -> int:
    log = root / LICENSE_LOG
    if not log.is_file():
        print(f"ERROR: {LICENSE_LOG.as_posix()} is missing.")
        return 1

    items = asset_files(root) | addon_items(root)
    logged = logged_files(log)

    for row in sorted(logged):
        if not (root / GAME_DIR / row).exists():
            print(f"WARNING: {LICENSE_LOG.as_posix()} lists {row}, which does not exist.")

    unlogged = sorted(item for item in items if not _is_covered(item, logged))
    if unlogged:
        print(f"ERROR: {len(unlogged)} item(s) have no row in {LICENSE_LOG.as_posix()}:")
        for path in unlogged:
            print(f"  {path}")
        return 1

    print(f"All {len(items)} item(s) in game/assets/ and game/addons/ are logged.")
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
