extends GdUnitTestSuite
## #157 criteria 1, 2, 4, 5 (wrapper part), 14 (data part) and 21 (owner: developer): the three
## starter items in the shipped game/catalog/decor folder, on purpose the real shipped data. The
## generic shipped-data rules (file name = id, files exist, value ranges) stay in
## test_item_catalog_shipped.gd; this file pins what is specific to river_stone, driftwood_branch
## and clay_amphora: the ids, categories, keys, paths, colourable true for clay_amphora only (#32),
## sort order 10, every Mode 2 value of the domain-ba table, the scene wrappers and the six
## translation keys.
##
## Group that makes this file pass: developer (the .tres files, the three .tscn wrappers and
## the .po/.pot entries). The wrappers and the thumbnails need the technical-artist files first
## (the .glb models and the thumbnail PNGs).
##
## The expected values are constants from the issue tables (not read from another group's files),
## so the footprint check here and the size check on the models in test_decor_models.gd together
## give the "bounds match footprint_cm" part of AC 5.
##
## Test decisions where the plan is silent:
## - The scan of AC 4 reads every .gd under res:// except tests/, addons/ and .godot/, and fails
##   on any of the three ids as a quoted string (comments are stripped first).
## - Plant fields at defaults are compared with a fresh ItemDefinition.new().
## - The English and Hungarian names and descriptions are pinned exactly to the strings table of
##   the issue (AC 18 names the Hungarian names; the owner may change a text on the PR preview and
##   then changes this table with it). AC 14 itself only asks for non-empty text.

const SourceScan := preload("res://tests/helpers/source_scan.gd")

const IDS: Array[String] = ["river_stone", "driftwood_branch", "clay_amphora"]
const CATEGORY: Dictionary[String, ItemDefinition.Category] = {
	"river_stone": ItemDefinition.Category.ROCK,
	"driftwood_branch": ItemDefinition.Category.WOOD,
	"clay_amphora": ItemDefinition.Category.ORNAMENT,
}
const PASCAL: Dictionary[String, String] = {
	"river_stone": "RiverStone",
	"driftwood_branch": "DriftwoodBranch",
	"clay_amphora": "ClayAmphora",
}
const FOOTPRINT_CM: Dictionary[String, Vector3] = {
	"river_stone": Vector3(11.0, 6.0, 8.0),
	"driftwood_branch": Vector3(28.0, 8.0, 7.0),
	"clay_amphora": Vector3(9.0, 14.0, 8.0),
}
const MATERIAL: Dictionary[String, ItemDefinition.ItemMaterial] = {
	"river_stone": ItemDefinition.ItemMaterial.STONE,
	"driftwood_branch": ItemDefinition.ItemMaterial.WOOD,
	"clay_amphora": ItemDefinition.ItemMaterial.CERAMIC,
}
const PH_EFFECT: Dictionary[String, ItemDefinition.WaterEffect] = {
	"river_stone": ItemDefinition.WaterEffect.INERT,
	"driftwood_branch": ItemDefinition.WaterEffect.LOWERS_SLIGHTLY,
	"clay_amphora": ItemDefinition.WaterEffect.INERT,
}
## The float fields of the domain-ba table, in the order stone, branch, amphora.
const FLOATS: Dictionary[String, Array] = {
	"weight_kg": [0.80, 0.40, 0.30],
	"volume_displacement_l": [0.30, 0.35, 0.20],
	"tannin_release": [0.0, 0.4, 0.0],
	"hiding_quality": [0.0, 0.0, 0.7],
	"shade_cover": [0.05, 0.1, 0.4],
	"edge_smoothness": [0.9, 0.6, 0.7],
	"flow_obstruction": [0.1, 0.2, 0.2],
	"waste_trapping": [0.15, 0.2, 0.4],
	"cleaning_difficulty": [0.2, 0.4, 0.4],
	"algae_surface": [0.3, 0.5, 0.4],
}
const HIDING_PLACES: Array[int] = [0, 0, 1]
const BREAKS_DOWN: Array[bool] = [false, true, false]
const PLANT_FIELDS: Array[String] = [
	"growth_form",
	"anchoring",
	"light_need",
	"growth_cm_per_week",
	"max_height_cm",
	"temp_min_c",
	"temp_max_c",
	"ph_min",
	"ph_max",
	"nutrient_uptake",
	"oxygen_output",
	"co2_need",
	"substrate_rooting_need",
	"nibble_vulnerability",
	"provides_cover",
]
const EN: Dictionary[String, String] = {
	"item.river_stone.name": "River stone",
	"item.river_stone.description": "A smooth, rounded stone worn by running water.",
	"item.driftwood_branch.name": "Driftwood branch",
	"item.driftwood_branch.description":
	"A curved piece of weathered driftwood with a warm brown grain.",
	"item.clay_amphora.name": "Clay amphora",
	"item.clay_amphora.description":
	"A small two-handled terracotta amphora to rest among the stones.",
}
const HU: Dictionary[String, String] = {
	"item.river_stone.name": "Folyami kő",
	"item.river_stone.description": "Folyóvíz csiszolta, sima, lekerekített kő.",
	"item.driftwood_branch.name": "Uszadékfa ág",
	"item.driftwood_branch.description": "Íves, kopott fadarab meleg barna erezettel.",
	"item.clay_amphora.name": "Agyag amfora",
	"item.clay_amphora.description": "Kis, kétfülű terrakotta amfora a kövek között.",
}
const LOCALIZATION_DIR := "res://localization/"
const SCAN_EXCLUDED: PackedStringArray = ["res://tests/", "res://addons/", "res://.godot/"]
const EPS := 1e-6


