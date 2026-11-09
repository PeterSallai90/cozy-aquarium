# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #117 criteria 1 to 10 (owner: developer): what the tank details panel shows. The real catalog
## and the real controls for the three delivered tanks, fixture catalogs (no scene, no room) for
## rounding and broken data. Node names: tests/helpers/tank_ui_rig.gd (header). The language is
## switched through the Localization autoload, because the number format follows it.

const Api := preload("res://tests/helpers/late_api.gd")
const Rig := preload("res://tests/helpers/room_rig.gd")
const Ui := preload("res://tests/helpers/tank_ui_rig.gd")
const Table := preload("res://tests/helpers/tank_table.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")

const WINDOW := Vector2i(1280, 720)
const UNKNOWN: Dictionary = {"en": "Unknown", "hu": "Ismeretlen"}
const FALLBACK_NOTE: Dictionary = {
	"en": "The tank in your save was not found, so the default tank is shown.",
	"hu": "A mentésben szereplő akvárium nem található, ezért az alapértelmezett akvárium látható.",
}
const KEY_TEXTS: Dictionary = {
	"en":
	{
		"LengthRow": "Length",
		"WidthRow": "Width",
		"HeightRow": "Height",
		"WaterLevelRow": "Water level",
		"WaterVolumeRow": "Water volume",
		"GlassThicknessRow": "Glass thickness",
	},
	"hu":
	{
		"LengthRow": "Hosszúság",
		"WidthRow": "Szélesség",
		"HeightRow": "Magasság",
		"WaterLevelRow": "Vízszint",
		"WaterVolumeRow": "Vízmennyiség",
		"GlassThicknessRow": "Üvegvastagság",
	},
}

var _saved_locale: String = ""
var _saved_language: String = ""
var _history: CommandHistory = null
var _controls: Control = null
var _room: Node3D = null


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()
	_saved_language = Localization.get_language()
	Localization.set_language("en")
	_history = CommandHistory.new()
	_controls = null
	_room = null


func after_test() -> void:
	Localization.set_language(_saved_language)
	TranslationServer.set_locale(_saved_locale)


func _wait() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _drop() -> void:
	for node: Node in [_controls, _room]:
		if is_instance_valid(node):
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.free()
	_controls = null
	_room = null


## True when the panel node exists; fails the test once with a clear message otherwise.
func _has_panel() -> bool:
	var found: bool = _controls != null and Ui.details(_controls) != null
	(
		assert_bool(found)
		. override_failure_message("the TankDetails panel is missing in %s" % Ui.CONTROLS_SCENE)
		. is_true()
	)
	return found


## Controls on the real catalog without a room; the model asks for `model_id`, the room "displays"
## `displayed_id`. The panel is opened through its button.
func _open_real(model_id: StringName, displayed_id: StringName = &"", parent: Node = null) -> bool:
	_drop()
	var shown_id: StringName = model_id if displayed_id == &"" else displayed_id
	_controls = await Ui.open_controls_only(
		parent if parent != null else self,
		Rig.model_with(model_id),
		Rig.default_catalog(),
		_history,
		shown_id
	)
	if not _has_panel():
		return false
	await Ui.open_details(self, _controls)
	return Ui.details_open(_controls)


## Controls on a fixture catalog; the panel is opened through its button.
func _open_fixture(
	definitions: Array[TankDefinition],
	model_id: StringName,
	displayed_id: StringName,
	parent: Node = null
) -> bool:
	_drop()
	_controls = await Ui.open_controls_only(
		parent if parent != null else self,
		Rig.model_with(model_id),
		Ui.fixture_catalog(definitions),
		_history,
		displayed_id
	)
	if not _has_panel():
		return false
	await Ui.open_details(self, _controls)
	return Ui.details_open(_controls)


