"""Render preview stills of a generated fish .glb headless in Blender 5.2 (#21).

Usage (the arguments after ``--`` belong to this script):

    blender --background --python tools/blender/render_fish_preview.py -- \
        --glb game/assets/fish/proof_fish.glb --out-dir .claude/state/previews/21

    blender --background --python tools/blender/render_fish_preview.py -- \
        --species neon_tetra --length-cm 3.0 --out-dir .claude/state/previews/34/neon_tetra

Writes front.png, side.png, three_quarter.png and beside_4cm_cube.png (PNG, 1600 x 1000 px by
default). The fish is scaled to its runtime size (``--length-cm``, standard length, default 3.5;
with ``--species`` and no ``--length-cm``, the value of ``adult_length_cm`` in
``game/catalog/fish/<id>.tres``, which must then exist) and shaded like the proof shader: base
colour from the palette atlas through UV1, vertex colour alpha as the fin translucency mask. With
``--species`` the camera framing follows the fish size. The 4 cm reference cube exists only inside
this script; it is never exported or committed. Previews are not committed (.claude/state is
gitignored).

``--species <id>`` (#34) reads ``game/assets/fish/<id>.glb``, the shared ``fish_palette_atlas.png``
and the species mask ``<id>_mask.png`` (UV0): R and G regions and the B eye bands (pupil, iris
ring, painted dot, read unfiltered) are painted with ``PREVIEW_COLOURS``, the linearised colours of
the species materials; the material files stay the source of the game colours.

Exit code 0 on success, 1 on any error.
"""

from __future__ import annotations

import argparse
import math
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
ASSET_DIR = REPO_ROOT / "game" / "assets" / "fish"
CATALOG_DIR = REPO_ROOT / "game" / "catalog" / "fish"
DEFAULT_GLB = ASSET_DIR / "proof_fish.glb"
ATLAS_NAME = "proof_palette_atlas.png"
SPECIES_ATLAS_NAME = "fish_palette_atlas.png"
FIN_OPACITY = 0.55
# fin_opacity of the species materials (game/assets/fish/materials/<id>.tres).
SPECIES_FIN_OPACITY = {"neon_tetra": 0.4, "angelfish": 0.35, "bronze_corydoras": 0.6}
CUBE_EDGE_M = 0.04
BACKGROUND = (0.035, 0.09, 0.11)
PROOF_LENGTH_M = 0.035  # the framing below was set for the 3.5 cm proof fish

# Preview colours (linear RGB) for the mask regions: R, G, eye pupil, iris ring, painted dot. They
# are the sRGB values of game/assets/fish/materials/<id>.tres linearised (the painted dot is
# mix(eye_colour, eye_highlight_colour, eye_highlight_strength 0.85)). Shimmer, tint, glint and the
# bend are shader effects and show only in the in-engine previews.
PREVIEW_COLOURS: dict[str, dict[str, tuple[float, float, float]]] = {
    "neon_tetra": {
        "r": (0.0153, 0.3931, 0.6038),
        "g": (0.6739, 0.0153, 0.0174),
        "pupil": (0.0039, 0.0039, 0.0049),
        "iris": (0.0039, 0.0039, 0.0049),
        "dot": (0.794, 0.794, 0.739),
    },
    "angelfish": {
        "r": (0.022, 0.022, 0.0272),
        "g": (0.6383, 0.6383, 0.6038),
        "pupil": (0.0039, 0.0031, 0.0031),
        "iris": (0.7106, 0.0637, 0.0072),
        "dot": (0.794, 0.794, 0.739),
    },
    "bronze_corydoras": {
        "r": (0.0397, 0.1065, 0.0637),
        "g": (0.5705, 0.233, 0.055),
        "pupil": (0.0039, 0.0039, 0.0049),
        "iris": (0.0039, 0.0039, 0.0049),
        "dot": (0.794, 0.794, 0.739),
    },
}


