extends GdUnitTestSuite
## #35 docs (owner: tester): docs/architecture.md and the two ADRs of the technical plan name the
## decided facts, so a later edit cannot drop them unnoticed: the five group styles and the new
## behaviour fields in the catalog schema, the three EventBus fish signals, `poses_moved` and the
## per-frame driver in the fish rows, ADR 0015 (accepted for the #35 pull request, gated by
## needs:owner) and ADR 0013 Amendment 1 (rules 3, 5 and 8). Pattern of test_settings_docs.gd.
## Test decisions: facts are checked as short phrases, not as sentences, so wording can change.

const ARCHITECTURE := "docs/architecture.md"
const ADR_15 := (
	"docs/adr/" + "0015-fish-swimming-steering-model-tuning-inputs-and-per-frame-driver.md"
)
const ADR_13 := (
	"docs/adr/" + "0013-fish-presentation-mask-layout-shader-contract-and-derived-resting-pose.md"
)


func _read(path: String) -> String:
	var root: String = ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	return FileAccess.get_file_as_string(root.path_join(path))


func _contains_all(path: String, phrases: PackedStringArray) -> void:
	var text: String = _read(path)
	assert_str(text).override_failure_message("%s was not read" % path).is_not_empty()
	for phrase: String in phrases:
		(
			assert_bool(text.contains(phrase))
			. override_failure_message("%s does not contain %s" % [path, phrase])
			. is_true()
		)


func test_35_architecture_lists_the_group_style_enum_and_the_behaviour_fields() -> void:
	_contains_all(
		ARCHITECTURE,
		[
			(
				"enum GroupStyle { UNSET = 0, SOLITARY = 1, TIGHT_SCHOOL = 2, "
				+ "LOOSE_GROUP = 3, FORAGING_GROUP = 4 }"
			),
			"idle_share",
			"dart_interval_min_s",
			"dart_duration_max_s",
			"turn_rate_max_deg_s",
			"pitch_limit_deg",
			"nose_down_bias_deg",
		]
	)


func test_35_architecture_names_the_three_fish_signals_the_driver_and_the_labels_contract() -> void:
	_contains_all(
		ARCHITECTURE,
		[
			"fish_pause_requested(paused)",
			"fish_override_requested(uid, target)",
			"fish_override_cleared(uid)",
			"poses_moved",
			"FishSwimSim",
			"FishPersonality",
			"fish_swim_tuning.tres",
			"no `_process`",
		]
	)


func test_35_adr_0015_is_accepted_for_the_pull_request_and_gated_by_the_owner() -> void:
	_contains_all(
		ADR_15,
		[
			"Status: Accepted",
			"needs:owner",
			"fish.trait.speed",
			"fish.trait.depth_preference",
			"FishSwimTuning",
			"begin_recovery",
			"poses_moved",
			"FishTailPhase",
		]
	)


func test_35_adr_0013_carries_amendment_1_for_rules_3_5_and_8() -> void:
	_contains_all(ADR_13, ["Amendment 1", "poses_moved", "swim_phase"])
