"""Reusable, physically settled pack tiles for the substrate bake (#28, ADR 0011 rule 7).

All tiles are poured with substrate_sim.pour(). Tiles that must meet each other share "seam
sets": bands of stones that were settled first and are frozen colliders while the tile between
them is poured. Every stone therefore rests on its real neighbours, also across tile borders;
no stone is ever settled against an invisible flat wall that a camera can see. The seam sets are
poured in a trough that is `seam_extra_m` wider than the band that is kept on each side, so the
kept band has natural neighbours on both sides and shows no rows along a wall (the 2.5 cm sand
tiles of the look spike were poured in a narrow trough and showed a grid from above).

Canonical frames (Blender, z up, metres):

Ring (the bed against a glass pane, full depth, floor at z = 0):
    glass plane y = 0, interior towards +y, x along the glass.
    E     seam between two ring cells: stones with centre |x| < seam_half, 0 < y < depth.
    F<k>  ring cell between the seams at x = 0 and x = period (k = fill variant).
    K     corner cell 0 <= x, y < corner: second glass at x = 0, the seam E at x = corner (the
          start of this pane's row) and the last seam of the previous pane's row at y = corner.
          Only the stones within `depth` of one of the two panes are kept.
    The four panes use the same sets rotated by 0, 90, 180 and 270 degrees.

Top (the upper layers away from the glass, shallow, floor at z = 0 = fill depth - thickness):
    C     node set at the origin: |x|, |y| < seam_half.
    X     seam along x between the nodes (0, 0) and (period, 0).
    Z     seam along y between the nodes (0, 0) and (0, period).
    I<k>  cell interior between two X and two Z seams.
    Top tiles repeat by translation only; any fill variant fits any cell.

The junction between ring and top is resolved at run time (ring stones win, top stones that
overlap them are dropped): the top layer moves with the fill depth, the ring pile does not.
"""

from __future__ import annotations

import math
import random
import time

import numpy as np

import substrate_sim as sim

BIG = 0.05


def _rot_z(stones: np.ndarray, quarter_turns: int) -> np.ndarray:
    """Stones rotated about +z by quarter_turns x 90 degrees (counter-clockwise)."""
    out = stones.copy()
    angle = quarter_turns * math.pi / 2.0
    c, s = round(math.cos(angle)), round(math.sin(angle))
    out[:, 0] = c * stones[:, 0] - s * stones[:, 1]
    out[:, 1] = s * stones[:, 0] + c * stones[:, 1]
    # q' = qz * q, qz = (cos(a/2), 0, 0, sin(a/2))
    cw, sz = math.cos(angle / 2.0), math.sin(angle / 2.0)
    w, x, y, z = stones[:, 3], stones[:, 4], stones[:, 5], stones[:, 6]
    out[:, 3] = cw * w - sz * z
    out[:, 4] = cw * x - sz * y
    out[:, 5] = cw * y + sz * x
    out[:, 6] = cw * z + sz * w
    return out


def _shift(stones: np.ndarray, dx: float, dy: float) -> np.ndarray:
    out = stones.copy()
    out[:, 0] += dx
    out[:, 1] += dy
    return out


def _cat(parts: list[np.ndarray]) -> np.ndarray:
    parts = [p for p in parts if len(p)]
    return np.concatenate(parts) if parts else np.zeros((0, sim.STONE_COLS))


def _box(x0: float, x1: float, y0: float, y1: float, z0: float, z1: float) -> tuple:
    return (
        ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
        ((x1 - x0) / 2, (y1 - y0) / 2, (z1 - z0) / 2),
    )


def _walls(x0, x1, y0, y1, top, glass: set[str], physics: dict) -> list[tuple]:
    """Floor plus four side walls around the rectangle; sides named in `glass` are glass."""
    gf = physics.get("glass_friction", 0.3)
    tf = physics.get("temp_friction", 0.5)
    t = BIG
    out = [(*_box(x0 - t, x1 + t, y0 - t, y1 + t, -t, 0.0), gf)]
    out.append((*_box(x0 - t, x0, y0 - t, y1 + t, 0.0, top), gf if "x0" in glass else tf))
    out.append((*_box(x1, x1 + t, y0 - t, y1 + t, 0.0, top), gf if "x1" in glass else tf))
    out.append((*_box(x0 - t, x1 + t, y0 - t, y0, 0.0, top), gf if "y0" in glass else tf))
    out.append((*_box(x0 - t, x1 + t, y1, y1 + t, 0.0, top), gf if "y1" in glass else tf))
    return out


