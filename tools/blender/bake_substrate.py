"""Bakes the physically settled stone data of the substrate bed (#28, ADR 0011 rules 7 and 8).

    blender --background --python tools/blender/bake_substrate.py -- --type <type> \
        [--tank <tank_id>] [--out game/assets/substrate/bake] [--seed 28] \
        [--work <cache dir>] [--part ring|top|tank]

Types (params/substrate_bake.json): gravel_natural, gravel_coloured, sand_fine (its data set
"sand" is shared by sand_fine and sand_black) and pebbles_river (one bake per tank, --tank
tank_small_1 | tank_medium_1 | tank_large_1; the interior comes from params/tank_<id>.json).

Modes:
- "tank":  the whole bed of one tank is poured in layers against the four glass walls
           (pebbles: a few thousand stones, so no tiles and no repetition).
- "tiles": reusable tiles, see substrate_tiles.py (gravel, coloured gravel, sand positions).

Steps: build the stone bodies (substrate_stones.py, same seed as the glb meshes), pour and settle
them (substrate_sim.py, substrate_tiles.py), run the visibility pass (substrate_visibility.py)
and write `<data set>.bin`. A bake takes minutes; it never runs in CI or in a test. With --work
the settled stones of each part are cached there, and --part pours only that part into the
cache (so the parts of one type can run in parallel processes); a later run without --part
reads the cache and writes the file.

File format (little-endian): 4 bytes magic "CASB", u32 format version, u32 byte length of the
UTF-8 JSON header, the header, then records of 9 float32: x, y, z, qx, qy, qz, qw, drawn size,
packed integer (bits 0 to 3 variant, bit 4 visible from above, bit 5 visible through a pane,
bit 6 kept behind, bits 7 to 10 exposure 0..15). Godot frame, metres, set-local (see
substrate_visibility.py). Only stones with at least one flag are written.

The functions above `bake` need the standard library only (tools/blender/test_bake_substrate.py);
numpy and bpy are imported inside the bake.
"""

from __future__ import annotations

import hashlib
import json
import random
import struct
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import blender_common  # noqa: E402
from blender_common import GeneratorError  # noqa: E402

PARAMS_PATH = HERE / "params" / "substrate_bake.json"
DEFAULT_OUT = HERE.parents[1] / "game" / "assets" / "substrate" / "bake"
DEFAULT_SEED = 28

MAGIC = b"CASB"
FORMAT_VERSION = 1
# Must equal SubstrateAssembler.PACKING_VERSION (game/scenes/tank/substrate/): it changes with
# every re-bake that changes the data.
PACKING_VERSION = 1
FLOATS = 9
RECORD_BYTES = FLOATS * 4
PREAMBLE = struct.Struct("<4sII")

VARIANT_MASK = 15
FLAG_ABOVE = 16
FLAG_PANE = 32
FLAG_BEHIND = 64
EXPOSURE_SHIFT = 7
EXPOSURE_MAX = 15
FLAG_BITS = FLAG_ABOVE | FLAG_PANE | FLAG_BEHIND

MODES = ("tank", "tiles")
STONE_CLASSES = ("angular", "round", "pebble", "sand")
TANK_IDS = ("tank_small_1", "tank_medium_1", "tank_large_1")
MIN_TOP_TILE_M = 0.05
MAX_LIFT_M = 0.003


# --- packed flags ---


def pack_flags(variant: int, above: bool, pane: bool, behind: bool, exposure: int) -> int:
    """The packed integer of a record (stored as a float32, exact up to 2^24)."""
    if not 0 <= variant <= VARIANT_MASK:
        raise ValueError(f"variant {variant} is outside 0..{VARIANT_MASK}")
    if not 0 <= exposure <= EXPOSURE_MAX:
        raise ValueError(f"exposure {exposure} is outside 0..{EXPOSURE_MAX}")
    packed = variant
    if above:
        packed |= FLAG_ABOVE
    if pane:
        packed |= FLAG_PANE
    if behind:
        packed |= FLAG_BEHIND
    return packed | (exposure << EXPOSURE_SHIFT)


def unpack_flags(packed: int) -> dict:
    return {
        "variant": packed & VARIANT_MASK,
        "above": bool(packed & FLAG_ABOVE),
        "pane": bool(packed & FLAG_PANE),
        "behind": bool(packed & FLAG_BEHIND),
        "exposure": (packed >> EXPOSURE_SHIFT) & EXPOSURE_MAX,
    }


