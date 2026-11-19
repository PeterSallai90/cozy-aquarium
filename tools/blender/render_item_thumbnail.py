"""Render one item model as a 256 x 256 transparent PNG thumbnail, headless in Blender 5.2 (#153).

Usage (the arguments after ``--`` belong to this script):

    blender --background --python tools/blender/render_item_thumbnail.py -- \
        --model <model .glb> --id <item id> [--out game/assets/items/thumbnails]

Writes exactly one file, ``<out>/<id>.png``: 256 x 256 px, 8 bit RGBA with straight alpha, a
transparent background. The script reads no ``.tres``; the caller passes the model and the catalog
id. The output folder must exist (it is not created). An existing PNG is replaced all or nothing
through ``blender_common.write_group``; on any failure it stays unchanged. Exit code 0 on success,
1 on any error, with one message that starts with ``render_item_thumbnail: error:``. On success one
line reports the measurement of the written file (size, corner alphas, alpha box, long side and
centre), computed by ``measure_png``.

The id rule (shared with ItemCatalog.is_valid_id, #152): the whole id matches
``[a-z][a-z0-9_]{0,47}`` and is not a Windows device name (con, prn, aux, nul, com1 to com9, lpt1
to lpt9).

Framing (the values the checks use): orthographic camera, ``AZIMUTH_DEG`` from the model front and
``ELEVATION_DEG`` above it, looking at the centre of the item. The model front is glTF +Z, which
the importer turns into Blender -Y with Z up: azimuth 0 and elevation 0 look straight at the model
front, a positive azimuth turns the camera toward Blender +X, and a positive elevation looks down.
Only visible meshes with at least one triangle are framed (empties, curves, cameras, lights and
hidden objects are ignored). The box of the projected vertices of all framed meshes (the box of
the silhouette, not the 3D box) is centred in the frame, and the box of the rendered pixels with
alpha above 0 gets a longer side of ``SIZE_PX - 2 * MARGIN_PX`` px (224 of 256, within 2 px). The
pixel filter spills about ``FILTER_SPILL_PX`` of faint alpha past the geometry on every side, so the
camera fits the geometry with a margin of ``MARGIN_PX + FILTER_SPILL_PX`` (222 px of geometry). A
thin or flat item fills only its longer side; the thumbnail shows the shape, not the real size.
Defaults (AZIMUTH_DEG 35, ELEVATION_DEG 25, MARGIN_PX 16) are the BA starting values (#153 Q2).

Render settings (the values the checks use, all fixed so two runs on one machine with one Blender
version give the same file bytes, AC 2):

- Cycles on the CPU (never the GPU), ``SAMPLES`` fixed samples, adaptive sampling off, seed
  ``SEED``, animated seed off, denoiser off, Blackman-Harris pixel filter ``FILTER_WIDTH_PX`` px;
- film transparent; view transform Standard, look None, exposure 0, gamma 1, display sRGB, dither
  0 (dither noise would change the palette colours and the edge alpha);
- PNG, RGBA, 8 bit, compression ``PNG_COMPRESSION``; Blender writes straight (unassociated) alpha;
- stamp and every stamp metadata flag off (render time and date in the PNG text chunks would change
  the hash on every run); Cycles still writes its render statistics as text chunks, so the writer
  keeps only the critical PNG chunks and sRGB, gAMA and cHRM (``strip_png_metadata``); compositor
  and sequencer off;
- light: one ``SUN`` (strength ``SUN_STRENGTH``, angular diameter ``SUN_ANGLE_DEG``, neutral
  white) placed ``LIGHT_AZIMUTH_DEG`` to the left of and ``LIGHT_ELEVATION_DEG`` above the view
  direction, plus a flat neutral world (``WORLD_GREY`` at ``WORLD_STRENGTH``) as fill. A sun's
  light does not fall off with distance, so a 2 cm and a 45 cm item get the same light. The film is
  transparent, so the world is never seen. No ground, no shadow catcher; the item shades itself.

Materials: the imported glTF materials are kept where their Principled BSDF base colour is fed by
an image (the palette atlas through the UV set the glb names). Their image nodes sample with
``Closest`` (exact atlas cell colours), every link into Alpha is removed and Alpha is 1 (opaque),
backface culling is off (double-sided), and every vertex colour link is replaced by white (the
vertex colour alpha is the Godot translucency mask, not a Blender input). A slot without a material
or without a readable image gets one neutral grey material (``GREY``), which is not a failure.

Cameras, lights and empties in the file are removed (child meshes keep their world transform), and
the script's own camera, light and world are used. Previews of throwaway models are not committed.

The module imports without Blender: ``bpy`` and ``mathutils`` are imported inside the render part
only, so ``test_render_item_thumbnail.py`` runs with the stdlib.
"""

