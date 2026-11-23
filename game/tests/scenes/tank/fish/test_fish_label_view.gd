# gdlint: disable=max-public-methods
extends GdUnitTestSuite
## #164 FishLabelView (owner: tester; res://scenes/tank/fish/fish_label_view.gd), the sibling of
## FishView in the tank frame. With [fish] show_names on it shows one Label3D per drawn fish whose
## text is the shown name (the same string as the panel row), above the fish at the rest pose
## position + UP * (scaled above_m + 0.02 m), never turned with the fish. Off (the default) or
## with no tank: no label node at all. It follows add, remove, undo, redo, reset, variant, tank,
## substrate, heightmap, nickname and language changes, has no per-frame code and listens to no
## model signal (the addendum conditions). Test decisions where the plan is silent: the label view
## is set up after the view, as the room does; the label position is read in the view frame (the
## rig puts both under one identity host); the expected anchor uses the rig's own measure of the
## species model (never FishView.get_extents).

const Api := preload("res://tests/helpers/fish_api.gd")
const FishRig := preload("res://tests/helpers/fish_view_rig.gd")
const LabelRig := preload("res://tests/helpers/fish_label_rig.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")
const SaveFixtures := preload("res://tests/helpers/save_fixtures.gd")
const SettingsRig := preload("res://tests/helpers/settings_rig.gd")
const Ui := preload("res://tests/helpers/tank_ui_rig.gd")

const TRIO: Array[String] = ["f1000001", "f1000003", "f1000006"]
const MIN_TURN_DEG: float = 30.0

var _dir: String = ""
var _saved_locale: String = ""
var _language_state: Dictionary = {}
var _open_rigs: Array[LabelRig.LabelRig] = []


func before_test() -> void:
	_dir = SaveFixtures.make_dir("fish_label_view")
	_saved_locale = TranslationServer.get_locale()
	_language_state = Ui.begin_language_isolation("fish_label_view_lang")
	TranslationServer.set_locale("en")
	_open_rigs = []


func after_test() -> void:
	for lr: LabelRig.LabelRig in _open_rigs:
		LabelRig.close(lr)
	Ui.end_language_isolation(_language_state, _saved_locale)
	SaveFixtures.remove_dir(_dir)
	SaveFixtures.remove_root_if_empty()


func _path() -> String:
	return LabelRig.settings_path(_dir)


## The rig; null (after a failed assertion) while a class is missing.
func _open(
	source: AquariumModel, show_names: bool = true, catalog: RefCounted = null
) -> LabelRig.LabelRig:
	var lr: LabelRig.LabelRig = LabelRig.open(self, source, _path(), show_names, catalog)
	_open_rigs.append(lr)
	(
		assert_object(lr.rig.view)
		. override_failure_message("FishView script is missing or has no setup()")
		. is_not_null()
	)
	(
		assert_object(LabelRig.key())
		. override_failure_message("FishSettingKeys.show_names() is missing")
		. is_not_null()
	)
	(
		assert_object(lr.labels)
		. override_failure_message("FishLabelView script is missing or has no setup()")
		. is_not_null()
	)
	if lr.labels == null or lr.rig.view == null or LabelRig.key() == null:
		return null
	return lr


func _frame() -> void:
	await get_tree().process_frame


func _check_anchors(lr: LabelRig.LabelRig, uids: Array[String], context: String) -> void:
	for uid: String in uids:
		var label: Label3D = LabelRig.label_of(lr, uid)
		(
			assert_object(label)
			. override_failure_message("%s: no label for %s" % [context, uid])
			. is_not_null()
		)
		if label == null:
			continue
		var want: Vector3 = LabelRig.expected_anchor(lr, uid)
		(
			assert_vector(label.position)
			. override_failure_message(
				"%s: label of %s at %s, expected %s" % [context, uid, label.position, want]
			)
			. is_equal_approx(want, Vector3.ONE * LabelRig.TOLERANCE_M)
		)


# --- off by default, on by the setting ---