# --- drawn sizes ---


def sample_size(rng: random.Random, classes: list) -> float:
    """One drawn size in metres from the size classes [low, high, share]."""
    r = rng.random()
    acc = 0.0
    for lo, hi, share in classes:
        acc += share
        if r <= acc:
            return rng.uniform(lo, hi)
    lo, hi, _share = classes[-1]
    return rng.uniform(lo, hi)


def size_statistics(classes: list) -> dict:
    """Smallest, median and largest drawn size of the size classes (uniform inside a class)."""
    smallest = min(lo for lo, _hi, _share in classes)
    largest = max(hi for _lo, hi, _share in classes)
    acc = 0.0
    median = largest
    for lo, hi, share in sorted(classes):
        if acc + share >= 0.5:
            median = lo + (hi - lo) * (0.5 - acc) / share
            break
        acc += share
    return {"smallest_m": smallest, "median_m": median, "largest_m": largest}


# --- parameters ---


def _number(table: dict, key: str, where: str, low: float, high: float) -> float:
    if key not in table:
        raise GeneratorError(f"parameter {where}.{key}: missing")
    value = table[key]
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise GeneratorError(f"parameter {where}.{key}: must be a number, got {value!r}")
    if not low <= value <= high:
        raise GeneratorError(f"parameter {where}.{key}: {value!r} is outside {low} .. {high}")
    return float(value)


def check_type(name: str, params: dict) -> None:
    """Validates the parameters of one type; a GeneratorError names the offending key."""
    for key in ("class", "mode", "data_set", "fill_depth_m", "overfill_m", "size_classes",
                "sim_scale", "height_cell_m", "pour", "physics", "keep"):
        if key not in params:
            raise GeneratorError(f"parameter {name}.{key}: missing")
    if params["class"] not in STONE_CLASSES:
        raise GeneratorError(f"parameter {name}.class: must be one of {STONE_CLASSES}")
    if params["mode"] not in MODES:
        raise GeneratorError(f"parameter {name}.mode: must be one of {MODES}")
    _number(params, "fill_depth_m", name, 0.03, 0.2)
    _number(params, "overfill_m", name, -0.02, 0.02)
    _number(params, "sim_scale", name, 1.0, 5000.0)
    classes = params["size_classes"]
    if not isinstance(classes, list) or not classes:
        raise GeneratorError(f"parameter {name}.size_classes: must be a non-empty list")
    total = 0.0
    for entry in classes:
        if not isinstance(entry, list) or len(entry) != 3:
            raise GeneratorError(f"parameter {name}.size_classes: each class is [low, high, share]")
        lo, hi, share = entry
        if not 0.0 < lo < hi or not 0.0 < share <= 1.0:
            raise GeneratorError(f"parameter {name}.size_classes: bad class {entry!r}")
        total += share
    if abs(total - 1.0) > 1e-6:
        raise GeneratorError(f"parameter {name}.size_classes: the shares add up to {total}, not 1")
    stats = size_statistics(classes)
    _number(params["keep"], "crop_above_m", f"{name}.keep", 0.0, 0.05)
    if params["mode"] == "tiles":
        for part in ("ring", "top"):
            if part not in params:
                raise GeneratorError(f"parameter {name}.{part}: missing")
        ring = params["ring"]
        _number(ring, "period_m", f"{name}.ring", 0.005, 0.5)
        depth = _number(ring, "depth_m", f"{name}.ring", 0.001, 0.2)
        if depth < 2.0 * stats["median_m"]:
            raise GeneratorError(
                f"parameter {name}.ring.depth_m: the shell must be at least two median stones deep"
            )
        if ring.get("corner_m", depth) < depth:
            raise GeneratorError(f"parameter {name}.ring.corner_m: must be at least depth_m")
        top = params["top"]
        _number(top, "period_m", f"{name}.top", MIN_TOP_TILE_M, 0.5)
        _number(top, "thickness_m", f"{name}.top", 0.001, params["fill_depth_m"])
        for part in (ring, top):
            fills = part.get("fills", 0)
            if isinstance(fills, bool) or not isinstance(fills, int) or fills < 1:
                raise GeneratorError(f"parameter {name}: fills must be a whole number above 0")
        if top["fills"] < 3:
            raise GeneratorError(
                f"parameter {name}.top.fills: at least 3, so neighbours never repeat a tile"
            )


