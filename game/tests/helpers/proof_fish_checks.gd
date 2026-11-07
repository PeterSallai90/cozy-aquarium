extends RefCounted
## Rule checks for the proof fish (#21). Every function returns a list of failures, empty when the
## rule holds, and each failure starts with the name of the broken rule (criterion 15). The same
## code checks the committed .glb and a temporary one, and the negative tests feed it synthetic
## data.

const TRIANGLES_MIN := 800
const TRIANGLES_MAX := 2500
const GRID := 4
const CELL_PIXELS := 16
const INSET := 1.0 / 128.0
const CELL_TOLERANCE := 1e-4
const ALPHA_FIN_MIN := 0.99
const ALPHA_BODY_MAX := 0.01
const SMOOTH_MAX_DEGREES := 5.0
const POSITION_SNAP := 0.0001
const BODY := "body"
const FIN := "fin"
const FISH_SCALE := 0.035
const TOTAL_MIN_UNITS := 1.15
const TOTAL_MAX_UNITS := 1.40
const CEILING_UNITS := 2.29
const CENTRE_PLANE_X := 0.01
const EPS := 1e-4
const CAUDAL_ROOT_ZONE := 0.10


static func column_int(arrays: Array, slot: int) -> PackedInt32Array:
	var raw: Variant = arrays[slot]
	return raw if raw is PackedInt32Array else PackedInt32Array()


static func column_v3(arrays: Array, slot: int) -> PackedVector3Array:
	var raw: Variant = arrays[slot]
	return raw if raw is PackedVector3Array else PackedVector3Array()


static func column_v2(arrays: Array, slot: int) -> PackedVector2Array:
	var raw: Variant = arrays[slot]
	return raw if raw is PackedVector2Array else PackedVector2Array()


static func column_color(arrays: Array, slot: int) -> PackedColorArray:
	var raw: Variant = arrays[slot]
	return raw if raw is PackedColorArray else PackedColorArray()


static func surface_name(mesh: Mesh, surface: int) -> String:
	var material: Material = mesh.surface_get_material(surface)
	if material == null:
		return "surface_%d" % surface
	return material.resource_name


static func surface_by_name(mesh: Mesh, wanted: String) -> int:
	for surface: int in mesh.get_surface_count():
		if surface_name(mesh, surface) == wanted:
			return surface
	return -1


static func triangle_count(mesh: Mesh) -> int:
	var total: int = 0
	for surface: int in mesh.get_surface_count():
		total += surface_triangles(mesh.surface_get_arrays(surface)).size() / 3
	return total


## Vertex indices of one surface, three per triangle (a non-indexed surface counts in order).
static func surface_triangles(arrays: Array) -> PackedInt32Array:
	var indices: PackedInt32Array = column_int(arrays, Mesh.ARRAY_INDEX)
	if not indices.is_empty():
		return indices
	var vertices: PackedVector3Array = column_v3(arrays, Mesh.ARRAY_VERTEX)
	var sequence: PackedInt32Array = PackedInt32Array()
	for i: int in vertices.size():
		sequence.append(i)
	return sequence


static func surface_vertices(mesh: Mesh, wanted: String) -> PackedVector3Array:
	var surface: int = surface_by_name(mesh, wanted)
	if surface < 0:
		return PackedVector3Array()
	return column_v3(mesh.surface_get_arrays(surface), Mesh.ARRAY_VERTEX)


static func all_vertices(mesh: Mesh) -> PackedVector3Array:
	var all: PackedVector3Array = PackedVector3Array()
	for surface: int in mesh.get_surface_count():
		all.append_array(column_v3(mesh.surface_get_arrays(surface), Mesh.ARRAY_VERTEX))
	return all


static func z_extent(points: PackedVector3Array) -> Vector2:
	var low: float = INF
	var high: float = -INF
	for point: Vector3 in points:
		low = minf(low, point.z)
		high = maxf(high, point.z)
	return Vector2(low, high)


static func bounds(points: PackedVector3Array) -> AABB:
	var box: AABB = AABB(points[0], Vector3.ZERO)
	for point: Vector3 in points:
		box = box.expand(point)
	return box


# --- criteria 1 and 19: scene layout and transforms ---


