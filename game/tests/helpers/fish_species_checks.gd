extends RefCounted
## Rule checks and measurements for the three #34 species models and masks (technical plan of #34,
## section 1). Every check returns a list of failures, empty when the rule holds, and each failure
## starts with the name of the broken rule. The same code checks the committed files and, for the
## mask rules, synthetic images (the edge cases of AC 31 and 37).
##
## The species .glb maps both glTF materials to the one species material (ADR 0013 rule 2), so the
## surface names cannot be read from the imported material. The surface roles come from the glTF
## JSON instead: primitive i of the file is surface i of the imported mesh, and its material
## name is `body` or `fin`. Whether a material is double-sided is read from the same JSON.

const Checks := preload("res://tests/helpers/proof_fish_checks.gd")
const LfsGuard := preload("res://tests/helpers/lfs_guard.gd")

const ASSET_DIR := "res://assets/fish/"
const MASK_SIZE := 256
const BAND_TOLERANCE := 20
const BARYCENTRIC_STEPS := 6
const LENGTH_TOLERANCE := 0.01
const SLICE := 0.05
const MID_PLANE := 0.01

## adult_length_cm (standard length) of the issue table, the scale of AC 9.
const ADULT_CM: Dictionary[StringName, float] = {
	&"neon_tetra": 3.0,
	&"angelfish": 12.0,
	&"bronze_corydoras": 5.5,
}
## AC 9: total length including fins in body units, bounds inclusive.
const TOTAL_UNITS: Dictionary[StringName, Vector2] = {
	&"neon_tetra": Vector2(1.15, 1.40),
	&"angelfish": Vector2(1.25, 1.40),
	&"bronze_corydoras": Vector2(1.20, 1.30),
}
const ANGEL_HEIGHT_CAP := 1.55


## One loaded species model: the imported scene, its mesh, the surface roles and the .import file.
class FishModel:
	extends RefCounted
	var id: StringName = &""
	var root: Node3D = null
	var mesh: ArrayMesh = null
	var body: int = -1
	var fin: int = -1
	var config: ConfigFile = null
	var gltf: Dictionary = {}
	## "" when everything loaded; otherwise the cause.
	var problem: String = ""

	func release() -> void:
		if root != null and is_instance_valid(root):
			root.free()
		root = null
		mesh = null


static func glb_path(id: StringName) -> String:
	return "%s%s.glb" % [ASSET_DIR, id]


static func mask_path(id: StringName) -> String:
	return "%s%s_mask.png" % [ASSET_DIR, id]


static func open(id: StringName) -> FishModel:
	var result: FishModel = FishModel.new()
	result.id = id
	var path: String = glb_path(id)
	result.problem = LfsGuard.problem(path, LfsGuard.GLB_MAGIC)
	if not result.problem.is_empty():
		return result
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		result.problem = "import failed: %s did not load as a PackedScene" % path
		return result
	result.root = scene.instantiate() as Node3D
	if result.root == null:
		result.problem = "import failed: root of %s is not a Node3D" % path
		return result
	var instances: Array[MeshInstance3D] = mesh_instances(result.root)
	if instances.size() != 1 or not instances[0].mesh is ArrayMesh:
		result.problem = "layout: expected exactly 1 MeshInstance3D with an ArrayMesh in %s" % path
		return result
	result.mesh = instances[0].mesh as ArrayMesh
	result.gltf = read_gltf(path)
	var roles: Dictionary = _surface_roles(result.gltf)
	result.body = int(roles.get("body", -1))
	result.fin = int(roles.get("fin", -1))
	if result.body < 0 or result.fin < 0 or result.mesh.get_surface_count() != 2:
		result.problem = "layout: surfaces must be one body and one fin, glTF roles %s" % [roles]
		return result
	var config: ConfigFile = ConfigFile.new()
	if config.load(path + ".import") != OK:
		result.problem = "missing: %s.import" % path
		return result
	result.config = config
	return result


static func mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		found.append_array(mesh_instances(child))
	return found