def load_params(path: Path = PARAMS_PATH) -> dict:
    """All types of the parameter file, validated. Keys starting with "_" are comments."""
    data = blender_common.load_json_object(path)
    types = {key: value for key, value in data.items() if not key.startswith("_")}
    if not types:
        raise GeneratorError(f"parameter file has no type: {path}")
    for name, params in types.items():
        if not isinstance(params, dict):
            raise GeneratorError(f"parameter {name}: must be an object")
        check_type(name, params)
    return types


def tank_interior(tank_id: str) -> tuple[float, float]:
    """Interior length (x) and depth (z) of a tank in metres, from its generator parameters."""
    if tank_id not in TANK_IDS:
        raise GeneratorError(f"--tank must be one of {', '.join(TANK_IDS)}, got {tank_id!r}")
    data = blender_common.load_json_object(HERE / "params" / f"{tank_id}.json")
    return float(data["interior_length_m"]), float(data["interior_depth_m"])


def data_set_name(params: dict, tank_id: str) -> str:
    """File name (without .bin) of a data set: pebbles get one file per tank."""
    if params["mode"] == "tank":
        if not tank_id:
            raise GeneratorError("a whole-tank bake needs --tank <tank_id>")
        return f"{params['data_set']}_{tank_id}"
    if tank_id:
        raise GeneratorError("--tank is only for a whole-tank bake (pebbles)")
    return str(params["data_set"])


def bake_command(type_name: str, tank_id: str, seed: int) -> str:
    """The documented command that makes a data set (recorded in the header)."""
    command = f"blender --background --python tools/blender/bake_substrate.py -- --type {type_name}"
    if tank_id:
        command += f" --tank {tank_id}"
    if seed != DEFAULT_SEED:
        command += f" --seed {seed}"
    return command + " --out game/assets/substrate/bake"


# --- file ---


def encode(header: dict, records: bytes) -> bytes:
    """The bytes of a data file: preamble, JSON header, records."""
    if len(records) % RECORD_BYTES != 0:
        raise ValueError("the records are not a multiple of 36 bytes")
    text = json.dumps(header, separators=(",", ":"), sort_keys=True).encode("utf-8")
    return PREAMBLE.pack(MAGIC, FORMAT_VERSION, len(text)) + text + records


def decode(data: bytes) -> tuple[dict, list[tuple[float, ...]]]:
    """Header and records (tuples of 9 floats) of the bytes of a data file."""
    if len(data) < PREAMBLE.size:
        raise ValueError("shorter than the preamble")
    magic, version, length = PREAMBLE.unpack_from(data, 0)
    if magic != MAGIC:
        raise ValueError(f"wrong magic {magic!r}")
    if version != FORMAT_VERSION:
        raise ValueError(f"format version {version}, this reader knows {FORMAT_VERSION}")
    start = PREAMBLE.size + length
    if start > len(data) or (len(data) - start) % RECORD_BYTES != 0:
        raise ValueError("the header length or the record block is broken")
    header = json.loads(data[PREAMBLE.size : start].decode("utf-8"))
    count = (len(data) - start) // RECORD_BYTES
    values = struct.unpack_from(f"<{count * FLOATS}f", data, start)
    records = [tuple(values[i * FLOATS : (i + 1) * FLOATS]) for i in range(count)]
    return header, records


