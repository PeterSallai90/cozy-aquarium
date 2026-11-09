"""Generate the rectangular glass tanks (#22, #24), headless in Blender 5.2.

Usage (the arguments after ``--`` belong to this script):

    blender --background --python tools/blender/generate_tank.py -- [--params <file> [--out <path>]]

- Without arguments every ``tools/blender/params/tank_*.json`` is generated into
  ``game/assets/tank/<file stem>.glb`` (``tank_small_1.json`` -> ``tank_small_1.glb``), all files
  as one group (``blender_common.write_group``): the folder holds the old group or the new group.
- ``--params``: generate only this parameter file. ``--out``: the ``.glb`` to write (default
  ``game/assets/tank/<file stem>.glb``); only together with ``--params``.
- Defaults are resolved from the location of this script, so the working directory does not
  matter.

The parameter files mirror the catalog (``game/catalog/tanks/<id>.tres`` is the source of truth,
#24 plan section 3); the GdUnit test ``test_tank_params_match_catalog.gd`` fails on any difference.

Geometry (BA decisions Q7 and Q8 on #22), in the glTF frame (1 unit = 1 m, +X right, +Y up, +Z
toward the front glass):

- The origin is the centre of the inner tank floor (model convention #16).
- ``Glass``: five panes. The bottom pane spans the whole exterior footprint from
  y = -glass_thickness to 0; the front and back panes span the full exterior length; the two side
  panes sit between them. The inner faces lie exactly on the interior size, the outer faces on
  interior + 2 x glass thickness. Material ``glass`` (Godot maps it to the placeholder glass).
- ``Frame``: the rim trim, a closed ring ``trim_size_m`` wide and ``trim_size_m`` tall on top of
  the glass rim, flush with the outer glass faces. The exterior footprint including the trim is
  therefore the glass footprint. Material ``palette`` (the shared room palette atlas).
- Hard edges by split normals (smooth by angle at 30 degrees), exactly two UV layers (``UV0``,
  ``UV1``); see ``blender_common``. No scale is baked in.

Parameter file: a JSON object with exactly these keys, in metres. Values outside the range are
rejected with a message that names the key.

    interior_length_m   0.10 .. 3.00   inner length along X
    interior_height_m   0.10 .. 1.50   inner floor to the top of the glass along Y
    interior_depth_m    0.10 .. 1.50   inner depth along Z
    glass_thickness_m   0.002 .. 0.03  every pane
    trim_size_m         0.002 .. 0.05  rim trim width and height (catalog field trim_size_m); at
                                       least glass_thickness_m, below a quarter of the depth

Exit code 0 on success, 1 on any error. Every ``.glb`` is written to a temporary file and the
group is renamed into place only after every export succeeded.
"""

from __future__ import annotations

import argparse
import sys
from collections.abc import Callable
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import blender_common  # noqa: E402
import room_palette  # noqa: E402
from blender_common import GeneratorError, MeshData  # noqa: E402,F401 (re-exported for tests)

REPO_ROOT = Path(__file__).resolve().parents[2]
PARAMS_DIR = REPO_ROOT / "tools" / "blender" / "params"
OUT_DIR = REPO_ROOT / "game" / "assets" / "tank"
PARAMS_GLOB = "tank_*.json"

FLOAT_RANGES: dict[str, tuple[float, float]] = {
    "interior_length_m": (0.10, 3.00),
    "interior_height_m": (0.10, 1.50),
    "interior_depth_m": (0.10, 1.50),
    "glass_thickness_m": (0.002, 0.03),
    "trim_size_m": (0.002, 0.05),
}

FRAME_NAME = "Frame"
GLASS_NAME = "Glass"
PALETTE_MATERIAL = "palette"
GLASS_MATERIAL = "glass"


def load_params(path: Path) -> dict[str, float]:
    """Reads and validates the parameter file before any Blender work happens."""
    params = blender_common.load_ranged(path, FLOAT_RANGES)
    blender_common.require(
        params["trim_size_m"] >= params["glass_thickness_m"],
        "trim_size_m",
        f"{params['trim_size_m']} must be at least glass_thickness_m "
        f"({params['glass_thickness_m']}), so the trim covers the glass edge",
    )
    blender_common.require(
        params["trim_size_m"] < params["interior_depth_m"] / 4.0,
        "trim_size_m",
        f"{params['trim_size_m']} must be below a quarter of interior_depth_m",
    )
    return params


