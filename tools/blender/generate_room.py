"""Generate the room corner, the cabinet, the lamp and the shared palette atlas (#22), headless in
Blender 5.2.

Usage (the arguments after ``--`` belong to this script):

    blender --background --python tools/blender/generate_room.py -- --params <file> --out-dir <dir>

- ``--params``: parameter JSON (default ``tools/blender/params/room.json``).
- ``--out-dir``: folder for ``cabinet_medium_1.glb``, ``room_corner.glb``, ``lamp_medium_1.glb`` and
  ``room_palette_atlas.png`` (default ``game/assets/room``). The four files are replaced as one
  group (``blender_common.swap_in_group``): the folder holds the old group or the new group.
- Running without arguments regenerates the committed files. Defaults are resolved from the
  location of this script, so the working directory does not matter.

Spaces and origins (technical plan of #22), glTF frame (1 unit = 1 m, +X right, +Y up, +Z front):

- ``cabinet_medium_1.glb``: origin = centre of the cabinet footprint on the floor; the top is at
  ``cabinet_height_m``. One mesh ``cabinet``: recessed plinth, carcass, top slab with chamfered
  edges, two plain panel doors and two brass knobs. The footprint is exactly
  ``cabinet_width_m`` x ``cabinet_depth_m`` (the top slab); nothing reaches beyond it.
- ``room_corner.glb``: origin = the floor point under the tank centre (= the cabinet footprint
  centre). ``Floor`` is a slab whose top face is y = 0; ``BackWall`` and ``SideWall`` are
  single-sided planes facing into the room (the palette shader culls back faces, so from outside
  they vanish like a dollhouse cut-away); ``Skirting`` runs along both walls. The back wall's
  inner face is at z = -(cabinet_depth_m / 2 + wall_gap_m).
- ``lamp_medium_1.glb``: origin = centre of the plane where the feet rest on the tank trim. ``lamp`` is the
  bar (``lamp_bar_length_m`` x ``lamp_bar_depth_m``, with a warm LED diffuser underneath that uses
  the emissive atlas row); ``lamp_brackets`` are the two feet that reach from the bar ends down
  onto the side trims (BA decision on AC 10). Nothing hangs in front of the bar (no front skirt).
- Every mesh uses the material ``palette`` (Godot maps it to ``room_palette.tres``), hard edges by
  split normals (smooth by angle at 30 degrees), exactly two UV layers; see ``blender_common``.

Parameter file: a JSON object with exactly these keys, in metres unless stated. Values outside the
range are rejected with a message that names the key.

    cabinet_width_m           0.20 .. 2.50   footprint along X (the top slab)
    cabinet_depth_m           0.15 .. 1.00   footprint along Z
    cabinet_height_m          0.30 .. 1.20   floor to the top surface
    cabinet_top_thickness_m   0.015 .. 0.06  top slab
    cabinet_side_overhang_m   0.0 .. 0.04    top slab beyond the carcass sides
    cabinet_door_setback_m    0.01 .. 0.06   door fronts behind the front edge of the top slab
    door_thickness_m          0.01 .. 0.03
    door_gap_m                0.002 .. 0.01  gap between the doors and around them
    knob_radius_m             0.004 .. 0.02
    knob_depth_m              0.005 .. 0.04  at most cabinet_door_setback_m
    plinth_height_m           0.03 .. 0.15   recessed kick board
    plinth_inset_m            0.005 .. 0.08
    wall_gap_m                0.02 .. 0.05   cabinet back to the back wall
    wall_height_m             2.20 .. 3.00
    side_wall_side            -1 or 1        the side wall stands left (-1) or right (1)
    side_wall_offset_m        0.40 .. 3.00   tank centre to the side wall
    room_reach_m              0.80 .. 6.00   tank centre to the open side and to the open front
    floor_thickness_m         0.02 .. 0.20   floor slab below y = 0
    skirting_height_m         0.08 .. 0.10
    skirting_thickness_m      0.008 .. 0.03
    lamp_bar_length_m         0.10 .. 1.50
    lamp_bar_depth_m          0.02 .. 0.20
    lamp_bar_thickness_m      0.006 .. 0.04
    lamp_bar_lift_m           0.008 .. 0.10  trim top to the underside of the bar
    lamp_foot_span_m          0.10 .. 1.60   centre to centre of the feet (the trim centre lines)
    lamp_foot_width_m         0.003 .. 0.02  along X, so a foot stands on a trim
    lamp_foot_depth_m         0.006 .. 0.10  along Z, at most lamp_bar_depth_m

Exit code 0 on success, 1 on any error.
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
DEFAULT_PARAMS = REPO_ROOT / "tools" / "blender" / "params" / "room.json"
DEFAULT_OUT_DIR = REPO_ROOT / "game" / "assets" / "room"
CABINET_FILE = "cabinet_medium_1.glb"
ROOM_FILE = "room_corner.glb"
LAMP_FILE = "lamp_medium_1.glb"
ATLAS_FILE = "room_palette_atlas.png"
PALETTE_MATERIAL = "palette"

FLOAT_RANGES: dict[str, tuple[float, float]] = {
    "cabinet_width_m": (0.20, 2.50),
    "cabinet_depth_m": (0.15, 1.00),
    "cabinet_height_m": (0.30, 1.20),
    "cabinet_top_thickness_m": (0.015, 0.06),
    "cabinet_side_overhang_m": (0.0, 0.04),
    "cabinet_door_setback_m": (0.01, 0.06),
    "door_thickness_m": (0.01, 0.03),
    "door_gap_m": (0.002, 0.01),
    "knob_radius_m": (0.004, 0.02),
    "knob_depth_m": (0.005, 0.04),
    "plinth_height_m": (0.03, 0.15),
    "plinth_inset_m": (0.005, 0.08),
    "wall_gap_m": (0.02, 0.05),
    "wall_height_m": (2.20, 3.00),
    "side_wall_offset_m": (0.40, 3.00),
    "room_reach_m": (0.80, 6.00),
    "floor_thickness_m": (0.02, 0.20),
    "skirting_height_m": (0.08, 0.10),
    "skirting_thickness_m": (0.008, 0.03),
    "lamp_bar_length_m": (0.10, 1.50),
    "lamp_bar_depth_m": (0.02, 0.20),
    "lamp_bar_thickness_m": (0.006, 0.04),
    "lamp_bar_lift_m": (0.008, 0.10),
    "lamp_foot_span_m": (0.10, 1.60),
    "lamp_foot_width_m": (0.003, 0.02),
    "lamp_foot_depth_m": (0.006, 0.10),
}
CHOICES: dict[str, tuple[int, ...]] = {"side_wall_side": (-1, 1)}

# --- fixed shape constants (not tuning knobs of the parameter file) ---

TOP_CHAMFER = 0.004  # cabinet top slab edges
DOOR_CHAMFER = 0.003  # door front edges
DOOR_SIDE_REVEAL = 0.002  # doors stop this far inside the carcass sides
KNOB_FROM_DOOR_EDGE = 0.045  # knob centre from the meeting edge of the doors
KNOB_BELOW_TOP = 0.09  # knob centre below the underside of the top slab
KNOB_SEGMENTS = 16  # 22.5 degrees between side faces: smooth, not faceted
KNOB_STEM_RADIUS = 0.45  # fraction of the knob radius
KNOB_STEM_DEPTH = 0.4  # fraction of the knob depth
SKIRTING_CHAMFER = 0.4  # fraction of the skirting thickness
BAR_CHAMFER = 0.004
LED_MARGIN_X = 0.02  # diffuser ends inside the bar ends
LED_MARGIN_Z = 0.012  # diffuser edges inside the bar front and back
LED_PROUD = 0.001  # the diffuser stands this far below the bar body
ARM_REACH = 0.012  # the bracket arm reaches this far under the bar end
ARM_THICKNESS = 0.004


def load_params(path: Path) -> dict[str, float]:
    """Reads and validates the parameter file before any Blender work happens."""
    p = blender_common.load_ranged(path, FLOAT_RANGES, CHOICES)
    req = blender_common.require
    req(
        p["knob_depth_m"] <= p["cabinet_door_setback_m"],
        "knob_depth_m",
        f"{p['knob_depth_m']} must not exceed cabinet_door_setback_m "
        f"({p['cabinet_door_setback_m']}), so the knobs stay inside the footprint",
    )
    carcass_depth = p["cabinet_depth_m"] - p["cabinet_door_setback_m"] - p["door_thickness_m"]
    req(
        carcass_depth > 2.0 * p["plinth_inset_m"] + 0.05,
        "plinth_inset_m",
        f"{p['plinth_inset_m']} leaves no plinth inside a carcass {carcass_depth:.3f} m deep",
    )
    req(
        p["plinth_height_m"] + 2.0 * p["door_gap_m"] + 0.1
        < p["cabinet_height_m"] - p["cabinet_top_thickness_m"],
        "plinth_height_m",
        f"{p['plinth_height_m']} leaves no room for the doors",
    )
    req(
        p["side_wall_offset_m"] >= p["cabinet_width_m"] / 2.0 + 0.1,
        "side_wall_offset_m",
        f"{p['side_wall_offset_m']} must keep the side wall at least 10 cm from the cabinet",
    )
    req(
        p["room_reach_m"] >= p["cabinet_width_m"] / 2.0 + 0.3
        and p["room_reach_m"] >= p["cabinet_depth_m"] / 2.0 + 0.3,
        "room_reach_m",
        f"{p['room_reach_m']} must reach at least 30 cm beyond the cabinet",
    )
    req(
        p["skirting_thickness_m"] < p["wall_gap_m"],
        "skirting_thickness_m",
        f"{p['skirting_thickness_m']} must be below wall_gap_m, so the cabinet clears it",
    )
    foot_inner = (p["lamp_foot_span_m"] - p["lamp_foot_width_m"]) / 2.0
    req(
        foot_inner > p["lamp_bar_length_m"] / 2.0,
        "lamp_foot_span_m",
        f"{p['lamp_foot_span_m']}: the feet must stand outside the bar ends",
    )
    req(
        foot_inner - ARM_REACH - p["lamp_bar_length_m"] / 2.0 < 0.0,
        "lamp_foot_span_m",
        f"{p['lamp_foot_span_m']}: the bracket arms cannot reach under the bar ends",
    )
    req(
        p["lamp_foot_depth_m"] <= p["lamp_bar_depth_m"],
        "lamp_foot_depth_m",
        f"{p['lamp_foot_depth_m']} must not exceed lamp_bar_depth_m (no front skirt)",
    )
    req(
        p["lamp_bar_lift_m"] > ARM_THICKNESS + 0.002,
        "lamp_bar_lift_m",
        f"{p['lamp_bar_lift_m']} leaves no room for the bracket arms",
    )
    return p


# --- cabinet ---


def build_cabinet(p: dict[str, float]) -> MeshData:
    w = p["cabinet_width_m"]
    d = p["cabinet_depth_m"]
    h = p["cabinet_height_m"]
    top_t = p["cabinet_top_thickness_m"]
    carcass_hx = w / 2.0 - p["cabinet_side_overhang_m"]
    door_front = d / 2.0 - p["cabinet_door_setback_m"]
    carcass_front = door_front - p["door_thickness_m"]
    plinth_h = p["plinth_height_m"]
    inset = p["plinth_inset_m"]
    gap = p["door_gap_m"]
    under_top = h - top_t
    data = MeshData()
    # recessed plinth
    blender_common.box(
        data,
        (-carcass_hx + inset, 0.0, -d / 2.0 + inset),
        (carcass_hx - inset, plinth_h, carcass_front - inset),
        room_palette.WOOD_SHADOW,
    )
    # carcass
    blender_common.box(
        data,
        (-carcass_hx, plinth_h, -d / 2.0),
        (carcass_hx, under_top, carcass_front),
        room_palette.WOOD_CARCASS,
    )
    # top slab: the full footprint
    blender_common.chamfer_box(
        data,
        (-w / 2.0, under_top, -d / 2.0),
        (w / 2.0, h, d / 2.0),
        room_palette.WOOD_TOP,
        TOP_CHAMFER,
    )
    # two plain panel doors, chamfered front edges
    door_outer = carcass_hx - DOOR_SIDE_REVEAL
    for side in (-1.0, 1.0):
        x_inner = side * gap / 2.0
        x_outer = side * door_outer
        blender_common.chamfer_box(
            data,
            (min(x_inner, x_outer), plinth_h + gap, carcass_front),
            (max(x_inner, x_outer), under_top - gap, door_front),
            room_palette.WOOD_DOOR,
            DOOR_CHAMFER,
            up="z",
        )
        # knob: a thin stem and a round head
        centre = (side * (gap / 2.0 + KNOB_FROM_DOOR_EDGE), under_top - KNOB_BELOW_TOP)
        radius = p["knob_radius_m"]
        depth = p["knob_depth_m"]
        stem_end = door_front + depth * KNOB_STEM_DEPTH
        blender_common.cylinder_z(
            data,
            centre,
            door_front,
            stem_end,
            radius * KNOB_STEM_RADIUS,
            KNOB_SEGMENTS,
            room_palette.KNOB,
        )
        blender_common.cylinder_z(
            data, centre, stem_end, door_front + depth, radius, KNOB_SEGMENTS, room_palette.KNOB
        )
    return data


# --- room corner ---


def room_extent(p: dict[str, float]) -> tuple[float, float, float, float]:
    """(x_min, x_max, back_z, front_z) of the floor."""
    side = p["side_wall_side"]
    side_x = side * p["side_wall_offset_m"]
    open_x = -side * p["room_reach_m"]
    back_z = -(p["cabinet_depth_m"] / 2.0 + p["wall_gap_m"])
    return min(side_x, open_x), max(side_x, open_x), back_z, p["room_reach_m"]


def build_room(p: dict[str, float]) -> dict[str, MeshData]:
    x_min, x_max, back_z, front_z = room_extent(p)
    side = p["side_wall_side"]
    side_x = side * p["side_wall_offset_m"]
    wall_h = p["wall_height_m"]

    floor = MeshData()
    blender_common.chamfer_box(
        floor,
        (x_min, -p["floor_thickness_m"], back_z),
        (x_max, 0.0, front_z),
        room_palette.FLOOR_EDGE,
        top_cell=room_palette.FLOOR,
    )

    back = MeshData()
    blender_common.quad(
        back,
        (
            (x_min, 0.0, back_z),
            (x_max, 0.0, back_z),
            (x_max, wall_h, back_z),
            (x_min, wall_h, back_z),
        ),
        room_palette.WALL,
        (0.0, 0.0, 1.0),
    )

    side_wall = MeshData()
    blender_common.quad(
        side_wall,
        (
            (side_x, 0.0, back_z),
            (side_x, 0.0, front_z),
            (side_x, wall_h, front_z),
            (side_x, wall_h, back_z),
        ),
        room_palette.WALL,
        (-side, 0.0, 0.0),
    )

    skirting = MeshData()
    t = p["skirting_thickness_m"]
    sk_h = p["skirting_height_m"]
    chamfer = t * SKIRTING_CHAMFER
    blender_common.chamfer_box(
        skirting, (x_min, 0.0, back_z), (x_max, sk_h, back_z + t), room_palette.SKIRTING, chamfer
    )
    inner_x = side_x - side * t
    blender_common.chamfer_box(
        skirting,
        (min(side_x, inner_x), 0.0, back_z + t),
        (max(side_x, inner_x), sk_h, front_z),
        room_palette.SKIRTING,
        chamfer,
    )
    return {"Floor": floor, "BackWall": back, "SideWall": side_wall, "Skirting": skirting}


# --- lamp ---


def build_lamp(p: dict[str, float]) -> dict[str, MeshData]:
    half_len = p["lamp_bar_length_m"] / 2.0
    half_depth = p["lamp_bar_depth_m"] / 2.0
    lift = p["lamp_bar_lift_m"]
    bar_top = lift + p["lamp_bar_thickness_m"]

    bar = MeshData()
    blender_common.chamfer_box(
        bar,
        (-half_len, lift, -half_depth),
        (half_len, bar_top, half_depth),
        room_palette.LAMP_BODY,
        BAR_CHAMFER,
    )
    blender_common.box(
        bar,
        (-half_len + LED_MARGIN_X, lift - LED_PROUD, -half_depth + LED_MARGIN_Z),
        (half_len - LED_MARGIN_X, lift, half_depth - LED_MARGIN_Z),
        room_palette.LAMP_LED,
    )

    brackets = MeshData()
    foot_half = p["lamp_foot_width_m"] / 2.0
    foot_depth = p["lamp_foot_depth_m"] / 2.0
    centre = p["lamp_foot_span_m"] / 2.0
    for side in (-1.0, 1.0):
        x_in = centre - foot_half
        x_out = centre + foot_half
        blender_common.box(
            brackets,
            (min(side * x_in, side * x_out), 0.0, -foot_depth),
            (max(side * x_in, side * x_out), bar_top, foot_depth),
            room_palette.LAMP_BRACKET,
        )
        arm_start = half_len - ARM_REACH
        blender_common.box(
            brackets,
            (min(side * arm_start, side * x_in), lift - ARM_THICKNESS, -foot_depth),
            (max(side * arm_start, side * x_in), lift, foot_depth),
            room_palette.LAMP_BRACKET,
        )
    return {"lamp": bar, "lamp_brackets": brackets}


# --- entry point ---


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="generate_room.py",
        description="Generate the room corner, cabinet, lamp and palette atlas (#22).",
    )
    parser.add_argument("--params", type=Path, default=DEFAULT_PARAMS)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    return parser.parse_args(blender_common.script_args(argv))


def run(argv: list[str]) -> None:
    args = parse_args(argv)
    params = load_params(args.params.resolve())
    out_dir: Path = args.out_dir.resolve()
    if not out_dir.is_dir():
        raise GeneratorError(f"--out-dir does not exist: {out_dir}")
    groups: dict[str, dict[str, MeshData]] = {
        CABINET_FILE: {"cabinet": build_cabinet(params)},
        ROOM_FILE: build_room(params),
        LAMP_FILE: build_lamp(params),
    }

    blender_common.reset_scene()
    material = blender_common.new_material(PALETTE_MATERIAL)
    objects: dict[str, list] = {
        file_name: [
            blender_common.build_object(name, data, material) for name, data in meshes.items()
        ]
        for file_name, meshes in groups.items()
    }

    def glb_writer(file_name: str):  # noqa: ANN202
        return lambda path: blender_common.export_glb(objects[file_name], path)

    def atlas_writer(path: Path) -> None:
        path.write_bytes(room_palette.atlas_png())

    outputs = [(name, glb_writer(name), blender_common.GLB_MAGIC) for name in groups]
    outputs.append((ATLAS_FILE, atlas_writer, blender_common.PNG_MAGIC))
    blender_common.write_group(out_dir, outputs)
    for file_name, meshes in groups.items():
        triangles = sum(data.triangle_count() for data in meshes.values())
        print(f"generate_room: wrote {out_dir / file_name} ({triangles} triangles)")
    print(f"generate_room: wrote {out_dir / ATLAS_FILE}")


if __name__ == "__main__":
    sys.exit(blender_common.main("generate_room", run))