func test_fresh_install_has_no_label_and_the_label_view_is_hidden() -> void:
	var lr: LabelRig.LabelRig = _open(FishRig.trio(), false)
	if lr == null:
		return
	for uid: String in TRIO:
		assert_object(LabelRig.label_of(lr, uid)).is_null()
	assert_int(LabelRig.all_labels(lr).size()).is_equal(0)
	assert_int(lr.labels.get_child_count()).is_equal(0)
	assert_bool(lr.labels.visible).is_false()


func test_turning_the_setting_on_shows_one_visible_label_per_fish_with_the_shown_name() -> void:
	var source: AquariumModel = FishRig.trio()
	source.get_fish("f1000003").nickname = "Goldie"
	var lr: LabelRig.LabelRig = _open(source, false)
	if lr == null:
		return
	LabelRig.set_names(lr, true)
	assert_bool(lr.labels.visible).is_true()
	assert_int(LabelRig.all_labels(lr).size()).is_equal(3)
	for entry: FishInstance in source.get_fish_list():
		var label: Label3D = LabelRig.label_of(lr, entry.uid)
		assert_object(label).override_failure_message("no label for %s" % entry.uid).is_not_null()
		if label == null:
			continue
		assert_bool(label.visible).is_true()
		assert_str(label.text).is_equal(LabelRig.shown_text(entry, self))
	assert_str(LabelRig.label_of(lr, "f1000003").text).is_equal("Goldie")


func test_turning_the_setting_off_removes_every_label_at_once() -> void:
	var lr: LabelRig.LabelRig = _open(FishRig.trio())
	if lr == null:
		return
	assert_int(LabelRig.all_labels(lr).size()).is_equal(3)
	LabelRig.set_names(lr, false)
	assert_int(lr.labels.get_child_count()).is_equal(0)
	assert_int(LabelRig.all_labels(lr).size()).is_equal(0)
	assert_bool(lr.labels.visible).is_false()


func test_one_setting_changed_per_real_change_and_none_for_the_same_value() -> void:
	var lr: LabelRig.LabelRig = _open(FishRig.trio(), false)
	if lr == null:
		return
	LabelRig.set_names(lr, true)
	assert_array(lr.changes).is_equal([true])
	LabelRig.set_names(lr, true)
	assert_array(lr.changes).is_equal([true])
	assert_int(LabelRig.all_labels(lr).size()).is_equal(3)
	LabelRig.set_names(lr, false)
	assert_array(lr.changes).is_equal([true, false])
	assert_int(LabelRig.all_labels(lr).size()).is_equal(0)


func test_an_unrelated_setting_change_leaves_the_labels_alone() -> void:
	var lr: LabelRig.LabelRig = _open(FishRig.trio())
	if lr == null:
		return
	var before: Label3D = LabelRig.label_of(lr, "f1000001")
	EventBus.setting_changed.emit("audio", "volume", 0.3)
	EventBus.setting_changed.emit("fish", "other_key", true)
	assert_object(LabelRig.label_of(lr, "f1000001")).is_same(before)
	assert_int(LabelRig.all_labels(lr).size()).is_equal(3)


func test_the_choice_survives_a_restart() -> void:
	var first: Node = auto_free(SettingsRig.make_settings(self, _path()))
	if first == null or LabelRig.key() == null:
		assert_bool(false).override_failure_message("Settings or FishSettingKeys missing").is_true()
		return
	first.set_value(LabelRig.key(), true)
	var lr: LabelRig.LabelRig = _open(FishRig.trio(), false)
	if lr == null:
		return
	assert_int(LabelRig.all_labels(lr).size()).is_equal(3)
	assert_bool(lr.labels.visible).is_true()


func test_a_wrong_typed_or_missing_value_gives_no_label() -> void:
	SaveFixtures.write_text(_path(), '[fish]\nshow_names = "yes"\n')
	var lr: LabelRig.LabelRig = _open(FishRig.trio(), false)
	if lr == null:
		return
	assert_int(LabelRig.all_labels(lr).size()).is_equal(0)
	SaveFixtures.write_text(_path(), '[general]\nlanguage = "en"\n')
	var second: LabelRig.LabelRig = _open(FishRig.trio(), false)
	if second == null:
		return
	assert_int(LabelRig.all_labels(second).size()).is_equal(0)