## A one-definition fixture catalog (the medium copy with `overrides`) shown as displayed tank.
func _open_override(overrides: Dictionary) -> bool:
	var definitions: Array[TankDefinition] = [Ui.fixture_definition(overrides)]
	return await _open_fixture(definitions, Table.MEDIUM, Table.MEDIUM)


## The eight value texts the panel must show for a delivered tank, built from the issue table.
func _expected(id: StringName, language: String) -> Array[String]:
	var inner: Vector3 = Table.interior(id)
	var point: String = "." if language == "en" else ","
	var litres: String = "%d L" if language == "en" else "%d l"
	var glass: String = "%.1f" % (Table.glass(id) * 100.0)
	var row: Dictionary = Table.row(id)
	return [
		row["name_" + language],
		row["description_" + language],
		"%d cm" % roundi(inner.x * 100.0),
		"%d cm" % roundi(inner.z * 100.0),
		"%d cm" % roundi(inner.y * 100.0),
		"%d cm" % roundi(Table.water_line(id) * 100.0),
		litres % row["litres"],
		"%s cm" % glass.replace(".", point),
	]


func _assert_values(expected: Array[String], context: String) -> void:
	var actual: Array[String] = Ui.row_values(_controls)
	for index: int in Ui.ROW_NAMES.size():
		(
			assert_str(actual[index])
			. override_failure_message(
				(
					"%s: %s shows '%s', expected '%s'"
					% [context, Ui.ROW_NAMES[index], actual[index], expected[index]]
				)
			)
			. is_equal(expected[index])
		)


# --- AC 1 and 2: rows and values ---


func test_ac01_the_details_button_is_labelled_and_the_panel_is_closed_until_pressed() -> void:
	_controls = await Ui.open_controls_only(
		self, Rig.model_with(Table.MEDIUM), Rig.default_catalog(), _history, Table.MEDIUM
	)
	if not _has_panel():
		return
	assert_object(Ui.details_button(_controls)).is_not_null()
	assert_str(Ui.shown(Ui.details_button(_controls))).is_equal("Tank details")
	assert_bool(Ui.details_open(_controls)).is_false()
	await Ui.open_details(self, _controls)
	assert_bool(Ui.details_open(_controls)).is_true()
	var title: Label = Ui.details(_controls).find_child(Ui.TITLE, true, false) as Label
	assert_str(Ui.shown(title)).is_equal("Tank details")
	assert_str(Ui.shown(Ui.details_close_button(_controls))).is_equal("Close")


func test_ac02_each_tank_shows_its_values_in_english() -> void:
	for id: StringName in Table.IDS:
		if not await _open_real(id):
			return
		_assert_values(_expected(id, "en"), "en " + String(id))


func test_ac02_the_medium_tank_values_are_the_issue_numbers() -> void:
	if not await _open_real(Table.MEDIUM):
		return
	(
		assert_array(Ui.row_values(_controls))
		. is_equal(
			[
				"Medium tank",
				"A cozy, balanced tank for a small community.",
				"60 cm",
				"30 cm",
				"35 cm",
				"33 cm",
				"60 L",
				"0.5 cm",
			]
		)
	)


func test_ac02_the_panel_has_exactly_the_eight_rows_in_order() -> void:
	if not await _open_real(Table.MEDIUM):
		return
	var names: Array[String] = []
	for row: Control in Ui.details_rows(_controls):
		names.append(String(row.name))
	assert_array(names).is_equal(Ui.ROW_NAMES)
	assert_int(Ui.details_rows(_controls).size()).is_equal(8)


func test_ac02_the_key_labels_are_the_english_row_labels() -> void:
	if not await _open_real(Table.MEDIUM):
		return
	for row_name: String in KEY_TEXTS["en"]:
		assert_str(Ui.row_key(_controls, row_name)).is_equal(KEY_TEXTS["en"][row_name])
	for row_name: String in ["NameRow", "DescriptionRow"]:
		assert_object(Ui.row(_controls, row_name).find_child(Ui.KEY_LABEL, true, false)).is_null()


