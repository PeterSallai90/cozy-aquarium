extends RefCounted
## Geometry of an assembled substrate bed for the #28 tests: pure maths on arrays, no scene, no
## production class. A bed is read as "entries" (an instance buffer, the mesh variant it uses and
## the transform of its tile placement). From the entries the helper builds one analysis (a bounding
## box per stone and the top height field per 5 mm cell) and the checks of the plan read it:
## mean top height and top edge (AC 14, 24), glass contact and shell (AC 27, 39), top coverage
## (AC 28), tile seams and orientation (AC 40), sizes (AC 30) and tint data (AC 31).
##
## Conventions (see substrate_bed_api.gd): tank-local metres, floor at y = 0, front glass at +z,
## 16 floats per instance (12 transform floats in the MultiMesh layout, 4 custom floats). A mesh
## stone is the LOD0 mesh of its variant under the instance transform; a sand grain is an
## ellipsoid, the unit sphere under the instance transform (analytic top, centre y plus the length
## of the y row of the basis). Footprints are the xz bounding rectangle of a stone (an ellipse for
## sand), the plan's own definition (technical plan 1.9). The conventions of the mirror flag and of
## the rotation sense of a tile placement do not matter here: every statistic below is symmetric
## under the eight square symmetries.

const CELL_M: float = 0.005
const FLOATS: int = 16
const CUSTOM_AT: int = 12
const GLASS_REACH_M: float = 0.001
const EPS: float = 1e-5

const FRONT: int = 0
const BACK: int = 1
const LEFT: int = 2
const RIGHT: int = 3
const FACES: Array[int] = [FRONT, BACK, LEFT, RIGHT]
const FACE_NAMES: Array[String] = ["front", "back", "left", "right"]
## Bounding box record: min x, y, z then max x, y, z.
const BBOX_FLOATS: int = 6


## The transform of instance `index` of a 16-float buffer.
static func instance_transform(buffer: PackedFloat32Array, index: int) -> Transform3D:
	var b: int = index * FLOATS
	return Transform3D(
		Basis(
			Vector3(buffer[b], buffer[b + 4], buffer[b + 8]),
			Vector3(buffer[b + 1], buffer[b + 5], buffer[b + 9]),
			Vector3(buffer[b + 2], buffer[b + 6], buffer[b + 10])
		),
		Vector3(buffer[b + 3], buffer[b + 7], buffer[b + 11])
	)


## The transform of a tile placement: optional mirror (x flipped), quarter turns about +y, then the
## cell centre (x, z).
static func tile_offset(x: float, z: float, turns: int, mirror: int) -> Transform3D:
	var basis: Basis = Basis(Vector3.UP, float(turns) * PI / 2.0)
	if mirror != 0:
		basis = basis * Basis.from_scale(Vector3(-1.0, 1.0, 1.0))
	return Transform3D(basis, Vector3(x, 0.0, z))


## The instance buffers of a bed with the transform each is placed with: every chunk buffer once,
## and every tile buffer once per placement.
static func entries_of(data: RefCounted) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var chunks: Array = data.get("chunks")
	for chunk: RefCounted in chunks:
		var buffers: Array = chunk.get("buffers")
		for variant: int in buffers.size():
			var buffer: PackedFloat32Array = buffers[variant]
			if buffer.size() >= FLOATS:
				result.append(
					{"buffer": buffer, "variant": variant, "offset": Transform3D.IDENTITY}
				)
	var tiles: Array = data.get("top_tiles")
	var placements: PackedFloat32Array = data.get("top_placements")
	if tiles.is_empty():
		return result
	for cell: int in placements.size() / 5:
		var at: int = cell * 5
		var tile_index: int = int(placements[at + 4])
		if tile_index < 0 or tile_index >= tiles.size():
			continue
		result.append(
			{
				"buffer": tiles[tile_index],
				"variant": -1,
				"offset":
				tile_offset(
					placements[at],
					placements[at + 1],
					int(placements[at + 2]),
					int(placements[at + 3])
				)
			}
		)
	return result


static func instance_count(entries: Array[Dictionary]) -> int:
	var total: int = 0
	for entry: Dictionary in entries:
		total += (entry["buffer"] as PackedFloat32Array).size() / FLOATS
	return total