func test_a_damaged_settings_file_gives_no_label_and_no_crash() -> void:
	SaveFixtures.write_text(_path(), "this is [not valid\n==")
	var holder: Array = []
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void: holder.append(_open(FishRig.trio(), false))
	)
	var lr: LabelRig.LabelRig = holder[0]
	if lr == null:
		return
	assert_int(LabelRig.all_labels(lr).size()).is_equal(0)
	assert_dict(seen["warnings"]).is_empty()
	for message: String in seen["errors"]:
		assert_str(message).starts_with("ConfigFile parse error")


# --- add, remove, undo, redo, reset ---


func test_add_remove_undo_redo_keep_the_labels_exact_at_once() -> void:
	var lr: LabelRig.LabelRig = _open(FishRig.trio())
	if lr == null:
		return
	var added: FishInstance = FishRig.fish("f1000009", Api.ANGEL)
	var add: Command = AddFishCommand.new(lr.rig.model, added)
	assert_bool(add.do()).is_true()
	assert_int(LabelRig.all_labels(lr).size()).is_equal(4)
	assert_object(LabelRig.label_of(lr, "f1000009")).is_not_null()
	assert_bool(add.undo()).is_true()
	assert_int(lr.labels.get_child_count()).is_equal(3)
	assert_object(LabelRig.label_of(lr, "f1000009")).is_null()
	assert_bool(add.do()).is_true()
	assert_int(lr.labels.get_child_count()).is_equal(4)
	var remove: Command = RemoveFishCommand.new(lr.rig.model, "f1000001")
	assert_bool(remove.do()).is_true()
	assert_int(lr.labels.get_child_count()).is_equal(3)
	assert_object(LabelRig.label_of(lr, "f1000001")).is_null()
	assert_bool(remove.undo()).is_true()
	assert_int(lr.labels.get_child_count()).is_equal(4)
	assert_object(LabelRig.label_of(lr, "f1000001")).is_not_null()
	await _frame()
	assert_int(LabelRig.all_labels(lr).size()).is_equal(4)
	for label: Label3D in LabelRig.all_labels(lr):
		assert_bool(is_instance_valid(label) and label.is_inside_tree()).is_true()


func test_model_reset_leaves_labels_for_exactly_the_new_fish() -> void:
	var lr: LabelRig.LabelRig = _open(FishRig.trio())
	if lr == null:
		return
	var other: AquariumModel = FishRig.model(
		FishRig.MEDIUM,
		FishRig.SAND,
		[FishRig.fish("f2000001", Api.CORY), FishRig.fish("f2000002", Api.NEON)]
	)
	lr.rig.model.reset_from(other)
	assert_int(lr.labels.get_child_count()).is_equal(2)
	for uid: String in TRIO:
		assert_object(LabelRig.label_of(lr, uid)).is_null()
	var fresh: Array[String] = ["f2000001", "f2000002"]
	_check_anchors(lr, fresh, "after reset")


# --- text ---


func test_the_text_is_the_panel_row_string_and_follows_fish_changed() -> void:
	var lr: LabelRig.LabelRig = _open(FishRig.trio())
	if lr == null:
		return
	var entry: FishInstance = lr.rig.model.get_fish("f1000001")
	assert_str(LabelRig.label_of(lr, "f1000001").text).is_equal(LabelRig.shown_text(entry, self))
	var renamed: FishInstance = entry.copy()
	renamed.nickname = "Sparky"
	assert_bool(lr.rig.model.apply_replace_fish(renamed)).is_true()
	assert_str(LabelRig.label_of(lr, "f1000001").text).is_equal("Sparky")
	var cleared: FishInstance = renamed.copy()
	cleared.nickname = ""
	assert_bool(lr.rig.model.apply_replace_fish(cleared)).is_true()
	assert_str(LabelRig.label_of(lr, "f1000001").text).is_equal(LabelRig.shown_text(cleared, self))


