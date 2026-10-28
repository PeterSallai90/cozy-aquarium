"""Fail if any file in game/assets/ has no row in docs/asset-licenses.md.

The File column holds paths relative to game/, for example assets/room/cabinet_01.glb.
Godot sidecar files (*.import, *.uid) and .gitkeep placeholders are not assets.

Usage: python tools/scripts/check_asset_licenses.py [--root REPO_ROOT]
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

GAME_DIR = Path("game")
ASSETS_DIR = GAME_DIR / "assets"
LICENSE_LOG = Path("docs/asset-licenses.md")
IGNORED_NAMES = {".gitkeep"}
IGNORED_SUFFIXES = {".import", ".uid"}


def _cells(line: str) -> list[str]:
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def _clean_path(cell: str) -> str:
    """Normalise a File cell: drop backticks, Markdown escapes and a leading game/ or ./."""
    path = cell.strip().strip("`").replace("\\", "")
    for prefix in ("./", "game/"):
        path = path.removeprefix(prefix)
    return path


def logged_files(log: Path) -> set[str]:
    """Return the File column of every data row in the first table that has one."""
    files: set[str] = set()
    file_column: int | None = None
    for line in log.read_text(encoding="utf-8").splitlines():
        if not line.lstrip().startswith("|"):
            if file_column is not None and files:
                break  # end of the license table
            continue
        cells = _cells(line)
        if file_column is None:
            if "File" in cells:
                file_column = cells.index("File")
            continue
        if all(set(cell) <= set(":- ") for cell in cells):
            continue  # separator row
        if file_column < len(cells) and cells[file_column]:
            files.add(_clean_path(cells[file_column]))
    return files


def asset_files(root: Path) -> set[str]:
    assets = root / ASSETS_DIR
    if not assets.is_dir():
        return set()
    return {
        path.relative_to(root / GAME_DIR).as_posix()
        for path in assets.rglob("*")
        if path.is_file()
        and path.name not in IGNORED_NAMES
        and path.suffix not in IGNORED_SUFFIXES
    }


def check(root: Path) -> int:
    log = root / LICENSE_LOG
    if not log.is_file():
        print(f"ERROR: {LICENSE_LOG.as_posix()} is missing.")
        return 1

    assets = asset_files(root)
    logged = logged_files(log)

    for stale in sorted(logged - assets):
        print(f"WARNING: {LICENSE_LOG.as_posix()} lists {stale}, which does not exist.")

    unlogged = sorted(assets - logged)
    if unlogged:
        print(f"ERROR: {len(unlogged)} asset(s) have no row in {LICENSE_LOG.as_posix()}:")
        for path in unlogged:
            print(f"  {path}")
        return 1

    print(f"All {len(assets)} asset(s) in {ASSETS_DIR.as_posix()}/ are logged.")
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