static func layout_failures(root: Node, mesh: Mesh) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	if not root is Node3D:
		failures.append("scene root: %s is not a Node3D" % root.get_class())
	var count: int = _count_mesh_instances(root)
	if count != 1:
		failures.append("scene root: expected exactly 1 MeshInstance3D, found %d" % count)
	if not mesh is ArrayMesh:
		failures.append("mesh layout: the mesh is not an ArrayMesh")
		return failures
	var names: Array[String] = []
	for surface: int in mesh.get_surface_count():
		names.append(surface_name(mesh, surface))
	if names != [BODY, FIN]:
		failures.append("mesh layout: surfaces must be [body, fin], found %s" % [names])
	return failures


static func _count_mesh_instances(node: Node) -> int:
	var total: int = 1 if node is MeshInstance3D else 0
	for child: Node in node.get_children():
		total += _count_mesh_instances(child)
	return total


static func transform_failures(node: Node) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	if node is Node3D:
		var xform: Transform3D = (node as Node3D).transform
		var off: float = xform.origin.length()
		off += (xform.basis.x - Vector3.RIGHT).length()
		off += (xform.basis.y - Vector3.UP).length()
		off += (xform.basis.z - Vector3.BACK).length()
		if off > 0.00001:
			failures.append("identity transform: node %s has a baked transform" % node.name)
	for child: Node in node.get_children():
		failures.append_array(transform_failures(child))
	return failures


# --- criterion 4: import settings ---


static func import_failures(config: ConfigFile) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	if config == null:
		return failures
	var baking: Variant = null
	if config.has_section_key("params", "meshes/light_baking"):
		baking = config.get_value("params", "meshes/light_baking")
	if baking == null or int(baking) != 0:
		failures.append(
			"meshes/light_baking is %s, must be 0 (lightmaps overwrite the UV2 atlas)" % [baking]
		)
	var subresources: Variant = config.get_value("params", "_subresources", {})
	if _has_lightmap_uv(subresources):
		failures.append("generate/lightmap_uv=1 in _subresources, it overwrites the UV2 atlas")
	return failures


static func _has_lightmap_uv(value: Variant) -> bool:
	if value is Dictionary:
		var table: Dictionary = value
		for key: Variant in table:
			if str(key) == "generate/lightmap_uv" and int(table[key]) == 1:
				return true
			if _has_lightmap_uv(table[key]):
				return true
	return false


# --- criterion 2: triangle budget ---


static func budget_failures(mesh: Mesh) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	var total: int = triangle_count(mesh)
	if total > TRIANGLES_MAX:
		failures.append("triangle budget: %d > %d" % [total, TRIANGLES_MAX])
	if total < TRIANGLES_MIN:
		failures.append("triangle budget: %d < %d" % [total, TRIANGLES_MIN])
	return failures


# --- criterion 3: UV sets and atlas cells ---


static func uv_array_failures(mesh: Mesh) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	for surface: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var label: String = surface_name(mesh, surface)
		var uv: PackedVector2Array = column_v2(arrays, Mesh.ARRAY_TEX_UV)
		var uv2: PackedVector2Array = column_v2(arrays, Mesh.ARRAY_TEX_UV2)
		if uv.is_empty():
			failures.append("UV missing on surface %s" % label)
		if uv2.is_empty():
			failures.append("UV2 missing on surface %s (UV1 palette atlas lookup)" % label)
	return failures


## Cell (column, row from the top) of the centroid of every triangle of one surface, in index order.
static func triangle_cells(arrays: Array) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var uv2: PackedVector2Array = column_v2(arrays, Mesh.ARRAY_TEX_UV2)
	if uv2.is_empty():
		return cells
	var indices: PackedInt32Array = surface_triangles(arrays)
	for t: int in indices.size() / 3:
		var centroid: Vector2 = Vector2.ZERO
		for k: int in 3:
			centroid += uv2[indices[t * 3 + k]] / 3.0
		cells.append(Vector2i(floori(centroid.x * GRID), floori(centroid.y * GRID)))
	return cells


