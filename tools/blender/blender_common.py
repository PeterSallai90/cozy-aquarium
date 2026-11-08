"""Shared helpers of the tank and room generators (#22). ``generate_fish.py`` (#21) does not use it.

The module imports outside Blender (stdlib only at import time), so the local unittests can test
the parameter checks and the group swap without Blender. ``bpy`` and ``bmesh`` are imported inside
the functions that need them.

What is here:

- ``GeneratorError``: a failure with a message meant for the person running the generator.
- Strict parameter loading: JSON object, duplicate keys rejected, unknown and missing keys
  rejected, each value type- and range-checked with the key named in the message.
- ``MeshData`` and shape builders (box, chamfered box, cylinder, frame ring) in the glTF frame:
  1 unit = 1 m, +X right, +Y up, +Z front (glTF +Z = Blender -Y = Godot ``Vector3.MODEL_FRONT``).
- Blender object creation with exactly two UV layers, ``UV0`` and ``UV1`` (docs/art-style.md,
  "Generator conventions"): UV0 is a planar projection in metres (no mask or gradient texture uses
  it yet, so it is not a packed unwrap); UV1 collapses every face onto the centre of one cell of
  the shared palette atlas (``room_palette``). The lightmap pack operator is never used.
- Hard edges by split normals: every face is smooth and an edge is marked sharp when its two
  faces meet at more than ``SHARP_ANGLE_DEG`` (smooth by angle at 30 degrees, no flat faceting).
- glTF export settings like #21, and the all-or-nothing output swap (``swap_in_group``).
"""

from __future__ import annotations

import json
import math
import os
import shutil
import sys
from collections.abc import Callable, Iterable
from pathlib import Path

import room_palette

SHARP_ANGLE_DEG = 30.0
UV_LAYERS = ("UV0", "UV1")

Vec = tuple[float, float, float]
Cell = tuple[int, int]


class GeneratorError(Exception):
    """A failure with a message meant for the person running the generator."""


# --- parameters ---


def _reject_duplicates(pairs: list[tuple[str, object]]) -> dict[str, object]:
    table: dict[str, object] = {}
    for key, value in pairs:
        if key in table:
            raise GeneratorError(f"parameter file: key {key!r} appears twice")
        table[key] = value
    return table


def load_json_object(path: Path) -> dict[str, object]:
    """Reads a parameter file: a JSON object without duplicate keys."""
    if not path.is_file():
        raise GeneratorError(f"parameter file not found: {path}")
    try:
        text = path.read_text(encoding="utf-8")
        data = json.loads(text, object_pairs_hook=_reject_duplicates)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise GeneratorError(f"parameter file is not valid JSON: {path}: {error}") from error
    if not isinstance(data, dict):
        raise GeneratorError(f"parameter file must hold a JSON object: {path}")
    return data


def check_keys(data: dict[str, object], allowed: Iterable[str]) -> None:
    """Rejects unknown and missing keys, naming them."""
    allowed = tuple(allowed)
    unknown = sorted(set(data) - set(allowed))
    if unknown:
        raise GeneratorError(
            f"parameter file: unknown key(s) {', '.join(unknown)}; allowed: {', '.join(allowed)}"
        )
    missing = [key for key in allowed if key not in data]
    if missing:
        raise GeneratorError(f"parameter file: missing key(s) {', '.join(missing)}")


def read_float(data: dict[str, object], key: str, low: float, high: float) -> float:
    value = data[key]
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise GeneratorError(f"parameter {key}: must be a number, got {value!r}")
    if not math.isfinite(value) or not low <= value <= high:
        raise GeneratorError(f"parameter {key}: {value!r} is outside {low} .. {high}")
    return float(value)


def read_choice(data: dict[str, object], key: str, choices: tuple[int, ...]) -> int:
    value = data[key]
    if isinstance(value, bool) or not isinstance(value, int) or value not in choices:
        raise GeneratorError(f"parameter {key}: must be one of {choices}, got {value!r}")
    return value