def build_glass(params: dict[str, float]) -> MeshData:
    length = params["interior_length_m"]
    height = params["interior_height_m"]
    depth = params["interior_depth_m"]
    g = params["glass_thickness_m"]
    hx = length / 2.0
    hz = depth / 2.0
    cell = room_palette.GLASS
    data = MeshData()
    # bottom pane under the whole footprint
    blender_common.box(data, (-hx - g, -g, -hz - g), (hx + g, 0.0, hz + g), cell)
    # front and back panes over the full exterior length
    blender_common.box(data, (-hx - g, 0.0, hz), (hx + g, height, hz + g), cell)
    blender_common.box(data, (-hx - g, 0.0, -hz - g), (hx + g, height, -hz), cell)
    # side panes between them
    blender_common.box(data, (hx, 0.0, -hz), (hx + g, height, hz), cell)
    blender_common.box(data, (-hx - g, 0.0, -hz), (-hx, height, hz), cell)
    return data


def build_frame(params: dict[str, float]) -> MeshData:
    hx = params["interior_length_m"] / 2.0 + params["glass_thickness_m"]
    hz = params["interior_depth_m"] / 2.0 + params["glass_thickness_m"]
    size = params["trim_size_m"]
    y0 = params["interior_height_m"]
    data = MeshData()
    blender_common.frame_ring(
        data, (hx, hz), (hx - size, hz - size), y0, y0 + size, room_palette.TRIM
    )
    return data


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="generate_tank.py", description="Generate the glass tank .glb files (#22, #24)."
    )
    parser.add_argument("--params", type=Path, default=None)
    parser.add_argument("--out", type=Path, default=None)
    return parser.parse_args(blender_common.script_args(argv))


def jobs(params_file: Path | None, out: Path | None) -> list[tuple[Path, Path]]:
    """(parameter file, output .glb) pairs: every committed tank, or the one named file."""
    if params_file is None:
        if out is not None:
            raise GeneratorError("--out needs --params")
        files = sorted(PARAMS_DIR.glob(PARAMS_GLOB))
        if not files:
            raise GeneratorError(f"no {PARAMS_GLOB} in {PARAMS_DIR}")
        return [(path, OUT_DIR / f"{path.stem}.glb") for path in files]
    params_file = params_file.resolve()
    target = (out if out is not None else OUT_DIR / f"{params_file.stem}.glb").resolve()
    if target.suffix.lower() != ".glb":
        raise GeneratorError(f"--out must name a .glb file: {target}")
    return [(params_file, target)]


def _writer(glass: MeshData, frame: MeshData) -> Callable[[Path], None]:
    """Builds one tank in a fresh Blender scene and exports it, so the object names of several
    tanks never collide (Blender would rename a second ``Frame`` to ``Frame.001``)."""

    def write(path: Path) -> None:
        blender_common.reset_scene()
        objects = [
            blender_common.build_object(
                FRAME_NAME, frame, blender_common.new_material(PALETTE_MATERIAL)
            ),
            blender_common.build_object(
                GLASS_NAME, glass, blender_common.new_material(GLASS_MATERIAL)
            ),
        ]
        blender_common.export_glb(objects, path)

    return write


def run(argv: list[str]) -> None:
    args = parse_args(argv)
    planned = jobs(args.params, args.out)
    folders = {out.parent for _, out in planned}
    if len(folders) != 1:
        raise GeneratorError("all tank .glb files must go to one folder")
    outputs: list[tuple[str, Callable[[Path], None], bytes]] = []
    report: list[tuple[Path, int]] = []
    for params_file, out in planned:
        params = load_params(params_file)
        glass = build_glass(params)
        frame = build_frame(params)
        outputs.append((out.name, _writer(glass, frame), blender_common.GLB_MAGIC))
        report.append((out, glass.triangle_count() + frame.triangle_count()))
    blender_common.write_group(folders.pop(), outputs)
    for out, triangles in report:
        print(f"generate_tank: wrote {out} ({triangles} triangles)")


if __name__ == "__main__":
    sys.exit(blender_common.main("generate_tank", run))