func test_ac02_no_mode_2_value_is_shown_anywhere_in_the_panel() -> void:
	if not await _open_real(Table.MEDIUM):
		return
	# Medium Mode 2 numbers (weight 8, heat loss 1, evaporation 0.5, watts 50, lph 240).
	var texts: Array[String] = []
	for node: Node in Ui.details(_controls).find_children("*", "Label", true, false):
		if (node as Label).is_visible_in_tree():
			texts.append(Ui.shown(node as Label))
	var joined: String = " | ".join(texts)
	for forbidden: String in ["240", "50 W", "kg", "lph", "slot"]:
		(
			assert_bool(joined.contains(forbidden))
			. override_failure_message("'%s' appears in: %s" % [forbidden, joined])
			. is_false()
		)


func test_ac02_the_fallback_note_is_hidden_when_the_displayed_tank_is_the_model_tank() -> void:
	for id: StringName in Table.IDS:
		if not await _open_real(id):
			return
		assert_bool(Ui.fallback_shown(_controls)).is_false()


# --- AC 3: Hungarian ---


func test_ac03_the_medium_tank_in_hungarian_uses_the_decimal_comma_and_l() -> void:
	await Ui.set_language(self, "hu")
	if not await _open_real(Table.MEDIUM):
		return
	(
		assert_array(Ui.row_values(_controls))
		. is_equal(
			[
				"Közepes akvárium",
				"Hangulatos, kiegyensúlyozott akvárium egy kis közösségnek.",
				"60 cm",
				"30 cm",
				"35 cm",
				"33 cm",
				"60 l",
				"0,5 cm",
			]
		)
	)


func test_ac03_every_tank_in_hungarian_and_the_hungarian_labels() -> void:
	await Ui.set_language(self, "hu")
	for id: StringName in Table.IDS:
		if not await _open_real(id):
			return
		_assert_values(_expected(id, "hu"), "hu " + String(id))
		for row_name: String in KEY_TEXTS["hu"]:
			assert_str(Ui.row_key(_controls, row_name)).is_equal(KEY_TEXTS["hu"][row_name])
	assert_str(Ui.shown(Ui.details_button(_controls))).is_equal("Akvárium adatai")
	var title: Label = Ui.details(_controls).find_child(Ui.TITLE, true, false) as Label
	assert_str(Ui.shown(title)).is_equal("Akvárium adatai")
	assert_str(Ui.shown(Ui.details_close_button(_controls))).is_equal("Bezárás")


# --- AC 4: the same litres as the chooser card ---


func test_ac04_the_volume_row_equals_the_chooser_card_litres_in_both_languages() -> void:
	for language: String in ["en", "hu"]:
		await Ui.set_language(self, language)
		for id: StringName in Table.IDS:
			if not await _open_real(id):
				return
			var card_text: String = Ui.shown(Ui.card_label(_controls, id, "LitresLabel"))
			assert_str(Ui.row_value(_controls, "WaterVolumeRow")).is_equal(card_text)


func test_ac04_the_volume_is_the_stored_nominal_figure_not_the_computed_one() -> void:
	# 60 x 30 x 33 cm computes to 59.4 L; the stored 60 is shown (BA decision Q2).
	if not await _open_real(Table.MEDIUM):
		return
	assert_str(Ui.row_value(_controls, "WaterVolumeRow")).is_equal("60 L")
	var odd: Dictionary = {"volume_litres": 77}
	if not await _open_override(odd):
		return
	assert_str(Ui.row_value(_controls, "WaterVolumeRow")).is_equal("77 L")


# --- AC 5: rounded before formatting ---


func test_ac05_a_float_artefact_in_a_length_reads_as_the_whole_centimetre() -> void:
	# 0.29 * 100 is 28.999999999999996.
	if not await _open_override({"interior_size_m": Vector3(0.29, 0.35, 0.30)}):
		return
	assert_str(Ui.row_value(_controls, "LengthRow")).is_equal("29 cm")