def load_ranged(
    path: Path,
    float_ranges: dict[str, tuple[float, float]],
    choices: dict[str, tuple[int, ...]] | None = None,
) -> dict[str, float]:
    """Loads a parameter file whose keys are exactly ``float_ranges`` plus ``choices``."""
    choices = choices or {}
    data = load_json_object(path)
    check_keys(data, tuple(float_ranges) + tuple(choices))
    params: dict[str, float] = {}
    for key, (low, high) in float_ranges.items():
        params[key] = read_float(data, key, low, high)
    for key, allowed in choices.items():
        params[key] = read_choice(data, key, allowed)
    return params


def require(condition: bool, key: str, reason: str) -> None:
    """A cross-key rule; the message names ``key``, the key to change."""
    if not condition:
        raise GeneratorError(f"parameter {key}: {reason}")


# --- small vector helpers (glTF frame) ---


def _add(a: Vec, b: Vec) -> Vec:
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def _sub(a: Vec, b: Vec) -> Vec:
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _mul(a: Vec, k: float) -> Vec:
    return (a[0] * k, a[1] * k, a[2] * k)


def _dot(a: Vec, b: Vec) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _cross(a: Vec, b: Vec) -> Vec:
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


# --- mesh data (pure Python, deterministic, testable outside Blender) ---


class MeshData:
    """Vertices and faces in the glTF frame; each face has an atlas cell and UV0 corners."""

    def __init__(self) -> None:
        self.vertices: list[Vec] = []
        self.faces: list[tuple[int, ...]] = []
        self.cells: list[Cell] = []
        self.uv0: list[tuple[tuple[float, float], ...]] = []

    def vertex(self, p: Vec) -> int:
        self.vertices.append(p)
        return len(self.vertices) - 1

    def face_normal(self, corners: tuple[int, ...]) -> Vec:
        n = (0.0, 0.0, 0.0)
        for k, index in enumerate(corners):
            a = self.vertices[index]
            b = self.vertices[corners[(k + 1) % len(corners)]]
            n = _add(n, _cross(a, b))
        return n

    def centre(self, corners: Iterable[int]) -> Vec:
        corners = tuple(corners)
        total = (0.0, 0.0, 0.0)
        for index in corners:
            total = _add(total, self.vertices[index])
        return _mul(total, 1.0 / len(corners))

    def face(self, corners: tuple[int, ...], cell: Cell, outward: Vec) -> None:
        """Adds a face wound to face ``outward``; UV0 is a planar projection in metres."""
        normal = self.face_normal(corners)
        if _dot(normal, outward) < 0.0:
            corners = tuple(reversed(corners))
            normal = _mul(normal, -1.0)
        axis = max(range(3), key=lambda i: (abs(normal[i]), -i))
        u_axis, v_axis = {0: (2, 1), 1: (0, 2), 2: (0, 1)}[axis]
        uv = tuple((self.vertices[i][u_axis], self.vertices[i][v_axis]) for i in corners)
        self.faces.append(corners)
        self.cells.append(cell)
        self.uv0.append(uv)

    def triangle_count(self) -> int:
        return sum(len(face) - 2 for face in self.faces)

    def bounds(self) -> tuple[Vec, Vec]:
        low = tuple(min(p[i] for p in self.vertices) for i in range(3))
        high = tuple(max(p[i] for p in self.vertices) for i in range(3))
        return low, high  # type: ignore[return-value]


def _swap_yz(p: Vec) -> Vec:
    return (p[0], p[2], p[1])