func test_the_default_name_follows_the_language_and_a_nickname_does_not() -> void:
	var source: AquariumModel = FishRig.trio()
	source.get_fish("f1000003").nickname = "Goldie"
	var lr: LabelRig.LabelRig = _open(source)
	if lr == null:
		return
	var english: String = LabelRig.label_of(lr, "f1000001").text
	await Ui.set_language(self, "hu")
	var hungarian: String = LabelRig.label_of(lr, "f1000001").text
	assert_str(hungarian).is_not_equal(english)
	assert_str(hungarian).is_equal(LabelRig.shown_text(source.get_fish("f1000001"), self))
	assert_str(LabelRig.label_of(lr, "f1000003").text).is_equal("Goldie")


func test_a_long_nickname_is_cut_like_the_panel_and_the_stored_name_is_kept() -> void:
	var long_name: String = "N".repeat(300)
	var source: AquariumModel = FishRig.trio()
	source.get_fish("f1000001").nickname = long_name
	var lr: LabelRig.LabelRig = _open(source)
	if lr == null:
		return
	var text: String = LabelRig.label_of(lr, "f1000001").text
	assert_str(text).is_equal("N".repeat(FishNameText.MAX_SHOWN_CHARS) + "…")
	assert_str(source.get_fish("f1000001").nickname).is_equal(long_name)


func test_cjk_accented_and_multiline_nicknames_are_shown_as_one_line_text() -> void:
	var source: AquariumModel = FishRig.trio()
	source.get_fish("f1000001").nickname = "金魚ちゃん"
	source.get_fish("f1000003").nickname = "Árvíztűrő tükörfúrógép"
	source.get_fish("f1000006").nickname = "Two\nlines"
	var lr: LabelRig.LabelRig = _open(source)
	if lr == null:
		return
	assert_str(LabelRig.label_of(lr, "f1000001").text).is_equal("金魚ちゃん")
	assert_str(LabelRig.label_of(lr, "f1000003").text).is_equal("Árvíztűrő tükörfúrógép")
	assert_str(LabelRig.label_of(lr, "f1000006").text).is_equal("Two lines")


func test_a_nickname_equal_to_a_translation_key_is_not_translated() -> void:
	var source: AquariumModel = FishRig.trio()
	source.get_fish("f1000001").nickname = "settings.close"
	var lr: LabelRig.LabelRig = _open(source)
	if lr == null:
		return
	var label: Label3D = LabelRig.label_of(lr, "f1000001")
	assert_int(label.auto_translate_mode).is_equal(Node.AUTO_TRANSLATE_MODE_DISABLED)
	assert_str(label.text).is_equal("settings.close")


# --- position ---


func test_the_anchor_is_pose_plus_scaled_above_plus_two_cm_for_all_three_species() -> void:
	for species: StringName in Api.IDS:
		var source: AquariumModel = FishRig.model(
			FishRig.MEDIUM, FishRig.SAND, [FishRig.fish("f4000001", species)]
		)
		var lr: LabelRig.LabelRig = _open(source)
		if lr == null:
			return
		var one: Array[String] = ["f4000001"]
		_check_anchors(lr, one, str(species))
		var label: Label3D = LabelRig.label_of(lr, "f4000001")
		if label != null:
			var node: Node3D = FishRig.node_of(lr.rig, "f4000001")
			assert_float(label.position.y).is_greater(node.position.y)


