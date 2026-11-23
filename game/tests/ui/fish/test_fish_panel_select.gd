extends GdUnitTestSuite
## #36 selection (owner: developer, BA decision Q3): the first catalog species is preselected and
## listed in catalog order; selecting a species button changes what Add uses and clears the shown
## fish; selecting a fish row shows that fish on the card and does not change the Add species. A
## catalog with zero species gives an empty list, a hidden card, a disabled Add button and no
## crash. A fish of an unknown species lists with "Unknown species", shows the card placeholder
## and can be removed.

const Fp := preload("res://tests/helpers/fish_panel_rig.gd")
const Api := preload("res://tests/helpers/fish_api.gd")
const Ui := preload("res://tests/helpers/tank_ui_rig.gd")
const Factory := preload("res://tests/helpers/factory.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")

const A := "f0000001"
const B := "f0000002"

var _saved_locale: String = ""
var _language_state: Dictionary = {}
var _model: AquariumModel = null
var _history: CommandHistory = null
var _panel: Control = null


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()
	_language_state = Ui.begin_language_isolation("fish_panel_select")
	TranslationServer.set_locale("en")
	_model = Fp.model_with_tank()
	_history = CommandHistory.new()


func after_test() -> void:
	Ui.end_language_isolation(_language_state, _saved_locale)


func _open(species: RefCounted = null) -> bool:
	_panel = await Fp.open_panel_alone(
		self, _model, _history, species, UidGenerator.new(4), Fp.seeded_rng()
	)
	assert_object(_panel).override_failure_message("fish_panel.tscn is missing").is_not_null()
	if _panel == null:
		return false
	auto_free(_panel)
	return true


func test_36_the_species_list_follows_the_catalog_order_and_the_first_is_selected() -> void:
	if not await _open():
		return
	var ids: Array[String] = []
	for id: StringName in Api.shipped().call("get_ids"):
		ids.append(String(id))
	assert_array(Fp.species_ids(_panel)).is_equal(ids)
	assert_str(Fp.selected_species(_panel)).is_equal(ids[0])


func test_36_the_species_buttons_show_the_translated_name_and_description_tooltip() -> void:
	if not await _open():
		return
	for id: StringName in Api.IDS:
		var button: Button = Fp.species_button(_panel, id)
		assert_object(button).is_not_null()
		assert_str(Fp.shown(button)).is_equal(tr("fish.%s.name" % id))
		assert_str(Fp.tooltip_of(button)).is_equal(tr("fish.%s.description" % id))


func test_36_pressing_a_species_changes_what_add_uses() -> void:
	if not await _open():
		return
	await Fp.select_species(self, _panel, Api.NEON)
	await Fp.click(self, Fp.add_button(_panel))
	assert_str(String(_model.get_fish_at(0).species_id)).is_equal("neon_tetra")
	await Fp.select_species(self, _panel, Api.CORY)
	assert_str(Fp.selected_species(_panel)).is_equal("bronze_corydoras")
	await Fp.click(self, Fp.add_button(_panel))
	assert_str(String(_model.get_fish_at(1).species_id)).is_equal("bronze_corydoras")


func test_36_selecting_a_fish_row_shows_the_fish_and_keeps_the_add_species() -> void:
	_model.apply_insert_fish(Factory.fish(A, &"angelfish", 0, "Angel"), 0)
	if not await _open():
		return
	await Fp.select_species(self, _panel, Api.NEON)
	await Fp.click(self, Fp.name_button(_panel, A))
	assert_str(Fp.shown_fish(_panel)).is_equal(A)
	assert_str(Fp.selected_species(_panel)).is_equal("neon_tetra")
	assert_bool(Fp.visible_in_tree(Fp.label(_panel, "FishNameLabel"))).is_true()
	assert_str(Fp.shown(Fp.label(_panel, "CommonNameLabel"))).is_equal(tr("fish.angelfish.name"))
	await Fp.click(self, Fp.add_button(_panel))
	assert_str(String(_model.get_fish_at(1).species_id)).is_equal("neon_tetra")


func test_36_selecting_a_species_clears_the_shown_fish() -> void:
	_model.apply_insert_fish(Factory.fish(A, &"angelfish", 0, "Angel"), 0)
	if not await _open():
		return
	await Fp.click(self, Fp.name_button(_panel, A))
	assert_str(Fp.shown_fish(_panel)).is_equal(A)
	await Fp.select_species(self, _panel, Api.CORY)
	assert_str(Fp.shown_fish(_panel)).is_empty()
	assert_bool(Fp.visible_in_tree(Fp.label(_panel, "FishNameLabel"))).is_false()
	assert_str(Fp.shown(Fp.label(_panel, "CommonNameLabel"))).is_equal(
		tr("fish.bronze_corydoras.name")
	)


func test_36_zero_species_gives_an_empty_list_no_card_and_a_disabled_add_button() -> void:
	var empty: RefCounted = Fp.catalog_of([])
	(
		assert_object(empty)
		. override_failure_message("FishCatalog.from_definitions is missing")
		. is_not_null()
	)
	var seen: Dictionary = {}
	await EngineOutput.capture(func() -> void: seen["ok"] = await _open(empty))
	if not seen.get("ok", false):
		return
	assert_int(Fp.species_buttons(_panel).size()).is_equal(0)
	assert_bool(Fp.visible_in_tree(Fp.card(_panel))).is_false()
	assert_bool(Fp.add_button(_panel).disabled).is_true()
	assert_str(Fp.selected_species(_panel)).is_empty()


func test_36_zero_species_with_no_fish_and_a_pressed_add_changes_nothing() -> void:
	var empty: RefCounted = Fp.catalog_of([])
	if empty == null or not await _open(empty):
		return
	Fp.add_button(_panel).pressed.emit()
	await Fp.frames(self)
	assert_int(_model.get_fish_count()).is_equal(0)
	assert_bool(_history.can_undo()).is_false()


func test_36_a_fish_of_an_unknown_species_lists_with_the_placeholder_and_can_be_removed() -> void:
	_model.apply_insert_fish(Factory.fish(A, &"mystery_fish", 0, "Ghost"), 0)
	if not await _open():
		return
	assert_array(Fp.row_uids(_panel)).is_equal([A])
	assert_str(Fp.shown(Fp.name_button(_panel, A))).is_equal("Ghost")
	assert_str(Fp.shown(Fp.row_species_label(_panel, A))).is_equal("Unknown species")
	await Fp.click(self, Fp.name_button(_panel, A))
	assert_str(Fp.shown(Fp.label(_panel, "CommonNameLabel"))).is_equal("Unknown species")
	assert_bool(Fp.visible_in_tree(Fp.label(_panel, "LatinLabel"))).is_false()
	assert_bool(Fp.visible_in_tree(Fp.label(_panel, "DescriptionLabel"))).is_false()
	assert_bool(Fp.visible_in_tree(Fp.control(_panel, "LengthRow"))).is_false()
	assert_bool(Fp.visible_in_tree(Fp.control(_panel, "ZoneRow"))).is_false()
	await Fp.click(self, Fp.remove_button(_panel, A))
	assert_int(_model.get_fish_count()).is_equal(0)
	assert_str(Fp.shown(Fp.label(_panel, "CommonNameLabel"))).is_equal(
		tr("fish.%s.name" % Fp.selected_species(_panel))
	)