def build_header(
    type_name: str,
    params: dict,
    tank_id: str,
    seed: int,
    blender_version: str,
    shapes: dict,
    sets: dict[str, dict],
    settling: dict,
    statistics: dict,
) -> dict:
    """The JSON header of a data set. `shapes`: half_extents and axes per variant (Godot frame)
    and lod_triangles; `sets`: name -> {"offset", "count"} in records."""
    stats = size_statistics(params["size_classes"])
    header = {
        "format": FORMAT_VERSION,
        "packing_version": PACKING_VERSION,
        "floats": FLOATS,
        "type": type_name,
        "data_set": data_set_name(params, tank_id),
        "class": params["class"],
        "mode": params["mode"],
        "tank_id": tank_id,
        "fill_depth": params["fill_depth_m"],
        "size_classes": params["size_classes"],
        "smallest_size_m": stats["smallest_m"],
        "median_size_m": stats["median_m"],
        "largest_size_m": stats["largest_m"],
        "half_extents": shapes["half_extents"],
        "axes": shapes["axes"],
        "lod_triangles": shapes["lod_triangles"],
        "keep": params["keep"],
        "sets": sets,
        "blender_version": blender_version,
        "seed": seed,
        "commands": [
            "blender --background --python tools/blender/substrate_stones.py -- --seed %d" % seed,
            bake_command(type_name, tank_id, seed),
        ],
        "settling": settling,
        "statistics": statistics,
    }
    if params["mode"] == "tiles":
        ring = params["ring"]
        top = params["top"]
        header["ring"] = {
            "period_m": ring["period_m"],
            "depth_m": ring["depth_m"],
            "corner_m": ring.get("corner_m", ring["depth_m"]),
            "fills": ring["fills"],
        }
        header["top"] = {
            "period_m": top["period_m"],
            "thickness_m": top["thickness_m"],
            "seam_half_m": top["seam_half_m"],
            "fills": top["fills"],
            "lift_m": top.get("lift_m", 0.0),
        }
    return header


def merge_settling(reports: list[dict]) -> dict:
    """One settling report for the whole data set from the reports of its parts."""
    return {
        "all_at_rest": all(bool(r["all_at_rest"]) for r in reports),
        "largest_final_speed_m_per_s": max(r["largest_final_speed_m_per_s"] for r in reports),
        "rest_speed_limit_m_per_s": max(r["rest_speed_limit_m_per_s"] for r in reports),
        "removed_while_moving": sum(r["removed_while_moving"] for r in reports),
        "batches": sum(r["batches"] for r in reports),
        "frames": sum(r["frames"] for r in reports),
        "sim_seconds": round(sum(r.get("sim_seconds", 0.0) for r in reports), 1),
    }


# --- the bake (inside Blender) ---


def parse_args(argv: list[str]):  # noqa: ANN201
    import argparse  # noqa: PLC0415

    parser = argparse.ArgumentParser(prog="bake_substrate.py")
    parser.add_argument("--type", required=True)
    parser.add_argument("--tank", default="")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED)
    parser.add_argument("--work", type=Path, default=None)
    parser.add_argument("--part", default="")
    return parser.parse_args(blender_common.script_args(argv))


def _part_key(type_name: str, params: dict, part: str, seed: int, tank: str) -> str:
    after_pour = ("keep", "visibility", "data_set", "seam_trim_share")
    relevant = {k: v for k, v in params.items() if k not in after_pour}
    if part == "ring":
        relevant.pop("top", None)
    elif part == "top":
        relevant.pop("ring", None)
        # placing the settled layer is not part of the pour
        relevant["top"] = {
            k: v for k, v in params["top"].items() if k not in ("lift_m", "surface_bias_m")
        }
    text = json.dumps([type_name, part, seed, tank, relevant], sort_keys=True)
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]


def _stones_to_godot(rows):  # noqa: ANN001, ANN202 (numpy)
    """Blender-frame stone rows to float32 Godot rows: x, y, z, qx, qy, qz, qw, size, variant."""
    import numpy as np  # noqa: PLC0415

    out = np.empty((len(rows), FLOATS), dtype=np.float32)
    out[:, 0] = rows[:, 0]
    out[:, 1] = rows[:, 2]
    out[:, 2] = -rows[:, 1]
    out[:, 3] = rows[:, 4]
    out[:, 4] = rows[:, 6]
    out[:, 5] = -rows[:, 5]
    out[:, 6] = rows[:, 3]
    out[:, 7] = rows[:, 7]
    out[:, 8] = rows[:, 8]
    return out


