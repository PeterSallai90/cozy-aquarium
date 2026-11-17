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

The data file holds the ring sets as poured and, for the top, one whole tile I<k> per fill: the
fill together with the node and seam stones on its borders (substrate_visibility.py).
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
        # The seams settle a little higher in their narrow trough than a fill poured to the same
        # target, which leaves a low band in the middle of every tile; `fill_overfill_m` pours
        # the fills that much higher (the lift of the layer then re-centres the mean surface).
        fill_target = target + top.get("fill_overfill_m", 0.0)
        for k in range(top["fills"]):
            self._pour(
                f"I{k}", (0.0, period, 0.0, period), (-h, period + h, -h, period + h), set(),
                frame, fill_target, (0.0, period, 0.0, period), True,
            )


def trim_overlaps(sets: dict[str, np.ndarray], params: dict) -> dict[str, int]:
    """Drops the stones of a set whose centre lies in the band of a set that was settled before
    it, in place: a fill stone inside a seam band, a seam stone inside a node, a corner stone
    inside the seams it was poured against. Such a stone came to rest on top of the stones of the
    band, so a tile border would carry more top stones than the rest of the tile and show as a
    ridge (the tile grid of the look spike). `seam_trim_share` of the type (default 1) is the
    share of the band, from its middle, that is cleared: stones as large as the band is wide
    also fill the flanks of the band, and dropping those would leave a groove along the border.
    Returns the number of stones dropped per set."""
    dropped: dict[str, int] = {}
    share = float(params.get("seam_trim_share", 1.0))

    def keep(name: str, mask: np.ndarray) -> None:
        dropped[name] = int((~mask).sum())
        sets[name] = sets[name][mask]

    if "E" in sets:
        ring = params["ring"]
        period, depth, h = ring["period_m"], ring["depth_m"], ring["seam_half_m"] * share
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
        period, h = top["period_m"], top["seam_half_m"] * share
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


