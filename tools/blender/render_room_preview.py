"""Render preview stills of one tank with its cabinet, lamp and the room, headless in Blender 5.2
(#22, #24).

Usage (the arguments after ``--`` belong to this script):

    blender --background --python tools/blender/render_room_preview.py -- \
        --out-dir <dir> [--tank tank_medium_1] [--width 1920 --height 1080]

Writes PNG files (1920 x 1080 px, 16:9, by default) into ``--out-dir``:

- ``<asset>_front.png`` and ``<asset>_side.png`` for tank, cabinet, lamp and room (orthographic);
- ``composed_default.png``: the default front view of ADR 0005 and ADR 0006 (50 degree
  horizontal field of view, 5 degree elevation, pivot at the water centre; distance = the larger
  of the 85% width distance and the 16:9 vertical-fit distance with a 2% margin);
- ``composed_three_quarter.png``, ``composed_back_cutaway.png`` and ``composed_scale_4cm.png``
  (a 4 cm reference cube on the inner tank floor, fish size).

The tank, cabinet and lamp of ``--tank`` are read from ``game/assets``; the sizes come from
``tools/blender/params/<tank>.json`` and ``room.json`` (the generator rules), the water line and
the lamp mount from ``game/scenes/tank/<tank>.tscn``, the key light from
``game/scenes/room/lamp_<suffix>.tscn``. The stand (cabinet, tank, lamp) stands with its back
``wall_gap_m`` in front of the fixed back wall (#24 plan section 4).

These are asset previews only. The lighting lives in Godot (KeyLight in the lamp scene, the room
environment), so this script only approximates it: a warm spot at the lamp, a dim dusk-violet world,
AgX. The palette is read from the atlas through UV1 with a closest filter; the bottom atlas row
emits, like ``palette_atlas.gdshader``. The 4 cm cube exists only inside this script. Previews are
not committed (.claude/state is gitignored).

Exit code 0 on success, 1 on any error.
"""

from __future__ import annotations

import argparse
import math
import re
import sys
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import generate_room  # noqa: E402
import generate_tank  # noqa: E402
import room_palette  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]
ROOM_DIR = REPO_ROOT / "game" / "assets" / "room"
TANK_DIR = REPO_ROOT / "game" / "assets" / "tank"
TANK_SCENES = REPO_ROOT / "game" / "scenes" / "tank"
LAMP_SCENES = REPO_ROOT / "game" / "scenes" / "room"
PARAMS_DIR = REPO_ROOT / "tools" / "blender" / "params"
ATLAS = ROOM_DIR / "room_palette_atlas.png"
DEFAULT_TANK = "tank_medium_1"

HFOV_DEG = 50.0
ELEVATION_DEG = 5.0
WIDTH_SHARE = 0.85
REFERENCE_ASPECT = 16.0 / 9.0
FIT_MARGIN = 0.02  # of the half screen height (ADR 0006)
MEDIUM_EXTERIOR_X = 0.61  # the #22 views were set up for this width
KEY_COLOUR = (1.0, 0.72, 0.5)
KEY_WATTS_PER_GODOT_ENERGY = 4.0  # 12 W for the medium lamp's energy 3.0
AMBIENT = (0.36, 0.30, 0.48)
AMBIENT_ENERGY = 0.2
LED_ENERGY = 3.0
GLASS_ALPHA = 0.12


@dataclass(frozen=True)
class Layout:
    """Room-space numbers of one tank on its stand, glTF frame (+Y up, +Z front)."""

    exterior: tuple[float, float, float]  # x, y (without trim), z
    glass: float
    trim: float
    water_line: float
    lamp_mount: tuple[float, float, float]  # tank space
    cabinet: tuple[float, float]  # width, depth
    cabinet_top: float
    stand_z: float
    key_energy: float
    key_angle_deg: float

    @property
    def tank_y(self) -> float:
        return self.cabinet_top + self.glass

    @property
    def pivot(self) -> tuple[float, float, float]:
        return (0.0, self.tank_y + self.water_line / 2.0, self.stand_z)