def chamfer_box(
    data: MeshData,
    low: Vec,
    high: Vec,
    cell: Cell,
    chamfer: float = 0.0,
    up: str = "y",
    top_cell: Cell | None = None,
) -> None:
    """A box whose edges around the ``up`` face (+Y or +Z) are chamfered at 45 degrees.

    ``chamfer`` 0 gives a plain box. ``top_cell`` colours the ``up`` face and its chamfers.
    """
    if up not in ("y", "z"):
        raise GeneratorError(f"internal: chamfer_box up must be y or z, got {up}")
    to_real: Callable[[Vec], Vec] = _swap_yz if up == "z" else (lambda p: p)
    lo = to_real(low)
    hi = to_real(high)
    x0, y0, z0 = lo
    x1, y1, z1 = hi
    if chamfer * 2.0 >= min(x1 - x0, z1 - z0) or chamfer >= y1 - y0:
        raise GeneratorError(f"internal: chamfer {chamfer} too large for box {low} .. {high}")
    top = top_cell or cell
    ring = ((x0, z0), (x1, z0), (x1, z1), (x0, z1))
    bottom = [data.vertex(to_real((x, y0, z))) for x, z in ring]
    if chamfer > 0.0:
        mid = [data.vertex(to_real((x, y1 - chamfer, z))) for x, z in ring]
        inset = ((x0 + chamfer, z0 + chamfer), (x1 - chamfer, z0 + chamfer))
        inset += ((x1 - chamfer, z1 - chamfer), (x0 + chamfer, z1 - chamfer))
        upper = [data.vertex(to_real((x, y1, z))) for x, z in inset]
    else:
        mid = [data.vertex(to_real((x, y1, z))) for x, z in ring]
        upper = mid
    centre = to_real(((x0 + x1) / 2.0, (y0 + y1) / 2.0, (z0 + z1) / 2.0))

    def add(corners: list[int], face_cell: Cell) -> None:
        out = _sub(data.centre(corners), centre)
        data.face(tuple(corners), face_cell, out)

    add(bottom, cell)
    for k in range(4):
        n = (k + 1) % 4
        add([bottom[k], bottom[n], mid[n], mid[k]], cell)
        if chamfer > 0.0:
            add([mid[k], mid[n], upper[n], upper[k]], top)
    add(upper, top)


def box(data: MeshData, low: Vec, high: Vec, cell: Cell) -> None:
    chamfer_box(data, low, high, cell)


def cylinder_z(
    data: MeshData,
    centre_xy: tuple[float, float],
    z0: float,
    z1: float,
    radius: float,
    segments: int,
    cell: Cell,
) -> None:
    """A closed cylinder along +Z; with 16 or more segments the side stays smooth (< 30 deg)."""
    cx, cy = centre_xy
    rings: list[list[int]] = []
    for z in (z0, z1):
        ring: list[int] = []
        for k in range(segments):
            angle = 2.0 * math.pi * k / segments
            x = cx + radius * math.cos(angle)
            y = cy + radius * math.sin(angle)
            ring.append(data.vertex((x, y, z)))
        rings.append(ring)
    for k in range(segments):
        n = (k + 1) % segments
        corners = (rings[0][k], rings[0][n], rings[1][n], rings[1][k])
        mid = data.centre(corners)
        data.face(corners, cell, (mid[0] - cx, mid[1] - cy, 0.0))
    data.face(tuple(rings[0]), cell, (0.0, 0.0, -1.0))
    data.face(tuple(rings[1]), cell, (0.0, 0.0, 1.0))


def frame_ring(
    data: MeshData,
    outer_half: tuple[float, float],
    inner_half: tuple[float, float],
    y0: float,
    y1: float,
    cell: Cell,
) -> None:
    """A closed rectangular ring (a rim frame) centred on the Y axis, from y0 to y1."""
    ox, oz = outer_half
    ix, iz = inner_half
    outer = ((-ox, -oz), (ox, -oz), (ox, oz), (-ox, oz))
    inner = ((-ix, -iz), (ix, -iz), (ix, iz), (-ix, iz))
    ob = [data.vertex((x, y0, z)) for x, z in outer]
    ot = [data.vertex((x, y1, z)) for x, z in outer]
    ib = [data.vertex((x, y0, z)) for x, z in inner]
    it = [data.vertex((x, y1, z)) for x, z in inner]
    for k in range(4):
        n = (k + 1) % 4
        side = data.centre((ob[k], ob[n]))
        out = (side[0], 0.0, side[2])
        data.face((ot[k], ot[n], it[n], it[k]), cell, (0.0, 1.0, 0.0))
        data.face((ob[k], ob[n], ib[n], ib[k]), cell, (0.0, -1.0, 0.0))
        data.face((ob[k], ob[n], ot[n], ot[k]), cell, out)
        data.face((ib[k], ib[n], it[n], it[k]), cell, _mul(out, -1.0))


