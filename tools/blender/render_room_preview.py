"""Render preview stills of the #22 tank, cabinet, lamp and room assets headless in Blender 5.2.

Usage (the arguments after ``--`` belong to this script):

    blender --background --python tools/blender/render_room_preview.py -- --out-dir <dir>

Writes PNG files (1600 x 1000 px by default) into ``--out-dir``:

- ``<asset>_front.png`` and ``<asset>_side.png`` for tank, cabinet, lamp and room (orthographic);
- ``composed_default.png`` (the default front view: 50 degree horizontal field of view, 5 degree
  elevation, pivot at the water centre, tank width at 85% of the image width),
  ``composed_three_quarter.png``, ``composed_back_cutaway.png`` and ``composed_scale_4cm.png``
  (a 4 cm reference cube on the inner tank floor, fish size).

These are asset previews only. The lighting lives in Godot (KeyLight in lamp.tscn, the room
environment), so this script only approximates it: a warm spot at the lamp, a dim dusk-violet world,
AgX. The palette is read from the atlas through UV1 with a closest filter; the bottom atlas row
emits, like ``palette_atlas.gdshader``. The 4 cm cube exists only inside this script. Previews are
not committed (.claude/state is gitignored).

Exit code 0 on success, 1 on any error.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import room_palette  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]
ROOM_DIR = REPO_ROOT / "game" / "assets" / "room"
TANK_GLB = REPO_ROOT / "game" / "assets" / "tank" / "tank_medium_60l.glb"
ATLAS = ROOM_DIR / "room_palette_atlas.png"

CABINET_TOP = 0.75
GLASS = 0.005
TANK_Y = CABINET_TOP + GLASS  # tank root height in the room (glTF Y = Blender Z)
LAMP_MOUNT = (0.0, 0.36, -0.03)  # tank space, glTF frame (as in tank_medium_60l.tscn)
PIVOT_Y = 0.165  # centre of the water volume, tank space
HFOV_DEG = 50.0
ELEVATION_DEG = 5.0
WIDTH_SHARE = 0.85
EXTERIOR = (0.61, 0.31)
KEY_COLOUR = (1.0, 0.72, 0.5)
AMBIENT = (0.36, 0.30, 0.48)
AMBIENT_ENERGY = 0.2
LED_ENERGY = 3.0
GLASS_ALPHA = 0.12


def parse_args(argv: list[str]) -> argparse.Namespace:
    script_args = argv[argv.index("--") + 1 :] if "--" in argv else []
    parser = argparse.ArgumentParser(prog="render_room_preview.py")
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--width", type=int, default=1600)
    parser.add_argument("--height", type=int, default=1000)
    return parser.parse_args(script_args)


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


def _key_light(bpy, scene) -> None:  # noqa: ANN001
    data = bpy.data.lights.new("key", "SPOT")
    data.color = KEY_COLOUR
    data.energy = 12.0
    data.spot_size = math.radians(100.0)
    data.spot_blend = 0.6
    data.shadow_soft_size = 0.03
    light = bpy.data.objects.new("key", data)
    mount = (LAMP_MOUNT[0], TANK_Y + LAMP_MOUNT[1] + 0.018, LAMP_MOUNT[2])
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


def _render(bpy, scene, camera, path: Path, location, target, ortho: float | None) -> None:  # noqa: ANN001
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
    out = args.out_dir.resolve()
    out.mkdir(parents=True, exist_ok=True)
    scene, camera = _setup(bpy, args)
    atlas = bpy.data.images.load(str(ATLAS))
    palette = None
    glass = _glass_material(bpy)

    # single assets in neutral studio light, orthographic front (Blender -Y) and side (+X)
    _studio_light(bpy, scene)
    singles = (
        ("tank", TANK_GLB, (0.0, 0.0, 0.18), 0.8),
        ("cabinet", ROOM_DIR / "cabinet.glb", (0.0, 0.0, 0.375), 1.4),
        ("lamp", ROOM_DIR / "lamp.glb", (0.0, 0.0, 0.02), 0.68),
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
        _render(bpy, scene, camera, out / f"{name}_front.png", (target[0], -6.0, target[2]), target, size)
        _render(bpy, scene, camera, out / f"{name}_side.png", (6.0, target[1], target[2]), target, size)

    # composed room in the approximated room lighting
    for obj in list(bpy.data.objects):
        if obj.type == "LIGHT":
            bpy.data.objects.remove(obj, do_unlink=True)
    _clear_meshes(bpy)
    _import(bpy, ROOM_DIR / "room_corner.glb", palette, glass)
    _import(bpy, ROOM_DIR / "cabinet.glb", palette, glass)
    _import(bpy, TANK_GLB, palette, glass, (0.0, TANK_Y, 0.0))
    mount = (LAMP_MOUNT[0], TANK_Y + LAMP_MOUNT[1], LAMP_MOUNT[2])
    _import(bpy, ROOM_DIR / "lamp.glb", palette, glass, mount)
    _key_light(bpy, scene)

    pivot = (0.0, TANK_Y + PIVOT_Y, 0.0)
    half = math.radians(HFOV_DEG) / 2.0
    elevation = math.radians(ELEVATION_DEG)
    distance = EXTERIOR[0] / (2.0 * WIDTH_SHARE * math.tan(half)) + EXTERIOR[1] / 2.0 * math.cos(
        elevation
    )

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
    _render(bpy, scene, camera, out / "composed_default.png", orbit(0.0, ELEVATION_DEG, distance), target, None)
    _render(bpy, scene, camera, out / "composed_three_quarter.png", orbit(35.0, 18.0, 2.0), target, None)
    _render(bpy, scene, camera, out / "composed_back_cutaway.png", orbit(200.0, 20.0, 2.2), target, None)

    bpy.ops.mesh.primitive_cube_add(size=0.04)
    cube = bpy.context.active_object
    cube.name = "reference_4cm_cube"
    cube.location = _gltf_to_blender((0.1, TANK_Y + 0.02, 0.05))  # on the inner tank floor
    grey = bpy.data.materials.new("reference_grey")
    grey.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value = (0.6, 0.6, 0.6, 1)
    cube.data.materials.append(grey)
    _render(bpy, scene, camera, out / "composed_scale_4cm.png", orbit(20.0, 12.0, 1.1), target, None)


def main() -> int:
    try:
        run(sys.argv)
    except SystemExit as stop:
        return stop.code if isinstance(stop.code, int) else 1
    except BaseException as error:  # noqa: BLE001 (background Blender exits 0 otherwise)
        print(f"render_room_preview: error: {type(error).__name__}: {error}", file=sys.stderr, flush=True)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
