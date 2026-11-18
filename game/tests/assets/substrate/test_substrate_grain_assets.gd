# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #28 criterion 37 (owner: technical-artist): the grain meshes of the substrate beds and the
## provenance of every new asset (technical plan v3, sections 3.1 and 6). Three glb files, one per
## stone class (ANGULAR gravel, ROUND coloured gravel, PEBBLE pebbles; sand has no mesh), each with
## at least 3 variants named <class>_v<n>_lod<k>, a strictly decreasing LOD chain within the
## triangle caps, longest extent 1.0 and the origin at the bounds centre (the instance scale is the
## drawn size), unit node scale, no texture, import flags that keep the UV2 layer
## (docs/art-style.md)
## and a licence row for every new file that names the generating script and the Blender version.
## The Blender scripts and their params are committed. check_asset_licenses.py is part of the
## commands of the test report.

const Glb := preload("res://tests/helpers/glb_mesh_checks.gd")
const Checks := preload("res://tests/helpers/proof_fish_checks.gd")
const LfsGuard := preload("res://tests/helpers/lfs_guard.gd")
const Api := preload("res://tests/helpers/substrate_bed_api.gd")
const Geo := preload("res://tests/helpers/substrate_geometry.gd")

const NODE_PATTERN := "^(?<class>[a-z0-9]+)_v(?<variant>\\d+)_lod(?<lod>\\d+)$"
const MIN_VARIANTS := 3
const EXTENT_TOLERANCE := 1e-3
const CENTRE_TOLERANCE := 1e-3
const LICENSES := "res://../docs/asset-licenses.md"
const BLENDER_DIR := "res://../tools/blender/"

## glb file, LOD0 cap, last LOD cap (AC 37).
const CLASSES: Array[Dictionary] = [
	{"file": "grains_angular.glb", "first": 64, "last": 6},
	{"file": "grains_round.glb", "first": 100, "last": 6},
	{"file": "grains_pebble.glb", "first": 640, "last": 80},
]
const BAKE_FILES: Array[String] = [
	"sand.bin",
	"gravel_natural.bin",
	"gravel_coloured.bin",
	"pebbles_river_tank_small_1.bin",
	"pebbles_river_tank_medium_1.bin",
	"pebbles_river_tank_large_1.bin",
]
const LOOK_IDS: Array[String] = [
	"sand_fine", "sand_black", "gravel_natural", "gravel_coloured", "pebbles_river"
]
const SCRIPTS: Array[String] = [
	"bake_substrate.py",
	"substrate_sim.py",
	"substrate_tiles.py",
	"substrate_stones.py",
	"substrate_visibility.py",
	"params/substrate_bake.json",
]


func _path(entry: Dictionary) -> String:
	return "%s/%s" % [Api.GLB_DIR, entry["file"]]


## {"root": Node3D or null, "variants": {number: {lod: {"triangles", "vertices"}}}}; the problem
## text is asserted once.
func _open(entry: Dictionary) -> Dictionary:
	var opened: Dictionary = Glb.open_glb(_path(entry))
	assert_str(String(opened["problem"])).is_empty()
	var root: Node3D = opened["root"]
	var variants: Dictionary = {}
	if root == null:
		return {"root": null, "variants": variants}
	auto_free(root)
	var pattern: RegEx = RegEx.create_from_string(NODE_PATTERN)
	for instance: MeshInstance3D in Glb.mesh_instances(root):
		var found: RegExMatch = pattern.search(String(instance.name))
		(
			assert_object(found)
			. override_failure_message(
				"%s: node %s is not named <class>_v<n>_lod<k>" % [entry["file"], instance.name]
			)
			. is_not_null()
		)
		if found == null:
			continue
		var number: int = int(found.get_string("variant"))
		var by_lod: Dictionary = variants.get(number, {})
		by_lod[int(found.get_string("lod"))] = {
			"triangles": Checks.triangle_count(instance.mesh),
			"vertices": Glb.vertices_in(instance, root),
		}
		variants[number] = by_lod
	return {"root": root, "variants": variants}


func test_ac37_the_three_glb_files_exist_and_are_not_lfs_pointers() -> void:
	for entry: Dictionary in CLASSES:
		assert_str(LfsGuard.problem(_path(entry), LfsGuard.GLB_MAGIC)).is_empty()


