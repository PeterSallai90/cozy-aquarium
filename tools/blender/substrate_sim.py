"""Rigid-body settling of stones with Blender's Bullet world, for the substrate bake (#28).

Stones are poured in batches into a region bounded by walls (glass or temporary) and by stones
that already rest there. After each batch the settled stones are frozen: they become passive
convex hulls, and only the frozen stones the next batch can reach stay in the world. That keeps
Bullet at a few hundred to about 1,500 active convex hulls per run, well below the body counts
where it gets slow or unstable. (A merged static triangle mesh was tried first: about 8x slower,
because every hull is tested against every triangle of its neighbours.)

Units: stone data is in real metres in the Blender frame (z up). The simulation runs scaled up so
that the median stone is about one unit across (Bullet is unstable at millimetre scale).

A stone row is float64[9]: x, y, z, qw, qx, qy, qz, size, variant.

Settling report (ADR 0011 rule 8): a batch runs until 99.5 percent of its stones moved less than
`rest_tolerance` over `rest_check_frames`, then up to `rest_extra_frames` more until every stone
is below `rest_limit`. A stone that still moves faster after that is removed from the result, so
every stone that is written is at rest; SimWorld counts them and keeps the largest final speed.

Lean (stones lean on the glass): a batch may fall with the gravity tilted towards a pane, so the
stones slide against the glass and pack there like gravel poured against a wall. The tilt ends
before the settling does: every batch comes to rest under plain vertical gravity.
"""

from __future__ import annotations

import math
import random
import time

import bpy
import numpy as np

STONE_COLS = 9


def quat_to_matrix(q: np.ndarray) -> np.ndarray:
    """(n, 4) w, x, y, z quaternions to (n, 3, 3) rotation matrices."""
    w, x, y, z = q[:, 0], q[:, 1], q[:, 2], q[:, 3]
    m = np.empty((len(q), 3, 3))
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


def random_quat(rng: random.Random) -> list[float]:
    q = [rng.gauss(0, 1) for _ in range(4)]
    n = math.sqrt(sum(c * c for c in q))
    return [c / n for c in q]


