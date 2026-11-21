"""Species mode of generate_fish.py (#34): geometry, mask and palette atlas of the real species.

Pure Python (no bpy), so every number here is deterministic and can be checked outside Blender.
generate_fish.py imports this module only for ``--species <id>``; the proof fish of #21 never
touches it, so the proof outputs stay byte-identical.

Conventions are those of generate_fish.py and docs/art-style.md ("Generator conventions"): glTF
frame (+X left of the fish, +Y up, +Z front), unit standard length, origin at the centre of the
bounding box of the body without fins, smooth normals, single-layer double-sided fins on the
``fin`` material, UV0 unwrap plus UV1 palette lookup, vertex colour alpha 1 on fins and 0 on the
body. Positions along the body use ``s`` from the tail base (0) to the snout (1) inside the body
classes; parameter files and the mask rules use the distance from the snout (``*_sl`` keys named
``..._from_snout`` or ``..._front``/``..._back``), which is ``1 - s``.

Mask (ADR 0013 rule 4; technical plan of #34, section 1): 256 x 256 RGBA8, sampled with UV0.
R and G are pattern regions (coverage from 2 x 2 subsamples, so the edge is soft by at most one
texel), B holds the eye bands written hard (0 none, 85 pupil, 170 iris ring, 255 painted dot),
A marks the tintable body (0 or 255): every body texel, minus the R region where the parameter
file asks for it (the neon stripe stays blue-green under a variant tint). Eye islands and fin
islands have A = 0.

Parameter file: a JSON object with exactly the keys of ``SCHEMA`` plus a ``pattern`` object whose
keys depend on its ``kind`` (``PATTERN_SCHEMAS``). Unknown, missing or out-of-range keys raise
``GeneratorError`` with a message that names the key. Each species file stores the "must stay
recognisable" numbers of #34 as named values (body depth, fin reach, barbels, stripe extents).
"""

from __future__ import annotations

import json
import math
import struct
import zlib
from collections.abc import Callable
from pathlib import Path

import generate_fish as base

GeneratorError = base.GeneratorError
Vec = tuple[float, float, float]

SPECIES_IDS = ("neon_tetra", "angelfish", "bronze_corydoras")
ATLAS_NAME = "fish_palette_atlas.png"
MASK_SUFFIX = "_mask.png"
MASK_SIZE = 256

# --- shared fish palette atlas: 4 x 4 cells of 16 px, row 0 at the top (sRGB hex) ---
# One row per species (columns: back, flank, belly, fin); row 3 holds the eye and spare cells.
FISH_ATLAS_PALETTE: tuple[tuple[int, ...], ...] = (
    # neon tetra: olive back, silver flank, silver-white belly, clear pale fin
    (0x4E5A48, 0xB4C2C4, 0xECEFEC, 0xDCE3E4),
    # angelfish: warm silver back, silver flank, pearl belly, smoky silver fin
    (0xBDC1B8, 0xD0D6D4, 0xEDEEE8, 0xC8CFCF),
    # bronze corydoras: dark bronze-olive back, bronze flank, cream-pink belly, pale tan fin
    (0x5C5233, 0x9A7A4B, 0xE4C8B2, 0xD2C3A3),
    # eye (darkest cell), spare dark, spare mid, spare light
    (0x14161A, 0x3A3F47, 0x8A929C, 0xF4F1EA),
)
COLUMN_BACK = 0
COLUMN_FLANK = 1
COLUMN_BELLY = 2
COLUMN_FIN = 3
CELL_EYE = (0, 3)
BACK_FROM = 0.6  # sin of the ring segment mid-angle at or above which a face is "back"
BELLY_BELOW = -0.4  # below this it is "belly"; in between "flank"

# --- fixed construction constants (not species knobs) ---
POLE_PROBE = 0.05
EYE_BULGE = 0.32
EYE_RING_RADII = (0.55, 0.9, 1.0)
EYE_RIM_SINK = 0.010
EYE_SEGMENTS = 14
EYE_UV_RADIUS = 0.07
EYE_UV_CENTRES = ((0.10, 0.76), (0.27, 0.76))  # Blender UV of the right (+X) and left eye
EYE_ISLAND_MARGIN = 1.08  # island radius in eye radii: covers the rim ring with a texel to spare
CAUDAL_ROOT_INSET = 0.03
FIN_ROOT_SINK = 0.012
PECTORAL_ROOT_SINK = 0.012
PECTORAL_HALF_WIDTH = (0.14, 0.20, 0.23, 0.19, 0.06)
PELVIC_ROOT_SINK = 0.006
BARBEL_ROOT_SINK = 0.006
BARBEL_ROWS = 4
BODY_UV_V0 = 0.02
BODY_UV_V_SPAN = 0.6

# Fin UV islands, Blender UV boxes (u0, v0, u1, v1): non-overlapping, at least 5 texels apart and
# clear of the body rectangle (v 0.02 .. 0.62) and the eye islands (u below 0.35).
FIN_UV_BOXES: dict[str, tuple[float, float, float, float]] = {
    "caudal": (0.37, 0.66, 0.52, 0.98),
    "dorsal": (0.54, 0.82, 0.80, 0.98),
    "anal": (0.54, 0.66, 0.80, 0.80),
    "adipose": (0.82, 0.92, 0.88, 0.98),
    "pectoral_right": (0.82, 0.66, 0.88, 0.76),
    "pectoral_left": (0.82, 0.78, 0.88, 0.89),
    "pelvic_right": (0.90, 0.66, 0.94, 0.80),
    "pelvic_left": (0.95, 0.66, 0.99, 0.80),
    "barbel_0": (0.900, 0.82, 0.918, 0.98),
    "barbel_1": (0.925, 0.82, 0.943, 0.98),
    "barbel_2": (0.950, 0.82, 0.968, 0.98),
    "barbel_3": (0.975, 0.82, 0.993, 0.98),
}