def parse_args(argv: list[str]) -> argparse.Namespace:
    script_args = argv[argv.index("--") + 1 :] if "--" in argv else []
    parser = argparse.ArgumentParser(prog="render_fish_preview.py")
    parser.add_argument("--glb", type=Path, default=None)
    parser.add_argument("--species", default=None)
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--length-cm", type=float, default=None)
    parser.add_argument("--width", type=int, default=1600)
    parser.add_argument("--height", type=int, default=1000)
    args = parser.parse_args(script_args)
    if args.species is not None:
        if args.species not in PREVIEW_COLOURS:
            parser.error(f"unknown species {args.species!r}; known: {', '.join(PREVIEW_COLOURS)}")
        args.glb = args.glb or ASSET_DIR / f"{args.species}.glb"
        catalog = CATALOG_DIR / f"{args.species}.tres"
        if catalog.is_file():
            found = re.search(r"^adult_length_cm\s*=\s*([0-9.]+)", catalog.read_text("utf-8"), re.M)
            if found and args.length_cm is None:
                args.length_cm = float(found.group(1))
        if args.length_cm is None:
            parser.error(f"--length-cm is required: no adult_length_cm in {catalog}")
    args.glb = args.glb or DEFAULT_GLB
    if args.length_cm is None:
        args.length_cm = 3.5
    return args


def _mask_regions(  # noqa: ANN202
    bpy, material, base_socket, mask, uv0_name: str, colours: dict  # noqa: ANN001
):
    """Paints the mask regions over the atlas colour: R, G (filtered), then the B eye bands."""
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    uv = nodes.new("ShaderNodeUVMap")
    uv.uv_map = uv0_name
    smooth = nodes.new("ShaderNodeTexImage")
    smooth.image = mask
    smooth.interpolation = "Linear"
    hard = nodes.new("ShaderNodeTexImage")
    hard.image = mask
    hard.interpolation = "Closest"
    for image_node in (smooth, hard):
        links.new(uv.outputs["UV"], image_node.inputs["Vector"])
    split = nodes.new("ShaderNodeSeparateColor")
    links.new(smooth.outputs["Color"], split.inputs["Color"])
    split_hard = nodes.new("ShaderNodeSeparateColor")
    links.new(hard.outputs["Color"], split_hard.inputs["Color"])
    current = base_socket

    def mix(factor_socket, colour, threshold: float | None = None):  # noqa: ANN001, ANN202
        node = nodes.new("ShaderNodeMix")
        node.data_type = "RGBA"
        if threshold is None:
            links.new(factor_socket, node.inputs["Factor"])
        else:
            step = nodes.new("ShaderNodeMath")
            step.operation = "GREATER_THAN"
            step.inputs[1].default_value = threshold
            links.new(factor_socket, step.inputs[0])
            links.new(step.outputs["Value"], node.inputs["Factor"])
        links.new(current, node.inputs["A"])
        node.inputs["B"].default_value = (*colour, 1.0)
        return node.outputs["Result"]

    current = mix(split.outputs["Red"], colours["r"])
    current = mix(split.outputs["Green"], colours["g"])
    current = mix(split_hard.outputs["Blue"], colours["pupil"], 1.0 / 6.0)
    current = mix(split_hard.outputs["Blue"], colours["iris"], 0.5)
    current = mix(split_hard.outputs["Blue"], colours["dot"], 5.0 / 6.0)
    return current


