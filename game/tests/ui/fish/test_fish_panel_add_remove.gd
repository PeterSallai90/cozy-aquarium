extends GdUnitTestSuite
## #36 add and remove through the panel (owner: developer): one command per press with an injected
## seeded UidGenerator and random source; the new row is appended last and scrolled into view; the
## count label (fish.browser.count, also 0 and 1, en and hu) and the empty label follow add,
## remove, undo, redo and model_reset; two quick presses give two fish and two history entries;
## 60 fish then one more works; a UidGenerator that returns a used uid leaves no row, no history
## entry and no error; removing the shown fish makes the card fall back to the species; a reset
## rebuilds both lists.

const Fp := preload("res://tests/helpers/fish_panel_rig.gd")
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
	_language_state = Ui.begin_language_isolation("fish_panel_add_remove")
	TranslationServer.set_locale("en")
	_model = Fp.model_with_tank()
	_history = CommandHistory.new()


func after_test() -> void:
	Ui.end_language_isolation(_language_state, _saved_locale)


func _open(uids: UidGenerator = null) -> bool:
	var generator: UidGenerator = uids if uids != null else UidGenerator.new(11)
	_panel = await Fp.open_panel_alone(self, _model, _history, null, generator, Fp.seeded_rng())
	assert_object(_panel).override_failure_message("fish_panel.tscn is missing").is_not_null()
	if _panel == null:
		return false
	auto_free(_panel)
	return true


func _add() -> void:
	await Fp.click(self, Fp.add_button(_panel))


func test_36_add_runs_one_command_and_appends_one_fish() -> void:
	if not await _open():
		return
	var added: Array[String] = []
	_model.fish_added.connect(func(uid: String, _index: int) -> void: added.append(uid))
	await _add()
	assert_int(_model.get_fish_count()).is_equal(1)
	assert_int(added.size()).is_equal(1)
	assert_int(_history.get_undo_count()).is_equal(1)
	var fish: FishInstance = _model.get_fish_at(0)
	assert_int(fish.uid.length()).is_equal(8)
	assert_str(fish.nickname).is_empty()
	assert_str(String(fish.species_id)).is_equal(Fp.selected_species(_panel))
	assert_array(Fp.row_uids(_panel)).is_equal([fish.uid])


func test_36_two_quick_presses_give_two_fish_two_entries_and_two_undos_remove_both() -> void:
	if not await _open():
		return
	Fp.add_button(_panel).pressed.emit()
	Fp.add_button(_panel).pressed.emit()
	await Fp.frames(self)
	assert_int(_model.get_fish_count()).is_equal(2)
	assert_int(_history.get_undo_count()).is_equal(2)
	assert_bool(_history.undo()).is_true()
	assert_bool(_history.undo()).is_true()
	await Fp.frames(self)
	assert_int(_model.get_fish_count()).is_equal(0)
	assert_int(Fp.rows(_panel).size()).is_equal(0)


func test_36_the_new_row_is_last_and_the_list_scrolls_to_it() -> void:
	_model.apply_insert_fish(Factory.fish(A), 0)
	if not await _open():
		return
	for i: int in 15:
		await _add()
	await Fp.frames(self, 3)
	var uids: Array[String] = Fp.row_uids(_panel)
	assert_int(uids.size()).is_equal(16)
	assert_str(uids[0]).is_equal(A)
	assert_str(uids[uids.size() - 1]).is_equal(_model.get_fish_at(15).uid)
	var last: Control = Fp.rows(_panel)[15]
	var scroll: ScrollContainer = Fp.scroll(_panel)
	var visible_rect: Rect2 = scroll.get_global_rect()
	assert_bool(visible_rect.encloses(last.get_global_rect())).is_true()


func test_36_the_count_reads_0_1_and_2_fish_in_english() -> void:
	if not await _open():
		return
	assert_str(Fp.count_text(_panel)).is_equal("0 fish")
	await _add()
	assert_str(Fp.count_text(_panel)).is_equal("1 fish")
	await _add()
	assert_str(Fp.count_text(_panel)).is_equal("2 fish")


