class_name SubstrateAssembler
extends RefCounted
## Assembles the substrate bed of a tank from the committed baked data (ADR 0011 rule 9). Static
## and pure: the result depends only on the input and the baked data, never on the thread, the
## timing or the colour, so it may run on a worker thread (rule 10).
##
## Whole-tank data (pebbles): the baked stones are the bed. Tile data: the four panes use the
## ring sets rotated by 0, 90, 180 and 270 degrees (corner K, seams E, one fill F<k> per cell);
## the top lattice of 5 cm cells starts at the back left corner of the interior and holds one top
## tile I<k> per cell (a fill with the seam stones on its borders, so the tiles of any fills
## fit), translated only. No two edge-adjacent cells use the same fill. Stone types: the top
## stones go into the chunk buffers; ring stones win at the
## junction, a top stone that overlaps one is dropped. Sand: the top grains stay in shared tile
## buffers (one per fill for the inner cells, nine parts per fill for the cells at a pane, which
## leave out the parts inside the ring strip); the ring grains go into the chunk buffers.
##
## One seeded random number generator, used in a fixed order: ring fills per pane cell, top fills
## per cell, then four draws per stone for the tint (for every placed stone, in placement order).

## Changes whenever the output for the same input changes on purpose, including every re-bake.
const PACKING_VERSION: int = 1
const RECORD: int = SubstrateBakeData.FLOATS
const FLOATS: int = SubstrateBedData.FLOATS
## Stones between two looks at the cancel token inside a pass.
const CANCEL_STRIDE: int = 1024
const NO_CLIP: Rect2 = Rect2(-1000.0, -1000.0, 2000.0, 2000.0)
## Draw parts of a chunk buffer, in buffer order (SubstrateChunkData).
const DRAW_ABOVE: int = 0
const DRAW_SURFACE_BEHIND: int = 1
const DRAW_PANE: int = 2
const DRAW_PANE_BEHIND: int = 3
const DRAW_PARTS: int = 4
## Sand: the fills whose tiles are also kept in nine parts for the cells at a pane.
const BORDER_FILLS: int = 2
## Parts of a tile along one axis: inside the strip at the low border, the middle, the high one.
const PART_LOW: int = 0
const PART_MIDDLE: int = 1
const PART_HIGH: int = 2


## 32-bit FNV-1a over the UTF-8 bytes of "<tank_id>|<substrate_id>|<version>".
static func seed_for(
	tank_id: StringName, substrate_id: StringName, version: int = PACKING_VERSION
) -> int:
	var text: String = "%s|%s|%d" % [tank_id, substrate_id, version]
	var value: int = 2166136261
	for byte: int in text.to_utf8_buffer():
		value = ((value ^ byte) * 16777619) & 0xFFFFFFFF
	return value


## The bed of the input, or null when the token was cancelled or the depth of the input is not
## the depth the data was poured to.
static func assemble(
	input: SubstrateAssemblyInput, bake: SubstrateBakeData, cancel: SubstrateCancelToken = null
) -> SubstrateBedData:
	if input == null or bake == null or _stop(cancel):
		return null
	if absf(bake.depth_m() - input.depth()) > 1e-6:
		return null
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = input.seed
	var data: SubstrateBedData = SubstrateBedData.new()
	data.input = input
	data.median_size_m = bake.median_size()
	var size: Vector3 = input.interior_size_m
	var core_height: float = maxf(input.depth() - input.core_drop_m, 0.001)
	data.core_size = Vector3(
		size.x - 2.0 * input.core_inset_m, core_height, size.z - 2.0 * input.core_inset_m
	)
	data.core_centre = Vector3(0.0, core_height / 2.0, 0.0)
	var world: PackedFloat32Array = PackedFloat32Array()
	var is_sand: bool = input.grain_class == SubstrateBedLook.CLASS_SAND
	if bake.mode() == SubstrateBakeData.MODE_TANK:
		world = bake.get_set("tank")
	else:
		world = _place_ring(input, bake, rng)
		if _stop(cancel):
			return null
		var fills: PackedInt32Array = _pick_top_fills(input, bake, rng, is_sand)
		if is_sand:
			_build_sand_tiles(input, bake, rng, data, fills)
		else:
			world = _place_top(input, bake, world, data, fills)
		if _stop(cancel):
			return null
	if not _build_chunks(input, bake, world, rng, data, cancel):
		return null
	return data


