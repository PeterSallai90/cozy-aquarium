extends RefCounted
## Rule checks for the generated tank and room assets (#22). Every check returns a list of
## failures, empty when the rule holds; each failure starts with the name of the broken rule.
## Reuses the #21 helpers for the counting and UV array rules and adds the transform, glTF
## attribute, normal split and atlas collapse rules for several meshes in one scene.

const LfsGuard := preload("res://tests/helpers/lfs_guard.gd")
const Checks := preload("res://tests/helpers/proof_fish_checks.gd")

const TRIANGLE_LIMIT := 10000
const SPLIT_MIN_DEGREES := 30.0
const SAME_MAX_DEGREES := 5.0
const POSITION_SNAP := 0.0001
const COLLAPSE_TOLERANCE := 1e-4
const SCALE_TOLERANCE := 1e-4
const MM := 0.001


## Loads an imported .glb. Returns {"root": Node3D or null, "problem": String}.
static func open_glb(path: String) -> Dictionary:
	var problem: String = LfsGuard.problem(path, LfsGuard.GLB_MAGIC)
	if not problem.is_empty():
		return {"root": null, "problem": problem}
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		return {"root": null, "problem": "import failed: %s is not a PackedScene" % path}
	var root: Node3D = scene.instantiate() as Node3D
	if root == null:
		return {"root": null, "problem": "import failed: root of %s is not a Node3D" % path}
	return {"root": root, "problem": ""}


static func mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		found.append_array(mesh_instances(child))
	return found


## The MeshInstance3D with this node name anywhere below `root`, or null.
static func find_mesh(root: Node, wanted: String) -> MeshInstance3D:
	for instance: MeshInstance3D in mesh_instances(root):
		if String(instance.name) == wanted:
			return instance
	return null


## Product of the local transforms from `node` up to (not including) `ancestor`.
static func relative_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var result: Transform3D = Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != ancestor:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result


## Vertices of every surface of `instance`, in the space of `ancestor`.
static func vertices_in(instance: MeshInstance3D, ancestor: Node3D) -> PackedVector3Array:
	var xform: Transform3D = relative_transform(instance, ancestor)
	var result: PackedVector3Array = PackedVector3Array()
	if instance.mesh == null:
		return result
	for point: Vector3 in Checks.all_vertices(instance.mesh):
		result.append(xform * point)
	return result


## Bounds of the vertices of `instance` in the space of `ancestor`. A zero box when the mesh is
## missing or empty.
static func bounds_in(instance: MeshInstance3D, ancestor: Node3D) -> AABB:
	if instance == null:
		return AABB()
	var points: PackedVector3Array = vertices_in(instance, ancestor)
	if points.is_empty():
		return AABB()
	return Checks.bounds(points)


## Bounds of all the meshes below `root`, in the space of `root`.
static func scene_bounds(root: Node3D) -> AABB:
	var points: PackedVector3Array = PackedVector3Array()
	for instance: MeshInstance3D in mesh_instances(root):
		points.append_array(vertices_in(instance, root))
	if points.is_empty():
		return AABB()
	return Checks.bounds(points)


## Bounds of all the meshes below `root`, in the space of `ancestor`.
static func scene_bounds_in(root: Node3D, ancestor: Node3D) -> AABB:
	var points: PackedVector3Array = PackedVector3Array()
	for instance: MeshInstance3D in mesh_instances(root):
		points.append_array(vertices_in(instance, ancestor))
	if points.is_empty():
		return AABB()
	return Checks.bounds(points)


static func distinct_values(points: PackedVector3Array, axis: int) -> Array[float]:
	var found: Array[float] = []
	for point: Vector3 in points:
		var value: float = point[axis]
		var known: bool = false
		for other: float in found:
			if absf(other - value) < 0.0002:
				known = true
				break
		if not known:
			found.append(value)
	found.sort()
	return found


static func has_value(values: Array[float], wanted: float, tolerance: float) -> bool:
	for value: float in values:
		if absf(value - wanted) <= tolerance:
			return true
	return false


# --- AC 8: budget, UV layers, normals, import flags, scale ---


static func budget_failures(root: Node3D) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	var total: int = 0
	for instance: MeshInstance3D in mesh_instances(root):
		total += Checks.triangle_count(instance.mesh)
	if total == 0:
		failures.append("triangle budget: the scene has no triangles")
	if total > TRIANGLE_LIMIT:
		failures.append("triangle budget: %d > %d" % [total, TRIANGLE_LIMIT])
	return failures


static func uv_failures(root: Node3D) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	for instance: MeshInstance3D in mesh_instances(root):
		for text: String in Checks.uv_array_failures(instance.mesh):
			failures.append("%s (mesh %s)" % [text, instance.name])
	return failures