## The JSON chunk of a binary glTF as a Dictionary; empty when it cannot be read.
static func read_gltf(path: String) -> Dictionary:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.size() < 20:
		return {}
	var length: int = bytes.decode_u32(12)
	var parsed: Variant = JSON.parse_string(bytes.slice(20, 20 + length).get_string_from_utf8())
	return parsed if parsed is Dictionary else {}


## {material name: surface index}, in primitive order of the first mesh.
static func _surface_roles(gltf: Dictionary) -> Dictionary:
	var roles: Dictionary = {}
	var meshes: Array = gltf.get("meshes", [])
	var materials: Array = gltf.get("materials", [])
	if meshes.is_empty():
		return roles
	var primitives: Array = (meshes[0] as Dictionary).get("primitives", [])
	for index: int in primitives.size():
		var material_index: int = int((primitives[index] as Dictionary).get("material", -1))
		if material_index >= 0 and material_index < materials.size():
			roles[str((materials[material_index] as Dictionary).get("name", ""))] = index
	return roles


static func column_v3(m: FishModel, surface: int) -> PackedVector3Array:
	return Checks.column_v3(m.mesh.surface_get_arrays(surface), Mesh.ARRAY_VERTEX)


static func body_points(m: FishModel) -> PackedVector3Array:
	return column_v3(m, m.body)


static func fin_points(m: FishModel) -> PackedVector3Array:
	return column_v3(m, m.fin)


static func all_points(m: FishModel) -> PackedVector3Array:
	var all: PackedVector3Array = body_points(m)
	all.append_array(fin_points(m))
	return all


static func extent(points: PackedVector3Array, axis: int) -> Vector2:
	var low: float = INF
	var high: float = -INF
	for point: Vector3 in points:
		low = minf(low, point[axis])
		high = maxf(high, point[axis])
	return Vector2(low, high)


static func span(points: PackedVector3Array, axis: int) -> float:
	var range_v: Vector2 = extent(points, axis)
	return range_v.y - range_v.x


# --- AC 7: the #21 rules, by glTF surface role ---


static func layout_failures(m: FishModel) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	failures.append_array(Checks.transform_failures(m.root))
	failures.append_array(Checks.budget_failures(m.mesh))
	failures.append_array(Checks.uv_array_failures(m.mesh))
	failures.append_array(Checks.import_failures(m.config))
	return failures


static func atlas_cell_failures(m: FishModel) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	var used: Dictionary = {}
	for role: String in ["body", "fin"]:
		var surface: int = m.body if role == "body" else m.fin
		var arrays: Array = m.mesh.surface_get_arrays(surface)
		var uv2: PackedVector2Array = Checks.column_v2(arrays, Mesh.ARRAY_TEX_UV2)
		var indices: PackedInt32Array = Checks.surface_triangles(arrays)
		var cells: Array[Vector2i] = Checks.triangle_cells(arrays)
		var seen: Dictionary = {}
		var bad: int = 0
		for t: int in cells.size():
			seen[cells[t]] = true
			if not _inside_cell(uv2, indices, t, cells[t]):
				bad += 1
		if bad > 0:
			failures.append(
				"atlas cell: surface %s has %d triangles straddling cells" % [role, bad]
			)
		used[role] = seen
	var body_cells: Dictionary = used["body"]
	var fin_cells: Dictionary = used["fin"]
	for cell: Vector2i in body_cells:
		if fin_cells.has(cell):
			failures.append("atlas cell: body and fin triangles share cell %s" % cell)
	var distinct: Dictionary = body_cells.duplicate()
	distinct.merge(fin_cells)
	if distinct.size() < 2:
		failures.append("atlas cell: only %d cell(s) used, need at least 2" % distinct.size())
	return failures


static func _inside_cell(
	uv2: PackedVector2Array, indices: PackedInt32Array, triangle: int, cell: Vector2i
) -> bool:
	var margin: Vector2 = Vector2.ONE * (Checks.INSET - Checks.CELL_TOLERANCE)
	var low: Vector2 = Vector2(cell) / float(Checks.GRID) + margin
	var high: Vector2 = Vector2(cell + Vector2i.ONE) / float(Checks.GRID) - margin
	for k: int in 3:
		var point: Vector2 = uv2[indices[triangle * 3 + k]]
		if point.x < low.x or point.x > high.x or point.y < low.y or point.y > high.y:
			return false
	return true