def _pour_part(args, params: dict, part: str, built: list, log) -> tuple[dict, dict]:  # noqa: ANN001
    """Pours one part; returns (settling report, sets in the Blender frame)."""
    import numpy as np  # noqa: PLC0415

    import substrate_sim as sim  # noqa: PLC0415

    variants = sim.Variants(built)
    sim_args = {"type": args.type, "seed": args.seed}
    if part != "tank":
        import substrate_tiles as tiles  # noqa: PLC0415

        return tiles.bake_part(sim_args, params, variants, part, log)
    lx, lz = tank_interior(args.tank)
    physics = params["physics"]
    world = sim.SimWorld(variants, params["sim_scale"], physics)
    t = 0.05
    top = params["fill_depth_m"] + 0.5
    gf = physics.get("glass_friction", 0.3)
    world.set_walls(
        [
            ((0, 0, -t), (lx / 2 + t, lz / 2 + t, t), gf),
            ((-lx / 2 - t, 0, top / 2), (t, lz / 2 + t, top / 2 + t), gf),
            ((lx / 2 + t, 0, top / 2), (t, lz / 2 + t, top / 2 + t), gf),
            ((0, -lz / 2 - t, top / 2), (lx / 2 + t, t, top / 2 + t), gf),
            ((0, lz / 2 + t, top / 2), (lx / 2 + t, t, top / 2 + t), gf),
        ]
    )
    region = sim.Region(-lx / 2, lx / 2, -lz / 2, lz / 2, 0.0, params["height_cell_m"])
    rng = random.Random(f"{args.type}|tank|{lx}|{lz}|{args.seed}")
    target = params["fill_depth_m"] + params["overfill_m"]
    # stones lean on the glass: within `width_m` of a pane a stone falls with the gravity tilted
    # towards that pane (in a corner towards both)
    strength = float(params.get("lean", {}).get("strength", 0.0))
    width = float(params.get("lean", {}).get("width_m", 0.0))

    def lean(x: float, y: float) -> tuple[float, float]:
        tilt_x = strength if x > lx / 2 - width else (-strength if x < -lx / 2 + width else 0.0)
        tilt_y = strength if y > lz / 2 - width else (-strength if y < -lz / 2 + width else 0.0)
        return (tilt_x, tilt_y)

    placed = sim.pour(
        world, region, np.zeros((0, sim.STONE_COLS)), target, params["size_classes"], rng,
        params["pour"], log, lean if strength > 0.0 else None,
    )
    report = world.settling_report()
    report["sim_seconds"] = round(world.sim_seconds, 1)
    return report, {"tank": placed}


def _load_or_pour(args, params: dict, part: str, built: list, log) -> tuple[dict, dict]:  # noqa: ANN001
    import numpy as np  # noqa: PLC0415

    key = _part_key(args.type, params, part, args.seed, args.tank)
    name = data_set_name(params, args.tank)
    cache = None if args.work is None else args.work / f"{name}.{part}.{key}.npz"
    if cache is not None and cache.is_file() and args.part == "":
        with np.load(cache, allow_pickle=False) as stored:
            report = json.loads(str(stored["__report__"]))
            sets = {k: stored[k] for k in stored.files if k != "__report__"}
        log(f"{name}.{part}: read {sum(len(v) for v in sets.values())} stones from {cache.name}")
        return report, sets
    report, sets = _pour_part(args, params, part, built, log)
    if cache is not None:
        args.work.mkdir(parents=True, exist_ok=True)
        np.savez(cache, __report__=np.array(json.dumps(report)), **sets)
        log(f"{name}.{part}: cached in {cache.name}")
    return report, sets