static func atlas_cell_failures(mesh: Mesh) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	var used: Dictionary = {}
	for surface: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var label: String = surface_name(mesh, surface)
		var uv2: PackedVector2Array = column_v2(arrays, Mesh.ARRAY_TEX_UV2)
		if uv2.is_empty():
			continue
		var indices: PackedInt32Array = surface_triangles(arrays)
		var cells: Array[Vector2i] = triangle_cells(arrays)
		var seen: Dictionary = {}
		var bad: int = 0
		for t: int in cells.size():
			seen[cells[t]] = true
			if _triangle_inside_cell(uv2, indices, t, cells[t]):
				continue
			bad += 1
			if bad <= 3:
				failures.append(
					"atlas cell: surface %s triangle %d straddles cells (%s)" % [label, t, cells[t]]
				)
		if bad > 3:
			failures.append("atlas cell: surface %s has %d bad triangles in total" % [label, bad])
		used[label] = seen
	var distinct: Dictionary = {}
	for label: String in used:
		distinct.merge(used[label] as Dictionary)
	if distinct.size() < 2:
		failures.append("atlas cell: only %d cell(s) used, need at least 2" % distinct.size())
	if used.has(BODY) and used.has(FIN):
		for cell: Vector2i in used[BODY] as Dictionary:
			if (used[FIN] as Dictionary).has(cell):
				failures.append("atlas cell: body and fin triangles share cell %s" % cell)
	return failures


static func _triangle_inside_cell(
	uv2: PackedVector2Array, indices: PackedInt32Array, triangle: int, cell: Vector2i
) -> bool:
	var margin: Vector2 = Vector2.ONE * (INSET - CELL_TOLERANCE)
	var low: Vector2 = Vector2(cell) / float(GRID) + margin
	var high: Vector2 = Vector2(cell + Vector2i.ONE) / float(GRID) - margin
	for k: int in 3:
		var point: Vector2 = uv2[indices[triangle * 3 + k]]
		if point.x < low.x or point.x > high.x or point.y < low.y or point.y > high.y:
			return false
	return true


# --- criterion 7: vertex alpha mask ---


static func alpha_failures(mesh: Mesh) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	for wanted: String in [BODY, FIN]:
		var surface: int = surface_by_name(mesh, wanted)
		if surface < 0:
			failures.append("vertex alpha: surface %s missing" % wanted)
			continue
		var arrays: Array = mesh.surface_get_arrays(surface)
		var colors: PackedColorArray = column_color(arrays, Mesh.ARRAY_COLOR)
		if colors.is_empty():
			failures.append("vertex alpha: COLOR missing on surface %s" % wanted)
			continue
		var bad: int = 0
		for color: Color in colors:
			if wanted == FIN and color.a < ALPHA_FIN_MIN:
				bad += 1
			elif wanted == BODY and color.a > ALPHA_BODY_MAX:
				bad += 1
		if bad > 0:
			failures.append("vertex alpha: %d %s vertices break the binary mask" % [bad, wanted])
	return failures


# --- criterion 8: culling and smooth normals ---


static func cull_failures(mesh: Mesh) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	for wanted: String in [BODY, FIN]:
		var surface: int = surface_by_name(mesh, wanted)
		var material: BaseMaterial3D = null
		if surface >= 0:
			material = mesh.surface_get_material(surface) as BaseMaterial3D
		if material == null:
			failures.append("double-sided: surface %s has no BaseMaterial3D" % wanted)
			continue
		var disabled: bool = material.cull_mode == BaseMaterial3D.CULL_DISABLED
		if wanted == FIN and not disabled:
			failures.append("double-sided: the fin material must have cull mode disabled")
		if wanted == BODY and disabled:
			failures.append("double-sided: the body material must be single-sided")
	return failures


static func smooth_normal_failures(mesh: Mesh) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	var surface: int = surface_by_name(mesh, BODY)
	if surface < 0:
		failures.append("smooth normals: surface body missing")
		return failures
	var arrays: Array = mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = column_v3(arrays, Mesh.ARRAY_VERTEX)
	var normals: PackedVector3Array = column_v3(arrays, Mesh.ARRAY_NORMAL)
	if normals.size() != vertices.size():
		failures.append("smooth normals: NORMAL missing on the body surface")
		return failures
	var groups: Dictionary = {}
	for i: int in vertices.size():
		var key: Vector3i = Vector3i((vertices[i] / POSITION_SNAP).round())
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
	if worst > SMOOTH_MAX_DEGREES:
		failures.append(
			(
				"smooth normals: shared body vertices differ by %.1f degrees, max %.1f"
				% [worst, SMOOTH_MAX_DEGREES]
			)
		)
	return failures


