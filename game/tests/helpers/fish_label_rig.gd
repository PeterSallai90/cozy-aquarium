extends RefCounted
## Builds a FishView with a FishLabelView sibling in a test tree (#164 plan section 4). Both new
## classes are reached by path, so a missing script gives a null node and a readable failure and
## not a parse error that aborts the run. The label view gets its own Settings instance on a test
## path (never the live /root/Settings, never user://settings.cfg). Test helper only.

const FishRig := preload("res://tests/helpers/fish_view_rig.gd")
const SettingsRig := preload("res://tests/helpers/settings_rig.gd")
const SaveFixtures := preload("res://tests/helpers/save_fixtures.gd")
const Api := preload("res://tests/helpers/fish_api.gd")
const LABEL_PATH := "res://scenes/tank/fish/fish_label_view.gd"
const KEYS_PATH := "res://systems/settings/fish_setting_keys.gd"
const GAP_M: float = 0.02
const TOLERANCE_M: float = 0.001


class LabelRig:
	extends RefCounted
	var rig: FishRig.Rig = null
	var labels: Node3D = null
	var settings: Node = null
	## How many EventBus.setting_changed for [fish] show_names were seen.
	var changes: Array[bool] = []

	func on_setting_changed(section: String, key: String, value: Variant) -> void:
		if section == "fish" and key == "show_names":
			changes.append(bool(value))


static func settings_path(dir: String) -> String:
	return dir.path_join("settings.cfg")


## The show_names SettingKey; null while FishSettingKeys is missing.
static func key() -> RefCounted:
	var script: GDScript = Api.script_of(KEYS_PATH)
	if script == null:
		return null
	return script.call("show_names") as RefCounted


## Opens the view and the label view over `source`. `show_names` writes the setting before the
## label view is set up (a restart with the setting on).
static func open(
	suite: GdUnitTestSuite,
	source: AquariumModel,
	path: String,
	show_names: bool = false,
	catalog: RefCounted = null
) -> LabelRig:
	var result: LabelRig = LabelRig.new()
	result.rig = FishRig.open(suite, source, catalog)
	result.settings = suite.auto_free(SettingsRig.make_settings(suite, path))
	var keys: RefCounted = key()
	if show_names and result.settings != null and keys != null:
		result.settings.set_value(keys, true)
	var script: GDScript = Api.script_of(LABEL_PATH)
	if script == null or result.rig.view == null or result.settings == null:
		return result
	result.labels = script.new() as Node3D
	result.labels.set("settings", result.settings)
	result.rig.host.add_child(result.labels)
	result.labels.call("setup", source, result.rig.view)
	EventBus.setting_changed.connect(result.on_setting_changed)
	return result


static func close(lr: LabelRig) -> void:
	if EventBus.setting_changed.is_connected(lr.on_setting_changed):
		EventBus.setting_changed.disconnect(lr.on_setting_changed)


static func set_names(lr: LabelRig, value: bool) -> void:
	lr.settings.set_value(key(), value)


static func label_of(lr: LabelRig, uid: String) -> Label3D:
	if lr.labels == null:
		return null
	return lr.labels.call("get_label", uid) as Label3D


## Every Label3D below the label view, at any depth.
static func all_labels(lr: LabelRig) -> Array[Label3D]:
	var result: Array[Label3D] = []
	if lr.labels == null:
		return result
	for node: Node in lr.labels.find_children("*", "Label3D", true, false):
		if not node.is_queued_for_deletion():
			result.append(node as Label3D)
	return result


## The expected label position: the rest pose position plus UP * (scaled above_m + GAP_M). The
## scaled above_m comes from the rig's own measure of the species model, not from the view.
static func expected_anchor(lr: LabelRig, uid: String) -> Vector3:
	var entry: FishInstance = lr.rig.model.get_fish(uid)
	var pose: Dictionary = FishRig.expected_pose(lr.rig, uid)
	var adult: float = float(Api.field(entry.species_id, "adult_length_cm", 0.0))
	var above: float = float(FishRig.extents_of(entry.species_id, adult).get("above_m"))
	var position: Vector3 = pose["position"]
	return position + Vector3.UP * (above + GAP_M)


## The text the panel row shows for a fish.
static func shown_text(entry: FishInstance, translator: Object) -> String:
	return FishNameText.display(FishNameText.one_line(FishNameText.shown_name(entry, translator)))


## A model with `count` neon tetras (uids f3000000 ...), ids in order.
static func crowd(count: int) -> AquariumModel:
	var list: Array = []
	for index: int in count:
		list.append(FishRig.fish("f3%06d" % index, Api.NEON))
	return FishRig.model(FishRig.LARGE, FishRig.SAND, list)
