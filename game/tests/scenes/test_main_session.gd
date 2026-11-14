extends GdUnitTestSuite
## #28 criterion 3 (session level; owner: developer): a new aquarium starts with Sand and its
## default colour, set by the session bootstrap (Main) through SubstrateSetup, with an empty undo
## history. Main.get_model() is the accessor of the technical plan; Main is reached by path and
## method name because the accessor does not exist before the implementation.

const Sub := preload("res://tests/helpers/substrate_api.gd")
const Ui := preload("res://tests/helpers/tank_ui_rig.gd")

const MAIN_SCENE := "res://scenes/main.tscn"

var _saved_locale: String = ""
var _language_state: Dictionary = {}
var _main: Node = null


func before_test() -> void:
	_saved_locale = TranslationServer.get_locale()
	_language_state = Ui.begin_language_isolation("main_session")


func after_test() -> void:
	Ui.end_language_isolation(_language_state, _saved_locale)


func _open_main() -> bool:
	var scene: PackedScene = load(MAIN_SCENE) as PackedScene
	_main = scene.instantiate()
	add_child(_main)
	auto_free(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	var has_getter: bool = _main.has_method("get_model")
	assert_bool(has_getter).override_failure_message("Main.get_model() is missing").is_true()
	return has_getter


func test_ac03_a_new_session_starts_with_sand_and_the_decided_cream() -> void:
	if not await _open_main():
		return
	var model: AquariumModel = _main.call("get_model") as AquariumModel
	assert_object(model).is_not_null()
	assert_that(model.get_substrate_id()).is_equal(Sub.SAND)
	assert_bool(Sub.same_colour(model.get_substrate_colour(), Sub.SAND_DEFAULT)).is_true()


func test_ac03_the_session_colour_is_the_catalog_default_of_sand() -> void:
	if not await _open_main():
		return
	var model: AquariumModel = _main.call("get_model") as AquariumModel
	var catalog: RefCounted = Sub.catalog()
	(
		assert_bool(
			Sub.same_colour(model.get_substrate_colour(), Sub.default_colour(catalog, Sub.SAND))
		)
		. is_true()
	)


func test_ac03_the_history_is_empty_after_the_start() -> void:
	if not await _open_main():
		return
	var history: CommandHistory = _main.get("history") as CommandHistory
	assert_object(history).is_not_null()
	assert_bool(history.can_undo()).is_false()
	assert_bool(history.can_redo()).is_false()
	assert_int(history.get_undo_count()).is_equal(0)


func test_ac03_the_default_is_not_an_undoable_step() -> void:
	if not await _open_main():
		return
	var history: CommandHistory = _main.get("history") as CommandHistory
	var model: AquariumModel = _main.call("get_model") as AquariumModel
	assert_bool(history.undo()).is_false()
	assert_that(model.get_substrate_id()).is_equal(Sub.SAND)