func _definition(id: String) -> ItemDefinition:
	var definition: ItemDefinition = ItemCatalog.load_dirs().get_definition(StringName(id))
	assert_object(definition).override_failure_message("catalog has no item %s" % id).is_not_null()
	return definition


# --- AC 1 and 4: the catalog ---


func test_ac01_the_default_catalog_contains_the_three_ids() -> void:
	var ids: Array[StringName] = ItemCatalog.load_dirs().get_ids()
	for id: String in IDS:
		(
			assert_bool(ids.has(StringName(id)))
			. override_failure_message("%s is not in the catalog" % id)
			. is_true()
		)


func test_ac01_nothing_is_skipped_and_each_id_is_valid() -> void:
	var catalog: ItemCatalog = ItemCatalog.load_dirs()
	var reasons: Array[String] = []
	for skipped: ItemCatalog.SkippedItem in catalog.get_skipped():
		reasons.append("%s: %s" % [skipped.source, skipped.reason])
	assert_array(reasons).is_empty()
	for id: String in IDS:
		assert_bool(ItemCatalog.is_valid_id(id)).is_true()


func test_ac04_the_three_tres_files_are_in_the_decor_folder_and_named_after_the_id() -> void:
	var names: PackedStringArray = ResourceLoader.list_directory("res://catalog/decor")
	for id: String in IDS:
		(
			assert_bool(names.has(id + ".tres"))
			. override_failure_message("catalog/decor/%s.tres is missing" % id)
			. is_true()
		)


func test_ac04_no_script_outside_the_tests_hard_codes_one_of_the_ids() -> void:
	var hits: Array[String] = []
	for path: String in SourceScan.list_scripts("res://", SCAN_EXCLUDED):
		var source: String = SourceScan.strip_comments(SourceScan.read(path))
		for id: String in IDS:
			if source.contains('"%s"' % id) or source.contains('&"%s"' % id):
				hits.append("%s: %s" % [path, id])
	assert_array(hits).is_empty()


# --- AC 2: Mode 1 fields ---


func test_ac02_category_keys_paths_colourable_and_sort_order() -> void:
	for id: String in IDS:
		var definition: ItemDefinition = _definition(id)
		if definition == null:
			continue
		assert_int(definition.category).override_failure_message(id).is_equal(CATEGORY[id])
		assert_str(String(definition.id)).is_equal(id)
		assert_str(definition.name_key).is_equal("item.%s.name" % id)
		assert_str(definition.description_key).is_equal("item.%s.description" % id)
		# #32 (owner decision on #157 Q3, option B): only the amphora is colourable.
		assert_bool(definition.colourable).override_failure_message(id).is_equal(
			id == "clay_amphora"
		)
		assert_int(definition.sort_order).override_failure_message(id).is_equal(10)
		assert_object(definition.scene).override_failure_message("%s scene" % id).is_not_null()
		if definition.scene != null:
			assert_str(definition.scene.resource_path).is_equal(
				"res://assets/items/scenes/%s.tscn" % id
			)
		(
			assert_object(definition.thumbnail)
			. override_failure_message("%s thumbnail" % id)
			. is_not_null()
		)
		if definition.thumbnail != null:
			assert_str(definition.thumbnail.resource_path).is_equal(
				"res://assets/items/thumbnails/%s.png" % id
			)


# --- AC 21: Mode 2 ---


func test_ac21_footprint_material_and_water_effects_equal_the_domain_table() -> void:
	for id: String in IDS:
		var definition: ItemDefinition = _definition(id)
		if definition == null:
			continue
		assert_vector(definition.footprint_cm).override_failure_message(id).is_equal_approx(
			FOOTPRINT_CM[id], Vector3(EPS, EPS, EPS)
		)
		assert_int(definition.material).override_failure_message("%s material" % id).is_equal(
			MATERIAL[id]
		)
		assert_int(definition.ph_effect).override_failure_message("%s ph" % id).is_equal(
			PH_EFFECT[id]
		)
		(
			assert_int(definition.hardness_effect)
			. override_failure_message("%s hardness" % id)
			. is_equal(ItemDefinition.WaterEffect.INERT)
		)
		assert_bool(definition.aquarium_safe).override_failure_message(id).is_true()


func test_ac21_every_float_field_equals_the_domain_table() -> void:
	for field: String in FLOATS:
		var values: Array = FLOATS[field]
		for index: int in IDS.size():
			var definition: ItemDefinition = _definition(IDS[index])
			if definition == null:
				continue
			(
				assert_float(float(definition.get(field)))
				. override_failure_message("%s.%s" % [IDS[index], field])
				. is_equal_approx(float(values[index]), EPS)
			)