static func alpha_failures(m: FishModel) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	for role: String in ["body", "fin"]:
		var surface: int = m.body if role == "body" else m.fin
		var colors: PackedColorArray = Checks.column_color(
			m.mesh.surface_get_arrays(surface), Mesh.ARRAY_COLOR
		)
		if colors.is_empty():
			failures.append("vertex alpha: COLOR missing on surface %s" % role)
			continue
		var bad: int = 0
		for color: Color in colors:
			if role == "fin" and color.a < Checks.ALPHA_FIN_MIN:
				bad += 1
			elif role == "body" and color.a > Checks.ALPHA_BODY_MAX:
				bad += 1
		if bad > 0:
			failures.append("vertex alpha: %d %s vertices break the binary mask" % [bad, role])
	return failures


## The fin material is double-sided and the body material is not, read from the glTF JSON.
static func cull_failures(m: FishModel) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	var sided: Dictionary = {}
	for entry: Variant in m.gltf.get("materials", []):
		var material: Dictionary = entry
		sided[str(material.get("name", ""))] = bool(material.get("doubleSided", false))
	if not bool(sided.get("fin", false)):
		failures.append("double-sided: the glTF fin material must have doubleSided true")
	if bool(sided.get("body", true)):
		failures.append("double-sided: the glTF body material must be single-sided")
	return failures


static func smooth_normal_failures(m: FishModel) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	var arrays: Array = m.mesh.surface_get_arrays(m.body)
	var vertices: PackedVector3Array = Checks.column_v3(arrays, Mesh.ARRAY_VERTEX)
	var normals: PackedVector3Array = Checks.column_v3(arrays, Mesh.ARRAY_NORMAL)
	if normals.size() != vertices.size():
		failures.append("smooth normals: NORMAL missing on the body surface")
		return failures
	var groups: Dictionary = {}
	for i: int in vertices.size():
		var key: Vector3i = Vector3i((vertices[i] / Checks.POSITION_SNAP).round())
		var members: Array = groups.get(key, [])
		members.append(normals[i])
		groups[key] = members
	var worst: float = 0.0
	for key: Vector3i in groups:
		var members: Array = groups[key]
		for a: int in members.size():
			for b: int in range(a + 1, members.size()):
				var first: Vector3 = (members[a] as Vector3).normalized()
				var second: Vector3 = (members[b] as Vector3).normalized()
				worst = maxf(worst, rad_to_deg(first.angle_to(second)))
	if worst > Checks.SMOOTH_MAX_DEGREES:
		failures.append(
			(
				"smooth normals: shared body vertices differ by %.1f degrees, max %.1f"
				% [worst, Checks.SMOOTH_MAX_DEGREES]
			)
		)
	return failures


static func body_failures(m: FishModel) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	var body: PackedVector3Array = body_points(m)
	if body.is_empty():
		failures.append("body length: surface body is empty")
		return failures
	var box: AABB = Checks.bounds(body)
	if absf(box.size.z - 1.0) > 0.01:
		failures.append("body length: Z extent %.4f, must be 1.0 +/- 0.01" % box.size.z)
	if box.get_center().length() > 0.01:
		failures.append(
			"origin: body bounding box centre is %s, must be the origin" % box.get_center()
		)
	var fins: PackedVector3Array = fin_points(m)
	if fins.is_empty() or extent(fins, 2).x >= box.position.z:
		failures.append("front axis: the caudal fin must reach behind the body tail (negative Z)")
	return failures


# --- fin parts and measurement helpers (AC 9, 10) ---