# --- parameter schema ---
# ("float", low, high), ("int", low, high), ("bool",), ("floats", count_low, count_high, low, high)
Spec = tuple
SCHEMA: dict[str, Spec] = {
    "atlas_row": ("int", 0, 2),
    # body outline: depth and width are the bounding box of the body without fins
    "body_depth_sl": ("float", 0.15, 0.85),
    "body_width_sl": ("float", 0.08, 0.30),
    "dorsal_share": ("float", 0.25, 0.80),
    "side_level": ("float", 0.20, 0.80),
    "section_exponent_top": ("float", 1.5, 5.0),
    "section_exponent_belly": ("float", 1.5, 8.0),
    "top_peduncle": ("float", 0.05, 1.0),
    "top_rise_from": ("float", 0.0, 0.5),
    "top_peak_from": ("float", 0.1, 0.9),
    "top_peak_to": ("float", 0.1, 0.95),
    "top_snout": ("float", 0.0, 1.0),
    "top_snout_curve": ("float", 0.5, 3.0),
    "belly_peduncle": ("float", 0.05, 1.0),
    "belly_rise_from": ("float", 0.0, 0.5),
    "belly_peak_from": ("float", 0.1, 0.9),
    "belly_peak_to": ("float", 0.1, 0.95),
    "belly_snout": ("float", 0.0, 1.0),
    "belly_snout_curve": ("float", 0.5, 3.0),
    "width_peduncle": ("float", 0.05, 1.0),
    "width_rise_from": ("float", 0.0, 0.5),
    "width_peak_from": ("float", 0.1, 0.9),
    "width_peak_to": ("float", 0.1, 0.95),
    "width_snout": ("float", 0.0, 1.0),
    "width_snout_curve": ("float", 0.5, 3.0),
    "head_length_sl": ("float", 0.15, 0.40),
    "nose_cap_sl": ("float", 0.03, 0.25),
    "tail_cap_sl": ("float", 0.01, 0.08),
    "body_ring_count": ("int", 8, 48),
    "body_ring_segments": ("int", 8, 32),
    # eye: B bands of the mask; the iris ring is the angelfish feature
    "eye_diameter_sl": ("float", 0.05, 0.16),
    "eye_from_snout_sl": ("float", 0.04, 0.25),
    "eye_angle": ("float", -0.5, 1.2),
    "eye_iris_ring": ("bool",),
    "eye_pupil_of_eye": ("float", 0.3, 1.0),
    "eye_dot_of_eye": ("float", 0.12, 0.30),
    "eye_dot_offset": ("float", 0.0, 0.6),
    "eye_dot_angle_deg": ("float", 0.0, 360.0),
    # caudal fin
    "caudal_length_sl": ("float", 0.15, 0.45),
    "caudal_fork_depth_sl": ("float", 0.0, 0.20),
    "caudal_spread_sl": ("float", 0.05, 0.40),
    "caudal_lobe_curve": ("float", 0.5, 3.0),
    "caudal_columns": ("int", 4, 16),
    "caudal_rows": ("int", 2, 8),
    # dorsal fin (tip height is its reach above the highest point of the body)
    "dorsal_front_sl": ("float", 0.15, 0.80),
    "dorsal_back_sl": ("float", 0.20, 0.98),
    "dorsal_reach_sl": ("float", 0.05, 0.60),
    "dorsal_tip_back_sl": ("float", 0.0, 0.80),
    "dorsal_rear_height_sl": ("float", 0.0, 0.40),
    "dorsal_rear_back_sl": ("float", 0.0, 0.30),
    "dorsal_edge_sag": ("float", 0.0, 0.40),
    "dorsal_columns": ("int", 3, 12),
    "dorsal_rows": ("int", 2, 8),
    # anal fin (tip depth is its reach below the lowest point of the body)
    "anal_front_sl": ("float", 0.20, 0.90),
    "anal_back_sl": ("float", 0.30, 0.98),
    "anal_reach_sl": ("float", 0.01, 0.60),
    "anal_tip_back_sl": ("float", 0.0, 0.80),
    "anal_rear_height_sl": ("float", 0.0, 0.40),
    "anal_rear_back_sl": ("float", 0.0, 0.30),
    "anal_edge_sag": ("float", 0.0, 0.40),
    "anal_columns": ("int", 3, 12),
    "anal_rows": ("int", 2, 8),
    # adipose fin (height 0: none)
    "adipose_front_sl": ("float", 0.5, 0.95),
    "adipose_back_sl": ("float", 0.55, 0.98),
    "adipose_height_sl": ("float", 0.0, 0.10),
    # pectoral fins
    "pectoral_length_sl": ("float", 0.08, 0.30),
    "pectoral_angle": ("float", -1.4, 0.5),
    "pectoral_behind_head_sl": ("float", 0.0, 0.10),
    "pectoral_spread": ("float", 0.0, 1.5),
    "pectoral_droop": ("float", -1.0, 0.5),
    "pectoral_width": ("float", 0.5, 2.0),
    # pelvic fins (angelfish: long filaments)
    "pelvic_from_snout_sl": ("float", 0.20, 0.70),
    "pelvic_length_sl": ("float", 0.03, 0.70),
    "pelvic_root_width_sl": ("float", 0.005, 0.10),
    "pelvic_tip_width_sl": ("float", 0.002, 0.08),
    "pelvic_x_sl": ("float", 0.005, 0.08),
    "pelvic_down_deg": ("float", 0.0, 90.0),
    "pelvic_out_deg": ("float", 0.0, 60.0),
    "pelvic_curl_sl": ("float", 0.0, 0.20),
    "pelvic_rows": ("int", 2, 12),
    # barbels (corydoras: two pairs at the chin, each a thin double-sided strip)
    "barbel_pairs": ("int", 0, 2),
    "barbel_length_sl": ("float", 0.03, 0.12),
    "barbel_from_snout_sl": ("float", 0.0, 0.12),
    "barbel_x_sl": ("floats", 2, 2, 0.005, 0.08),
    "barbel_root_width_sl": ("float", 0.004, 0.03),
    "barbel_down_deg": ("float", 0.0, 90.0),
    "barbel_out_deg": ("float", 0.0, 80.0),
    # variant tint: keep the R region out of the alpha body region
    "tint_excludes_pattern_r": ("bool",),
}
PATTERN_SCHEMAS: dict[str, dict[str, Spec]] = {
    # neon tetra: blue-green stripe (R) above the red lower half in the rear half only (G)
    "neon_stripe": {
        "stripe_from_sl": ("float", 0.0, 0.5),
        "stripe_to_sl": ("float", 0.5, 1.0),
        "stripe_width_sl": ("float", 0.03, 0.20),
        "stripe_back_margin": ("float", 0.0, 0.5),
        "red_from_sl": ("float", 0.2, 0.9),
        "red_top_share": ("float", 0.2, 0.7),
        "red_slant_sl": ("float", 0.0, 0.2),
    },
    # angelfish: dark vertical bars (R), continued into the dorsal and anal fin
    "vertical_bars": {
        "bar_centres_sl": ("floats", 1, 5, 0.0, 1.0),
        "bar_width_sl": ("float", 0.03, 0.15),
        "bar_slant": ("float", -0.5, 0.5),
        "bars_on_fins": ("bool",),
    },
    # corydoras: metallic flank patch (R) and the head patch on the gill cover (G)
    "flank_patch": {
        "patch_from_sl": ("float", 0.1, 0.6),
        "patch_to_sl": ("float", 0.5, 1.0),
        "patch_centre_share": ("float", 0.1, 0.9),
        "patch_half_share": ("float", 0.05, 0.5),
        "head_patch_centre_sl": ("float", 0.05, 0.4),
        "head_patch_radius_sl": ("float", 0.02, 0.2),
        "head_patch_share": ("float", 0.1, 0.9),
        "head_patch_half_share": ("float", 0.05, 0.5),
    },
}