# --- criterion 6: body extent, origin and front ---


static func body_failures(mesh: Mesh) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	var body: PackedVector3Array = surface_vertices(mesh, BODY)
	if body.is_empty():
		failures.append("body length: surface body missing or empty")
		return failures
	var box: AABB = bounds(body)
	if absf(box.size.z - 1.0) > 0.01:
		failures.append("body length: Z extent %.4f, must be 1.0 +/- 0.01" % box.size.z)
	var centre: Vector3 = box.get_center()
	if centre.length() > 0.01:
		failures.append("origin: body bounding box centre is %s, must be the origin" % centre)
	var fins: PackedVector3Array = surface_vertices(mesh, FIN)
	if fins.is_empty() or z_extent(fins).x >= box.position.z:
		failures.append("front axis: the caudal fin must reach behind the body tail (negative Z)")
	return failures


## Eye faces are the body triangles that point into the darkest atlas cell.
static func eye_failures(mesh: Mesh, atlas: Image) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	var surface: int = surface_by_name(mesh, BODY)
	if surface < 0 or atlas == null:
		failures.append("eye faces: need the body surface and the atlas")
		return failures
	var eye_cell: Vector2i = darkest_cell(atlas)
	var arrays: Array = mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = column_v3(arrays, Mesh.ARRAY_VERTEX)
	var indices: PackedInt32Array = surface_triangles(arrays)
	var cells: Array[Vector2i] = triangle_cells(arrays)
	var eye_triangles: int = 0
	var left: int = 0
	var right: int = 0
	var behind: int = 0
	for t: int in cells.size():
		if cells[t] != eye_cell:
			continue
		eye_triangles += 1
		var centroid: Vector3 = Vector3.ZERO
		for k: int in 3:
			centroid += vertices[indices[t * 3 + k]] / 3.0
		if centroid.z <= 0.2:
			behind += 1
		if centroid.x > 0.0:
			right += 1
		elif centroid.x < 0.0:
			left += 1
	if eye_triangles == 0:
		failures.append("eye faces: no body triangle uses the darkest atlas cell %s" % eye_cell)
		return failures
	if float(eye_triangles) / float(cells.size()) >= 0.15:
		failures.append(
			(
				"eye faces: %d of %d body triangles, need below 15 percent"
				% [eye_triangles, cells.size()]
			)
		)
	if behind > 0:
		failures.append("front axis: %d eye triangles are not at Z above 0.2" % behind)
	if left == 0 or right == 0:
		failures.append("eye faces: need an eye on both sides (left %d, right %d)" % [left, right])
	var fin_surface: int = surface_by_name(mesh, FIN)
	if fin_surface >= 0:
		var fin_cells: Array[Vector2i] = triangle_cells(mesh.surface_get_arrays(fin_surface))
		if fin_cells.has(eye_cell):
			failures.append("eye faces: a fin triangle uses the eye cell %s" % eye_cell)
	return failures


# --- criterion 17: real size and fins ---


static func size_failures(mesh: Mesh) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	var body: PackedVector3Array = surface_vertices(mesh, BODY)
	var fins: PackedVector3Array = surface_vertices(mesh, FIN)
	if body.is_empty() or fins.is_empty():
		failures.append("real size: surfaces body and fin must both exist")
		return failures
	var body_box: AABB = bounds(body)
	var total: Vector2 = z_extent(all_vertices(mesh))
	var total_units: float = total.y - total.x
	if total_units < TOTAL_MIN_UNITS or total_units > TOTAL_MAX_UNITS:
		failures.append(
			(
				"real size: total length %.3f units, need %.2f to %.2f"
				% [total_units, TOTAL_MIN_UNITS, TOTAL_MAX_UNITS]
			)
		)
	if total_units > CEILING_UNITS:
		failures.append(
			"real size: total length %.3f units is above the 8 cm ceiling" % total_units
		)
	var body_cm: float = body_box.size.z * FISH_SCALE * 100.0
	if body_cm < 3.465 or body_cm > 3.535:
		failures.append("real size: body length %.3f cm, need 3.465 to 3.535" % body_cm)
	var fin_surface: int = surface_by_name(mesh, FIN)
	var triangles: PackedInt32Array = surface_triangles(mesh.surface_get_arrays(fin_surface))
	failures.append_array(_fin_failures(fins, triangles, body_box))
	return failures