static func _stop(cancel: SubstrateCancelToken) -> bool:
	return cancel != null and cancel.is_cancelled()


## An exact rotation about +y by a number of quarter turns.
static func _quarter(turns: int) -> Basis:
	match posmod(turns, 4):
		1:
			return Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0))
		2:
			return Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1))
		3:
			return Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0))
	return Basis.IDENTITY


# --- tiles: ring ---


## The ring stones of the four panes in the tank frame (9 floats per stone).
static func _place_ring(
	input: SubstrateAssemblyInput, bake: SubstrateBakeData, rng: RandomNumberGenerator
) -> PackedFloat32Array:
	var lx: float = input.interior_size_m.x
	var lz: float = input.interior_size_m.z
	var period: float = bake.tile_value("ring", "period_m")
	var depth: float = bake.tile_value("ring", "depth_m")
	var corner: float = bake.tile_value("ring", "corner_m", depth)
	var fills: int = maxi(1, int(bake.tile_value("ring", "fills", 1.0)))
	var corner_set: Vector2i = bake.set_range("K")
	var seam_set: Vector2i = bake.set_range("E")
	var fill_sets: Array[Vector2i] = []
	var largest: int = 0
	for k: int in fills:
		fill_sets.append(bake.set_range("F%d" % k))
		largest = maxi(largest, fill_sets[k].y)
	var cells: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
	var capacity: int = 0
	for face: int in 4:
		var length: float = lx if face % 2 == 0 else lz
		cells[face] = maxi(0, roundi((length - 2.0 * corner) / period))
		capacity += corner_set.y + (cells[face] + 1) * seam_set.y + cells[face] * largest
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(capacity * RECORD)
	var cursor: int = 0
	var origins: Array[Vector3] = [
		Vector3(-lx / 2.0, 0.0, lz / 2.0),
		Vector3(lx / 2.0, 0.0, lz / 2.0),
		Vector3(lx / 2.0, 0.0, -lz / 2.0),
		Vector3(-lx / 2.0, 0.0, -lz / 2.0),
	]
	for face: int in 4:
		var rot: Basis = _quarter(face)
		var origin: Vector3 = origins[face]
		cursor = _append(out, cursor, bake.stones, corner_set, rot, origin, Vector3.ZERO, NO_CLIP)
		for j: int in cells[face] + 1:
			var at: Vector3 = Vector3(corner + j * period, 0.0, 0.0)
			cursor = _append(out, cursor, bake.stones, seam_set, rot, origin, at, NO_CLIP)
		var previous: int = -1
		for j: int in cells[face]:
			var k: int = _pick(rng, fills, previous, -1)
			previous = k
			var at: Vector3 = Vector3(corner + j * period, 0.0, 0.0)
			cursor = _append(out, cursor, bake.stones, fill_sets[k], rot, origin, at, NO_CLIP)
	out.resize(cursor)
	return out


## A fill 0..count - 1 that differs from the two given ones (-1 = none), drawn with one random
## number.
static func _pick(rng: RandomNumberGenerator, count: int, avoid_a: int, avoid_b: int) -> int:
	var allowed: PackedInt32Array = PackedInt32Array()
	for k: int in count:
		if k != avoid_a and k != avoid_b:
			allowed.append(k)
	var draw: int = rng.randi()
	if allowed.is_empty():
		return draw % count
	return allowed[draw % allowed.size()]