def _check_value(key: str, spec: Spec, value: object) -> object:
    kind = spec[0]
    if kind == "bool":
        if not isinstance(value, bool):
            raise GeneratorError(f"parameter {key}: must be true or false, got {value!r}")
        return value
    if kind == "floats":
        _, count_low, count_high, low, high = spec
        if not isinstance(value, list) or not count_low <= len(value) <= count_high:
            raise GeneratorError(
                f"parameter {key}: must be a list of {count_low} to {count_high} numbers"
            )
        return [_check_value(f"{key}[{i}]", ("float", low, high), v) for i, v in enumerate(value)]
    low, high = spec[1], spec[2]
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise GeneratorError(f"parameter {key}: must be a number, got {value!r}")
    if kind == "int" and not isinstance(value, int):
        raise GeneratorError(f"parameter {key}: must be an integer, got {value!r}")
    if not low <= value <= high:
        raise GeneratorError(f"parameter {key}: {value!r} is outside {low} .. {high}")
    return value if kind == "int" else float(value)


def _check_table(label: str, data: dict, schema: dict[str, Spec]) -> dict:
    unknown = sorted(set(data) - set(schema))
    if unknown:
        raise GeneratorError(
            f"{label}: unknown key(s) {', '.join(unknown)}; allowed: {', '.join(schema)}"
        )
    missing = [key for key in schema if key not in data]
    if missing:
        raise GeneratorError(f"{label}: missing key(s) {', '.join(missing)}")
    return {key: _check_value(key, schema[key], data[key]) for key in schema}


def load_species_params(path: Path) -> dict:
    """Read and validate a species parameter file before any Blender work happens."""
    if not path.is_file():
        raise GeneratorError(f"parameter file not found: {path}")
    try:
        data = json.loads(
            path.read_text(encoding="utf-8"), object_pairs_hook=base._reject_duplicates
        )
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise GeneratorError(f"parameter file is not valid JSON: {path}: {error}") from error
    if not isinstance(data, dict):
        raise GeneratorError(f"parameter file must hold a JSON object: {path}")
    pattern = data.pop("pattern", None)
    params = _check_table("parameter file", data, SCHEMA)
    if not isinstance(pattern, dict):
        raise GeneratorError("parameter file: key 'pattern' must be an object with a 'kind'")
    kind = pattern.pop("kind", None)
    if kind not in PATTERN_SCHEMAS:
        raise GeneratorError(
            f"parameter pattern.kind: {kind!r} is unknown; allowed: {', '.join(PATTERN_SCHEMAS)}"
        )
    params["pattern"] = _check_table(f"parameter pattern ({kind})", pattern, PATTERN_SCHEMAS[kind])
    params["pattern"]["kind"] = kind
    if params["body_ring_segments"] % 2:
        raise GeneratorError("parameter body_ring_segments: must be even (mirrored flanks)")
    for outline in ("top", "belly", "width"):
        if not (
            params[f"{outline}_rise_from"]
            < params[f"{outline}_peak_from"]
            <= params[f"{outline}_peak_to"]
        ):
            raise GeneratorError(
                f"parameter {outline}_rise_from < {outline}_peak_from <= {outline}_peak_to "
                "does not hold"
            )
    for fin in ("dorsal", "anal", "adipose"):
        if params[f"{fin}_front_sl"] >= params[f"{fin}_back_sl"]:
            raise GeneratorError(f"parameter {fin}_front_sl: must be below {fin}_back_sl")
    if params["caudal_fork_depth_sl"] >= params["caudal_length_sl"]:
        raise GeneratorError("parameter caudal_fork_depth_sl: must be below caudal_length_sl")
    if not params["eye_iris_ring"] and params["eye_pupil_of_eye"] != 1.0:
        raise GeneratorError("parameter eye_pupil_of_eye: must be 1.0 without an iris ring")
    if params["eye_dot_offset"] + params["eye_dot_of_eye"] > params["eye_pupil_of_eye"]:
        raise GeneratorError("parameter eye_dot_offset: the dot must sit inside the pupil")
    return params


# --- body ---


