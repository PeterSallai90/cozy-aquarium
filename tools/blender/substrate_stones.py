"""Procedural stone meshes with authored LODs for the substrate bed (#28, ADR 0011).

    blender --background --python tools/blender/substrate_stones.py -- \
        [--class angular|round|pebble|all] [--seed 28] [--out game/assets/substrate]

Writes ``grains_<class>.glb`` (gravel: angular, coloured gravel: round, pebbles: pebble). Sand has
no mesh: its grains are ray-cast ellipsoids, the hull built here is only its collision shape.

Every stone is a convex body: an ellipsoid (optionally a superellipsoid) cut by a few random
planes. A LOD is the convex hull of N points sampled on that body in evenly spread (Fibonacci)
directions, so every LOD describes the same stone and no LOD is a decimation of another.

Conventions (docs/art-style.md): 1 unit = 1 m; a stone is authored at unit size, meaning the
longest local extent of LOD0 is 1.0 and the origin is the centre of its bounds, so the
per-instance uniform scale is the drawn size in metres. Local frame: +X is the longest axis, +Z
the shortest (Blender frame, Z up when lying flat). Nodes are named ``<class>_v<n>_lod<k>``.
Two UV layers, ``UV0`` (a spherical projection) and ``UV1`` (collapsed onto one cell of the shared
palette atlas); the stones are coloured by shader parameters and per-instance data, no texture
samples either layer. The lightmap pack operator is never used. Hard edges (split normals) only
on the angular class; the round classes carry the analytic normals of the smooth body.

The stone parameters (``class_parameters``) are pure Python and deterministic per seed; the
meshes need numpy and bmesh (Blender). The same seed gives the bake (bake_substrate.py) the same
bodies as collision hulls.
"""

from __future__ import annotations

import math
import random
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

DEFAULT_SEED = 28
# glb class name -> file name
GLB_CLASSES = ("angular", "round", "pebble")

# Shape classes. `lod_points` are the hull point counts (triangles = 2 N - 4 at most).
CLASSES: dict[str, dict] = {
    # natural gravel: angular to sub-angular chips, aspect 1 to 1.6
    "angular": {
        "variants": 4,
        "axes_b": (0.62, 0.90),
        "axes_c": (0.48, 0.74),
        "exponent": 2.0,
        "planes": (8, 11),
        "plane_depth": (0.50, 0.86),
        "lod_points": (32, 12, 7, 5),
        "phys_points": 24,
        "phys_scale": 1.0,
        "smooth_angle_deg": 38.0,
        "radial_normals_from_lod": 1,
    },
    # coloured gravel: rounded, smooth (coated)
    "round": {
        "variants": 3,
        "axes_b": (0.74, 0.94),
        "axes_c": (0.60, 0.84),
        "exponent": 2.3,
        "planes": (1, 3),
        "plane_depth": (0.9, 0.97),
        "egg": 0.08,
        "lumps": (3, 0.05),
        "lod_points": (50, 14, 7, 5),
        "phys_points": 26,
        "phys_scale": 1.02,
        "smooth_angle_deg": 180.0,
        "radial_normals_from_lod": 1,
    },
    # river pebbles: smooth flattened ovals, long:short 1.2 to 1.8, thickness 0.5 to 0.7 of width
    "pebble": {
        "variants": 5,
        "axes_b": (0.58, 0.83),
        "axes_c_of_b": (0.50, 0.70),
        "exponent": 2.4,
        "planes": (0, 0),
        "plane_depth": (1.0, 1.0),
        "egg": 0.12,
        "lumps": (3, 0.06),
        "lod_points": (322, 102, 42),
        "phys_points": 48,
        "phys_scale": 1.03,
        "smooth_angle_deg": 180.0,
        "radial_normals_from_lod": 99,
    },
    # sand: sub-rounded blobs, aspect 1 to 1.4. Drawn as ray-cast ellipsoids; the hull is only the
    # collision shape (circumscribed, so drawn grains never overlap).
    "sand": {
        "variants": 6,
        "axes_b": (0.72, 1.0),
        "axes_c": (0.62, 0.9),
        "exponent": 2.0,
        "planes": (0, 0),
        "plane_depth": (1.0, 1.0),
        "lod_points": (32,),
        "phys_points": 32,
        "phys_scale": 1.05,
        "exact_ellipsoid": True,
        "smooth_angle_deg": 180.0,
        "radial_normals_from_lod": 99,
    },
}