def parse_args(argv: list[str]) -> argparse.Namespace:
    script_args = argv[argv.index("--") + 1 :] if "--" in argv else []
    parser = argparse.ArgumentParser(prog="render_room_preview.py")
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--tank", default=DEFAULT_TANK)
    parser.add_argument("--width", type=int, default=1920)
    parser.add_argument("--height", type=int, default=1080)
    return parser.parse_args(script_args)


def _node_values(scene: Path, node: str, keys: tuple[str, ...]) -> dict[str, str]:
    """``key = value`` lines of one ``[node name="..."]`` section of a .tscn file."""
    text = scene.read_text(encoding="utf-8")
    match = re.search(rf'\[node name="{node}"[^\]]*\]\n(.*?)(?:\n\[|\Z)', text, re.S)
    if match is None:
        raise RuntimeError(f"{scene.name}: node {node} not found")
    values: dict[str, str] = {}
    for line in match.group(1).splitlines():
        key, _, value = line.partition(" = ")
        if key in keys:
            values[key] = value
    return values


def _origin(transform: str) -> tuple[float, float, float]:
    numbers = [float(n) for n in transform[transform.index("(") + 1 : -1].split(",")]
    return (numbers[9], numbers[10], numbers[11])


def layout_for(tank_id: str) -> Layout:
    tank = generate_tank.load_params(PARAMS_DIR / f"{tank_id}.json")
    room = generate_room.load_params(PARAMS_DIR / "room.json")
    merged = generate_room.params_for_tank(room, tank)
    suffix = tank_id.removeprefix("tank_")
    tank_scene = TANK_SCENES / f"{tank_id}.tscn"
    water = _origin(_node_values(tank_scene, "WaterVolume", ("transform",))["transform"])
    mount = _origin(_node_values(tank_scene, "lamp_mount", ("transform",))["transform"])
    lamp_scene = LAMP_SCENES / f"lamp_{suffix}.tscn"
    key = _node_values(lamp_scene, "KeyLight", ("light_energy", "spot_angle"))
    glass = tank["glass_thickness_m"]
    depth = merged["cabinet_depth_m"]
    return Layout(
        exterior=(
            tank["interior_length_m"] + 2.0 * glass,
            tank["interior_height_m"] + glass,
            tank["interior_depth_m"] + 2.0 * glass,
        ),
        glass=glass,
        trim=tank["trim_size_m"],
        water_line=2.0 * water[1],
        lamp_mount=mount,
        cabinet=(merged["cabinet_width_m"], depth),
        cabinet_top=room["cabinet_height_m"],
        stand_z=-room["back_wall_distance_m"] + room["wall_gap_m"] + depth / 2.0,
        key_energy=float(key["light_energy"]),
        key_angle_deg=float(key["spot_angle"]),
    )


def width_distance(lay: Layout) -> float:
    """ADR 0005: the exterior width fills WIDTH_SHARE of the screen width."""
    half = math.radians(HFOV_DEG) / 2.0
    elevation = math.radians(ELEVATION_DEG)
    across = lay.exterior[0] / (2.0 * WIDTH_SHARE * math.tan(half))
    return across + lay.exterior[2] / 2.0 * math.cos(elevation)


def _fit_points(lay: Layout) -> list[tuple[float, float, float]]:
    """The tank exterior with the trim, and the front edge of the cabinet top."""
    hx = lay.exterior[0] / 2.0
    hz = lay.exterior[2] / 2.0
    low = lay.cabinet_top
    high = lay.tank_y + lay.exterior[1] - lay.glass + lay.trim
    points = [
        (sx * hx, y, lay.stand_z + sz * hz) for sx in (-1, 1) for y in (low, high) for sz in (-1, 1)
    ]
    front = lay.stand_z + lay.cabinet[1] / 2.0
    points += [(sx * lay.cabinet[0] / 2.0, lay.cabinet_top, front) for sx in (-1, 1)]
    return points


def worst_vertical(lay: Layout, distance: float) -> float:
    """The largest |y| of the fit points in units of the half screen height at 16:9."""
    elevation = math.radians(ELEVATION_DEG)
    pivot = lay.pivot
    camera = (
        pivot[0],
        pivot[1] + distance * math.sin(elevation),
        pivot[2] + distance * math.cos(elevation),
    )
    forward = (0.0, -math.sin(elevation), -math.cos(elevation))
    up = (0.0, math.cos(elevation), -math.sin(elevation))
    tan_v = math.tan(math.radians(HFOV_DEG) / 2.0) / REFERENCE_ASPECT
    worst = 0.0
    for point in _fit_points(lay):
        v = (point[0] - camera[0], point[1] - camera[1], point[2] - camera[2])
        depth = sum(a * b for a, b in zip(v, forward, strict=True))
        height = sum(a * b for a, b in zip(v, up, strict=True))
        worst = max(worst, abs(height / (depth * tan_v)))
    return worst


