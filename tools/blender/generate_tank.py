"""Generate a rectangular glass tank (#22), headless in Blender 5.2.

Usage (the arguments after ``--`` belong to this script):

    blender --background --python tools/blender/generate_tank.py -- --params <file> --out <path>

- ``--params``: parameter JSON (default ``tools/blender/params/tank_medium_1.json``).
- ``--out``: the ``.glb`` to write (default ``game/assets/tank/tank_medium_1.glb``).
- Running without arguments regenerates the committed medium tank. Defaults are resolved from the
  location of this script, so the working directory does not matter.

Geometry (BA decisions Q7 and Q8 on #22), in the glTF frame (1 unit = 1 m, +X right, +Y up, +Z
toward the front glass):

- The origin is the centre of the inner tank floor (model convention #16).
- ``Glass``: five panes. The bottom pane spans the whole exterior footprint from
  y = -glass_thickness to 0; the front and back panes span the full exterior length; the two side
  panes sit between them. The inner faces lie exactly on the interior size, the outer faces on
  interior + 2 x glass thickness. Material ``glass`` (Godot maps it to the placeholder glass).
- ``Frame``: the rim trim, a closed ring ``trim_width_m`` wide and ``trim_height_m`` tall on top
  of the glass rim, flush with the outer glass faces. The exterior footprint including the trim is
  therefore the glass footprint. Material ``palette`` (the shared room palette atlas).
- Hard edges by split normals (smooth by angle at 30 degrees), exactly two UV layers (``UV0``,
  ``UV1``); see ``blender_common``. No scale is baked in.

Parameter file: a JSON object with exactly these keys, in metres. Values outside the range are
rejected with a message that names the key.

    interior_length_m   0.10 .. 3.00   inner length along X
    interior_height_m   0.10 .. 1.50   inner floor to the top of the glass along Y
    interior_depth_m    0.10 .. 1.50   inner depth along Z
    glass_thickness_m   0.002 .. 0.03  every pane
    trim_width_m        0.002 .. 0.05  at least glass_thickness_m, below a quarter of the depth
    trim_height_m       0.002 .. 0.05

Exit code 0 on success, 1 on any error. The ``.glb`` is written to a temporary file and renamed
only after the export succeeded (``blender_common.write_group``).
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import blender_common  # noqa: E402
import room_palette  # noqa: E402
from blender_common import GeneratorError, MeshData  # noqa: E402,F401 (re-exported for tests)

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_PARAMS = REPO_ROOT / "tools" / "blender" / "params" / "tank_medium_1.json"
DEFAULT_OUT = REPO_ROOT / "game" / "assets" / "tank" / "tank_medium_1.glb"

FLOAT_RANGES: dict[str, tuple[float, float]] = {
    "interior_length_m": (0.10, 3.00),
    "interior_height_m": (0.10, 1.50),
    "interior_depth_m": (0.10, 1.50),
    "glass_thickness_m": (0.002, 0.03),
    "trim_width_m": (0.002, 0.05),
    "trim_height_m": (0.002, 0.05),
}

FRAME_NAME = "Frame"
GLASS_NAME = "Glass"
PALETTE_MATERIAL = "palette"
GLASS_MATERIAL = "glass"


def load_params(path: Path) -> dict[str, float]:
    """Reads and validates the parameter file before any Blender work happens."""
    params = blender_common.load_ranged(path, FLOAT_RANGES)
    blender_common.require(
        params["trim_width_m"] >= params["glass_thickness_m"],
        "trim_width_m",
        f"{params['trim_width_m']} must be at least glass_thickness_m "
        f"({params['glass_thickness_m']}), so the trim covers the glass edge",
    )
    blender_common.require(
        params["trim_width_m"] < params["interior_depth_m"] / 4.0,
        "trim_width_m",
        f"{params['trim_width_m']} must be below a quarter of interior_depth_m",
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
    w = params["trim_width_m"]
    y0 = params["interior_height_m"]
    data = MeshData()
    blender_common.frame_ring(
        data, (hx, hz), (hx - w, hz - w), y0, y0 + params["trim_height_m"], room_palette.TRIM
    )
    return data


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="generate_tank.py", description="Generate a glass tank .glb (#22)."
    )
    parser.add_argument("--params", type=Path, default=DEFAULT_PARAMS)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    return parser.parse_args(blender_common.script_args(argv))


def run(argv: list[str]) -> None:
    args = parse_args(argv)
    params = load_params(args.params.resolve())
    out: Path = args.out.resolve()
    if out.suffix.lower() != ".glb":
        raise GeneratorError(f"--out must name a .glb file: {out}")
    glass = build_glass(params)
    frame = build_frame(params)

    blender_common.reset_scene()
    objects = [
        blender_common.build_object(
            FRAME_NAME, frame, blender_common.new_material(PALETTE_MATERIAL)
        ),
        blender_common.build_object(
            GLASS_NAME, glass, blender_common.new_material(GLASS_MATERIAL)
        ),
    ]
    blender_common.write_group(
        out.parent,
        [
            (
                out.name,
                lambda path: blender_common.export_glb(objects, path),
                blender_common.GLB_MAGIC,
            )
        ],
    )
    triangles = glass.triangle_count() + frame.triangle_count()
    print(f"generate_tank: wrote {out} ({triangles} triangles)")


if __name__ == "__main__":
    sys.exit(blender_common.main("generate_tank", run))