## Appends the records `span` (first record, count) of `src`, moved by `offset` in the set frame,
## then rotated by `rot` and moved to `origin`. Stones whose centre (x, z) is outside `clip` are
## skipped. Returns the new cursor (in floats).
static func _append(
	out: PackedFloat32Array,
	cursor: int,
	src: PackedFloat32Array,
	span: Vector2i,
	rot: Basis,
	origin: Vector3,
	offset: Vector3,
	clip: Rect2
) -> int:
	var turned: bool = not rot.is_equal_approx(Basis.IDENTITY)
	var q: Quaternion = Quaternion(rot)
	var shift: Vector3 = origin + rot * offset
	var i: int = span.x * RECORD
	var end: int = (span.x + span.y) * RECORD
	while i < end:
		var p: Vector3 = Vector3(src[i], src[i + 1], src[i + 2])
		if turned:
			p = rot * p
		p += shift
		if clip.has_point(Vector2(p.x, p.z)):
			out[cursor] = p.x
			out[cursor + 1] = p.y
			out[cursor + 2] = p.z
			if turned:
				var sq: Quaternion = q * Quaternion(src[i + 3], src[i + 4], src[i + 5], src[i + 6])
				out[cursor + 3] = sq.x
				out[cursor + 4] = sq.y
				out[cursor + 5] = sq.z
				out[cursor + 6] = sq.w
			else:
				out[cursor + 3] = src[i + 3]
				out[cursor + 4] = src[i + 4]
				out[cursor + 5] = src[i + 5]
				out[cursor + 6] = src[i + 6]
			out[cursor + 7] = src[i + 7]
			out[cursor + 8] = src[i + 8]
			cursor += RECORD
		i += RECORD
	return cursor


# --- tiles: top ---


## Columns and rows of the top lattice.
static func _lattice(input: SubstrateAssemblyInput, bake: SubstrateBakeData) -> Vector2i:
	var period: float = bake.tile_value("top", "period_m")
	return Vector2i(
		maxi(1, roundi(input.interior_size_m.x / period)),
		maxi(1, roundi(input.interior_size_m.z / period))
	)


## The fill of every top cell (row-major, rows from the back pane), never the fill of an
## edge-adjacent cell. Sand: the cells at a pane alternate between the two border fills, an inner
## cell takes the border fill of its own colour or the last fill.
static func _pick_top_fills(
	input: SubstrateAssemblyInput,
	bake: SubstrateBakeData,
	rng: RandomNumberGenerator,
	is_sand: bool
) -> PackedInt32Array:
	var lattice: Vector2i = _lattice(input, bake)
	var count: int = maxi(1, int(bake.tile_value("top", "fills", 1.0)))
	var fills: PackedInt32Array = PackedInt32Array()
	fills.resize(lattice.x * lattice.y)
	for b: int in lattice.y:
		for a: int in lattice.x:
			var left: int = fills[b * lattice.x + a - 1] if a > 0 else -1
			var back: int = fills[(b - 1) * lattice.x + a] if b > 0 else -1
			var chosen: int = 0
			if is_sand and count > BORDER_FILLS:
				var own: int = (a + b) % BORDER_FILLS
				var at_pane: bool = a == 0 or b == 0 or a == lattice.x - 1 or b == lattice.y - 1
				var last: int = BORDER_FILLS + rng.randi() % (count - BORDER_FILLS)
				var free: bool = left < BORDER_FILLS and back < BORDER_FILLS
				chosen = last if not at_pane and free and rng.randf() < 0.5 else own
			else:
				chosen = _pick(rng, count, left, back)
			fills[b * lattice.x + a] = chosen
	return fills