class SpeciesBody:
    """Ring loft with separate back, belly and width outlines and a flat-bellied option.

    Each outline is a normalised profile: ``peduncle`` at the tail base, a smooth rise from
    ``rise_from`` to the plateau ``peak_from`` .. ``peak_to`` (value 1), then a fall to ``snout`` at
    the snout with the power ``snout_curve``. The back is ``dorsal_share`` of the depth above
    y = 0 and the belly the rest below, so a belly plateau is a straight underside. The widest line
    of a section sits at ``side_level`` of the local depth; the rounded caps at both poles close
    the outlines onto it.
    """

    def __init__(self, p: dict) -> None:
        depth = p["body_depth_sl"]
        self.top_height = depth * p["dorsal_share"]
        self.belly_height = depth - self.top_height
        self.half_width_max = 0.5 * p["body_width_sl"]
        self.side_level = p["side_level"]
        self.exponent_top = 2.0 / p["section_exponent_top"]
        self.exponent_belly = 2.0 / p["section_exponent_belly"]
        self.nose_cap = p["nose_cap_sl"]
        self.tail_cap = p["tail_cap_sl"]
        self.outlines = {
            name: (
                p[f"{name}_peduncle"],
                p[f"{name}_rise_from"],
                p[f"{name}_peak_from"],
                p[f"{name}_peak_to"],
                p[f"{name}_snout"],
                p[f"{name}_snout_curve"],
            )
            for name in ("top", "belly", "width")
        }
        self.segments = int(p["body_ring_segments"])
        count = int(p["body_ring_count"])
        self.rings = [
            0.5 * (1.0 - math.cos(math.pi * i / (count + 1))) for i in range(1, count + 1)
        ]

    def _profile(self, name: str, s: float) -> float:
        peduncle, rise_from, peak_from, peak_to, snout, curve = self.outlines[name]
        if s < peak_from:
            return peduncle + (1.0 - peduncle) * base._smoothstep(
                (s - rise_from) / (peak_from - rise_from)
            )
        if s <= peak_to:
            return 1.0
        t = (s - peak_to) / (1.0 - peak_to)
        return 1.0 - (1.0 - snout) * t**curve

    def _closure(self, s: float) -> float:
        factor = 1.0
        if s < self.tail_cap:
            t = (self.tail_cap - s) / self.tail_cap
            factor *= math.sqrt(max(0.0, 1.0 - t * t))
        start = 1.0 - self.nose_cap
        if s > start:
            t = (s - start) / self.nose_cap
            factor *= math.sqrt(max(0.0, 1.0 - t * t))
        return factor

    def _raw(self, s: float) -> tuple[float, float]:
        return self.top_height * self._profile("top", s), -self.belly_height * self._profile(
            "belly", s
        )

    def centre(self, s: float) -> float:
        top, bottom = self._raw(s)
        return bottom + self.side_level * (top - bottom)

    def top(self, s: float) -> float:
        top, _ = self._raw(s)
        mid = self.centre(s)
        return mid + (top - mid) * self._closure(s)

    def bottom(self, s: float) -> float:
        _, bottom = self._raw(s)
        mid = self.centre(s)
        return mid + (bottom - mid) * self._closure(s)

    def half_width(self, s: float) -> float:
        return self.half_width_max * self._profile("width", s) * self._closure(s)

    def point(self, s: float, phi: float) -> Vec:
        mid = self.centre(s)
        sine = math.sin(phi)
        if sine >= 0.0:
            exponent = self.exponent_top
            y = mid + (self.top(s) - mid) * base._signed_pow(sine, exponent)
        else:
            exponent = self.exponent_belly
            y = mid + (mid - self.bottom(s)) * base._signed_pow(sine, exponent)
        x = self.half_width(s) * base._signed_pow(math.cos(phi), exponent)
        return (x, y, s - 0.5)

    def phi(self, j: int) -> float:
        return math.pi / 2.0 - 2.0 * math.pi * j / self.segments

    def ring_point(self, s: float, j: int) -> Vec:
        half = self.segments // 2
        j %= self.segments
        if j > half:
            x, y, z = self.point(s, self.phi(self.segments - j))
            return (-x, y, z)
        x, y, z = self.point(s, self.phi(j))
        if j in (0, half):
            x = 0.0
        return (x, y, z)

    def axis(self, s: float) -> Vec:
        return (0.0, self.centre(s), s - 0.5)

    def normal(self, s: float, phi: float) -> Vec:
        d = 1e-4
        along_phi = base._sub(self.point(s, phi + d), self.point(s, phi - d))
        along_s = base._sub(self.point(s + d, phi), self.point(s - d, phi))
        n = base._norm(base._cross(along_phi, along_s))
        if base._dot(n, base._sub(self.point(s, phi), self.axis(s))) < 0.0:
            n = base._mul(n, -1.0)
        return n

    def top_max(self) -> float:
        return max(self.top(i / 400.0) for i in range(401))

    def bottom_min(self) -> float:
        return min(self.bottom(i / 400.0) for i in range(401))


class Built:
    """The mesh plus what the mask painter needs: a part name per face and the body frame."""

    def __init__(self, body: SpeciesBody, params: dict) -> None:
        self.data = base.MeshData()
        self.parts: list[str] = []
        self.body = body
        self.params = params
        self.offset: Vec = (0.0, 0.0, 0.0)

    def tag(self, part: str) -> None:
        self.parts.extend([part] * (len(self.data.faces) - len(self.parts)))

    def cell(self, column: int) -> tuple[int, int]:
        return (column, int(self.params["atlas_row"]))

    def frame_top(self, s_snout: float) -> float:
        return self.body.top(1.0 - s_snout) - self.offset[1]

    def frame_bottom(self, s_snout: float) -> float:
        return self.body.bottom(1.0 - s_snout) - self.offset[1]


def _body_cell(built: Built, j: int) -> tuple[int, int]:
    body = built.body
    mid = math.sin(body.phi(j) - math.pi / body.segments)
    if mid >= BACK_FROM:
        return built.cell(COLUMN_BACK)
    if mid > BELLY_BELOW:
        return built.cell(COLUMN_FLANK)
    return built.cell(COLUMN_BELLY)


def _uv_body(j: int, s: float, segments: int) -> tuple[float, float]:
    return (j / segments, BODY_UV_V0 + BODY_UV_V_SPAN * s)