class Variants:
    """Per-variant lookup tables built from substrate_stones.build_class()."""

    def __init__(self, variants: list[dict]) -> None:
        self.variants = variants
        self.half = np.array([v["half_extents"] for v in variants])
        self.volume = np.array([v["volume"] for v in variants])

    def vertical_half(self, stones: np.ndarray) -> np.ndarray:
        """Half height of each stone along world z (ellipsoid approximation of the stone)."""
        rot = quat_to_matrix(stones[:, 3:7])
        half = self.half[stones[:, 8].astype(int)]
        return np.sqrt(np.sum((rot[:, 2, :] * half) ** 2, axis=1)) * stones[:, 7]

    def axis_half(self, stones: np.ndarray, axis: int) -> np.ndarray:
        rot = quat_to_matrix(stones[:, 3:7])
        half = self.half[stones[:, 8].astype(int)]
        return np.sqrt(np.sum((rot[:, axis, :] * half) ** 2, axis=1)) * stones[:, 7]

    def merged_mesh(self, stones: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        """World-space vertices and triangles of the collision hulls of all `stones`."""
        verts: list[np.ndarray] = []
        tris: list[np.ndarray] = []
        offset = 0
        rot = quat_to_matrix(stones[:, 3:7])
        for vi, variant in enumerate(self.variants):
            sel = np.nonzero(stones[:, 8].astype(int) == vi)[0]
            if len(sel) == 0:
                continue
            pv = variant["phys_verts"]
            pt = variant["phys_tris"]
            world = np.einsum("nij,kj->nki", rot[sel], pv) * stones[sel, 7][:, None, None]
            world += stones[sel, 0:3][:, None, :]
            verts.append(world.reshape(-1, 3))
            idx = pt[None, :, :] + (np.arange(len(sel)) * len(pv))[:, None, None] + offset
            tris.append(idx.reshape(-1, 3))
            offset += len(sel) * len(pv)
        if not verts:
            return np.zeros((0, 3)), np.zeros((0, 3), dtype=np.int32)
        return np.concatenate(verts), np.concatenate(tris).astype(np.int32)


class SimWorld:
    """One Blender scene reused for many pours."""

    def __init__(self, variants: Variants, sim_scale: float, settings: dict) -> None:
        self.variants = variants
        self.k = sim_scale
        self.settings = settings
        self.walls: list[tuple[np.ndarray, np.ndarray, float]] = []
        self.sim_seconds = 0.0
        self.frames_run = 0
        self.batches_run = 0
        self.removed_moving = 0
        # largest speed of a kept stone at the end of its batch, real metres per second
        self.largest_final_speed = 0.0
        bpy.ops.wm.read_factory_settings(use_empty=True)
        self.scene = bpy.context.scene
        self.scene.unit_settings.system = "NONE"
        self.scene.gravity = (0.0, 0.0, -settings.get("gravity", 9.81))
        self.scene.render.fps = settings.get("fps", 60)
        self.collection = bpy.data.collections.new("sim")
        self.scene.collection.children.link(self.collection)
        bpy.ops.rigidbody.world_add()
        world = self.scene.rigidbody_world
        world.collection = self.collection
        world.substeps_per_frame = settings.get("substeps", 10)
        world.solver_iterations = settings.get("solver_iterations", 20)
        world.use_split_impulse = True
        world.point_cache.frame_start = 1
        world.point_cache.frame_end = 100000
        self.scene.frame_start = 1
        self.scene.frame_end = 100000
        self.phys_meshes = []
        for vi, variant in enumerate(variants.variants):
            mesh = bpy.data.meshes.new(f"phys_{vi}")
            mesh.from_pydata(variant["phys_verts"].tolist(), [], variant["phys_tris"].tolist())
            mesh.update()
            self.phys_meshes.append(mesh)
        self.cube = bpy.data.meshes.new("cube")
        cv = [(x, y, z) for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]
        cf = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
        self.cube.from_pydata(cv, [], cf)
        self.cube.update()

    # ---- scene helpers ----
    def _clear_objects(self) -> None:
        for ob in list(self.collection.objects):
            data = ob.data
            bpy.data.objects.remove(ob, do_unlink=True)
            if data is not None and data.users == 0 and data.name.startswith("static"):
                bpy.data.meshes.remove(data)

    def _add_rigid(self, objects: list, kind: str) -> None:
        if not objects:
            return
        with bpy.context.temp_override(
            scene=self.scene,
            selected_objects=objects,
            selected_editable_objects=objects,
            object=objects[0],
            active_object=objects[0],
        ):
            bpy.ops.rigidbody.objects_add(type=kind)

    def set_walls(self, walls: list[tuple]) -> None:
        """walls: (centre xyz, half extents xyz, friction) in real metres."""
        self.walls = [(np.array(c, float), np.array(h, float), float(f)) for c, h, f in walls]

    # ---- one pour ----
    def run_batch(
        self,
        static: np.ndarray,
        batch: np.ndarray,
        max_frames: int,
        lean: tuple[float, float] = (0.0, 0.0),
        lean_frames: int = 0,
    ) -> np.ndarray:
        """Simulates `batch` (start poses) on top of the frozen `static` stones; returns the
        settled poses of the stones that came to rest (the others are dropped and counted)."""
        t0 = time.time()
        k = self.k
        s = self.settings
        self._clear_objects()
        passive = []
        for centre, half, friction in self.walls:
            ob = bpy.data.objects.new("wall", self.cube)
            ob.location = (centre * k).tolist()
            ob.scale = (half * k).tolist()
            self.collection.objects.link(ob)
            ob["friction"] = friction
            passive.append(ob)
        frozen = []
        for row in static:
            ob = bpy.data.objects.new("f", self.phys_meshes[int(row[8])])
            ob.rotation_mode = "QUATERNION"
            ob.location = (row[0] * k, row[1] * k, row[2] * k)
            ob.rotation_quaternion = (row[3], row[4], row[5], row[6])
            size = row[7] * k
            ob.scale = (size, size, size)
            self.collection.objects.link(ob)
            frozen.append(ob)
        active = []
        for row in batch:
            ob = bpy.data.objects.new("s", self.phys_meshes[int(row[8])])
            ob.rotation_mode = "QUATERNION"
            ob.location = (row[0] * k, row[1] * k, row[2] * k)
            ob.rotation_quaternion = (row[3], row[4], row[5], row[6])
            size = row[7] * k
            ob.scale = (size, size, size)
            self.collection.objects.link(ob)
            active.append(ob)
        bpy.context.view_layer.update()
        self._add_rigid(passive + frozen, "PASSIVE")
        self._add_rigid(active, "ACTIVE")
        for ob in passive:
            rb = ob.rigid_body
            rb.collision_shape = "BOX"
            rb.friction = ob["friction"]
            rb.restitution = 0.0
            rb.use_margin = True
            rb.collision_margin = 0.0
        margin = s.get("margin", 0.02)
        for ob in frozen:
            rb = ob.rigid_body
            rb.collision_shape = "CONVEX_HULL"
            rb.friction = s.get("friction", 0.7)
            rb.restitution = 0.0
            rb.use_margin = True
            rb.collision_margin = margin
        for ob, row in zip(active, batch):
            rb = ob.rigid_body
            rb.collision_shape = "CONVEX_HULL"
            rb.mass = max(1e-3, (row[7] * k) ** 3)
            rb.friction = s.get("friction", 0.7)
            rb.restitution = s.get("restitution", 0.02)
            rb.use_margin = True
            rb.collision_margin = margin
            rb.linear_damping = s.get("linear_damping", 0.25)
            rb.angular_damping = s.get("angular_damping", 0.35)
            rb.use_deactivation = True
            rb.use_start_deactivated = False
            rb.deactivate_linear_velocity = s.get("sleep_linear", 0.25)
            rb.deactivate_angular_velocity = s.get("sleep_angular", 0.4)
        gravity = abs(float(self.scene.gravity[2]))
        leaning = lean_frames > 0 and (lean[0] != 0.0 or lean[1] != 0.0)
        if leaning:
            self.scene.gravity = (lean[0] * gravity, lean[1] * gravity, -gravity)
        else:
            lean_frames = 0
        self.scene.frame_set(1)
        last = None
        frame = 1
        rest_tol = s.get("rest_tolerance", 0.01)
        rest_limit = s.get("rest_limit", 0.02)
        check = s.get("rest_check_frames", 12)
        min_frames = s.get("min_frames", 60)
        extra_frames = s.get("rest_extra_frames", 96)
        moved = np.full(len(active), np.inf)
        calm_at = -1
        while True:
            frame += 1
            if leaning and frame > lean_frames:
                # from here on the batch settles under plain vertical gravity
                self.scene.gravity = (0.0, 0.0, -gravity)
                leaning = False
            self.scene.frame_set(frame)
            if frame % check != 0:
                continue
            pos = np.array([ob.matrix_world.translation[:] for ob in active])
            if last is not None:
                moved = np.linalg.norm(pos - last, axis=1)
            last = pos
            if calm_at < 0 and frame >= lean_frames + check:
                if frame >= min_frames and float(np.percentile(moved, 99.5)) < rest_tol:
                    calm_at = frame
                elif frame >= max_frames:
                    calm_at = frame
            if calm_at >= 0 and (float(moved.max()) < rest_limit or frame >= calm_at + extra_frames):
                break
        self.scene.gravity = (0.0, 0.0, -gravity)
        out = batch.copy()
        for i, ob in enumerate(active):
            loc, rot, _scale = ob.matrix_world.decompose()
            out[i, 0:3] = (loc.x / k, loc.y / k, loc.z / k)
            out[i, 3:7] = (rot.w, rot.x, rot.y, rot.z)
        at_rest = moved < rest_limit
        window = check / float(self.scene.render.fps)
        if at_rest.any():
            speed = float(moved[at_rest].max()) / window / k
            self.largest_final_speed = max(self.largest_final_speed, speed)
        self.removed_moving += int((~at_rest).sum())
        self.batches_run += 1
        self.frames_run += frame
        self.sim_seconds += time.time() - t0
        return out[at_rest]

    def rest_speed_limit(self) -> float:
        """The speed (real metres per second) below which a stone counts as at rest."""
        s = self.settings
        window = s.get("rest_check_frames", 12) / float(self.scene.render.fps)
        return s.get("rest_limit", 0.02) / window / self.k

    def settling_report(self) -> dict:
        return {
            "all_at_rest": True,
            "largest_final_speed_m_per_s": round(self.largest_final_speed, 9),
            "rest_speed_limit_m_per_s": round(self.rest_speed_limit(), 9),
            "removed_while_moving": int(self.removed_moving),
            "batches": int(self.batches_run),
            "frames": int(self.frames_run),
        }


class Region:
    """Axis-aligned pour region with a column height grid (real metres, Blender frame)."""

    def __init__(self, x0: float, x1: float, y0: float, y1: float, floor: float, cell: float):
        self.x0, self.x1, self.y0, self.y1 = x0, x1, y0, y1
        self.floor = floor
        self.nx = max(1, int(math.ceil((x1 - x0) / cell)))
        self.ny = max(1, int(math.ceil((y1 - y0) / cell)))
        self.cx = (x1 - x0) / self.nx
        self.cy = (y1 - y0) / self.ny

    def heights(self, stones: np.ndarray, variants: Variants) -> np.ndarray:
        """Top of the pile per grid column (floor where empty)."""
        grid = np.full((self.nx, self.ny), self.floor)
        if len(stones) == 0:
            return grid
        top = stones[:, 2] + variants.vertical_half(stones) * 0.85
        radius = stones[:, 7] * 0.3
        ix0 = np.clip(np.floor((stones[:, 0] - radius - self.x0) / self.cx).astype(int), 0, self.nx - 1)
        ix1 = np.clip(np.floor((stones[:, 0] + radius - self.x0) / self.cx).astype(int), 0, self.nx - 1)
        iy0 = np.clip(np.floor((stones[:, 1] - radius - self.y0) / self.cy).astype(int), 0, self.ny - 1)
        iy1 = np.clip(np.floor((stones[:, 1] + radius - self.y0) / self.cy).astype(int), 0, self.ny - 1)
        inside = (
            (stones[:, 0] + radius > self.x0)
            & (stones[:, 0] - radius < self.x1)
            & (stones[:, 1] + radius > self.y0)
            & (stones[:, 1] - radius < self.y1)
        )
        for i in np.nonzero(inside)[0]:
            block = grid[ix0[i] : ix1[i] + 1, iy0[i] : iy1[i] + 1]
            np.maximum(block, top[i], out=block)
        return grid


def sample_size(rng: random.Random, classes: list) -> float:
    r = rng.random()
    acc = 0.0
    for lo, hi, share in classes:
        acc += share
        if r <= acc:
            return rng.uniform(lo, hi)
    lo, hi, _share = classes[-1]
    return rng.uniform(lo, hi)


def pour(
    world: SimWorld,
    region: Region,
    static: np.ndarray,
    target_top: float,
    size_classes: list,
    rng: random.Random,
    params: dict,
    log=print,
    lean=None,
) -> np.ndarray:
    """Pours stones into `region` until every column reaches `target_top`. `static` stones are
    frozen colliders (already baked neighbours). Returns the new settled stones. `lean(x, y)`
    gives the sideways share of the gravity (towards a pane) a stone dropped at (x, y) falls
    with; stones with different leans settle in separate runs, one after the other."""
    variants = world.variants
    n_variants = len(variants.variants)
    max_size = max(hi for _lo, hi, _s in size_classes)
    mean_volume = float(
        np.mean([sample_size(rng, size_classes) ** 3 for _ in range(400)]) * variants.volume.mean()
    )
    spacing = max_size * params.get("lattice_spacing", 1.04)
    max_active = params.get("max_active", 1200)
    max_layers = params.get("max_layers", 6)
    placed = np.zeros((0, STONE_COLS))
    pit_rounds = 0
    ncol_x = max(1, int((region.x1 - region.x0) / spacing))
    ncol_y = max(1, int((region.y1 - region.y0) / spacing))
    step_x = (region.x1 - region.x0) / ncol_x
    step_y = (region.y1 - region.y0) / ncol_y
    for batch_index in range(params.get("max_batches", 60)):
        everything = np.concatenate([static, placed]) if len(static) else placed
        heights = region.heights(everything, variants)
        # A column counts as full when it or a direct neighbour reaches the target (the gaps
        # between stones never fill up).
        padded = np.pad(heights, 1, mode="edge")
        local = heights.copy()
        for dx in range(3):
            for dy in range(3):
                local = np.maximum(local, padded[dx : dx + region.nx, dy : dy + region.ny])
        deficit = np.clip(target_top - local, 0.0, None)
        # ... but a pit deeper than `pit_depth` is filled even when its neighbours are full, so no
        # hole reaches down through the visible layers
        pit = target_top - heights > params.get("pit_depth", max_size)
        if float(deficit.max()) <= 0.0:
            # only pits are left: a few rounds, then stop
            pit_rounds += 1
            if pit_rounds > params.get("pit_rounds", 8):
                break
        deficit = np.where(pit, np.maximum(deficit, target_top - heights), deficit)
        need_share = float((deficit > 0).mean())
        deficit_volume = float(deficit.sum() * region.cx * region.cy)
        if need_share < params.get("done_share", 0.015):
            break
        # lattice columns above grid cells that still need stones
        columns = []
        for ix in range(ncol_x):
            for iy in range(ncol_y):
                x = region.x0 + (ix + 0.5) * step_x
                y = region.y0 + (iy + 0.5) * step_y
                gx = min(region.nx - 1, int((x - region.x0) / region.cx))
                gy = min(region.ny - 1, int((y - region.y0) / region.cy))
                gx0, gx1 = max(0, gx - 1), min(region.nx, gx + 2)
                gy0, gy1 = max(0, gy - 1), min(region.ny, gy + 2)
                if float(deficit[gx0:gx1, gy0:gy1].max()) > 0.0:
                    # aim at the deepest spot under this lattice column
                    block = deficit[gx0:gx1, gy0:gy1]
                    bx, by = np.unravel_index(int(block.argmax()), block.shape)
                    if pit[gx0:gx1, gy0:gy1].any():
                        x = region.x0 + (gx0 + bx + 0.5) * region.cx
                        y = region.y0 + (gy0 + by + 0.5) * region.cy
                    columns.append((x, y))
        if not columns:
            break
        wanted = deficit_volume * params.get("packing", 0.6) / mean_volume
        wanted *= params.get("batch_fill", 1.0)
        layers = int(max(1, min(max_layers, math.ceil(wanted / len(columns)))))
        layers = max(1, min(layers, max_active // max(1, len(columns))))
        base = float(heights.max()) + spacing * 0.6
        rows = []
        jitter = (spacing - max_size) * 0.5 + max_size * 0.04
        for layer in range(layers):
            for x, y in columns:
                if layers == 1 and rng.random() > min(1.0, wanted / len(columns) + 0.15):
                    continue
                size = sample_size(rng, size_classes)
                q = random_quat(rng)
                rows.append(
                    [
                        x + rng.uniform(-jitter, jitter),
                        y + rng.uniform(-jitter, jitter),
                        base + layer * spacing + rng.uniform(0, jitter),
                        q[0],
                        q[1],
                        q[2],
                        q[3],
                        size,
                        rng.randrange(n_variants),
                    ]
                )
        if not rows:
            break
        batch = np.array(rows)
        fall = (layers * spacing + spacing) * world.k
        frames = int(
            params.get("settle_frames", 90)
            + world.scene.render.fps * math.sqrt(2.0 * fall / abs(world.scene.gravity[2])) * 1.6
        )
        t0 = time.time()
        # Only stones the new batch can reach are colliders: everything whose top is above the
        # lowest point of the current surface minus one stone.
        reach = float(heights.min()) - max_size
        if len(everything):
            near = everything[everything[:, 2] + variants.vertical_half(everything) > reach]
        else:
            near = everything
        groups: dict[tuple[float, float], list[int]] = {}
        for index, row in enumerate(rows):
            key = (0.0, 0.0) if lean is None else lean(row[0], row[1])
            groups.setdefault((round(key[0], 4), round(key[1], 4)), []).append(index)
        lean_frames = int(frames - params.get("settle_frames", 90) * 0.6)
        kept = 0
        for key in sorted(groups):
            part = batch[groups[key]]
            settled = world.run_batch(near, part, frames, key, lean_frames)
            ok = (
                (settled[:, 2] > region.floor - max_size)
                & np.isfinite(settled).all(axis=1)
                & (settled[:, 2] < base + layers * spacing + max_size)
            )
            placed = np.concatenate([placed, settled[ok]])
            near = np.concatenate([near, settled[ok]]) if len(near) else settled[ok]
            kept += int(ok.sum())
        log(
            f"  batch {batch_index}: {len(batch)} stones ({layers} layers, {len(columns)} columns), "
            f"need {need_share:.2f}, lost {len(batch) - kept}, {time.time() - t0:.1f} s, "
            f"total {len(placed)}"
        )
    return placed


def hull_points(stones: np.ndarray, variants: Variants) -> np.ndarray:
    """World-space LOD0 vertices (the drawn shape) of all `stones`, (n, 3)."""
    if len(stones) == 0:
        return np.zeros((0, 3))
    rot = quat_to_matrix(stones[:, 3:7])
    parts = []
    for vi, variant in enumerate(variants.variants):
        sel = np.nonzero(stones[:, 8].astype(int) == vi)[0]
        if len(sel) == 0:
            continue
        pv = np.asarray(variant["lods"][0]["verts"], dtype=float)
        world = np.einsum("nij,kj->nki", rot[sel], pv) * stones[sel, 7][:, None, None]
        world += stones[sel, 0:3][:, None, :]
        parts.append(world.reshape(-1, 3))
    return np.concatenate(parts) if parts else np.zeros((0, 3))


def drawn_tops(stones: np.ndarray, variants: Variants) -> np.ndarray:
    """The highest drawn (LOD0) point of every stone, (n,)."""
    tops = np.zeros(len(stones))
    if len(stones) == 0:
        return tops
    rot = quat_to_matrix(stones[:, 3:7])
    for vi, variant in enumerate(variants.variants):
        sel = np.nonzero(stones[:, 8].astype(int) == vi)[0]
        if len(sel) == 0:
            continue
        pv = np.asarray(variant["lods"][0]["verts"], dtype=float)
        world_z = np.einsum("nj,kj->nk", rot[sel, 2, :], pv) * stones[sel, 7][:, None]
        tops[sel] = stones[sel, 2] + world_z.max(axis=1)
    return tops


def glass_edge_profiles(
    stones: np.ndarray, variants: Variants, lx: float, ly: float, cell: float, strip: float
) -> list[np.ndarray]:
    """The highest drawn point per `cell` along each pane, within `strip` of the pane (Blender
    frame; panes at x = -lx/2, x = lx/2, y = -ly/2, y = ly/2, in that order). A cell without a
    stone reads 0 (the floor)."""
    max_size = float(stones[:, 7].max()) if len(stones) else 0.0
    reach = strip + max_size
    near = (np.abs(stones[:, 0]) > lx / 2 - reach) | (np.abs(stones[:, 1]) > ly / 2 - reach)
    points = hull_points(stones[near], variants)
    profiles = []
    for pane in range(4):
        along = 1 if pane < 2 else 0
        length = ly if pane < 2 else lx
        if pane == 0:
            sel = points[:, 0] < -lx / 2 + strip
        elif pane == 1:
            sel = points[:, 0] > lx / 2 - strip
        elif pane == 2:
            sel = points[:, 1] < -ly / 2 + strip
        else:
            sel = points[:, 1] > ly / 2 - strip
        cells = max(1, int(round(length / cell)))
        profile = np.zeros(cells)
        p = points[sel]
        index = np.clip(((p[:, along] + length / 2) / (length / cells)).astype(int), 0, cells - 1)
        np.maximum.at(profile, index, p[:, 2])
        profiles.append(profile)
    return profiles


def fill_glass_notches(
    world: SimWorld,
    stones: np.ndarray,
    lx: float,
    ly: float,
    target: float,
    size_classes: list,
    rng: random.Random,
    fill: dict,
    log=print,
    crop_top: float | None = None,
) -> np.ndarray:
    """Whole-tank pours: drops extra stones into the notches of the top edge at the glass, where
    the top row along a pane leaves a gap that reaches far below the surface (the pour aims at
    grid columns that are wider than that strip). A notch is a run of `cell_m` cells along a
    pane whose highest point within `strip_m` of the glass lies more than `low_m` below
    `target`. One stone per notch falls against the glass with the gravity tilted towards the
    pane (`lean`) onto the settled pile, which stays frozen; at most `rounds` passes, from round
    `small_after` on with stones of the smallest size class, from round `deep_after` on started
    inside the notch. A stone whose top comes to rest at
    or above `crop_top` (the crop height of the visibility pass) is not kept. Returns the new
    settled stones."""
    cell = fill.get("cell_m", 0.005)
    strip = fill.get("strip_m", 0.005)
    low = fill["low_m"]
    lean_strength = fill.get("lean", 0.25)
    frames = int(fill.get("frames", 240))
    small_after = int(fill.get("small_after", 2))
    deep_after = int(fill.get("deep_after", 4))
    n_variants = len(world.variants.variants)
    added = np.zeros((0, STONE_COLS))
    if crop_top is not None:
        # the stones the visibility pass will crop do not count for the edge
        stones = stones[drawn_tops(stones, world.variants) < crop_top]
    for round_index in range(fill.get("rounds", 6)):
        drops = 0
        for pane in range(4):
            everything = np.concatenate([stones, added]) if len(added) else stones
            profile = glass_edge_profiles(everything, world.variants, lx, ly, cell, strip)[pane]
            length = ly if pane < 2 else lx
            step = length / len(profile)
            notch = profile < target - low
            batch = []
            i = 0
            while i < len(profile):
                if not notch[i]:
                    i += 1
                    continue
                j = i
                while j + 1 < len(profile) and notch[j + 1]:
                    j += 1
                # a notch that is still open after `small_after` rounds is narrow: the
                # smallest size class fits it best
                size = sample_size(
                    rng, size_classes[:1] if round_index >= small_after else size_classes
                )
                u = -length / 2 + (0.5 * (i + j) + 0.5) * step
                inward = 0.5 * size + 0.001
                drop_z = float(profile[max(0, i - 4) : j + 5].max()) + size
                if round_index >= deep_after:
                    # still open: the stone starts inside the notch, just above its floor, so
                    # no stone that overhangs the notch can catch it on the way down
                    drop_z = float(profile[i : j + 1].max()) + 0.6 * size
                if pane == 0:
                    x, y = -lx / 2 + inward, u
                elif pane == 1:
                    x, y = lx / 2 - inward, u
                elif pane == 2:
                    x, y = u, -ly / 2 + inward
                else:
                    x, y = u, ly / 2 - inward
                q = random_quat(rng)
                batch.append(
                    [x, y, drop_z, q[0], q[1], q[2], q[3], size, rng.randrange(n_variants)]
                )
                # the next notch starts at least one stone further along the pane
                i = max(j + 1, i + int(math.ceil(size / step)))
            if not batch:
                continue
            tilt = (
                -lean_strength if pane == 0 else (lean_strength if pane == 1 else 0.0),
                -lean_strength if pane == 2 else (lean_strength if pane == 3 else 0.0),
            )
            part = np.array(batch)
            low_z = float(part[:, 2].min()) - 3.0 * float(part[:, 7].max())
            near_glass = (np.abs(everything[:, 0]) > lx / 2 - 0.06) | (
                np.abs(everything[:, 1]) > ly / 2 - 0.06
            )
            near = everything[near_glass & (everything[:, 2] > low_z)]
            settled = world.run_batch(near, part, frames, tilt, int(frames * 0.5))
            ok = np.isfinite(settled).all(axis=1) & (settled[:, 2] > 0.0)
            if crop_top is not None and len(settled):
                # a stone that came to rest so high that the visibility pass would crop it
                # does not fill the notch: drop it here, the next round tries a smaller one
                ok &= drawn_tops(settled, world.variants) < crop_top
            added = np.concatenate([added, settled[ok]])
            drops += len(batch)
        log(f"  glass notches round {round_index}: {drops} stones dropped, {len(added)} kept")
        if drops == 0:
            break
    return added