func test_a_turned_fish_gets_a_label_that_ignores_the_rotation() -> void:
	var uid: String = ""
	var turned_model: AquariumModel = null
	for index: int in 200:
		var candidate: String = "f5%06d" % index
		var source: AquariumModel = FishRig.model(
			FishRig.MEDIUM, FishRig.SAND, [FishRig.fish(candidate, Api.ANGEL)]
		)
		var probe: LabelRig.LabelRig = _open(source, false)
		if probe == null:
			return
		var yaw: float = FishRig.expected_pose(probe.rig, candidate)["yaw"]
		if absf(rad_to_deg(wrapf(yaw, -PI, PI))) >= MIN_TURN_DEG:
			uid = candidate
			turned_model = source
			break
	assert_str(uid).override_failure_message("no fish turned by 30 degrees or more").is_not_empty()
	if turned_model == null:
		return
	var lr: LabelRig.LabelRig = _open(turned_model)
	if lr == null:
		return
	var node: Node3D = FishRig.node_of(lr.rig, uid)
	var turn: float = absf(rad_to_deg(wrapf(node.basis.get_euler().y, -PI, PI)))
	assert_float(turn).override_failure_message("the fish is not turned").is_greater_equal(
		MIN_TURN_DEG
	)
	var label: Label3D = LabelRig.label_of(lr, uid)
	assert_object(label).is_not_null()
	if label == null:
		return
	assert_float(label.position.x).is_equal_approx(node.position.x, LabelRig.TOLERANCE_M)
	assert_float(label.position.z).is_equal_approx(node.position.z, LabelRig.TOLERANCE_M)
	var turned: Array[String] = [uid]
	_check_anchors(lr, turned, "turned fish")
	assert_bool(label.global_basis.is_equal_approx(lr.labels.global_basis)).is_true()
	assert_bool(label.global_basis.is_equal_approx(node.global_basis)).is_false()


func test_a_bottom_fish_label_is_above_the_fish_and_the_bed() -> void:
	var source: AquariumModel = FishRig.model(
		FishRig.MEDIUM, FishRig.SAND, [FishRig.fish("f1000006", Api.CORY)]
	)
	var lr: LabelRig.LabelRig = _open(source)
	if lr == null:
		return
	var node: Node3D = FishRig.node_of(lr.rig, "f1000006")
	var label: Label3D = LabelRig.label_of(lr, "f1000006")
	if label == null or node == null:
		assert_bool(false).override_failure_message("no node or label").is_true()
		return
	var bed_top: float = 0.06 + Api.top_allowance(lr.rig.substrates.get_definition(FishRig.SAND))
	assert_float(label.position.y).is_greater(node.position.y)
	assert_float(node.position.y).is_greater(bed_top)


func test_the_labels_follow_a_variant_change() -> void:
	var lr: LabelRig.LabelRig = _open(FishRig.trio())
	if lr == null:
		return
	var changed: FishInstance = lr.rig.model.get_fish("f1000003").copy()
	changed.variant = 1
	assert_bool(lr.rig.model.apply_replace_fish(changed)).is_true()
	assert_int(LabelRig.all_labels(lr).size()).is_equal(3)
	_check_anchors(lr, TRIO, "after variant change")


func test_the_labels_follow_a_species_change() -> void:
	var lr: LabelRig.LabelRig = _open(FishRig.trio())
	if lr == null:
		return
	var changed: FishInstance = lr.rig.model.get_fish("f1000001").copy()
	changed.species_id = Api.ANGEL
	assert_bool(lr.rig.model.apply_replace_fish(changed)).is_true()
	assert_int(LabelRig.all_labels(lr).size()).is_equal(3)
	_check_anchors(lr, TRIO, "after species change")


func test_the_labels_follow_a_tank_change_with_undo_redo() -> void:
	var lr: LabelRig.LabelRig = _open(FishRig.trio(FishRig.LARGE, FishRig.SAND))
	if lr == null:
		return
	var command: ChangeTankCommand = ChangeTankCommand.new(
		lr.rig.model, lr.rig.tanks, FishRig.SMALL
	)
	assert_bool(command.do()).is_true()
	assert_int(lr.labels.get_child_count()).is_equal(0)
	assert_bool(command.undo()).is_true()
	assert_int(LabelRig.all_labels(lr).size()).is_equal(3)
	_check_anchors(lr, TRIO, "after tank undo")
	assert_bool(command.do()).is_true()
	assert_int(lr.labels.get_child_count()).is_equal(0)


func test_the_labels_follow_a_direct_tank_id_change() -> void:
	var lr: LabelRig.LabelRig = _open(FishRig.trio(FishRig.LARGE, FishRig.SAND))
	if lr == null:
		return
	lr.rig.model.apply_set_tank_id(FishRig.MEDIUM)
	assert_int(LabelRig.all_labels(lr).size()).is_equal(3)
	_check_anchors(lr, TRIO, "after tank id change")


