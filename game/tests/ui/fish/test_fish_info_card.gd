extends GdUnitTestSuite
## #36 info card (owner: developer): for each shipped species the card shows the common name, the
## Latin name verbatim (never translated, in no .po or .pot), the description, the adult length
## (3 cm, 5.5 cm, 12 cm in English; 5,5 cm in Hungarian) and the zone text. The decimal separator
## follows the game language only (no region test: the BA decision keeps LocalFormat as it is). A
## fixture species of 3.5 cm gives 3.5 cm in English and 3,5 cm in Hungarian; an empty
## scientific_name hides the Latin line; zone UNSET hides the zone row; a non-positive length shows
## the unknown number text; a language switch updates the open card; a fish row adds the fish name.

const Fp := preload("res://tests/helpers/fish_panel_rig.gd")
const Api := preload("res://tests/helpers/fish_api.gd")
const Ui := preload("res://tests/helpers/tank_ui_rig.gd")
const Factory := preload("res://tests/helpers/factory.gd")

const POT := "res://localization/messages.pot"
const LATIN: Dictionary[StringName, String] = {
	&"neon_tetra": "Paracheirodon innesi",
	&"angelfish": "Pterophyllum scalare",
	&"bronze_corydoras": "Corydoras aeneus",
}
const LENGTH_EN: Dictionary[StringName, String] = {
	&"neon_tetra": "3 cm", &"angelfish": "12 cm", &"bronze_corydoras": "5.5 cm"
}
const LENGTH_HU: Dictionary[StringName, String] = {
	&"neon_tetra": "3 cm", &"angelfish": "12 cm", &"bronze_corydoras": "5,5 cm"
}
const ZONE_KEY: Dictionary[StringName, String] = {
	&"neon_tetra": "fish.zone.middle",
	&"angelfish": "fish.zone.middle",
	&"bronze_corydoras": "fish.zone.bottom",
}

var _saved_locale: String = ""
var _language_state: Dictionary = {}
var _model: AquariumModel = null
var _panel: Control = null


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()
	_language_state = Ui.begin_language_isolation("fish_info_card")
	TranslationServer.set_locale("en")
	_model = Fp.model_with_tank()


func after_test() -> void:
	Ui.end_language_isolation(_language_state, _saved_locale)


func _open(species: RefCounted = null) -> bool:
	_panel = await Fp.open_panel_alone(
		self, _model, CommandHistory.new(), species, UidGenerator.new(2), Fp.seeded_rng()
	)
	assert_object(_panel).override_failure_message("fish_panel.tscn is missing").is_not_null()
	if _panel == null:
		return false
	auto_free(_panel)
	return Fp.card(_panel) != null


func _text(node_name: String) -> String:
	return Fp.shown(Fp.label(_panel, node_name))


func _length() -> String:
	return Fp.shown(Fp.label(_panel, "LengthValue"))


func _zone() -> String:
	return Fp.shown(Fp.label(_panel, "ZoneValue"))


func test_36_each_shipped_species_card_shows_every_field_in_english() -> void:
	if not await _open():
		return
	for id: StringName in Api.IDS:
		await Fp.select_species(self, _panel, id)
		assert_str(_text("CommonNameLabel")).is_equal(tr("fish.%s.name" % id))
		assert_str(_text("LatinLabel")).is_equal(LATIN[id])
		assert_str(_text("DescriptionLabel")).is_equal(tr("fish.%s.description" % id))
		assert_str(Fp.shown(Fp.label(_panel, "LengthCaption"))).is_equal("Adult length")
		assert_str(_length()).is_equal(LENGTH_EN[id])
		assert_str(Fp.shown(Fp.label(_panel, "ZoneCaption"))).is_equal("Swims in")
		assert_str(_zone()).is_equal(tr(ZONE_KEY[id]))
		assert_bool(Fp.visible_in_tree(Fp.card(_panel))).is_true()


func test_36_the_card_reads_hungarian_after_a_switch_and_the_length_uses_a_comma() -> void:
	if not await _open():
		return
	await Fp.select_species(self, _panel, Api.CORY)
	await Ui.set_language(self, "hu")
	assert_str(_text("CommonNameLabel")).is_equal("Bronz páncélosharcsa")
	assert_str(_length()).is_equal("5,5 cm")
	assert_str(Fp.shown(Fp.label(_panel, "LengthCaption"))).is_equal("Kifejlett hossz")
	assert_str(Fp.shown(Fp.label(_panel, "ZoneCaption"))).is_equal("Itt úszik")
	assert_str(_zone()).is_equal("A fenék közelében")
	assert_str(_text("LatinLabel")).is_equal("Corydoras aeneus")
	for id: StringName in Api.IDS:
		await Fp.select_species(self, _panel, id)
		assert_str(_length()).is_equal(LENGTH_HU[id])


func test_36_the_card_updates_without_reopening_when_the_language_changes() -> void:
	if not await _open():
		return
	await Fp.select_species(self, _panel, Api.ANGEL)
	assert_str(_text("CommonNameLabel")).is_equal("Angelfish")
	await Ui.set_language(self, "hu")
	assert_str(_text("CommonNameLabel")).is_equal("Vitorláshal")
	assert_str(_zone()).is_equal("Középső vízréteg")
	await Ui.set_language(self, "en")
	assert_str(_text("CommonNameLabel")).is_equal("Angelfish")
	assert_str(_zone()).is_equal("Middle water")


func test_36_a_3_5_cm_species_reads_3_5_in_english_and_3_comma_5_in_hungarian() -> void:
	var fixture: FishSpecies = Fp.species_fixture(&"tiny_test", 3.5, FishSpecies.Zone.TOP)
	var catalog: RefCounted = Fp.catalog_of([fixture])
	if catalog == null or not await _open(catalog):
		return
	assert_str(_length()).is_equal("3.5 cm")
	await Ui.set_language(self, "hu")
	assert_str(_length()).is_equal("3,5 cm")