func test_36_the_count_reads_the_same_form_in_hungarian_and_follows_a_language_switch() -> void:
	if not await _open():
		return
	await _add()
	await Ui.set_language(self, "hu")
	assert_str(Fp.count_text(_panel)).is_equal("1 hal")
	await _add()
	assert_str(Fp.count_text(_panel)).is_equal("2 hal")
	await Ui.set_language(self, "en")
	assert_str(Fp.count_text(_panel)).is_equal("2 fish")


func test_36_the_count_sits_on_the_right_of_the_in_your_tank_heading_line() -> void:
	if not await _open():
		return
	var heading: Label = Fp.label(_panel, "InTankHeading")
	var count: Label = Fp.label(_panel, "CountLabel")
	assert_object(heading).is_not_null()
	assert_object(count).is_not_null()
	assert_str(Fp.shown(heading)).is_equal("In your tank")
	assert_float(count.get_global_rect().position.x).is_greater(
		heading.get_global_rect().position.x
	)
	(
		assert_float(
			absf(count.get_global_rect().get_center().y - heading.get_global_rect().get_center().y)
		)
		. is_less(heading.get_global_rect().size.y)
	)


func test_36_the_empty_label_shows_only_with_no_fish() -> void:
	if not await _open():
		return
	var empty: Label = Fp.label(_panel, "EmptyTankLabel")
	assert_str(Fp.shown(empty)).is_equal("No fish yet. Pick a species and add one.")
	assert_bool(Fp.visible_in_tree(empty)).is_true()
	await _add()
	assert_bool(Fp.visible_in_tree(empty)).is_false()
	assert_bool(_history.undo()).is_true()
	await Fp.frames(self)
	assert_bool(Fp.visible_in_tree(empty)).is_true()


func test_36_undo_and_redo_update_rows_and_count() -> void:
	if not await _open():
		return
	await _add()
	var uid: String = _model.get_fish_at(0).uid
	assert_bool(_history.undo()).is_true()
	await Fp.frames(self)
	assert_array(Fp.row_uids(_panel)).is_empty()
	assert_str(Fp.count_text(_panel)).is_equal("0 fish")
	assert_bool(_history.redo()).is_true()
	await Fp.frames(self)
	assert_array(Fp.row_uids(_panel)).is_equal([uid])
	assert_str(Fp.count_text(_panel)).is_equal("1 fish")


func test_36_remove_runs_one_command_and_undo_brings_the_row_back_at_its_place() -> void:
	_model.apply_insert_fish(Factory.fish(A, &"neon_tetra", 0, "One"), 0)
	_model.apply_insert_fish(Factory.fish(B, &"angelfish", 1, "Two"), 1)
	if not await _open():
		return
	await Fp.click(self, Fp.remove_button(_panel, A))
	assert_bool(_model.has_uid(A)).is_false()
	assert_int(_history.get_undo_count()).is_equal(1)
	assert_array(Fp.row_uids(_panel)).is_equal([B])
	assert_str(Fp.count_text(_panel)).is_equal("1 fish")
	assert_bool(_history.undo()).is_true()
	await Fp.frames(self)
	assert_array(Fp.row_uids(_panel)).is_equal([A, B])
	assert_str(_model.get_fish_at(0).nickname).is_equal("One")


func test_36_a_model_reset_rebuilds_both_lists_from_the_new_model() -> void:
	_model.apply_insert_fish(Factory.fish(A, &"neon_tetra", 0, "One"), 0)
	if not await _open():
		return
	var other: AquariumModel = Fp.model_with_tank()
	other.apply_insert_fish(Factory.fish(B, &"angelfish", 0, "Two"), 0)
	other.apply_insert_fish(Factory.fish("f0000003", &"angelfish", 0, "Three"), 1)
	_model.reset_from(other)
	await Fp.frames(self)
	assert_array(Fp.row_uids(_panel)).is_equal([B, "f0000003"])
	assert_str(Fp.count_text(_panel)).is_equal("2 fish")