## Connected components of the fin surface, vertices welded by position.
static func fin_components(m: FishModel) -> Array[PackedVector3Array]:
	var arrays: Array = m.mesh.surface_get_arrays(m.fin)
	var fins: PackedVector3Array = Checks.column_v3(arrays, Mesh.ARRAY_VERTEX)
	var triangles: PackedInt32Array = Checks.surface_triangles(arrays)
	var parent: Dictionary = {}
	var key_of: Array[Vector3i] = []
	for point: Vector3 in fins:
		var key: Vector3i = Vector3i((point / Checks.POSITION_SNAP).round())
		key_of.append(key)
		if not parent.has(key):
			parent[key] = key
	for t: int in range(0, triangles.size() - 2, 3):
		Checks._union(parent, key_of[triangles[t]], key_of[triangles[t + 1]])
		Checks._union(parent, key_of[triangles[t]], key_of[triangles[t + 2]])
	var groups: Dictionary = {}
	for index: int in fins.size():
		var root: Vector3i = Checks._find(parent, key_of[index])
		var members: PackedVector3Array = groups.get(root, PackedVector3Array())
		members.append(fins[index])
		groups[root] = members
	var result: Array[PackedVector3Array] = []
	for group: Variant in groups.values():
		result.append(group as PackedVector3Array)
	return result


static func centroid(points: PackedVector3Array) -> Vector3:
	var sum: Vector3 = Vector3.ZERO
	for point: Vector3 in points:
		sum += point
	return sum / maxf(1.0, float(points.size()))


static func largest_distance(points: PackedVector3Array) -> float:
	var best: float = 0.0
	for a: int in points.size():
		for b: int in range(a + 1, points.size()):
			best = maxf(best, points[a].distance_to(points[b]))
	return best


## The named fin parts of the plan (method of AC 10). Each value is a PackedVector3Array, empty
## when the part does not exist; "barbels" is an Array of them.
static func fin_parts(m: FishModel) -> Dictionary:
	var parts: Dictionary = {
		"caudal": PackedVector3Array(),
		"dorsal": PackedVector3Array(),
		"anal": PackedVector3Array(),
		"pelvic": PackedVector3Array(),
		"barbels": [],
	}
	var components: Array[PackedVector3Array] = fin_components(m)
	var caudal_index: int = -1
	var lowest_z: float = INF
	for index: int in components.size():
		var z_low: float = extent(components[index], 2).x
		if z_low < lowest_z:
			lowest_z = z_low
			caudal_index = index
	var dorsal_top: float = -INF
	var anal_bottom: float = INF
	var pelvic_bottom: float = INF
	var barbels: Array = []
	for index: int in components.size():
		var part: PackedVector3Array = components[index]
		var middle: bool = absf(centroid(part).x) < MID_PLANE
		var y_range: Vector2 = extent(part, 1)
		if index == caudal_index:
			parts["caudal"] = part
		if middle and y_range.y > dorsal_top:
			dorsal_top = y_range.y
			parts["dorsal"] = part
		if middle and index != caudal_index and y_range.x < anal_bottom:
			anal_bottom = y_range.x
			parts["anal"] = part
		if not middle and y_range.x < pelvic_bottom:
			pelvic_bottom = y_range.x
			parts["pelvic"] = part
		if extent(part, 2).x >= 0.35:
			barbels.append(part)
	parts["barbels"] = barbels
	return parts


## Dictionary of every number AC 9 and AC 10 bind, measured on the unscaled model by the plan.
static func measure(m: FishModel, mask: Image) -> Dictionary:
	var body: PackedVector3Array = body_points(m)
	var everything: PackedVector3Array = all_points(m)
	var parts: Dictionary = fin_parts(m)
	var body_y: Vector2 = extent(body, 1)
	var result: Dictionary = {
		"body_length": span(body, 2),
		"total_length": span(everything, 2),
		"total_height": span(everything, 1),
		"body_depth": span(body, 1),
		"thickness": _thickness(m, mask),
	}
	var dorsal: PackedVector3Array = parts["dorsal"]
	var anal: PackedVector3Array = parts["anal"]
	var pelvic: PackedVector3Array = parts["pelvic"]
	var caudal: PackedVector3Array = parts["caudal"]
	if not dorsal.is_empty():
		result["dorsal_reach"] = extent(dorsal, 1).y - body_y.y
	if not anal.is_empty():
		result["anal_reach"] = body_y.x - extent(anal, 1).x
	if not pelvic.is_empty():
		result["pelvic_reach"] = body_y.x - extent(pelvic, 1).x
	if not caudal.is_empty():
		result["tail_fin_length"] = extent(body, 2).x - extent(caudal, 2).x
	result["belly_variation"] = _belly_variation(body)
	var lengths: Array[float] = []
	var beyond: int = 0
	for barbel: Variant in parts["barbels"]:
		lengths.append(largest_distance(barbel as PackedVector3Array))
		for point: Vector3 in barbel as PackedVector3Array:
			if point.z > 0.5 + 1e-4:
				beyond += 1
	result["barbel_lengths"] = lengths
	result["barbel_vertices_beyond"] = beyond
	return result


