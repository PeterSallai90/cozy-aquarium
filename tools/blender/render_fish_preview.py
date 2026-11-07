"""Render preview stills of a generated fish .glb headless in Blender 5.2 (#21).

Usage (the arguments after ``--`` belong to this script):

    blender --background --python tools/blender/render_fish_preview.py -- \
        --glb game/assets/fish/proof_fish.glb --out-dir .claude/state/previews/21

Writes front.png, side.png, three_quarter.png and beside_4cm_cube.png (PNG, 1600 x 1000 px by
default). The fish is scaled to its runtime size (``--length-cm``, standard length, default 3.5)
and shaded like the proof shader: base colour from the palette atlas through UV1, vertex colour
alpha as the fin translucency mask. The 4 cm reference cube exists only inside this script; it is
never exported or committed. Previews are not committed (.claude/state is gitignored).

Exit code 0 on success, 1 on any error.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_GLB = REPO_ROOT / "game" / "assets" / "fish" / "proof_fish.glb"
ATLAS_NAME = "proof_palette_atlas.png"
FIN_OPACITY = 0.55
CUBE_EDGE_M = 0.04
BACKGROUND = (0.035, 0.09, 0.11)


def parse_args(argv: list[str]) -> argparse.Namespace:
    script_args = argv[argv.index("--") + 1 :] if "--" in argv else []
    parser = argparse.ArgumentParser(prog="render_fish_preview.py")
    parser.add_argument("--glb", type=Path, default=DEFAULT_GLB)
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--length-cm", type=float, default=3.5)
    parser.add_argument("--width", type=int, default=1600)
    parser.add_argument("--height", type=int, default=1000)
    return parser.parse_args(script_args)


def _material(bpy, name: str, atlas, uv_name: str, colour_name: str):  # noqa: ANN001, ANN202
    material = bpy.data.materials.new(name)
    material.use_backface_culling = name != "fin"
    material.surface_render_method = "BLENDED" if name == "fin" else "DITHERED"
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    shader = nodes.get("Principled BSDF")
    uv = nodes.new("ShaderNodeUVMap")
    uv.uv_map = uv_name
    image = nodes.new("ShaderNodeTexImage")
    image.image = atlas
    image.interpolation = "Linear"
    image.extension = "EXTEND"
    links.new(uv.outputs["UV"], image.inputs["Vector"])
    links.new(image.outputs["Color"], shader.inputs["Base Color"])
    shader.inputs["Roughness"].default_value = 0.6
    colour = nodes.new("ShaderNodeVertexColor")
    colour.layer_name = colour_name
    opacity = nodes.new("ShaderNodeMath")
    opacity.operation = "MULTIPLY_ADD"  # opacity = a * (fin_opacity - 1) + 1 = mix(1, fin_opacity, a)
    opacity.inputs[1].default_value = FIN_OPACITY - 1.0
    opacity.inputs[2].default_value = 1.0
    links.new(colour.outputs["Alpha"], opacity.inputs[0])
    clear = nodes.new("ShaderNodeBsdfTransparent")
    mix = nodes.new("ShaderNodeMixShader")
    links.new(opacity.outputs["Value"], mix.inputs["Fac"])
    links.new(clear.outputs["BSDF"], mix.inputs[1])
    links.new(shader.outputs["BSDF"], mix.inputs[2])
    output = nodes.get("Material Output")
    links.new(mix.outputs["Shader"], output.inputs["Surface"])
    return material


def _look_at(obj, target: tuple[float, float, float]) -> None:  # noqa: ANN001
    from mathutils import Vector  # noqa: PLC0415

    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def build_scene(bpy, args: argparse.Namespace):  # noqa: ANN001, ANN201
    bpy.ops.wm.read_factory_settings(use_empty=True)
    glb = args.glb.resolve()
    atlas_path = glb.parent / ATLAS_NAME
    if not glb.is_file() or not atlas_path.is_file():
        raise RuntimeError(f"missing input: {glb} or {atlas_path}")
    bpy.ops.import_scene.gltf(filepath=str(glb))
    fish = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
    mesh = fish.data
    if len(mesh.uv_layers) != 2:
        raise RuntimeError(f"expected 2 UV layers, found {len(mesh.uv_layers)}")
    atlas = bpy.data.images.load(str(atlas_path))
    uv1 = mesh.uv_layers[1].name
    colour_name = mesh.color_attributes[0].name
    for slot in fish.material_slots:
        slot.material = _material(bpy, slot.material.name, atlas, uv1, colour_name)
    scale = args.length_cm / 100.0
    fish.scale = (scale, scale, scale)
    fish.location = (0.0, 0.0, 0.0)

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = args.width
    scene.render.resolution_y = args.height
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "AgX"
    world = bpy.data.worlds.new("preview")
    world.color = BACKGROUND
    background = world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (*BACKGROUND, 1.0)
    background.inputs["Strength"].default_value = 1.0
    scene.world = world

    def sun(name: str, rotation: tuple[float, float, float], energy: float, colour) -> None:  # noqa: ANN001
        data = bpy.data.lights.new(name, "SUN")
        data.energy = energy
        data.color = colour
        light = bpy.data.objects.new(name, data)
        light.rotation_euler = rotation
        scene.collection.objects.link(light)

    sun("key", (math.radians(35), math.radians(25), math.radians(20)), 3.5, (1.0, 0.88, 0.72))
    sun("rim", (math.radians(-60), 0.0, math.radians(200)), 2.0, (0.7, 0.9, 1.0))
    sun("fill", (math.radians(80), 0.0, math.radians(90)), 0.8, (0.6, 0.8, 0.85))

    camera_data = bpy.data.cameras.new("camera")
    camera_data.clip_start = 0.001
    camera = bpy.data.objects.new("camera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    return scene, fish, camera


def render(bpy, scene, camera, path: Path, *, location, target, ortho: float | None) -> None:  # noqa: ANN001
    camera.location = location
    _look_at(camera, target)
    if ortho is None:
        camera.data.type = "PERSP"
        camera.data.lens = 85.0
    else:
        camera.data.type = "ORTHO"
        camera.data.ortho_scale = ortho
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    if not path.is_file():
        raise RuntimeError(f"render wrote no file: {path}")
    print(f"render_fish_preview: wrote {path}")


def run(argv: list[str]) -> None:
    import bpy  # noqa: PLC0415

    args = parse_args(argv)
    out_dir = args.out_dir.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    scene, fish, camera = build_scene(bpy, args)
    # Blender frame: the fish front is -Y, up is +Z, the fish centre is the origin.
    centre = (0.0, 0.0035, 0.0)  # midpoint of the total length, the tail reaches further back
    render(bpy, scene, camera, out_dir / "side.png", location=(0.3, 0.0035, 0.0), target=centre, ortho=0.06)
    render(bpy, scene, camera, out_dir / "front.png", location=(0.0, -0.3, 0.0), target=(0, 0, 0), ortho=0.035)
    render(
        bpy, scene, camera, out_dir / "three_quarter.png",
        location=(0.16, -0.12, 0.05), target=centre, ortho=None,
    )
    bpy.ops.mesh.primitive_cube_add(size=CUBE_EDGE_M, location=(0.0, 0.0, 0.0))
    cube = bpy.context.active_object
    cube.name = "reference_4cm_cube"
    cube.location = (0.0, 0.0, -0.034)  # below the fish, both seen from the side
    grey = bpy.data.materials.new("reference_grey")
    grey.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value = (0.5, 0.5, 0.5, 1)
    cube.data.materials.append(grey)
    render(
        bpy, scene, camera, out_dir / "beside_4cm_cube.png",
        location=(0.3, 0.0, -0.012), target=(0.0, 0.0, -0.012), ortho=0.1,
    )


def main() -> int:
    try:
        run(sys.argv)
    except SystemExit as stop:
        return stop.code if isinstance(stop.code, int) else 1
    except BaseException as error:  # noqa: BLE001 (background Blender exits 0 otherwise)
        print(f"render_fish_preview: error: {type(error).__name__}: {error}", file=sys.stderr, flush=True)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