from __future__ import annotations

import argparse
import math
import re
import struct
import sys
import tempfile
import zlib
from collections.abc import Iterable
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import blender_common  # noqa: E402
from blender_common import GeneratorError  # noqa: E402

PROG = "render_item_thumbnail"
REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = REPO_ROOT / "game" / "assets" / "items" / "thumbnails"

# --- id rule (#152, #153) ---
ID_PATTERN = re.compile(r"[a-z][a-z0-9_]{0,47}")
DEVICE_NAMES = frozenset(
    {"con", "prn", "aux", "nul"}
    | {f"com{i}" for i in range(1, 10)}
    | {f"lpt{i}" for i in range(1, 10)}
)

# --- framing (the values the checks use) ---
SIZE_PX = 256
MARGIN_PX = 16
AZIMUTH_DEG = 35.0
ELEVATION_DEG = 25.0
MIN_SILHOUETTE_M = 1e-6  # a silhouette at or below this long side has zero size
CLIP_PAD_SHARE = 0.25  # depth padding around the item, a share of the silhouette long side
CLIP_PAD_MIN_M = 0.001
# The pixel filter gives the silhouette edge about 1 px of faint alpha on every side, so the camera
# fits the geometry to SIZE_PX - 2 * (MARGIN_PX + FILTER_SPILL_PX) px and the measured box of the
# pixels with alpha above 0 comes out at SIZE_PX - 2 * MARGIN_PX px (224).
FILTER_SPILL_PX = 1.0

# --- render settings (the values the checks use) ---
SAMPLES = 64
SEED = 0
FILTER_WIDTH_PX = 1.5
PNG_COMPRESSION = 15
SUN_STRENGTH = 2.6
SUN_ANGLE_DEG = 35.0
SUN_COLOUR = (1.0, 1.0, 1.0)
LIGHT_AZIMUTH_DEG = 60.0  # to the left of the view direction
LIGHT_ELEVATION_DEG = 35.0  # above the view direction
WORLD_GREY = 0.5
WORLD_STRENGTH = 0.6
GREY = (0.5, 0.5, 0.5)  # neutral grey for a slot without a material or a readable image
GREY_ROUGHNESS = 0.75

Vec = tuple[float, float, float]


# --- id, arguments, output path ---


def validate_id(item_id: str) -> str:
    """Returns ``item_id`` when it follows the id rule, else raises ``GeneratorError``."""
    if not isinstance(item_id, str) or ID_PATTERN.fullmatch(item_id) is None:
        raise GeneratorError(
            f"invalid item id {item_id!r}: it must be 1 to 48 characters of a-z, 0-9 and _, "
            "starting with a letter a-z"
        )
    if item_id in DEVICE_NAMES:
        raise GeneratorError(f"invalid item id {item_id!r}: it is a Windows device name")
    return item_id


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(prog=PROG)
    parser.add_argument("--model", type=Path, required=True, help="the item model (.glb)")
    parser.add_argument("--id", required=True, help="the catalog id of the item")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help="existing output folder")
    return parser.parse_args(blender_common.script_args(argv))