func test_ac21_hiding_places_and_breaks_down_equal_the_domain_table() -> void:
	for index: int in IDS.size():
		var definition: ItemDefinition = _definition(IDS[index])
		if definition == null:
			continue
		assert_int(definition.hiding_places).override_failure_message(IDS[index]).is_equal(
			HIDING_PLACES[index]
		)
		assert_bool(definition.breaks_down).override_failure_message(IDS[index]).is_equal(
			BREAKS_DOWN[index]
		)


func test_ac21_the_plant_only_fields_stay_at_their_defaults() -> void:
	var defaults: ItemDefinition = ItemDefinition.new()
	for id: String in IDS:
		var definition: ItemDefinition = _definition(id)
		if definition == null:
			continue
		for field: String in PLANT_FIELDS:
			(
				assert_that(definition.get(field))
				. override_failure_message("%s.%s is not the default" % [id, field])
				. is_equal(defaults.get(field))
			)


# --- AC 5: the scene wrappers ---


func _wrapper(id: String) -> Node:
	var path: String = "res://assets/items/scenes/%s.tscn" % id
	var scene: PackedScene = load(path) as PackedScene if ResourceLoader.exists(path) else null
	assert_object(scene).override_failure_message("%s does not load" % path).is_not_null()
	if scene == null:
		return null
	var root: Node = scene.instantiate()
	auto_free(root)
	return root


func test_ac05_each_wrapper_root_is_a_plain_node3d_named_in_pascal_case_without_a_script() -> void:
	for id: String in IDS:
		var root: Node = _wrapper(id)
		if root == null:
			continue
		assert_str(root.get_class()).override_failure_message(id).is_equal("Node3D")
		assert_str(String(root.name)).override_failure_message(id).is_equal(PASCAL[id])
		assert_object(root.get_script()).override_failure_message("%s has a script" % id).is_null()


func test_ac05_each_wrapper_has_the_glb_instance_as_its_only_child() -> void:
	for id: String in IDS:
		var root: Node = _wrapper(id)
		if root == null:
			continue
		assert_int(root.get_child_count()).override_failure_message(id).is_equal(1)
		if root.get_child_count() != 1:
			continue
		assert_str(root.get_child(0).scene_file_path).override_failure_message(id).is_equal(
			"res://assets/items/models/%s.glb" % id
		)


func test_ac05_each_wrapper_has_identity_transforms_and_no_collision_or_bounds_node() -> void:
	for id: String in IDS:
		var root: Node = _wrapper(id)
		if root == null:
			continue
		assert_object(root).is_instanceof(Node3D)
		var top: Node3D = root as Node3D
		if top == null:
			continue
		assert_that(top.transform).override_failure_message("%s root" % id).is_equal(
			Transform3D.IDENTITY
		)
		for child: Node in top.get_children():
			if child is Node3D:
				(
					assert_that((child as Node3D).transform)
					. override_failure_message("%s child %s" % [id, child.name])
					. is_equal(Transform3D.IDENTITY)
				)
		var bad: Array[Node] = top.find_children("*", "CollisionObject3D", true, false)
		bad.append_array(top.find_children("*", "CollisionShape3D", true, false))
		assert_int(bad.size()).override_failure_message("%s has a collision node" % id).is_equal(0)


# --- AC 14: strings (data part) ---


## msgid -> msgstr of one localization file, single-line entries.
func _po_value(file_name: String, key: String) -> String:
	var text: String = FileAccess.get_file_as_string(LOCALIZATION_DIR + file_name)
	var marker: String = 'msgid "%s"\nmsgstr "' % key
	var start: int = text.find(marker)
	if start < 0:
		return "<missing>"
	var from: int = start + marker.length()
	return text.substr(from, text.find('"\n', from) - from)


func test_ac14_the_six_keys_are_in_the_pot() -> void:
	for key: String in EN:
		(
			assert_str(_po_value("messages.pot", key))
			. override_failure_message("%s is missing in messages.pot" % key)
			. is_not_equal("<missing>")
		)


func test_ac14_each_key_has_non_empty_text_in_en_po_and_hu_po() -> void:
	for key: String in EN:
		for file_name: String in ["en.po", "hu.po"]:
			var value: String = _po_value(file_name, key)
			(
				assert_str(value)
				. override_failure_message("%s is missing in %s" % [key, file_name])
				. is_not_equal("<missing>")
			)
			(
				assert_str(value)
				. override_failure_message("%s is empty in %s" % [key, file_name])
				. is_not_empty()
			)
			assert_str(value).override_failure_message("%s is the key" % key).is_not_equal(key)


func test_ac14_the_english_and_hungarian_texts_are_the_ones_of_the_issue_table() -> void:
	for key: String in EN:
		assert_str(_po_value("en.po", key)).override_failure_message(key).is_equal(EN[key])
		assert_str(_po_value("hu.po", key)).override_failure_message(key).is_equal(HU[key])