def _keep(stones: np.ndarray, x0: float, x1: float, y0: float, y1: float) -> np.ndarray:
    m = (stones[:, 0] >= x0) & (stones[:, 0] < x1) & (stones[:, 1] >= y0) & (stones[:, 1] < y1)
    return stones[m]


class TileBaker:
    def __init__(self, args: dict, params: dict, variants: sim.Variants, log) -> None:
        self.args = args
        self.params = params
        self.variants = variants
        self.log = log
        self.world = sim.SimWorld(variants, params["sim_scale"], params["physics"])
        self.classes = params["size_classes"]
        self.max_size = max(hi for _lo, hi, _s in self.classes)
        self.cell = params["height_cell_m"]
        self.sets: dict[str, np.ndarray] = {}
        self.timing: dict[str, float] = {}

    def _pour(
        self, name, rect, walls_rect, glass, static, target, keep_rect, fill_pits=False
    ) -> np.ndarray:
        # stones lean on the glass: the ring sets fall with the gravity tilted towards their
        # pane (the corner towards both)
        strength = float(self.params.get("ring", {}).get("lean_strength", 0.0))
        tilt = (-strength if "x0" in glass else 0.0, -strength if "y0" in glass else 0.0)
        lean = (lambda _x, _y: tilt) if strength > 0.0 and glass else None
        t0 = time.time()
        x0, x1, y0, y1 = rect
        wx0, wx1, wy0, wy1 = walls_rect
        self.world.set_walls(
            _walls(wx0, wx1, wy0, wy1, target + 0.6, glass, self.params["physics"])
        )
        region = sim.Region(x0, x1, y0, y1, 0.0, self.cell)
        rng = random.Random(f"{self.args['type']}|{name}|{self.args['seed']}")
        self.log(f"{name}: pour {rect} static {len(static)} target {target:.4f}")
        pour_params = dict(self.params["pour"])
        if not fill_pits:
            # Full-depth ring piles: aiming extra stones at pits made rows of small cavities at
            # the glass, at the height where one batch ended. Pits only matter for the shallow
            # top tiles, where a hole would reach down to the core.
            pour_params["pit_depth"] = self.params.get("ring_pit_depth_m", 1.0)
        placed = sim.pour(
            self.world, region, static, target, self.classes, rng, pour_params, self.log, lean
        )
        kept = _keep(placed, *keep_rect)
        self.sets[name] = kept
        self.timing[name] = round(time.time() - t0, 1)
        self.log(f"{name}: kept {len(kept)} of {len(placed)} in {self.timing[name]} s")
        return kept

    # ---- ring ----
    def bake_ring(self) -> None:
        ring = self.params["ring"]
        period, depth = ring["period_m"], ring["depth_m"]
        corner = ring.get("corner_m", depth)
        extra, h = ring["sim_extra_m"], ring["seam_half_m"]
        target = self.params["fill_depth_m"] + ring.get("overfill_m", self.params["overfill_m"])
        w = h + ring.get("seam_extra_m", self.max_size)
        far = depth + extra
        seam = self._pour(
            "E", (-w, w, 0.0, far), (-w, w, 0.0, far), {"y0"}, np.zeros((0, 9)), target,
            (-h, h, 0.0, depth),
        )
        for k in range(ring["fills"]):
            static = _cat([seam, _shift(seam, period, 0.0)])
            self._pour(
                f"F{k}", (0.0, period, 0.0, far), (-h, period + h, 0.0, far), {"y0"}, static,
                target, (0.0, period, 0.0, depth),
            )
        # corner: this pane's first seam at x = corner, the previous pane's last seam at
        # y = corner
        prev = _shift(_rot_z(seam, -1), 0.0, corner)
        static = _cat([_shift(seam, corner, 0.0), prev])
        kept = self._pour(
            "K", (0.0, corner, 0.0, corner), (0.0, corner + h, 0.0, corner + h), {"x0", "y0"},
            static, target, (0.0, corner, 0.0, corner),
        )
        if corner > depth:
            near_pane = (kept[:, 0] < depth) | (kept[:, 1] < depth)
            self.sets["K"] = kept[near_pane]
            self.log(f"K: {int(near_pane.sum())} of {len(kept)} within the ring depth")

    # ---- top ----
    def bake_top(self) -> None:
        top = self.params["top"]
        period, h = top["period_m"], top["seam_half_m"]
        target = top["thickness_m"] + top.get("overfill_m", self.params["overfill_m"])
        w = h + top.get("seam_extra_m", self.max_size)
        none = np.zeros((0, 9))
        node = self._pour("C", (-w, w, -w, w), (-w, w, -w, w), set(), none, target, (-h, h, -h, h), True)
        static = _cat([node, _shift(node, period, 0.0)])
        seam_x = self._pour(
            "X", (0.0, period, -w, w), (-h, period + h, -w, w), set(), static, target,
            (0.0, period, -h, h), True,
        )
        static = _cat([node, _shift(node, 0.0, period)])
        seam_z = self._pour(
            "Z", (-w, w, 0.0, period), (-w, w, -h, period + h), set(), static, target,
            (-h, h, 0.0, period), True,
        )
        frame = _cat(
            [
                node,
                _shift(node, period, 0.0),
                _shift(node, 0.0, period),
                _shift(node, period, period),
                seam_x,
                _shift(seam_x, 0.0, period),
                seam_z,
                _shift(seam_z, period, 0.0),
            ]
        )
        for k in range(top["fills"]):
            self._pour(
                f"I{k}", (0.0, period, 0.0, period), (-h, period + h, -h, period + h), set(),
                frame, target, (0.0, period, 0.0, period), True,
            )