def output_path(out_dir: Path, item_id: str) -> Path:
    return out_dir / f"{validate_id(item_id)}.png"


# --- framing maths (stdlib) ---


def _dot(a: Vec, b: Vec) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _cross(a: Vec, b: Vec) -> Vec:
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _scaled(a: Vec, k: float) -> Vec:
    return (a[0] * k, a[1] * k, a[2] * k)


def _sum(*vectors: Vec) -> Vec:
    return (
        sum(v[0] for v in vectors),
        sum(v[1] for v in vectors),
        sum(v[2] for v in vectors),
    )


def _normalised(a: Vec) -> Vec:
    length = math.sqrt(_dot(a, a))
    return _scaled(a, 1.0 / length)


def view_basis(azimuth_deg: float, elevation_deg: float) -> tuple[Vec, Vec, Vec]:
    """(right, up, toward_camera) unit vectors in the Blender frame (model front -Y, Z up)."""
    if not -90.0 < elevation_deg < 90.0:
        raise GeneratorError(f"elevation must be between -90 and 90 degrees, got {elevation_deg}")
    a = math.radians(azimuth_deg)
    e = math.radians(elevation_deg)
    toward = (math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e))
    forward = _scaled(toward, -1.0)
    right = _normalised(_cross(forward, (0.0, 0.0, 1.0)))
    up = _cross(right, forward)
    return right, up, toward


@dataclass(frozen=True)
class Framing:
    """An orthographic camera that fits a silhouette; ``basis`` is (right, up, toward_camera)."""

    target: Vec
    camera_location: Vec
    ortho_scale: float
    clip_start: float
    clip_end: float
    basis: tuple[Vec, Vec, Vec]


def fit_frame(
    points: Iterable[Vec],
    azimuth_deg: float,
    elevation_deg: float,
    size_px: int = SIZE_PX,
    margin_px: float = MARGIN_PX,
) -> Framing:
    """Fits the projected box of ``points`` to ``size_px - 2 * margin_px`` px, centred."""
    right, up, toward = view_basis(azimuth_deg, elevation_deg)
    us: list[float] = []
    vs: list[float] = []
    ws: list[float] = []
    for point in points:
        if not all(math.isfinite(c) for c in point):
            raise GeneratorError(f"the model has a vertex with a NaN or infinite coordinate: {point}")
        us.append(_dot(point, right))
        vs.append(_dot(point, up))
        ws.append(_dot(point, toward))
    if not us:
        raise GeneratorError("no vertex to frame")
    du = max(us) - min(us)
    dv = max(vs) - min(vs)
    long = max(du, dv)
    if not long > MIN_SILHOUETTE_M:
        raise GeneratorError(f"the silhouette has zero size ({long:.3g} m) from the fixed angle")
    inner = size_px - 2.0 * margin_px
    if not inner > 0.0:
        raise GeneratorError(f"margin {margin_px} px leaves no room in {size_px} px")
    cu = (max(us) + min(us)) / 2.0
    cv = (max(vs) + min(vs)) / 2.0
    cw = (max(ws) + min(ws)) / 2.0
    depth_half = (max(ws) - min(ws)) / 2.0
    pad = max(CLIP_PAD_SHARE * long, CLIP_PAD_MIN_M)
    target = _sum(_scaled(right, cu), _scaled(up, cv), _scaled(toward, cw))
    camera = _sum(target, _scaled(toward, depth_half + pad))
    return Framing(
        target=target,
        camera_location=camera,
        ortho_scale=long * size_px / inner,
        clip_start=pad / 2.0,
        clip_end=2.0 * depth_half + 1.5 * pad,
        basis=(right, up, toward),
    )


