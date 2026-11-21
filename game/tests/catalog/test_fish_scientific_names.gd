extends GdUnitTestSuite
## #34 AC 3 (owner: developer): the Latin names are data, never text. None of the three scientific
## names appears in messages.pot, en.po or hu.po (not as msgid, not as msgstr). The names are read
## from the catalog and also pinned to the issue table, so a wrong or empty name fails here too.
## Edge: a name routed through tr() would be found by the same scan; the synthetic case shows it.

const Api := preload("res://tests/helpers/fish_api.gd")

const FILES: PackedStringArray = [
	"res://localization/messages.pot",
	"res://localization/en.po",
	"res://localization/hu.po",
]
const NAMES: Dictionary[StringName, String] = {
	&"neon_tetra": "Paracheirodon innesi",
	&"angelfish": "Pterophyllum scalare",
	&"bronze_corydoras": "Corydoras aeneus",
}


## The names that occur in `text`, case-insensitive; the whole binomial must appear, the genus or
## species word alone does not count.
func _hits(text: String, names: Array) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var lower: String = text.to_lower()
	for latin: String in names:
		if not latin.is_empty() and lower.contains(latin.to_lower()):
			found.append(latin)
	return found


func test_ac03_the_catalog_names_are_the_issue_names() -> void:
	for id: StringName in Api.IDS:
		var latin: String = Api.field(id, "scientific_name", "")
		(
			assert_str(latin)
			. override_failure_message("scientific_name of %s is not %s" % [id, NAMES[id]])
			. is_equal(NAMES[id])
		)


func test_ac03_no_latin_name_is_in_the_pot_or_the_po_files() -> void:
	var names: Array = []
	for id: StringName in Api.IDS:
		names.append(NAMES[id])
		names.append(Api.field(id, "scientific_name", ""))
	for path: String in FILES:
		var text: String = FileAccess.get_file_as_string(path)
		assert_str(text).override_failure_message("%s is empty or missing" % path).is_not_empty()
		(
			assert_array(Array(_hits(text, names)))
			. override_failure_message("%s contains a scientific name" % path)
			. is_empty()
		)


func test_ac03_edge_a_name_as_msgid_or_msgstr_is_found() -> void:
	var as_msgid: String = 'msgid "Corydoras aeneus"\nmsgstr ""\n'
	var as_msgstr: String = 'msgid "fish.x.name"\nmsgstr "Pterophyllum scalare"\n'
	var clean: String = 'msgid "fish.x.name"\nmsgstr "Angelfish"\n'
	var names: Array = NAMES.values()
	assert_int(_hits(as_msgid, names).size()).is_equal(1)
	assert_int(_hits(as_msgstr, names).size()).is_equal(1)
	assert_int(_hits(clean, names).size()).is_equal(0)


func test_ac03_the_scientific_name_field_does_not_end_in_key_so_the_pot_script_ignores_it() -> void:
	var species: Resource = Api.new_species()
	assert_object(species).override_failure_message("FishSpecies is missing").is_not_null()
	if species == null:
		return
	var found: bool = false
	for entry: Dictionary in species.get_property_list():
		if str(entry["name"]) == "scientific_name":
			found = true
	assert_bool(found).is_true()
	assert_bool("scientific_name".ends_with("_key")).is_false()