## Fin rules: front, tail, dorsal, pectorals. Fins are identified by position and connectivity
## only: centre plane |x| <= CENTRE_PLANE_X, grouped into components joined through shared triangle
## positions (vertices at the same position are welded). The mesh has no fin name or tag. Y is not
## used to tell fins apart because the proof caudal's upper lobe tip rises above the body top.
## A centre-plane component may extend behind the tail end only if it starts within
## CAUDAL_ROOT_ZONE of the tail end (the caudal); any other one fails as non-caudal.
## Known limits for #40:
## 1. A non-caudal fin welded to the caudal, or starting within CAUDAL_ROOT_ZONE of the tail end
##    (for example an adipose fin trailing behind the tail), counts as caudal and is not caught.
## 2. The strict rule fits the proof fish and short-finned tetras (neon, cardinal, rasbora, danio,
##    corydoras). Long-finned species (long-fin betta, fancy guppy, veil-tail, angelfish) have
##    dorsal and anal tips trailing past the tail base and need a per-species rule.
static func _fin_failures(
	fins: PackedVector3Array, triangles: PackedInt32Array, body_box: AABB
) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	var body_low: float = body_box.position.z
	var body_high: float = body_box.end.z
	var caudal_low: float = INF
	var dorsal_top: float = -INF
	var right: PackedVector3Array = PackedVector3Array()
	var left: PackedVector3Array = PackedVector3Array()
	var in_front: int = 0
	var behind_tail: int = 0
	for point: Vector3 in fins:
		if point.z > body_high + EPS:
			in_front += 1
		if absf(point.x) <= CENTRE_PLANE_X:
			dorsal_top = maxf(dorsal_top, point.y)
			continue
		if point.x > 0.0:
			right.append(point)
		else:
			left.append(point)
		if point.z < body_low - EPS:
			behind_tail += 1
	if in_front > 0:
		failures.append("fins extend Z: %d fin vertices are in front of the snout" % in_front)
	if behind_tail > 0:
		failures.append("fins extend Z: %d non-caudal vertices lie behind the tail" % behind_tail)
	var caudal_zone: float = body_low + CAUDAL_ROOT_ZONE
	for component: PackedVector3Array in _centre_components(fins, triangles):
		var span: Vector2 = z_extent(component)
		if span.y <= caudal_zone:
			caudal_low = minf(caudal_low, span.x)
			continue
		var behind: int = 0
		for point: Vector3 in component:
			if point.z < body_low - EPS:
				behind += 1
		if behind > 0:
			(
				failures
				. append(
					(
						"fins extend Z: non-caudal centre-plane fin lies behind the tail "
						+ (
							"(%d vertices, front at z %.3f, a caudal starts within %.2f of the tail end)"
							% [behind, span.y, CAUDAL_ROOT_ZONE]
						)
					)
				)
			)
	if caudal_low > body_low - 0.15:
		failures.append("caudal: reaches %.3f beyond the tail, need 0.15" % (body_low - caudal_low))
	if dorsal_top < body_box.end.y + 0.08:
		failures.append(
			"dorsal: rises %.3f above the body, need 0.08" % (dorsal_top - body_box.end.y)
		)
	for side: int in [1, -1]:
		var points: PackedVector3Array = right if side == 1 else left
		if points.is_empty():
			failures.append("pectoral: no fin vertices on side %d" % side)
			continue
		var extent: Vector2 = z_extent(points)
		if extent.y - extent.x < 0.10:
			failures.append(
				"pectoral: side %d is %.3f long, need 0.10" % [side, extent.y - extent.x]
			)
		if extent.x < body_low - EPS or extent.y > body_high + EPS:
			failures.append("pectoral: side %d is not inside the body Z range" % side)
	failures.append_array(_mirror_failures(right, left))
	return failures