def to_pixels(framing: Framing, point: Vec, size_px: int = SIZE_PX) -> tuple[float, float]:
    """Pixel coordinates of ``point`` in the frame: x to the right, y down, (0, 0) top left."""
    right, up, _ = framing.basis
    offset = (
        point[0] - framing.target[0],
        point[1] - framing.target[1],
        point[2] - framing.target[2],
    )
    per_metre = size_px / framing.ortho_scale
    x = size_px / 2.0 + _dot(offset, right) * per_metre
    y = size_px / 2.0 - _dot(offset, up) * per_metre
    return x, y


# --- PNG measurement (stdlib) ---

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
# Ancillary chunks kept by strip_png_metadata: the colour space only (deterministic).
KEPT_ANCILLARY = frozenset({b"sRGB", b"gAMA", b"cHRM"})


@dataclass(frozen=True)
class PngFacts:
    """What the checks read from a PNG. Pixel facts are None unless it is 8-bit RGBA."""

    width: int
    height: int
    bit_depth: int
    colour_type: int
    corner_alphas: tuple[int, int, int, int] | None  # top left, top right, bottom left, bottom right
    alpha_box: tuple[int, int, int, int] | None  # x0, y0, x1, y1 inclusive, of alpha above 0
    long_side: int | None
    centre: tuple[float, float] | None

    @property
    def is_rgba8(self) -> bool:
        return self.bit_depth == 8 and self.colour_type == 6

    def summary(self) -> str:
        mode = "RGBA 8 bit" if self.is_rgba8 else f"colour type {self.colour_type}"
        mode += f" (bit depth {self.bit_depth})" if not self.is_rgba8 else ""
        centre = "none" if self.centre is None else f"({self.centre[0]:g}, {self.centre[1]:g})"
        return (
            f"size {self.width}x{self.height}, {mode}, corner alphas {self.corner_alphas}, "
            f"alpha box {self.alpha_box}, long side {self.long_side} px, centre {centre}"
        )


def _chunks(data: bytes, path: Path) -> list[tuple[bytes, bytes, bytes]]:
    """(kind, body, raw chunk bytes with length and CRC) of every chunk up to IEND."""
    if not data.startswith(PNG_SIGNATURE):
        raise GeneratorError(f"not a PNG file: {path}")
    chunks: list[tuple[bytes, bytes, bytes]] = []
    offset = len(PNG_SIGNATURE)
    while offset + 8 <= len(data):
        length, kind = struct.unpack(">I4s", data[offset : offset + 8])
        end = offset + 12 + length
        if end > len(data):
            raise GeneratorError(f"truncated PNG chunk {kind!r}: {path}")
        chunks.append((kind, data[offset + 8 : offset + 8 + length], data[offset:end]))
        offset = end
        if kind == b"IEND":
            break
    if not chunks or chunks[0][0] != b"IHDR":
        raise GeneratorError(f"PNG without IHDR: {path}")
    return chunks


def strip_png_metadata(path: Path) -> None:
    """Rewrites ``path`` with only its critical chunks and the colour chunks in KEPT_ANCILLARY.

    Cycles adds its render statistics (render time and so on) as tEXt chunks even with every stamp
    flag off; they change on every run and would break the byte-identical output of AC 2. The
    pixel data is copied unchanged.
    """
    path = Path(path)
    kept = [
        raw
        for kind, _, raw in _chunks(path.read_bytes(), path)
        if kind[:1].isupper() or kind in KEPT_ANCILLARY
    ]
    path.write_bytes(PNG_SIGNATURE + b"".join(kept))


