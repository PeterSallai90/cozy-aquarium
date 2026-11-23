extends GdUnitTestSuite
## #36 keyboard (owner: developer, BA decision Q6): species buttons, Add to tank, the fish rows
## (name button, then Remove button) and Close are reachable with Tab and Shift+Tab in that order
## and wrap inside the panel; Enter and Space activate. The panel is built alone with two fish.
## Test decision: the focus starts on the first species button (the plan leaves focus_start free).

const Fp := preload("res://tests/helpers/fish_panel_rig.gd")
const Ui := preload("res://tests/helpers/tank_ui_rig.gd")
const Factory := preload("res://tests/helpers/factory.gd")

const A := "f0000001"
const B := "f0000002"

var _saved_locale: String = ""
var _language_state: Dictionary = {}
var _model: AquariumModel = null
var _history: CommandHistory = null
var _panel: Control = null


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()
	_language_state = Ui.begin_language_isolation("fish_panel_focus")
	TranslationServer.set_locale("en")
	_model = Fp.model_with_tank()
	_model.apply_insert_fish(Factory.fish(A, &"neon_tetra", 0, "One"), 0)
	_model.apply_insert_fish(Factory.fish(B, &"angelfish", 0, "Two"), 1)
	_history = CommandHistory.new()


func after_test() -> void:
	Ui.end_language_isolation(_language_state, _saved_locale)


func _open() -> bool:
	_panel = await Fp.open_panel_alone(
		self, _model, _history, null, UidGenerator.new(4), Fp.seeded_rng()
	)
	assert_object(_panel).override_failure_message("fish_panel.tscn is missing").is_not_null()
	if _panel == null:
		return false
	auto_free(_panel)
	return Fp.species_buttons(_panel).size() > 0 and Fp.add_button(_panel) != null


## The expected forward chain, in order.
func _chain() -> Array[Control]:
	var chain: Array[Control] = []
	for button: Button in Fp.species_buttons(_panel):
		chain.append(button)
	chain.append(Fp.add_button(_panel))
	for uid: String in [A, B]:
		chain.append(Fp.name_button(_panel, uid))
		chain.append(Fp.remove_button(_panel, uid))
	chain.append(Fp.close_button(_panel))
	return chain


func _tab(count: int, shift: bool = false) -> Array[Control]:
	var visited: Array[Control] = []
	for _step: int in count:
		Ui.tap(_panel, KEY_TAB, shift)
		visited.append(Fp.focus_owner(_panel))
	return visited


func test_36_tab_visits_species_add_rows_and_close_in_order() -> void:
	if not await _open():
		return
	var chain: Array[Control] = _chain()
	for control: Control in chain:
		assert_object(control).is_not_null()
	chain[0].grab_focus()
	var visited: Array[Control] = _tab(chain.size() - 1)
	assert_array(visited).is_equal(chain.slice(1))


func test_36_tab_wraps_from_close_to_the_first_species() -> void:
	if not await _open():
		return
	var chain: Array[Control] = _chain()
	Fp.close_button(_panel).grab_focus()
	var visited: Array[Control] = _tab(1)
	assert_object(visited[0]).is_same(chain[0])


func test_36_shift_tab_walks_backwards_and_wraps_to_close() -> void:
	if not await _open():
		return
	var chain: Array[Control] = _chain()
	chain[0].grab_focus()
	var visited: Array[Control] = _tab(2, true)
	assert_object(visited[0]).is_same(Fp.close_button(_panel))
	assert_object(visited[1]).is_same(chain[chain.size() - 2])


func test_36_enter_activates_add_to_tank() -> void:
	if not await _open():
		return
	Fp.add_button(_panel).grab_focus()
	Ui.tap(_panel, KEY_ENTER)
	await Fp.frames(self)
	assert_int(_model.get_fish_count()).is_equal(3)


func test_36_space_activates_remove() -> void:
	if not await _open():
		return
	Fp.remove_button(_panel, A).grab_focus()
	Ui.tap(_panel, KEY_SPACE)
	await Fp.frames(self)
	assert_bool(_model.has_uid(A)).is_false()
	assert_bool(_model.has_uid(B)).is_true()


func test_36_after_a_keyboard_remove_the_focus_moves_to_a_remove_button_or_add() -> void:
	if not await _open():
		return
	Fp.remove_button(_panel, A).grab_focus()
	Ui.tap(_panel, KEY_ENTER)
	await Fp.frames(self)
	assert_object(Fp.focus_owner(_panel)).is_same(Fp.remove_button(_panel, B))
	Ui.tap(_panel, KEY_ENTER)
	await Fp.frames(self)
	assert_int(_model.get_fish_count()).is_equal(0)
	assert_object(Fp.focus_owner(_panel)).is_same(Fp.add_button(_panel))


func test_36_enter_on_a_species_button_selects_it() -> void:
	if not await _open():
		return
	var buttons: Array[Button] = Fp.species_buttons(_panel)
	var last: Button = buttons[buttons.size() - 1]
	last.grab_focus()
	Ui.tap(_panel, KEY_ENTER)
	await Fp.frames(self)
	assert_str(Fp.selected_species(_panel)).is_equal(String(last.name).trim_prefix("Species_"))