## Every triangle of UV1 (Godot UV2) collapses onto one point, the centre of an atlas cell, and the
## point lies inside the atlas.
static func atlas_collapse_failures(root: Node3D) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	for instance: MeshInstance3D in mesh_instances(root):
		for surface: int in instance.mesh.get_surface_count():
			var arrays: Array = instance.mesh.surface_get_arrays(surface)
			var uv2: PackedVector2Array = Checks.column_v2(arrays, Mesh.ARRAY_TEX_UV2)
			if uv2.is_empty():
				continue
			var indices: PackedInt32Array = Checks.surface_triangles(arrays)
			var bad: int = 0
			for t: int in indices.size() / 3:
				var a: Vector2 = uv2[indices[t * 3]]
				var b: Vector2 = uv2[indices[t * 3 + 1]]
				var c: Vector2 = uv2[indices[t * 3 + 2]]
				var spread: float = maxf(a.distance_to(b), a.distance_to(c))
				var inside: bool = a.x >= 0.0 and a.x <= 1.0 and a.y >= 0.0 and a.y <= 1.0
				if spread > COLLAPSE_TOLERANCE or not inside:
					bad += 1
			if bad > 0:
				failures.append(
					(
						"atlas cell: mesh %s surface %d has %d triangles off one cell centre"
						% [instance.name, surface, bad]
					)
				)
	return failures


## Vertices at one position may differ in normal only by a smooth difference (at most 5 degrees)
## or a real hard edge (at least 30 degrees).
static func normal_failures(root: Node3D) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	for instance: MeshInstance3D in mesh_instances(root):
		for surface: int in instance.mesh.get_surface_count():
			var arrays: Array = instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = Checks.column_v3(arrays, Mesh.ARRAY_VERTEX)
			var normals: PackedVector3Array = Checks.column_v3(arrays, Mesh.ARRAY_NORMAL)
			if normals.size() != vertices.size():
				failures.append("normals: mesh %s has no NORMAL array" % instance.name)
				continue
			var groups: Dictionary = {}
			for i: int in vertices.size():
				var key: Vector3i = Vector3i((vertices[i] / POSITION_SNAP).round())
				var members: Array = groups.get(key, [])
				members.append(normals[i])
				groups[key] = members
			var worst_between: float = 0.0
			for key: Vector3i in groups:
				var members: Array = groups[key]
				for a: int in members.size():
					for b: int in range(a + 1, members.size()):
						var first: Vector3 = (members[a] as Vector3).normalized()
						var second: Vector3 = (members[b] as Vector3).normalized()
						var angle: float = rad_to_deg(first.angle_to(second))
						if angle > SAME_MAX_DEGREES and angle < SPLIT_MIN_DEGREES - 0.5:
							worst_between = maxf(worst_between, angle)
			if worst_between > 0.0:
				failures.append(
					(
						"hard edges: mesh %s splits normals by %.1f degrees, a split needs %.0f"
						% [instance.name, worst_between, SPLIT_MIN_DEGREES]
					)
				)
	return failures


## No baked scale: every Node3D below and including `root` has unit scale.
static func scale_failures(root: Node3D) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Node3D:
			var scale_now: Vector3 = (node as Node3D).transform.basis.get_scale()
			if (scale_now - Vector3.ONE).length() > SCALE_TOLERANCE:
				failures.append("no baked scale: node %s has scale %s" % [node.name, scale_now])
		stack.append_array(node.get_children())
	return failures


static func import_failures(glb_path: String) -> PackedStringArray:
	var config: ConfigFile = ConfigFile.new()
	if config.load(glb_path + ".import") != OK:
		return PackedStringArray(["import flags: missing %s.import" % glb_path])
	return Checks.import_failures(config)


## Reads the glTF JSON chunk and checks that every primitive has TEXCOORD_0 and TEXCOORD_1 and no
## TEXCOORD_2 (exactly two UV layers).
static func texcoord_failures(glb_path: String) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(glb_path)
	if bytes.size() < 20:
		failures.append("glTF: %s is too short" % glb_path)
		return failures
	var length: int = bytes.decode_u32(12)
	var parsed: Variant = JSON.parse_string(bytes.slice(20, 20 + length).get_string_from_utf8())
	if not parsed is Dictionary:
		failures.append("glTF: the JSON chunk of %s does not parse" % glb_path)
		return failures
	var meshes: Array = (parsed as Dictionary).get("meshes", [])
	if meshes.is_empty():
		failures.append("glTF: %s has no meshes" % glb_path)
	for mesh: Variant in meshes:
		for primitive: Variant in (mesh as Dictionary).get("primitives", []):
			var attributes: Dictionary = (primitive as Dictionary).get("attributes", {})
			if not attributes.has("TEXCOORD_0") or not attributes.has("TEXCOORD_1"):
				failures.append("UV layers: a primitive of %s lacks TEXCOORD_0 or 1" % glb_path)
			if attributes.has("TEXCOORD_2"):
				failures.append("UV layers: a primitive of %s has a third UV layer" % glb_path)
	return failures