def trim_overlaps(sets: dict[str, np.ndarray], params: dict) -> dict[str, int]:
    """Drops the stones of a set whose centre lies in the band of a set that was settled before
    it, in place: a fill stone inside a seam band, a seam stone inside a node, a corner stone
    inside the seams it was poured against. Such a stone came to rest on top of the stones of the
    band, so a tile border would carry more top stones than the rest of the tile and show as a
    ridge (the tile grid of the look spike). Returns the number of stones dropped per set."""
    dropped: dict[str, int] = {}

    def keep(name: str, mask: np.ndarray) -> None:
        dropped[name] = int((~mask).sum())
        sets[name] = sets[name][mask]

    if "E" in sets:
        ring = params["ring"]
        period, depth, h = ring["period_m"], ring["depth_m"], ring["seam_half_m"]
        corner = ring.get("corner_m", depth)
        for k in range(ring["fills"]):
            s = sets[f"F{k}"]
            keep(f"F{k}", (s[:, 0] >= h) & (s[:, 0] < period - h))
        s = sets["K"]
        in_seam = (s[:, 0] >= corner - h) & (s[:, 1] < depth)
        in_previous = (s[:, 1] >= corner - h) & (s[:, 0] < depth)
        keep("K", ~(in_seam | in_previous))
    if "C" in sets:
        top = params["top"]
        period, h = top["period_m"], top["seam_half_m"]
        s = sets["X"]
        keep("X", (s[:, 0] >= h) & (s[:, 0] < period - h))
        s = sets["Z"]
        keep("Z", (s[:, 1] >= h) & (s[:, 1] < period - h))
        for k in range(top["fills"]):
            s = sets[f"I{k}"]
            inside = (s[:, 0] >= h) & (s[:, 0] < period - h)
            inside &= (s[:, 1] >= h) & (s[:, 1] < period - h)
            keep(f"I{k}", inside)
    return dropped


def bake_part(args: dict, params: dict, variants: sim.Variants, part: str, log) -> tuple[dict, dict]:
    """Pours one part ("ring" or "top") of a tile type. Returns (report, sets): the settling
    report of the part and its stone sets in the Blender frame."""
    baker = TileBaker(args, params, variants, log)
    if part == "ring":
        baker.bake_ring()
    elif part == "top":
        baker.bake_top()
    else:
        raise ValueError(f"unknown tile part {part!r}")
    report = baker.world.settling_report()
    report["timing_s"] = baker.timing
    report["sim_seconds"] = round(baker.world.sim_seconds, 1)
    return report, baker.sets