def build_body(built: Built) -> None:
    data = built.data
    body = built.body
    m = body.segments
    tail = data.vertex(body.axis(0.0))
    rings = [[data.vertex(body.ring_point(s, j)) for j in range(m)] for s in body.rings]
    snout = data.vertex(body.axis(1.0))
    first = body.rings[0]
    last = body.rings[-1]
    for j in range(m):
        k = (j + 1) % m
        cell = _body_cell(built, j)
        pole_u = (j + 0.5) / m
        corners = (tail, rings[0][k], rings[0][j])
        uv = ((pole_u, BODY_UV_V0), _uv_body(j + 1, first, m), _uv_body(j, first, m))
        out = base._sub(data.centre(corners), body.axis(first + POLE_PROBE))
        data.face(corners, uv, 0, cell, out)
        corners = (snout, rings[-1][j], rings[-1][k])
        uv = (
            (pole_u, BODY_UV_V0 + BODY_UV_V_SPAN),
            _uv_body(j, last, m),
            _uv_body(j + 1, last, m),
        )
        out = base._sub(data.centre(corners), body.axis(last - POLE_PROBE))
        data.face(corners, uv, 0, cell, out)
    for i in range(len(rings) - 1):
        s0 = body.rings[i]
        s1 = body.rings[i + 1]
        for j in range(m):
            k = (j + 1) % m
            corners = (rings[i][j], rings[i][k], rings[i + 1][k], rings[i + 1][j])
            uv = (
                _uv_body(j, s0, m),
                _uv_body(j + 1, s0, m),
                _uv_body(j + 1, s1, m),
                _uv_body(j, s1, m),
            )
            out = base._sub(data.centre(corners), body.axis(0.5 * (s0 + s1)))
            data.face(corners, uv, 0, _body_cell(built, j), out)
    built.tag("body")


def build_eye(built: Built, side: int) -> None:
    """A round bump on the head side (the #21 eye, placed by the species parameters)."""
    data = built.data
    body = built.body
    p = built.params
    s_eye = 1.0 - p["eye_from_snout_sl"]
    angle = p["eye_angle"]
    radius = 0.5 * p["eye_diameter_sl"]
    d = 1e-4
    step = base._sub(body.point(s_eye, angle + d), body.point(s_eye, angle - d))
    phi_per_unit = 2.0 * d / math.sqrt(base._dot(step, step))
    bulge = EYE_BULGE * radius

    def at(rho: float, psi: float, height: float) -> Vec:
        s = s_eye + rho * radius * math.cos(psi)
        phi = angle + rho * radius * math.sin(psi) * phi_per_unit
        q = base._add(body.point(s, phi), base._mul(body.normal(s, phi), height))
        return (q[0] * side, q[1], q[2])

    points: list[Vec] = [at(0.0, 0.0, bulge)]
    local: list[tuple[float, float]] = [(0.0, 0.0)]
    for r, rho in enumerate(EYE_RING_RADII):
        last = r == len(EYE_RING_RADII) - 1
        height = -EYE_RIM_SINK if last else bulge * math.sqrt(1.0 - rho * rho)
        for k in range(EYE_SEGMENTS):
            psi = 2.0 * math.pi * k / EYE_SEGMENTS
            points.append(at(rho, psi, height))
            local.append((rho * math.cos(psi), rho * math.sin(psi)))
    centre_u, centre_v = EYE_UV_CENTRES[0 if side == 1 else 1]
    uvs = [(centre_u + EYE_UV_RADIUS * a, centre_v + EYE_UV_RADIUS * b) for a, b in local]
    indices = [data.vertex(q) for q in points]
    outward = body.normal(s_eye, angle)
    outward = (outward[0] * side, outward[1], outward[2])

    def ring_index(r: int, k: int) -> int:
        return 1 + (r - 1) * EYE_SEGMENTS + (k % EYE_SEGMENTS)

    def add(corner_ids: tuple[int, ...]) -> None:
        corners = tuple(indices[i] for i in corner_ids)
        data.face(corners, tuple(uvs[i] for i in corner_ids), 0, CELL_EYE, outward)

    for k in range(EYE_SEGMENTS):
        add((0, ring_index(1, k), ring_index(1, k + 1)))
    for r in range(1, len(EYE_RING_RADII)):
        for k in range(EYE_SEGMENTS):
            add(
                (
                    ring_index(r, k),
                    ring_index(r, k + 1),
                    ring_index(r + 1, k + 1),
                    ring_index(r + 1, k),
                )
            )
    built.tag("eye_right" if side == 1 else "eye_left")


def _fin_grid(built: Built, part: str, grid: list[list[Vec]], normal: Vec) -> None:
    data = built.data
    rows = len(grid)
    columns = len(grid[0])
    u0, v0, u1, v1 = FIN_UV_BOXES[part]
    indices = [[data.vertex(q) for q in row] for row in grid]

    def uv(r: int, c: int) -> tuple[float, float]:
        return (u0 + (u1 - u0) * c / (columns - 1), v0 + (v1 - v0) * r / (rows - 1))

    cell = built.cell(COLUMN_FIN)
    for r in range(rows - 1):
        for c in range(columns - 1):
            local = ((r, c), (r, c + 1), (r + 1, c + 1), (r + 1, c))
            corners = tuple(indices[a][b] for a, b in local)
            data.face(corners, tuple(uv(a, b) for a, b in local), 1, cell, normal)
    built.tag(part)


def build_caudal(built: Built) -> None:
    body = built.body
    p = built.params
    s_root = CAUDAL_ROOT_INSET
    centre = body.centre(s_root)
    root_half = 0.4 * (body.top(s_root) - body.bottom(s_root))
    spread = p["caudal_spread_sl"]
    length = p["caudal_length_sl"]
    fork = p["caudal_fork_depth_sl"]
    curve = p["caudal_lobe_curve"]
    rows = int(p["caudal_rows"])
    columns = int(p["caudal_columns"])
    grid: list[list[Vec]] = []
    for r in range(rows + 1):
        u = r / rows
        row: list[Vec] = []
        for c in range(columns + 1):
            v = -1.0 + 2.0 * c / columns
            root = (0.0, centre + v * root_half, s_root - 0.5)
            trail = (0.0, centre + v * spread, -0.5 - length + fork * (1.0 - abs(v) ** curve))
            row.append(base._add(root, base._mul(base._sub(trail, root), u)))
        grid.append(row)
    _fin_grid(built, "caudal", grid, (1.0, 0.0, 0.0))


