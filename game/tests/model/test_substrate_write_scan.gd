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
## The bed, the view, the job and the room only read the model (technical plan v3, section 2).
const READERS: Array[String] = [
	"res://scenes/room/room_corner.gd",
	"res://scenes/tank/substrate/substrate_bed.gd",
	"res://scenes/tank/substrate/substrate_bed_view.gd",
	"res://scenes/tank/substrate/substrate_assembly_job.gd",
]
## The files that run on a worker thread (technical plan 1.8): the pure assembly, its input, the
## data objects, the bake reader and the cancel token.
const WORKER_FILES: Array[String] = [
	"res://scenes/tank/substrate/substrate_assembler.gd",
	"res://scenes/tank/substrate/substrate_assembly_input.gd",
	"res://scenes/tank/substrate/substrate_bed_data.gd",
	"res://scenes/tank/substrate/substrate_chunk_data.gd",
	"res://scenes/tank/substrate/substrate_bake_data.gd",
	"res://scenes/tank/substrate/substrate_cancel_token.gd",
]
## What a worker file must not use: scene nodes and the tree, loading, the render server, MultiMesh,
## signals and the autoloads (reading the bake file with FileAccess is allowed).
const WORKER_FORBIDDEN: Array[String] = [
	"\\b(Node|Node2D|Node3D|SceneTree|Viewport|Window)\\b",
	"\\b(get_tree|get_node|get_node_or_null|add_child|call_deferred)\\b",
	"(?<![\\w.])(load|preload)\\s*\\(",
	"\\b(ResourceLoader|RenderingServer|MultiMesh|MultiMeshInstance3D|MeshInstance3D)\\b",
	"\\b(emit_signal|connect)\\s*\\(|\\.emit\\s*\\(|\\bsignal\\s",
	"\\b(EventBus|Localization|Settings)\\b",
]
## Unseeded or engine-version dependent randomness: the global random functions, randomize() and
## hash() (technical plan 1.6). A seeded RandomNumberGenerator instance is the sanctioned way.
const NONDETERMINISM: Array[String] = [
	(
		"(?<![\\w.])(randi|randf|randi_range|randf_range|randfn|randomize|"
		+ "rand_from_seed|seed|hash)\\s*\\("
	),
	"\\.(randomize|hash)\\s*\\(",
]
const SUBSTRATE_DIR := "res://scenes/tank/substrate/"
const INPUT_PATH := "res://scenes/tank/substrate/substrate_assembly_input.gd"
## The scripts outside the catalog that may name fill_depth_m: the surface helper, and the assembly
## input with its own plain-value field (plan 3.1).
const FILL_DEPTH_HOLDERS: Array[String] = [
	"res://model/substrate_surface.gd",
	INPUT_PATH,
]
## Calls of the model's writers: apply_(set|insert|remove|replace)_*, reset_from, set_save_times.
const MODEL_WRITER_CALLS: Array[String] = [
	"\\bapply_(set|insert|remove|replace)_\\w+\\s*\\(",
	"\\breset_from\\s*\\(",
	"\\bset_save_times\\s*\\(",
]
## Every apply_ writer the model declares must match this, or MODEL_WRITER_CALLS falls behind.
const MODEL_WRITER_PREFIX := "^apply_(set|insert|remove|replace)_"
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