func test_36_a_length_with_a_long_tail_rounds_to_one_decimal_and_whole_values_have_none() -> void:
	var fixtures: Array = [
		Fp.species_fixture(&"aa_a", 3.04, FishSpecies.Zone.TOP),
		Fp.species_fixture(&"aa_b", 3.96, FishSpecies.Zone.TOP),
		Fp.species_fixture(&"aa_c", 12.0, FishSpecies.Zone.TOP),
	]
	var catalog: RefCounted = Fp.catalog_of(fixtures)
	if catalog == null or not await _open(catalog):
		return
	await Fp.select_species(self, _panel, &"aa_a")
	assert_str(_length()).is_equal("3 cm")
	await Fp.select_species(self, _panel, &"aa_b")
	assert_str(_length()).is_equal("4 cm")
	await Fp.select_species(self, _panel, &"aa_c")
	assert_str(_length()).is_equal("12 cm")


func test_36_a_length_that_is_not_positive_shows_the_unknown_number_text() -> void:
	var fixtures: Array = [
		Fp.species_fixture(&"aa_zero", 0.0, FishSpecies.Zone.TOP),
		Fp.species_fixture(&"aa_negative", -2.0, FishSpecies.Zone.TOP),
	]
	var catalog: RefCounted = Fp.catalog_of(fixtures)
	if catalog == null or not await _open(catalog):
		return
	for id: StringName in [&"aa_zero", &"aa_negative"]:
		await Fp.select_species(self, _panel, id)
		assert_str(_length()).is_equal(tr("number.unknown"))


func test_36_an_empty_scientific_name_hides_the_latin_line() -> void:
	var fixture: FishSpecies = Fp.species_fixture(&"no_latin", 4.0, FishSpecies.Zone.TOP, "")
	var catalog: RefCounted = Fp.catalog_of([fixture])
	if catalog == null or not await _open(catalog):
		return
	assert_bool(Fp.visible_in_tree(Fp.label(_panel, "LatinLabel"))).is_false()
	assert_bool(Fp.visible_in_tree(Fp.label(_panel, "CommonNameLabel"))).is_true()


func test_36_an_unset_zone_hides_the_zone_row_and_the_other_zones_show_it() -> void:
	var fixtures: Array = [
		Fp.species_fixture(&"aa_unset", 4.0, FishSpecies.Zone.UNSET),
		Fp.species_fixture(&"aa_top", 4.0, FishSpecies.Zone.TOP),
		Fp.species_fixture(&"aa_mid", 4.0, FishSpecies.Zone.MIDDLE),
		Fp.species_fixture(&"aa_bottom", 4.0, FishSpecies.Zone.BOTTOM),
	]
	var catalog: RefCounted = Fp.catalog_of(fixtures)
	if catalog == null or not await _open(catalog):
		return
	var row: Control = Fp.control(_panel, "ZoneRow")
	assert_object(row).is_not_null()
	await Fp.select_species(self, _panel, &"aa_unset")
	assert_bool(Fp.visible_in_tree(row)).is_false()
	await Fp.select_species(self, _panel, &"aa_top")
	assert_bool(Fp.visible_in_tree(row)).is_true()
	assert_str(_zone()).is_equal("Upper water")
	await Fp.select_species(self, _panel, &"aa_mid")
	assert_str(_zone()).is_equal("Middle water")
	await Fp.select_species(self, _panel, &"aa_bottom")
	assert_str(_zone()).is_equal("Near the bottom")


func test_36_a_fish_row_adds_the_fish_name_above_the_species_data() -> void:
	_model.apply_insert_fish(Factory.fish("f1000001", &"angelfish", 0, "Nemo"), 0)
	_model.apply_insert_fish(Factory.fish("f1000002", &"neon_tetra", 0, ""), 1)
	if not await _open():
		return
	var name_label: Label = Fp.label(_panel, "FishNameLabel")
	assert_object(name_label).is_not_null()
	await Fp.click(self, Fp.name_button(_panel, "f1000001"))
	assert_bool(Fp.visible_in_tree(name_label)).is_true()
	assert_str(Fp.shown(name_label)).is_equal("Nemo")
	(
		assert_bool(
			(
				name_label.get_global_rect().position.y
				< Fp.label(_panel, "CommonNameLabel").get_global_rect().position.y
			)
		)
		. is_true()
	)
	await Fp.click(self, Fp.name_button(_panel, "f1000002"))
	assert_str(Fp.shown(name_label)).is_equal(tr("fish.default_name.%02d" % _derived("f1000002")))


func _derived(uid: String) -> int:
	var unit: float = Api.expected_unit(uid, "fish.name.default")
	return mini(floori(unit * 30.0), 29) + 1


func test_36_the_latin_names_are_in_no_translation_file() -> void:
	for path: String in [POT, "res://localization/en.po", "res://localization/hu.po"]:
		var text: String = FileAccess.get_file_as_string(path)
		for latin: String in LATIN.values():
			(
				assert_bool(text.contains(latin))
				. override_failure_message("%s holds %s" % [path, latin])
				. is_false()
			)


func test_36_the_card_shows_no_mode_2_text() -> void:
	if not await _open():
		return
	for id: StringName in Api.IDS:
		await Fp.select_species(self, _panel, id)
		for node: Node in Fp.card(_panel).find_children("*", "Label", true, false):
			var text: String = Fp.shown(node as Label).to_lower()
			for word: String in ["temperature", "°c", "litre", "hőmérséklet"]:
				(
					assert_bool(text.contains(word))
					. override_failure_message("%s shows %s" % [node.name, word])
					. is_false()
				)