def _material(  # noqa: ANN202
    bpy,  # noqa: ANN001
    name: str,
    atlas,  # noqa: ANN001
    uv_name: str,
    colour_name: str,
    mask=None,  # noqa: ANN001
    uv0_name: str = "",
    colours: dict | None = None,
    fin_opacity: float = FIN_OPACITY,
):
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
    colour_socket = image.outputs["Color"]
    if mask is not None:
        colour_socket = _mask_regions(bpy, material, colour_socket, mask, uv0_name, colours)
    links.new(colour_socket, shader.inputs["Base Color"])
    shader.inputs["Roughness"].default_value = 0.6
    colour = nodes.new("ShaderNodeVertexColor")
    colour.layer_name = colour_name
    opacity = nodes.new("ShaderNodeMath")
    opacity.operation = "MULTIPLY_ADD"  # opacity = a * (fin_opacity - 1) + 1 = mix(1, fin_opacity, a)
    opacity.inputs[1].default_value = fin_opacity - 1.0
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
    atlas_path = glb.parent / (SPECIES_ATLAS_NAME if args.species else ATLAS_NAME)
    if not glb.is_file() or not atlas_path.is_file():
        raise RuntimeError(f"missing input: {glb} or {atlas_path}")
    mask = None
    if args.species:
        mask_path = glb.parent / f"{args.species}_mask.png"
        if not mask_path.is_file():
            raise RuntimeError(f"missing input: {mask_path}")
        mask = bpy.data.images.load(str(mask_path))
        mask.colorspace_settings.name = "Non-Color"
        mask.alpha_mode = "NONE"  # A is the tint region, not transparency
    bpy.ops.import_scene.gltf(filepath=str(glb))
    fish = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH")
    mesh = fish.data
    if len(mesh.uv_layers) != 2:
        raise RuntimeError(f"expected 2 UV layers, found {len(mesh.uv_layers)}")
    atlas = bpy.data.images.load(str(atlas_path))
    uv0 = mesh.uv_layers[0].name
    uv1 = mesh.uv_layers[1].name
    colour_name = mesh.color_attributes[0].name
    colours = PREVIEW_COLOURS.get(args.species or "", {})
    fin_opacity = SPECIES_FIN_OPACITY.get(args.species or "", FIN_OPACITY)
    for slot in fish.material_slots:
        slot.material = _material(
            bpy, slot.material.name, atlas, uv1, colour_name, mask, uv0, colours, fin_opacity
        )
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


def render_species(bpy, scene, fish, camera, out_dir: Path) -> None:  # noqa: ANN001
    """The four views, framed from the world bounding box of the scaled fish (fins included)."""
    from mathutils import Vector  # noqa: PLC0415

    bpy.context.view_layer.update()
    corners = [fish.matrix_world @ Vector(corner) for corner in fish.bound_box]
    low = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
    high = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
    centre = (low + high) / 2.0
    size = high - low
    aspect = scene.render.resolution_x / scene.render.resolution_y
    far = 10.0 * max(size)
    side = 1.15 * max(size.y, size.z * aspect)
    target = tuple(centre)
    render(bpy, scene, camera, out_dir / "side.png",
           location=(centre.x + far, centre.y, centre.z), target=target, ortho=side)
    front = 1.25 * max(size.x * aspect, size.z)
    render(bpy, scene, camera, out_dir / "front.png",
           location=(centre.x, centre.y - far, centre.z), target=target, ortho=front)
    d = 2.6 * max(size)
    render(bpy, scene, camera, out_dir / "three_quarter.png",
           location=(centre.x + 0.75 * d, centre.y - 0.6 * d, centre.z + 0.25 * d),
           target=target, ortho=None)
    bpy.ops.mesh.primitive_cube_add(size=CUBE_EDGE_M, location=(0.0, 0.0, 0.0))
    cube = bpy.context.active_object
    cube.name = "reference_4cm_cube"
    gap = 0.005
    cube.location = (0.0, centre.y, low.z - gap - 0.5 * CUBE_EDGE_M)  # below the fish, side view
    grey = bpy.data.materials.new("reference_grey")
    grey.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value = (0.5, 0.5, 0.5, 1)
    cube.data.materials.append(grey)
    both_low = low.z - gap - CUBE_EDGE_M
    middle_z = 0.5 * (both_low + high.z)
    span = 1.2 * max(size.y, CUBE_EDGE_M, (high.z - both_low) * aspect)
    render(bpy, scene, camera, out_dir / "beside_4cm_cube.png",
           location=(far, centre.y, middle_z), target=(0.0, centre.y, middle_z), ortho=span)


def run(argv: list[str]) -> None:
    import bpy  # noqa: PLC0415

    args = parse_args(argv)
    out_dir = args.out_dir.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    scene, fish, camera = build_scene(bpy, args)
    if args.species:
        render_species(bpy, scene, fish, camera, out_dir)
        return
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
