extends GdUnitTestSuite
## #165 (owner: developer): in the default 1152 x 648 window the whole fish panel, the Close button
## included, stays inside the viewport after a fish row is selected (the info card grows) with 10
## fish, in English and in Hungarian, and also in Hungarian with an Angelfish selected. The panel
## rects are read after the layout has settled.

const Fp := preload("res://tests/helpers/fish_panel_rig.gd")
const Ui := preload("res://tests/helpers/tank_ui_rig.gd")
const Api := preload("res://tests/helpers/fish_api.gd")
const WINDOW := Vector2i(1152, 648)
const TOLERANCE: float = 1.0
const SETTLE_FRAMES: int = 6

var _saved_locale: String = ""
var _language_state: Dictionary = {}
var _model: AquariumModel = null
var _controls: Control = null


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()
	_language_state = Ui.begin_language_isolation("fish_panel_fit")
	TranslationServer.set_locale("en")
	_model = Fp.model_with_tank()


func after_test() -> void:
	Ui.end_language_isolation(_language_state, _saved_locale)


## Opens TankControls with the Fish panel in a 1152 x 648 SubViewport and adds 10 fish of `species`
## with the Add button, as the playtest did.
func _open(locale: String, species: StringName) -> bool:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = WINDOW
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(auto_free(viewport))
	var holder: Node = Node.new()
	viewport.add_child(holder)
	_controls = await Fp.open_controls(holder, _model, Api.shipped())
	auto_free(_controls)
	if _controls == null or Fp.button_of(_controls) == null:
		assert_bool(false).override_failure_message("no Fish button in TankControls").is_true()
		return false
	if locale != "en":
		await Ui.set_language(self, locale)
	await Fp.press_open(self, _controls)
	assert_bool(Fp.is_open(_controls)).override_failure_message("the panel did not open").is_true()
	if not Fp.is_open(_controls):
		return false
	await Fp.select_species(self, _controls, species)
	for _press: int in 10:
		await Fp.click(self, Fp.add_button(_controls))
	await Fp.frames(self, SETTLE_FRAMES)
	assert_int(_model.get_fish_count()).is_equal(10)
	return true


func _select_first_row() -> void:
	var uid: String = Fp.row_uids(_controls)[0]
	await Fp.click(self, Fp.name_button(_controls, uid))
	await Fp.frames(self, SETTLE_FRAMES)


func _check_fit(label: String) -> void:
	var screen: Rect2 = Rect2(Vector2.ZERO, Vector2(WINDOW))
	assert_vector(_controls.get_viewport().get_visible_rect().size).is_equal(Vector2(WINDOW))
	var parts: Array[Control] = [
		Fp.panel_of(_controls), Fp.close_button(_controls), Fp.card(_controls)
	]
	for part: Control in parts:
		assert_bool(part.is_visible_in_tree()).is_true()
		var rect: Rect2 = part.get_global_rect()
		(
			assert_bool(screen.grow(TOLERANCE).encloses(rect))
			. override_failure_message(
				"%s %s %s lies outside the viewport %s" % [label, part.name, rect, screen]
			)
			. is_true()
		)
	var panel_rect: Rect2 = Fp.panel_of(_controls).get_global_rect()
	var close_rect: Rect2 = Fp.close_button(_controls).get_global_rect()
	(
		assert_bool(panel_rect.grow(TOLERANCE).encloses(close_rect))
		. override_failure_message(
			"%s Close %s lies outside the panel %s" % [label, close_rect, panel_rect]
		)
		. is_true()
	)


func test_165_the_panel_and_close_button_fit_the_viewport_with_a_row_selected_in_english() -> void:
	if not await _open("en", &"angelfish"):
		return
	await _check_fit_after_select("en")


func test_165_the_panel_and_close_button_fit_the_viewport_with_a_row_selected_in_hungarian(
) -> void:
	if not await _open("hu", &"angelfish"):
		return
	await _check_fit_after_select("hu")


func test_165_the_panel_and_close_button_fit_the_viewport_with_an_angelfish_selected_in_hungarian(
) -> void:
	if not await _open("hu", &"angelfish"):
		return
	await _check_fit_after_select("hu angelfish")


func _check_fit_after_select(label: String) -> void:
	_check_fit("%s before select" % label)
	await _select_first_row()
	_check_fit("%s after select" % label)
