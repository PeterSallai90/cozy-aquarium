"""Render preview stills of the starter decoration set (#157) headless in Blender 5.2.

Usage (the arguments after ``--`` belong to this script):

    blender --background --python tools/blender/render_decor_preview.py -- \
        --out-dir .claude/state/previews/157 [--width 1600 --height 1000]

Reads the committed ``game/assets/items/models/<id>.glb`` files, ``decor_palette_atlas.png`` and
the 4 cm reference fish ``game/assets/fish/proof_fish.glb``, and writes PNG files (1600 x 1000 px
by default) into ``--out-dir``:

- ``<id>_front.png`` (orthographic from glTF +Z, the model front), ``<id>_side.png``
  (orthographic from +X), ``<id>_top.png`` (orthographic from above) and
  ``<id>_three_quarter.png`` (perspective) for each item, plus
  ``<id>_three_quarter_vertex_shade_0.png`` (the same view without the vertex colours);
- ``river_stone_underside.png``: the flat underside seen from below;
- ``clay_amphora_cutaway.png``: the amphora cut in half at x = 0 (preview only, the cut face has
  its own plain colour), to show the cavity, the wall and the inside depth;
- ``set_front_4cm_fish.png``, ``set_three_quarter_4cm_fish.png`` and
  ``set_three_quarter_vertex_shade_0.png``: the three at real size (1 unit = 1 m) on a 5 cm
  checker ground beside the proof fish scaled to a 4 cm standard length;
- ``measurements.json``: per item the LOD0 triangle count, the bounds (cm), the lowest point,
  the x/z centre, non-manifold edges and connected parts (``bmesh``, after welding the split
  vertices of the glb), the stone's flat underside extent and the amphora's AC 22 numbers
  (``generate_decor.amphora_measurements`` on the welded glb mesh).

Shading follows ``palette_atlas.gdshader`` with ``decor_palette.tres``: the base colour is the
atlas cell through UV1 (closest filter) times ``mix(1, COLOR.rgb, vertex_shade)``, roughness 0.75.
The light is a neutral studio rig, not the Godot room light, so the in-engine screenshot is the
reference for the final look. The ground, the fish and the cut face exist only inside this script.
Previews are not committed (.claude/state is gitignored).

Exit code 0 on success, 1 on any error.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import generate_decor  # noqa: E402
import render_fish_preview  # noqa: E402
from blender_common import MeshData  # noqa: E402

PROG = "render_decor_preview"
REPO_ROOT = Path(__file__).resolve().parents[2]
ITEMS_DIR = REPO_ROOT / "game" / "assets" / "items"
ATLAS = ITEMS_DIR / "decor_palette_atlas.png"
FISH_GLB = REPO_ROOT / "game" / "assets" / "fish" / "proof_fish.glb"
FISH_ATLAS = FISH_GLB.parent / render_fish_preview.ATLAS_NAME
IDS = (generate_decor.STONE_ID, generate_decor.BRANCH_ID, generate_decor.AMPHORA_ID)
FISH_LENGTH_CM = 4.0
ROUGHNESS = 0.75  # decor_palette.tres
WELD_M = 1e-6
GROUND_SQUARE_M = 0.05
GROUND = ((0.42, 0.40, 0.36), (0.36, 0.34, 0.31))
CUT_COLOUR = (0.85, 0.62, 0.48)
BACKGROUND = (0.035, 0.09, 0.11)
# Set layout along x (glTF metres): stone, branch, amphora; the fish swims 9 cm above the ground,
# 8 cm in front of the branch (Blender -y is the front).
SET_X = {
    generate_decor.STONE_ID: -0.215,
    generate_decor.BRANCH_ID: 0.0,
    generate_decor.AMPHORA_ID: 0.205,
}
FISH_X = 0.06
FISH_FRONT_M = 0.08
FISH_LIFT_M = 0.09
SHADOW_MAX_RES_M = 0.0002  # finer shadow maps: less terminator striping on the low-poly curves


def parse_args(argv: list[str]) -> argparse.Namespace:
    script_args = argv[argv.index("--") + 1 :] if "--" in argv else []
    parser = argparse.ArgumentParser(prog="render_decor_preview.py")
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--width", type=int, default=1600)
    parser.add_argument("--height", type=int, default=1000)
    return parser.parse_args(script_args)


def _to_gltf(p) -> tuple[float, float, float]:  # noqa: ANN001
    return (p[0], p[2], -p[1])


def _decor_material(bpy, atlas, uv_name: str, colour_name: str):  # noqa: ANN001, ANN202
    """Atlas cell through UV1 times mix(1, vertex colour, vertex_shade); the shade is the value
    of the node named ``vertex_shade``."""
    material = bpy.data.materials.new("preview_decor_palette")
    material.use_backface_culling = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    shader = nodes.get("Principled BSDF")
    shader.inputs["Roughness"].default_value = ROUGHNESS
    uv = nodes.new("ShaderNodeUVMap")
    uv.uv_map = uv_name
    image = nodes.new("ShaderNodeTexImage")
    image.image = atlas
    image.interpolation = "Closest"
    image.extension = "EXTEND"
    links.new(uv.outputs["UV"], image.inputs["Vector"])
    colour = nodes.new("ShaderNodeVertexColor")
    colour.layer_name = colour_name
    shade = nodes.new("ShaderNodeValue")
    shade.name = "vertex_shade"
    shade.outputs[0].default_value = 1.0
    blend = nodes.new("ShaderNodeMix")
    blend.data_type = "RGBA"
    blend.blend_type = "MIX"
    blend.inputs["A"].default_value = (1.0, 1.0, 1.0, 1.0)
    links.new(shade.outputs[0], blend.inputs["Factor"])
    links.new(colour.outputs["Color"], blend.inputs["B"])
    multiply = nodes.new("ShaderNodeMix")
    multiply.data_type = "RGBA"
    multiply.blend_type = "MULTIPLY"
    multiply.inputs["Factor"].default_value = 1.0
    links.new(image.outputs["Color"], multiply.inputs["A"])
    links.new(blend.outputs["Result"], multiply.inputs["B"])
    links.new(multiply.outputs["Result"], shader.inputs["Base Color"])
    return material


def _plain_material(bpy, name: str, rgb: tuple[float, float, float]):  # noqa: ANN001, ANN202
    material = bpy.data.materials.new(name)
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*rgb, 1.0)
    shader.inputs["Roughness"].default_value = 0.9
    return material


def _ground_material(bpy):  # noqa: ANN001, ANN202
    material = bpy.data.materials.new("preview_ground")
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    shader = nodes.get("Principled BSDF")
    shader.inputs["Roughness"].default_value = 0.95
    coords = nodes.new("ShaderNodeTexCoord")
    checker = nodes.new("ShaderNodeTexChecker")
    checker.inputs["Scale"].default_value = 0.5 / GROUND_SQUARE_M  # one square per 5 cm
    checker.inputs["Color1"].default_value = (*GROUND[0], 1.0)
    checker.inputs["Color2"].default_value = (*GROUND[1], 1.0)
    links.new(coords.outputs["Object"], checker.inputs["Vector"])
    links.new(checker.outputs["Color"], shader.inputs["Base Color"])
    return material


def _weld(bpy, obj):  # noqa: ANN001, ANN202
    import bmesh  # noqa: PLC0415 (only inside Blender)

    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=WELD_M)
    return bm


def _measure(bpy, item_id: str, obj) -> dict[str, object]:  # noqa: ANN001
    mesh = obj.data
    bm = _weld(bpy, obj)
    try:
        data = MeshData()
        data.vertices = [_to_gltf(v.co) for v in bm.verts]
        bm.verts.index_update()
        data.faces = [tuple(v.index for v in face.verts) for face in bm.faces]
        open_edges = sum(1 for e in bm.edges if not e.is_manifold or not e.is_contiguous)
    finally:
        bm.free()
    low, high = data.bounds()
    cm = generate_decor.CM
    result: dict[str, object] = {
        "triangles": sum(len(p.vertices) - 2 for p in mesh.polygons),
        "size_cm": [round((high[i] - low[i]) / cm, 3) for i in range(3)],
        "lowest_y_mm": round(low[1] * 1000.0, 3),
        "centre_xz_mm": [round((high[i] + low[i]) / 2.0 * 1000.0, 3) for i in (0, 2)],
        "uv_layers": [layer.name for layer in mesh.uv_layers],
        "colour_attributes": [attr.name for attr in mesh.color_attributes],
        "non_manifold_edges": open_edges,
        "parts": generate_decor.components(data),
        "volume_cm3": round(generate_decor.signed_volume(data) / cm**3, 1),
    }
    if item_id == generate_decor.STONE_ID:
        flat = [v for v in data.vertices if v[1] < 1e-6]
        for axis, key in ((0, "x"), (2, "z")):
            extent = max(v[axis] for v in flat) - min(v[axis] for v in flat)
            result[f"flat_underside_{key}_share"] = round(extent / (high[axis] - low[axis]), 3)
    if item_id == generate_decor.AMPHORA_ID:
        m = generate_decor.amphora_measurements(data)
        result["opening_cm"] = round(m["opening_cm"], 3)
        result["inside_depth_cm"] = round(m["inside_depth_cm"], 3)
    return result


def _import_item(bpy, item_id: str, atlas):  # noqa: ANN001, ANN202
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(ITEMS_DIR / "models" / f"{item_id}.glb"))
    added = [obj for obj in bpy.data.objects if obj not in before and obj.type == "MESH"]
    if len(added) != 1:
        raise RuntimeError(f"{item_id}: expected one mesh object, found {len(added)}")
    obj = added[0]
    mesh = obj.data
    if len(mesh.uv_layers) != 2 or not mesh.color_attributes:
        raise RuntimeError(f"{item_id}: expected 2 UV layers and a colour attribute")
    material = _decor_material(bpy, atlas, mesh.uv_layers[1].name, mesh.color_attributes[0].name)
    for slot in obj.material_slots:
        slot.material = material
    return obj, material


def _import_fish(bpy):  # noqa: ANN001, ANN202
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(FISH_GLB))
    fish = next(o for o in bpy.data.objects if o not in before and o.type == "MESH")
    atlas = bpy.data.images.load(str(FISH_ATLAS))
    mesh = fish.data
    for slot in fish.material_slots:
        slot.material = render_fish_preview._material(  # noqa: SLF001 (same tool family)
            bpy, slot.material.name, atlas, mesh.uv_layers[1].name, mesh.color_attributes[0].name
        )
    scale = FISH_LENGTH_CM / 100.0
    fish.scale = (scale, scale, scale)
    fish.rotation_mode = "XYZ"  # the glTF importer sets quaternions
    fish.rotation_euler = (0.0, 0.0, math.radians(90.0))  # swims towards +x, profile to the front
    return fish


def _world_bounds(bpy, objects: list):  # noqa: ANN001, ANN202
    from mathutils import Vector  # noqa: PLC0415

    bpy.context.view_layer.update()
    points = [o.matrix_world @ Vector(corner) for o in objects for corner in o.bound_box]
    low = [min(p[i] for p in points) for i in range(3)]
    high = [max(p[i] for p in points) for i in range(3)]
    return low, high


def _setup(bpy, args: argparse.Namespace):  # noqa: ANN001, ANN202
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = args.width
    scene.render.resolution_y = args.height
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "AgX"
    world = bpy.data.worlds.new("preview")
    background = world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (*BACKGROUND, 1.0)
    background.inputs["Strength"].default_value = 1.0
    scene.world = world
    lights = {}
    for name, rotation, energy, colour in (
        ("key", (35.0, 25.0, 20.0), 3.5, (1.0, 0.95, 0.9)),
        ("rim", (-60.0, 0.0, 200.0), 1.5, (0.75, 0.9, 1.0)),
        ("fill", (75.0, 0.0, 100.0), 0.8, (0.8, 0.85, 0.9)),
        ("under", (180.0, 0.0, 0.0), 2.5, (1.0, 0.97, 0.94)),
    ):
        data = bpy.data.lights.new(name, "SUN")
        data.energy = energy
        data.color = colour
        data.angle = math.radians(3.0)
        data.shadow_maximum_resolution = SHADOW_MAX_RES_M
        data.use_shadow_jitter = False
        light = bpy.data.objects.new(name, data)
        light.rotation_euler = tuple(math.radians(a) for a in rotation)
        scene.collection.objects.link(light)
        lights[name] = light
    lights["under"].hide_render = True
    camera_data = bpy.data.cameras.new("camera")
    camera_data.clip_start = 0.001
    camera_data.sensor_fit = "HORIZONTAL"
    camera = bpy.data.objects.new("camera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    bpy.ops.mesh.primitive_plane_add(size=2.0, location=(0.0, 0.0, 0.0))
    ground = bpy.context.active_object
    ground.name = "preview_ground"
    ground.data.materials.append(_ground_material(bpy))
    return scene, camera, ground, lights


def _render(bpy, scene, camera, path: Path, *, location, target, ortho: float | None) -> None:  # noqa: ANN001
    camera.location = location
    render_fish_preview._look_at(camera, target)  # noqa: SLF001
    if ortho is None:
        camera.data.type = "PERSP"
        camera.data.lens = 50.0
    else:
        camera.data.type = "ORTHO"
        camera.data.ortho_scale = ortho
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    if not path.is_file():
        raise RuntimeError(f"render wrote no file: {path}")
    print(f"{PROG}: wrote {path}")


def _ortho_fit(across: float, tall: float, aspect: float) -> float:
    return max(across * 1.35, tall * 1.35 * aspect)


def _set_shade(materials: list, value: float) -> None:
    for material in materials:
        material.node_tree.nodes["vertex_shade"].outputs[0].default_value = value


def _cut_half(bpy, obj, cap) -> None:  # noqa: ANN001
    """Remove the x > 0 half (Blender x = glTF x) and cap the cut with the plain cut material."""
    import bmesh  # noqa: PLC0415

    obj.data.materials.append(cap)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=WELD_M)
    geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
    bmesh.ops.bisect_plane(
        bm, geom=geom, dist=1e-7, plane_co=(0.0, 0.0, 0.0), plane_no=(1.0, 0.0, 0.0), clear_outer=True
    )
    before = set(bm.faces)
    bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary], sides=0)
    for face in bm.faces:
        if face not in before:
            face.material_index = len(obj.data.materials) - 1
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def run(argv: list[str]) -> None:
    import bpy  # noqa: PLC0415

    args = parse_args(argv)
    out_dir = args.out_dir.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    aspect = args.width / args.height
    scene, camera, ground, lights = _setup(bpy, args)
    atlas = bpy.data.images.load(str(ATLAS))
    items = {}
    measurements: dict[str, object] = {}
    for item_id in IDS:
        obj, material = _import_item(bpy, item_id, atlas)
        items[item_id] = (obj, material)
        measurements[item_id] = _measure(bpy, item_id, obj)
        print(f"{PROG}: {item_id} {json.dumps(measurements[item_id])}")
    (out_dir / "measurements.json").write_text(json.dumps(measurements, indent=2) + "\n", "utf-8")

    def show_only(visible: list) -> None:  # noqa: ANN001
        for obj, _material in items.values():
            obj.hide_render = obj not in visible

    # Single items, each at the origin (Blender: front -Y, up +Z).
    for item_id, (obj, material) in items.items():
        show_only([obj])
        low, high = _world_bounds(bpy, [obj])
        w, d, h = high[0] - low[0], high[1] - low[1], high[2] - low[2]
        mid = (0.0, 0.0, h / 2.0)
        far = 1.0
        ground.hide_render = True  # edge-on in the level orthographic views
        _render(bpy, scene, camera, out_dir / f"{item_id}_front.png",
                location=(0.0, -far, h / 2.0), target=mid, ortho=_ortho_fit(w, h, aspect))
        _render(bpy, scene, camera, out_dir / f"{item_id}_side.png",
                location=(far, 0.0, h / 2.0), target=mid, ortho=_ortho_fit(d, h, aspect))
        ground.hide_render = False
        camera.rotation_euler = (0.0, 0.0, 0.0)
        _render(bpy, scene, camera, out_dir / f"{item_id}_top.png",
                location=(0.0, -1e-4, far), target=(0.0, 0.0, 0.0), ortho=_ortho_fit(w, d, aspect))
        size = max(w, d, h)
        three = (size * 1.6, -size * 2.2, size * 1.3)
        for shade, suffix in ((1.0, ""), (0.0, "_vertex_shade_0")):
            _set_shade([material], shade)
            _render(bpy, scene, camera, out_dir / f"{item_id}_three_quarter{suffix}.png",
                    location=three, target=(0.0, 0.0, h * 0.4), ortho=None)
        _set_shade([material], 1.0)
        if item_id == generate_decor.STONE_ID:
            ground.hide_render = True
            lights["under"].hide_render = False
            _render(bpy, scene, camera, out_dir / "river_stone_underside.png",
                    location=(0.0, 1e-4, -far), target=(0.0, 0.0, 0.0), ortho=_ortho_fit(w, d, aspect))
            ground.hide_render = False
            lights["under"].hide_render = True
        if item_id == generate_decor.AMPHORA_ID:
            cut = obj.copy()
            cut.data = obj.data.copy()
            scene.collection.objects.link(cut)
            _cut_half(bpy, cut, _plain_material(bpy, "preview_cut", CUT_COLOUR))
            obj.hide_render = True
            _render(bpy, scene, camera, out_dir / "clay_amphora_cutaway.png",
                    location=(far, 0.0, h / 2.0), target=mid, ortho=_ortho_fit(d, h, aspect))
            bpy.data.objects.remove(cut, do_unlink=True)

    # The set at real size beside the 4 cm fish.
    show_only([obj for obj, _m in items.values()])
    for item_id, (obj, _material) in items.items():
        x = SET_X[item_id]
        obj.location = (x, 0.0, 0.0)
    fish = _import_fish(bpy)
    flow, fhigh = _world_bounds(bpy, [fish])
    fish.location = (FISH_X - (flow[0] + fhigh[0]) / 2.0, -FISH_FRONT_M, FISH_LIFT_M - flow[2])
    everything = [obj for obj, _m in items.values()] + [fish]
    low, high = _world_bounds(bpy, everything)
    w, h = high[0] - low[0], high[2] - low[2]
    cx = (low[0] + high[0]) / 2.0
    _render(bpy, scene, camera, out_dir / "set_front_4cm_fish.png",
            location=(cx, -1.0, h / 2.0), target=(cx, 0.0, h / 2.0), ortho=_ortho_fit(w, h, aspect) * 0.95)
    materials = [m for _o, m in items.values()]
    three = (cx + 0.32, -0.62, 0.36)
    _render(bpy, scene, camera, out_dir / "set_three_quarter_4cm_fish.png",
            location=three, target=(cx, 0.0, 0.03), ortho=None)
    _set_shade(materials, 0.0)
    _render(bpy, scene, camera, out_dir / "set_three_quarter_vertex_shade_0.png",
            location=three, target=(cx, 0.0, 0.03), ortho=None)


def main() -> int:
    try:
        run(sys.argv)
    except SystemExit as stop:
        return stop.code if isinstance(stop.code, int) else 1
    except BaseException as error:  # noqa: BLE001 (background Blender exits 0 otherwise)
        print(f"{PROG}: error: {type(error).__name__}: {error}", file=sys.stderr, flush=True)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