# --- pure Python: the random parameters of every variant ---


def _unit(rng: random.Random, count: int) -> list[float]:
    values = [rng.gauss(0, 1) for _ in range(count)]
    length = math.sqrt(sum(v * v for v in values))
    return [v / length for v in values]


def class_parameters(class_name: str, seed: int = DEFAULT_SEED) -> list[dict]:
    """The random shape parameters of every variant of a class, deterministic per seed.

    Per variant: ``axes`` (semi-axes before the unit scaling, the first is 1.0), ``exponent``,
    ``planes`` (unit normal, distance), ``egg``, ``lumps`` (unit normal, gain) and ``rotation``
    (unit quaternion w, x, y, z that turns the Fibonacci sampling directions).
    """
    if class_name not in CLASSES:
        raise ValueError(f"unknown stone class {class_name!r}; known: {', '.join(CLASSES)}")
    cls = CLASSES[class_name]
    rng = random.Random(f"stones|{class_name}|{seed}")
    result: list[dict] = []
    for _ in range(cls["variants"]):
        b = rng.uniform(*cls["axes_b"])
        if "axes_c_of_b" in cls:
            c = b * rng.uniform(*cls["axes_c_of_b"])
        else:
            c = min(b, rng.uniform(*cls["axes_c"]))
        axes = [1.0, b, c]
        planes = []
        for _plane in range(rng.randint(*cls["planes"])):
            normal = _unit(rng, 3)
            support = math.sqrt(sum((a * n) ** 2 for a, n in zip(axes, normal, strict=True)))
            planes.append((normal, support * rng.uniform(*cls["plane_depth"])))
        egg_range = cls.get("egg", 0.0)
        egg = rng.uniform(-egg_range, egg_range)
        lumps = []
        lump_count, lump_gain = cls.get("lumps", (0, 0.0))
        for _lump in range(lump_count):
            normal = _unit(rng, 3)
            lumps.append((normal, rng.uniform(-lump_gain, lump_gain)))
        rotation = _unit(rng, 4)
        result.append(
            {
                "axes": axes,
                "exponent": cls["exponent"],
                "planes": planes,
                "egg": egg,
                "lumps": lumps,
                "rotation": rotation,
            }
        )
    return result


def lod_triangle_caps(class_name: str) -> list[int]:
    """The largest triangle count each LOD of a class can have (2 N - 4 for N hull points)."""
    return [2 * count - 4 for count in CLASSES[class_name]["lod_points"]]


# --- numpy and bmesh (inside Blender) ---


def fibonacci_dirs(count: int, rot):  # noqa: ANN001, ANN201 (numpy)
    """`count` evenly spread unit vectors, rotated by the 3x3 matrix `rot`."""
    import numpy as np  # noqa: PLC0415

    i = np.arange(count) + 0.5
    phi = np.arccos(1.0 - 2.0 * i / count)
    theta = math.pi * (1.0 + 5.0**0.5) * i
    dirs = np.stack([np.cos(theta) * np.sin(phi), np.sin(theta) * np.sin(phi), np.cos(phi)], axis=1)
    return dirs @ rot.T


