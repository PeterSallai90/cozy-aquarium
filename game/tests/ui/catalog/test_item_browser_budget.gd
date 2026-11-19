extends GdUnitTestSuite
## #30 criterion 23, budget (owner: developer): with 100 items the cards and their thumbnails are
## built on the first open (not before), and any number of query and category changes creates and
## frees no card and assigns no texture again (cards are shown and hidden); one update of 100 cards
## stays under 100 ms (a smoke guard; the 60 FPS check with 100 placed items is #49).

const Ir := preload("res://tests/helpers/item_browser_rig.gd")
const Ui := preload("res://tests/helpers/tank_ui_rig.gd")

const COUNT := 100
const BUDGET_MS := 100.0

var _saved_locale: String = ""
var _language_state: Dictionary = {}
var _controls: Control = null


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()
	_language_state = Ui.begin_language_isolation("item_browser_budget")
	TranslationServer.set_locale("en")


func after_test() -> void:
	Ui.end_language_isolation(_language_state, _saved_locale)


func _build() -> bool:
	_controls = await Ir.open(self, AquariumModel.new(), Ir.big_catalog(COUNT))
	auto_free(_controls)
	var ok: bool = _controls != null and Ir.open_button(_controls) != null
	assert_bool(ok).override_failure_message("TankControls has no ItemsButton").is_true()
	return ok


func _instance_ids() -> Array[int]:
	var ids: Array[int] = []
	for button: Button in Ir.cards(_controls):
		ids.append(button.get_instance_id())
	return ids


func _texture_ids() -> Array[int]:
	var ids: Array[int] = []
	for button: Button in Ir.cards(_controls):
		var picture: TextureRect = button.find_child("Thumbnail", true, false) as TextureRect
		var has_texture: bool = picture != null and picture.texture != null
		ids.append(picture.texture.get_instance_id() if has_texture else 0)
	return ids


func test_ac23_no_card_exists_before_the_first_open() -> void:
	if not await _build():
		return
	assert_object(Ir.cards_box(_controls)).is_not_null()
	assert_int(Ir.cards_box(_controls).get_child_count()).is_equal(0)
	assert_bool(Ir.is_open(_controls)).is_false()


func test_ac23_the_first_open_builds_one_card_per_item() -> void:
	if not await _build():
		return
	await Ir.press_open(self, _controls)
	assert_int(Ir.cards_box(_controls).get_child_count()).is_equal(COUNT)
	assert_int(Ir.visible_cards(_controls).size()).is_equal(COUNT)


func test_ac23_every_card_holds_its_own_thumbnail_texture() -> void:
	if not await _build():
		return
	await Ir.press_open(self, _controls)
	var seen: Dictionary = {}
	for button: Button in Ir.cards(_controls):
		var picture: TextureRect = button.find_child("Thumbnail", true, false) as TextureRect
		assert_object(picture).is_not_null()
		assert_object(picture.texture).is_not_null()
		seen[picture.texture.get_instance_id()] = true
	assert_int(seen.size()).is_equal(COUNT)


func test_ac23_closing_and_reopening_builds_nothing_again() -> void:
	if not await _build():
		return
	await Ir.press_open(self, _controls)
	var cards: Array[int] = _instance_ids()
	var textures: Array[int] = _texture_ids()
	Ir.close_button(_controls).pressed.emit()
	await get_tree().process_frame
	await Ir.press_open(self, _controls)
	await Ir.press_open(self, _controls)
	await Ir.press_open(self, _controls)
	assert_that(_instance_ids()).is_equal(cards)
	assert_that(_texture_ids()).is_equal(textures)


func test_ac23_many_query_and_category_changes_create_and_free_no_card_and_load_no_texture(
) -> void:
	if not await _build():
		return
	await Ir.press_open(self, _controls)
	var cards: Array[int] = _instance_ids()
	var textures: Array[int] = _texture_ids()
	var queries: Array[String] = ["0", "01", "item_01", "zzz", "  ", "item_099", "9", ""]
	for _round: int in 5:
		for query: String in queries:
			Ir.type_text(_controls, query)
		for node_name: String in Ir.CATEGORY_NAMES:
			Ir.select_category(_controls, node_name)
			Ir.type_text(_controls, "item_0")
			Ir.type_text(_controls, "")
	assert_int(Ir.cards_box(_controls).get_child_count()).is_equal(COUNT)
	assert_that(_instance_ids()).is_equal(cards)
	assert_that(_texture_ids()).is_equal(textures)
	for id: int in cards:
		assert_bool(is_instance_valid(instance_from_id(id))).is_true()


func test_ac23_hidden_cards_stay_in_the_tree_and_come_back_as_the_same_nodes() -> void:
	if not await _build():
		return
	await Ir.press_open(self, _controls)
	var first: Button = Ir.card(_controls, &"item_000")
	Ir.type_text(_controls, "item_099")
	assert_int(Ir.visible_cards(_controls).size()).is_equal(1)
	assert_bool(first.is_inside_tree()).is_true()
	assert_bool(first.is_visible_in_tree()).is_false()
	Ir.type_text(_controls, "")
	assert_object(Ir.card(_controls, &"item_000")).is_same(first)
	assert_bool(first.is_visible_in_tree()).is_true()


func test_ac23_a_hundred_item_search_gives_the_right_cards() -> void:
	if not await _build():
		return
	await Ir.press_open(self, _controls)
	Ir.type_text(_controls, "item_05")
	assert_int(Ir.visible_cards(_controls).size()).is_equal(10)
	Ir.select_category(_controls, "Category_rock")
	assert_int(Ir.visible_cards(_controls).size()).is_equal(2)
	Ir.select_category(_controls, "Category_all")
	Ir.type_text(_controls, "")
	assert_int(Ir.visible_cards(_controls).size()).is_equal(COUNT)


func test_ac23_one_update_of_a_hundred_cards_takes_under_100_ms() -> void:
	if not await _build():
		return
	await Ir.press_open(self, _controls)
	var worst: float = 0.0
	for query: String in ["item_0", "item_05", "", "zzz", "9", ""]:
		var start: int = Time.get_ticks_usec()
		Ir.type_text(_controls, query)
		worst = maxf(worst, float(Time.get_ticks_usec() - start) / 1000.0)
	for node_name: String in ["Category_rock", "Category_plant", "Category_all"]:
		var start: int = Time.get_ticks_usec()
		Ir.select_category(_controls, node_name)
		worst = maxf(worst, float(Time.get_ticks_usec() - start) / 1000.0)
	assert_float(worst).override_failure_message("the slowest update took %.1f ms" % worst).is_less(
		BUDGET_MS
	)
