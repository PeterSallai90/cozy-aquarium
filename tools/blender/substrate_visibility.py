"""Offline visibility pass of the substrate bake (#28, ADR 0011 rule 7): which settled stones are
ever seen, how open they are to the light, and the last clean-up before the data is written.

Used by bake_substrate.py (numpy only, runs in Blender's Python). All data here is in the Godot
frame, metres: x across, y up, z towards the viewer. A stone row is float32[9]: x, y, z, qx, qy,
qz, qw, size, variant.

For every stone of a set the pass answers "can this stone be seen from above, or through the
glass it lies against?". The stones are placed in their real neighbourhood (the seam sets and
neighbouring tiles around them), every stone is sampled as a cloud of surface points, and the
points are splatted into a depth buffer from several directions (straight and tilted). A stone
that wins at least `min_cells` buffer cells in any direction is visible.

Flags (bits of the packed integer, see bake_substrate.pack_flags):
- above:   visible from above;
- pane:    visible through a glass pane;
- behind:  not visible itself, but in the row behind the visible stones (its top within
           `top_keep_m` of the fill depth, or its near side within `glass_keep_m` of a pane), so a
           gap between visible stones shows a darker stone and not the core;
- exposure 0..15: how much of the stone is open to the light from above (its share of the depth
  buffer seen from above). The shader uses it as the stone's own shadowing, because stones cast
  no shadows.
Stones without a flag are not written. Stones whose top would end above the fill depth plus
`crop_above_m` are dropped, and stones that poke through a glass plane or the floor by a hair
(solver tolerance) are moved back inside, so no drawn stone leaves the tank.

Set frames: ring sets have the glass at z = 0, the interior at z < 0 and x along the glass (the
corner set K has its second glass at x = 0); a top tile I<k> covers x in [0, period), z in
(-period, 0] with the tile floor at y = 0 and holds the fill k together with the seam and node
stones on its borders; the tank set is in the tank frame.
"""

from __future__ import annotations

import math

import numpy as np

ABOVE = 1
PANE = 2
BEHIND = 4
FLOATS = 9
# Stones are kept this far inside a glass plane or the floor (metres).
INSIDE_MARGIN_M = 2e-6
REPORT_CELL_M = 0.005


def quat_matrix(q: np.ndarray) -> np.ndarray:
    """(n, 4) x, y, z, w quaternions to (n, 3, 3) rotation matrices."""
    x, y, z, w = q[:, 0], q[:, 1], q[:, 2], q[:, 3]
    m = np.empty((len(q), 3, 3), dtype=np.float32)
    m[:, 0, 0] = 1 - 2 * (y * y + z * z)
    m[:, 0, 1] = 2 * (x * y - z * w)
    m[:, 0, 2] = 2 * (x * z + y * w)
    m[:, 1, 0] = 2 * (x * y + z * w)
    m[:, 1, 1] = 1 - 2 * (x * x + z * z)
    m[:, 1, 2] = 2 * (y * z - x * w)
    m[:, 2, 0] = 2 * (x * z - y * w)
    m[:, 2, 1] = 2 * (y * z + x * w)
    m[:, 2, 2] = 1 - 2 * (x * x + y * y)
    return m