func test_ac05_the_glass_thickness_keeps_one_decimal_without_an_artefact() -> void:
	# 0.007 * 100 is 0.7000000000000001.
	if not await _open_override({"glass_thickness_m": 0.007}):
		return
	assert_str(Ui.row_value(_controls, "GlassThicknessRow")).is_equal("0.7 cm")
	await Ui.set_language(self, "hu")
	assert_str(Ui.row_value(_controls, "GlassThicknessRow")).is_equal("0,7 cm")


func test_ac05_values_between_whole_centimetres_round_to_the_nearest() -> void:
	var sizes: Dictionary = {
		"interior_size_m": Vector3(0.604, 0.356, 0.306), "water_line_height_m": 0.334
	}
	if not await _open_override(sizes):
		return
	assert_str(Ui.row_value(_controls, "LengthRow")).is_equal("60 cm")
	assert_str(Ui.row_value(_controls, "HeightRow")).is_equal("36 cm")
	assert_str(Ui.row_value(_controls, "WidthRow")).is_equal("31 cm")
	assert_str(Ui.row_value(_controls, "WaterLevelRow")).is_equal("33 cm")
	if not await _open_override({"glass_thickness_m": 0.0056}):
		return
	assert_str(Ui.row_value(_controls, "GlassThicknessRow")).is_equal("0.6 cm")
	if not await _open_override({"glass_thickness_m": 0.0054}):
		return
	assert_str(Ui.row_value(_controls, "GlassThicknessRow")).is_equal("0.5 cm")


func test_ac05_no_row_text_holds_a_float_artefact() -> void:
	var sizes: Dictionary = {
		"interior_size_m": Vector3(0.29, 0.57, 0.58),
		"water_line_height_m": 0.57,
		"glass_thickness_m": 0.007,
	}
	if not await _open_override(sizes):
		return
	for text: String in Ui.row_values(_controls):
		assert_bool(RegEx.create_from_string("\\d[.,]\\d{2,}").search(text) != null).is_false()


# --- AC 6: language switch ---


func test_ac06_a_language_switch_keeps_the_panel_open_and_the_focus_on_close() -> void:
	if not await _open_real(Table.MEDIUM):
		return
	var close: Button = Ui.details_close_button(_controls)
	assert_object(Ui.focus_owner(_controls)).is_same(close)
	await Ui.set_language(self, "hu")
	assert_bool(Ui.details_open(_controls)).is_true()
	assert_object(Ui.focus_owner(_controls)).is_same(close)
	assert_array(Ui.row_values(_controls)).is_equal(_expected(Table.MEDIUM, "hu"))
	assert_str(Ui.row_key(_controls, "WaterVolumeRow")).is_equal("Vízmennyiség")
	assert_str(Ui.shown(close)).is_equal("Bezárás")
	await Ui.set_language(self, "en")
	assert_array(Ui.row_values(_controls)).is_equal(_expected(Table.MEDIUM, "en"))
	assert_object(Ui.focus_owner(_controls)).is_same(close)


func test_ac06_a_closed_panel_stays_closed_and_shows_the_new_language_when_opened() -> void:
	_controls = await Ui.open_controls_only(
		self, Rig.model_with(Table.LARGE), Rig.default_catalog(), _history, Table.LARGE
	)
	if not _has_panel():
		return
	await Ui.set_language(self, "hu")
	assert_bool(Ui.details_open(_controls)).is_false()
	await Ui.open_details(self, _controls)
	assert_array(Ui.row_values(_controls)).is_equal(_expected(Table.LARGE, "hu"))
	assert_str(Ui.row_key(_controls, "LengthRow")).is_equal("Hosszúság")