def bake(argv: list[str]) -> None:
    import bpy  # noqa: PLC0415
    import numpy as np  # noqa: PLC0415

    import substrate_stones as stones  # noqa: PLC0415
    import substrate_visibility as visibility  # noqa: PLC0415

    args = parse_args(argv)
    all_params = load_params()
    if args.type not in all_params:
        raise GeneratorError(f"--type must be one of {', '.join(all_params)}, got {args.type!r}")
    params = all_params[args.type]
    name = data_set_name(params, args.tank)
    parts = ("tank",) if params["mode"] == "tank" else ("ring", "top")
    if args.part and args.part not in parts:
        raise GeneratorError(f"--part must be one of {', '.join(parts)} for {args.type}")
    if args.part and args.work is None:
        raise GeneratorError("--part pours into the cache only: it needs --work <dir>")
    t0 = time.time()

    def log(message: str) -> None:
        print(message, flush=True)

    built = stones.build_class(params["class"], args.seed)
    log(f"{name}: {len(built)} variants, LOD triangles {[lod['triangles'] for lod in built[0]['lods']]}")
    reports = []
    blender_sets: dict[str, np.ndarray] = {}
    for part in parts:
        if args.part and part != args.part:
            continue
        report, sets = _load_or_pour(args, params, part, built, log)
        reports.append(report)
        blender_sets.update(sets)
    if args.part:
        log(f"{name}.{args.part}: poured in {time.time() - t0:.1f} s (cache only, no data file)")
        return

    shapes = visibility.Shapes(
        [stones.to_godot(v["lods"][0]["verts"]) for v in built],
        [v["lods"][0]["tris"] for v in built],
        np.array([stones.godot_vector(v["axes"]) for v in built]),
        params["class"] == "sand",
    )
    if params["mode"] == "tiles":
        import substrate_tiles as tiles  # noqa: PLC0415

        log(f"{name}: stones on top of an earlier set dropped: {tiles.trim_overlaps(blender_sets, params)}")
    godot_sets = {k: _stones_to_godot(v) for k, v in blender_sets.items()}
    run = visibility.Pass(params, shapes, log)
    if params["mode"] == "tank":
        lx, lz = tank_interior(args.tank)
        written = run.run_tank(godot_sets["tank"], lx, lz)
        order = ["tank"]
    else:
        written = run.run_ring(godot_sets)
        written.update(run.run_top(godot_sets))
        ring_fills = params["ring"]["fills"]
        top_fills = params["top"]["fills"]
        order = ["K", "E"] + [f"F{k}" for k in range(ring_fills)]
        order += [f"I{k}" for k in range(top_fills)]
        if "lift_m" not in params["top"]:
            # the settled top layer is placed so that its measured mean surface is the fill depth
            # (plus surface_bias_m, a share of the tolerance, so more stone tops reach it)
            wanted = params["fill_depth_m"] + params["top"].get("surface_bias_m", 0.0)
            lift = wanted - run.report["top_field"]["mean_mm"] / 1000.0
            if abs(lift) > MAX_LIFT_M:
                raise GeneratorError(
                    f"the top layer of {name} ends {lift * 1000:.2f} mm from the fill depth: "
                    "change top.overfill_m and bake again"
                )
            params["top"]["lift_m"] = round(lift, 6)
        run.lift_top(written, params["top"]["lift_m"])
    table: dict[str, dict] = {}
    blocks = []
    offset = 0
    for set_name in order:
        stones_out, flags, exposure = written[set_name]
        if len(stones_out) == 0:
            continue
        records = stones_out.astype(np.float32).copy()
        variant = records[:, 8].astype(np.int32) & VARIANT_MASK
        packed = (
            variant
            + FLAG_ABOVE * ((flags & visibility.ABOVE) > 0)
            + FLAG_PANE * ((flags & visibility.PANE) > 0)
            + FLAG_BEHIND * ((flags & visibility.BEHIND) > 0)
            + (exposure.astype(np.int32) << EXPOSURE_SHIFT)
        )
        records[:, 8] = packed.astype(np.float32)
        table[set_name] = {"offset": offset, "count": int(len(records))}
        blocks.append(records)
        offset += len(records)
    data = np.concatenate(blocks).astype("<f4")
    statistics = {"sets": run.statistics, "surface": run.report, "records": int(len(data))}
    header = build_header(
        args.type,
        params,
        args.tank,
        args.seed,
        bpy.app.version_string,
        {
            "half_extents": [stones.godot_vector(v["half_extents"]) for v in built],
            "axes": [stones.godot_vector(v["axes"]) for v in built],
            "lod_triangles": [[int(lod["triangles"]) for lod in v["lods"]] for v in built],
        },
        table,
        merge_settling(reports),
        statistics,
    )
    args.out.mkdir(parents=True, exist_ok=True)

    def write(path: Path) -> None:
        path.write_bytes(encode(header, data.tobytes()))

    blender_common.write_group(args.out, [(f"{name}.bin", write, MAGIC)])
    log(f"{name}: surface {json.dumps(run.report)}")
    log(f"{name}: sets {json.dumps(run.statistics)}")
    log(
        f"{name}: {len(data)} records, {len(data) * RECORD_BYTES / 1024:.0f} KB, "
        f"settling {json.dumps(header['settling'])}, {time.time() - t0:.1f} s -> {args.out}"
    )


if __name__ == "__main__":
    sys.exit(blender_common.main("bake_substrate.py", bake))