def quaternion_matrix(q: list[float]):  # noqa: ANN201 (numpy)
    import numpy as np  # noqa: PLC0415

    w, x, y, z = q
    return np.array(
        [
            [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
        ]
    )


class Body:
    """A convex stone: superellipsoid cut by half-spaces. `radius(dirs)` is its radial function."""

    def __init__(self, parameters: dict) -> None:
        import numpy as np  # noqa: PLC0415

        self.np = np
        self.axes = np.array(parameters["axes"])
        self.exponent = parameters["exponent"]
        self.planes = [(np.array(n), d) for n, d in parameters["planes"]]
        self.egg = parameters["egg"]
        self.lumps = [(np.array(n), gain) for n, gain in parameters["lumps"]]

    def radius(self, dirs):  # noqa: ANN001, ANN201
        np = self.np
        e = self.exponent
        t = np.sum(np.abs(dirs / self.axes) ** e, axis=1) ** (-1.0 / e)
        t = t * (1.0 + self.egg * dirs[:, 0])
        for n, gain in self.lumps:
            t = t * (1.0 + gain * (dirs @ n) ** 2)
        for n, d in self.planes:
            dot = dirs @ n
            with np.errstate(divide="ignore"):
                tk = np.where(dot > 1e-6, d / np.maximum(dot, 1e-6), np.inf)
            t = np.minimum(t, tk)
        return t

    def normals(self, points):  # noqa: ANN001, ANN201
        """Analytic surface normals of the smooth body at `points` (finite differences of the
        radial function). Used for the smooth classes, so even a coarse LOD shades smoothly."""
        np = self.np
        length = np.linalg.norm(points, axis=1)
        d = points / np.maximum(length[:, None], 1e-12)
        helper = np.where(np.abs(d[:, 0:1]) > 0.8, [[0.0, 1.0, 0.0]], [[1.0, 0.0, 0.0]])
        t1 = np.cross(d, helper)
        t1 /= np.linalg.norm(t1, axis=1)[:, None]
        t2 = np.cross(d, t1)
        eps = 2e-3
        r0 = self.radius(d)
        d1 = d + eps * t1
        d1 /= np.linalg.norm(d1, axis=1)[:, None]
        d2 = d + eps * t2
        d2 /= np.linalg.norm(d2, axis=1)[:, None]
        g1 = (self.radius(d1) - r0) / eps
        g2 = (self.radius(d2) - r0) / eps
        n = d * r0[:, None] - g1[:, None] * t1 - g2[:, None] * t2
        return n / np.maximum(np.linalg.norm(n, axis=1)[:, None], 1e-12)

    def points(self, count: int, rot):  # noqa: ANN001, ANN201
        dirs = fibonacci_dirs(count, rot)
        return dirs * self.radius(dirs)[:, None]


def hull(points):  # noqa: ANN001, ANN201
    """Convex hull as (vertices, triangles) with outward winding (counter-clockwise from outside)."""
    import bmesh  # noqa: PLC0415
    import numpy as np  # noqa: PLC0415

    bm = bmesh.new()
    verts = [bm.verts.new(p) for p in points.tolist()]
    result = bmesh.ops.convex_hull(bm, input=verts)
    interior = [e for e in result["geom_interior"] if isinstance(e, bmesh.types.BMVert)]
    if interior:
        bmesh.ops.delete(bm, geom=interior, context="VERTS")
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.verts.ensure_lookup_table()
    bm.verts.index_update()
    out_verts = np.array([v.co[:] for v in bm.verts], dtype=np.float64)
    out_tris = np.array([[v.index for v in f.verts] for f in bm.faces], dtype=np.int32)
    bm.free()
    # make sure the winding points outward (centroid test)
    centre = out_verts.mean(axis=0)
    a = out_verts[out_tris[:, 0]]
    n = np.cross(out_verts[out_tris[:, 1]] - a, out_verts[out_tris[:, 2]] - a)
    flip = np.einsum("ij,ij->i", n, a - centre) < 0
    out_tris[flip] = out_tris[flip][:, ::-1]
    return out_verts, out_tris


def shade(verts, tris, smooth_angle_deg: float, radial: bool):  # noqa: ANN001, ANN201
    """Returns the normal of every triangle corner, shape (triangles, 3, 3).

    radial: normals point from the centre outwards (blended with the smooth normal), so even a
    6 to 8 triangle stone shades round. Otherwise smooth by angle: a corner takes the area-weighted
    mean of the adjacent face normals that lie within `smooth_angle_deg` of its own face (split
    normals on feature edges only; never faceted flat shading unless the edge is a real ridge).
    """
    import numpy as np  # noqa: PLC0415

    a = verts[tris[:, 0]]
    fn = np.cross(verts[tris[:, 1]] - a, verts[tris[:, 2]] - a)
    area = np.linalg.norm(fn, axis=1)
    fnu = fn / np.maximum(area[:, None], 1e-12)
    vert_faces: list[list[int]] = [[] for _ in range(len(verts))]
    for fi, tri in enumerate(tris):
        for vi in tri:
            vert_faces[vi].append(fi)
    if radial or smooth_angle_deg >= 179.0:
        normals = np.zeros_like(verts)
        for vi, faces in enumerate(vert_faces):
            normals[vi] = fn[faces].sum(axis=0)
        normals /= np.maximum(np.linalg.norm(normals, axis=1)[:, None], 1e-12)
        if radial:
            rad = verts / np.maximum(np.linalg.norm(verts, axis=1)[:, None], 1e-12)
            normals = normals * 0.5 + rad * 0.5
            normals /= np.maximum(np.linalg.norm(normals, axis=1)[:, None], 1e-12)
        return normals[tris]
    cos_limit = math.cos(math.radians(smooth_angle_deg))
    corners = np.zeros((len(tris), 3, 3))
    for fi, tri in enumerate(tris):
        for k, vi in enumerate(tri):
            group = [f for f in vert_faces[vi] if float(fnu[f] @ fnu[fi]) >= cos_limit]
            n = fn[group].sum(axis=0)
            corners[fi, k] = n / max(float(np.linalg.norm(n)), 1e-12)
    return corners


def hull_volume(verts, tris) -> float:  # noqa: ANN001
    import numpy as np  # noqa: PLC0415

    a = verts[tris[:, 0]]
    b = verts[tris[:, 1]]
    c = verts[tris[:, 2]]
    return float(abs(np.einsum("ij,ij->i", a, np.cross(b, c)).sum()) / 6.0)


def build_class(class_name: str, seed: int = DEFAULT_SEED) -> list[dict]:
    """All variants of a class: render LODs plus the collision hull, at unit size (Blender frame).

    Per variant: ``lods`` (each ``verts``, ``tris``, ``corner_normals``, ``triangles``),
    ``phys_verts``, ``phys_tris``, ``half_extents`` (of LOD0), ``axes`` (the ellipsoid semi-axes at
    unit size) and ``volume`` (of the collision hull).
    """
    import numpy as np  # noqa: PLC0415

    cls = CLASSES[class_name]
    variants: list[dict] = []
    for parameters in class_parameters(class_name, seed):
        body = Body(parameters)
        rot = quaternion_matrix(parameters["rotation"])
        lods = []
        scale = None
        centre = np.zeros(3)
        for li, count in enumerate(cls["lod_points"]):
            hv, ht = hull(body.points(count, rot))
            if scale is None and cls.get("exact_ellipsoid", False):
                # the drawn grain is the exact ellipsoid: longest axis 2 x 0.5 = 1.0
                scale = 0.5
            elif scale is None:
                # unit size: longest local extent of the most detailed LOD is 1.0
                extent = hv.max(axis=0) - hv.min(axis=0)
                scale = 1.0 / float(extent.max())
                centre = (hv.max(axis=0) + hv.min(axis=0)) / 2.0
            raw = hv
            hv = (hv - centre) * scale
            radial = li >= cls["radial_normals_from_lod"]
            corner_normals = shade(hv, ht, cls["smooth_angle_deg"], radial)
            if cls["smooth_angle_deg"] >= 179.0:
                # smooth classes: exact normals of the body, blended with the mesh normals so
                # the flats of the gentle cut planes stay readable
                exact = body.normals(raw)[ht]
                corner_normals = exact * 0.7 + corner_normals * 0.3
                corner_normals /= np.linalg.norm(corner_normals, axis=2)[:, :, None]
            lods.append(
                {"verts": hv, "tris": ht, "corner_normals": corner_normals, "triangles": len(ht)}
            )
        pv, pt = hull(body.points(cls["phys_points"], rot))
        pv = (pv - centre) * scale * cls["phys_scale"]
        half = (lods[0]["verts"].max(axis=0) - lods[0]["verts"].min(axis=0)) / 2.0
        variants.append(
            {
                "lods": lods,
                "phys_verts": pv,
                "phys_tris": pt,
                "half_extents": half,
                "axes": body.axes * scale,
                "volume": hull_volume(pv, pt),
            }
        )
    return variants


def to_godot(points):  # noqa: ANN001, ANN201
    """Blender (x, y, z up) to Godot/glTF (x, y up, z): (x, z, -y)."""
    import numpy as np  # noqa: PLC0415

    return np.stack([points[:, 0], points[:, 2], -points[:, 1]], axis=1)


def godot_vector(v) -> list[float]:  # noqa: ANN001
    """A per-axis size (half extents, semi-axes) in the Godot frame: (x, z, y) of Blender."""
    return [float(v[0]), float(v[2]), float(v[1])]


# --- glb export ---


def _build_object(name: str, lod: dict, material):  # noqa: ANN001, ANN202 (bpy types)
    import bpy  # noqa: PLC0415

    import blender_common  # noqa: PLC0415
    import room_palette  # noqa: PLC0415

    verts = lod["verts"]
    tris = lod["tris"]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts.tolist(), [], tris.tolist())
    mesh.update()
    uv0 = mesh.uv_layers.new(name=blender_common.UV_LAYERS[0])
    uv1 = mesh.uv_layers.new(name=blender_common.UV_LAYERS[1])
    atlas = room_palette.cell_uv((3, 5))
    loop_normals = []
    for polygon in mesh.polygons:
        polygon.use_smooth = True
        for k, loop_index in enumerate(polygon.loop_indices):
            vertex = verts[mesh.loops[loop_index].vertex_index]
            length = max(float((vertex**2).sum()) ** 0.5, 1e-9)
            u = 0.5 + math.atan2(vertex[1], vertex[0]) / (2.0 * math.pi)
            v = 0.5 + math.asin(max(-1.0, min(1.0, vertex[2] / length))) / math.pi
            uv0.data[loop_index].uv = (u, v)
            uv1.data[loop_index].uv = atlas
            loop_normals.append(tuple(float(c) for c in lod["corner_normals"][polygon.index][k]))
    mesh.normals_split_custom_set(loop_normals)
    names = [layer.name for layer in mesh.uv_layers]
    if names != list(blender_common.UV_LAYERS):
        raise blender_common.GeneratorError(f"internal: UV layers of {name} are {names}")
    mesh.uv_layers[blender_common.UV_LAYERS[0]].active = True
    mesh.uv_layers[blender_common.UV_LAYERS[0]].active_render = True
    mesh.materials.append(material)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def export_class(class_name: str, seed: int, folder: Path) -> list[list[int]]:
    """Writes grains_<class>.glb into `folder`; returns the triangle counts per variant and LOD."""
    import blender_common  # noqa: PLC0415

    if class_name not in GLB_CLASSES:
        raise blender_common.GeneratorError(f"class {class_name!r} has no mesh file")
    variants = build_class(class_name, seed)
    counts = [[int(lod["triangles"]) for lod in variant["lods"]] for variant in variants]

    def write(path: Path) -> None:
        blender_common.reset_scene()
        material = blender_common.new_material("substrate_stone")
        objects = []
        for vi, variant in enumerate(variants):
            for li, lod in enumerate(variant["lods"]):
                objects.append(_build_object(f"{class_name}_v{vi}_lod{li}", lod, material))
        blender_common.export_glb(objects, path)

    blender_common.write_group(
        folder, [(f"grains_{class_name}.glb", write, blender_common.GLB_MAGIC)]
    )
    return counts


def run(argv: list[str]) -> None:
    import argparse  # noqa: PLC0415

    import blender_common  # noqa: PLC0415

    parser = argparse.ArgumentParser(prog="substrate_stones.py")
    parser.add_argument("--class", dest="stone_class", default="all")
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED)
    parser.add_argument("--out", type=Path, default=HERE.parents[1] / "game/assets/substrate")
    args = parser.parse_args(blender_common.script_args(argv))
    wanted = GLB_CLASSES if args.stone_class == "all" else (args.stone_class,)
    for class_name in wanted:
        counts = export_class(class_name, args.seed, args.out)
        print(f"grains_{class_name}.glb: {len(counts)} variants, LOD triangles {counts}", flush=True)


if __name__ == "__main__":
    import blender_common

    sys.exit(blender_common.main("substrate_stones.py", run))
