"""Generate the pipeline-proof fish (#21) and its palette atlas, headless in Blender 5.2.

Usage (the arguments after ``--`` belong to this script):

    blender --background --python tools/blender/generate_fish.py -- --params <file> --out <path>

- ``--params``: parameter JSON (default ``tools/blender/params/proof_fish.json``).
- ``--out``: the ``.glb`` to write (default ``game/assets/fish/proof_fish.glb``). The palette atlas
  is written next to it as ``proof_palette_atlas.png``.
- Running without arguments regenerates the committed proof files. Defaults are resolved from the
  location of this script, so the working directory does not matter.
- #40 extends this script with ``--all`` and ``--species <name>`` and keeps ``--params`` and
  ``--out``.

Conventions (docs/art-style.md, "Generator conventions"):

- 1 Blender unit = 1 m. The front is glTF +Z (Blender -Y). The body without fins is 1 unit long
  (standard length) with the origin at the centre of its bounding box. No scale is baked in.
- Smooth normals everywhere. Fins are single-layer sheets on the ``fin`` material, which is
  double-sided (backface culling off); the body and the eyes use the single-sided ``body``
  material.
- Exactly two UV layers: ``UV0`` (unwrap, glTF TEXCOORD_0) and ``UV1`` (palette atlas lookup,
  glTF TEXCOORD_1, Godot UV2). Every face of UV1 collapses onto the centre of one atlas cell. The
  lightmap pack operator is never used.
- The corner colour attribute ``Color`` holds the fin translucency mask in alpha: 1.0 on fins,
  0.0 on the body. RGB is white and unused.

Parameter file: a JSON object with exactly these keys (fractions of the standard length, ``_sl``,
or counts). Values outside the range are rejected with a message that names the key.

    body_height_sl        float 0.15 .. 0.40   body depth (bounding box Y)
    body_width_sl         float 0.08 .. 0.25   body width (bounding box X, eyes excluded)
    head_length_sl        float 0.20 .. 0.35   snout tip to the gill cover
    eye_diameter_sl       float 0.06 .. 0.14   visible eye diameter
    caudal_length_sl      float 0.15 .. 0.40   tail base to the lobe tips
    caudal_fork_depth_sl  float 0.00 .. 0.20   lobe tip to the fork notch, below caudal_length_sl
    dorsal_base_sl        float 0.10 .. 0.30   length of the dorsal fin base
    dorsal_height_sl      float 0.08 .. 0.25   dorsal tip height above the back
    pectoral_length_sl    float 0.10 .. 0.20   length of each pectoral fin
    body_ring_count       int   8 .. 48        cross-section rings between the two body poles
    body_ring_segments    int   8 .. 32        vertices per ring (even)

Exit code 0 on success, 1 on any error (background Blender would otherwise exit 0 on an uncaught
exception). Outputs are written to temporary files in the target folder and renamed only after
the export succeeded, so a failed run never leaves a half-written file. The ``.glb`` and the atlas
are replaced as a pair (``swap_in_pair``): the old ``.glb`` is backed up first, and when a rename
fails the earlier state is restored, so the folder holds the old pair or the new pair, never a mix.
A process kill or power loss between the two renames is not covered (#115).
"""

from __future__ import annotations

import argparse
import json
import math
import os
import shutil
import struct
import sys
import zlib
from collections.abc import Callable
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_PARAMS = REPO_ROOT / "tools" / "blender" / "params" / "proof_fish.json"
DEFAULT_OUT = REPO_ROOT / "game" / "assets" / "fish" / "proof_fish.glb"
ATLAS_NAME = "proof_palette_atlas.png"
OBJECT_NAME = "proof_fish"

FLOAT_RANGES: dict[str, tuple[float, float]] = {
    "body_height_sl": (0.15, 0.40),
    "body_width_sl": (0.08, 0.25),
    "head_length_sl": (0.20, 0.35),
    "eye_diameter_sl": (0.06, 0.14),
    "caudal_length_sl": (0.15, 0.40),
    "caudal_fork_depth_sl": (0.0, 0.20),
    "dorsal_base_sl": (0.10, 0.30),
    "dorsal_height_sl": (0.08, 0.25),
    "pectoral_length_sl": (0.10, 0.20),
}
COUNT_RANGES: dict[str, tuple[int, int]] = {
    "body_ring_count": (8, 48),
    "body_ring_segments": (8, 32),
}
ALLOWED_KEYS = tuple(FLOAT_RANGES) + tuple(COUNT_RANGES)

# --- palette atlas: 4 x 4 cells of 16 px, one flat colour per cell, row 0 at the top ---