func test_36_a_reset_drops_the_shown_fish_and_the_card_falls_back_to_the_species() -> void:
	_model.apply_insert_fish(Factory.fish(A, &"angelfish", 0, "One"), 0)
	if not await _open():
		return
	await Fp.click(self, Fp.name_button(_panel, A))
	assert_str(Fp.shown_fish(_panel)).is_equal(A)
	_model.reset_from(Fp.model_with_tank())
	await Fp.frames(self)
	assert_str(Fp.shown_fish(_panel)).is_empty()
	assert_bool(Fp.visible_in_tree(Fp.label(_panel, "FishNameLabel"))).is_false()
	assert_str(Fp.shown(Fp.label(_panel, "CommonNameLabel"))).is_equal(
		tr("fish.%s.name" % Fp.selected_species(_panel))
	)


func test_36_removing_the_shown_fish_makes_the_card_show_the_selected_species() -> void:
	_model.apply_insert_fish(Factory.fish(A, &"angelfish", 0, "One"), 0)
	if not await _open():
		return
	var selected: String = Fp.selected_species(_panel)
	await Fp.click(self, Fp.name_button(_panel, A))
	await Fp.click(self, Fp.remove_button(_panel, A))
	assert_str(Fp.shown_fish(_panel)).is_empty()
	assert_bool(Fp.visible_in_tree(Fp.label(_panel, "FishNameLabel"))).is_false()
	assert_str(Fp.shown(Fp.label(_panel, "CommonNameLabel"))).is_equal(
		tr("fish.%s.name" % selected)
	)


func test_36_a_used_uid_from_the_generator_leaves_no_row_no_entry_and_no_error() -> void:
	_model.apply_insert_fish(Factory.fish(A), 0)
	var clash: Fp.FixedUid = Fp.FixedUid.new(A)
	if not await _open(clash):
		return
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void:
			Fp.add_button(_panel).pressed.emit()
			await Fp.frames(self)
	)
	assert_int(_model.get_fish_count()).is_equal(1)
	assert_bool(_history.can_undo()).is_false()
	assert_array(Fp.row_uids(_panel)).is_equal([A])
	assert_int((seen["errors"] as Dictionary).size()).is_equal(0)


func test_36_sixty_fish_then_one_more_is_added_and_the_list_stays_usable() -> void:
	Fp.fill(_model, 60)
	if not await _open():
		return
	assert_int(Fp.rows(_panel).size()).is_equal(60)
	assert_str(Fp.count_text(_panel)).is_equal("60 fish")
	await _add()
	assert_int(_model.get_fish_count()).is_equal(61)
	assert_int(Fp.rows(_panel).size()).is_equal(61)
	assert_str(Fp.count_text(_panel)).is_equal("61 fish")
	var scroll: ScrollContainer = Fp.scroll(_panel)
	assert_bool(scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page).is_true()


func test_36_every_added_variant_is_valid_over_many_adds() -> void:
	if not await _open():
		return
	for i: int in 30:
		await _add()
	var variants: Dictionary = {}
	for fish: FishInstance in _model.get_fish_list():
		variants[fish.variant] = true
		assert_int(fish.variant).is_greater_equal(0)
	assert_int(_model.get_fish_count()).is_equal(30)


func test_36_a_row_shows_the_derived_name_for_an_empty_nickname() -> void:
	_model.apply_insert_fish(Factory.fish("f1000001", &"neon_tetra", 0, ""), 0)
	if not await _open():
		return
	assert_str(Fp.shown(Fp.name_button(_panel, "f1000001"))).is_equal(tr("fish.default_name.21"))
	await Ui.set_language(self, "hu")
	assert_str(Fp.shown(Fp.name_button(_panel, "f1000001"))).is_equal(tr("fish.default_name.21"))
	assert_str(Fp.shown(Fp.name_button(_panel, "f1000001"))).is_not_equal("fish.default_name.21")