def _surface_samples(variants: sim.Variants, per_stone: int) -> list[np.ndarray]:
    """Points on the LOD0 surface of every variant at unit size (vertices plus seeded points
    inside the triangles), Blender frame."""
    out = []
    rng = np.random.default_rng(28)
    for variant in variants.variants:
        verts = np.asarray(variant["lods"][0]["verts"], dtype=float)
        tris = np.asarray(variant["lods"][0]["tris"], dtype=int)
        a, b, c = verts[tris[:, 0]], verts[tris[:, 1]], verts[tris[:, 2]]
        parts = [verts]
        for _ in range(max(1, per_stone // max(1, len(tris)))):
            u = rng.random((len(tris), 1))
            v = rng.random((len(tris), 1))
            flip = (u + v) > 1.0
            u = np.where(flip, 1.0 - u, u)
            v = np.where(flip, 1.0 - v, v)
            parts.append(a + (b - a) * u + (c - a) * v)
        out.append(np.concatenate(parts))
    return out


def _top_heights(
    stones: np.ndarray, samples: list[np.ndarray], period: float, cell: float
) -> np.ndarray:
    """The highest drawn point per `cell` over the top cell 0 <= x, y < period (Blender frame),
    from points on the stone surfaces. Cells without a stone read 0 (the tile floor)."""
    n = max(1, int(round(period / cell)))
    grid = np.zeros((n, n))
    if len(stones) == 0:
        return grid
    rot = sim.quat_to_matrix(stones[:, 3:7])
    variant = stones[:, 8].astype(int)
    for vi, points in enumerate(samples):
        sel = np.nonzero(variant == vi)[0]
        if len(sel) == 0:
            continue
        world = np.einsum("nij,kj->nki", rot[sel], points) * stones[sel, 7][:, None, None]
        world = (world + stones[sel, 0:3][:, None, :]).reshape(-1, 3)
        ix = np.floor(world[:, 0] / cell).astype(int)
        iy = np.floor(world[:, 1] / cell).astype(int)
        inside = (ix >= 0) & (ix < n) & (iy >= 0) & (iy < n)
        np.maximum.at(grid, (ix[inside], iy[inside]), world[inside, 2])
    return grid


def _low_spots(low: np.ndarray, minimum: int) -> list[list[tuple[int, int]]]:
    """Connected (4-neighbour) groups of True cells with at least `minimum` cells."""
    seen = np.zeros_like(low, dtype=bool)
    groups = []
    n, m = low.shape
    for i in range(n):
        for j in range(m):
            if not low[i, j] or seen[i, j]:
                continue
            stack = [(i, j)]
            seen[i, j] = True
            group = []
            while stack:
                a, b = stack.pop()
                group.append((a, b))
                for da, db in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    c, d = a + da, b + db
                    if 0 <= c < n and 0 <= d < m and low[c, d] and not seen[c, d]:
                        seen[c, d] = True
                        stack.append((c, d))
            if len(group) >= minimum:
                groups.append(group)
    return groups


def fill_top_holes(args: dict, params: dict, variants: sim.Variants, sets: dict, log) -> dict:
    """Top tiles: drops extra stones into the holes of every fill I<k> (params top.hole_fill).
    A fill is poured against frozen seam stones and settles looser in a band beside them, which
    leaves holes down to the core in rows along every tile border: a grid from above. A hole is
    a group of at least `min_cells` cells of `cell_m` in the band from the seam band out to
    `band_m` beyond it, whose highest drawn point (from `samples` points per stone surface) lies
    more than `low_m` below the pour target. One stone of the smallest
    size class falls into each hole onto the frozen frame and fill, `rounds` passes; a stone
    whose top would be cropped by the visibility pass is not kept. Adds the stones to the sets in
    place and returns the settling report."""
    top = params["top"]
    fill = top["hole_fill"]
    period, h = top["period_m"], top["seam_half_m"]
    target = top["thickness_m"] + top.get("overfill_m", params["overfill_m"])
    crop_top = top["thickness_m"] + params["keep"]["crop_above_m"] - 0.0005
    cell = fill.get("cell_m", 0.0005)
    low = fill["low_m"]
    band = fill.get("band_m", 1.0)
    samples = _surface_samples(variants, int(fill.get("samples", 400)))
    small = [min(params["size_classes"], key=lambda c: c[0])]
    world = sim.SimWorld(variants, params["sim_scale"], params["physics"])
    world.set_walls(
        _walls(-h, period + h, -h, period + h, target + 0.6, set(), params["physics"])
    )
    node, seam_x, seam_z = sets["C"], sets["X"], sets["Z"]
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
    n = max(1, int(round(period / cell)))
    centres = (np.arange(n) + 0.5) * cell
    border = np.minimum(
        np.minimum(centres[:, None], period - centres[:, None]),
        np.minimum(centres[None, :], period - centres[None, :]),
    )
    # the holes are looked for beside the seams: from the seam band out to `band_m` beyond it
    outside_seams = (border >= h) & (border < h + band)
    added_total = 0
    for k in range(top["fills"]):
        name = f"I{k}"
        rng = random.Random(f"{args['type']}|hole_fill|{name}|{args['seed']}")
        added = np.zeros((0, sim.STONE_COLS))
        for round_index in range(fill.get("rounds", 6)):
            everything = _cat([frame, sets[name], added])
            heights = _top_heights(everything, samples, period, cell)
            holes = _low_spots((heights < target - low) & outside_seams, fill.get("min_cells", 4))
            if not holes:
                break
            batch = []
            for group in holes:
                a, b = min(group, key=lambda c: heights[c[0], c[1]])
                size = sim.sample_size(rng, small)
                around = heights[max(0, a - 3) : a + 4, max(0, b - 3) : b + 4]
                q = sim.random_quat(rng)
                batch.append(
                    [
                        (a + 0.5) * cell,
                        (b + 0.5) * cell,
                        float(around.max()) + 0.6 * size,
                        q[0],
                        q[1],
                        q[2],
                        q[3],
                        size,
                        rng.randrange(len(variants.variants)),
                    ]
                )
            part = np.array(batch)
            reach = float(part[:, 2].min()) - 3.0 * float(part[:, 7].max())
            near = everything[everything[:, 2] + variants.vertical_half(everything) > reach]
            settled = world.run_batch(near, part, int(fill.get("frames", 200)))
            ok = np.isfinite(settled).all(axis=1) & (settled[:, 2] > 0.0)
            ok &= (settled[:, 0] >= 0.0) & (settled[:, 0] < period)
            ok &= (settled[:, 1] >= 0.0) & (settled[:, 1] < period)
            ok &= sim.drawn_tops(settled, variants) < crop_top
            added = _cat([added, settled[ok]])
            log(f"  {name} holes round {round_index}: {len(holes)} holes, {int(ok.sum())} kept")
        sets[name] = _cat([sets[name], added])
        added_total += len(added)
    log(f"top holes: {added_total} stones added")
    report = world.settling_report()
    report["sim_seconds"] = round(world.sim_seconds, 1)
    return report