## All the AC 8 rules of one .glb, ready for one assert.
static func asset_failures(glb_path: String) -> PackedStringArray:
	var opened: Dictionary = open_glb(glb_path)
	var failures: PackedStringArray = PackedStringArray()
	if not String(opened["problem"]).is_empty():
		failures.append(String(opened["problem"]))
		return failures
	var root: Node3D = opened["root"]
	failures.append_array(budget_failures(root))
	failures.append_array(uv_failures(root))
	failures.append_array(atlas_collapse_failures(root))
	failures.append_array(normal_failures(root))
	failures.append_array(scale_failures(root))
	failures.append_array(import_failures(glb_path))
	failures.append_array(texcoord_failures(glb_path))
	root.free()
	return failures


# --- tank geometry (AC 6) ---


## Interior, exterior, height and base of the tank glb against the given interior size (x length,
## y height, z depth), glass thickness and trim size (width and height), all in metres, tolerance
## 1 mm.
static func tank_failures(
	root: Node3D, interior: Vector3, glass: float, trim_size: float = 0.01
) -> PackedStringArray:
	var failures: PackedStringArray = PackedStringArray()
	var frame: MeshInstance3D = find_mesh(root, "Frame")
	var glass_mesh: MeshInstance3D = find_mesh(root, "Glass")
	if frame == null or glass_mesh == null:
		failures.append("tank meshes: Frame and Glass must both exist")
		return failures
	var panes: PackedVector3Array = vertices_in(glass_mesh, root)
	var half_x: float = interior.x / 2.0
	var half_z: float = interior.z / 2.0
	var xs: Array[float] = distinct_values(panes, 0)
	var ys: Array[float] = distinct_values(panes, 1)
	var zs: Array[float] = distinct_values(panes, 2)
	for side: float in [-1.0, 1.0]:
		if not has_value(xs, side * half_x, MM):
			failures.append("interior length: no glass inner face at x = %.4f" % (side * half_x))
		if not has_value(zs, side * half_z, MM):
			failures.append("interior depth: no glass inner face at z = %.4f" % (side * half_z))
		if not has_value(xs, side * (half_x + glass), MM):
			failures.append(
				"exterior length: no glass outer face at x = %.4f" % (side * (half_x + glass))
			)
		if not has_value(zs, side * (half_z + glass), MM):
			failures.append(
				"exterior depth: no glass outer face at z = %.4f" % (side * (half_z + glass))
			)
	if not has_value(ys, 0.0, MM):
		failures.append("interior floor: no glass inner face at y = 0")
	if not has_value(ys, interior.y, MM):
		failures.append("interior height: no glass top at y = %.4f" % interior.y)
	if not has_value(ys, -glass, MM):
		failures.append("exterior base: no glass underside at y = %.4f" % -glass)
	var whole: AABB = scene_bounds(root)
	var footprint: Vector2 = Vector2(interior.x + 2.0 * glass, interior.z + 2.0 * glass)
	if absf(whole.size.x - footprint.x) > MM or absf(whole.size.z - footprint.y) > MM:
		failures.append(
			(
				"exterior footprint: %.4f x %.4f, need %.4f x %.4f"
				% [whole.size.x, whole.size.z, footprint.x, footprint.y]
			)
		)
	if absf(whole.position.y + glass) > MM:
		failures.append("exterior base: lowest y = %.4f, need %.4f" % [whole.position.y, -glass])
	var trim: AABB = bounds_in(frame, root)
	var total_height: float = interior.y + glass + trim_size
	if absf(whole.size.y - total_height) > MM:
		failures.append("exterior height: %.4f, need %.4f" % [whole.size.y, total_height])
	if absf(trim.size.y - trim_size) > MM or absf(trim.position.y - interior.y) > MM:
		failures.append(
			"trim: must be %.3f m tall on the glass rim at y = %.3f" % [trim_size, interior.y]
		)
	if absf(trim.size.x - footprint.x) > MM or absf(trim.size.z - footprint.y) > MM:
		failures.append("trim: must be flush with the outer glass faces")
	var frame_points: PackedVector3Array = vertices_in(frame, root)
	var frame_xs: Array[float] = distinct_values(frame_points, 0)
	var frame_zs: Array[float] = distinct_values(frame_points, 2)
	for side: float in [-1.0, 1.0]:
		if not has_value(frame_xs, side * (footprint.x / 2.0 - trim_size), MM):
			failures.append(
				"trim width: no inner edge at x = %.4f" % (side * (footprint.x / 2.0 - trim_size))
			)
		if not has_value(frame_zs, side * (footprint.y / 2.0 - trim_size), MM):
			failures.append(
				"trim width: no inner edge at z = %.4f" % (side * (footprint.y / 2.0 - trim_size))
			)
	if absf(whole.get_center().x) > MM or absf(whole.get_center().z) > MM:
		failures.append("origin: the footprint is not centred on the inner floor centre")
	return failures