def _unfilter(raw: bytes, width: int, height: int, bpp: int, path: Path) -> list[bytearray]:
    stride = width * bpp
    if len(raw) != height * (stride + 1):
        raise GeneratorError(f"PNG pixel data has the wrong size: {path}")
    rows: list[bytearray] = []
    prior = bytearray(stride)
    for y in range(height):
        start = y * (stride + 1)
        kind = raw[start]
        row = bytearray(raw[start + 1 : start + 1 + stride])
        if kind == 1:
            for i in range(bpp, stride):
                row[i] = (row[i] + row[i - bpp]) & 0xFF
        elif kind == 2:
            for i in range(stride):
                row[i] = (row[i] + prior[i]) & 0xFF
        elif kind == 3:
            for i in range(stride):
                left = row[i - bpp] if i >= bpp else 0
                row[i] = (row[i] + ((left + prior[i]) >> 1)) & 0xFF
        elif kind == 4:
            for i in range(stride):
                left = row[i - bpp] if i >= bpp else 0
                up = prior[i]
                up_left = prior[i - bpp] if i >= bpp else 0
                p = left + up - up_left
                pa, pb, pc = abs(p - left), abs(p - up), abs(p - up_left)
                if pa <= pb and pa <= pc:
                    predicted = left
                elif pb <= pc:
                    predicted = up
                else:
                    predicted = up_left
                row[i] = (row[i] + predicted) & 0xFF
        elif kind != 0:
            raise GeneratorError(f"PNG row {y} has an unknown filter type {kind}: {path}")
        rows.append(row)
        prior = row
    return rows


def measure_png(path: Path) -> PngFacts:
    """Reads size, type, corner alphas and the box of the pixels with alpha above 0 (stdlib)."""
    try:
        data = Path(path).read_bytes()
    except OSError as error:
        raise GeneratorError(f"could not read {path}: {error}") from error
    chunks = _chunks(data, Path(path))
    ihdr = chunks[0][1]
    if len(ihdr) != 13:
        raise GeneratorError(f"PNG IHDR has the wrong size: {path}")
    width, height, bit_depth, colour_type, _, _, interlace = struct.unpack(">IIBBBBB", ihdr)
    if interlace != 0:
        raise GeneratorError(f"interlaced PNG is not supported: {path}")
    if bit_depth != 8 or colour_type != 6:
        return PngFacts(width, height, bit_depth, colour_type, None, None, None, None)
    try:
        raw = zlib.decompress(b"".join(body for kind, body, _ in chunks if kind == b"IDAT"))
    except zlib.error as error:
        raise GeneratorError(f"PNG pixel data is broken: {path}: {error}") from error
    rows = _unfilter(raw, width, height, 4, Path(path))
    last = 4 * (width - 1) + 3
    corners = (rows[0][3], rows[0][last], rows[-1][3], rows[-1][last])
    xs: list[int] = []
    ys: list[int] = []
    for y, row in enumerate(rows):
        alphas = row[3::4]
        if any(alphas):
            ys.append(y)
            xs.append(next(x for x, a in enumerate(alphas) if a))
            xs.append(width - 1 - next(x for x, a in enumerate(reversed(alphas)) if a))
    if not ys:
        return PngFacts(width, height, bit_depth, colour_type, corners, None, None, None)
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    return PngFacts(
        width=width,
        height=height,
        bit_depth=bit_depth,
        colour_type=colour_type,
        corner_alphas=corners,
        alpha_box=(x0, y0, x1, y1),
        long_side=max(x1 - x0 + 1, y1 - y0 + 1),
        centre=((x0 + x1 + 1) / 2.0, (y0 + y1 + 1) / 2.0),
    )


def check_thumbnail(path: Path) -> PngFacts:
    """The writer's check: a 256 x 256 8-bit RGBA PNG with transparent corners and some pixels."""
    facts = measure_png(path)
    if (facts.width, facts.height) != (SIZE_PX, SIZE_PX) or not facts.is_rgba8:
        raise GeneratorError(f"the render is not a {SIZE_PX} x {SIZE_PX} RGBA PNG: {facts.summary()}")
    if facts.corner_alphas != (0, 0, 0, 0):
        raise GeneratorError(f"the render has non-transparent corners: {facts.summary()}")
    if facts.alpha_box is None:
        raise GeneratorError("the render is empty: no pixel has alpha above 0")
    return facts


