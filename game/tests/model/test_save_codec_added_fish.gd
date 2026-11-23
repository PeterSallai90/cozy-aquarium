extends GdUnitTestSuite
## #36 save format unchanged (owner: developer): a fish built by AddFishCommand.make_fish is saved
## with "nickname": "" and the current format_version (no new field, no bump); a round trip keeps
## the empty nickname, so the derived default name key is the same after loading.

const Edit := preload("res://tests/helpers/fish_edit_api.gd")
const Api := preload("res://tests/helpers/fish_api.gd")
const SaveFixtures := preload("res://tests/helpers/save_fixtures.gd")

const STAMP := "2026-11-01T12:00:00Z"
const UID := "f1000001"


func _model_with_made_fish() -> AquariumModel:
	var model: AquariumModel = AquariumModel.new(STAMP)
	var species: FishSpecies = Api.species(Api.ANGEL) as FishSpecies
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 3
	var fish: FishInstance = Edit.make_fish(UID, species, rng)
	(
		assert_object(fish)
		. override_failure_message("AddFishCommand.make_fish is missing")
		. is_not_null()
	)
	if fish != null:
		model.apply_insert_fish(fish, 0)
	return model


func test_36_a_made_fish_is_saved_with_an_empty_nickname_and_format_version_1() -> void:
	var model: AquariumModel = _model_with_made_fish()
	var result: SaveResult = SaveCodec.new().encode(model, STAMP)
	assert_int(result.kind).is_equal(SaveResult.Kind.OK)
	var data: Dictionary = JSON.parse_string(result.text)
	assert_int(int(data["format_version"])).is_equal(SaveCodec.FORMAT_VERSION)
	assert_int(SaveCodec.FORMAT_VERSION).is_equal(1)
	var fish: Array = data["fish"]
	assert_int(fish.size()).is_equal(1)
	if fish.is_empty():
		return
	var entry: Dictionary = fish[0]
	assert_str(entry["nickname"]).is_empty()
	assert_array(entry.keys()).is_equal(["uid", "species_id", "variant", "nickname"])


func test_36_the_empty_nickname_round_trips_and_the_derived_key_is_unchanged() -> void:
	var model: AquariumModel = _model_with_made_fish()
	var encoded: SaveResult = SaveCodec.new().encode(model, STAMP)
	var decoded: SaveResult = SaveCodec.new().decode(encoded.text, STAMP)
	assert_int(decoded.kind).is_equal(SaveResult.Kind.OK)
	var loaded: AquariumModel = SaveFixtures.model_of(decoded)
	assert_int(loaded.get_fish_count()).is_equal(1)
	if loaded.get_fish(UID) == null:
		return
	assert_str(loaded.get_fish(UID).nickname).is_empty()
	assert_str(Edit.key_for(loaded.get_fish(UID).uid)).is_equal(Edit.key_for(UID))
	assert_str(Edit.key_for(UID)).is_equal("fish.default_name.21")