func test_ac06_the_fallback_note_follows_the_language_too() -> void:
	if not await _open_real(Table.MEDIUM, &"tank_ghost"):
		return
	assert_bool(Ui.fallback_shown(_controls)).is_true()
	var note: Label = Ui.details(_controls).find_child(Ui.FALLBACK, true, false) as Label
	assert_str(Ui.shown(note)).is_equal(FALLBACK_NOTE["en"])
	await Ui.set_language(self, "hu")
	assert_str(Ui.shown(note)).is_equal(FALLBACK_NOTE["hu"])


# --- AC 7: follows the displayed tank ---


func _open_with_room(model: AquariumModel) -> bool:
	_drop()
	var rig: Dictionary = await Ui.open(self, model, Rig.default_catalog(), _history)
	_room = rig["room"]
	_controls = rig["controls"]
	if not _has_panel():
		return false
	await Ui.open_details(self, _controls)
	return Ui.details_open(_controls)


func test_ac07_a_tank_change_while_open_updates_every_row() -> void:
	var model: AquariumModel = Rig.model_with(Table.MEDIUM)
	if not await _open_with_room(model):
		return
	model.apply_set_tank_id(Table.LARGE)
	await _wait()
	assert_bool(Ui.details_open(_controls)).is_true()
	assert_array(Ui.row_values(_controls)).is_equal(_expected(Table.LARGE, "en"))
	assert_bool(Ui.fallback_shown(_controls)).is_false()


func test_ac07_a_model_tank_without_a_scene_shows_the_default_values_and_the_note() -> void:
	var model: AquariumModel = Rig.model_with(Table.LARGE)
	if not await _open_with_room(model):
		return
	await EngineOutput.capture(
		func() -> void:
			model.apply_set_tank_id(&"tank_medium_60l")
			await _wait()
	)
	assert_array(Ui.row_values(_controls)).is_equal(_expected(Table.MEDIUM, "en"))
	assert_bool(Ui.fallback_shown(_controls)).is_true()
	model.apply_set_tank_id(Table.SMALL)
	await _wait()
	assert_array(Ui.row_values(_controls)).is_equal(_expected(Table.SMALL, "en"))
	assert_bool(Ui.fallback_shown(_controls)).is_false()


func test_ac07_a_model_reset_updates_the_panel() -> void:
	var model: AquariumModel = Rig.model_with(Table.MEDIUM)
	if not await _open_with_room(model):
		return
	model.reset_from(Rig.model_with(Table.SMALL))
	await _wait()
	assert_array(Ui.row_values(_controls)).is_equal(_expected(Table.SMALL, "en"))
	assert_bool(Ui.fallback_shown(_controls)).is_false()
	await EngineOutput.capture(
		func() -> void:
			model.reset_from(Rig.model_with(&"tank_from_the_future"))
			await _wait()
	)
	assert_array(Ui.row_values(_controls)).is_equal(_expected(Table.MEDIUM, "en"))
	assert_bool(Ui.fallback_shown(_controls)).is_true()


func test_ac07_undo_and_redo_of_a_tank_change_update_the_panel() -> void:
	var model: AquariumModel = Rig.model_with(Table.MEDIUM)
	if not await _open_with_room(model):
		return
	_history.execute(Api.change_tank(model, Rig.default_catalog(), Table.LARGE))
	await _wait()
	assert_array(Ui.row_values(_controls)).is_equal(_expected(Table.LARGE, "en"))
	_history.undo()
	await _wait()
	assert_array(Ui.row_values(_controls)).is_equal(_expected(Table.MEDIUM, "en"))
	_history.redo()
	await _wait()
	assert_array(Ui.row_values(_controls)).is_equal(_expected(Table.LARGE, "en"))


func test_ac07_a_closed_panel_shows_the_current_tank_the_moment_it_opens() -> void:
	var model: AquariumModel = Rig.model_with(Table.MEDIUM)
	if not await _open_with_room(model):
		return
	Ui.details_close_button(_controls).pressed.emit()
	await _wait()
	assert_bool(Ui.details_open(_controls)).is_false()
	model.apply_set_tank_id(Table.LARGE)
	await _wait()
	await Ui.open_details(self, _controls)
	assert_array(Ui.row_values(_controls)).is_equal(_expected(Table.LARGE, "en"))