class Shapes:
    """The drawn shape of every variant at unit size in the Godot frame: the LOD0 vertices and
    triangles of a mesh class, or the ellipsoid semi-axes of the sand class."""

    def __init__(self, verts: list[np.ndarray], tris: list[np.ndarray], axes: np.ndarray,
                 ellipsoid: bool) -> None:
        self.verts = [v.astype(np.float32) for v in verts]
        self.tris = tris
        self.axes = axes.astype(np.float32)
        self.ellipsoid = ellipsoid

    def samples(self, target: int) -> list[np.ndarray]:
        """Surface points per variant: the vertices plus points inside every triangle."""
        out = []
        for pos, idx in zip(self.verts, self.tris, strict=True):
            a, b, c = pos[idx[:, 0]], pos[idx[:, 1]], pos[idx[:, 2]]
            per_tri = max(1, int(math.ceil(target / len(idx))))
            rng = np.random.default_rng(28)
            parts = [pos]
            for _ in range(per_tri):
                u = rng.random((len(idx), 1), dtype=np.float32)
                v = rng.random((len(idx), 1), dtype=np.float32)
                flip = (u + v) > 1.0
                u = np.where(flip, 1.0 - u, u)
                v = np.where(flip, 1.0 - v, v)
                parts.append(a + (b - a) * u + (c - a) * v)
            out.append(np.concatenate(parts))
        return out

    def extents(self, stones: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        """Exact lowest and highest drawn point of every stone on the three axes, (n, 3) each."""
        low = np.zeros((len(stones), 3), dtype=np.float64)
        high = np.zeros((len(stones), 3), dtype=np.float64)
        if len(stones) == 0:
            return low, high
        variant = stones[:, 8].astype(np.int32) & 15
        rot = quat_matrix(stones[:, 3:7]).astype(np.float64)
        size = stones[:, 7].astype(np.float64)
        centre = stones[:, 0:3].astype(np.float64)
        for vi in range(len(self.axes)):
            sel = np.nonzero(variant == vi)[0]
            if len(sel) == 0:
                continue
            if self.ellipsoid:
                reach = np.sqrt(np.sum((rot[sel] * self.axes[vi].astype(np.float64)) ** 2, axis=2))
                reach *= size[sel][:, None]
                low[sel] = centre[sel] - reach
                high[sel] = centre[sel] + reach
            else:
                verts = self.verts[vi].astype(np.float64)
                world = np.einsum("nij,kj->nki", rot[sel], verts) * size[sel][:, None, None]
                low[sel] = centre[sel] + world.min(axis=1)
                high[sel] = centre[sel] + world.max(axis=1)
        return low, high

    def top_points(self, stones: np.ndarray, floor_y: float) -> np.ndarray:
        """World points whose height the surface report reads: every LOD0 vertex of a mesh stone,
        the highest point of an ellipsoid grain. Only stones that reach above `floor_y`."""
        low, high = self.extents(stones)
        del low
        keep = high[:, 1] >= floor_y
        stones = stones[keep]
        if len(stones) == 0:
            return np.zeros((0, 3))
        if self.ellipsoid:
            points = stones[:, 0:3].astype(np.float64).copy()
            points[:, 1] = high[keep][:, 1]
            return points
        variant = stones[:, 8].astype(np.int32) & 15
        rot = quat_matrix(stones[:, 3:7]).astype(np.float64)
        parts = []
        for vi in range(len(self.verts)):
            sel = np.nonzero(variant == vi)[0]
            if len(sel) == 0:
                continue
            verts = self.verts[vi].astype(np.float64)
            world = np.einsum("nij,kj->nki", rot[sel], verts) * stones[sel, 7][:, None, None]
            world += stones[sel, 0:3][:, None, :]
            parts.append(world.reshape(-1, 3))
        return np.concatenate(parts)


class Cloud:
    """World-space sample points of a list of stones, with the index of the owning stone."""

    def __init__(self, stones: np.ndarray, samples: list[np.ndarray], blockers=None) -> None:
        variant = stones[:, 8].astype(np.int32) & 15
        rot = quat_matrix(stones[:, 3:7])
        pts = []
        owner = []
        for vi, sample in enumerate(samples):
            sel = np.nonzero(variant == vi)[0]
            if len(sel) == 0:
                continue
            world = np.einsum("nij,kj->nki", rot[sel], sample) * stones[sel, 7][:, None, None]
            world += stones[sel, 0:3][:, None, :]
            pts.append(world.reshape(-1, 3))
            owner.append(np.repeat(sel, len(sample)))
        if blockers is not None and len(blockers):
            # opaque filler (the core): it can win cells but is no stone
            pts.append(blockers.astype(np.float32))
            owner.append(np.full(len(blockers), len(stones)))
        self.points = np.concatenate(pts).astype(np.float32)
        self.owner = np.concatenate(owner)
        self.count = len(stones) + 1

    def visible(self, direction, cell: float) -> np.ndarray:
        """Per stone: the number of depth buffer cells it wins looking along `direction` (from
        the viewer into the scene)."""
        d = np.array(direction, dtype=np.float32)
        d /= np.linalg.norm(d)
        helper = np.array([1.0, 0.0, 0.0], dtype=np.float32)
        if abs(d[0]) > 0.8:
            helper = np.array([0.0, 1.0, 0.0], dtype=np.float32)
        e1 = np.cross(d, helper)
        e1 /= np.linalg.norm(e1)
        e2 = np.cross(d, e1)
        u = np.floor(self.points @ e1 / cell).astype(np.int64)
        v = np.floor(self.points @ e2 / cell).astype(np.int64)
        depth = self.points @ d
        u -= u.min()
        v -= v.min()
        key = u * (int(v.max()) + 1) + v
        # nearest point per cell: sort by depth descending, the last write per cell wins
        order = np.argsort(-depth, kind="stable")
        winner = np.full(int(key.max()) + 1, -1, dtype=np.int64)
        winner[key[order]] = self.owner[order]
        wins = np.bincount(winner[winner >= 0], minlength=self.count)
        return wins[: self.count - 1]


def directions(axis: tuple, side_a: tuple, side_b: tuple, both: bool = True) -> list[np.ndarray]:
    """The straight view along `axis` plus views tilted by 35 and 60 degrees towards +-side_a and
    +side_b (and -side_b when `both`)."""
    a = np.array(axis, dtype=np.float32)
    out = [a]
    for tilt in (35.0, 60.0):
        t = math.tan(math.radians(tilt))
        tilts = ((1, 0), (-1, 0), (0, 1), (0, -1)) if both else ((1, 0), (-1, 0), (0, 1))
        for sx, sy in tilts:
            out.append(a + t * (sx * np.array(side_a, np.float32) + sy * np.array(side_b, np.float32)))
    return out


TOP_DIRS = directions((0, -1, 0), (1, 0, 0), (0, 0, 1))
# through a pane at z = 0 with the interior at z < 0: the viewer looks along -z; tilts stay
# moderate upwards because nobody looks up through the bed from below the floor
FRONT_DIRS = directions((0, 0, -1), (1, 0, 0), (0, -1, 0), False)
LEFT_DIRS = directions((1, 0, 0), (0, 0, 1), (0, -1, 0), False)


def shift(stones: np.ndarray, dx: float, dz: float) -> np.ndarray:
    out = stones.copy()
    out[:, 0] += dx
    out[:, 2] += dz
    return out


def turn_y(stones: np.ndarray, quarter_turns: int) -> np.ndarray:
    """Stones rotated about +y by quarter_turns x 90 degrees (Godot sense)."""
    out = stones.copy()
    angle = quarter_turns * math.pi / 2.0
    c, s = round(math.cos(angle)), round(math.sin(angle))
    out[:, 0] = c * stones[:, 0] + s * stones[:, 2]
    out[:, 2] = -s * stones[:, 0] + c * stones[:, 2]
    # q' = qy * q with qy = (0, sin(a / 2), 0, cos(a / 2)) as x, y, z, w
    sy, cw = math.sin(angle / 2.0), math.cos(angle / 2.0)
    x, y, z, w = stones[:, 3], stones[:, 4], stones[:, 5], stones[:, 6]
    out[:, 3] = cw * x + sy * z
    out[:, 4] = cw * y + sy * w
    out[:, 5] = cw * z - sy * x
    out[:, 6] = cw * w - sy * y
    return out


def evaluate(stones: np.ndarray, cloud: Cloud, cell: float, dirs_top, dirs_glass,
             min_cells: int) -> tuple[np.ndarray, np.ndarray]:
    """Per stone: the visibility flags (ABOVE, PANE) and the exposure 0..15."""
    flags = np.zeros(len(stones), dtype=np.int32)
    # a fully open stone lying flat covers about half of its bounding square
    full = 0.5 * (stones[:, 7] / cell) ** 2
    exposure = np.zeros(len(stones), dtype=np.float32)
    for i, d in enumerate(dirs_top):
        wins = cloud.visible(d, cell)
        flags |= np.where(wins >= min_cells, ABOVE, 0)
        weight = 1.0 if i == 0 else 0.75
        exposure = np.maximum(exposure, weight * wins / full)
    for d in dirs_glass:
        flags |= np.where(cloud.visible(d, cell) >= min_cells, PANE, 0)
    quantised = np.clip(np.round(exposure * 15.0), 0, 15).astype(np.int32)
    return flags, quantised


def flags_for(context, samples, cell, dirs_top, dirs_glass, min_cells, head: int = 1,
              blockers=None) -> list[tuple[np.ndarray, np.ndarray]]:
    """Flags and exposure of the stones of the first `head` sets of `context`, evaluated with all
    of `context` (and the opaque `blockers` points) present."""
    stones = np.concatenate(context)
    cloud = Cloud(stones, samples, blockers)
    flags, exposure = evaluate(stones, cloud, cell, dirs_top, dirs_glass, min_cells)
    out = []
    start = 0
    for i in range(head):
        end = start + len(context[i])
        out.append((flags[start:end], exposure[start:end]))
        start = end
    return out


def wall(x0: float, x1: float, y0: float, y1: float, z: float, step: float) -> np.ndarray:
    """Opaque points on the plane z = const (the core face behind the ring)."""
    xs = np.arange(x0, x1, step, dtype=np.float32)
    ys = np.arange(y0, y1, step, dtype=np.float32)
    gx, gy = np.meshgrid(xs, ys)
    return np.stack([gx.reshape(-1), gy.reshape(-1), np.full(gx.size, z, dtype=np.float32)], axis=1)


def merge(a: tuple, b: tuple) -> tuple[np.ndarray, np.ndarray]:
    """Two results of the same stones in different neighbourhoods: flags are OR-ed, the exposure
    is the larger one."""
    return a[0] | b[0], np.maximum(a[1], b[1])


def keep_inside(stones: np.ndarray, shapes: Shapes, planes: list[tuple[int, float, float]]) -> int:
    """Moves stones that poke through a plane back inside, in place. `planes`: (axis, position,
    side) with side +1 when the inside is at larger coordinates. Returns how many were moved."""
    moved = np.zeros(len(stones), dtype=bool)
    for axis, position, side in planes:
        low, high = shapes.extents(stones)
        if side > 0:
            over = (position + INSIDE_MARGIN_M) - low[:, axis]
        else:
            over = high[:, axis] - (position - INSIDE_MARGIN_M)
        push = over > 0.0
        stones[push, axis] += (side * over[push]).astype(np.float32)
        moved |= push
    return int(moved.sum())


def behind_mask(stones: np.ndarray, shapes: Shapes, top_limit: float, glass: list[np.ndarray],
                top_keep: float, glass_keep: float) -> np.ndarray:
    """True for the stones of the row behind the visible ones: the top within `top_keep` of the
    surface (top_limit = fill depth in the frame of the set) or the near side within `glass_keep`
    of a pane. `glass` holds the distance of every stone centre to each pane of the set."""
    if top_keep <= 0.0 and glass_keep <= 0.0:
        return np.zeros(len(stones), dtype=bool)
    _low, high = shapes.extents(stones)
    mask = high[:, 1] >= top_limit - top_keep if top_keep > 0.0 else np.zeros(len(stones), bool)
    reach = stones[:, 7] * 0.35
    for distance in glass:
        mask |= (distance - reach) <= glass_keep
    return mask


def height_field(points: np.ndarray, x0: float, z0: float, nx: int, nz: int) -> np.ndarray:
    """The highest point per 5 mm cell of the rectangle starting at (x0, z0); cells without a
    point hold 0."""
    field = np.zeros((nx, nz))
    ix = np.floor((points[:, 0] - x0) / REPORT_CELL_M).astype(np.int64)
    iz = np.floor((points[:, 2] - z0) / REPORT_CELL_M).astype(np.int64)
    inside = (ix >= 0) & (ix < nx) & (iz >= 0) & (iz < nz)
    np.maximum.at(field, (ix[inside], iz[inside]), points[inside, 1])
    return field


def paint(grid: np.ndarray, cell: float, origin: tuple[float, float], lo: np.ndarray,
          hi: np.ndarray, ellipse: bool) -> None:
    """Marks the cells of `grid` (columns x rows) whose centres lie in the rectangles lo..hi (or
    in the ellipses inscribed in them); at least the cell of each rectangle centre is marked.
    The same rule as the coverage checks of the game tests (tests/helpers/substrate_geometry.gd)."""
    cols, rows = grid.shape
    for a, b in zip(lo, hi, strict=True):
        c0 = int(np.clip(math.floor((a[0] - origin[0]) / cell), 0, cols - 1))
        c1 = int(np.clip(math.floor((b[0] - origin[0]) / cell), 0, cols - 1))
        r0 = int(np.clip(math.floor((a[1] - origin[1]) / cell), 0, rows - 1))
        r1 = int(np.clip(math.floor((b[1] - origin[1]) / cell), 0, rows - 1))
        centre = (a + b) / 2.0
        half = np.maximum((b - a) / 2.0, 1e-9)
        px = origin[0] + (np.arange(c0, c1 + 1) + 0.5) * cell
        py = origin[1] + (np.arange(r0, r1 + 1) + 0.5) * cell
        if ellipse:
            inside = (
                ((px[:, None] - centre[0]) / half[0]) ** 2
                + ((py[None, :] - centre[1]) / half[1]) ** 2
            ) <= 1.0
        else:
            inside = np.ones((len(px), len(py)), dtype=bool)
        if inside.any():
            grid[c0 : c1 + 1, r0 : r1 + 1] |= inside
        else:
            cc = int(np.clip(math.floor((centre[0] - origin[0]) / cell), 0, cols - 1))
            cr = int(np.clip(math.floor((centre[1] - origin[1]) / cell), 0, rows - 1))
            grid[cc, cr] = True


def spread(values: np.ndarray) -> dict:
    return {
        "mean_mm": round(float(values.mean()) * 1000.0, 3),
        "min_mm": round(float(values.min()) * 1000.0, 3),
        "max_mm": round(float(values.max()) * 1000.0, 3),
    }


class Pass:
    """One visibility pass over the sets of a data set."""

    def __init__(self, params: dict, shapes: Shapes, log) -> None:
        self.params = params
        self.shapes = shapes
        self.log = log
        self.fill = params["fill_depth_m"]
        keep = params.get("keep", {})
        self.top_keep = keep.get("top_keep_m", 0.0)
        self.glass_keep = keep.get("glass_keep_m", 0.0)
        self.crop_above = keep["crop_above_m"]
        vis = params.get("visibility", {})
        self.min_cells = int(vis.get("min_cells", 4))
        self.cell = min(c[0] for c in params["size_classes"]) * vis.get("cell_share", 0.3)
        self.samples = shapes.samples(int(vis.get("samples", 300)))
        self.statistics: dict[str, dict] = {}
        self.report: dict = {}

    # ---- shared steps ----
    def _crop(self, name: str, stones: np.ndarray, base_y: float) -> np.ndarray:
        """Drops the stones whose top ends above the fill depth plus crop_above."""
        _low, high = self.shapes.extents(stones)
        keep = high[:, 1] + base_y <= self.fill + self.crop_above
        self.statistics.setdefault(name, {})["cropped"] = int((~keep).sum())
        return stones[keep]

    def _finish(self, name: str, stones: np.ndarray, result: tuple, behind: np.ndarray):
        flags, exposure = result
        flags = flags.copy()
        flags[(flags == 0) & behind] = BEHIND
        keep = flags != 0
        stats = self.statistics.setdefault(name, {})
        stats.update(
            {
                "settled": int(len(stones)),
                "above": int(((flags & ABOVE) > 0).sum()),
                "pane": int(((flags & PANE) > 0).sum()),
                "behind": int(((flags & BEHIND) > 0).sum()),
                "written": int(keep.sum()),
            }
        )
        return stones[keep], flags[keep], exposure[keep]

    def _report_cell(self) -> float:
        """The cell of the coverage checks: max(2 mm, median drawn size)."""
        acc = 0.0
        median = 0.0
        for lo, hi, share in sorted(self.params["size_classes"]):
            if acc + share >= 0.5:
                median = lo + (hi - lo) * (0.5 - acc) / share
                break
            acc += share
        self.median = median
        return max(0.002, median)

    def _contact_share(self, stones: np.ndarray, axis: int, plane: float, side: float,
                       u_axis: int, u0: float, u1: float) -> float:
        """Share of the glass cells (floor to the fill depth) that hold a stone whose near side is
        within 1 mm of the pane at `plane` (the interior on the `side` of it)."""
        cell = self._report_cell()
        low, high = self.shapes.extents(stones)
        near = (low[:, axis] - plane) if side > 0 else (plane - high[:, axis])
        touch = (near <= 0.001) & (near >= -1e-5)
        grid = np.zeros(
            (math.ceil((u1 - u0) / cell - 1e-6), math.ceil(self.fill / cell - 1e-6)), dtype=bool
        )
        paint(grid, cell, (u0, 0.0), low[touch][:, [u_axis, 1]], high[touch][:, [u_axis, 1]], True)
        return round(float(grid.mean()), 4)

    def _top_cover(self, stones: np.ndarray, base_y: float, x0: float, x1: float, z0: float,
                   z1: float) -> float:
        """Share of the top cells covered by the footprint of a stone whose top reaches the fill
        depth minus T_mean = max(1 mm, 0.25 x median)."""
        cell = self._report_cell()
        t_mean = max(0.001, 0.25 * self.median)
        low, high = self.shapes.extents(stones)
        reach = high[:, 1] + base_y >= self.fill - t_mean
        grid = np.zeros(
            (math.ceil((x1 - x0) / cell - 1e-6), math.ceil((z1 - z0) / cell - 1e-6)), dtype=bool
        )
        paint(grid, cell, (x0, z0), low[reach][:, [0, 2]], high[reach][:, [0, 2]],
              self.shapes.ellipsoid)
        return round(float(grid.mean()), 4)

    # ---- whole-tank data (pebbles) ----
    def run_tank(self, tank: np.ndarray, lx: float, lz: float) -> dict:
        tank = self._crop("tank", tank.copy(), 0.0)
        moved = keep_inside(
            tank,
            self.shapes,
            [(1, 0.0, 1.0), (0, -lx / 2, 1.0), (0, lx / 2, -1.0), (2, -lz / 2, 1.0),
             (2, lz / 2, -1.0)],
        )
        self.statistics["tank"]["moved_inside"] = moved
        cloud = Cloud(tank, self.samples)
        panes = [
            directions((0, 0, -1), (1, 0, 0), (0, -1, 0), False),
            directions((0, 0, 1), (1, 0, 0), (0, -1, 0), False),
            directions((-1, 0, 0), (0, 0, 1), (0, -1, 0), False),
            directions((1, 0, 0), (0, 0, 1), (0, -1, 0), False),
        ]
        glass_dirs = [d for pane in panes for d in pane]
        result = evaluate(tank, cloud, self.cell, TOP_DIRS, glass_dirs, self.min_cells)
        glass = [
            lz / 2 - tank[:, 2],
            lz / 2 + tank[:, 2],
            lx / 2 - tank[:, 0],
            lx / 2 + tank[:, 0],
        ]
        behind = behind_mask(tank, self.shapes, self.fill, glass, self.top_keep, self.glass_keep)
        out = {"tank": self._finish("tank", tank, result, behind)}
        # surface report: the top height field of the written stones
        written = out["tank"][0]
        points = self.shapes.top_points(written, 0.0)
        nx, nz = round(lx / REPORT_CELL_M), round(lz / REPORT_CELL_M)
        field = height_field(points, -lx / 2, -lz / 2, nx, nz)
        self.report = {
            "field": spread(field),
            "edge_front": spread(field[:, -1]),
            "edge_back": spread(field[:, 0]),
            "edge_left": spread(field[0, :]),
            "edge_right": spread(field[-1, :]),
            "contact_front": self._contact_share(written, 2, lz / 2, -1.0, 0, -lx / 2, lx / 2),
            "contact_back": self._contact_share(written, 2, -lz / 2, 1.0, 0, -lx / 2, lx / 2),
            "contact_left": self._contact_share(written, 0, -lx / 2, 1.0, 2, -lz / 2, lz / 2),
            "contact_right": self._contact_share(written, 0, lx / 2, -1.0, 2, -lz / 2, lz / 2),
            "top_cover": self._top_cover(written, 0.0, -lx / 2, lx / 2, -lz / 2, lz / 2),
            "lowest_mm": round(float(self.shapes.extents(written)[0][:, 1].min()) * 1000.0, 4),
            "highest_mm": round(float(self.shapes.extents(written)[1][:, 1].max()) * 1000.0, 4),
        }
        return out

    # ---- tile data ----
    def run_ring(self, sets: dict[str, np.ndarray]) -> dict:
        ring = self.params["ring"]
        period, depth, fills = ring["period_m"], ring["depth_m"], ring["fills"]
        corner_size = ring.get("corner_m", depth)
        floor_and_glass = [(1, 0.0, 1.0), (2, 0.0, -1.0)]
        clean: dict[str, np.ndarray] = {}
        for name in ["E"] + [f"F{k}" for k in range(fills)] + ["K"]:
            stones = self._crop(name, sets[name].copy(), 0.0)
            planes = floor_and_glass + ([(0, 0.0, 1.0)] if name == "K" else [])
            self.statistics[name]["moved_inside"] = keep_inside(stones, self.shapes, planes)
            clean[name] = stones
        seam = clean["E"]
        fill = [clean[f"F{k}"] for k in range(fills)]
        corner = clean["K"]
        results: dict[str, tuple] = {}
        seam_result = (np.zeros(len(seam), np.int32), np.zeros(len(seam), np.int32))
        # The core stands behind the ring below the top layers: nothing is seen from the inside.
        core_top = self.fill - self.params["top"]["thickness_m"] * 0.6
        back = wall(-period, 2 * period, 0.0, core_top, -depth - self.cell, self.cell * 0.5)
        for k in range(fills):
            left = fill[(k + 1) % fills]
            right = fill[(k + 2) % fills]
            context = [
                fill[k],
                seam,
                shift(seam, period, 0.0),
                shift(left, -period, 0.0),
                shift(right, period, 0.0),
                shift(seam, -period, 0.0),
                shift(seam, 2 * period, 0.0),
            ]
            got = flags_for(
                context, self.samples, self.cell, TOP_DIRS, FRONT_DIRS, self.min_cells, 2, back
            )
            results[f"F{k}"] = got[0]
            seam_result = merge(seam_result, got[1])
        results["E"] = seam_result
        # corner: its own pane (z = 0) and the previous pane (x = 0); neighbours on both sides.
        # A set of the previous pane row is turned by a quarter and ends `corner_size` from the
        # corner along the second glass.
        context = [
            corner,
            shift(seam, corner_size, 0.0),
            shift(fill[0], corner_size, 0.0),
            shift(turn_y(seam, -1), 0.0, -corner_size),
            shift(turn_y(fill[1 % fills], -1), 0.0, -corner_size - period),
        ]
        results["K"] = flags_for(
            context, self.samples, self.cell, TOP_DIRS, FRONT_DIRS + LEFT_DIRS, self.min_cells
        )[0]
        out = {}
        for name, stones in clean.items():
            glass = [-stones[:, 2]] + ([stones[:, 0]] if name == "K" else [])
            behind = behind_mask(
                stones, self.shapes, self.fill, glass, self.top_keep, self.glass_keep
            )
            out[name] = self._finish(name, stones, results[name], behind)
        # surface report: the top edge at the glass and the strip behind it, per fill
        cells = round(period / REPORT_CELL_M)
        rows = max(1, round(depth / REPORT_CELL_M))
        edges = []
        strips = []
        for k in range(fills):
            parts = [out[f"F{k}"][0], out["E"][0], shift(out["E"][0], period, 0.0)]
            points = self.shapes.top_points(np.concatenate(parts), self.fill * 0.5)
            field = height_field(points, 0.0, -rows * REPORT_CELL_M, cells, rows)
            edges.append(field[:, -1])
            strips.append(field.reshape(-1))
            self.report[f"ring_contact_F{k}"] = self._contact_share(
                np.concatenate(parts), 2, 0.0, -1.0, 0, 0.0, period
            )
        self.report["ring_edge"] = spread(np.concatenate(edges))
        self.report["ring_strip"] = spread(np.concatenate(strips))
        return out

    def run_top(self, sets: dict[str, np.ndarray]) -> dict:
        top = self.params["top"]
        period, fills = top["period_m"], top["fills"]
        base = self.fill - top["thickness_m"]
        clean = {
            name: self._crop(name, sets[name].copy(), base)
            for name in ["C", "X", "Z"] + [f"I{k}" for k in range(fills)]
        }
        node, seam_x, seam_z = clean["C"], clean["X"], clean["Z"]
        fill = [clean[f"I{k}"] for k in range(fills)]
        # A written top tile I<k> is everything whose centre lies in the cell: the fill and the
        # pieces of the frame (nodes and seams) on its four borders, with the flags they have in
        # the neighbourhood of that fill. The frame stones are therefore written once per fill:
        # a seam stone that one fill covers and another leaves open is drawn only where it shows.
        # (One merged frame for all fills carried about a fifth more stones than the rest of the
        # tile along every border.)
        out = {}
        cells = round(period / REPORT_CELL_M)
        fields = []
        for k in range(fills):
            pieces = [
                fill[k],
                node,
                seam_x,
                seam_z,
                shift(node, period, 0.0),
                shift(node, 0.0, -period),
                shift(node, period, -period),
                shift(seam_x, 0.0, -period),
                shift(seam_z, period, 0.0),
            ]
            others = []
            for i_a in (-1, 0, 1):
                for i_b in (-1, 0, 1):
                    dx, dz = i_a * period, -i_b * period
                    if (i_a, i_b) != (0, 0):
                        others.append(shift(fill[(k + i_a + 2 * i_b) % fills], dx, dz))
                    if (i_a, i_b) not in ((0, 0), (1, 0), (0, 1), (1, 1)):
                        others.append(shift(node, dx, dz))
                    if (i_a, i_b) not in ((0, 0), (0, 1)):
                        others.append(shift(seam_x, dx, dz))
                    if (i_a, i_b) not in ((0, 0), (1, 0)):
                        others.append(shift(seam_z, dx, dz))
            for i_a, i_b in ((2, -1), (2, 0), (2, 1), (-1, 2), (0, 2), (1, 2), (2, 2)):
                dx, dz = i_a * period, -i_b * period
                others.append(shift(node, dx, dz))
                if i_a < 2:
                    others.append(shift(seam_x, dx, dz))
                if i_b < 2:
                    others.append(shift(seam_z, dx, dz))
            got = flags_for(
                pieces + others, self.samples, self.cell, TOP_DIRS, [], self.min_cells,
                len(pieces),
            )
            stones = np.concatenate(pieces)
            flags = np.concatenate([g[0] for g in got])
            exposure = np.concatenate([g[1] for g in got])
            inside = (stones[:, 0] >= 0.0) & (stones[:, 0] < period)
            inside &= (stones[:, 2] > -period) & (stones[:, 2] <= 0.0)
            stones, flags, exposure = stones[inside], flags[inside], exposure[inside]
            behind = behind_mask(stones, self.shapes, top["thickness_m"], [], self.top_keep, 0.0)
            name = f"I{k}"
            out[name] = self._finish(name, stones, (flags, exposure), behind)
            # surface report: the top height field of the tile
            points = self.shapes.top_points(out[name][0], top["thickness_m"] * 0.5)
            field = height_field(points, 0.0, -period, cells, cells) + base
            fields.append(field.reshape(-1))
            self.report[f"top_cover_I{k}"] = self._top_cover(
                out[name][0], base, 0.0, period, -period, 0.0
            )
        self.report["top_field"] = spread(np.concatenate(fields))
        return out

    def lift_top(self, written: dict, lift: float) -> None:
        """Applies the lift of the top layer to the report and drops the few top stones that
        would end above the crop limit after it. `written` is changed in place."""
        base = self.fill - self.params["top"]["thickness_m"] + lift
        fills = self.params["top"]["fills"]
        for name in [f"I{k}" for k in range(fills)]:
            stones, flags, exposure = written[name]
            _low, high = self.shapes.extents(stones)
            keep = high[:, 1] + base <= self.fill + self.crop_above
            self.statistics[name]["cropped"] += int((~keep).sum())
            self.statistics[name]["written"] = int(keep.sum())
            written[name] = (stones[keep], flags[keep], exposure[keep])
        self.report["top_lift_mm"] = round(lift * 1000.0, 3)
