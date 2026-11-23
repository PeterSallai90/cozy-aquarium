extends GdUnitTestSuite
## #36 long, multi-line and CJK names (owner: developer, BA decision Q5): the list row name, the
## card name line and the Remove tooltip show the name on one line (a line break becomes a space),
## clipped with an ellipsis; the tooltips hold the full one-line text; the stored nickname is never
## changed or trimmed. Texts set in code never look up a translation key (a nickname that equals a
## key stays as typed).

const Fp := preload("res://tests/helpers/fish_panel_rig.gd")
const Ui := preload("res://tests/helpers/tank_ui_rig.gd")
const Factory := preload("res://tests/helpers/factory.gd")

const LONG := "Sir Bubbles the Third of the Great Barrier Reef and all its friendly neighbours"
const MULTI := "first line\nsecond line\r\nthird fourth"
const CJK := "魚ちゃん黄金のアロワナ美しい金魚"
const KEY_LIKE := "fish.default_name.05"
const UIDS: PackedStringArray = ["f0000001", "f0000002", "f0000003", "f0000004"]
const NAMES: PackedStringArray = [LONG, MULTI, CJK, KEY_LIKE]

var _saved_locale: String = ""
var _language_state: Dictionary = {}
var _model: AquariumModel = null
var _panel: Control = null


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()
	_language_state = Ui.begin_language_isolation("fish_panel_long_names")
	TranslationServer.set_locale("en")
	_model = Fp.model_with_tank()
	for index: int in UIDS.size():
		_model.apply_insert_fish(Factory.fish(UIDS[index], &"neon_tetra", 0, NAMES[index]), index)


func after_test() -> void:
	Ui.end_language_isolation(_language_state, _saved_locale)


func _open() -> bool:
	_panel = await Fp.open_panel_alone(
		self, _model, CommandHistory.new(), null, UidGenerator.new(2), Fp.seeded_rng()
	)
	assert_object(_panel).override_failure_message("fish_panel.tscn is missing").is_not_null()
	if _panel == null:
		return false
	auto_free(_panel)
	return true


func _one_line(text: String) -> String:
	var result: String = text.replace("\r\n", " ")
	for separator: String in ["\n", "\r", " ", " "]:
		result = result.replace(separator, " ")
	return result


func test_36_every_row_name_is_one_line_and_clipped_with_an_ellipsis() -> void:
	if not await _open():
		return

	for index: int in UIDS.size():
		var button: Button = Fp.name_button(_panel, UIDS[index])
		assert_object(button).is_not_null()
		var text: String = Fp.shown(button)
		assert_bool(text.contains("\n") or text.contains("\r")).is_false()
		assert_bool(text.contains(" ") or text.contains(" ")).is_false()
		assert_bool(button.clip_text).is_true()
		assert_int(button.text_overrun_behavior).is_equal(TextServer.OVERRUN_TRIM_ELLIPSIS)
		assert_str(Fp.tooltip_of(button)).is_equal(_one_line(NAMES[index]))


func test_36_the_multi_line_name_shows_each_break_as_a_space() -> void:
	if not await _open():
		return
	var text: String = Fp.shown(Fp.name_button(_panel, UIDS[1]))
	assert_str(text).is_equal("first line second line third fourth")


func test_36_the_remove_tooltip_is_one_line_and_holds_the_full_name() -> void:
	if not await _open():
		return
	for index: int in UIDS.size():
		var tip: String = Fp.tooltip_of(Fp.remove_button(_panel, UIDS[index]))
		assert_str(tip).is_equal("Remove %s" % _one_line(NAMES[index]))
		assert_bool(tip.contains("\n")).is_false()


func test_36_the_card_name_line_is_one_line_clipped_with_a_full_text_tooltip() -> void:
	if not await _open():
		return
	for index: int in UIDS.size():
		await Fp.click(self, Fp.name_button(_panel, UIDS[index]))
		var label: Label = Fp.label(_panel, "FishNameLabel")
		assert_bool(Fp.shown(label).contains("\n")).is_false()
		assert_int(label.text_overrun_behavior).is_equal(TextServer.OVERRUN_TRIM_ELLIPSIS)
		assert_str(Fp.tooltip_of(label)).is_equal(_one_line(NAMES[index]))


func test_36_the_stored_nicknames_are_never_changed() -> void:
	if not await _open():
		return
	for index: int in UIDS.size():
		await Fp.click(self, Fp.name_button(_panel, UIDS[index]))
		assert_str(_model.get_fish(UIDS[index]).nickname).is_equal(NAMES[index])


func test_36_a_nickname_that_looks_like_a_key_is_shown_as_typed() -> void:
	if not await _open():
		return
	assert_str(Fp.shown(Fp.name_button(_panel, UIDS[3]))).is_equal(KEY_LIKE)
	await Ui.set_language(self, "hu")
	assert_str(Fp.shown(Fp.name_button(_panel, UIDS[3]))).is_equal(KEY_LIKE)


func test_36_the_row_stays_inside_the_panel_for_a_very_long_name() -> void:
	_model.apply_insert_fish(Factory.fish("f0000009", &"neon_tetra", 0, "w".repeat(10000)), 4)
	if not await _open():
		return

	var row: Control = Fp.row(_panel, "f0000009")
	assert_object(row).is_not_null()
	assert_float(row.size.x).is_less_equal(Fp.panel_of(_panel).size.x)
	assert_str(_model.get_fish("f0000009").nickname).is_equal("w".repeat(10000))
