"""Generate the starter decoration set (#157): river stone, driftwood branch and clay amphora, and
the shared decor palette atlas, headless in Blender 5.2.

Usage (the arguments after ``--`` belong to this script):

    blender --background --python tools/blender/generate_decor.py -- \
        [--params tools/blender/params/decor.json] [--out-dir game/assets/items]

- ``--params``: the parameter file (default ``tools/blender/params/decor.json``).
- ``--out-dir``: an existing folder (default ``game/assets/items``). The script writes
  ``models/river_stone.glb``, ``models/driftwood_branch.glb``, ``models/clay_amphora.glb`` (the
  ``models`` sub-folder is created when missing) and ``decor_palette_atlas.png`` as one group
  (``blender_common.write_group``): the folders hold the old group or the new group.
- Running without arguments regenerates every committed file. Defaults are resolved from the
  location of this script, so the working directory does not matter.
- One line per model reports the triangle count and the size; the amphora line adds the AC 22
  measurements (narrowest inner diameter, inside depth, non-manifold edges counted by Blender
  ``bmesh``, connected parts, solid clay volume).

All geometry is built in plain Python (``build_river_stone``, ``build_driftwood_branch``,
``build_clay_amphora`` return a ``blender_common.MeshData``), so the local unittest
``test_generate_decor.py`` checks it without Blender. Blender only builds the object, sets the
normals and exports. No modifier, no boolean, no unseeded random.

Frame and size (docs/art-style.md, "Generator conventions"; #157 AC 5): 1 unit = 1 m, glTF +Y up,
front +Z, width x, height y, depth z. Each mesh is scaled per axis so its bounds equal the size in
the parameter file (the catalog ``footprint_cm``) exactly, the lowest point is y = 0 and the x/z
bounding box is centred on the origin. The shapes are designed at the committed sizes, so this fit
is (almost) the identity for them.

Look (docs/art-style.md "Shading", "Colouring", "Hardscape and substrate"):

- One material ``decor_palette`` for every model (Godot maps it to one shared material). Every
  face of UV1 collapses onto the centre of the model's own cell of ``decor_palette``
  (stone ``STONE_GRANITE``, branch ``WOOD_DRIFT``, amphora ``TERRACOTTA``). UV0 is a planar
  projection in metres (no mask or gradient texture uses it).
- Vertex colours (``COLOR_0``, RGB = shade multiplier, alpha 0 = opaque): crevice and contact
  darkening on the stone, a lengthwise grain gradient on the branch, a darkening inside the
  amphora mouth.
- Normals: the stone is smooth by angle (``blender_common.SHARP_ANGLE_DEG``), so only the rim of
  its flat underside is a split edge; the branch and the amphora are smooth everywhere.

The three shapes:

- ``river_stone``: a grey granite-type river cobble. A squashed sphere (wider than tall, widest a
  little above half height) with a seeded low-frequency form (``stone_seed``), cut by a flat
  underside so it sits level. The underside rim meets the sides at ``STONE_RIM_TILT_DEG``, above
  the 30 degree split angle, and no other edge reaches it (checked; a seed that breaks this is
  rejected).
- ``driftwood_branch``: one smooth curved piece of barkless Malaysian-type driftwood, no side
  branches. A tube swept along a gentle C-curve in the x-z plane with a flattened-bottom
  cross-section, thicker at the root end, which sweeps up a little; rounded caps close both ends.
  BA decision Q20: no cross-section (outside the 1.5 cm of each end) has its lowest point at or
  above ``BRANCH_GAP_MAX_CM`` above y = 0, so the model shows no gap a fish can enter (checked).
- ``clay_amphora``: a small two-handled terracotta amphora on a flat foot. One lathe of a single
  closed profile (outer bottom centre, foot, belly, shoulder, neck, rounded lip, inner wall, inner
  floor centre), ``AMPHORA_SEGMENTS`` around, so the shell is watertight and consistently wound by
  construction. The inner wall is the outer profile offset inward by ``amphora_wall_cm``; its
  radius never goes below ``amphora_opening_cm / 2`` (measured flat to flat of the polygon), and
  the inner floor lies ``amphora_inside_depth_cm`` below the top of the rim (#157 AC 22, BA
  decision Q21). Each handle is a tube that starts and ends on a hole of two wall quads (one
  quad wide, two tall) at the neck and at the shoulder, with the hole loops as its end rings: no
  boolean, no loose part, one connected 2-manifold. The handles reach x = +/- width / 2.

Parameter file: a JSON object with exactly these keys (sizes in cm). Values outside the range are
rejected with a message that names the key.

    stone_width_cm, stone_height_cm, stone_depth_cm          SIZE_MIN_CM .. SIZE_MAX_CM
    branch_width_cm, branch_height_cm, branch_depth_cm       SIZE_MIN_CM .. SIZE_MAX_CM
    amphora_width_cm, amphora_height_cm, amphora_depth_cm    SIZE_MIN_CM .. SIZE_MAX_CM
    stone_seed                 integer 0 .. 2147483647
    amphora_opening_cm         3.5 .. 6.0   narrowest inner diameter of the neck (AC 22: >= 3.5)
    amphora_inside_depth_cm    8.0 .. 14.0  top of the rim to the inner floor (AC 22: >= 8)
    amphora_wall_cm            0.5 .. 0.7   wall thickness (AC 22: about 0.6)

Cross-key rules: the inside depth plus one wall fits the amphora height, and the opening plus two
walls is narrower than the amphora body (its depth).

Exit code 0 on success, 1 on any error.
"""

from __future__ import annotations

import argparse
import math
import random
import sys
from collections.abc import Callable
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import blender_common  # noqa: E402
import decor_palette  # noqa: E402
from blender_common import GeneratorError, MeshData  # noqa: E402

PROG = "generate_decor"
REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_PARAMS = REPO_ROOT / "tools" / "blender" / "params" / "decor.json"
DEFAULT_OUT_DIR = REPO_ROOT / "game" / "assets" / "items"
MODELS_DIR = "models"
ATLAS_FILE = "decor_palette_atlas.png"
MATERIAL = "decor_palette"
STONE_ID = "river_stone"
BRANCH_ID = "driftwood_branch"
AMPHORA_ID = "clay_amphora"