## X extent of the body vertices whose UV0 texel is band 0 (the eye excluded).
static func _thickness(m: FishModel, mask: Image) -> float:
	var arrays: Array = m.mesh.surface_get_arrays(m.body)
	var points: PackedVector3Array = Checks.column_v3(arrays, Mesh.ARRAY_VERTEX)
	var uvs: PackedVector2Array = Checks.column_v2(arrays, Mesh.ARRAY_TEX_UV)
	var low: float = INF
	var high: float = -INF
	for index: int in points.size():
		if mask != null and index < uvs.size() and band_at(mask, uvs[index]) != 0:
			continue
		low = minf(low, points[index].x)
		high = maxf(high, points[index].x)
	return high - low if high >= low else 0.0


## Body vertices with z in [-0.25, 0.25], bins of 0.025 in z, the lowest y of each bin; the span of
## those minima.
static func _belly_variation(body: PackedVector3Array) -> float:
	var minima: Dictionary = {}
	for point: Vector3 in body:
		if point.z < -0.25 or point.z > 0.25:
			continue
		var bin: int = floori((point.z + 0.25) / 0.025)
		minima[bin] = minf(float(minima.get(bin, INF)), point.y)
	if minima.is_empty():
		return INF
	var values: Array = minima.values()
	return float(values.max()) - float(values.min())


## Band of the texel under a UV0 position: round(b * 3) of the nearest texel.
static func band_at(mask: Image, uv: Vector2) -> int:
	var texel: Color = texel_at(mask, uv)
	return int(roundf(texel.b * 3.0))


static func texel_at(image: Image, uv: Vector2) -> Color:
	var x: int = clampi(floori(uv.x * image.get_width()), 0, image.get_width() - 1)
	var y: int = clampi(floori(uv.y * image.get_height()), 0, image.get_height() - 1)
	return image.get_pixel(x, y)


static func load_mask(id: StringName) -> Image:
	var path: String = mask_path(id)
	if not LfsGuard.problem(path, LfsGuard.PNG_MAGIC).is_empty():
		return null
	var image: Image = Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	return image


static func _in_range(
	label: String,
	value: float,
	low: float,
	high: float,
	tolerance: float,
	failures: PackedStringArray
) -> void:
	if value < low * (1.0 - tolerance) or value > high * (1.0 + tolerance):
		failures.append(
			(
				"%s: %.4f outside %.3f to %.3f (+- %.0f%%)"
				% [label, value, low, high, tolerance * 100.0]
			)
		)