# --- checks before Blender ---


def _check_out_folder(folder: Path) -> None:
    if not folder.is_dir():
        raise GeneratorError(f"output folder does not exist: {folder}")
    try:
        with tempfile.TemporaryFile(dir=folder, prefix=".render_item_thumbnail_probe"):
            pass
    except OSError as error:
        raise GeneratorError(f"output folder cannot be written: {folder}: {error}") from error


def _check_model(model: Path) -> None:
    if not model.is_file():
        raise GeneratorError(f"model file not found: {model}")
    try:
        with model.open("rb") as handle:
            magic = handle.read(len(blender_common.GLB_MAGIC))
    except OSError as error:
        raise GeneratorError(f"could not read the model {model}: {error}") from error
    if magic != blender_common.GLB_MAGIC:
        raise GeneratorError(f"not a readable .glb (no glTF binary header): {model}")


# --- Blender part (bpy imported lazily) ---


def _set_render_settings(scene) -> None:  # noqa: ANN001 (bpy type)
    render = scene.render
    render.engine = "CYCLES"
    cycles = scene.cycles
    cycles.device = "CPU"
    cycles.seed = SEED
    cycles.use_animated_seed = False
    cycles.samples = SAMPLES
    cycles.use_adaptive_sampling = False
    cycles.use_denoising = False
    cycles.pixel_filter_type = "BLACKMAN_HARRIS"
    cycles.filter_width = FILTER_WIDTH_PX
    for layer in scene.view_layers:
        layer.cycles.use_denoising = False
        layer.cycles.denoising_store_passes = False
    render.film_transparent = True
    render.dither_intensity = 0.0
    render.use_compositing = False
    render.use_sequencer = False
    for prop in render.bl_rna.properties:
        if prop.identifier.startswith("use_stamp"):
            setattr(render, prop.identifier, False)
    view = scene.view_settings
    view.view_transform = "Standard"
    view.look = "None"
    view.exposure = 0.0
    view.gamma = 1.0
    view.use_curve_mapping = False
    scene.display_settings.display_device = "sRGB"
    image = render.image_settings
    image.file_format = "PNG"
    image.color_mode = "RGBA"
    image.color_depth = "8"
    image.compression = PNG_COMPRESSION
    render.resolution_x = SIZE_PX
    render.resolution_y = SIZE_PX
    render.resolution_percentage = 100
    render.pixel_aspect_x = 1.0
    render.pixel_aspect_y = 1.0
    render.use_file_extension = False


def _import_model(bpy, model: Path) -> list:  # noqa: ANN001
    before = set(bpy.data.objects)
    try:
        result = bpy.ops.import_scene.gltf(filepath=str(model))
    except RuntimeError as error:
        lines = [line for line in str(error).splitlines() if line.strip()]
        reason = lines[-1].strip() if lines else type(error).__name__
        raise GeneratorError(f"not a readable .glb: {model}: {reason}") from error
    if result != {"FINISHED"}:
        raise GeneratorError(f"not a readable .glb: {model}: import returned {result}")
    return [obj for obj in bpy.data.objects if obj not in before]


def _drop_foreign_objects(bpy, objects: list) -> list:  # noqa: ANN001
    """Removes cameras, lights, empties and every other non-mesh object; meshes keep their place."""
    meshes = [obj for obj in objects if obj.type == "MESH"]
    for obj in meshes:
        world = obj.matrix_world.copy()
        obj.parent = None
        obj.matrix_world = world
    for obj in objects:
        if obj.type != "MESH":
            bpy.data.objects.remove(obj, do_unlink=True)
    bpy.context.view_layer.update()
    return meshes


def _renders(obj) -> bool:  # noqa: ANN001
    if obj.hide_render or not obj.visible_get():
        return False
    return not any(collection.hide_render for collection in obj.users_collection)


