extends GdUnitTestSuite
## #152 criterion 12 (owner: developer): the data test of the shipped items in game/catalog/decor
## and game/catalog/plants. The loader enforces none of these value checks, so a bad Mode 2 value
## never hides an item from the player; this test is what fails in CI. With today's empty folders
## it checks nothing and passes; it starts to bite when #41 and #42 add items. The checks live in
## _problems(), which the last tests run on built definitions, so a rule that stops biting fails.

const Items := preload("res://tests/helpers/item_api.gd")
const SCENE_DIR := "res://assets/items/scenes"
const THUMBNAIL_DIR := "res://assets/items/thumbnails"
const PO_FILES: Array[String] = ["res://localization/en.po", "res://localization/hu.po"]
## UI keys of the `item` area; no shipped id may equal one of these subjects (plan, section 4.2).
const RESERVED_SUBJECTS: Array[String] = ["browser", "category"]
const UNIT_RANGE: Array[String] = [
	"tannin_release",
	"hiding_quality",
	"shade_cover",
	"edge_smoothness",
	"flow_obstruction",
	"waste_trapping",
	"cleaning_difficulty",
	"algae_surface",
	"nutrient_uptake",
	"oxygen_output",
	"co2_need",
	"substrate_rooting_need",
	"nibble_vulnerability",
]
const NOT_NEGATIVE: Array[String] = [
	"weight_kg",
	"volume_displacement_l",
	"hiding_places",
	"growth_cm_per_week",
	"max_height_cm",
]
const ENUM_FIELDS: Dictionary = {
	"category": "Category",
	"material": "ItemMaterial",
	"ph_effect": "WaterEffect",
	"hardness_effect": "WaterEffect",
	"growth_form": "GrowthForm",
	"anchoring": "Anchoring",
	"light_need": "LightNeed",
}
## Category member -> the ItemMaterial members that fit it.
const MATERIALS: Dictionary = {
	"ROCK": ["STONE"],
	"WOOD": ["WOOD"],
	"ORNAMENT": ["CERAMIC", "RESIN", "SHELL"],
	"PLANT": ["LIVE_PLANT"],
}


func _have_classes() -> bool:
	var ok: bool = (
		Items.script_exists(Items.DEFINITION_PATH) and Items.script_exists(Items.CATALOG_PATH)
	)
	assert_bool(ok).override_failure_message("ItemDefinition or ItemCatalog is missing").is_true()
	return ok


# --- helpers ---


func _e(enum_name: String, member: String) -> int:
	return Items.enum_value(enum_name, member)


## msgid -> msgstr of one .po file, as {key: text}; an empty text is kept as an empty string.
func _po(path: String) -> Dictionary:
	var entries: Dictionary = {}
	var key: String = ""
	var text: String = ""
	var mode: String = ""
	for line: String in FileAccess.get_file_as_string(path).split("\n"):
		var stripped: String = line.strip_edges()
		if stripped.begins_with("msgid "):
			if mode == "str" and not key.is_empty():
				entries[key] = text
			key = _unquote(stripped.trim_prefix("msgid "))
			text = ""
			mode = "id"
		elif stripped.begins_with("msgstr "):
			text = _unquote(stripped.trim_prefix("msgstr "))
			mode = "str"
		elif stripped.begins_with('"'):
			if mode == "id":
				key += _unquote(stripped)
			elif mode == "str":
				text += _unquote(stripped)
	if mode == "str" and not key.is_empty():
		entries[key] = text
	return entries


func _unquote(quoted: String) -> String:
	return quoted.trim_prefix('"').trim_suffix('"')


func _po_files() -> Dictionary:
	var result: Dictionary = {}
	for path: String in PO_FILES:
		result[path] = _po(path)
	return result


func _base_names(dir: String) -> Array[String]:
	var names: Array[String] = []
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".tres"):
			names.append(file.trim_suffix(".tres"))
	return names