ATLAS_GRID = 4
ATLAS_CELL_PX = 16
ATLAS_PALETTE: tuple[tuple[int, ...], ...] = (
    # deep to light blue; (0, 0) is the eye and the darkest cell
    (0x1D2433, 0x2C5D74, 0x3F8A9E, 0x79BCCB),
    # teal ramp
    (0x2F6E6A, 0x4A9B90, 0x7CC6B6, 0xB7E6D8),
    # warm coral ramp
    (0x8D4F5A, 0xC46F6F, 0xE8A08C, 0xF6CDB8),
    # silver and cream ramp
    (0x5F6878, 0x9AA6B4, 0xD3DBE2, 0xF6F0E4),
)
# (column, row from the top) of the cell each region samples
CELL_EYE = (0, 0)
CELL_BACK = (2, 0)
CELL_STRIPE = (2, 1)
CELL_FLANK = (2, 3)
CELL_BELLY = (3, 3)
CELL_FIN = (3, 2)

# --- fixed shape constants (not tuning knobs of the parameter file) ---

SECTION_EXPONENT = 2.2  # superellipse cross-section: laterally compressed, slightly full
PEDUNCLE_HEIGHT = 0.38  # caudal peduncle depth as a fraction of the maximum depth
PEDUNCLE_WIDTH = 0.30
DEEPEST_AT = 0.58  # fraction of the body from the tail base to the snout
WIDEST_AT = 0.66
SNOUT_HEIGHT = 0.55
SNOUT_WIDTH = 0.62
TAIL_CAP = 0.035  # length of the rounded closure at the tail base
NOSE_CAP_OF_HEAD = 0.55  # rounded snout closure as a fraction of the head length
POLE_PROBE = 0.05  # pole fans face away from this point on the axis, inside the end ring
EYE_FROM_SNOUT_OF_HEAD = 0.42
EYE_ANGLE = 0.18  # radians above the horizontal on the flank
EYE_BULGE = 0.32  # how far the eye centre stands out of the head, fraction of the eye radius
EYE_RING_RADII = (0.55, 0.9, 1.0)  # fractions of the eye radius; the last ring is the rim
EYE_RIM_SINK = 0.010  # the rim ring sits this far under the head surface (a steep, clean edge)
EYE_SEGMENTS = 14
CAUDAL_ROOT_INSET = 0.03
CAUDAL_COLUMNS = 8
CAUDAL_ROWS = 4
DORSAL_CENTRE = -0.03
DORSAL_COLUMNS = 6
DORSAL_ROWS = 3
DORSAL_EDGE_SAG = 0.15  # concave trailing edge, fraction of the dorsal height
FIN_ROOT_SINK = 0.012
PECTORAL_ANGLE = -0.45  # radians below the horizontal on the flank
PECTORAL_BEHIND_HEAD = 0.02
PECTORAL_ROOT_SINK = 0.012  # the root sits this far inside the flank
PECTORAL_DIRECTION = (0.35, -0.2, -1.0)
PECTORAL_HALF_WIDTH = (0.14, 0.20, 0.23, 0.19, 0.06)  # per row, fraction of the length

Vec = tuple[float, float, float]


class GeneratorError(Exception):
    """A failure with a message meant for the person running the generator."""


# --- small vector helpers (glTF frame: +X left of the fish, +Y up, +Z front) ---


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


def _norm(a: Vec) -> Vec:
    length = math.sqrt(_dot(a, a))
    return _mul(a, 1.0 / length)