## Connected components of the centre-plane fin triangles, vertices welded by position.
static func _centre_components(
	fins: PackedVector3Array, triangles: PackedInt32Array
) -> Array[PackedVector3Array]:
	var parent: Dictionary = {}
	var keys: Dictionary = {}
	for i: int in fins.size():
		var point: Vector3 = fins[i]
		if absf(point.x) > CENTRE_PLANE_X:
			continue
		var key: Vector3i = Vector3i(point / POSITION_SNAP + Vector3.ONE * 0.5)
		keys[i] = key
		if not parent.has(key):
			parent[key] = key
	for t: int in range(0, triangles.size() - 2, 3):
		var corners: Array[Vector3i] = []
		for c: int in 3:
			var index: int = triangles[t + c]
			if keys.has(index):
				corners.append(keys[index] as Vector3i)
		if corners.size() == 3:
			_union(parent, corners[0], corners[1])
			_union(parent, corners[0], corners[2])
	var groups: Dictionary = {}
	for key: Vector3i in parent:
		var root: Vector3i = _find(parent, key)
		var members: PackedVector3Array = groups.get(root, PackedVector3Array())
		members.append(Vector3(key) * POSITION_SNAP)
		groups[root] = members
	var result: Array[PackedVector3Array] = []
	for group: Variant in groups.values():
		result.append(group as PackedVector3Array)
	return result


static func _find(parent: Dictionary, key: Vector3i) -> Vector3i:
	var root: Vector3i = key
	while (parent[root] as Vector3i) != root:
		root = parent[root] as Vector3i
	return root


static func _union(parent: Dictionary, a: Vector3i, b: Vector3i) -> void:
	var root_a: Vector3i = _find(parent, a)
	var root_b: Vector3i = _find(parent, b)
	if root_a != root_b:
		parent[root_a] = root_b


static func _mirror_failures(
	right: PackedVector3Array, left: PackedVector3Array
) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	for point: Vector3 in right:
		if not _has_partner(left, Vector3(-point.x, point.y, point.z)):
			failures.append("pectoral: vertex %s has no X-mirrored partner" % point)
			break
	for point: Vector3 in left:
		if not _has_partner(right, Vector3(-point.x, point.y, point.z)):
			failures.append("pectoral: vertex %s has no X-mirrored partner" % point)
			break
	return failures


static func _has_partner(points: PackedVector3Array, wanted: Vector3) -> bool:
	for point: Vector3 in points:
		if point.distance_to(wanted) <= 0.001:
			return true
	return false


# --- criterion 9: the atlas image ---


static func luminance(color: Color) -> float:
	return 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b


static func darkest_cell(image: Image) -> Vector2i:
	var best: Vector2i = Vector2i.ZERO
	var best_luma: float = INF
	for row: int in GRID:
		for col: int in GRID:
			var middle: int = CELL_PIXELS / 2
			var luma: float = luminance(
				image.get_pixel(col * CELL_PIXELS + middle, row * CELL_PIXELS + middle)
			)
			if luma < best_luma:
				best_luma = luma
				best = Vector2i(col, row)
	return best


static func _cell_is_flat(image: Image, col: int, row: int) -> bool:
	var corner: Color = image.get_pixel(col * CELL_PIXELS, row * CELL_PIXELS)
	for y: int in CELL_PIXELS:
		for x: int in CELL_PIXELS:
			if image.get_pixel(col * CELL_PIXELS + x, row * CELL_PIXELS + y) != corner:
				return false
	return true


static func atlas_failures(image: Image) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	var expected: int = GRID * CELL_PIXELS
	if image.get_width() != expected or image.get_height() != expected:
		failures.append("atlas size: %dx%d, need 64x64" % [image.get_width(), image.get_height()])
		return failures
	var lumas: Array[float] = []
	for row: int in GRID:
		for col: int in GRID:
			if not _cell_is_flat(image, col, row):
				failures.append("atlas cells: cell (%d, %d) is not one flat colour" % [col, row])
			lumas.append(luminance(image.get_pixel(col * CELL_PIXELS, row * CELL_PIXELS)))
	var lowest: float = lumas.min()
	var ties: int = 0
	for luma: float in lumas:
		if absf(luma - lowest) < 1e-6:
			ties += 1
	if ties != 1:
		failures.append("atlas eye cell: the darkest cell must be unique, %d cells tie" % ties)
	return failures