func test_ac37_each_class_has_at_least_three_variants() -> void:
	for entry: Dictionary in CLASSES:
		var opened: Dictionary = _open(entry)
		(
			assert_int((opened["variants"] as Dictionary).size())
			. override_failure_message("%s: variants" % entry["file"])
			. is_greater_equal(MIN_VARIANTS)
		)


func test_ac37_every_variant_has_a_strictly_decreasing_lod_chain_of_at_least_two() -> void:
	for entry: Dictionary in CLASSES:
		var variants: Dictionary = _open(entry)["variants"]
		for number: int in variants:
			var by_lod: Dictionary = variants[number]
			var lods: Array = by_lod.keys()
			lods.sort()
			(
				assert_int(lods.size())
				. override_failure_message("%s v%d: LODs" % [entry["file"], number])
				. is_greater_equal(2)
			)
			assert_int(int(lods[0])).override_failure_message("the chain starts at lod0").is_equal(
				0
			)
			var previous: int = 1 << 30
			for lod: int in lods:
				var triangles: int = by_lod[lod]["triangles"]
				(
					assert_int(triangles)
					. override_failure_message(
						(
							"%s v%d lod%d has %d triangles, not fewer than %d"
							% [entry["file"], number, lod, triangles, previous]
						)
					)
					. is_less(previous)
				)
				previous = triangles


func test_ac37_lod0_and_the_last_lod_stay_within_the_triangle_caps() -> void:
	for entry: Dictionary in CLASSES:
		var variants: Dictionary = _open(entry)["variants"]
		for number: int in variants:
			var by_lod: Dictionary = variants[number]
			var lods: Array = by_lod.keys()
			lods.sort()
			if lods.is_empty():
				continue
			var first: int = by_lod[lods[0]]["triangles"]
			var last: int = by_lod[lods[lods.size() - 1]]["triangles"]
			(
				assert_int(first)
				. override_failure_message(
					(
						"%s v%d lod0: %d triangles, cap %d"
						% [entry["file"], number, first, entry["first"]]
					)
				)
				. is_between(1, int(entry["first"]))
			)
			(
				assert_int(last)
				. override_failure_message(
					(
						"%s v%d last lod: %d triangles, cap %d"
						% [entry["file"], number, last, entry["last"]]
					)
				)
				. is_between(1, int(entry["last"]))
			)


func test_ac37_lod0_has_a_longest_extent_of_1_and_the_origin_at_the_bounds_centre() -> void:
	for entry: Dictionary in CLASSES:
		var variants: Dictionary = _open(entry)["variants"]
		for number: int in variants:
			var by_lod: Dictionary = variants[number]
			var lods: Array = by_lod.keys()
			lods.sort()
			if lods.is_empty():
				continue
			var vertices: PackedVector3Array = by_lod[lods[0]]["vertices"]
			(
				assert_float(Geo.longest_extent(vertices))
				. override_failure_message("%s v%d lod0 extent" % [entry["file"], number])
				. is_equal_approx(1.0, EXTENT_TOLERANCE)
			)
			var bounds: AABB = Checks.bounds(vertices)
			(
				assert_float(bounds.get_center().length())
				. override_failure_message(
					"%s v%d lod0 centre %s" % [entry["file"], number, bounds.get_center()]
				)
				. is_less(CENTRE_TOLERANCE)
			)


func test_ac37_no_node_carries_a_baked_scale() -> void:
	for entry: Dictionary in CLASSES:
		var root: Node3D = _open(entry)["root"]
		if root != null:
			assert_str("\n".join(Glb.scale_failures(root))).is_empty()


func test_ac37_every_lod_has_both_uv_layers_and_the_import_keeps_uv2() -> void:
	for entry: Dictionary in CLASSES:
		var root: Node3D = _open(entry)["root"]
		if root == null:
			continue
		(
			assert_str("\n".join(Glb.uv_failures(root)))
			. override_failure_message("%s" % entry["file"])
			. is_empty()
		)
		(
			assert_str("\n".join(Glb.import_failures(_path(entry))))
			. override_failure_message("%s" % entry["file"])
			. is_empty()
		)
		(
			assert_str("\n".join(Glb.texcoord_failures(_path(entry))))
			. override_failure_message("%s" % entry["file"])
			. is_empty()
		)