## Every rule of the criterion applied to one definition; returns the broken rules as texts.
func _problems(definition: Resource, folder: String, po_files: Dictionary) -> Array[String]:
	var found: Array[String] = []
	var id: String = String(definition.get("id"))
	var category: int = definition.get("category")
	var is_plant: bool = category == _e("Category", "PLANT")
	if not definition.get("aquarium_safe"):
		found.append("aquarium_safe is false")
	if Items.is_valid_id(id) != true:
		found.append("id breaks the item-id rule")
	if RESERVED_SUBJECTS.has(id):
		found.append("id is a reserved key subject")
	_scene_problems(definition, id, found)
	_key_problems(definition, id, po_files, found)
	if folder == "plants" and not is_plant:
		found.append("plants/ holds a non-plant")
	if folder == "decor" and is_plant:
		found.append("decor/ holds a plant")
	_material_problems(definition, category, found)
	_value_problems(definition, category, found)
	if is_plant:
		_plant_problems(definition, found)
	else:
		_non_plant_problems(definition, category, found)
	return found


func _scene_problems(definition: Resource, id: String, found: Array[String]) -> void:
	var scene: Variant = definition.get("scene")
	if scene == null:
		found.append("scene is not set")
	elif not scene is PackedScene:
		found.append("scene is not a PackedScene")
	elif (scene as Resource).resource_path != "%s/%s.tscn" % [SCENE_DIR, id]:
		found.append("scene is not %s/%s.tscn" % [SCENE_DIR, id])
	var thumbnail: Variant = definition.get("thumbnail")
	if (
		thumbnail != null
		and (thumbnail as Resource).resource_path != "%s/%s.png" % [THUMBNAIL_DIR, id]
	):
		found.append("thumbnail is not %s/%s.png" % [THUMBNAIL_DIR, id])


func _key_problems(
	definition: Resource, id: String, po_files: Dictionary, found: Array[String]
) -> void:
	var name_key: String = definition.get("name_key")
	var description_key: String = definition.get("description_key")
	if name_key != "item.%s.name" % id:
		found.append("name_key is not item.%s.name" % id)
	if description_key != "item.%s.description" % id:
		found.append("description_key is not item.%s.description" % id)
	for path: String in po_files:
		var entries: Dictionary = po_files[path]
		for key: String in [name_key, description_key]:
			if String(entries.get(key, "")).is_empty():
				found.append("%s has no text for %s" % [path, key])
		var prefix: String = "item.%s." % id
		for key: Variant in entries:
			var text: String = String(key)
			var allowed: bool = text == prefix + "name" or text == prefix + "description"
			if text.begins_with(prefix) and not allowed:
				found.append("%s has the foreign key %s under an item id" % [path, text])


func _material_problems(definition: Resource, category: int, found: Array[String]) -> void:
	var material: int = definition.get("material")
	if material == _e("ItemMaterial", "UNSET"):
		found.append("material is not set")
	for member: String in MATERIALS:
		if category == _e("Category", member):
			var fits: bool = false
			for material_name: String in MATERIALS[member]:
				fits = fits or material == _e("ItemMaterial", material_name)
			if not fits:
				found.append("material %d does not fit category %s" % [material, member])
	var colourable: bool = definition.get("colourable")
	if colourable:
		var allowed: bool = (
			category == _e("Category", "ORNAMENT")
			and (
				material == _e("ItemMaterial", "CERAMIC") or material == _e("ItemMaterial", "RESIN")
			)
		)
		if not allowed:
			found.append("colourable is true for something that is not a ceramic or resin ornament")


func _value_problems(definition: Resource, category: int, found: Array[String]) -> void:
	for field: String in UNIT_RANGE:
		var value: float = definition.get(field)
		if value < 0.0 or value > 1.0:
			found.append("%s is outside 0..1" % field)
	for field: String in NOT_NEGATIVE:
		if float(definition.get(field)) < 0.0:
			found.append("%s is negative" % field)
	var footprint: Vector3 = definition.get("footprint_cm")
	if footprint.x < 0.0 or footprint.y < 0.0 or footprint.z < 0.0:
		found.append("footprint_cm has a negative part")
	if footprint.x <= 0.0 or footprint.y <= 0.0 or footprint.z <= 0.0:
		found.append("footprint_cm has a part that is not above 0")
	for field: String in ENUM_FIELDS:
		var values: Array = Items.ENUMS[ENUM_FIELDS[field]].values()
		if not values.has(int(definition.get(field))):
			found.append("%s is not a defined %s value" % [field, ENUM_FIELDS[field]])
	var needs_weight: bool = (
		category == _e("Category", "ROCK")
		or category == _e("Category", "WOOD")
		or category == _e("Category", "ORNAMENT")
	)
	if needs_weight and float(definition.get("weight_kg")) <= 0.0:
		found.append("weight_kg is not above 0")