## AC 10 for one species, from the numbers of measure().
static func silhouette_failures(id: StringName, numbers: Dictionary) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	var tol: float = LENGTH_TOLERANCE
	var depth: float = float(numbers["body_depth"])
	if id == &"neon_tetra":
		_in_range("neon body depth", depth, 0.22, 0.26, tol, failures)
	elif id == &"angelfish":
		_in_range("angelfish total height", float(numbers["total_height"]), 1.4, 1.8, tol, failures)
		if float(numbers["total_height"]) > ANGEL_HEIGHT_CAP:
			failures.append(
				"angelfish total height %.3f above the plan cap 1.55" % numbers["total_height"]
			)
		_in_range("angelfish body depth", depth, 0.70, 0.80, tol, failures)
		_in_range("angelfish thickness", float(numbers["thickness"]), 0.20, 0.25, tol, failures)
		for key: String in ["dorsal_reach", "anal_reach", "pelvic_reach"]:
			if not numbers.has(key):
				failures.append("angelfish: part %s not found" % key)
			elif float(numbers[key]) < 0.30 * (1.0 - tol):
				failures.append("angelfish %s %.3f, need at least 0.30" % [key, numbers[key]])
		if not numbers.has("tail_fin_length"):
			failures.append("angelfish: caudal fin not found")
		else:
			_in_range(
				"angelfish tail fin", float(numbers["tail_fin_length"]), 0.30, 0.40, tol, failures
			)
	elif id == &"bronze_corydoras":
		if float(numbers["belly_variation"]) > 0.05 * (1.0 + tol):
			failures.append("corydoras belly varies %.4f, max 0.05" % numbers["belly_variation"])
		_in_range("corydoras body depth", depth, 0.28, 0.33, tol, failures)
		if not numbers.has("dorsal_reach"):
			failures.append("corydoras: dorsal fin not found")
		else:
			_in_range(
				"corydoras dorsal fin", float(numbers["dorsal_reach"]), 0.25, 0.30, tol, failures
			)
		var lengths: Array = numbers["barbel_lengths"]
		if lengths.size() != 4:
			failures.append(
				"corydoras: expected 4 barbel parts (two pairs), found %d" % lengths.size()
			)
		for length: Variant in lengths:
			_in_range("corydoras barbel length", float(length), 0.06, 0.10, tol, failures)
		if int(numbers["barbel_vertices_beyond"]) > 0:
			failures.append("corydoras: barbel vertices beyond z = 0.5")
	return failures


# --- neon mask extents (AC 10) ---


## Interpolated positions and UV0 of every triangle of one surface on a 6 x 6 barycentric grid.
static func surface_samples(m: FishModel, surface: int) -> Dictionary:
	var arrays: Array = m.mesh.surface_get_arrays(surface)
	var points: PackedVector3Array = Checks.column_v3(arrays, Mesh.ARRAY_VERTEX)
	var uvs: PackedVector2Array = Checks.column_v2(arrays, Mesh.ARRAY_TEX_UV)
	var triangles: PackedInt32Array = Checks.surface_triangles(arrays)
	var out_points: PackedVector3Array = PackedVector3Array()
	var out_uvs: PackedVector2Array = PackedVector2Array()
	for t: int in range(0, triangles.size() - 2, 3):
		for i: int in BARYCENTRIC_STEPS + 1:
			for j: int in BARYCENTRIC_STEPS + 1 - i:
				var u: float = float(i) / BARYCENTRIC_STEPS
				var v: float = float(j) / BARYCENTRIC_STEPS
				var w: float = 1.0 - u - v
				var a: int = triangles[t]
				var b: int = triangles[t + 1]
				var c: int = triangles[t + 2]
				out_points.append(points[a] * w + points[b] * u + points[c] * v)
				out_uvs.append(uvs[a] * w + uvs[b] * u + uvs[c] * v)
	return {"points": out_points, "uvs": out_uvs}


