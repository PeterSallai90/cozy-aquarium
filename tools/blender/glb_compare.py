"""Compare and measure generated .glb files with the Python standard library only (#21).

Local helper for the [script] checks of criterion 10; CI does not run it.

Usage:
    python tools/blender/glb_compare.py same A.glb B.glb
        Exit 0 when the files are byte-identical, or else when their glTF JSON (without
        asset.generator) and their binary chunks are equal.
    python tools/blender/glb_compare.py extent FILE.glb --material body --axis y
        Print the extent of the POSITION accessor (its min and max) of every primitive that uses
        the named material, merged, along the axis. Exit 0 when such a primitive exists.
    python tools/blender/glb_compare.py info FILE.glb
        Print the meshes, primitives, attributes and materials.
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

GLB_MAGIC = b"glTF"
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942
AXES = {"x": 0, "y": 1, "z": 2}


class GlbError(Exception):
    pass


def read_glb(path: Path) -> tuple[dict, bytes]:
    """Returns the glTF JSON and the binary chunk of a .glb file."""
    data = path.read_bytes()
    if len(data) < 20 or data[:4] != GLB_MAGIC:
        raise GlbError(f"not a .glb file: {path}")
    _, _, length = struct.unpack_from("<4sII", data, 0)
    if length != len(data):
        raise GlbError(f"truncated .glb file: {path}")
    offset = 12
    document: dict | None = None
    binary = b""
    while offset < length:
        size, kind = struct.unpack_from("<II", data, offset)
        payload = data[offset + 8 : offset + 8 + size]
        if kind == CHUNK_JSON:
            document = json.loads(payload.decode("utf-8"))
        elif kind == CHUNK_BIN:
            binary = payload
        offset += 8 + size
    if document is None:
        raise GlbError(f"no JSON chunk: {path}")
    return document, binary


def same(first: Path, second: Path) -> tuple[bool, str]:
    if first.read_bytes() == second.read_bytes():
        return True, "byte-identical"
    doc_a, bin_a = read_glb(first)
    doc_b, bin_b = read_glb(second)
    for doc in (doc_a, doc_b):
        doc.get("asset", {}).pop("generator", None)
    if doc_a != doc_b:
        return False, "glTF JSON differs (asset.generator ignored)"
    if bin_a != bin_b:
        return False, "binary buffer differs"
    return True, "equal JSON (asset.generator ignored) and equal binary buffer"


def extent(path: Path, material: str, axis: str) -> float:
    document, _ = read_glb(path)
    names = [entry.get("name", "") for entry in document.get("materials", [])]
    low = float("inf")
    high = float("-inf")
    found = False
    for mesh in document.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            index = primitive.get("material")
            if index is None or names[index] != material:
                continue
            accessor = document["accessors"][primitive["attributes"]["POSITION"]]
            low = min(low, accessor["min"][AXES[axis]])
            high = max(high, accessor["max"][AXES[axis]])
            found = True
    if not found:
        raise GlbError(f"no primitive uses material {material!r}: {path}")
    return high - low


def info(path: Path) -> str:
    document, binary = read_glb(path)
    lines = [f"generator: {document.get('asset', {}).get('generator')}", f"bin: {len(binary)}"]
    for material in document.get("materials", []):
        lines.append(f"material {material.get('name')}: doubleSided={material.get('doubleSided', False)}")
    for mesh in document.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            attributes = sorted(primitive.get("attributes", {}))
            lines.append(f"mesh {mesh.get('name')}: material={primitive.get('material')} {attributes}")
    for node in document.get("nodes", []):
        lines.append(f"node {node.get('name')}: {sorted(set(node) - {'name', 'mesh'})}")
    return "\n".join(lines)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="glb_compare.py", description=__doc__.split("\n")[0])
    commands = parser.add_subparsers(dest="command", required=True)
    same_parser = commands.add_parser("same")
    same_parser.add_argument("first", type=Path)
    same_parser.add_argument("second", type=Path)
    extent_parser = commands.add_parser("extent")
    extent_parser.add_argument("file", type=Path)
    extent_parser.add_argument("--material", required=True)
    extent_parser.add_argument("--axis", choices=sorted(AXES), required=True)
    info_parser = commands.add_parser("info")
    info_parser.add_argument("file", type=Path)
    args = parser.parse_args(argv)
    try:
        if args.command == "same":
            equal, reason = same(args.first, args.second)
            print(("same: " if equal else "different: ") + reason)
            return 0 if equal else 1
        if args.command == "extent":
            print(f"{extent(args.file, args.material, args.axis):.6f}")
            return 0
        print(info(args.file))
        return 0
    except (OSError, GlbError, KeyError, ValueError) as error:
        print(f"glb_compare: error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