func _plant_problems(definition: Resource, found: Array[String]) -> void:
	var growth_form: int = definition.get("growth_form")
	var anchoring: int = definition.get("anchoring")
	for field: String in ["growth_form", "anchoring", "light_need"]:
		if int(definition.get(field)) == 0:
			found.append("%s is UNSET" % field)
	var t_min: float = definition.get("temp_min_c")
	var t_max: float = definition.get("temp_max_c")
	if t_min > t_max or t_min < 5.0 or t_max > 35.0 or t_max < 5.0 or t_min > 35.0:
		found.append("temperature range %s..%s is not within 5..35" % [t_min, t_max])
	var ph_min: float = definition.get("ph_min")
	var ph_max: float = definition.get("ph_max")
	if ph_min > ph_max or ph_min < 4.0 or ph_max > 9.5 or ph_max < 4.0 or ph_min > 9.5:
		found.append("pH range %s..%s is not within 4.0..9.5" % [ph_min, ph_max])
	var floating_form: bool = growth_form == _e("GrowthForm", "FLOATING")
	var floating_anchor: bool = anchoring == _e("Anchoring", "FLOATING")
	if floating_form != floating_anchor:
		found.append("growth_form FLOATING and anchoring FLOATING do not go together")
	var rooting: float = definition.get("substrate_rooting_need")
	var free: bool = (
		anchoring == _e("Anchoring", "FLOATING")
		or anchoring == _e("Anchoring", "LOOSE")
		or anchoring == _e("Anchoring", "EPIPHYTE")
	)
	if free and rooting != 0.0:
		found.append("substrate_rooting_need is not 0 for a plant that is not rooted")
	if anchoring == _e("Anchoring", "ROOTED") and rooting <= 0.0:
		found.append("substrate_rooting_need is not above 0 for a rooted plant")


func _non_plant_problems(definition: Resource, category: int, found: Array[String]) -> void:
	var fresh: Resource = Items.new_definition()
	for field: String in Items.PLANT:
		if definition.get(field) != fresh.get(field):
			found.append("plant field %s is not at its default" % field)
	if float(definition.get("tannin_release")) > 0.0 and category != _e("Category", "WOOD"):
		found.append("tannin_release is above 0 for something that is not wood")


# --- the shipped data ---


func test_ac12_the_classes_exist() -> void:
	_have_classes()


func test_ac12_nothing_shipped_is_skipped() -> void:
	if not _have_classes():
		return
	var cat: RefCounted = Items.load_default_dirs()
	assert_bool(Items.has_api(cat)).is_true()
	(
		assert_array(Items.skipped(cat))
		. override_failure_message("a shipped item is skipped: %s" % str(Items.skipped(cat)))
		. is_empty()
	)


func test_ac12_each_shipped_folder_holds_only_tres_files_and_gitkeep() -> void:
	for folder: String in Items.SHIPPED_DIRS:
		(
			assert_array(DirAccess.get_directories_at(folder))
			. override_failure_message("%s has a subfolder the loader ignores" % folder)
			. is_empty()
		)
		for file: String in DirAccess.get_files_at(folder):
			var allowed: bool = file.ends_with(".tres") or file == ".gitkeep"
			assert_bool(allowed).override_failure_message("%s/%s" % [folder, file]).is_true()


func test_ac12_every_id_equals_the_file_base_name_and_every_file_loads() -> void:
	if not _have_classes():
		return
	var cat: RefCounted = Items.load_default_dirs()
	var loaded: Array[String] = Items.ids(cat)
	var files: Array[String] = []
	for dir: String in Items.SHIPPED_DIRS:
		files.append_array(_base_names(dir))
	files.sort()
	var sorted_ids: Array[String] = loaded.duplicate()
	sorted_ids.sort()
	assert_array(sorted_ids).override_failure_message("ids differ from file base names").is_equal(
		files
	)