## Half extents of the ellipsoid (unit sphere under `basis`) on the three world axes.
static func ellipsoid_half_extents(basis: Basis) -> Vector3:
	return Vector3(
		Vector3(basis.x.x, basis.y.x, basis.z.x).length(),
		Vector3(basis.x.y, basis.y.y, basis.z.y).length(),
		Vector3(basis.x.z, basis.y.z, basis.z.z).length()
	)


## The point of the ellipsoid furthest along the world direction `normal` (unit length).
static func ellipsoid_extreme_point(transform: Transform3D, normal: Vector3) -> Vector3:
	var basis: Basis = transform.basis
	var along: Vector3 = Vector3(basis.x.dot(normal), basis.y.dot(normal), basis.z.dot(normal))
	var length: float = along.length()
	if length < 1e-12:
		return transform.origin
	return transform.origin + basis * (along / length)


## The analysis of a bed: a bounding box per stone, the field of the highest point per 5 mm cell
## (the core top inside the core footprint, 0 elsewhere), the overall minimum and maximum.
## `lod0` holds the LOD0 vertices of every mesh variant (empty for sand).
static func analyse(
	entries: Array[Dictionary],
	lod0: Array[PackedVector3Array],
	interior: Vector3,
	core_centre: Vector3,
	core_size: Vector3,
	is_sand: bool
) -> Dictionary:
	var nx: int = roundi(interior.x / CELL_M)
	var nz: int = roundi(interior.z / CELL_M)
	var half_x: float = interior.x / 2.0
	var half_z: float = interior.z / 2.0
	var field: PackedFloat32Array = PackedFloat32Array()
	field.resize(nx * nz)
	var core_top: float = core_centre.y + core_size.y / 2.0
	for iz: int in nz:
		var z: float = -half_z + (float(iz) + 0.5) * CELL_M
		for ix: int in nx:
			var x: float = -half_x + (float(ix) + 0.5) * CELL_M
			if (
				absf(x - core_centre.x) <= core_size.x / 2.0
				and absf(z - core_centre.z) <= core_size.z / 2.0
			):
				field[iz * nx + ix] = core_top
	var bbox: PackedFloat32Array = PackedFloat32Array()
	bbox.resize(instance_count(entries) * BBOX_FLOATS)
	var lowest: Vector3 = Vector3(INF, INF, INF)
	var highest: Vector3 = Vector3(-INF, -INF, -INF)
	var written: int = 0
	for entry: Dictionary in entries:
		var buffer: PackedFloat32Array = entry["buffer"]
		var offset: Transform3D = entry["offset"]
		var variant: int = entry["variant"]
		for index: int in buffer.size() / FLOATS:
			var t: Transform3D = offset * instance_transform(buffer, index)
			var low: Vector3 = Vector3(INF, INF, INF)
			var high: Vector3 = Vector3(-INF, -INF, -INF)
			if is_sand:
				var half: Vector3 = ellipsoid_half_extents(t.basis)
				low = t.origin - half
				high = t.origin + half
				var top: Vector3 = ellipsoid_extreme_point(t, Vector3.UP)
				_raise(field, nx, nz, half_x, half_z, top)
			else:
				var vertices: PackedVector3Array = lod0[variant]
				for vertex: Vector3 in vertices:
					var p: Vector3 = t * vertex
					low = low.min(p)
					high = high.max(p)
					_raise(field, nx, nz, half_x, half_z, p)
			var at: int = written * BBOX_FLOATS
			bbox[at] = low.x
			bbox[at + 1] = low.y
			bbox[at + 2] = low.z
			bbox[at + 3] = high.x
			bbox[at + 4] = high.y
			bbox[at + 5] = high.z
			lowest = lowest.min(low)
			highest = highest.max(high)
			written += 1
	return {
		"count": written,
		"bbox": bbox,
		"field": field,
		"nx": nx,
		"nz": nz,
		"min": lowest,
		"max": highest,
		"interior": interior,
		"core_centre": core_centre,
		"core_size": core_size,
	}


static func _raise(
	field: PackedFloat32Array, nx: int, nz: int, half_x: float, half_z: float, p: Vector3
) -> void:
	var ix: int = clampi(int((p.x + half_x) / CELL_M), 0, nx - 1)
	var iz: int = clampi(int((p.z + half_z) / CELL_M), 0, nz - 1)
	var at: int = iz * nx + ix
	if p.y > field[at]:
		field[at] = p.y