## Stone types: adds the top stones of every cell to the ring stones and resolves the junction
## (ring stones win). Fills data.top_placements. Returns all stones in the tank frame.
static func _place_top(
	input: SubstrateAssemblyInput,
	bake: SubstrateBakeData,
	ring: PackedFloat32Array,
	data: SubstrateBedData,
	fills: PackedInt32Array
) -> PackedFloat32Array:
	var lx: float = input.interior_size_m.x
	var lz: float = input.interior_size_m.z
	var period: float = bake.tile_value("top", "period_m")
	var thickness: float = bake.tile_value("top", "thickness_m")
	var lift: float = bake.tile_value("top", "lift_m")
	var depth: float = bake.tile_value("ring", "depth_m")
	var lattice: Vector2i = _lattice(input, bake)
	var count: int = maxi(1, int(bake.tile_value("top", "fills", 1.0)))
	var fill_sets: Array[Vector2i] = []
	var largest: int = 0
	for k: int in count:
		fill_sets.append(bake.set_range("I%d" % k))
		largest = maxi(largest, fill_sets[k].y)
	var ring_floats: int = ring.size()
	var out: PackedFloat32Array = ring.duplicate()
	out.resize(ring_floats + lattice.x * lattice.y * largest * RECORD)
	var cursor: int = ring_floats
	var inset: float = depth - input.junction_overlap_m
	var clip: Rect2 = Rect2(
		-lx / 2.0 + inset, -lz / 2.0 + inset, lx - 2.0 * inset, lz - 2.0 * inset
	)
	var base_y: float = input.depth() - thickness + lift
	data.top_pitch_m = period
	data.top_placements.resize(lattice.x * lattice.y * SubstrateBedData.PLACEMENT_FLOATS)
	for b: int in lattice.y:
		for a: int in lattice.x:
			var cell: int = b * lattice.x + a
			var k: int = fills[cell]
			# a set covers x in [0, period) and z in (-period, 0] from its origin
			var origin: Vector3 = Vector3(
				-lx / 2.0 + a * period, base_y, -lz / 2.0 + (b + 1) * period
			)
			cursor = _append(
				out, cursor, bake.stones, fill_sets[k], Basis.IDENTITY, origin, Vector3.ZERO, clip
			)
			var at: int = cell * SubstrateBedData.PLACEMENT_FLOATS
			data.top_placements[at] = origin.x + period / 2.0
			data.top_placements[at + 1] = origin.z - period / 2.0
			data.top_placements[at + 2] = 0.0
			data.top_placements[at + 3] = 0.0
			# stone types: the tile index is the fill; the stones are in the chunk buffers
			data.top_placements[at + 4] = float(k)
	cursor = _resolve_junction(input, bake, out, ring_floats, cursor)
	out.resize(cursor)
	return out


## Drops the top stones (floats ring_floats..cursor of `out`) that overlap a ring stone near the
## inner edge of the ring. Returns the new cursor.
static func _resolve_junction(
	input: SubstrateAssemblyInput,
	bake: SubstrateBakeData,
	out: PackedFloat32Array,
	ring_floats: int,
	cursor: int
) -> int:
	var lx: float = input.interior_size_m.x
	var lz: float = input.interior_size_m.z
	var depth: float = bake.tile_value("ring", "depth_m")
	var max_size: float = bake.largest_size()
	var cell: float = max_size
	var low: float = input.depth() - bake.tile_value("top", "thickness_m") - max_size
	var grid: Dictionary[Vector2i, PackedInt32Array] = {}
	var i: int = 0
	while i < ring_floats:
		var x: float = out[i]
		var z: float = out[i + 2]
		var inward: float = minf(lx / 2.0 - absf(x), lz / 2.0 - absf(z))
		if inward > depth - 1.5 * max_size and out[i + 1] > low:
			var key: Vector2i = Vector2i(floori(x / cell), floori(z / cell))
			var members: PackedInt32Array = grid.get(key, PackedInt32Array())
			members.append(i)
			grid[key] = members
		i += RECORD
	var factor: float = input.junction_factor
	var write: int = ring_floats
	i = ring_floats
	while i < cursor:
		var x: float = out[i]
		var y: float = out[i + 1]
		var z: float = out[i + 2]
		var keep: bool = true
		var inward: float = minf(lx / 2.0 - absf(x), lz / 2.0 - absf(z))
		if inward < depth + max_size:
			var radius: float = out[i + 7]
			var kx: int = floori(x / cell)
			var kz: int = floori(z / cell)
			for dx: int in range(-1, 2):
				for dz: int in range(-1, 2):
					var key: Vector2i = Vector2i(kx + dx, kz + dz)
					if not keep or not grid.has(key):
						continue
					for r: int in grid[key]:
						var ddx: float = out[r] - x
						var ddy: float = out[r + 1] - y
						var ddz: float = out[r + 2] - z
						var limit: float = factor * (radius + out[r + 7])
						if ddx * ddx + ddy * ddy + ddz * ddz < limit * limit:
							keep = false
							break
		if keep:
			if write != i:
				for c: int in RECORD:
					out[write + c] = out[i + c]
			write += RECORD
		i += RECORD
	return write