func test_ac12_every_shipped_item_passes_every_check() -> void:
	if not _have_classes():
		return
	var cat: RefCounted = Items.load_default_dirs()
	var po_files: Dictionary = _po_files()
	var report: Array[String] = []
	for dir: String in Items.SHIPPED_DIRS:
		var folder: String = dir.get_file()
		for id: String in _base_names(dir):
			var definition: Resource = Items.definition(cat, StringName(id))
			if definition == null:
				report.append("%s: not in the catalog" % id)
				continue
			for problem: String in _problems(definition, folder, po_files):
				report.append("%s: %s" % [id, problem])
	assert_array(report).override_failure_message("\n".join(report)).is_empty()


# --- the checks themselves bite (built definitions, no shipped data needed) ---


func _good_rock() -> Resource:
	var rock: Resource = Items.make("rock_ok", _e("Category", "ROCK"))
	rock.set("description_key", "item.rock_ok.description")
	rock.set("material", _e("ItemMaterial", "STONE"))
	rock.set("weight_kg", 2.0)
	rock.set("footprint_cm", Vector3(10, 5, 8))
	return rock


func _good_plant() -> Resource:
	var plant: Resource = Items.make("plant_ok", _e("Category", "PLANT"))
	plant.set("description_key", "item.plant_ok.description")
	plant.set("material", _e("ItemMaterial", "LIVE_PLANT"))
	plant.set("footprint_cm", Vector3(10, 20, 10))
	plant.set("growth_form", _e("GrowthForm", "STEM"))
	plant.set("anchoring", _e("Anchoring", "ROOTED"))
	plant.set("light_need", _e("LightNeed", "LOW"))
	plant.set("temp_min_c", 20.0)
	plant.set("temp_max_c", 28.0)
	plant.set("ph_min", 6.0)
	plant.set("ph_max", 7.5)
	plant.set("substrate_rooting_need", 0.5)
	return plant


## The po stand-in that has both keys of the id, so only the data fields are tested.
func _po_for(id: String) -> Dictionary:
	var entries: Dictionary = {
		"item.%s.name" % id: "Name", "item.%s.description" % id: "Description"
	}
	return {"fixture.po": entries}


func _complaints(definition: Resource, folder: String = "decor") -> Array[String]:
	return _problems(definition, folder, _po_for(String(definition.get("id"))))


func _has_complaint(complaints: Array[String], part: String) -> bool:
	for text: String in complaints:
		if text.contains(part):
			return true
	return false


func test_ac12_the_check_accepts_a_complete_rock_and_plant_except_the_scene() -> void:
	if not _have_classes():
		return
	for definition: Resource in [_good_rock(), _good_plant()]:
		var folder: String = "plants" if definition.get("id") == &"plant_ok" else "decor"
		var complaints: Array[String] = _complaints(definition, folder)
		assert_array(complaints).is_equal(["scene is not set"])