SIZE_MIN_CM = 0.5
SIZE_MAX_CM = 60.0
SEED_KEY = "stone_seed"
SEED_MAX = 2**31 - 1
FLOAT_RANGES: dict[str, tuple[float, float]] = {
    **{
        f"{item}_{axis}_cm": (SIZE_MIN_CM, SIZE_MAX_CM)
        for item in ("stone", "branch", "amphora")
        for axis in ("width", "height", "depth")
    },
    "amphora_opening_cm": (3.5, 6.0),
    "amphora_inside_depth_cm": (8.0, 14.0),
    "amphora_wall_cm": (0.5, 0.7),
}

CM = 0.01  # metres per centimetre

# --- river stone: fixed shape constants (not tuning knobs of the parameter file) ---

STONE_SEGMENTS = 28  # around the vertical axis
STONE_RINGS = 14  # rings below the top pole; the last one is the rim of the flat underside
STONE_UNDERSIDE_SHARE = 0.68  # underside rim radius / stone half-size
STONE_RIM_TILT_DEG = 40.0  # side surface at the rim, measured from the flat underside
STONE_RIM_SPLIT_MIN_DEG = 32.0  # every rim edge must split by at least this (> 30, the split)
STONE_SMOOTH_MAX_DEG = 27.0  # every other edge stays below this (< 30, smooth)
# Seeded low-frequency form: (waves across the stone, relative amplitude).
STONE_WAVES = ((1.0, 0.045), (1.6, 0.025), (2.4, 0.012))
STONE_CAVITY_SHADE = 0.84  # vertex shade of the most concave spot (1 = the most convex)
STONE_CONTACT_SHADE = 0.78  # vertex shade where the stone meets the ground
STONE_CONTACT_SHARE = 0.4  # contact darkening fades out at this share of the height
STONE_MOTTLE = 0.03  # +/- seeded per-vertex variation (granite mottling)

# --- driftwood branch ---

BRANCH_SIDES = 12  # around the tube; side 9 (270 degrees) is the lowest point of a section
BRANCH_RINGS = 34  # body rings from the root end (t = 0) to the tip (t = 1)
BRANCH_CAP_RINGS = 3  # rings of each rounded end cap before its pole
BRANCH_ROOT_HALF_HEIGHT = 0.36  # share of the item height
BRANCH_TIP_HALF_HEIGHT = 0.2
BRANCH_ROOT_HALF_WIDTH = 0.29  # share of the item depth
BRANCH_TIP_HALF_WIDTH = 0.19
BRANCH_LIFT = 0.19  # the root end's underside rises this share of the item height
BRANCH_LIFT_SPAN = 0.34  # ... and is back on the bed at this share of the length
BRANCH_BOW = 0.45  # C-curve sag, share of the item depth
BRANCH_BOW_SKEW = 0.18  # second harmonic, makes the curve asymmetric
BRANCH_FLAT_BOTTOM = 0.55  # exponent on the lower half-section (< 1 flattens the underside)
BRANCH_CAP_LENGTH = 0.8  # cap length / the smaller half-size at that end
BRANCH_GAP_MAX_CM = 2.0  # Q20: lowest point of every cross-section stays below this
BRANCH_GAP_MARGIN_CM = 0.1  # the generator demands this much margin under the limit
BRANCH_END_SKIP_CM = 1.5  # the Q20 check skips this much at each rounded end

# --- clay amphora ---

AMPHORA_SEGMENTS = 16  # lathe segments; vertices sit at (k + 0.5) x 22.5 degrees
# Outer profile (radius, height) in cm for the nominal 9 x 14 x 8 cm amphora (body diameter 8,
# height 14); scaled by amphora_depth_cm / 8 and amphora_height_cm / 14. From the foot edge up to
# the start of the lip; the outer bottom centre is added on the axis.
AMPHORA_NOMINAL_DEPTH_CM = 8.0
AMPHORA_NOMINAL_HEIGHT_CM = 14.0
AMPHORA_OUTER_CM = (
    (1.9, 0.0),  # index 0: edge of the flat foot
    (2.15, 0.15),
    (2.3, 0.5),
    (2.55, 1.0),
    (3.0, 1.8),
    (3.45, 2.8),
    (3.78, 3.9),
    (3.96, 5.0),
    (4.0, 6.0),  # widest point of the belly
    (3.94, 7.0),
    (3.75, 7.9),
    (3.42, 8.7),  # index 11: lower handle hole, bottom ring
    (3.0, 9.4),
    (2.68, 10.0),  # index 13: lower handle hole, top ring
    (2.56, 10.6),
    (2.55, 11.2),
    (2.55, 11.8),  # index 16: upper handle hole, bottom ring
    (2.6, 12.4),
    (2.68, 13.0),  # index 18: upper handle hole, top ring
    (2.8, 13.5),
)
AMPHORA_LOWER_HOLE = 11  # index into AMPHORA_OUTER_CM of the bottom ring of the hole
AMPHORA_UPPER_HOLE = 16
# The inner wall is the offset of these outer points (every point at the neck, where the wall is
# concave and a skipped point would thin it; every other point lower down, where skipping only
# thickens the wall and the inside is dark).
AMPHORA_INNER_FROM = (4, 6, 8, 10, 12, 13, 14, 15, 16, 17, 18, 19)
AMPHORA_LIP_STEPS = 3  # half-circle of the rounded lip, in this many steps
AMPHORA_FLOOR_FILLET_CM = 0.3  # the inner floor meets the inner wall over this much
AMPHORA_HANDLE_STEPS = 8  # tube segments of one handle
AMPHORA_HANDLE_HALF_WIDTH_CM = 0.42  # along z, the strap width / 2
AMPHORA_HANDLE_HALF_THICKNESS_CM = 0.3
AMPHORA_HANDLE_LOWER_REACH = 0.8  # lower Bezier handle length / upper one
AMPHORA_BASE_SHADE = 0.82  # outer vertex shade at the foot (contact)
AMPHORA_BASE_SHADE_SHARE = 0.25  # fades out at this share of the height
AMPHORA_MOUTH_SHADE = 0.95  # inner wall just below the lip
AMPHORA_INNER_SHADE = 0.4  # inner wall deep inside and the inner floor
AMPHORA_INNER_FADE = 0.6  # share of the inside depth over which the inside darkens