def build_median(built: Built, fin: str) -> None:
    """Dorsal (above) or anal (below) fin in the centre plane, swept back from its root line."""
    body = built.body
    p = built.params
    upper = fin == "dorsal"
    sign = 1.0 if upper else -1.0
    z_front = 0.5 - p[f"{fin}_front_sl"]
    z_back = 0.5 - p[f"{fin}_back_sl"]

    def outline(z: float) -> float:
        return body.top(z + 0.5) if upper else body.bottom(z + 0.5)

    extreme = body.top_max() if upper else body.bottom_min()
    tip = (0.0, extreme + sign * p[f"{fin}_reach_sl"], z_front - p[f"{fin}_tip_back_sl"])
    rear = (
        0.0,
        outline(z_back) + sign * p[f"{fin}_rear_height_sl"],
        z_back - p[f"{fin}_rear_back_sl"],
    )
    height = abs(tip[1] - outline(z_front))
    sag = p[f"{fin}_edge_sag"]
    rows = int(p[f"{fin}_rows"])
    columns = int(p[f"{fin}_columns"])
    grid: list[list[Vec]] = []
    for r in range(rows + 1):
        lift = r / rows
        row: list[Vec] = []
        for c in range(columns + 1):
            t = c / columns
            z = z_front + t * (z_back - z_front)
            root = (0.0, outline(z) - sign * FIN_ROOT_SINK, z)
            edge = base._add(tip, base._mul(base._sub(rear, tip), t))
            edge = (0.0, edge[1] - sign * sag * height * math.sin(math.pi * t), edge[2])
            row.append(base._add(root, base._mul(base._sub(edge, root), lift)))
        grid.append(row)
    _fin_grid(built, fin, grid, (1.0, 0.0, 0.0))


def build_adipose(built: Built) -> None:
    """Small fleshy fin on the back before the tail (tetras and catfish); none at height 0."""
    p = built.params
    height = p["adipose_height_sl"]
    if height <= 0.0:
        return
    body = built.body
    z_front = 0.5 - p["adipose_front_sl"]
    z_back = 0.5 - p["adipose_back_sl"]
    tip = (0.0, body.top(z_back + 0.5) + height, z_back - 0.3 * (z_front - z_back))
    rear = (0.0, body.top(z_back + 0.5) + 0.25 * height, z_back - 0.45 * (z_front - z_back))
    rows = 2
    columns = 3
    grid: list[list[Vec]] = []
    for r in range(rows + 1):
        lift = r / rows
        row: list[Vec] = []
        for c in range(columns + 1):
            t = c / columns
            z = z_front + t * (z_back - z_front)
            root = (0.0, body.top(z + 0.5) - FIN_ROOT_SINK, z)
            front_edge = (
                0.0,
                body.top(z_front + 0.5) + 0.2 * height,
                z_front - 0.2 * (z_front - z_back),
            )
            edge = rear
            if t < 1.0:
                edge = base._add(front_edge, base._mul(base._sub(tip, front_edge), t))
            row.append(base._add(root, base._mul(base._sub(edge, root), lift)))
        grid.append(row)
    _fin_grid(built, "adipose", grid, (1.0, 0.0, 0.0))


def build_pectorals(built: Built) -> None:
    body = built.body
    p = built.params
    length = p["pectoral_length_sl"]
    angle = p["pectoral_angle"]
    s = 1.0 - p["head_length_sl"] - p["pectoral_behind_head_sl"]
    normal = body.normal(s, angle)
    root = base._sub(body.point(s, angle), base._mul(normal, PECTORAL_ROOT_SINK))
    direction = base._norm((p["pectoral_spread"], p["pectoral_droop"], -1.0))
    up = (0.0, 1.0, 0.0)
    across = base._norm(base._sub(up, base._mul(direction, base._dot(direction, up))))
    rows = len(PECTORAL_HALF_WIDTH)
    grid: list[list[Vec]] = []
    for r in range(rows):
        u = r / (rows - 1)
        row: list[Vec] = []
        for v in (-1.0, 0.0, 1.0):
            reach = length * u * (1.0 - 0.1 * u**4 * abs(v))
            offset = v * PECTORAL_HALF_WIDTH[r] * length * p["pectoral_width"]
            along = base._add(root, base._mul(direction, reach))
            row.append(base._add(along, base._mul(across, offset)))
        grid.append(row)
    facing = base._cross(across, direction)
    if base._dot(facing, (1.0, 0.0, 0.0)) < 0.0:
        facing = base._mul(facing, -1.0)
    _fin_grid(built, "pectoral_right", grid, facing)
    left = [[(-q[0], q[1], q[2]) for q in row] for row in grid]
    _fin_grid(built, "pectoral_left", left, (-facing[0], facing[1], facing[2]))


def _ribbon(
    root: Vec,
    direction: Vec,
    across: Vec,
    length: float,
    root_width: float,
    tip_width: float,
    curl: float,
    rows: int,
) -> list[list[Vec]]:
    """A tapered strip: rows along ``direction``, three vertices across, a backward curl."""
    grid: list[list[Vec]] = []
    for r in range(rows + 1):
        u = r / rows
        half = 0.5 * (root_width + (tip_width - root_width) * u)
        along = base._add(root, base._mul(direction, length * u))
        centre = base._add(along, (0.0, 0.0, -curl * u * u))
        grid.append([base._add(centre, base._mul(across, v * half)) for v in (-1.0, 0.0, 1.0)])
    return grid


def build_pelvics(built: Built) -> None:
    body = built.body
    p = built.params
    s = 1.0 - p["pelvic_from_snout_sl"]
    x = p["pelvic_x_sl"]
    root = (x, body.bottom(s) + PELVIC_ROOT_SINK, s - 0.5)
    down = math.radians(p["pelvic_down_deg"])
    out = math.radians(p["pelvic_out_deg"])
    direction = base._norm(
        (math.sin(out), -math.sin(down) * math.cos(out), -math.cos(down) * math.cos(out))
    )
    across = base._norm(base._cross((1.0, 0.0, 0.0), direction))
    grid = _ribbon(
        root,
        direction,
        across,
        p["pelvic_length_sl"],
        p["pelvic_root_width_sl"],
        p["pelvic_tip_width_sl"],
        p["pelvic_curl_sl"],
        int(p["pelvic_rows"]),
    )
    facing = base._norm(base._cross(across, direction))
    if base._dot(facing, (1.0, 0.0, 0.0)) < 0.0:
        facing = base._mul(facing, -1.0)
    _fin_grid(built, "pelvic_right", grid, facing)
    left = [[(-q[0], q[1], q[2]) for q in row] for row in grid]
    _fin_grid(built, "pelvic_left", left, (-facing[0], facing[1], facing[2]))