## Sand: the shared top tile buffers and the placement of every cell. A tile holds the grains of
## the baked tile I<k> relative to the centre of the cell. The first tiles are the whole tiles of
## every fill (inner cells); then, for each border fill, nine parts: the strips and corners inside
## the ring strip at a border and the middle. A cell at a pane draws the parts that are not in the
## ring strip of its panes.
static func _build_sand_tiles(
	input: SubstrateAssemblyInput,
	bake: SubstrateBakeData,
	rng: RandomNumberGenerator,
	data: SubstrateBedData,
	fills: PackedInt32Array
) -> void:
	var lx: float = input.interior_size_m.x
	var lz: float = input.interior_size_m.z
	var period: float = bake.tile_value("top", "period_m")
	var base_y: float = (
		input.depth() - bake.tile_value("top", "thickness_m") + bake.tile_value("top", "lift_m")
	)
	var strip: float = bake.tile_value("ring", "depth_m") - input.junction_overlap_m
	var lattice: Vector2i = _lattice(input, bake)
	var count: int = maxi(1, int(bake.tile_value("top", "fills", 1.0)))
	var border_fills: int = mini(BORDER_FILLS, count)
	data.top_pitch_m = period
	data.top_y_range = Vector2(INF, -INF)
	for k: int in count:
		var whole: PackedFloat32Array = PackedFloat32Array()
		var parts: Array[PackedFloat32Array] = []
		if k < border_fills:
			for _part: int in 9:
				parts.append(PackedFloat32Array())
		# a tile covers x in [0, period) and z in (-period, 0] from its origin
		var span: Vector2i = bake.set_range("I%d" % k)
		for record: int in range(span.x, span.x + span.y):
			var o: int = record * RECORD
			var x: float = bake.stones[o]
			var z: float = bake.stones[o + 2]
			var r_light: float = rng.randf()
			var r_hue: float = rng.randf()
			var r_kind: float = rng.randf()
			var r_seed: float = rng.randf()
			var centre: Vector3 = Vector3(
				x - period / 2.0, bake.stones[o + 1] + base_y, z + period / 2.0
			)
			var reach: float = _write_instance(
				whole, input, bake, o, centre, r_light, r_hue, r_kind, r_seed
			)
			data.top_y_range.x = minf(data.top_y_range.x, centre.y - reach)
			data.top_y_range.y = maxf(data.top_y_range.y, centre.y + reach)
			if k < border_fills:
				var part: int = _part_of(x, period, strip) + 3 * _part_of(z + period, period, strip)
				_write_instance(parts[part], input, bake, o, centre, r_light, r_hue, r_kind, r_seed)
		data.top_tiles.append(whole)
		if k < border_fills:
			data.top_tiles.append_array(parts)
	if data.top_y_range.x > data.top_y_range.y:
		data.top_y_range = Vector2(base_y, input.depth())
	# placements: tile index of the whole tile of fill k, and of part p of border fill k
	var whole_index: PackedInt32Array = PackedInt32Array()
	var next: int = 0
	for k: int in count:
		whole_index.append(next)
		next += 10 if k < border_fills else 1
	for b: int in lattice.y:
		for a: int in lattice.x:
			var k: int = fills[b * lattice.x + a]
			var x: float = -lx / 2.0 + (a + 0.5) * period
			var z: float = -lz / 2.0 + (b + 0.5) * period
			var at_pane: bool = a == 0 or b == 0 or a == lattice.x - 1 or b == lattice.y - 1
			if not at_pane or k >= border_fills:
				_add_placement(data, x, z, whole_index[k])
				continue
			# the middle part last: it names the fill of the cell
			for order: int in 9:
				var part: int = (order + 5) % 9
				var px: int = part % 3
				var pz: int = part / 3
				if (px == PART_LOW and a == 0) or (px == PART_HIGH and a == lattice.x - 1):
					continue
				if (pz == PART_LOW and b == 0) or (pz == PART_HIGH and b == lattice.y - 1):
					continue
				_add_placement(data, x, z, whole_index[k] + 1 + part)