func test_ac37_the_grain_meshes_carry_no_texture() -> void:
	for entry: Dictionary in CLASSES:
		var root: Node3D = _open(entry)["root"]
		if root == null:
			continue
		for instance: MeshInstance3D in Glb.mesh_instances(root):
			for surface: int in instance.mesh.get_surface_count():
				var material: BaseMaterial3D = (
					instance.mesh.surface_get_material(surface) as BaseMaterial3D
				)
				if material != null:
					(
						assert_object(material.albedo_texture)
						. override_failure_message(
							"%s: %s has an albedo texture" % [entry["file"], instance.name]
						)
						. is_null()
					)


# --- provenance ---


func _licence_rows() -> PackedStringArray:
	return FileAccess.get_file_as_string(LICENSES).split("\n")


func _row_for(path: String) -> String:
	for line: String in _licence_rows():
		if line.begins_with("| `%s`" % path):
			return line
	return ""


func test_ac37_every_new_asset_has_a_licence_row() -> void:
	var paths: Array[String] = []
	for entry: Dictionary in CLASSES:
		paths.append("assets/substrate/%s" % entry["file"])
	for file_name: String in BAKE_FILES:
		paths.append("assets/substrate/bake/%s" % file_name)
	for id: String in LOOK_IDS:
		paths.append("assets/substrate/looks/%s.tres" % id)
	for path: String in paths:
		(
			assert_str(_row_for(path))
			. override_failure_message("docs/asset-licenses.md has no row for %s" % path)
			. is_not_empty()
		)


func test_ac37_the_licence_rows_of_generated_files_name_the_script_the_blender_version_and_command(
) -> void:
	var blender: RegEx = RegEx.create_from_string("Blender\\s+\\d+\\.\\d+")
	for entry: Dictionary in CLASSES:
		var row: String = _row_for("assets/substrate/%s" % entry["file"])
		assert_str(row).contains("tools/blender/substrate_stones.py")
		(
			assert_object(blender.search(row))
			. override_failure_message("%s: the row names no Blender version" % entry["file"])
			. is_not_null()
		)
	for file_name: String in BAKE_FILES:
		var row: String = _row_for("assets/substrate/bake/%s" % file_name)
		assert_str(row).contains("tools/blender/bake_substrate.py")
		assert_str(row).contains("--type")
		(
			assert_object(blender.search(row))
			. override_failure_message("%s: the row names no Blender version" % file_name)
			. is_not_null()
		)


func test_ac37_the_flat_layer_material_has_no_licence_row_any_more() -> void:
	assert_str(_row_for("assets/tank/materials/substrate.tres")).is_empty()


func test_ac37_the_blender_scripts_and_their_params_are_committed() -> void:
	for script_path: String in SCRIPTS:
		(
			assert_bool(FileAccess.file_exists(BLENDER_DIR + script_path))
			. override_failure_message("tools/blender/%s is missing" % script_path)
			. is_true()
		)


func test_ac37_sand_has_no_grain_mesh() -> void:
	for id: StringName in Api.SAND_IDS:
		var look: Resource = Api.look_of(id)
		assert_object(look).override_failure_message("no look for %s" % id).is_not_null()
		if look != null:
			(
				assert_object(look.get("grain_glb"))
				. override_failure_message("%s must have no grain mesh" % id)
				. is_null()
			)


func test_ac37_the_stone_looks_point_at_the_glb_of_their_class() -> void:
	var by_id: Dictionary = {
		"gravel_natural": "grains_angular.glb",
		"gravel_coloured": "grains_round.glb",
		"pebbles_river": "grains_pebble.glb",
	}
	for id: String in by_id:
		var look: Resource = Api.look_of(StringName(id))
		assert_object(look).override_failure_message("no look for %s" % id).is_not_null()
		if look == null:
			continue
		var scene: PackedScene = look.get("grain_glb") as PackedScene
		assert_object(scene).override_failure_message("%s: grain_glb is null" % id).is_not_null()
		if scene != null:
			assert_str(scene.resource_path).is_equal("%s/%s" % [Api.GLB_DIR, by_id[id]])