def build_barbels(built: Built) -> None:
    """Two pairs of thin strips under the snout, pointing down, out and slightly forward."""
    p = built.params
    pairs = int(p["barbel_pairs"])
    body = built.body
    s = 1.0 - p["barbel_from_snout_sl"]
    down = math.radians(p["barbel_down_deg"])
    for pair in range(pairs):
        x = p["barbel_x_sl"][pair]
        out = math.radians(p["barbel_out_deg"]) * (1.0 + 0.5 * pair)
        horizontal = math.cos(down)
        direction = base._norm(
            (horizontal * math.sin(out), -math.sin(down), horizontal * math.cos(out))
        )
        across = base._norm(base._cross(direction, (0.0, 1.0, 0.0)))
        root = (x, body.bottom(s) + BARBEL_ROOT_SINK, s - 0.5)
        width = p["barbel_root_width_sl"]
        grid = _ribbon(
            root, direction, across, p["barbel_length_sl"], width, 0.3 * width, 0.0, BARBEL_ROWS
        )
        facing = base._norm(base._cross(across, direction))
        if base._dot(facing, (1.0, 0.0, 0.0)) < 0.0:
            facing = base._mul(facing, -1.0)
        _fin_grid(built, f"barbel_{2 * pair}", grid, facing)
        left = [[(-q[0], q[1], q[2]) for q in row] for row in grid]
        _fin_grid(built, f"barbel_{2 * pair + 1}", left, (-facing[0], facing[1], facing[2]))


def build_species(params: dict) -> Built:
    built = Built(SpeciesBody(params), params)
    build_body(built)
    build_eye(built, 1)
    build_eye(built, -1)
    data = built.data
    body_vertex_count = len(data.vertices)
    build_caudal(built)
    build_median(built, "dorsal")
    build_median(built, "anal")
    build_adipose(built)
    build_pectorals(built)
    build_pelvics(built)
    build_barbels(built)
    body = data.vertices[:body_vertex_count]
    low = [min(q[i] for q in body) for i in range(3)]
    high = [max(q[i] for q in body) for i in range(3)]
    if abs((high[2] - low[2]) - 1.0) > 1e-9:
        raise GeneratorError(f"internal: body length is {high[2] - low[2]}, must be 1.0")
    built.offset = (0.5 * (low[0] + high[0]), 0.5 * (low[1] + high[1]), 0.5 * (low[2] + high[2]))
    data.vertices = [base._sub(q, built.offset) for q in data.vertices]
    return built


# --- palette atlas and PNG writing ---


def png_bytes(width: int, height: int, channels: int, pixel: Callable[[int, int], bytes]) -> bytes:
    """8-bit RGB (3) or RGBA (4) PNG, row 0 at the top; deterministic (zlib level 9)."""
    colour_type = {3: 2, 4: 6}[channels]
    rows = [b"\x00" + b"".join(pixel(x, y) for x in range(width)) for y in range(height)]

    def chunk(tag: bytes, payload: bytes) -> bytes:
        crc = zlib.crc32(tag + payload) & 0xFFFFFFFF
        return struct.pack(">I", len(payload)) + tag + payload + struct.pack(">I", crc)

    header = struct.pack(">IIBBBBB", width, height, 8, colour_type, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(b"".join(rows), 9))
        + chunk(b"IEND", b"")
    )