def quad(data: MeshData, corners: tuple[Vec, Vec, Vec, Vec], cell: Cell, outward: Vec) -> None:
    """A single-sided quad (a wall) facing ``outward``."""
    data.face(tuple(data.vertex(p) for p in corners), cell, outward)


# --- Blender ---


def build_object(name: str, data: MeshData, material):  # noqa: ANN001, ANN201 (bpy types)
    """A Blender object from ``data`` with UV0, UV1 and smooth-by-angle split normals."""
    import bmesh  # noqa: PLC0415 (only inside Blender)
    import bpy  # noqa: PLC0415

    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    uv0 = bm.loops.layers.uv.new(UV_LAYERS[0])
    uv1 = bm.loops.layers.uv.new(UV_LAYERS[1])
    # glTF (x, y, z) -> Blender (x, -z, y): a proper rotation, so the winding stays outward
    verts = [bm.verts.new((p[0], -p[2], p[1])) for p in data.vertices]
    bm.verts.ensure_lookup_table()
    for corners, uvs, cell in zip(data.faces, data.uv0, data.cells, strict=True):
        face = bm.faces.new([verts[i] for i in corners])
        face.material_index = 0
        face.smooth = True
        atlas = room_palette.cell_uv(cell)
        for loop, uv in zip(face.loops, uvs, strict=True):
            loop[uv0].uv = uv
            loop[uv1].uv = atlas
    bm.normal_update()
    limit = math.radians(SHARP_ANGLE_DEG)
    for edge in bm.edges:
        if len(edge.link_faces) == 2 and edge.calc_face_angle(0.0) > limit:
            edge.smooth = False
    bm.to_mesh(mesh)
    bm.free()

    names = [layer.name for layer in mesh.uv_layers]
    if names != list(UV_LAYERS):
        raise GeneratorError(
            f"internal: UV layers of {name} are {names}, must be {list(UV_LAYERS)}"
        )
    mesh.uv_layers[UV_LAYERS[0]].active = True
    mesh.uv_layers[UV_LAYERS[0]].active_render = True
    mesh.materials.append(material)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def new_material(name: str):  # noqa: ANN201 (bpy type)
    """A plain single-sided material; Godot maps it to an external .tres on import."""
    import bpy  # noqa: PLC0415

    material = bpy.data.materials.new(name)
    material.use_backface_culling = True
    return material


def reset_scene() -> None:
    import bpy  # noqa: PLC0415

    bpy.ops.wm.read_factory_settings(use_empty=True)


def export_glb(objects: list, path: Path) -> None:  # noqa: ANN001 (bpy types)
    """Exports exactly ``objects`` (identity transforms, origin at the asset origin)."""
    import bpy  # noqa: PLC0415

    for other in bpy.context.scene.objects:
        other.select_set(False)
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    try:
        result = bpy.ops.export_scene.gltf(
            filepath=str(path),
            check_existing=False,
            export_format="GLB",
            use_selection=True,
            export_texcoords=True,
            export_normals=True,
            export_tangents=False,
            export_vertex_color="NONE",
            export_attributes=False,
            export_materials="EXPORT",
            export_image_format="NONE",
            export_yup=True,
            export_apply=True,
            export_animations=False,
            export_skins=False,
            export_morph=False,
            export_cameras=False,
            export_lights=False,
            export_extras=False,
        )
    except RuntimeError as error:
        raise GeneratorError(f"glTF export failed for {path.name}: {error}") from error
    if result != {"FINISHED"}:
        raise GeneratorError(f"glTF export failed for {path.name}: {result}")


# --- output files ---


def _backup_of(final: Path) -> Path:
    return final.with_name(f".{final.name}.bak")


