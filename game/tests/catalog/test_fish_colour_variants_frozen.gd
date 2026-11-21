extends GdUnitTestSuite
## #34 AC 4 (owner: developer, the snapshot is written last from the final colours): the
## colour_variants of every species are append-only because a saved fish stores `variant` as an
## index. The shipped catalog must keep every snapshot colour at its index
## (game/tests/data/colour_variants_frozen.json: species id to hex strings). Appending a colour
## passes without editing the snapshot. The synthetic cases show that removing a species,
## removing a colour, reordering two colours and changing a colour each fail with a message that
## names the species and the index. The synthetic cases use the comparison helper alone and pass
## before the implementation; the shipped test fails until the snapshot and the catalog exist.

const Api := preload("res://tests/helpers/fish_api.gd")
const Snapshot := preload("res://tests/helpers/fish_variant_snapshot.gd")

const FROZEN: Dictionary = {
	"neon_tetra": ["#112233", "#445566"],
	"angelfish": ["#aabbcc", "#ddeeff", "#010203"],
}


func _failures(current: Dictionary) -> PackedStringArray:
	return Snapshot.failures(FROZEN, current)


func _copy() -> Dictionary:
	return FROZEN.duplicate(true)


# --- the shipped catalog against the committed snapshot ---


func test_ac04_the_snapshot_file_exists_and_covers_the_three_species() -> void:
	var snapshot: Dictionary = Snapshot.load_snapshot()
	(
		assert_bool(snapshot.is_empty())
		. override_failure_message("%s is missing or not a JSON object" % Snapshot.SNAPSHOT_PATH)
		. is_false()
	)
	for id: StringName in Api.IDS:
		(
			assert_bool(snapshot.has(str(id)))
			. override_failure_message("the snapshot has no species %s" % id)
			. is_true()
		)


func test_ac04_the_snapshot_counts_match_the_issue_variants() -> void:
	var snapshot: Dictionary = Snapshot.load_snapshot()
	var expected: Dictionary = {"neon_tetra": 2, "angelfish": 3, "bronze_corydoras": 2}
	for id: String in expected:
		var list: Array = snapshot.get(id, [])
		(
			assert_int(list.size())
			. override_failure_message("snapshot of %s has %d colours" % [id, list.size()])
			. is_equal(expected[id])
		)


func test_ac04_every_snapshot_colour_is_still_at_its_index_in_the_shipped_catalog() -> void:
	var catalog: RefCounted = Api.shipped()
	assert_object(catalog).override_failure_message("FishCatalog is missing").is_not_null()
	if catalog == null:
		return
	var snapshot: Dictionary = Snapshot.load_snapshot()
	assert_bool(snapshot.is_empty()).override_failure_message("no snapshot").is_false()
	var definitions: Array = []
	for id: StringName in catalog.call("get_ids"):
		definitions.append(catalog.call("get_definition", id))
	var problems: PackedStringArray = Snapshot.failures(snapshot, Snapshot.hex_lists(definitions))
	assert_str("\n".join(problems)).is_empty()


# --- synthetic data: the failure cases name the species and the index ---


func test_ac04_edge_an_unchanged_list_passes() -> void:
	assert_int(_failures(_copy()).size()).is_equal(0)


func test_ac04_edge_appending_a_colour_passes() -> void:
	var current: Dictionary = _copy()
	(current["neon_tetra"] as Array).append("#777777")
	current["new_species"] = ["#000000"]
	assert_int(_failures(current).size()).is_equal(0)


func test_ac04_edge_a_removed_species_fails_and_names_it() -> void:
	var current: Dictionary = _copy()
	current.erase("angelfish")
	var found: PackedStringArray = _failures(current)
	assert_int(found.size()).is_equal(1)
	assert_str(found[0]).contains("angelfish")


func test_ac04_edge_a_removed_colour_fails_and_names_species_and_index() -> void:
	var current: Dictionary = _copy()
	(current["angelfish"] as Array).remove_at(2)
	var found: PackedStringArray = _failures(current)
	assert_int(found.size()).is_equal(1)
	assert_str(found[0]).contains("angelfish")
	assert_str(found[0]).contains("2")


func test_ac04_edge_two_reordered_colours_fail_and_name_species_and_index() -> void:
	var current: Dictionary = _copy()
	var list: Array = current["neon_tetra"]
	var first: Variant = list[0]
	list[0] = list[1]
	list[1] = first
	var found: PackedStringArray = _failures(current)
	assert_int(found.size()).is_greater_equal(1)
	assert_str(found[0]).contains("neon_tetra")
	assert_str(found[0]).contains("0")


func test_ac04_edge_a_changed_colour_fails_and_names_species_and_index() -> void:
	var current: Dictionary = _copy()
	(current["angelfish"] as Array)[1] = "#ddeef0"
	var found: PackedStringArray = _failures(current)
	assert_int(found.size()).is_equal(1)
	assert_str(found[0]).contains("angelfish")
	assert_str(found[0]).contains("1")


func test_ac04_edge_hex_case_does_not_matter() -> void:
	var current: Dictionary = _copy()
	current["neon_tetra"] = ["#112233", "#445566".to_upper()]
	assert_int(_failures(current).size()).is_equal(0)