static func neon_extent_failures(m: FishModel, mask: Image) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	var samples: Dictionary = surface_samples(m, m.body)
	var points: PackedVector3Array = samples["points"]
	var uvs: PackedVector2Array = samples["uvs"]
	var stripe_s_low: float = INF
	var stripe_s_high: float = -INF
	var red_s_low: float = INF
	var red_s_high: float = -INF
	var stripe_slices: Dictionary = {}
	var red_slices: Dictionary = {}
	var body_slices: Dictionary = {}
	for index: int in points.size():
		var texel: Color = texel_at(mask, uvs[index])
		var s: float = 0.5 - points[index].z
		var slice: int = floori(s / SLICE)
		var body_range: Vector2 = body_slices.get(slice, Vector2(INF, -INF))
		body_slices[slice] = Vector2(
			minf(body_range.x, points[index].y), maxf(body_range.y, points[index].y)
		)
		if texel.r8 >= 128:
			stripe_s_low = minf(stripe_s_low, s)
			stripe_s_high = maxf(stripe_s_high, s)
			if points[index].x > 0.0:
				var range_y: Vector2 = stripe_slices.get(slice, Vector2(INF, -INF))
				stripe_slices[slice] = Vector2(
					minf(range_y.x, points[index].y), maxf(range_y.y, points[index].y)
				)
		if texel.g8 >= 128:
			red_s_low = minf(red_s_low, s)
			red_s_high = maxf(red_s_high, s)
			var red_range: Vector2 = red_slices.get(slice, Vector2(INF, -INF))
			red_slices[slice] = Vector2(
				minf(red_range.x, points[index].y), maxf(red_range.y, points[index].y)
			)
	if stripe_s_low == INF:
		failures.append("neon stripe: no body sample reads R >= 128")
	else:
		if absf(stripe_s_low - 0.12) > 0.03:
			failures.append("neon stripe starts at s %.3f, need 0.12 +- 0.03" % stripe_s_low)
		if absf(stripe_s_high - 0.88) > 0.03:
			failures.append("neon stripe ends at s %.3f, need 0.88 +- 0.03" % stripe_s_high)
	var widths: Array[float] = []
	for slice: int in stripe_slices:
		var slice_s: float = (float(slice) + 0.5) * SLICE
		if slice_s >= 0.25 and slice_s <= 0.75:
			var range_y: Vector2 = stripe_slices[slice]
			widths.append(range_y.y - range_y.x)
	widths.sort()
	if widths.is_empty():
		failures.append("neon stripe: no stripe samples between s 0.25 and 0.75")
	else:
		var median: float = widths[widths.size() / 2]  # lower-middle element of the sorted list
		if median < 0.07 or median > 0.16:
			failures.append("neon stripe width %.3f, need 0.10 to 0.13 +- 0.03" % median)
	if red_s_low == INF:
		failures.append("neon red: no body sample reads G >= 128")
		return failures
	if absf(red_s_low - 0.45) > 0.03:
		failures.append("neon red starts at s %.3f, need 0.45 +- 0.03" % red_s_low)
	if red_s_high < 0.97:
		failures.append("neon red reaches s %.3f, need at least 0.97" % red_s_high)
	for slice: int in red_slices:
		var slice_s: float = (float(slice) + 0.5) * SLICE
		if slice_s < 0.5 or slice_s > 0.85:
			continue
		var body_range: Vector2 = body_slices[slice]
		var red_range: Vector2 = red_slices[slice]
		var local_depth: float = body_range.y - body_range.x
		if local_depth <= 0.0:
			continue
		var share: float = (red_range.y - body_range.x) / local_depth
		if share < 0.37 or share > 0.53:
			failures.append(
				(
					"neon red top at %.3f of the depth in slice s %.2f, need 0.40 to 0.50"
					% [share, slice_s]
				)
			)
	return failures


# --- AC 8, 31, 37: the mask image ---


## Mask rules for one species on a loaded image (also fed synthetic images by the edge tests).
static func mask_failures(image: Image, id: StringName) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	if image.get_width() != MASK_SIZE or image.get_height() != MASK_SIZE:
		failures.append("mask size: %dx%d, need 256x256" % [image.get_width(), image.get_height()])
		return failures
	if image.get_format() != Image.FORMAT_RGBA8:
		failures.append(
			"mask format: %d, need RGBA8 (%d)" % [image.get_format(), Image.FORMAT_RGBA8]
		)
		return failures
	var data: PackedByteArray = image.get_data()
	var size: int = MASK_SIZE
	var bands: PackedInt32Array = PackedInt32Array()
	bands.resize(size * size)
	var band_counts: Array[int] = [0, 0, 0, 0]
	var blue_bad: int = 0
	var alpha_bad: int = 0
	var alpha_body: int = 0
	var eye_alpha: int = 0
	var red_count: int = 0
	var green_count: int = 0
	for index: int in size * size:
		var red: int = data[index * 4]
		var green: int = data[index * 4 + 1]
		var blue: int = data[index * 4 + 2]
		var alpha: int = data[index * 4 + 3]
		var band: int = int(roundf(float(blue) / 255.0 * 3.0))
		bands[index] = band
		band_counts[band] += 1
		if absi(blue - band * 85) > BAND_TOLERANCE:
			blue_bad += 1
		if alpha > BAND_TOLERANCE and alpha < 255 - BAND_TOLERANCE:
			alpha_bad += 1
		if alpha >= 255 - BAND_TOLERANCE:
			alpha_body += 1
		if band > 0 and alpha > BAND_TOLERANCE:
			eye_alpha += 1
		if red >= 128:
			red_count += 1
		if green >= 128:
			green_count += 1
	if blue_bad > 0:
		failures.append(
			(
				"eye bands: %d B texels are outside the tolerance of 20 around 0, 85, 170, 255"
				% blue_bad
			)
		)
	if band_counts[1] == 0:
		failures.append("eye bands: no pupil texel (85)")
	if band_counts[3] == 0:
		failures.append("eye bands: no painted dot texel (255)")
	elif not _has_block(bands, 3, 3):
		failures.append("eye bands: the dot has no 3 x 3 block of texels")
	if id == &"angelfish":
		if band_counts[2] == 0:
			failures.append("eye bands: the angelfish has no iris ring (170)")
		else:
			failures.append_array(_ring_failures(bands))
	elif band_counts[2] > 0:
		failures.append(
			"eye bands: %s must have no iris band, found %d texels" % [id, band_counts[2]]
		)
	if alpha_bad > 0:
		failures.append("body alpha: %d texels are not within 20 of 0 or 255" % alpha_bad)
	if alpha_body == 0:
		failures.append("body alpha: the tintable body region is empty")
	if eye_alpha > 0:
		failures.append("body alpha: %d eye texels carry a body alpha above 20" % eye_alpha)
	if id == &"neon_tetra":
		if red_count == 0:
			failures.append("pattern R: the stripe region is empty")
		if green_count == 0:
			failures.append("pattern G: the red lower half region is empty")
	return failures