func test_ac12_the_check_finds_each_broken_rule() -> void:
	if not _have_classes():
		return
	var cases: Array = []
	var unit: Resource = _good_rock()
	unit.set("shade_cover", 1.2)
	cases.append([unit, "decor", "shade_cover is outside 0..1"])
	var negative: Resource = _good_rock()
	negative.set("hiding_places", -1)
	cases.append([negative, "decor", "hiding_places is negative"])
	var heavy: Resource = _good_rock()
	heavy.set("weight_kg", 0.0)
	cases.append([heavy, "decor", "weight_kg is not above 0"])
	var flat: Resource = _good_rock()
	flat.set("footprint_cm", Vector3(10, 0, 8))
	cases.append([flat, "decor", "footprint_cm has a part that is not above 0"])
	var wrong_material: Resource = _good_rock()
	wrong_material.set("material", _e("ItemMaterial", "WOOD"))
	cases.append([wrong_material, "decor", "does not fit category ROCK"])
	var colour: Resource = _good_rock()
	colour.set("colourable", true)
	cases.append([colour, "decor", "colourable is true"])
	var growing_rock: Resource = _good_rock()
	growing_rock.set("growth_form", _e("GrowthForm", "MOSS"))
	cases.append([growing_rock, "decor", "plant field growth_form"])
	var tannin: Resource = _good_rock()
	tannin.set("tannin_release", 0.3)
	cases.append([tannin, "decor", "tannin_release is above 0"])
	var misplaced: Resource = _good_rock()
	cases.append([misplaced, "plants", "plants/ holds a non-plant"])
	var wrong_key: Resource = _good_rock()
	wrong_key.set("name_key", "decor.rock_ok.name")
	cases.append([wrong_key, "decor", "name_key is not item.rock_ok.name"])
	var unsafe: Resource = _good_rock()
	unsafe.set("aquarium_safe", false)
	cases.append([unsafe, "decor", "aquarium_safe is false"])
	var reserved: Resource = _good_rock()
	reserved.set("id", &"browser")
	reserved.set("name_key", "item.browser.name")
	reserved.set("description_key", "item.browser.description")
	cases.append([reserved, "decor", "reserved key subject"])
	for entry: Array in cases:
		var complaints: Array[String] = _complaints(entry[0], entry[1])
		(
			assert_bool(_has_complaint(complaints, entry[2]))
			. override_failure_message("no complaint '%s' in %s" % [entry[2], str(complaints)])
			. is_true()
		)


func test_ac12_the_check_finds_each_broken_plant_rule() -> void:
	if not _have_classes():
		return
	var checks: Array = [
		["growth_form", _e("GrowthForm", "UNSET"), "growth_form is UNSET"],
		["light_need", _e("LightNeed", "UNSET"), "light_need is UNSET"],
		["temp_min_c", 30.0, "temperature range"],
		["temp_max_c", 40.0, "temperature range"],
		["ph_min", 8.0, "pH range"],
		["ph_max", 10.0, "pH range"],
		["anchoring", _e("Anchoring", "FLOATING"), "do not go together"],
		["growth_form", _e("GrowthForm", "FLOATING"), "do not go together"],
		["substrate_rooting_need", 0.0, "not above 0 for a rooted plant"],
		["footprint_cm", Vector3.ZERO, "footprint_cm has a part that is not above 0"],
	]
	for check: Array in checks:
		var plant: Resource = _good_plant()
		plant.set(check[0], check[1])
		var complaints: Array[String] = _complaints(plant, "plants")
		(
			assert_bool(_has_complaint(complaints, check[2]))
			. override_failure_message(
				"%s = %s: no complaint '%s' in %s" % [check[0], check[1], check[2], str(complaints)]
			)
			. is_true()
		)


func test_ac12_a_plant_that_is_not_rooted_must_not_need_a_substrate() -> void:
	if not _have_classes():
		return
	for member: String in ["LOOSE", "EPIPHYTE"]:
		var plant: Resource = _good_plant()
		plant.set("anchoring", _e("Anchoring", member))
		var complaints: Array[String] = _complaints(plant, "plants")
		assert_bool(_has_complaint(complaints, "not 0 for a plant that is not rooted")).is_true()
		plant.set("substrate_rooting_need", 0.0)
		assert_bool(_has_complaint(_complaints(plant, "plants"), "rooting")).is_false()


func test_ac12_a_plant_in_decor_and_a_missing_po_text_are_found() -> void:
	if not _have_classes():
		return
	var plant: Resource = _good_plant()
	assert_bool(_has_complaint(_complaints(plant, "decor"), "decor/ holds a plant")).is_true()
	var empty_text: Dictionary = {"fixture.po": {"item.plant_ok.name": "", "item.plant_ok.x": "y"}}
	var complaints: Array[String] = _problems(plant, "plants", empty_text)
	assert_bool(_has_complaint(complaints, "has no text for item.plant_ok.name")).is_true()
	assert_bool(_has_complaint(complaints, "has no text for item.plant_ok.description")).is_true()
	assert_bool(_has_complaint(complaints, "foreign key item.plant_ok.x")).is_true()