def atlas_png() -> bytes:
    size = base.ATLAS_GRID * base.ATLAS_CELL_PX

    def pixel(x: int, y: int) -> bytes:
        rgb = FISH_ATLAS_PALETTE[y // base.ATLAS_CELL_PX][x // base.ATLAS_CELL_PX]
        return bytes(((rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF))

    return png_bytes(size, size, 3, pixel)


# --- mask painting ---

SUBSAMPLES = ((0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75))


def _region_function(built: Built) -> Callable[[str, Vec], tuple[float, float]]:
    """(R, G) coverage of a surface point, by the species pattern."""
    pattern = built.params["pattern"]
    kind = pattern["kind"]

    def local(point: Vec) -> tuple[float, float, float]:
        s = 0.5 - point[2]
        bottom = built.frame_bottom(min(max(s, 0.0), 1.0))
        top = built.frame_top(min(max(s, 0.0), 1.0))
        depth = max(top - bottom, 1e-6)
        return s, bottom, depth

    if kind == "neon_stripe":

        def neon(part: str, point: Vec) -> tuple[float, float]:
            if part != "body":
                return 0.0, 0.0
            s, bottom, depth = local(point)
            share = (point[1] - bottom) / depth
            red = 0.0
            if share <= pattern["red_top_share"] and s >= pattern["red_from_sl"] + pattern[
                "red_slant_sl"
            ] * (share / pattern["red_top_share"]):
                red = 1.0
            stripe = 0.0
            if pattern["stripe_from_sl"] <= s <= pattern["stripe_to_sl"]:
                lower = bottom + pattern["red_top_share"] * depth
                upper = min(
                    lower + pattern["stripe_width_sl"],
                    bottom + depth * (1.0 - pattern["stripe_back_margin"]),
                )
                if lower <= point[1] <= upper:
                    stripe = 1.0
            return stripe, red

        return neon

    if kind == "vertical_bars":

        def bars(part: str, point: Vec) -> tuple[float, float]:
            if part != "body" and not (pattern["bars_on_fins"] and part in ("dorsal", "anal")):
                return 0.0, 0.0
            s = 0.5 - point[2]
            half = 0.5 * pattern["bar_width_sl"]
            for centre in pattern["bar_centres_sl"]:
                if abs(s - (centre - pattern["bar_slant"] * point[1])) <= half:
                    return 1.0, 0.0
            return 0.0, 0.0

        return bars

    def patch(part: str, point: Vec) -> tuple[float, float]:
        if part != "body":
            return 0.0, 0.0
        s, bottom, depth = local(point)
        share = (point[1] - bottom) / depth
        flank = 0.0
        start = pattern["patch_from_sl"]
        end = pattern["patch_to_sl"]
        if start <= s <= end:
            envelope = math.sin(math.pi * (s - start) / (end - start)) ** 0.5
            if abs(share - pattern["patch_centre_share"]) <= pattern["patch_half_share"] * envelope:
                flank = 1.0
        head = 0.0
        ds = (s - pattern["head_patch_centre_sl"]) / pattern["head_patch_radius_sl"]
        dh = (share - pattern["head_patch_share"]) / pattern["head_patch_half_share"]
        if ds * ds + dh * dh <= 1.0:
            head = 1.0
        return flank, head

    return patch


def _paint_triangles(
    built: Built, region: Callable[[str, Vec], tuple[float, float]]
) -> tuple[list[list[float]], list[int], list[str]]:
    """Rasterise every body and fin triangle in UV0 space; (R, G) sums, counts and texel kinds."""
    size = MASK_SIZE
    sums = [[0.0, 0.0] for _ in range(size * size)]
    counts = [0] * (size * size)
    kinds = [""] * (size * size)
    data = built.data
    for face, uvs, part in zip(data.faces, data.uv0, built.parts, strict=True):
        if part.startswith("eye"):
            continue
        kind = "body" if part == "body" else "fin"
        for k in range(1, len(face) - 1):
            ids = (0, k, k + 1)
            corners = [(uvs[i][0] * size, (1.0 - uvs[i][1]) * size) for i in ids]
            points = [data.vertices[face[i]] for i in ids]
            (ax, ay), (bx, by), (cx, cy) = corners
            det = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
            if abs(det) < 1e-12:
                continue
            x0 = max(0, math.floor(min(ax, bx, cx)) - 1)
            x1 = min(size - 1, math.ceil(max(ax, bx, cx)) + 1)
            y0 = max(0, math.floor(min(ay, by, cy)) - 1)
            y1 = min(size - 1, math.ceil(max(ay, by, cy)) + 1)
            for ty in range(y0, y1 + 1):
                for tx in range(x0, x1 + 1):
                    index = ty * size + tx
                    for sx, sy in SUBSAMPLES:
                        qx = tx + sx
                        qy = ty + sy
                        l0 = ((by - cy) * (qx - cx) + (cx - bx) * (qy - cy)) / det
                        l1 = ((cy - ay) * (qx - cx) + (ax - cx) * (qy - cy)) / det
                        l2 = 1.0 - l0 - l1
                        if l0 < -1e-9 or l1 < -1e-9 or l2 < -1e-9:
                            continue
                        q = base._add(
                            base._add(base._mul(points[0], l0), base._mul(points[1], l1)),
                            base._mul(points[2], l2),
                        )
                        r, g = region(part, q)
                        sums[index][0] += r
                        sums[index][1] += g
                        counts[index] += 1
                        kinds[index] = kind
    return sums, counts, kinds


def _dilate(values: list[list[float]], kinds: list[str], passes: int) -> None:
    """Grow painted texels by ``passes`` texels into unpainted ones (8-neighbourhood)."""
    size = MASK_SIZE
    for _ in range(passes):
        grown: list[tuple[int, list[float], str]] = []
        for y in range(size):
            for x in range(size):
                index = y * size + x
                if kinds[index]:
                    continue
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        nx = x + dx
                        ny = y + dy
                        if 0 <= nx < size and 0 <= ny < size and kinds[ny * size + nx]:
                            neighbour = ny * size + nx
                            grown.append((index, list(values[neighbour]), kinds[neighbour]))
                            break
                    else:
                        continue
                    break
        for index, value, kind in grown:
            values[index] = value
            kinds[index] = kind


def _eye_band(built: Built, gu: float, gv: float) -> int | None:
    """Band 0..3 of a texel centre in Godot UV inside an eye island; None outside both islands."""
    p = built.params
    pupil = p["eye_pupil_of_eye"] if p["eye_iris_ring"] else EYE_ISLAND_MARGIN
    dot_angle = math.radians(p["eye_dot_angle_deg"])
    dot = (p["eye_dot_offset"] * math.cos(dot_angle), p["eye_dot_offset"] * math.sin(dot_angle))
    for centre_u, centre_v in EYE_UV_CENTRES:
        a = (gu - centre_u) / EYE_UV_RADIUS
        b = ((1.0 - gv) - centre_v) / EYE_UV_RADIUS
        rho = math.hypot(a, b)
        if rho > EYE_ISLAND_MARGIN:
            continue
        if math.hypot(a - dot[0], b - dot[1]) <= p["eye_dot_of_eye"]:
            return 3
        return 1 if rho <= pupil else 2
    return None


def mask_png(built: Built) -> bytes:
    region = _region_function(built)
    sums, counts, kinds = _paint_triangles(built, region)
    size = MASK_SIZE
    values = [
        [sums[i][0] / counts[i], sums[i][1] / counts[i]] if counts[i] else [0.0, 0.0]
        for i in range(size * size)
    ]
    _dilate(values, kinds, 2)
    exclude_r = built.params["tint_excludes_pattern_r"]
    texels: list[bytes] = []
    for y in range(size):
        for x in range(size):
            index = y * size + x
            band = _eye_band(built, (x + 0.5) / size, (y + 0.5) / size)
            if band is not None:
                texels.append(bytes((0, 0, 85 * band, 0)))
                continue
            red = round(255 * min(max(values[index][0], 0.0), 1.0))
            green = round(255 * min(max(values[index][1], 0.0), 1.0))
            alpha = 0
            if kinds[index] == "body" and not (exclude_r and red >= 128):
                alpha = 255
            texels.append(bytes((red, green, 0, alpha)))
    return png_bytes(size, size, 4, lambda x, y: texels[y * size + x])


def triangle_count(built: Built) -> int:
    return sum(len(face) - 2 for face in built.data.faces)