# --- AC 8: unknown and empty ids ---


func test_ac08_an_unknown_model_id_shows_the_default_values_and_the_note() -> void:
	# The room shows the default tank for an id it does not know.
	if not await _open_real(&"tank_medium_60l", Table.MEDIUM):
		return
	assert_array(Ui.row_values(_controls)).is_equal(_expected(Table.MEDIUM, "en"))
	assert_bool(Ui.fallback_shown(_controls)).is_true()
	var note: Label = Ui.details(_controls).find_child(Ui.FALLBACK, true, false) as Label
	assert_str(Ui.shown(note)).is_equal(FALLBACK_NOTE["en"])


func test_ac08_an_unknown_displayed_id_shows_the_default_values_and_the_note() -> void:
	if not await _open_real(Table.MEDIUM, &"tank_ghost"):
		return
	assert_array(Ui.row_values(_controls)).is_equal(_expected(Table.MEDIUM, "en"))
	assert_bool(Ui.fallback_shown(_controls)).is_true()


func test_ac08_an_empty_displayed_id_shows_the_default_values_and_the_note() -> void:
	_drop()
	_controls = await Ui.open_controls_only(
		self, Rig.model_with(Table.LARGE), Rig.default_catalog(), _history, &""
	)
	if not _has_panel():
		return
	await Ui.open_details(self, _controls)
	assert_array(Ui.row_values(_controls)).is_equal(_expected(Table.MEDIUM, "en"))
	assert_bool(Ui.fallback_shown(_controls)).is_true()


func test_ac08_a_known_displayed_tank_that_differs_from_the_model_shows_the_note() -> void:
	if not await _open_real(Table.LARGE, Table.SMALL):
		return
	assert_array(Ui.row_values(_controls)).is_equal(_expected(Table.SMALL, "en"))
	assert_bool(Ui.fallback_shown(_controls)).is_true()


func test_ac08_the_note_disappears_when_the_displayed_tank_matches_the_model_again() -> void:
	if not await _open_real(Table.MEDIUM, &"tank_ghost"):
		return
	assert_bool(Ui.fallback_shown(_controls)).is_true()
	EventBus.emit_signal("tank_displayed", Table.MEDIUM)
	await _wait()
	assert_bool(Ui.fallback_shown(_controls)).is_false()


# --- AC 9: broken data ---


func _assert_only_unknown(unknown_rows: Array[String], context: String) -> void:
	var expected: Array[String] = _expected(Table.MEDIUM, "en")
	assert_int(Ui.details_rows(_controls).size()).is_equal(8)
	var actual: Array[String] = Ui.row_values(_controls)
	for index: int in Ui.ROW_NAMES.size():
		var want: String = (
			UNKNOWN["en"] if unknown_rows.has(Ui.ROW_NAMES[index]) else expected[index]
		)
		(
			assert_str(actual[index])
			. override_failure_message(
				(
					"%s: %s shows '%s', expected '%s'"
					% [context, Ui.ROW_NAMES[index], actual[index], want]
				)
			)
			. is_equal(want)
		)
		assert_str(actual[index]).is_not_empty()
		assert_str(actual[index]).is_not_equal("0 cm")
		assert_str(actual[index]).is_not_equal("0.0 cm")
		assert_str(actual[index]).is_not_equal("0 L")


func test_ac09_with_no_default_entry_every_value_is_unknown_and_the_note_shows() -> void:
	var other: Array[TankDefinition] = [Ui.fixture_definition({"id": &"tank_other_1"})]
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void:
			if not await _open_fixture(other, &"tank_other_1", &"tank_gone"):
				return
	)
	if _controls == null or not Ui.details_open(_controls):
		return
	assert_int(Ui.details_rows(_controls).size()).is_equal(8)
	for row_name: String in Ui.ROW_NAMES:
		assert_str(Ui.row_value(_controls, row_name)).is_equal("Unknown")
	assert_bool(Ui.fallback_shown(_controls)).is_true()
	assert_dict(seen["errors"]).is_empty()