def fit_distance(lay: Layout) -> float:
    """ADR 0006: the smallest distance that keeps every fit point inside 1 - FIT_MARGIN."""
    low, high = 0.05, 20.0
    for _ in range(80):
        middle = (low + high) / 2.0
        if worst_vertical(lay, middle) <= 1.0 - FIT_MARGIN:
            high = middle
        else:
            low = middle
    return high


def default_distance(lay: Layout) -> tuple[float, float, float]:
    """(distance, width distance, fit distance)."""
    d_w = width_distance(lay)
    d_v = fit_distance(lay)
    return max(d_w, d_v), d_w, d_v


def width_share(lay: Layout, distance: float) -> float:
    half = math.radians(HFOV_DEG) / 2.0
    front = distance - lay.exterior[2] / 2.0 * math.cos(math.radians(ELEVATION_DEG))
    return lay.exterior[0] / (2.0 * front * math.tan(half))


def _gltf_to_blender(p: tuple[float, float, float]) -> tuple[float, float, float]:
    return (p[0], -p[2], p[1])


def _palette_material(bpy, atlas, uv_name: str):  # noqa: ANN001, ANN202
    material = bpy.data.materials.new("preview_palette")
    material.use_backface_culling = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    shader = nodes.get("Principled BSDF")
    uv = nodes.new("ShaderNodeUVMap")
    uv.uv_map = uv_name
    image = nodes.new("ShaderNodeTexImage")
    image.image = atlas
    image.interpolation = "Closest"
    image.extension = "EXTEND"
    links.new(uv.outputs["UV"], image.inputs["Vector"])
    links.new(image.outputs["Color"], shader.inputs["Base Color"])
    shader.inputs["Roughness"].default_value = 0.75
    # the bottom atlas row emits: Godot UV2.y >= EMISSIVE_V_MIN is Blender v <= 1 - EMISSIVE_V_MIN
    split = nodes.new("ShaderNodeSeparateXYZ")
    links.new(uv.outputs["UV"], split.inputs["Vector"])
    mask = nodes.new("ShaderNodeMath")
    mask.operation = "LESS_THAN"
    mask.inputs[1].default_value = 1.0 - room_palette.EMISSIVE_V_MIN
    links.new(split.outputs["Y"], mask.inputs[0])
    strength = nodes.new("ShaderNodeMath")
    strength.operation = "MULTIPLY"
    strength.inputs[1].default_value = LED_ENERGY
    links.new(mask.outputs["Value"], strength.inputs[0])
    links.new(image.outputs["Color"], shader.inputs["Emission Color"])
    links.new(strength.outputs["Value"], shader.inputs["Emission Strength"])
    return material


def _glass_material(bpy):  # noqa: ANN001, ANN202
    material = bpy.data.materials.new("preview_glass")
    material.surface_render_method = "BLENDED"
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (0.86, 0.96, 0.93, 1.0)
    shader.inputs["Alpha"].default_value = GLASS_ALPHA
    shader.inputs["Roughness"].default_value = 0.05
    return material


def _import(bpy, path: Path, palette, glass, offset=(0.0, 0.0, 0.0)) -> list:  # noqa: ANN001
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    added = [obj for obj in bpy.data.objects if obj not in before and obj.type == "MESH"]
    for obj in added:
        if len(obj.data.uv_layers) != 2:
            raise RuntimeError(f"{path.name}/{obj.name}: expected 2 UV layers")
        for slot in obj.material_slots:
            slot.material = glass if slot.material.name.startswith("glass") else palette
        obj.location = _gltf_to_blender(offset)
    return added