static func _part_of(value: float, period: float, strip: float) -> int:
	if value < strip:
		return PART_LOW
	if value >= period - strip:
		return PART_HIGH
	return PART_MIDDLE


static func _add_placement(data: SubstrateBedData, x: float, z: float, tile: int) -> void:
	data.top_placements.append(x)
	data.top_placements.append(z)
	data.top_placements.append(0.0)
	data.top_placements.append(0.0)
	data.top_placements.append(float(tile))


# --- instance buffers ---


## Appends one instance (16 floats) of baked record `o` (float offset in bake.stones) at
## `centre` to `buffer`. Returns the vertical reach of the instance above and below its centre.
static func _write_instance(
	buffer: PackedFloat32Array,
	input: SubstrateAssemblyInput,
	bake: SubstrateBakeData,
	o: int,
	centre: Vector3,
	r_light: float,
	r_hue: float,
	r_kind: float,
	r_seed: float
) -> float:
	var src: PackedFloat32Array = bake.stones
	var packed: int = int(src[o + 8])
	var basis: Basis = Basis(Quaternion(src[o + 3], src[o + 4], src[o + 5], src[o + 6]))
	var axes: Vector3 = bake.axes[packed & SubstrateBakeData.VARIANT_MASK] * src[o + 7]
	basis.x *= axes.x
	basis.y *= axes.y
	basis.z *= axes.z
	var w: int = buffer.size()
	buffer.resize(w + FLOATS)
	_store(buffer, w, basis, centre)
	var exposure: int = (
		(packed >> SubstrateBakeData.EXPOSURE_SHIFT) & SubstrateBakeData.EXPOSURE_MASK
	)
	_store_tint(buffer, w + 12, input, r_light, r_hue, r_kind, r_seed, exposure)
	return sqrt(basis.x.y * basis.x.y + basis.y.y * basis.y.y + basis.z.y * basis.z.y)


static func _store(buffer: PackedFloat32Array, w: int, basis: Basis, origin: Vector3) -> void:
	buffer[w] = basis.x.x
	buffer[w + 1] = basis.y.x
	buffer[w + 2] = basis.z.x
	buffer[w + 3] = origin.x
	buffer[w + 4] = basis.x.y
	buffer[w + 5] = basis.y.y
	buffer[w + 6] = basis.z.y
	buffer[w + 7] = origin.y
	buffer[w + 8] = basis.x.z
	buffer[w + 9] = basis.y.z
	buffer[w + 10] = basis.z.z
	buffer[w + 11] = origin.z


## The custom data of an instance: lightness factor, hue shift in turns, saturation plus
## 4 x exposure, random 0..1 (Story Scope 9; the look gives the spreads).
static func _store_tint(
	buffer: PackedFloat32Array,
	w: int,
	input: SubstrateAssemblyInput,
	r_light: float,
	r_hue: float,
	r_kind: float,
	r_seed: float,
	exposure: int
) -> void:
	var hue_spread: float = input.tone_hue_deg / 360.0
	var lightness: float = 1.0 + (r_light * 2.0 - 1.0) * input.tone_lightness
	var hue: float = (r_hue * 2.0 - 1.0) * hue_spread
	var saturation: float = 1.0 + (r_seed * 2.0 - 1.0) * input.tone_saturation
	var outliers: float = input.tone_outlier_share
	if r_kind < outliers:
		# mixed-rock outliers: near-white quartz, dark grey, rusty brown
		var which: float = r_kind / outliers
		if which < 0.4:
			lightness = 1.55 + r_light * 0.3
			saturation = 0.25
		elif which < 0.75:
			lightness = 0.42 + r_light * 0.15
			saturation = 0.3
		else:
			lightness = 0.85 + r_light * 0.2
			saturation = 1.7
			hue = -minf(0.02, hue_spread)
	elif r_kind > 1.0 - input.tone_glint_share:
		lightness = input.tone_glint_gain * (1.0 + 0.04 * r_light)
		saturation = 0.6
	elif r_kind < outliers + input.tone_dark_share:
		lightness = 0.68 + r_light * 0.1
	buffer[w] = lightness
	buffer[w + 1] = hue
	# z carries the saturation (below 4) and the baked exposure in steps of 4
	buffer[w + 2] = clampf(saturation, 0.0, 2.0) + 4.0 * float(exposure)
	buffer[w + 3] = r_seed


