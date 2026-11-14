extends GdUnitTestSuite
## #28 criterion 18 (owner: developer): the substrate changes only through the Command. The model
## stays catalog-free and pure data. Static scans of the game sources (tests, addons and .godot are
## excluded), pattern of test_apply_mutator_scan.gd. Named exceptions of the technical plan and
## ADR 0010: SubstrateSetup.apply_default (called from scenes/main.gd) and SubstrateSetup.normalise
## (called from systems/save_store.gd) are the only non-Command writers; both live in the model
## folder. TankControls is the only place that builds a SetSubstrateCommand. No script outside the
## catalog reads the Mode 2 fields (BA decision Q13).

const SourceScan := preload("res://tests/helpers/source_scan.gd")

const EXCLUDED := ["res://tests/", "res://addons/", "res://.godot/"]
const NEW_WRITERS: Array[String] = [
	"res://model/set_substrate_command.gd",
	"res://model/substrate_setup.gd",
]
## The model and the codec (which fills a fresh model while decoding) write by construction.
const WRITERS: Array[String] = [
	"res://model/aquarium_model.gd",
	"res://model/save_codec.gd",
	"res://model/set_substrate_command.gd",
	"res://model/substrate_setup.gd",
]
const SETUP_CALLERS: Array[String] = [
	"res://model/substrate_setup.gd",
	"res://scenes/main.gd",
	"res://systems/save_store.gd",
]
const COMMAND_USERS: Array[String] = [
	"res://model/set_substrate_command.gd",
	"res://ui/tank/tank_controls.gd",
]
const MODE_2_PATTERN := (
	"\\b(ph_effect|hardness_effect|bulk_density_kg_per_l|rooting_suitability|"
	+ "nutrient_retention|burrowing_suitability|edge_smoothness|waste_trapping|"
	+ "cleaning_difficulty|grain_size_min_mm|grain_size_max_mm)\\b"
)


## Paths of the scripts whose comment-free source matches the expression.
func _scripts_matching(expression: String) -> PackedStringArray:
	var patterns: Array[RegEx] = SourceScan.compile(PackedStringArray([expression]))
	var found: PackedStringArray = PackedStringArray()
	for path: String in SourceScan.list_scripts("res://", PackedStringArray(EXCLUDED)):
		var source: String = SourceScan.strip_comments(SourceScan.read(path))
		if not SourceScan.find_matches(source, patterns).is_empty():
			found.append(path)
	found.sort()
	return found


func _source(path: String) -> String:
	return SourceScan.strip_comments(SourceScan.read(path))


func test_ac18_the_new_files_exist_so_the_scans_are_not_vacuous() -> void:
	for path: String in [
		"res://model/set_substrate_command.gd",
		"res://model/substrate_setup.gd",
		"res://catalog/substrate_catalog.gd",
		"res://catalog/substrate_definition.gd",
	]:
		(
			assert_bool(ResourceLoader.exists(path))
			. override_failure_message("%s is missing" % path)
			. is_true()
		)


func test_ac18_apply_set_substrate_is_called_only_from_the_model_writers() -> void:
	var found: PackedStringArray = _scripts_matching("\\bapply_set_substrate\\s*\\(")
	for path: String in found:
		(
			assert_bool(WRITERS.has(path))
			. override_failure_message(
				"%s calls apply_set_substrate; only %s may" % [path, WRITERS]
			)
			. is_true()
		)
	for path: String in WRITERS:
		(
			assert_bool(found.has(path))
			. override_failure_message("%s does not call apply_set_substrate" % path)
			. is_true()
		)


func test_ac18_the_command_and_the_setup_write_through_apply_set_substrate_only() -> void:
	for path: String in NEW_WRITERS:
		var source: String = _source(path)
		assert_str(source).override_failure_message("%s: empty or missing" % path).is_not_empty()
		for forbidden: String in [
			"apply_set_name",
			"apply_set_tank_id",
			"apply_set_heightmap",
			"apply_insert_",
			"apply_remove_",
			"apply_replace_",
			"reset_from",
			"set_save_times"
		]:
			(
				assert_str(source)
				. override_failure_message("%s must not call %s" % [path, forbidden])
				. not_contains(forbidden)
			)