func test_ac09_with_an_empty_catalog_every_value_is_unknown_and_the_note_shows() -> void:
	var none: Array[TankDefinition] = []
	if not await _open_fixture(none, Table.MEDIUM, Table.MEDIUM):
		return
	for row_name: String in Ui.ROW_NAMES:
		assert_str(Ui.row_value(_controls, row_name)).is_equal("Unknown")
	assert_bool(Ui.fallback_shown(_controls)).is_true()


func test_ac09_an_empty_name_key_shows_unknown_in_the_name_row_only() -> void:
	if not await _open_override({"name_key": ""}):
		return
	_assert_only_unknown(["NameRow"], "empty name_key")


func test_ac09_an_empty_description_key_shows_unknown_in_the_description_row_only() -> void:
	if not await _open_override({"description_key": ""}):
		return
	_assert_only_unknown(["DescriptionRow"], "empty description_key")


func test_ac09_a_zero_or_negative_size_shows_unknown_in_its_own_row_only() -> void:
	var cases: Dictionary = {
		"LengthRow": ["interior_size_m", Vector3(0.0, 0.35, 0.30), Vector3(-0.6, 0.35, 0.30)],
		"HeightRow": ["interior_size_m", Vector3(0.60, 0.0, 0.30), Vector3(0.60, -0.35, 0.30)],
		"WidthRow": ["interior_size_m", Vector3(0.60, 0.35, 0.0), Vector3(0.60, 0.35, -0.3)],
		"WaterLevelRow": ["water_line_height_m", 0.0, -0.33],
		"GlassThicknessRow": ["glass_thickness_m", 0.0, -0.005],
	}
	for row_name: String in cases:
		var spec: Array = cases[row_name]
		for index: int in [1, 2]:
			if not await _open_override({spec[0]: spec[index]}):
				return
			_assert_only_unknown([row_name], "%s with %s" % [row_name, str(spec[index])])


func test_ac09_a_zero_or_negative_volume_shows_unknown_without_a_unit() -> void:
	for litres: int in [0, -5]:
		if not await _open_override({"volume_litres": litres}):
			return
		_assert_only_unknown(["WaterVolumeRow"], "volume %d" % litres)


func test_ac09_a_value_that_rounds_to_zero_shows_unknown_not_zero() -> void:
	# 0.0001 m is 0.01 cm: 0 cm after rounding; 0.0004 m glass is 0.04 cm: 0.0 after rounding.
	if not await _open_override({"interior_size_m": Vector3(0.0001, 0.35, 0.30)}):
		return
	_assert_only_unknown(["LengthRow"], "length 0.0001 m")
	if not await _open_override({"glass_thickness_m": 0.0004}):
		return
	_assert_only_unknown(["GlassThicknessRow"], "glass 0.0004 m")


func test_ac09_a_non_finite_size_shows_unknown_and_logs_nothing() -> void:
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void:
			if not await _open_override({"interior_size_m": Vector3(INF, 0.35, NAN)}):
				return
	)
	if _controls == null or not Ui.details_open(_controls):
		return
	_assert_only_unknown(["LengthRow", "WidthRow"], "non-finite size")
	assert_dict(seen["errors"]).is_empty()
	assert_dict(seen["warnings"]).is_empty()


func test_ac09_broken_data_logs_no_error_of_its_own() -> void:
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void:
			var broken: Dictionary = {
				"name_key": "",
				"description_key": "",
				"volume_litres": 0,
				"glass_thickness_m": -1.0,
				"water_line_height_m": 0.0,
				"interior_size_m": Vector3(0.0, -1.0, 0.0),
			}
			if not await _open_override(broken):
				return
	)
	if _controls == null or not Ui.details_open(_controls):
		return
	assert_int(Ui.details_rows(_controls).size()).is_equal(8)
	for row_name: String in Ui.ROW_NAMES:
		assert_str(Ui.row_value(_controls, row_name)).is_equal("Unknown")
	assert_dict(seen["errors"]).is_empty()
	assert_dict(seen["warnings"]).is_empty()