func test_the_labels_follow_a_substrate_change() -> void:
	var lr: LabelRig.LabelRig = _open(FishRig.trio())
	if lr == null:
		return
	var colour: Color = lr.rig.substrates.get_definition(FishRig.PEBBLES).default_colour
	var command: SetSubstrateCommand = SetSubstrateCommand.new(
		lr.rig.model, lr.rig.substrates, FishRig.PEBBLES, colour
	)
	assert_bool(command.do()).is_true()
	_check_anchors(lr, TRIO, "after substrate change")
	assert_bool(command.undo()).is_true()
	_check_anchors(lr, TRIO, "after substrate undo")


func test_the_labels_follow_a_heightmap_change() -> void:
	var lr: LabelRig.LabelRig = _open(FishRig.trio())
	if lr == null:
		return
	lr.rig.model.apply_set_heightmap(PackedFloat32Array([0.03, 0.03, 0.03, 0.03]), Vector2i(2, 2))
	_check_anchors(lr, TRIO, "after heightmap change")


# --- skipped fish, no tank ---


func test_a_fish_of_an_unknown_species_has_no_label_and_nothing_crashes() -> void:
	var source: AquariumModel = FishRig.trio()
	source.apply_insert_fish(FishRig.fish("f1000099", &"no_such_fish"), source.get_fish_count())
	var holder: Array = []
	var seen: Dictionary = await EngineOutput.capture(func() -> void: holder.append(_open(source)))
	var lr: LabelRig.LabelRig = holder[0]
	if lr == null:
		return
	assert_dict(seen["errors"]).is_empty()
	for message: String in seen["warnings"]:
		assert_str(message).starts_with("FishView: ")
	assert_object(LabelRig.label_of(lr, "f1000099")).is_null()
	assert_int(LabelRig.all_labels(lr).size()).is_equal(3)


func test_an_unknown_tank_shows_no_label_and_hides_the_label_view() -> void:
	var source: AquariumModel = FishRig.trio()
	source.apply_set_tank_id(&"no_such_tank")
	var lr: LabelRig.LabelRig = _open(source)
	if lr == null:
		return
	assert_int(LabelRig.all_labels(lr).size()).is_equal(0)
	assert_bool(lr.labels.visible).is_false()
	source.apply_set_tank_id(FishRig.MEDIUM)
	assert_int(LabelRig.all_labels(lr).size()).is_equal(3)
	assert_bool(lr.labels.visible).is_true()


# --- 60 fish, no per-frame work, no model listeners ---


func _has_no_frame_code(node: Node) -> bool:
	var script: Script = node.get_script() as Script
	if script != null:
		for entry: Dictionary in script.get_script_method_list():
			if entry["name"] == &"_process" or entry["name"] == &"_physics_process":
				return false
	return not node.is_processing() and not node.is_physics_processing()


func test_sixty_fish_have_sixty_labels_and_no_node_with_per_frame_code() -> void:
	var lr: LabelRig.LabelRig = _open(LabelRig.crowd(60))
	if lr == null:
		return
	assert_int(lr.rig.model.get_fish_count()).is_equal(60)
	assert_int(LabelRig.all_labels(lr).size()).is_equal(60)
	assert_bool(_has_no_frame_code(lr.labels)).override_failure_message("label view").is_true()
	var offenders: Array[String] = []
	for label: Label3D in LabelRig.all_labels(lr):
		if not _has_no_frame_code(label):
			offenders.append(str(label.name))
	assert_array(offenders).is_empty()


func test_the_label_view_listens_to_no_model_signal() -> void:
	var lr: LabelRig.LabelRig = _open(FishRig.trio())
	if lr == null:
		return
	var model: AquariumModel = lr.rig.model
	var signals: Array[Signal] = [
		model.fish_added,
		model.fish_removed,
		model.fish_changed,
		model.tank_changed,
		model.substrate_changed,
		model.heightmap_changed,
		model.model_reset,
	]
	for model_signal: Signal in signals:
		for connection: Dictionary in model_signal.get_connections():
			var target: Callable = connection["callable"]
			(
				assert_object(target.get_object())
				. override_failure_message("the label view listens to %s" % model_signal.get_name())
				. is_not_same(lr.labels)
			)