Vec = tuple[float, float, float]
Rgba = tuple[float, float, float, float]


# --- parameters ---


def load_params(path: Path) -> dict[str, float]:
    """Reads and validates ``decor.json`` before any Blender work happens. Raises
    ``GeneratorError`` with a message that names the key to change."""
    data = blender_common.load_json_object(path)
    blender_common.check_keys(data, (*FLOAT_RANGES, SEED_KEY))
    params: dict[str, float] = {}
    for key, (low, high) in FLOAT_RANGES.items():
        params[key] = blender_common.read_float(data, key, low, high)
    seed = data[SEED_KEY]
    if isinstance(seed, bool) or not isinstance(seed, int) or not 0 <= seed <= SEED_MAX:
        raise GeneratorError(
            f"parameter {SEED_KEY}: must be an integer 0 .. {SEED_MAX}, got {seed!r}"
        )
    params[SEED_KEY] = seed
    req = blender_common.require
    req(
        params["amphora_inside_depth_cm"] + params["amphora_wall_cm"]
        <= params["amphora_height_cm"],
        "amphora_inside_depth_cm",
        f"{params['amphora_inside_depth_cm']} plus one wall must fit the amphora height "
        f"({params['amphora_height_cm']})",
    )
    req(
        params["amphora_opening_cm"] + 2.0 * params["amphora_wall_cm"]
        < params["amphora_depth_cm"],
        "amphora_opening_cm",
        f"{params['amphora_opening_cm']} plus two walls must be narrower than the amphora body "
        f"(amphora_depth_cm {params['amphora_depth_cm']})",
    )
    return params


# --- small helpers ---


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


def _unit(a: Vec) -> Vec:
    length = math.sqrt(_dot(a, a))
    if length == 0.0:
        raise GeneratorError("internal: zero-length vector")
    return _mul(a, 1.0 / length)


def _mean(points: list[Vec]) -> Vec:
    total = (0.0, 0.0, 0.0)
    for point in points:
        total = _add(total, point)
    return _mul(total, 1.0 / len(points))