def _look_at(obj, target) -> None:  # noqa: ANN001
    from mathutils import Vector  # noqa: PLC0415

    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def _setup(bpy, args):  # noqa: ANN001, ANN202
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = args.width
    scene.render.resolution_y = args.height
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "AgX"
    world = bpy.data.worlds.new("preview")
    background = world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (*AMBIENT, 1.0)
    background.inputs["Strength"].default_value = AMBIENT_ENERGY
    scene.world = world
    camera_data = bpy.data.cameras.new("camera")
    camera_data.clip_start = 0.005
    camera_data.sensor_fit = "HORIZONTAL"
    camera = bpy.data.objects.new("camera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    return scene, camera


def _key_light(bpy, scene, lay: Layout) -> None:  # noqa: ANN001
    data = bpy.data.lights.new("key", "SPOT")
    data.color = KEY_COLOUR
    data.energy = KEY_WATTS_PER_GODOT_ENERGY * lay.key_energy
    # the #22 preview used 100 degrees for the Godot half angle of 55 degrees
    data.spot_size = math.radians(min(2.0 * lay.key_angle_deg - 10.0, 179.0))
    data.spot_blend = 0.6
    data.shadow_soft_size = 0.03
    light = bpy.data.objects.new("key", data)
    mount = (
        lay.lamp_mount[0],
        lay.tank_y + lay.lamp_mount[1] + 0.018,
        lay.stand_z + lay.lamp_mount[2],
    )
    light.location = _gltf_to_blender(mount)
    light.rotation_euler = (0.0, 0.0, 0.0)  # Blender spots point down -Z
    scene.collection.objects.link(light)


def _studio_light(bpy, scene) -> None:  # noqa: ANN001
    data = bpy.data.lights.new("studio", "SUN")
    data.energy = 2.5
    data.color = (1.0, 0.95, 0.9)
    light = bpy.data.objects.new("studio", data)
    light.rotation_euler = (math.radians(50), 0.0, math.radians(-30))
    scene.collection.objects.link(light)


def _render(  # noqa: ANN001
    bpy, scene, camera, path: Path, location, target, ortho: float | None
) -> None:
    camera.location = location
    _look_at(camera, target)
    if ortho is None:
        camera.data.type = "PERSP"
        camera.data.angle = math.radians(HFOV_DEG)
    else:
        camera.data.type = "ORTHO"
        camera.data.ortho_scale = ortho
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    if not path.is_file():
        raise RuntimeError(f"render wrote no file: {path}")
    print(f"render_room_preview: wrote {path}")


def _clear_meshes(bpy) -> None:  # noqa: ANN001
    for obj in list(bpy.data.objects):
        if obj.type == "MESH":
            bpy.data.objects.remove(obj, do_unlink=True)


def run(argv: list[str]) -> None:
    import bpy  # noqa: PLC0415

    args = parse_args(argv)
    tank_id: str = args.tank
    suffix = tank_id.removeprefix("tank_")
    tank_glb = TANK_DIR / f"{tank_id}.glb"
    cabinet_glb = ROOM_DIR / f"cabinet_{suffix}.glb"
    lamp_glb = ROOM_DIR / f"lamp_{suffix}.glb"
    lay = layout_for(tank_id)
    distance, d_w, d_v = default_distance(lay)
    print(
        f"render_room_preview: {tank_id} stand_z {lay.stand_z:.4f} width distance {d_w:.4f} "
        f"fit distance {d_v:.4f} default {distance:.4f} share {width_share(lay, distance):.3f} "
        f"worst |y| {worst_vertical(lay, distance):.3f}"
    )
    out = args.out_dir.resolve()
    out.mkdir(parents=True, exist_ok=True)
    scene, camera = _setup(bpy, args)
    atlas = bpy.data.images.load(str(ATLAS))
    palette = None
    glass = _glass_material(bpy)
    ext_x, ext_y, _ext_z = lay.exterior
    scale = min(max(ext_x / MEDIUM_EXTERIOR_X, 0.8), 1.7)

    # single assets in neutral studio light, orthographic front (Blender -Y) and side (+X)
    _studio_light(bpy, scene)
    aspect = args.width / args.height

    def ortho(across: float, tall: float) -> float:
        """Orthographic width that shows ``across`` x ``tall`` metres with a 25% border."""
        return 1.25 * max(across, tall * aspect)

    tall_tank = ext_y + lay.trim
    singles = (
        ("tank", tank_glb, (0.0, 0.0, tall_tank / 2.0 - lay.glass), ortho(ext_x, tall_tank)),
        (
            "cabinet",
            cabinet_glb,
            (0.0, 0.0, lay.cabinet_top / 2.0),
            ortho(lay.cabinet[0], lay.cabinet_top),
        ),
        ("lamp", lamp_glb, (0.0, 0.0, 0.02), ext_x * 1.1),
        ("room", ROOM_DIR / "room_corner.glb", (0.4, 0.4, 1.15), 4.4),
    )
    for name, path, centre, size in singles:
        _clear_meshes(bpy)
        objects = _import(bpy, path, None, glass)
        if palette is None:
            uv_name = objects[0].data.uv_layers[1].name
            palette = _palette_material(bpy, atlas, uv_name)
        for obj in objects:
            for slot in obj.material_slots:
                if slot.material is not glass:
                    slot.material = palette
        target = (centre[0], centre[1], centre[2])
        front = (target[0], -6.0, target[2])
        side = (6.0, target[1], target[2])
        _render(bpy, scene, camera, out / f"{name}_front.png", front, target, size)
        _render(bpy, scene, camera, out / f"{name}_side.png", side, target, size)

    # composed room in the approximated room lighting
    for obj in list(bpy.data.objects):
        if obj.type == "LIGHT":
            bpy.data.objects.remove(obj, do_unlink=True)
    _clear_meshes(bpy)
    _import(bpy, ROOM_DIR / "room_corner.glb", palette, glass)
    _import(bpy, cabinet_glb, palette, glass, (0.0, 0.0, lay.stand_z))
    _import(bpy, tank_glb, palette, glass, (0.0, lay.tank_y, lay.stand_z))
    mount = (
        lay.lamp_mount[0],
        lay.tank_y + lay.lamp_mount[1],
        lay.stand_z + lay.lamp_mount[2],
    )
    _import(bpy, lamp_glb, palette, glass, mount)
    _key_light(bpy, scene, lay)

    pivot = lay.pivot

    def orbit(yaw_deg: float, pitch_deg: float, dist: float):  # noqa: ANN202
        yaw = math.radians(yaw_deg)
        pitch = math.radians(pitch_deg)
        p = (
            pivot[0] + dist * math.cos(pitch) * math.sin(yaw),
            pivot[1] + dist * math.sin(pitch),
            pivot[2] + dist * math.cos(pitch) * math.cos(yaw),
        )
        return _gltf_to_blender(p)

    target = _gltf_to_blender(pivot)
    default_view = orbit(0.0, ELEVATION_DEG, distance)
    _render(bpy, scene, camera, out / "composed_default.png", default_view, target, None)
    three_quarter = orbit(35.0, 18.0, 2.0 * scale)
    _render(bpy, scene, camera, out / "composed_three_quarter.png", three_quarter, target, None)
    cutaway = orbit(200.0, 20.0, 2.2 * scale)
    _render(bpy, scene, camera, out / "composed_back_cutaway.png", cutaway, target, None)

    bpy.ops.mesh.primitive_cube_add(size=0.04)
    cube = bpy.context.active_object
    cube.name = "reference_4cm_cube"
    # on the inner tank floor, right of centre and toward the front
    floor_point = (ext_x / 6.0, lay.tank_y + 0.02, lay.stand_z + lay.exterior[2] / 6.0)
    cube.location = _gltf_to_blender(floor_point)
    grey = bpy.data.materials.new("reference_grey")
    grey_shader = grey.node_tree.nodes.get("Principled BSDF")
    grey_shader.inputs["Base Color"].default_value = (0.6, 0.6, 0.6, 1)
    cube.data.materials.append(grey)
    scale_view = orbit(20.0, 12.0, 1.1 * scale)
    _render(bpy, scene, camera, out / "composed_scale_4cm.png", scale_view, target, None)


def main() -> int:
    try:
        run(sys.argv)
    except SystemExit as stop:
        return stop.code if isinstance(stop.code, int) else 1
    except BaseException as error:  # noqa: BLE001 (background Blender exits 0 otherwise)
        message = f"render_room_preview: error: {type(error).__name__}: {error}"
        print(message, file=sys.stderr, flush=True)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