# --- surfaces (AC 14, 24, 27) ---


## The mean of the top height field over the interior.
static func mean_top(analysis: Dictionary) -> float:
	var field: PackedFloat32Array = analysis["field"]
	var total: float = 0.0
	for value: float in field:
		total += value
	return total / maxf(1.0, float(field.size()))


## The top height field along one glass face: the row or column of cells touching the pane.
static func edge_heights(analysis: Dictionary, face: int) -> PackedFloat32Array:
	var field: PackedFloat32Array = analysis["field"]
	var nx: int = analysis["nx"]
	var nz: int = analysis["nz"]
	var result: PackedFloat32Array = PackedFloat32Array()
	match face:
		FRONT:
			for ix: int in nx:
				result.append(field[(nz - 1) * nx + ix])
		BACK:
			for ix: int in nx:
				result.append(field[ix])
		LEFT:
			for iz: int in nz:
				result.append(field[iz * nx])
		RIGHT:
			for iz: int in nz:
				result.append(field[iz * nx + nx - 1])
	return result


static func mean_of(values: PackedFloat32Array) -> float:
	var total: float = 0.0
	for value: float in values:
		total += value
	return total / maxf(1.0, float(values.size()))


static func peak_to_peak(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var low: float = values[0]
	var high: float = values[0]
	for value: float in values:
		low = minf(low, value)
		high = maxf(high, value)
	return high - low


static func max_of(values: PackedFloat32Array) -> float:
	var high: float = -INF
	for value: float in values:
		high = maxf(high, value)
	return high


## The most distant point of any stone towards the pane, as a coordinate along the face normal.
static func shell_extreme(analysis: Dictionary, face: int) -> float:
	var low: Vector3 = analysis["min"]
	var high: Vector3 = analysis["max"]
	match face:
		FRONT:
			return high.z
		BACK:
			return low.z
		LEFT:
			return low.x
	return high.x


## The coordinate of the inner glass plane of a face.
static func plane_of(interior: Vector3, face: int) -> float:
	match face:
		FRONT:
			return interior.z / 2.0
		BACK:
			return -interior.z / 2.0
		LEFT:
			return -interior.x / 2.0
	return interior.x / 2.0


## +1 when the pane lies at the positive end of its axis, else -1.
static func face_sign(face: int) -> float:
	return 1.0 if face == FRONT or face == RIGHT else -1.0


## The axis (0 = x, 2 = z) of the face normal.
static func normal_axis(face: int) -> int:
	return 2 if face == FRONT or face == BACK else 0


## Distance from a stone's nearest point to the pane (negative when it pokes through).
static func stone_depth(
	bbox: PackedFloat32Array, index: int, interior: Vector3, face: int
) -> float:
	var at: int = index * BBOX_FLOATS
	var axis: int = normal_axis(face)
	var sign_value: float = face_sign(face)
	var extreme: float = bbox[at + 3 + axis] if sign_value > 0.0 else bbox[at + axis]
	return (plane_of(interior, face) - extreme) * sign_value


## Distance from the pane to the wall of the core box facing it.
static func core_wall_distance(analysis: Dictionary, face: int) -> float:
	var interior: Vector3 = analysis["interior"]
	var centre: Vector3 = analysis["core_centre"]
	var size: Vector3 = analysis["core_size"]
	var axis: int = normal_axis(face)
	var sign_value: float = face_sign(face)
	var wall: float = centre[axis] + sign_value * size[axis] / 2.0
	return (plane_of(interior, face) - wall) * sign_value


# --- painting (coverage grids) ---


## Marks the cells of a cols x rows grid (origin = lower corner of cell 0) whose centres lie in the
## rectangle lo..hi, or in the ellipse inscribed in it. At least the cell of the centre is marked.
static func paint(
	grid: PackedByteArray,
	cols: int,
	rows: int,
	cell: float,
	origin: Vector2,
	lo: Vector2,
	hi: Vector2,
	ellipse: bool
) -> void:
	var c0: int = clampi(int(floor((lo.x - origin.x) / cell)), 0, cols - 1)
	var c1: int = clampi(int(floor((hi.x - origin.x) / cell)), 0, cols - 1)
	var r0: int = clampi(int(floor((lo.y - origin.y) / cell)), 0, rows - 1)
	var r1: int = clampi(int(floor((hi.y - origin.y) / cell)), 0, rows - 1)
	var centre: Vector2 = (lo + hi) / 2.0
	var half: Vector2 = ((hi - lo) / 2.0).max(Vector2(1e-9, 1e-9))
	var painted: bool = false
	for r: int in range(r0, r1 + 1):
		var py: float = origin.y + (float(r) + 0.5) * cell
		for c: int in range(c0, c1 + 1):
			var px: float = origin.x + (float(c) + 0.5) * cell
			var inside: bool = true
			if ellipse:
				var dx: float = (px - centre.x) / half.x
				var dy: float = (py - centre.y) / half.y
				inside = dx * dx + dy * dy <= 1.0
			if inside:
				grid[r * cols + c] = 1
				painted = true
	if not painted:
		var cc: int = clampi(int(floor((centre.x - origin.x) / cell)), 0, cols - 1)
		var cr: int = clampi(int(floor((centre.y - origin.y) / cell)), 0, rows - 1)
		grid[cr * cols + cc] = 1


static func covered_fraction(grid: PackedByteArray) -> float:
	var total: int = 0
	for value: int in grid:
		total += value
	return float(total) / maxf(1.0, float(grid.size()))


## The (u, v) corners of a stone on a face: u along the pane, v up.
static func _face_rect(bbox: PackedFloat32Array, index: int, face: int) -> Array[Vector2]:
	var at: int = index * BBOX_FLOATS
	var u_axis: int = 0 if normal_axis(face) == 2 else 2
	return [
		Vector2(bbox[at + u_axis], bbox[at + 1]),
		Vector2(bbox[at + 3 + u_axis], bbox[at + 4]),
	]


## The share of the face cells (cell size `cell`, from the floor to the height `band_top`) that
## hold a stone whose outer point lies within 1 mm of the glass plane (AC 27).
static func glass_contact_share(
	analysis: Dictionary, face: int, cell: float, band_top: float
) -> float:
	var interior: Vector3 = analysis["interior"]
	var bbox: PackedFloat32Array = analysis["bbox"]
	var u_length: float = interior.x if normal_axis(face) == 2 else interior.z
	var cols: int = ceili(u_length / cell - 1e-6)
	var rows: int = ceili(band_top / cell - 1e-6)
	var grid: PackedByteArray = PackedByteArray()
	grid.resize(cols * rows)
	var origin: Vector2 = Vector2(-u_length / 2.0, 0.0)
	for index: int in int(analysis["count"]):
		var depth: float = stone_depth(bbox, index, interior, face)
		if depth > GLASS_REACH_M or depth < -EPS:
			continue
		var rect: Array[Vector2] = _face_rect(bbox, index, face)
		paint(grid, cols, rows, cell, origin, rect[0], rect[1], true)
	return covered_fraction(grid)


## The share of the 5 mm grid points of a face (floor to `band_top`) whose perpendicular ray from
## the pane meets a stone before the wall of the core (AC 39). A stone is met when its silhouette
## (the ellipse inscribed in its bounding rectangle) contains the point and its nearest point lies
## in front of the core wall.
static func ray_stone_share(analysis: Dictionary, face: int, step: float, band_top: float) -> float:
	var interior: Vector3 = analysis["interior"]
	var bbox: PackedFloat32Array = analysis["bbox"]
	var wall: float = core_wall_distance(analysis, face)
	var u_length: float = interior.x if normal_axis(face) == 2 else interior.z
	var cols: int = ceili(u_length / step - 1e-6)
	var rows: int = ceili(band_top / step - 1e-6)
	var grid: PackedByteArray = PackedByteArray()
	grid.resize(cols * rows)
	var origin: Vector2 = Vector2(-u_length / 2.0, 0.0)
	for index: int in int(analysis["count"]):
		if stone_depth(bbox, index, interior, face) >= wall:
			continue
		var rect: Array[Vector2] = _face_rect(bbox, index, face)
		paint(grid, cols, rows, step, origin, rect[0], rect[1], true)
	return covered_fraction(grid)


## Top coverage (AC 28): the stones whose top reaches at least `flat_depth - t_mean` are painted as
## footprints on a grid of `cell` over the interior. Returns the covered share and the number of
## k x k windows of cells without a covered cell, k = ceil(2 x largest / cell) + 1.
static func top_coverage(
	analysis: Dictionary,
	flat_depth: float,
	t_mean: float,
	cell: float,
	largest: float,
	ellipse: bool
) -> Dictionary:
	var interior: Vector3 = analysis["interior"]
	var bbox: PackedFloat32Array = analysis["bbox"]
	var cols: int = ceili(interior.x / cell - 1e-6)
	var rows: int = ceili(interior.z / cell - 1e-6)
	var grid: PackedByteArray = PackedByteArray()
	grid.resize(cols * rows)
	var origin: Vector2 = Vector2(-interior.x / 2.0, -interior.z / 2.0)
	for index: int in int(analysis["count"]):
		var at: int = index * BBOX_FLOATS
		if bbox[at + 4] < flat_depth - t_mean:
			continue
		paint(
			grid,
			cols,
			rows,
			cell,
			origin,
			Vector2(bbox[at], bbox[at + 2]),
			Vector2(bbox[at + 3], bbox[at + 5]),
			ellipse
		)
	var k: int = ceili(2.0 * largest / cell) + 1
	return {
		"share": covered_fraction(grid),
		"empty_windows": empty_windows(grid, cols, rows, k),
		"k": k,
		"cols": cols,
		"rows": rows,
	}


## The number of k x k windows of the grid in which no cell is covered (integral image).
static func empty_windows(grid: PackedByteArray, cols: int, rows: int, k: int) -> int:
	if k > cols or k > rows:
		return 0
	var sums: PackedInt32Array = PackedInt32Array()
	sums.resize((cols + 1) * (rows + 1))
	for r: int in rows:
		var running: int = 0
		for c: int in cols:
			running += grid[r * cols + c]
			sums[(r + 1) * (cols + 1) + c + 1] = sums[r * (cols + 1) + c + 1] + running
	var empty: int = 0
	for r: int in range(0, rows - k + 1):
		for c: int in range(0, cols - k + 1):
			var inside: int = (
				sums[(r + k) * (cols + 1) + c + k]
				- sums[r * (cols + 1) + c + k]
				- sums[(r + k) * (cols + 1) + c]
				+ sums[r * (cols + 1) + c]
			)
			if inside == 0:
				empty += 1
	return empty


# --- sizes and tint (AC 30, 31) ---


## The longest extent of a vertex set.
static func longest_extent(vertices: PackedVector3Array) -> float:
	if vertices.is_empty():
		return 0.0
	var low: Vector3 = vertices[0]
	var high: Vector3 = vertices[0]
	for vertex: Vector3 in vertices:
		low = low.min(vertex)
		high = high.max(vertex)
	var size: Vector3 = high - low
	return maxf(size.x, maxf(size.y, size.z))


## The index of the axis (0, 1, 2) along which a vertex set is longest.
static func longest_axis(vertices: PackedVector3Array) -> int:
	if vertices.is_empty():
		return 0
	var low: Vector3 = vertices[0]
	var high: Vector3 = vertices[0]
	for vertex: Vector3 in vertices:
		low = low.min(vertex)
		high = high.max(vertex)
	return (high - low).max_axis_index()


## The unique instance buffers of a bed: every chunk buffer and every tile buffer once, each with
## the mesh variant it uses (-1 for tile buffers, which only sand uses without a variant).
static func unique_buffers(data: RefCounted) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var chunks: Array = data.get("chunks")
	for chunk: RefCounted in chunks:
		var buffers: Array = chunk.get("buffers")
		for variant: int in buffers.size():
			var buffer: PackedFloat32Array = buffers[variant]
			if buffer.size() >= FLOATS:
				result.append({"buffer": buffer, "variant": variant})
	var tiles: Array = data.get("top_tiles")
	for tile: PackedFloat32Array in tiles:
		if tile.size() >= FLOATS:
			result.append({"buffer": tile, "variant": -1})
	return result


## The drawn size of every unique instance in metres: the mesh extent of its variant (1.0 for
## sand, whose grain is a unit sphere with radius 1, so twice the longest column) times the longest
## basis column. `extents` holds the longest extent of the LOD0 mesh per variant.
static func drawn_sizes(
	buffers: Array[Dictionary], extents: PackedFloat32Array, is_sand: bool
) -> PackedFloat32Array:
	var sizes: PackedFloat32Array = PackedFloat32Array()
	for entry: Dictionary in buffers:
		var buffer: PackedFloat32Array = entry["buffer"]
		var variant: int = entry["variant"]
		var unit: float = 2.0 if is_sand else extents[maxi(variant, 0)]
		for index: int in buffer.size() / FLOATS:
			var basis: Basis = instance_transform(buffer, index).basis
			var longest: float = maxf(basis.x.length(), maxf(basis.y.length(), basis.z.length()))
			sizes.append(unit * longest)
	return sizes


## The custom floats (4 per instance) of every unique instance.
static func custom_data(buffers: Array[Dictionary]) -> PackedFloat32Array:
	var result: PackedFloat32Array = PackedFloat32Array()
	for entry: Dictionary in buffers:
		var buffer: PackedFloat32Array = entry["buffer"]
		for index: int in buffer.size() / FLOATS:
			var at: int = index * FLOATS + CUSTOM_AT
			result.append(buffer[at])
			result.append(buffer[at + 1])
			result.append(buffer[at + 2])
			result.append(buffer[at + 3])
	return result


## The saturation factor of a custom z value (saturation + 4 x exposure, exposure a whole number).
static func saturation_of(custom_z: float) -> float:
	return custom_z - 4.0 * roundf((custom_z - 1.0) / 4.0)


static func percentile(values: PackedFloat32Array, share: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted: PackedFloat32Array = values.duplicate()
	sorted.sort()
	return sorted[clampi(int(share * float(sorted.size() - 1)), 0, sorted.size() - 1)]


# --- tiles (AC 40) ---


## The grid pitch of the tile placements: the smallest positive gap between distinct x values and
## between distinct z values.
static func tile_pitch(placements: PackedFloat32Array) -> Vector2:
	var xs: Array[float] = []
	var zs: Array[float] = []
	for cell: int in placements.size() / 5:
		_add_distinct(xs, placements[cell * 5])
		_add_distinct(zs, placements[cell * 5 + 1])
	xs.sort()
	zs.sort()
	return Vector2(_smallest_gap(xs), _smallest_gap(zs))


static func _add_distinct(values: Array[float], value: float) -> void:
	for known: float in values:
		if absf(known - value) < 1e-6:
			return
	values.append(value)


static func _smallest_gap(sorted_values: Array[float]) -> float:
	var gap: float = INF
	for i: int in range(1, sorted_values.size()):
		gap = minf(gap, sorted_values[i] - sorted_values[i - 1])
	return gap if gap != INF else 0.0


## The cells of the placement lattice: {Vector2i(column, row): Vector3i(tile, turns, mirror)}.
static func lattice(placements: PackedFloat32Array, pitch: Vector2) -> Dictionary:
	var result: Dictionary = {}
	if pitch.x <= 0.0 or pitch.y <= 0.0:
		return result
	var min_x: float = INF
	var min_z: float = INF
	for cell: int in placements.size() / 5:
		min_x = minf(min_x, placements[cell * 5])
		min_z = minf(min_z, placements[cell * 5 + 1])
	for cell: int in placements.size() / 5:
		var at: int = cell * 5
		var key: Vector2i = Vector2i(
			roundi((placements[at] - min_x) / pitch.x),
			roundi((placements[at + 1] - min_z) / pitch.y)
		)
		result[key] = Vector3i(
			int(placements[at + 4]), int(placements[at + 2]), int(placements[at + 3])
		)
	return result


## The number of pairs of edge-adjacent cells (in x or z) with the same (tile, turns, mirror).
static func adjacent_equal_pairs(cells: Dictionary) -> int:
	var equal: int = 0
	for key: Vector2i in cells:
		for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			var other: Vector2i = key + step
			if cells.has(other) and cells[other] == cells[key]:
				equal += 1
	return equal


## Positions and orientations of the top layer stones: centre height at least `flat_depth` minus
## `layer`, inside the inner lattice tiles only (the outer ring of tiles meets the glass ring).
## Returns a flat array of (x, z, angle in 0..PI) triples. The angle is the direction of the
## longest axis of the stone on the xz plane: the longest basis column for sand, the longest axis
## of the variant mesh (`axes`) for meshes.
static func top_layer_points(
	entries: Array[Dictionary],
	axes: PackedInt32Array,
	flat_depth: float,
	layer: float,
	is_sand: bool
) -> PackedFloat32Array:
	var points: PackedFloat32Array = PackedFloat32Array()
	for entry: Dictionary in entries:
		var buffer: PackedFloat32Array = entry["buffer"]
		var offset: Transform3D = entry["offset"]
		var variant: int = entry["variant"]
		for index: int in buffer.size() / FLOATS:
			var t: Transform3D = offset * instance_transform(buffer, index)
			if t.origin.y < flat_depth - layer:
				continue
			var direction: Vector3 = _longest_direction(t.basis, variant, axes, is_sand)
			var angle: float = fposmod(atan2(direction.z, direction.x), PI)
			points.append(t.origin.x)
			points.append(t.origin.z)
			points.append(angle)
	return points


static func _longest_direction(
	basis: Basis, variant: int, axes: PackedInt32Array, is_sand: bool
) -> Vector3:
	var columns: Array[Vector3] = [basis.x, basis.y, basis.z]
	var chosen: int = 0
	if is_sand or variant < 0:
		var best: float = -1.0
		for i: int in 3:
			if columns[i].length() > best:
				best = columns[i].length()
				chosen = i
	else:
		chosen = axes[variant]
	return columns[chosen]


## The density ratio of the 3 mm bands centred on the tile borders to the rest of the inner tiles
## (1.0 = equal), from the points of top_layer_points. `lattice_origin` is the centre of the cell
## (0, 0), `columns` and `rows` the lattice size; only points in the inner tiles are counted.
static func seam_density_ratio(
	points: PackedFloat32Array, lattice_origin: Vector2, pitch: Vector2, columns: int, rows: int
) -> float:
	var in_band: int = 0
	var elsewhere: int = 0
	var half_band: float = 0.0015
	for i: int in points.size() / 3:
		var local: Vector2 = Vector2(points[i * 3], points[i * 3 + 1]) - lattice_origin
		var column: int = roundi(local.x / pitch.x)
		var row: int = roundi(local.y / pitch.y)
		if column < 1 or row < 1 or column > columns - 2 or row > rows - 2:
			continue
		var dx: float = absf(local.x - float(column) * pitch.x)
		var dz: float = absf(local.y - float(row) * pitch.y)
		var to_border_x: float = pitch.x / 2.0 - dx
		var to_border_z: float = pitch.y / 2.0 - dz
		if to_border_x <= half_band or to_border_z <= half_band:
			in_band += 1
		else:
			elsewhere += 1
	var fraction: float = (
		1.0 - (1.0 - 2.0 * half_band / pitch.x) * (1.0 - 2.0 * half_band / pitch.y)
	)
	if in_band + elsewhere == 0 or fraction <= 0.0 or fraction >= 1.0:
		return 0.0
	var band_density: float = float(in_band) / fraction
	var other_density: float = float(elsewhere) / (1.0 - fraction)
	return band_density / maxf(other_density, 1e-9)


## 8-bin histograms (shares) of the angles of the points of every inner tile, keyed by the lattice
## cell, for tiles with at least `minimum` points.
static func orientation_histograms(
	points: PackedFloat32Array,
	lattice_origin: Vector2,
	pitch: Vector2,
	columns: int,
	rows: int,
	minimum: int
) -> Dictionary:
	var counts: Dictionary = {}
	for i: int in points.size() / 3:
		var local: Vector2 = Vector2(points[i * 3], points[i * 3 + 1]) - lattice_origin
		var key: Vector2i = Vector2i(roundi(local.x / pitch.x), roundi(local.y / pitch.y))
		if key.x < 1 or key.y < 1 or key.x > columns - 2 or key.y > rows - 2:
			continue
		var bins: PackedFloat32Array = counts.get(key, PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0]))
		var bin: int = clampi(int(points[i * 3 + 2] / PI * 8.0), 0, 7)
		bins[bin] += 1.0
		counts[key] = bins
	var result: Dictionary = {}
	for key: Vector2i in counts:
		var bins: PackedFloat32Array = counts[key]
		var total: float = 0.0
		for value: float in bins:
			total += value
		if int(total) < minimum:
			continue
		var shares: PackedFloat32Array = PackedFloat32Array()
		for value: float in bins:
			shares.append(value / total)
		result[key] = shares
	return result


## Half the L1 distance between two histograms of shares.
static func histogram_distance(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var total: float = 0.0
	for i: int in a.size():
		total += absf(a[i] - b[i])
	return total / 2.0