func test_ac18_substrate_setup_is_called_only_from_the_session_and_the_save_store() -> void:
	var found: PackedStringArray = _scripts_matching("\\bSubstrateSetup\\b")
	for path: String in found:
		(
			assert_bool(SETUP_CALLERS.has(path))
			. override_failure_message(
				"%s uses SubstrateSetup; only %s may" % [path, SETUP_CALLERS]
			)
			. is_true()
		)
	assert_bool(found.has("res://scenes/main.gd")).is_true()
	assert_bool(found.has("res://systems/save_store.gd")).is_true()


func test_ac18_the_session_applies_the_default_and_the_store_normalises() -> void:
	assert_str(_source("res://scenes/main.gd")).contains("SubstrateSetup.apply_default")
	assert_str(_source("res://systems/save_store.gd")).contains("SubstrateSetup.normalise")


func test_ac18_only_tank_controls_builds_the_set_substrate_command() -> void:
	var found: PackedStringArray = _scripts_matching("\\bSetSubstrateCommand\\b")
	for path: String in found:
		(
			assert_bool(COMMAND_USERS.has(path))
			. override_failure_message("%s uses SetSubstrateCommand" % path)
			. is_true()
		)
	assert_bool(found.has("res://ui/tank/tank_controls.gd")).is_true()


func test_ac18_the_chooser_the_room_and_the_layer_never_write_the_model() -> void:
	for path: String in [
		"res://ui/tank/substrate_chooser.gd",
		"res://scenes/room/room_corner.gd",
		"res://scenes/tank/substrate_layer.gd",
	]:
		var source: String = _source(path)
		assert_str(source).override_failure_message("%s is missing" % path).is_not_empty()
		assert_str(source).not_contains("apply_set_substrate")
		assert_str(source).not_contains("SetSubstrateCommand")
		assert_str(source).not_contains("SubstrateSetup")
		assert_str(source).not_contains("reset_from")


func test_ac18_the_model_and_the_codec_stay_catalog_free() -> void:
	for path: String in ["res://model/aquarium_model.gd", "res://model/save_codec.gd"]:
		var source: String = _source(path)
		assert_str(source).is_not_empty()
		for forbidden: String in ["SubstrateCatalog", "SubstrateDefinition", "SubstrateSetup"]:
			(
				assert_str(source)
				. override_failure_message(
					"%s must stay catalog-free but mentions %s" % [path, forbidden]
				)
				. not_contains(forbidden)
			)


func test_ac18_the_new_model_files_hold_no_node_and_no_event_bus() -> void:
	for path: String in ["res://model/set_substrate_command.gd", "res://model/substrate_setup.gd"]:
		var source: String = _source(path)
		assert_str(source).is_not_empty()
		for forbidden: String in [
			"extends Node", "extends Control", "EventBus", "get_tree", "add_child"
		]:
			(
				assert_str(source)
				. override_failure_message(
					"%s must stay pure data but mentions %s" % [path, forbidden]
				)
				. not_contains(forbidden)
			)
	assert_str(_source("res://model/substrate_setup.gd")).contains("extends RefCounted")
	assert_str(_source("res://model/set_substrate_command.gd")).contains("extends Command")


func test_ac18_no_script_outside_the_catalog_reads_the_layer_depth() -> void:
	for path: String in _scripts_matching("layer_depth_"):
		(
			assert_bool(path.begins_with("res://catalog/"))
			. override_failure_message(
				"%s reads layer_depth_*; it is a catalog-only Mode 2 field" % path
			)
			. is_true()
		)


func test_ac18_no_script_outside_the_catalog_reads_the_other_mode_2_fields() -> void:
	for path: String in _scripts_matching(MODE_2_PATTERN):
		(
			assert_bool(path.begins_with("res://catalog/"))
			. override_failure_message("%s uses a Mode 2 substrate field in Mode 1 code" % path)
			. is_true()
		)


func test_ac18_compaction_risk_is_nowhere() -> void:
	assert_array(_scripts_matching("compaction_risk")).is_empty()
	for file_name: String in DirAccess.get_files_at("res://catalog/substrates"):
		if file_name.ends_with(".tres"):
			var text: String = FileAccess.get_file_as_string(
				"res://catalog/substrates/".path_join(file_name)
			)
			assert_str(text).not_contains("compaction_risk")