def _framed_points(bpy, meshes: list, model: Path) -> tuple[list, list[Vec]]:  # noqa: ANN001
    """The meshes to frame (visible, at least one triangle) and their triangle vertices."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    framed = []
    points: list[Vec] = []
    for obj in meshes:
        if not _renders(obj):
            obj.hide_render = True
            continue
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        try:
            mesh.calc_loop_triangles()
            used = {index for tri in mesh.loop_triangles for index in tri.vertices}
            matrix = obj.matrix_world
            for index in sorted(used):
                p = matrix @ mesh.vertices[index].co
                points.append((p.x, p.y, p.z))
        finally:
            evaluated.to_mesh_clear()
        if used:
            framed.append(obj)
        else:
            obj.hide_render = True
    if not framed:
        raise GeneratorError(f"no visible mesh with a triangle in {model}")
    return framed, points


def _image_feeds(socket, seen: set | None = None) -> bool:  # noqa: ANN001
    """True when an image texture with pixel data is upstream of ``socket``."""
    seen = set() if seen is None else seen
    for link in socket.links:
        node = link.from_node
        if node.name in seen:
            continue
        seen.add(node.name)
        if node.type == "TEX_IMAGE":
            image = node.image
            if image is not None and image.size[0] > 0 and image.size[1] > 0:
                return True
        for upstream in node.inputs:
            if _image_feeds(upstream, seen):
                return True
    return False


def _neutralise_vertex_colours(tree) -> None:  # noqa: ANN001
    """Replaces every vertex colour output by white (colour 1, alpha 1)."""
    for link in list(tree.links):
        if link.from_node.type not in ("VERTEX_COLOR", "ATTRIBUTE"):
            continue
        target = link.to_socket
        tree.links.remove(link)
        value = getattr(target, "default_value", None)
        if value is None:
            continue
        if isinstance(value, float):
            target.default_value = 1.0
        elif len(value) == 4:
            target.default_value = (1.0, 1.0, 1.0, 1.0)
        elif len(value) == 3:
            target.default_value = (1.0, 1.0, 1.0)


def _prepare_material(material) -> bool:  # noqa: ANN001
    """Makes an atlas material opaque and double-sided; False when it has no readable image."""
    if material is None or material.node_tree is None:
        return False
    tree = material.node_tree
    shaders = [node for node in tree.nodes if node.type == "BSDF_PRINCIPLED"]
    if not shaders or not any(_image_feeds(s.inputs["Base Color"]) for s in shaders):
        return False
    _neutralise_vertex_colours(tree)
    for node in tree.nodes:
        if node.type == "TEX_IMAGE":
            node.interpolation = "Closest"
    for shader in shaders:
        alpha = shader.inputs["Alpha"]
        for link in list(alpha.links):
            tree.links.remove(link)
        alpha.default_value = 1.0
    material.use_backface_culling = False
    material.surface_render_method = "DITHERED"
    return True


def _grey_material(bpy):  # noqa: ANN001, ANN202
    material = bpy.data.materials.new("thumbnail_grey")
    material.use_backface_culling = False
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*GREY, 1.0)
    shader.inputs["Roughness"].default_value = GREY_ROUGHNESS
    return material


def _assign_materials(bpy, framed: list) -> None:  # noqa: ANN001
    grey = None
    checked: dict[str, bool] = {}
    for obj in framed:
        if not obj.material_slots:
            grey = grey or _grey_material(bpy)
            obj.data.materials.append(grey)
            continue
        for slot in obj.material_slots:
            material = slot.material
            usable = False
            if material is not None:
                if material.name not in checked:
                    checked[material.name] = _prepare_material(material)
                usable = checked[material.name]
            if not usable:
                grey = grey or _grey_material(bpy)
                slot.material = grey


def _add_world(bpy, scene) -> None:  # noqa: ANN001
    world = bpy.data.worlds.new("thumbnail_fill")
    background = world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (WORLD_GREY, WORLD_GREY, WORLD_GREY, 1.0)
    background.inputs["Strength"].default_value = WORLD_STRENGTH
    scene.world = world


def _add_camera(bpy, scene, framing: Framing) -> None:  # noqa: ANN001
    from mathutils import Matrix  # noqa: PLC0415 (only inside Blender)

    data = bpy.data.cameras.new("thumbnail_camera")
    data.type = "ORTHO"
    data.ortho_scale = framing.ortho_scale
    data.clip_start = framing.clip_start
    data.clip_end = framing.clip_end
    data.sensor_fit = "AUTO"
    data.shift_x = 0.0
    data.shift_y = 0.0
    camera = bpy.data.objects.new("thumbnail_camera", data)
    right, up, toward = framing.basis
    rotation = Matrix((right, up, toward)).transposed()  # columns: camera +X, +Y, +Z (looks -Z)
    camera.rotation_mode = "QUATERNION"
    camera.rotation_quaternion = rotation.to_quaternion()
    camera.location = framing.camera_location
    scene.collection.objects.link(camera)
    scene.camera = camera


def light_direction(basis: tuple[Vec, Vec, Vec]) -> Vec:
    """Unit vector from the item toward the sun, fixed relative to the view."""
    right, up, toward = basis
    a = math.radians(LIGHT_AZIMUTH_DEG)
    e = math.radians(LIGHT_ELEVATION_DEG)
    level = _sum(_scaled(toward, math.cos(a)), _scaled(right, -math.sin(a)))
    return _normalised(_sum(_scaled(level, math.cos(e)), _scaled(up, math.sin(e))))


def _add_sun(bpy, scene, framing: Framing) -> None:  # noqa: ANN001
    from mathutils import Vector  # noqa: PLC0415 (only inside Blender)

    data = bpy.data.lights.new("thumbnail_sun", "SUN")
    data.energy = SUN_STRENGTH
    data.angle = math.radians(SUN_ANGLE_DEG)
    data.color = SUN_COLOUR
    sun = bpy.data.objects.new("thumbnail_sun", data)
    sun.rotation_mode = "QUATERNION"
    # a sun shines along its local -Z, so its +Z points toward the light
    sun.rotation_quaternion = Vector(light_direction(framing.basis)).to_track_quat("Z", "Y")
    scene.collection.objects.link(sun)


def _render_to(bpy, scene, path: Path) -> None:  # noqa: ANN001
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    if not path.is_file():
        raise GeneratorError(f"the render wrote no file: {path}")
    strip_png_metadata(path)
    check_thumbnail(path)


def run(argv: list[str]) -> None:
    args = parse_args(argv)
    final = output_path(args.out, args.id)
    out_dir = args.out.resolve()
    model = args.model.resolve()
    _check_out_folder(out_dir)
    _check_model(model)

    import bpy  # noqa: PLC0415 (only inside Blender)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    objects = _import_model(bpy, model)
    meshes = _drop_foreign_objects(bpy, objects)
    framed, points = _framed_points(bpy, meshes, model)
    _assign_materials(bpy, framed)
    framing = fit_frame(points, AZIMUTH_DEG, ELEVATION_DEG, margin_px=MARGIN_PX + FILTER_SPILL_PX)
    _set_render_settings(scene)
    _add_world(bpy, scene)
    _add_camera(bpy, scene, framing)
    _add_sun(bpy, scene, framing)

    blender_common.write_group(
        out_dir,
        [(final.name, lambda path: _render_to(bpy, scene, path), blender_common.PNG_MAGIC)],
    )
    written = out_dir / final.name
    print(f"{PROG}: wrote {written}: {measure_png(written).summary()}", flush=True)


def main() -> int:
    return blender_common.main(PROG, run)


if __name__ == "__main__":
    sys.exit(main())