func test_ac09_the_placeholder_is_hungarian_in_hungarian() -> void:
	await Ui.set_language(self, "hu")
	if not await _open_override({"volume_litres": 0}):
		return
	assert_str(Ui.row_value(_controls, "WaterVolumeRow")).is_equal("Ismeretlen")


# --- AC 10: nothing is clipped ---


func _window() -> SubViewport:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = WINDOW
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(auto_free(viewport))
	return viewport


func _longest_description_id(language: String) -> StringName:
	var longest: StringName = Table.IDS[0]
	for id: StringName in Table.IDS:
		if (
			String(Table.row(id)["description_" + language]).length()
			> String(Table.row(longest)["description_" + language]).length()
		):
			longest = id
	return longest


func _check_nothing_is_clipped(language: String) -> void:
	await Ui.set_language(self, language)
	var viewport: SubViewport = _window()
	var holder: Node = Node.new()
	viewport.add_child(holder)
	var longest: StringName = _longest_description_id(language)
	for id: StringName in Table.IDS:
		if not await _open_real(id, &"", holder):
			return
		await _wait()
		var panel: Control = Ui.details(_controls)
		var context: String = "%s %s" % [language, id]
		assert_vector(_controls.get_viewport().get_visible_rect().size).is_equal(Vector2(WINDOW))
		(
			assert_float(panel.size.x)
			. override_failure_message(
				"%s: panel width %s grew from the fixed width" % [context, panel.size.x]
			)
			. is_equal_approx(Ui.DETAILS_WIDTH, 1.0)
		)
		var panel_rect: Rect2 = panel.get_global_rect()
		(
			assert_bool(Rect2(Vector2.ZERO, Vector2(WINDOW)).encloses(panel_rect))
			. override_failure_message("%s: panel %s leaves the window" % [context, panel_rect])
			. is_true()
		)
		for node: Node in panel.find_children("*", "Label", true, false):
			var label: Label = node as Label
			if not label.is_visible_in_tree():
				continue
			var rect: Rect2 = label.get_global_rect()
			(
				assert_bool(panel_rect.grow(0.5).encloses(rect))
				. override_failure_message(
					"%s: %s %s sticks out of the panel %s" % [context, label.name, rect, panel_rect]
				)
				. is_true()
			)
			(
				assert_bool(label.clip_text)
				. override_failure_message("%s: %s clips its text" % [context, label.name])
				. is_false()
			)
			(
				assert_int(label.text_overrun_behavior)
				. override_failure_message("%s: %s trims its text" % [context, label.name])
				. is_equal(TextServer.OVERRUN_NO_TRIMMING)
			)
			if label.autowrap_mode != TextServer.AUTOWRAP_OFF:
				(
					assert_int(label.get_visible_line_count())
					. override_failure_message("%s: %s hides lines" % [context, label.name])
					. is_equal(label.get_line_count())
				)
		if id == longest:
			var description: Label = (
				(Ui.row(_controls, "DescriptionRow").find_child(Ui.VALUE_LABEL, true, false))
				as Label
			)
			(
				assert_int(description.get_line_count())
				. override_failure_message(
					(
						"%s: the longest description does not wrap (%d line)"
						% [context, description.get_line_count()]
					)
				)
				. is_greater(1)
			)
		_drop()


func test_ac10_nothing_is_clipped_at_1280x720_in_english() -> void:
	await _check_nothing_is_clipped("en")


func test_ac10_nothing_is_clipped_at_1280x720_in_hungarian() -> void:
	await _check_nothing_is_clipped("hu")