## Sorts the stones of `world` (tank frame, 9 floats each) into the chunk buffers of `data`, in
## the draw order of SubstrateChunkData (seen from above, kept behind away from the glass, seen
## only through a pane, kept behind at the glass). False when the token was cancelled.
static func _build_chunks(
	input: SubstrateAssemblyInput,
	bake: SubstrateBakeData,
	world: PackedFloat32Array,
	rng: RandomNumberGenerator,
	data: SubstrateBedData,
	cancel: SubstrateCancelToken
) -> bool:
	var lx: float = input.interior_size_m.x
	var lz: float = input.interior_size_m.z
	var is_sand: bool = input.grain_class == SubstrateBedLook.CLASS_SAND
	var variants: int = 1 if is_sand else maxi(1, bake.variant_count())
	var chunk: float = maxf(input.chunk_size_m, 0.005)
	var nx: int = maxi(1, ceili(lx / chunk - 1e-6))
	var nz: int = maxi(1, ceili(lz / chunk - 1e-6))
	var cx: float = lx / nx
	var cz: float = lz / nz
	var slots: int = nx * nz * variants
	var count: int = world.size() / RECORD
	var reach_of: PackedFloat32Array = PackedFloat32Array()
	for v: int in bake.variant_count():
		reach_of.append(0.5 if is_sand else bake.half_extents[v].length())
	# a stone kept behind belongs to the glass when its near side is this close to a pane
	var glass_keep: float = bake.tile_value("keep", "glass_keep_m")
	# pass 1: the chunk, variant and draw class of every stone
	var class_counts: PackedInt32Array = PackedInt32Array()
	class_counts.resize(slots * DRAW_PARTS)
	var panes: PackedInt32Array = PackedInt32Array()
	panes.resize(nx * nz)
	var slot_of: PackedInt32Array = PackedInt32Array()
	slot_of.resize(count)
	var draw_of: PackedByteArray = PackedByteArray()
	draw_of.resize(count)
	for i: int in count:
		if i % CANCEL_STRIDE == 0 and _stop(cancel):
			return false
		var o: int = i * RECORD
		var packed: int = int(world[o + 8])
		var v: int = packed & SubstrateBakeData.VARIANT_MASK
		var ix: int = clampi(int((world[o] + lx * 0.5) / cx), 0, nx - 1)
		var iz: int = clampi(int((world[o + 2] + lz * 0.5) / cz), 0, nz - 1)
		var slot: int = (iz * nx + ix) * variants + (0 if is_sand else mini(v, variants - 1))
		var to_glass: float = (
			minf(lx * 0.5 - absf(world[o]), lz * 0.5 - absf(world[o + 2]))
			- reach_of[v] * world[o + 7]
		)
		var draw: int = _draw_part(packed, to_glass <= glass_keep)
		if draw == DRAW_PANE or draw == DRAW_PANE_BEHIND:
			panes[iz * nx + ix] |= _nearest_pane(world[o], world[o + 2], lx, lz)
		slot_of[i] = slot
		draw_of[i] = draw
		class_counts[slot * DRAW_PARTS + draw] += 1
	var buffers: Array[PackedFloat32Array] = []
	buffers.resize(slots)
	var cursors: PackedInt32Array = PackedInt32Array()
	cursors.resize(slots * DRAW_PARTS)
	for s: int in slots:
		var total: int = 0
		for draw: int in DRAW_PARTS:
			cursors[s * DRAW_PARTS + draw] = total
			total += class_counts[s * DRAW_PARTS + draw]
		var buffer: PackedFloat32Array = PackedFloat32Array()
		buffer.resize(total * FLOATS)
		buffers[s] = buffer
	var lows: PackedVector3Array = PackedVector3Array()
	var highs: PackedVector3Array = PackedVector3Array()
	lows.resize(nx * nz)
	highs.resize(nx * nz)
	lows.fill(Vector3(INF, INF, INF))
	highs.fill(Vector3(-INF, -INF, -INF))
	# pass 2: transforms and tint data; the random numbers are drawn for every stone
	for i: int in count:
		if i % CANCEL_STRIDE == 0 and _stop(cancel):
			return false
		var r_light: float = rng.randf()
		var r_hue: float = rng.randf()
		var r_kind: float = rng.randf()
		var r_seed: float = rng.randf()
		var o: int = i * RECORD
		var slot: int = slot_of[i]
		var size: float = world[o + 7]
		var packed: int = int(world[o + 8])
		var v: int = packed & SubstrateBakeData.VARIANT_MASK
		var basis: Basis = Basis(Quaternion(world[o + 3], world[o + 4], world[o + 5], world[o + 6]))
		if is_sand:
			var axes: Vector3 = bake.axes[v] * size
			basis.x *= axes.x
			basis.y *= axes.y
			basis.z *= axes.z
		else:
			basis = basis.scaled_local(Vector3(size, size, size))
		var origin: Vector3 = Vector3(world[o], world[o + 1], world[o + 2])
		var buffer: PackedFloat32Array = buffers[slot]
		var cursor: int = slot * DRAW_PARTS + draw_of[i]
		var w: int = cursors[cursor] * FLOATS
		cursors[cursor] += 1
		_store(buffer, w, basis, origin)
		var exposure: int = (
			(packed >> SubstrateBakeData.EXPOSURE_SHIFT) & SubstrateBakeData.EXPOSURE_MASK
		)
		_store_tint(buffer, w + 12, input, r_light, r_hue, r_kind, r_seed, exposure)
		var column: int = slot / variants
		var reach: Vector3 = Vector3.ONE * (reach_of[v] * size)
		lows[column] = lows[column].min(origin - reach)
		highs[column] = highs[column].max(origin + reach)
	for iz: int in nz:
		for ix: int in nx:
			var column: int = iz * nx + ix
			var total: int = 0
			for v: int in variants:
				total += buffers[column * variants + v].size() / FLOATS
			if total == 0:
				continue
			if _stop(cancel):
				return false
			var entry: SubstrateChunkData = SubstrateChunkData.new()
			entry.key = Vector2i(ix, iz)
			entry.aabb = AABB(lows[column], highs[column] - lows[column])
			entry.panes = panes[column]
			for v: int in variants:
				var s: int = column * variants + v
				entry.buffers.append(buffers[s])
				entry.counts.append(buffers[s].size() / FLOATS)
				var end: int = 0
				for draw: int in SubstrateChunkData.ENDS:
					end += class_counts[s * DRAW_PARTS + draw]
					entry.ends.append(end)
			data.chunks.append(entry)
	return true


## The draw part of a stone (SubstrateChunkData): 0 seen from above, 1 kept behind away from the
## glass (under the surface), 2 seen only through a pane, 3 kept behind at the glass.
static func _draw_part(packed: int, at_glass: bool) -> int:
	if (packed & SubstrateBakeData.FLAG_ABOVE) != 0:
		return DRAW_ABOVE
	if (packed & SubstrateBakeData.FLAG_PANE) != 0:
		return DRAW_PANE
	if at_glass:
		return DRAW_PANE_BEHIND
	return DRAW_SURFACE_BEHIND


## The pane bit (SubstrateChunkData) of the glass nearest to a point of the floor.
static func _nearest_pane(x: float, z: float, lx: float, lz: float) -> int:
	var to_x: float = lx / 2.0 - absf(x)
	var to_z: float = lz / 2.0 - absf(z)
	if to_z <= to_x:
		return SubstrateChunkData.PANE_FRONT if z > 0.0 else SubstrateChunkData.PANE_BACK
	return SubstrateChunkData.PANE_RIGHT if x > 0.0 else SubstrateChunkData.PANE_LEFT