func test_ac18_the_chooser_the_room_the_bed_the_view_and_the_job_never_write_the_model() -> void:
	for path: String in [
		"res://ui/tank/substrate_chooser.gd",
		"res://scenes/room/room_corner.gd",
		"res://scenes/tank/substrate/substrate_bed.gd",
		"res://scenes/tank/substrate/substrate_bed_view.gd",
		"res://scenes/tank/substrate/substrate_assembly_job.gd",
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


## The model's writers, an allowlist of their prefixes (code-reviewer decision, issue #28 comment
## 6958042040): apply_(set|insert|remove|replace)_*, reset_from and set_save_times. Other apply_*
## helpers (WaterFogSettings.apply_to_*, private _apply_* methods) are not model writers. A guard
## over aquarium_model.gd keeps the allowlist in step with the model.
func test_ac18_the_bed_the_view_the_job_and_the_room_never_call_a_model_writer() -> void:
	var declared: PackedStringArray = PackedStringArray()
	var declaration: RegEx = RegEx.create_from_string("\\bfunc\\s+(apply_\\w+)")
	for hit: RegExMatch in declaration.search_all(_source("res://model/aquarium_model.gd")):
		declared.append(hit.get_string(1))
	(
		assert_array(declared)
		. override_failure_message("res://model/aquarium_model.gd declares no apply_ writer")
		. is_not_empty()
	)
	var known: RegEx = RegEx.create_from_string(MODEL_WRITER_PREFIX)
	for writer: String in declared:
		(
			assert_object(known.search(writer))
			. override_failure_message(
				(
					"model writer %s is not covered by %s; the scan pattern needs extending"
					% [writer, MODEL_WRITER_PREFIX]
				)
			)
			. is_not_null()
		)
	var patterns: Array[RegEx] = SourceScan.compile(PackedStringArray(MODEL_WRITER_CALLS))
	for path: String in READERS:
		var source: String = _source(path)
		assert_str(source).override_failure_message("%s is missing or empty" % path).is_not_empty()
		var hits: PackedStringArray = SourceScan.find_matches(source, patterns)
		(
			assert_array(hits)
			. override_failure_message("%s calls a model writer: %s" % [path, hits])
			. is_empty()
		)


## The assembly input keeps the depth in its own plain field fill_depth_m (plan 3.1, code-reviewer
## decision, issue #28 comment 6957252973); it only receives the depth and never reads a
## SubstrateDefinition.
func test_ac18_fill_depth_m_is_read_only_through_the_surface_helper_and_the_catalog() -> void:
	var found: PackedStringArray = _scripts_matching("\\bfill_depth_m\\b")
	for path: String in found:
		(
			assert_bool(path.begins_with("res://catalog/") or FILL_DEPTH_HOLDERS.has(path))
			. override_failure_message(
				"%s reads fill_depth_m; only SubstrateSurface and the catalog may" % path
			)
			. is_true()
		)
	var input_source: String = _source(INPUT_PATH)
	assert_str(input_source).override_failure_message("%s is missing" % INPUT_PATH).is_not_empty()
	(
		assert_str(input_source)
		. override_failure_message(
			"%s must receive the depth, not read it from a SubstrateDefinition" % INPUT_PATH
		)
		. not_contains("SubstrateDefinition")
	)
	(
		assert_bool(found.has("res://model/substrate_surface.gd"))
		. override_failure_message("model/substrate_surface.gd does not read fill_depth_m")
		. is_true()
	)


func test_ac18_no_unseeded_or_engine_dependent_randomness_in_the_substrate_scripts() -> void:
	var paths: PackedStringArray = SourceScan.list_scripts(SUBSTRATE_DIR, PackedStringArray())
	(
		assert_array(paths)
		. override_failure_message("no scripts under %s" % SUBSTRATE_DIR)
		. is_not_empty()
	)
	var patterns: Array[RegEx] = SourceScan.compile(PackedStringArray(NONDETERMINISM))
	for path: String in paths:
		var hits: PackedStringArray = SourceScan.find_matches(_source(path), patterns)
		(
			assert_array(hits)
			. override_failure_message(
				"%s uses unseeded or engine-version dependent randomness: %s" % [path, hits]
			)
			. is_empty()
		)


func test_ac18_the_assembler_uses_one_seeded_random_number_generator() -> void:
	var source: String = _source(SUBSTRATE_DIR + "substrate_assembler.gd")
	assert_str(source).is_not_empty()
	assert_str(source).contains("RandomNumberGenerator")
	assert_str(source).contains("seed_for")


func test_ac18_the_worker_files_hold_no_node_load_render_server_signal_or_autoload() -> void:
	var patterns: Array[RegEx] = SourceScan.compile(PackedStringArray(WORKER_FORBIDDEN))
	for path: String in WORKER_FILES:
		var source: String = _source(path)
		assert_str(source).override_failure_message("%s is missing or empty" % path).is_not_empty()
		var hits: PackedStringArray = SourceScan.find_matches(source, patterns)
		(
			assert_array(hits)
			. override_failure_message("%s is a worker-thread file but uses %s" % [path, hits])
			. is_empty()
		)


func test_ac18_the_worker_files_extend_ref_counted_and_the_token_holds_a_mutex() -> void:
	for path: String in WORKER_FILES:
		assert_str(_source(path)).override_failure_message(path).contains("extends RefCounted")
	assert_str(_source(SUBSTRATE_DIR + "substrate_cancel_token.gd")).contains("Mutex")


func test_ac18_the_flat_layer_files_are_gone() -> void:
	for path: String in [
		"res://scenes/tank/substrate_layer.gd",
		"res://shaders/substrate.gdshader",
		"res://assets/tank/materials/substrate.tres",
	]:
		(
			assert_bool(FileAccess.file_exists(path))
			. override_failure_message("%s still exists" % path)
			. is_false()
		)
	assert_array(_scripts_matching("\\bSubstrateLayer\\b")).is_empty()