def _smoothstep(t: float) -> float:
    t = min(max(t, 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def _signed_pow(value: float, exponent: float) -> float:
    return math.copysign(abs(value) ** exponent, value)


# --- parameters ---


def _reject_duplicates(pairs: list[tuple[str, object]]) -> dict[str, object]:
    table: dict[str, object] = {}
    for key, value in pairs:
        if key in table:
            raise GeneratorError(f"parameter file: key {key!r} appears twice")
        table[key] = value
    return table


def load_params(path: Path) -> dict[str, float]:
    """Read and validate the parameter file before any Blender work happens."""
    if not path.is_file():
        raise GeneratorError(f"parameter file not found: {path}")
    try:
        text = path.read_text(encoding="utf-8")
        data = json.loads(text, object_pairs_hook=_reject_duplicates)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise GeneratorError(f"parameter file is not valid JSON: {path}: {error}") from error
    if not isinstance(data, dict):
        raise GeneratorError(f"parameter file must hold a JSON object: {path}")
    unknown = sorted(set(data) - set(ALLOWED_KEYS))
    if unknown:
        raise GeneratorError(
            f"parameter file: unknown key(s) {', '.join(unknown)}; allowed: {', '.join(ALLOWED_KEYS)}"
        )
    missing = [key for key in ALLOWED_KEYS if key not in data]
    if missing:
        raise GeneratorError(f"parameter file: missing key(s) {', '.join(missing)}")
    params: dict[str, float] = {}
    for key, (low, high) in FLOAT_RANGES.items():
        value = data[key]
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise GeneratorError(f"parameter {key}: must be a number, got {value!r}")
        if not low <= value <= high:
            raise GeneratorError(f"parameter {key}: {value!r} is outside {low} .. {high}")
        params[key] = float(value)
    for key, (low, high) in COUNT_RANGES.items():
        value = data[key]
        if isinstance(value, bool) or not isinstance(value, int):
            raise GeneratorError(f"parameter {key}: must be an integer, got {value!r}")
        if not low <= value <= high:
            raise GeneratorError(f"parameter {key}: {value!r} is outside {low} .. {high}")
        params[key] = value
    if params["body_ring_segments"] % 2:
        raise GeneratorError(
            f"parameter body_ring_segments: {params['body_ring_segments']} must be even "
            "(the left and right flank mirror each other)"
        )
    if params["caudal_fork_depth_sl"] >= params["caudal_length_sl"]:
        raise GeneratorError(
            "parameter caudal_fork_depth_sl: must be below caudal_length_sl "
            f"({params['caudal_fork_depth_sl']} >= {params['caudal_length_sl']})"
        )
    return params


# --- body shape ---


class BodyShape:
    """Analytic body: a ring loft of superellipse sections from the tail base to the snout."""

    def __init__(self, params: dict[str, float]) -> None:
        self.height = params["body_height_sl"]
        self.width = params["body_width_sl"]
        self.nose_cap = params["head_length_sl"] * NOSE_CAP_OF_HEAD
        self.segments = int(params["body_ring_segments"])
        count = int(params["body_ring_count"])
        # cosine spacing: rings densest at both ends, so the rounded caps close smoothly
        self.rings = [0.5 * (1.0 - math.cos(math.pi * i / (count + 1))) for i in range(1, count + 1)]
        self.x_scale = 1.0
        self.y_scale = 1.0
        xs: list[float] = []
        ys: list[float] = []
        for s in self.rings:
            for j in range(self.segments):
                x, y, _ = self.ring_point(s, j)
                xs.append(x)
                ys.append(y)
        self.x_scale = self.width / (max(xs) - min(xs))
        self.y_scale = self.height / (max(ys) - min(ys))

    def _closure(self, s: float) -> float:
        factor = 1.0
        if s < TAIL_CAP:
            t = (TAIL_CAP - s) / TAIL_CAP
            factor *= math.sqrt(max(0.0, 1.0 - t * t))
        start = 1.0 - self.nose_cap
        if s > start:
            t = (s - start) / self.nose_cap
            factor *= math.sqrt(max(0.0, 1.0 - t * t))
        return factor

    @staticmethod
    def _profile(s: float, peduncle: float, peak: float, snout: float) -> float:
        if s < peak:
            return peduncle + (1.0 - peduncle) * _smoothstep((s - 0.06) / (peak - 0.06))
        t = (s - peak) / (1.0 - peak)
        return 1.0 - (1.0 - snout) * t**1.8

    def half_height(self, s: float) -> float:
        g = self._profile(s, PEDUNCLE_HEIGHT, DEEPEST_AT, SNOUT_HEIGHT)
        return 0.5 * self.height * g * self._closure(s) * self.y_scale

    def half_width(self, s: float) -> float:
        g = self._profile(s, PEDUNCLE_WIDTH, WIDEST_AT, SNOUT_WIDTH)
        return 0.5 * self.width * g * self._closure(s) * self.x_scale

    def centre(self, s: float) -> float:
        lift = 0.06 * _smoothstep((s - 0.55) / 0.45) - 0.025 * math.sin(math.pi * s)
        return self.height * lift * self.y_scale

    def point(self, s: float, phi: float) -> Vec:
        exponent = 2.0 / SECTION_EXPONENT
        x = self.half_width(s) * _signed_pow(math.cos(phi), exponent)
        y = self.centre(s) + self.half_height(s) * _signed_pow(math.sin(phi), exponent)
        return (x, y, s - 0.5)

    def phi(self, j: int) -> float:
        return math.pi / 2.0 - 2.0 * math.pi * j / self.segments

    def ring_point(self, s: float, j: int) -> Vec:
        """Ring vertex j (0 = top, clockwise seen from the front); the two flanks mirror exactly."""
        half = self.segments // 2
        j %= self.segments
        if j > half:
            x, y, z = self.point(s, self.phi(self.segments - j))
            return (-x, y, z)
        x, y, z = self.point(s, self.phi(j))
        if j in (0, half):
            x = 0.0
        return (x, y, z)

    def top(self, s: float) -> float:
        return self.centre(s) + self.half_height(s)

    def axis(self, s: float) -> Vec:
        return (0.0, self.centre(s), s - 0.5)

    def normal(self, s: float, phi: float) -> Vec:
        d = 1e-4
        along_phi = _sub(self.point(s, phi + d), self.point(s, phi - d))
        along_s = _sub(self.point(s + d, phi), self.point(s - d, phi))
        n = _norm(_cross(along_phi, along_s))
        if _dot(n, _sub(self.point(s, phi), self.axis(s))) < 0.0:
            n = _mul(n, -1.0)
        return n


# --- mesh data (pure Python, so it is deterministic and testable outside Blender) ---


class MeshData:
    """Vertices and faces in the glTF frame. Each face has a material, a cell and UV0 corners."""

    def __init__(self) -> None:
        self.vertices: list[Vec] = []
        self.faces: list[tuple[int, ...]] = []
        self.materials: list[int] = []  # 0 = body, 1 = fin
        self.cells: list[tuple[int, int]] = []
        self.uv0: list[tuple[tuple[float, float], ...]] = []

    def vertex(self, p: Vec) -> int:
        self.vertices.append(p)
        return len(self.vertices) - 1

    def face(
        self,
        corners: tuple[int, ...],
        uv: tuple[tuple[float, float], ...],
        material: int,
        cell: tuple[int, int],
        outward: Vec | None = None,
    ) -> None:
        """Adds a face; with ``outward`` the winding is flipped where needed to face that way."""
        if outward is not None and _dot(self._face_normal(corners), outward) < 0.0:
            corners = tuple(reversed(corners))
            uv = tuple(reversed(uv))
        self.faces.append(corners)
        self.uv0.append(uv)
        self.materials.append(material)
        self.cells.append(cell)

    def _face_normal(self, corners: tuple[int, ...]) -> Vec:
        n = (0.0, 0.0, 0.0)
        for k, index in enumerate(corners):
            a = self.vertices[index]
            b = self.vertices[corners[(k + 1) % len(corners)]]
            n = _add(n, _cross(a, b))
        return n

    def centre(self, corners: tuple[int, ...]) -> Vec:
        total = (0.0, 0.0, 0.0)
        for index in corners:
            total = _add(total, self.vertices[index])
        return _mul(total, 1.0 / len(corners))


def _body_cell(shape: BodyShape, j: int) -> tuple[int, int]:
    """Back, lateral stripe, flank or belly, from the mid-angle of segment j."""
    mid = math.sin(shape.phi(j) - math.pi / shape.segments)
    if mid >= 0.57:
        return CELL_BACK
    if mid > 0.26:
        return CELL_STRIPE
    if mid > -0.5:
        return CELL_FLANK
    return CELL_BELLY


def _uv_body(j: int, s: float, segments: int) -> tuple[float, float]:
    return (j / segments, 0.02 + 0.6 * s)


def build_body(data: MeshData, shape: BodyShape) -> None:
    m = shape.segments
    tail = data.vertex(shape.axis(0.0))
    rings: list[list[int]] = []
    for s in shape.rings:
        rings.append([data.vertex(shape.ring_point(s, j)) for j in range(m)])
    snout = data.vertex(shape.axis(1.0))
    first = shape.rings[0]
    last = shape.rings[-1]
    for j in range(m):
        k = (j + 1) % m
        cell = _body_cell(shape, j)
        pole_u = (j + 0.5) / m
        # tail fan
        corners = (tail, rings[0][k], rings[0][j])
        uv = ((pole_u, 0.02), _uv_body(j + 1, first, m), _uv_body(j, first, m))
        out = _sub(data.centre(corners), shape.axis(first + POLE_PROBE))
        data.face(corners, uv, 0, cell, out)
        # snout fan
        corners = (snout, rings[-1][j], rings[-1][k])
        uv = ((pole_u, 0.62), _uv_body(j, last, m), _uv_body(j + 1, last, m))
        out = _sub(data.centre(corners), shape.axis(last - POLE_PROBE))
        data.face(corners, uv, 0, cell, out)
    for i in range(len(rings) - 1):
        s0 = shape.rings[i]
        s1 = shape.rings[i + 1]
        for j in range(m):
            k = (j + 1) % m
            corners = (rings[i][j], rings[i][k], rings[i + 1][k], rings[i + 1][j])
            uv = (
                _uv_body(j, s0, m),
                _uv_body(j + 1, s0, m),
                _uv_body(j + 1, s1, m),
                _uv_body(j, s1, m),
            )
            out = _sub(data.centre(corners), shape.axis(0.5 * (s0 + s1)))
            data.face(corners, uv, 0, _body_cell(shape, j), out)


def build_eye(data: MeshData, shape: BodyShape, params: dict[str, float], side: int) -> None:
    """A round bump that follows the head surface; its rim ring sinks just under the skin.

    side: 1 right (+X), -1 left (the exact X mirror).
    """
    s_eye = 1.0 - params["head_length_sl"] * EYE_FROM_SNOUT_OF_HEAD
    radius = 0.5 * params["eye_diameter_sl"]
    d = 1e-4
    step = _sub(shape.point(s_eye, EYE_ANGLE + d), shape.point(s_eye, EYE_ANGLE - d))
    phi_per_unit = 2.0 * d / math.sqrt(_dot(step, step))
    bulge = EYE_BULGE * radius

    def at(rho: float, psi: float, height: float) -> Vec:
        s = s_eye + rho * radius * math.cos(psi)
        phi = EYE_ANGLE + rho * radius * math.sin(psi) * phi_per_unit
        p = _add(shape.point(s, phi), _mul(shape.normal(s, phi), height))
        return (p[0] * side, p[1], p[2])

    points: list[Vec] = [at(0.0, 0.0, bulge)]
    uvs: list[tuple[float, float]] = [(0.0, 0.0)]
    for r, rho in enumerate(EYE_RING_RADII):
        last = r == len(EYE_RING_RADII) - 1
        height = -EYE_RIM_SINK if last else bulge * math.sqrt(1.0 - rho * rho)
        for k in range(EYE_SEGMENTS):
            psi = 2.0 * math.pi * k / EYE_SEGMENTS
            points.append(at(rho, psi, height))
            uvs.append((rho * math.cos(psi), rho * math.sin(psi)))
    base = 0.10 if side == 1 else 0.27
    uvs = [(base + 0.07 * u, 0.76 + 0.07 * v) for u, v in uvs]
    indices = [data.vertex(p) for p in points]
    outward = shape.normal(s_eye, EYE_ANGLE)
    outward = (outward[0] * side, outward[1], outward[2])

    def ring_index(r: int, k: int) -> int:
        return 1 + (r - 1) * EYE_SEGMENTS + (k % EYE_SEGMENTS)

    def add(local: tuple[int, ...]) -> None:
        corners = tuple(indices[i] for i in local)
        data.face(corners, tuple(uvs[i] for i in local), 0, CELL_EYE, outward)

    for k in range(EYE_SEGMENTS):
        add((0, ring_index(1, k), ring_index(1, k + 1)))
    for r in range(1, len(EYE_RING_RADII)):
        for k in range(EYE_SEGMENTS):
            add((ring_index(r, k), ring_index(r, k + 1), ring_index(r + 1, k + 1), ring_index(r + 1, k)))


def _fin_grid(
    data: MeshData,
    grid: list[list[Vec]],
    uv_box: tuple[float, float, float, float],
    normal: Vec,
) -> None:
    """Quads over grid[row][column], all facing ``normal`` (the fin material is double-sided)."""
    rows = len(grid)
    columns = len(grid[0])
    u0, v0, u1, v1 = uv_box
    indices = [[data.vertex(p) for p in row] for row in grid]

    def uv(r: int, c: int) -> tuple[float, float]:
        return (u0 + (u1 - u0) * c / (columns - 1), v0 + (v1 - v0) * r / (rows - 1))

    for r in range(rows - 1):
        for c in range(columns - 1):
            local = ((r, c), (r, c + 1), (r + 1, c + 1), (r + 1, c))
            corners = tuple(indices[a][b] for a, b in local)
            data.face(corners, tuple(uv(a, b) for a, b in local), 1, CELL_FIN, normal)


def build_caudal(data: MeshData, shape: BodyShape, params: dict[str, float]) -> None:
    """Forked tail in the centre plane, two equal lobes, from inside the peduncle backwards."""
    s_root = CAUDAL_ROOT_INSET
    centre = shape.centre(s_root)
    root_half = 0.8 * shape.half_height(s_root)
    spread = 0.48 * shape.height
    length = params["caudal_length_sl"]
    fork = params["caudal_fork_depth_sl"]
    grid: list[list[Vec]] = []
    for r in range(CAUDAL_ROWS + 1):
        u = r / CAUDAL_ROWS
        row: list[Vec] = []
        for c in range(CAUDAL_COLUMNS + 1):
            v = -1.0 + 2.0 * c / CAUDAL_COLUMNS
            root = (0.0, centre + v * root_half, s_root - 0.5)
            trail_z = -0.5 - length + fork * (1.0 - abs(v) ** 1.4)
            trail = (0.0, centre + v * spread, trail_z)
            row.append(_add(root, _mul(_sub(trail, root), u)))
        grid.append(row)
    _fin_grid(data, grid, (0.38, 0.66, 0.62, 0.96), (1.0, 0.0, 0.0))


def build_dorsal(data: MeshData, shape: BodyShape, params: dict[str, float]) -> None:
    """Pointed dorsal fin on the centre line of the back, swept slightly backwards."""
    base = params["dorsal_base_sl"]
    height = params["dorsal_height_sl"]
    z_front = DORSAL_CENTRE + 0.5 * base
    z_back = DORSAL_CENTRE - 0.5 * base
    tip = (0.0, shape.top(z_front + 0.5) + height, z_front - 0.30 * base)
    rear = (0.0, shape.top(z_back + 0.5) + 0.3 * height, z_back - 0.06 * base)
    grid: list[list[Vec]] = []
    for r in range(DORSAL_ROWS + 1):
        lift = r / DORSAL_ROWS
        row: list[Vec] = []
        for c in range(DORSAL_COLUMNS + 1):
            t = c / DORSAL_COLUMNS
            z = z_front + t * (z_back - z_front)
            root = (0.0, shape.top(z + 0.5) - FIN_ROOT_SINK, z)
            edge = _add(tip, _mul(_sub(rear, tip), t))
            edge = (0.0, edge[1] - DORSAL_EDGE_SAG * height * math.sin(math.pi * t), edge[2])
            row.append(_add(root, _mul(_sub(edge, root), lift)))
        grid.append(row)
    _fin_grid(data, grid, (0.66, 0.66, 0.82, 0.96), (1.0, 0.0, 0.0))


def _pectoral_grid(shape: BodyShape, params: dict[str, float]) -> tuple[list[list[Vec]], Vec]:
    length = params["pectoral_length_sl"]
    s = 1.0 - params["head_length_sl"] - PECTORAL_BEHIND_HEAD
    normal = shape.normal(s, PECTORAL_ANGLE)
    root = _sub(shape.point(s, PECTORAL_ANGLE), _mul(normal, PECTORAL_ROOT_SINK))
    direction = _norm(PECTORAL_DIRECTION)
    up = (0.0, 1.0, 0.0)
    across = _norm(_sub(up, _mul(direction, _dot(direction, up))))
    rows = len(PECTORAL_HALF_WIDTH)
    grid: list[list[Vec]] = []
    for r in range(rows):
        u = r / (rows - 1)
        row: list[Vec] = []
        for v in (-1.0, 0.0, 1.0):
            reach = length * u * (1.0 - 0.1 * u**4 * abs(v))
            offset = v * PECTORAL_HALF_WIDTH[r] * length
            row.append(_add(_add(root, _mul(direction, reach)), _mul(across, offset)))
        grid.append(row)
    return grid, _cross(across, direction)


def build_pectorals(data: MeshData, shape: BodyShape, params: dict[str, float]) -> None:
    """A mirrored pair behind the gill cover, low on the flank; the left is the exact X mirror."""
    grid, facing = _pectoral_grid(shape, params)
    if _dot(facing, (1.0, 0.0, 0.0)) < 0.0:
        facing = _mul(facing, -1.0)
    _fin_grid(data, grid, (0.85, 0.66, 0.91, 0.96), facing)
    left = [[(-p[0], p[1], p[2]) for p in row] for row in grid]
    _fin_grid(data, left, (0.93, 0.66, 0.99, 0.96), (-facing[0], facing[1], facing[2]))


def build_fish(params: dict[str, float]) -> MeshData:
    shape = BodyShape(params)
    data = MeshData()
    build_body(data, shape)
    build_eye(data, shape, params, 1)
    build_eye(data, shape, params, -1)
    body_vertex_count = len(data.vertices)
    build_caudal(data, shape, params)
    build_dorsal(data, shape, params)
    build_pectorals(data, shape, params)
    # origin = centre of the bounding box of the body without fins (eyes included)
    body = data.vertices[:body_vertex_count]
    low = [min(p[i] for p in body) for i in range(3)]
    high = [max(p[i] for p in body) for i in range(3)]
    if abs((high[2] - low[2]) - 1.0) > 1e-9:
        raise GeneratorError(f"internal: body length is {high[2] - low[2]}, must be 1.0")
    offset = (0.5 * (low[0] + high[0]), 0.5 * (low[1] + high[1]), 0.5 * (low[2] + high[2]))
    data.vertices = [_sub(p, offset) for p in data.vertices]
    return data


# --- palette atlas ---


def atlas_png() -> bytes:
    """64 x 64 px, 8-bit RGB, row 0 at the top; deterministic (no Blender colour management)."""
    size = ATLAS_GRID * ATLAS_CELL_PX
    rows: list[bytes] = []
    for y in range(size):
        line = bytearray()
        for x in range(size):
            rgb = ATLAS_PALETTE[y // ATLAS_CELL_PX][x // ATLAS_CELL_PX]
            line += bytes(((rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF))
        rows.append(b"\x00" + bytes(line))

    def chunk(tag: bytes, payload: bytes) -> bytes:
        crc = zlib.crc32(tag + payload) & 0xFFFFFFFF
        return struct.pack(">I", len(payload)) + tag + payload + struct.pack(">I", crc)

    header = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(b"".join(rows), 9))
        + chunk(b"IEND", b"")
    )


def cell_uv(cell: tuple[int, int]) -> tuple[float, float]:
    """Blender UV1 of a cell centre. The glTF exporter flips V, so Godot UV2 row = PNG row."""
    column, row = cell
    return ((column + 0.5) / ATLAS_GRID, 1.0 - (row + 0.5) / ATLAS_GRID)


# --- Blender ---


def build_object(data: MeshData):  # noqa: ANN201 (bpy types)
    import bmesh  # noqa: PLC0415 (only inside Blender)
    import bpy  # noqa: PLC0415

    mesh = bpy.data.meshes.new(OBJECT_NAME)
    bm = bmesh.new()
    uv0 = bm.loops.layers.uv.new("UV0")
    uv1 = bm.loops.layers.uv.new("UV1")
    colour = bm.loops.layers.float_color.new("Color")
    # glTF (x, y, z) -> Blender (x, -z, y): a proper rotation, so the winding stays outward
    verts = [bm.verts.new((p[0], -p[2], p[1])) for p in data.vertices]
    bm.verts.ensure_lookup_table()
    for corners, uvs, material, cell in zip(
        data.faces, data.uv0, data.materials, data.cells, strict=True
    ):
        face = bm.faces.new([verts[i] for i in corners])
        face.material_index = material
        face.smooth = True
        atlas = cell_uv(cell)
        alpha = 1.0 if material == 1 else 0.0
        for loop, uv in zip(face.loops, uvs, strict=True):
            loop[uv0].uv = uv
            loop[uv1].uv = atlas
            loop[colour] = (1.0, 1.0, 1.0, alpha)
    bm.to_mesh(mesh)
    bm.free()

    names = [layer.name for layer in mesh.uv_layers]
    if names != ["UV0", "UV1"]:
        raise GeneratorError(f"internal: UV layers are {names}, must be ['UV0', 'UV1']")
    mesh.uv_layers["UV0"].active = True
    mesh.uv_layers["UV0"].active_render = True
    mesh.color_attributes.active_color_name = "Color"
    mesh.color_attributes.render_color_index = mesh.color_attributes.active_color_index

    body = bpy.data.materials.new("body")
    body.use_backface_culling = True
    fin = bpy.data.materials.new("fin")
    fin.use_backface_culling = False
    mesh.materials.append(body)
    mesh.materials.append(fin)

    obj = bpy.data.objects.new(OBJECT_NAME, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def export_glb(obj, path: Path) -> None:  # noqa: ANN001 (bpy type)
    import bpy  # noqa: PLC0415

    for other in bpy.context.scene.objects:
        other.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    result = bpy.ops.export_scene.gltf(
        filepath=str(path),
        check_existing=False,
        export_format="GLB",
        use_selection=True,
        export_texcoords=True,
        export_normals=True,
        export_tangents=False,
        export_vertex_color="ACTIVE",
        export_all_vertex_colors=False,
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
    if result != {"FINISHED"}:
        raise GeneratorError(f"glTF export failed: {result}")


# --- entry point ---


def parse_args(argv: list[str]) -> argparse.Namespace:
    script_args = argv[argv.index("--") + 1 :] if "--" in argv else []
    parser = argparse.ArgumentParser(
        prog="generate_fish.py",
        description="Generate the proof fish .glb and its palette atlas (#21).",
    )
    parser.add_argument("--params", type=Path, default=DEFAULT_PARAMS)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    return parser.parse_args(script_args)


def _remove(path: Path) -> None:
    if path.is_file():
        path.unlink()


def swap_in_pair(
    new_glb: Path,
    glb: Path,
    new_atlas: Path,
    atlas: Path,
    rename: Callable[[Path, Path], None] = os.replace,
) -> None:
    """Move ``new_glb`` to ``glb`` and ``new_atlas`` to ``atlas`` as a pair.

    The old ``.glb`` is copied to a hidden backup first. If the ``.glb`` rename fails, nothing has
    changed. If the atlas rename fails, the old ``.glb`` is restored from the backup, or on a first
    run the new ``.glb`` is deleted, so the folder never holds a new ``.glb`` beside an old atlas.
    If that rollback fails too, the backup is kept on disk and the error names it.

    ``rename`` exists for the local unittest only; ``run()`` never passes it, so normal runs always
    use ``os.replace``. Raises ``GeneratorError`` with a message that names the failed file.
    """
    backup = glb.with_name(f".{glb.stem}.bak.glb")
    if backup.exists():
        raise GeneratorError(
            f"a backup from an earlier failed run exists: {backup}; "
            f"restore it to {glb.name} or delete it, then run again"
        )
    had_old = glb.is_file()
    keep_backup = False
    try:
        if had_old:
            try:
                # copyfile, not copy2: a read-only .glb must not give a read-only backup.
                shutil.copyfile(glb, backup)
            except OSError as error:
                raise GeneratorError(f"could not back up {glb}: {error}") from error
        try:
            rename(new_glb, glb)
        except OSError as error:
            raise GeneratorError(
                f"could not replace {glb}: {error}; the old pair is unchanged"
            ) from error
        try:
            rename(new_atlas, atlas)
        except OSError as error:
            try:
                if had_old:
                    rename(backup, glb)
                    undone = f"restored the old {glb.name}"
                else:
                    glb.unlink()
                    undone = f"removed the new {glb.name}"
            except OSError as rollback_error:
                keep_backup = had_old
                if had_old:
                    kept = f"the old {glb.name} is kept as {backup}"
                else:
                    kept = f"the new {glb.name} is left without its atlas"
                raise GeneratorError(
                    f"could not replace {atlas}: {error}; the rollback of {glb} failed too: "
                    f"{rollback_error}; {kept}"
                ) from error
            raise GeneratorError(f"could not replace {atlas}: {error}; {undone}") from error
    finally:
        if not keep_backup and backup.is_file():
            backup.unlink()


def run(argv: list[str]) -> None:
    args = parse_args(argv)
    params = load_params(args.params.resolve())
    out: Path = args.out.resolve()
    if out.suffix.lower() != ".glb":
        raise GeneratorError(f"--out must name a .glb file: {out}")
    folder = out.parent
    if not folder.is_dir():
        raise GeneratorError(f"--out folder does not exist: {folder}")
    data = build_fish(params)  # geometry errors surface before anything is written

    import bpy  # noqa: PLC0415

    bpy.ops.wm.read_factory_settings(use_empty=True)
    obj = build_object(data)

    atlas_final = folder / ATLAS_NAME
    tmp_glb = folder / f".{out.stem}.tmp.glb"
    tmp_atlas = folder / f".{atlas_final.stem}.tmp.png"
    try:
        try:
            with tmp_atlas.open("wb") as handle:  # also the write probe for the folder
                handle.write(atlas_png())
        except OSError as error:
            raise GeneratorError(f"--out folder is not writable: {folder} ({error})") from error
        try:
            export_glb(obj, tmp_glb)
        except RuntimeError as error:
            raise GeneratorError(f"glTF export failed: {error}") from error
        for written, magic in ((tmp_glb, b"glTF"), (tmp_atlas, b"\x89PNG")):
            if not written.is_file() or written.stat().st_size == 0:
                raise GeneratorError(f"export wrote no file: {written}")
            with written.open("rb") as handle:
                if handle.read(4) != magic:
                    raise GeneratorError(f"export wrote a broken file: {written}")
        swap_in_pair(tmp_glb, out, tmp_atlas, atlas_final)
    finally:
        _remove(tmp_glb)
        _remove(tmp_atlas)
    triangles = sum(len(face) - 2 for face in data.faces)
    print(f"generate_fish: wrote {out} ({triangles} triangles) and {atlas_final}")


def main() -> int:
    try:
        run(sys.argv)
    except GeneratorError as error:
        print(f"generate_fish: error: {error}", file=sys.stderr, flush=True)
        return 1
    except SystemExit as stop:  # argparse usage errors
        return stop.code if isinstance(stop.code, int) else 1
    except BaseException as error:  # noqa: BLE001 (background Blender exits 0 otherwise)
        print(
            f"generate_fish: error: unexpected {type(error).__name__}: {error}",
            file=sys.stderr,
            flush=True,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