def swap_in_group(
    moves: list[tuple[Path, Path]],
    rename: Callable[[Path, Path], None] = os.replace,
) -> None:
    """Moves every ``new`` to its ``final`` path, all or nothing.

    Each existing final file is copied to a hidden backup first. When a rename fails, every final
    file already replaced is restored from its backup (or deleted when it did not exist before),
    so the folder holds the complete old group or the complete new group, never a mix. Backups are
    removed afterwards; when a restore fails too, the backups are kept and the error names them.
    A process kill between two renames is not covered (as in #115).

    ``rename`` exists for the local unittest only; the generators never pass it. Raises
    ``GeneratorError`` with a message that names the failed file.
    """
    backups = [_backup_of(final) for _, final in moves]
    stale = [str(path) for path in backups if path.exists()]
    if stale:
        raise GeneratorError(
            f"backups from an earlier failed run exist: {', '.join(stale)}; "
            "restore or delete them, then run again"
        )
    had_old = [final.is_file() for _, final in moves]
    keep_backups = False
    try:
        for (_, final), backup, old in zip(moves, backups, had_old, strict=True):
            if old:
                try:
                    # copyfile, not copy2: a read-only file must not give a read-only backup.
                    shutil.copyfile(final, backup)
                except OSError as error:
                    raise GeneratorError(f"could not back up {final}: {error}") from error
        done = 0
        try:
            for new, final in moves:
                rename(new, final)
                done += 1
        except OSError as error:
            failed = moves[done][1]
            problems: list[str] = []
            for index in reversed(range(done)):
                final = moves[index][1]
                try:
                    if had_old[index]:
                        rename(backups[index], final)
                    else:
                        final.unlink()
                except OSError as rollback_error:
                    problems.append(f"{final.name}: {rollback_error}")
            if problems:
                keep_backups = True
                raise GeneratorError(
                    f"could not replace {failed}: {error}; the rollback failed too "
                    f"({'; '.join(problems)}); backups are kept next to the files"
                ) from error
            raise GeneratorError(
                f"could not replace {failed}: {error}; the old files are unchanged"
            ) from error
    finally:
        if not keep_backups:
            for backup in backups:
                if backup.is_file():
                    backup.unlink()


def write_group(folder: Path, outputs: list[tuple[str, Callable[[Path], None], bytes]]) -> None:
    """Writes each output to a hidden temp file in ``folder``, checks its magic bytes, then swaps
    the whole group in. ``outputs``: (final file name, writer of a path, expected magic)."""
    if not folder.is_dir():
        raise GeneratorError(f"output folder does not exist: {folder}")
    temps = [folder / f".{name}.tmp{Path(name).suffix}" for name, _, _ in outputs]
    try:
        for temp, (_, writer, magic) in zip(temps, outputs, strict=True):
            try:
                writer(temp)
            except OSError as error:
                raise GeneratorError(f"could not write {temp}: {error}") from error
            if not temp.is_file() or temp.stat().st_size == 0:
                raise GeneratorError(f"export wrote no file: {temp}")
            with temp.open("rb") as handle:
                if handle.read(len(magic)) != magic:
                    raise GeneratorError(f"export wrote a broken file: {temp}")
        finals = [folder / name for name, _, _ in outputs]
        swap_in_group(list(zip(temps, finals, strict=True)))
    finally:
        for temp in temps:
            if temp.is_file():
                temp.unlink()


GLB_MAGIC = b"glTF"
PNG_MAGIC = b"\x89PNG"


def script_args(argv: list[str]) -> list[str]:
    return argv[argv.index("--") + 1 :] if "--" in argv else []


def main(prog: str, run: Callable[[list[str]], None]) -> int:
    """Runs a generator; exit code 0 on success, 1 on any error (background Blender exits 0 on an
    uncaught exception otherwise)."""
    try:
        run(sys.argv)
    except GeneratorError as error:
        print(f"{prog}: error: {error}", file=sys.stderr, flush=True)
        return 1
    except SystemExit as stop:  # argparse usage errors
        return stop.code if isinstance(stop.code, int) else 1
    except BaseException as error:  # noqa: BLE001
        message = f"{prog}: error: unexpected {type(error).__name__}: {error}"
        print(message, file=sys.stderr, flush=True)
        return 1
    return 0