static func _has_block(bands: PackedInt32Array, wanted: int, side: int) -> bool:
	var size: int = MASK_SIZE
	for y: int in size - side + 1:
		for x: int in size - side + 1:
			var all_match: bool = true
			for dy: int in side:
				for dx: int in side:
					if bands[(y + dy) * size + x + dx] != wanted:
						all_match = false
			if all_match:
				return true
	return false


## Every band 0 or 2 texel within 2 texels (Chebyshev) of a pupil or dot texel must be band 2.
static func _ring_failures(bands: PackedInt32Array) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	var size: int = MASK_SIZE
	var bad: int = 0
	for y: int in size:
		for x: int in size:
			var band: int = bands[y * size + x]
			if band != 1 and band != 3:
				continue
			for dy: int in range(-2, 3):
				for dx: int in range(-2, 3):
					var nx: int = x + dx
					var ny: int = y + dy
					if nx < 0 or ny < 0 or nx >= size or ny >= size:
						continue
					var near: int = bands[ny * size + nx]
					if near == 0:
						bad += 1
	if bad > 0:
		failures.append(
			"eye bands: %d texels in the 2 texel ring around the pupil are band 0, not iris" % bad
		)
	return failures


## No fin triangle samples a texel with a body alpha above 20 (fins are tinted by nothing).
static func fin_alpha_failures(m: FishModel, mask: Image) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	var samples: Dictionary = surface_samples(m, m.fin)
	var uvs: PackedVector2Array = samples["uvs"]
	var bad: int = 0
	for uv: Vector2 in uvs:
		if texel_at(mask, uv).a8 > BAND_TOLERANCE:
			bad += 1
	if bad > 0:
		failures.append("body alpha: %d fin samples read a body alpha above 20" % bad)
	return failures


## The mask `.import` file: lossless, mipmapped, no alpha border fix, no premultiplication.
static func mask_import_failures(config: ConfigFile) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	var expected: Dictionary = {
		"compress/mode": 0,
		"process/fix_alpha_border": false,
		"process/premult_alpha": false,
		"detect_3d/compress_to": 0,
		"process/size_limit": 0,
		"process/channel_remap/red": 0,
		"process/channel_remap/green": 1,
		"process/channel_remap/blue": 2,
		"process/channel_remap/alpha": 3,
		"mipmaps/generate": true,
	}
	for key: String in expected:
		if not config.has_section_key("params", key):
			failures.append("mask import: %s is missing" % key)
		elif config.get_value("params", key) != expected[key]:
			failures.append(
				(
					"mask import: %s is %s, must be %s"
					% [key, config.get_value("params", key), expected[key]]
				)
			)
	return failures