def _smoothstep(edge0: float, edge1: float, x: float) -> float:
    t = min(1.0, max(0.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def _lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def _place(points: list[Vec], size_cm: tuple[float, float, float]) -> list[Vec]:
    """Points in cm -> metres, scaled per axis so the bounds equal ``size_cm``; the lowest point
    is y = 0 and the x/z bounding box is centred on the origin."""
    low = [min(p[i] for p in points) for i in range(3)]
    high = [max(p[i] for p in points) for i in range(3)]
    scale = [size_cm[i] * CM / (high[i] - low[i]) for i in range(3)]
    centre_x = (low[0] + high[0]) / 2.0
    centre_z = (low[2] + high[2]) / 2.0
    return [
        ((p[0] - centre_x) * scale[0], (p[1] - low[1]) * scale[1], (p[2] - centre_z) * scale[2])
        for p in points
    ]


def _mesh(points: list[Vec]) -> MeshData:
    data = MeshData()
    for point in points:
        data.vertex(point)
    return data


def edge_faces(data: MeshData) -> dict[tuple[int, int], list[int]]:
    """Undirected edge -> the faces that use it."""
    table: dict[tuple[int, int], list[int]] = {}
    for index, face in enumerate(data.faces):
        for k, a in enumerate(face):
            b = face[(k + 1) % len(face)]
            table.setdefault((min(a, b), max(a, b)), []).append(index)
    return table


def dihedral_degrees(data: MeshData) -> dict[tuple[int, int], float]:
    """Angle between the normals of the two faces of every edge with exactly two faces."""
    normals = [_unit(data.face_normal(face)) for face in data.faces]
    result: dict[tuple[int, int], float] = {}
    for edge, faces in edge_faces(data).items():
        if len(faces) == 2:
            cosine = max(-1.0, min(1.0, _dot(normals[faces[0]], normals[faces[1]])))
            result[edge] = math.degrees(math.acos(cosine))
    return result


def signed_volume(data: MeshData) -> float:
    """Volume enclosed by a closed, outward-wound mesh (cubic metres)."""
    total = 0.0
    for face in data.faces:
        a = data.vertices[face[0]]
        for k in range(1, len(face) - 1):
            total += _dot(a, _cross(data.vertices[face[k]], data.vertices[face[k + 1]])) / 6.0
    return total


def components(data: MeshData) -> int:
    parent = list(range(len(data.vertices)))

    def find(i: int) -> int:
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for face in data.faces:
        for index in face[1:]:
            parent[find(index)] = find(face[0])
    return len({find(i) for i in range(len(data.vertices))})


# --- river stone ---


def build_river_stone(p: dict[str, float]) -> MeshData:
    """The river cobble: a seeded squashed sphere with a flat underside (see the module text)."""
    width, height, depth = p["stone_width_cm"], p["stone_height_cm"], p["stone_depth_cm"]
    half_x, half_z = width / 2.0, depth / 2.0
    # The rim of the underside sits at the angle alpha from the bottom of the lower half-ellipse;
    # its half-height is chosen so the side meets the underside at STONE_RIM_TILT_DEG.
    alpha = math.asin(STONE_UNDERSIDE_SHARE)
    lower = half_x * math.tan(math.radians(STONE_RIM_TILT_DEG)) / math.tan(alpha)
    below = lower * math.cos(alpha)
    upper = height - below
    if upper <= 0.0:
        raise GeneratorError("internal: the stone underside leaves no upper half")

    def polar_of(turn_of_normal: float) -> float:
        # polar angle of the profile point whose normal is turn_of_normal from straight up, so
        # the rings follow the curvature (even normal steps, no crowding at the flat top)
        if turn_of_normal <= math.pi / 2.0:
            return math.atan2(half_x * math.sin(turn_of_normal), upper * math.cos(turn_of_normal))
        down = math.pi - turn_of_normal
        return math.pi - math.atan2(half_x * math.sin(down), lower * math.cos(down))

    rim_normal = math.pi - math.radians(STONE_RIM_TILT_DEG)

    rng = random.Random(int(p[SEED_KEY]))
    waves: list[tuple[Vec, float, float, float]] = []
    for frequency, amplitude in STONE_WAVES:
        y = rng.uniform(-1.0, 1.0)
        turn = rng.uniform(0.0, 2.0 * math.pi)
        r = math.sqrt(max(0.0, 1.0 - y * y))
        axis = (r * math.cos(turn), y, r * math.sin(turn))
        waves.append((axis, frequency, rng.uniform(0.0, 2.0 * math.pi), amplitude))

    def form(direction: Vec) -> float:
        return 1.0 + sum(
            amp * math.sin(math.pi * freq * _dot(direction, axis) + phase)
            for axis, freq, phase, amp in waves
        )

    def surface(polar: float, turn: float) -> Vec:
        direction = (
            math.sin(polar) * math.cos(turn),
            math.cos(polar),
            math.sin(polar) * math.sin(turn),
        )
        semi_y = upper if polar <= math.pi / 2.0 else lower
        base = (half_x * direction[0], semi_y * direction[1], half_z * direction[2])
        return _mul(base, form(direction))

    points: list[Vec] = [surface(0.0, 0.0)]  # top pole
    rings: list[list[int]] = []
    for ring in range(1, STONE_RINGS + 1):
        polar = polar_of(rim_normal * ring / STONE_RINGS)
        row = []
        for k in range(STONE_SEGMENTS):
            row.append(len(points))
            points.append(surface(polar, 2.0 * math.pi * k / STONE_SEGMENTS))
        rings.append(row)
    rim = rings[-1]
    cut = sum(points[i][1] for i in rim) / len(rim)
    for i in rim:
        points[i] = (points[i][0], cut, points[i][2])
    centre = _mean([points[i] for i in rim])
    if any(point[1] <= cut + 1e-9 for point in points[: rim[0]]):
        raise GeneratorError(f"parameter {SEED_KEY}: the stone reaches below its flat underside")
    bottom = len(points)
    points.append((centre[0], cut, centre[2]))

    data = _mesh(_place(points, (width, height, depth)))
    middle = _mul(_add(data.bounds()[0], data.bounds()[1]), 0.5)
    cell = decor_palette.STONE_GRANITE

    def side(corners: tuple[int, ...]) -> None:
        data.face(corners, cell, _sub(data.centre(corners), middle))

    for k in range(STONE_SEGMENTS):
        n = (k + 1) % STONE_SEGMENTS
        side((0, rings[0][k], rings[0][n]))
        for upper_row, lower_row in zip(rings, rings[1:], strict=False):
            side((upper_row[k], lower_row[k], lower_row[n], upper_row[n]))
        data.face((bottom, rim[n], rim[k]), cell, (0.0, -1.0, 0.0))

    _check_stone_edges(data, set(rim))
    data.colours = _stone_shades(data, rng)
    return data


def _check_stone_edges(data: MeshData, rim: set[int]) -> None:
    """Shading rule (AC 7): only the underside rim splits, and all of it."""
    for (a, b), angle in dihedral_degrees(data).items():
        on_rim = a in rim and b in rim
        if on_rim and angle < STONE_RIM_SPLIT_MIN_DEG:
            raise GeneratorError(
                f"parameter {SEED_KEY}: the underside rim splits by only {angle:.1f} degrees"
            )
        if not on_rim and angle > STONE_SMOOTH_MAX_DEG:
            raise GeneratorError(
                f"parameter {SEED_KEY}: a stone edge bends by {angle:.1f} degrees (hard edge)"
            )


def _stone_shades(data: MeshData, rng: random.Random) -> list[Rgba]:
    """Crevice darkening (less convex = darker), contact darkening and a faint mottle."""
    neighbours: list[set[int]] = [set() for _ in data.vertices]
    normals: list[Vec] = [(0.0, 0.0, 0.0)] * len(data.vertices)
    for face in data.faces:
        normal = data.face_normal(face)
        for k, a in enumerate(face):
            neighbours[a].add(face[(k + 1) % len(face)])
            neighbours[a].add(face[k - 1])
            normals[a] = _add(normals[a], normal)
    convexity: list[float] = []
    for index, point in enumerate(data.vertices):
        around = [data.vertices[i] for i in sorted(neighbours[index])]
        offset = _sub(point, _mean(around))
        spread = sum(math.dist(point, q) for q in around) / len(around)
        convexity.append(_dot(offset, _unit(normals[index])) / spread)
    ordered = sorted(convexity)
    low = ordered[len(ordered) // 10]
    high = ordered[(len(ordered) * 9) // 10]
    height = data.bounds()[1][1]
    shades: list[Rgba] = []
    for index, point in enumerate(data.vertices):
        cavity = _lerp(STONE_CAVITY_SHADE, 1.0, _smoothstep(low, high, convexity[index]))
        contact = _lerp(
            STONE_CONTACT_SHADE, 1.0, _smoothstep(0.0, STONE_CONTACT_SHARE * height, point[1])
        )
        mottle = 1.0 + rng.uniform(-STONE_MOTTLE, STONE_MOTTLE)
        shade = min(1.0, cavity * contact * mottle)
        shades.append((shade, shade, shade, 0.0))
    return shades


# --- driftwood branch ---


def build_driftwood_branch(p: dict[str, float]) -> MeshData:
    """The driftwood branch: a swept tube with rounded ends (see the module text)."""
    length, height, depth = p["branch_width_cm"], p["branch_height_cm"], p["branch_depth_cm"]

    def half_height(t: float) -> float:
        base = _lerp(BRANCH_ROOT_HALF_HEIGHT, BRANCH_TIP_HALF_HEIGHT, t**0.75) * height
        return base * (1.0 + 0.05 * math.sin(2.0 * math.pi * 1.7 * t + 0.6))

    def half_width(t: float) -> float:
        base = _lerp(BRANCH_ROOT_HALF_WIDTH, BRANCH_TIP_HALF_WIDTH, t**0.75) * depth
        return base * (1.0 + 0.06 * math.sin(2.0 * math.pi * 1.3 * t + 1.9))

    def lift(t: float) -> float:
        return BRANCH_LIFT * height * (1.0 - _smoothstep(0.0, BRANCH_LIFT_SPAN, t))

    bow = BRANCH_BOW * depth

    def path(t: float) -> Vec:
        x = (t - 0.5) * length
        z = bow * (math.sin(math.pi * t) + BRANCH_BOW_SKEW * math.sin(2.0 * math.pi * t))
        return (x, lift(t) + half_height(t), z)

    def tangent(t: float) -> Vec:
        step = 1e-4
        ahead = path(min(1.0, t + step))
        behind = path(max(0.0, t - step))
        return _unit((ahead[0] - behind[0], 0.0, ahead[2] - behind[2]))

    def lower(angle: float) -> float:
        s = math.sin(angle)
        return s if s >= 0.0 else -(abs(s) ** BRANCH_FLAT_BOTTOM)

    def section(t: float, shrink: float, centre: Vec) -> list[Vec]:
        forward = tangent(t)
        across = (-forward[2], 0.0, forward[0])
        w = half_width(t) * shrink
        h = half_height(t) * shrink
        ring = []
        for k in range(BRANCH_SIDES):
            angle = 2.0 * math.pi * k / BRANCH_SIDES
            offset = _add(_mul(across, w * math.cos(angle)), (0.0, h * lower(angle), 0.0))
            ring.append(_add(centre, offset))
        return ring

    points: list[Vec] = []
    shade_of: list[float] = []
    rings: list[list[int]] = []

    def add_ring(ring: list[Vec], t: float, end_grain: float) -> None:
        row = []
        for k, point in enumerate(ring):
            angle = 2.0 * math.pi * k / BRANCH_SIDES
            row.append(len(points))
            points.append(point)
            shade_of.append(_branch_shade(t, angle, end_grain))
        rings.append(row)

    def cap(t: float, outward: Vec) -> tuple[list[tuple[list[Vec], float]], Vec]:
        reach = BRANCH_CAP_LENGTH * min(half_width(t), half_height(t))
        steps = []
        for m in range(1, BRANCH_CAP_RINGS + 1):
            angle = 0.5 * math.pi * m / (BRANCH_CAP_RINGS + 1)
            centre = _add(path(t), _mul(outward, reach * math.sin(angle)))
            steps.append((section(t, math.cos(angle), centre), math.sin(angle)))
        return steps, _add(path(t), _mul(outward, reach))

    root_steps, root_pole = cap(0.0, _mul(tangent(0.0), -1.0))
    for ring, grain in reversed(root_steps):
        add_ring(ring, 0.0, grain)
    for j in range(BRANCH_RINGS):
        t = j / (BRANCH_RINGS - 1)
        add_ring(section(t, 1.0, path(t)), t, 0.0)
    tip_steps, tip_pole = cap(1.0, tangent(1.0))
    for ring, grain in tip_steps:
        add_ring(ring, 1.0, grain)
    poles = (len(points), len(points) + 1)
    points.extend((root_pole, tip_pole))
    shade_of.extend((_branch_shade(0.0, 0.0, 1.0), _branch_shade(1.0, 0.0, 1.0)))

    data = _mesh(_place(points, (length, height, depth)))
    centres = [_mean([data.vertices[i] for i in row]) for row in rings]
    cell = decor_palette.WOOD_DRIFT
    for j in range(len(rings) - 1):
        middle = _mul(_add(centres[j], centres[j + 1]), 0.5)
        for k in range(BRANCH_SIDES):
            n = (k + 1) % BRANCH_SIDES
            corners = (rings[j][k], rings[j][n], rings[j + 1][n], rings[j + 1][k])
            data.face(corners, cell, _sub(data.centre(corners), middle))
    ends = ((poles[0], rings[0], centres[0]), (poles[1], rings[-1], centres[-1]))
    for pole, row, centre in ends:
        for k in range(BRANCH_SIDES):
            n = (k + 1) % BRANCH_SIDES
            corners = (pole, row[k], row[n])
            data.face(corners, cell, _sub(data.centre(corners), centre))
    _check_branch_gap(data)
    data.colours = [(s, s, s, 0.0) for s in shade_of]
    return data


def _branch_shade(t: float, angle: float, end_grain: float) -> float:
    """Grain gradient along the length, faint streaks around, a darker underside and end grain."""
    along = 0.9 + 0.1 * math.cos(2.0 * math.pi * 1.3 * t + 0.4)
    streaks = 0.94 + 0.06 * math.cos(3.0 * angle + 5.0 * t)
    underside = 0.78 + 0.22 * (0.5 + 0.5 * math.sin(angle))
    ends = _lerp(1.0, 0.72, end_grain)
    return along * streaks * underside * ends


def lowest_under(data: MeshData, x: float) -> float | None:
    """Lowest y where the plane x = const cuts the mesh, None when it misses."""
    lowest: float | None = None
    for face in data.faces:
        for k, a_index in enumerate(face):
            a = data.vertices[a_index]
            b = data.vertices[face[(k + 1) % len(face)]]
            if (a[0] - x) * (b[0] - x) > 0.0 or a[0] == b[0]:
                continue
            y = a[1] + (x - a[0]) / (b[0] - a[0]) * (b[1] - a[1])
            lowest = y if lowest is None else min(lowest, y)
    return lowest


def branch_highest_gap_cm(data: MeshData) -> float:
    """Q20: the highest lowest point of the cross-sections x = const, 1 cm apart, outside the
    ``BRANCH_END_SKIP_CM`` of each end (cm)."""
    low, high = data.bounds()
    worst = 0.0
    x = low[0] + BRANCH_END_SKIP_CM * CM
    while x <= high[0] - BRANCH_END_SKIP_CM * CM:
        lowest = lowest_under(data, x)
        worst = max(worst, (lowest if lowest is not None else math.inf) / CM)
        x += 1.0 * CM
    return worst


def _check_branch_gap(data: MeshData) -> None:
    worst = branch_highest_gap_cm(data)
    if worst >= BRANCH_GAP_MAX_CM - BRANCH_GAP_MARGIN_CM:
        raise GeneratorError(
            f"parameter branch_height_cm: the branch leaves a gap of {worst:.2f} cm under it "
            f"(Q20: below {BRANCH_GAP_MAX_CM} cm)"
        )


# --- clay amphora ---


def _profile_normals(profile: list[tuple[float, float]]) -> list[tuple[float, float]]:
    """Outward (radius, height) normal at each point of an open profile traversed bottom-up on
    the outside: the mean of the neighbouring segment normals."""
    normals = []
    for i in range(len(profile)):
        a = profile[max(0, i - 1)]
        b = profile[min(len(profile) - 1, i + 1)]
        dr, dy = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dr, dy)
        normals.append((dy / length, -dr / length))
    return normals


def _amphora_profile(p: dict[str, float]) -> tuple[list[tuple[float, float]], list[str], float]:
    """The closed lathe profile (radius, height) in cm from the outer bottom centre to the inner
    floor centre, a kind per point (``outer``, ``lip``, ``inner``, ``pole``) and the inner floor
    height."""
    k_r = p["amphora_depth_cm"] / AMPHORA_NOMINAL_DEPTH_CM
    k_y = p["amphora_height_cm"] / AMPHORA_NOMINAL_HEIGHT_CM
    wall = p["amphora_wall_cm"]
    top = p["amphora_height_cm"]
    floor = top - p["amphora_inside_depth_cm"]
    inner_min = p["amphora_opening_cm"] / 2.0
    outer = [(r * k_r, y * k_y) for r, y in AMPHORA_OUTER_CM]
    last_r = outer[-1][0]
    lip_radius = wall / 2.0
    # the highest lip point (not always the half-circle's top) is the top of the rim
    steps = range(AMPHORA_LIP_STEPS + 1)
    peak = max(math.sin(math.pi * step / AMPHORA_LIP_STEPS) for step in steps)
    lip_centre = (last_r - lip_radius, top - lip_radius * peak)
    if lip_centre[1] <= outer[-1][1]:
        raise GeneratorError("parameter amphora_wall_cm: the lip does not fit above the neck")
    profile: list[tuple[float, float]] = [(0.0, 0.0), *outer]
    kinds = ["pole"] + ["outer"] * len(outer)
    for step in range(AMPHORA_LIP_STEPS + 1):
        angle = math.pi * step / AMPHORA_LIP_STEPS
        profile.append(
            (
                lip_centre[0] + lip_radius * math.cos(angle),
                lip_centre[1] + lip_radius * math.sin(angle),
            )
        )
        kinds.append("lip")
    normals = _profile_normals(outer)
    inner: list[tuple[float, float]] = []
    for index in AMPHORA_INNER_FROM:
        (r, y), (nr, ny) = outer[index], normals[index]
        ir, iy = r - wall * nr, y - wall * ny
        if floor + AMPHORA_FLOOR_FILLET_CM < iy < lip_centre[1] - 1e-6:
            inner.append((max(inner_min, ir), iy))
    if not inner:
        raise GeneratorError("parameter amphora_inside_depth_cm: no inner wall is left")
    for r, y in reversed(inner):
        profile.append((r, y))
        kinds.append("inner")
    # the inner floor ring: the inner wall at the fillet height, moved in by the fillet
    lowest_r = inner[0][0]
    floor_r = max(inner_min, lowest_r - AMPHORA_FLOOR_FILLET_CM)
    profile.append((floor_r, floor))
    kinds.append("inner")
    profile.append((0.0, floor))
    kinds.append("pole")
    return profile, kinds, floor


def build_clay_amphora(p: dict[str, float]) -> MeshData:
    """The hollow two-handled amphora (see the module text)."""
    width, height, depth = p["amphora_width_cm"], p["amphora_height_cm"], p["amphora_depth_cm"]
    profile, kinds, floor = _amphora_profile(p)
    segments = AMPHORA_SEGMENTS
    # Vertex radius = profile radius / cos(half segment): the polygon's flat faces lie on the
    # profile circle, so the measured (flat to flat) sizes equal the profile sizes.
    widen = 1.0 / math.cos(math.pi / segments)
    turns = [2.0 * math.pi * (k + 0.5) / segments for k in range(segments)]
    points: list[Vec] = []
    shades: list[float] = []
    rows: list[list[int] | int] = []
    inner_top = max(y for (r, y), kind in zip(profile, kinds, strict=True) if kind == "inner")
    for (r, y), kind in zip(profile, kinds, strict=True):
        shade = _amphora_shade(kind, y, height, inner_top, floor)
        if kind == "pole":
            rows.append(len(points))
            points.append((0.0, y, 0.0))
            shades.append(shade)
            continue
        row = []
        for turn in turns:
            row.append(len(points))
            points.append((r * widen * math.cos(turn), y, r * widen * math.sin(turn)))
            shades.append(shade)
        rows.append(row)

    # outward (radius, height) normal of each profile segment: right of the traversal direction
    seg_normals = []
    for i in range(len(profile) - 1):
        dr = profile[i + 1][0] - profile[i][0]
        dy = profile[i + 1][1] - profile[i][1]
        length = math.hypot(dr, dy)
        seg_normals.append((dy / length, -dr / length))

    # wall quads left open for the handles: (profile segment, first column); +1 because the
    # profile starts with the bottom pole
    holes = {
        (hole + 1 + s, column)
        for hole in (AMPHORA_LOWER_HOLE, AMPHORA_UPPER_HOLE)
        for s in (0, 1)
        for column in (segments - 1, segments // 2 - 1)
    }
    faces: list[tuple[tuple[int, ...], Vec]] = []
    for i in range(len(profile) - 1):
        nr, ny = seg_normals[i]
        for k in range(segments):
            n = (k + 1) % segments
            if (i, k) in holes:
                continue
            turn = (turns[k] + turns[n]) / 2.0 + (math.pi if n == 0 else 0.0)
            outward = (nr * math.cos(turn), ny, nr * math.sin(turn))
            a, b = rows[i], rows[i + 1]
            if isinstance(a, int):
                corners: tuple[int, ...] = (a, b[k], b[n])  # type: ignore[index]
            elif isinstance(b, int):
                corners = (a[k], a[n], b)
            else:
                corners = (a[k], a[n], b[n], b[k])
            faces.append((corners, outward))

    handles = _amphora_handles(p, points, rows, profile, widen)
    for side in handles:
        for ring in side["rings"][1:-1]:
            for point in ring:
                points.append(point)
                shades.append(_amphora_shade("outer", point[1], height, inner_top, floor))

    placed = _place(points, (width, height, depth))
    data = _mesh(placed)
    cell = decor_palette.TERRACOTTA
    for corners, outward in faces:
        data.face(corners, cell, outward)
    next_index = len(points) - sum(len(side["rings"]) - 2 for side in handles) * 6
    for side in handles:
        ring_ids: list[list[int]] = [side["start"]]
        for _ in side["rings"][1:-1]:
            ring_ids.append(list(range(next_index, next_index + 6)))
            next_index += 6
        ring_ids.append(side["end"])
        for j in range(len(ring_ids) - 1):
            middle = _mean([data.vertices[i] for i in ring_ids[j] + ring_ids[j + 1]])
            for s in range(6):
                t = (s + 1) % 6
                corners = (ring_ids[j][s], ring_ids[j][t], ring_ids[j + 1][t], ring_ids[j + 1][s])
                data.face(corners, cell, _sub(data.centre(corners), middle))
    data.colours = [(s, s, s, 0.0) for s in shades]
    _check_amphora(data, p)
    return data


def _amphora_shade(kind: str, y: float, height: float, inner_top: float, floor: float) -> float:
    if kind == "lip":
        return 1.0
    if kind == "inner" or (kind == "pole" and y > 0.0):
        depth_share = (inner_top - y) / max(1e-9, inner_top - floor)
        return _lerp(
            AMPHORA_MOUTH_SHADE,
            AMPHORA_INNER_SHADE,
            _smoothstep(0.0, AMPHORA_INNER_FADE, depth_share),
        )
    return _lerp(
        AMPHORA_BASE_SHADE, 1.0, _smoothstep(0.0, AMPHORA_BASE_SHADE_SHARE * height, y)
    )


def _hole_loop(
    rows: list[list[int] | int], profile_row: int, columns: tuple[int, int]
) -> list[int]:
    """The 6 boundary vertices of a hole one quad wide (``columns``) and two quads tall."""
    left, right = columns
    loop = []
    for row in (profile_row, profile_row + 1, profile_row + 2):
        ring = rows[row]
        if isinstance(ring, int):
            raise GeneratorError("internal: a handle hole touches a pole")
        loop.extend((ring[left], ring[right]))
    return loop


def _bezier(points: tuple[Vec, Vec, Vec, Vec], t: float) -> Vec:
    u = 1.0 - t
    a, b, c, d = points
    return _add(
        _add(_mul(a, u * u * u), _mul(b, 3.0 * u * u * t)),
        _add(_mul(c, 3.0 * u * t * t), _mul(d, t * t * t)),
    )


def _bezier_tangent(points: tuple[Vec, Vec, Vec, Vec], t: float) -> Vec:
    u = 1.0 - t
    a, b, c, d = points
    return _unit(
        _add(
            _add(_mul(_sub(b, a), 3.0 * u * u), _mul(_sub(c, b), 6.0 * u * t)),
            _mul(_sub(d, c), 3.0 * t * t),
        )
    )


def _amphora_handles(
    p: dict[str, float],
    points: list[Vec],
    rows: list[list[int] | int],
    profile: list[tuple[float, float]],
    widen: float,
) -> list[dict]:
    """Both handles: per side the start and end hole loops (vertex ids, in ring order) and the
    rings of the tube (the hole loops' points first and last). The Bezier reach is solved so the
    handle's outer surface touches x = +/- width / 2."""
    segments = AMPHORA_SEGMENTS
    k_r = p["amphora_depth_cm"] / AMPHORA_NOMINAL_DEPTH_CM
    half_w = AMPHORA_HANDLE_HALF_WIDTH_CM * k_r
    half_t = AMPHORA_HANDLE_HALF_THICKNESS_CM * k_r
    target = p["amphora_width_cm"] / 2.0
    normals = _profile_normals(profile[1 : len(AMPHORA_OUTER_CM) + 1])
    side_axis = (0.0, 0.0, 1.0)
    result = []
    for sign, columns in ((1.0, (segments - 1, 0)), (-1.0, (segments // 2 - 1, segments // 2))):
        upper = _hole_loop(rows, AMPHORA_UPPER_HOLE + 1, columns)
        lower = _hole_loop(rows, AMPHORA_LOWER_HOLE + 1, columns)
        start = _mean([points[i] for i in upper])
        end = _mean([points[i] for i in lower])
        n_up = normals[AMPHORA_UPPER_HOLE + 1]
        n_low = normals[AMPHORA_LOWER_HOLE + 1]
        out_up = _unit((sign * n_up[0], n_up[1], 0.0))
        out_low = _unit((sign * n_low[0], n_low[1], 0.0))

        def rings_for(reach: float) -> tuple[list[list[Vec]], tuple[Vec, Vec, Vec, Vec]]:
            curve = (
                start,
                _add(start, _mul(out_up, reach)),
                _add(end, _mul(out_low, reach * AMPHORA_HANDLE_LOWER_REACH)),
                end,
            )
            rings = []
            for j in range(1, AMPHORA_HANDLE_STEPS):
                t = j / AMPHORA_HANDLE_STEPS
                centre = _bezier(curve, t)
                forward = _bezier_tangent(curve, t)
                normal = _cross(side_axis, forward)
                ring = []
                for s in range(6):
                    angle = math.pi * s / 3.0
                    offset = _add(
                        _mul(side_axis, half_w * math.cos(angle)),
                        _mul(normal, half_t * math.sin(angle)),
                    )
                    ring.append(_add(centre, offset))
                rings.append(ring)
            return rings, curve

        def reach_of(reach: float) -> float:
            rings, _ = rings_for(reach)
            return max(sign * q[0] for ring in rings for q in ring)

        low, high = 0.1, 8.0
        if reach_of(high) < target:
            raise GeneratorError("parameter amphora_width_cm: the handles cannot reach the width")
        for _ in range(60):
            mid = (low + high) / 2.0
            if reach_of(mid) < target:
                low = mid
            else:
                high = mid
        rings, curve = rings_for(high)
        start_loop = _order_loop(points, upper, start, _bezier_tangent(curve, 0.0), side_axis)
        end_loop = _order_loop(points, lower, end, _bezier_tangent(curve, 1.0), side_axis)
        result.append(
            {
                "start": start_loop,
                "end": end_loop,
                "rings": [[points[i] for i in start_loop], *rings, [points[i] for i in end_loop]],
            }
        )
    return result


def _order_loop(
    points: list[Vec], loop: list[int], centre: Vec, forward: Vec, side_axis: Vec
) -> list[int]:
    """Hole vertices sorted like the tube slots (angle 0 = +side_axis, 90 = side x forward)."""
    normal = _cross(side_axis, forward)

    def key(index: int) -> float:
        offset = _sub(points[index], centre)
        angle = math.atan2(_dot(offset, normal), _dot(offset, side_axis))
        return (angle + math.pi / 6.0) % (2.0 * math.pi)

    return sorted(loop, key=key)


def amphora_measurements(data: MeshData) -> dict[str, float]:
    """AC 22 numbers measured on the mesh (cm): the narrowest inner diameter (flat to flat of the
    polygon, over the inner wall rings from the lip down to the floor), the inside depth (top of
    the rim to the inner floor), the solid volume (cm3) and the connected parts."""
    top = data.bounds()[1][1]
    floor = min(
        v[1] for v in data.vertices if abs(v[0]) < 1e-9 and abs(v[2]) < 1e-9 and v[1] > 1e-9
    )
    apothem = math.cos(math.pi / AMPHORA_SEGMENTS)
    # Between the floor and the top, the vertex nearest the axis at each height is on the inner
    # wall (or the floor ring, or the lip); the inner surface is linear between those heights.
    narrowest = math.inf
    for v in data.vertices:
        radius = math.hypot(v[0], v[2])
        if floor - 1e-9 <= v[1] <= top + 1e-9 and radius > 1e-9:
            narrowest = min(narrowest, 2.0 * radius * apothem)
    return {
        "opening_cm": narrowest / CM,
        "inside_depth_cm": (top - floor) / CM,
        "volume_cm3": signed_volume(data) / CM**3,
        "parts": float(components(data)),
    }


def _check_amphora(data: MeshData, p: dict[str, float]) -> None:
    measured = amphora_measurements(data)
    blender_common.require(
        measured["opening_cm"] >= p["amphora_opening_cm"] - 1e-6,
        "amphora_opening_cm",
        f"the measured opening is {measured['opening_cm']:.3f} cm",
    )
    blender_common.require(
        measured["inside_depth_cm"] >= p["amphora_inside_depth_cm"] - 1e-6,
        "amphora_inside_depth_cm",
        f"the measured inside depth is {measured['inside_depth_cm']:.3f} cm",
    )
    if measured["parts"] != 1.0 or measured["volume_cm3"] <= 0.0:
        raise GeneratorError("internal: the amphora is not one outward-wound shell")
    open_edges = [edge for edge, faces in edge_faces(data).items() if len(faces) != 2]
    if open_edges:
        raise GeneratorError(f"internal: the amphora has {len(open_edges)} non-manifold edges")


# --- entry point ---


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="generate_decor.py",
        description="Generate the starter decoration models and the decor palette atlas.",
    )
    parser.add_argument("--params", type=Path, default=DEFAULT_PARAMS)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    return parser.parse_args(blender_common.script_args(argv))


def _non_manifold_edges(obj) -> int:  # noqa: ANN001 (bpy type)
    """Edges of the Blender mesh without exactly two faces (``bmesh``)."""
    import bmesh  # noqa: PLC0415 (only inside Blender)

    bm = bmesh.new()
    try:
        bm.from_mesh(obj.data)
        return sum(1 for edge in bm.edges if not edge.is_manifold or not edge.is_contiguous)
    finally:
        bm.free()


def _glb_writer(
    name: str, data: MeshData, sharp_angle_deg: float | None, report: dict[str, int]
) -> Callable[[Path], None]:
    def write(path: Path) -> None:
        blender_common.reset_scene()
        material = blender_common.new_material(MATERIAL)
        obj = blender_common.build_object(
            name, data, material, cell_uv=decor_palette.cell_uv, sharp_angle_deg=sharp_angle_deg
        )
        report[name] = _non_manifold_edges(obj)
        blender_common.export_glb([obj], path, vertex_colours=True)

    return write


def build_all(p: dict[str, float]) -> dict[str, tuple[MeshData, float | None]]:
    """Every model: id -> (mesh, split angle; None = all smooth)."""
    return {
        STONE_ID: (build_river_stone(p), blender_common.SHARP_ANGLE_DEG),
        BRANCH_ID: (build_driftwood_branch(p), None),
        AMPHORA_ID: (build_clay_amphora(p), None),
    }


def run(argv: list[str]) -> None:
    args = parse_args(argv)
    params = load_params(args.params.resolve())
    out_dir: Path = args.out_dir.resolve()
    if not out_dir.is_dir():
        raise GeneratorError(f"--out-dir does not exist: {out_dir}")
    models = build_all(params)
    (out_dir / MODELS_DIR).mkdir(exist_ok=True)
    report: dict[str, int] = {}
    outputs: list[tuple[str, Callable[[Path], None], bytes]] = [
        (
            f"{MODELS_DIR}/{name}.glb",
            _glb_writer(name, data, angle, report),
            blender_common.GLB_MAGIC,
        )
        for name, (data, angle) in models.items()
    ]

    def atlas_writer(path: Path) -> None:
        path.write_bytes(decor_palette.atlas_png())

    outputs.append((ATLAS_FILE, atlas_writer, blender_common.PNG_MAGIC))
    blender_common.write_group(out_dir, outputs)
    for name, (data, _angle) in models.items():
        low, high = data.bounds()
        size = " x ".join(f"{(high[i] - low[i]) / CM:.2f}" for i in range(3))
        line = (
            f"{PROG}: wrote {out_dir / MODELS_DIR / name}.glb ({data.triangle_count()} triangles, "
            f"{size} cm, non-manifold edges {report.get(name, -1)}"
        )
        if name == BRANCH_ID:
            line += f", highest gap under a section {branch_highest_gap_cm(data):.2f} cm"
        if name == AMPHORA_ID:
            m = amphora_measurements(data)
            line += (
                f", opening {m['opening_cm']:.2f} cm, inside depth {m['inside_depth_cm']:.2f} cm, "
                f"parts {int(m['parts'])}, clay volume {m['volume_cm3']:.0f} cm3"
            )
        print(line + ")")
    print(f"{PROG}: wrote {out_dir / ATLAS_FILE}")


if __name__ == "__main__":
    sys.exit(blender_common.main(PROG, run))
