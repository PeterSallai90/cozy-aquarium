class_name FishLabelView
extends Node3D
## Name labels above the fish (#164): an overlay of the fish view, a sibling of FishView in the
## tank frame. With [fish] show_names on it shows one Label3D per drawn fish, upright (billboard)
## above the fish at its pose node position + UP * (scaled above_m + GAP_M); it never follows the
## fish rotation. Off (the default) or with no tank it holds no label node at all.
##
## Contract (plan addendum, amended by #35, ADR 0015 rule 10): it reads FishView only through
## refreshed, poses_moved, has_tank(), get_fish_node() (position only) and get_extents(); it never
## writes to the view or a pose node and keeps no pose-node reference after a handler returns. It
## listens to no model signal: every structural update (create, free, text) comes from
## FishView.refreshed. While labels are shown it also listens to FishView.poses_moved and moves the
## existing labels to the new pose position in that same call, keeping per fish only a float offset
## (above_m + GAP_M); hidden labels hold no connection and cost no work. Its other inputs are
## EventBus.setting_changed and EventBus.language_changed. No _process.

## Gap between the top of the fish and the label, metres (starting value, the owner may tune it).
const GAP_M: float = 0.02
const OUTLINE_SIZE: int = 8
const FONT_SIZE: int = 32
const PIXEL_SIZE: float = 0.0007

## The Settings node to read; null means /root/Settings. Set before setup() (tests).
var settings: Node = null

var _model: AquariumModel = null
var _view: FishView = null
var _labels: Dictionary[String, Label3D] = {}
## Uid to the height of the label above the pose position (above_m + GAP_M); only while shown.
var _offsets: Dictionary[String, float] = {}


## Connects to the view and the EventBus and syncs once. Call after the view is set up; a second
## call replaces the first.
func setup(model: AquariumModel, fish_view: FishView) -> void:
	_disconnect()
	_model = model
	_view = fish_view
	_view.refreshed.connect(_sync)
	EventBus.setting_changed.connect(_on_setting_changed)
	EventBus.language_changed.connect(_on_language_changed)
	_sync()


## The label of a fish, or null when it has none.
func get_label(uid: String) -> Label3D:
	return _labels.get(uid)


func _disconnect() -> void:
	if _view != null and _view.refreshed.is_connected(_sync):
		_view.refreshed.disconnect(_sync)
	_stop_following()
	if EventBus.setting_changed.is_connected(_on_setting_changed):
		EventBus.setting_changed.disconnect(_on_setting_changed)
	if EventBus.language_changed.is_connected(_on_language_changed):
		EventBus.language_changed.disconnect(_on_language_changed)


func _settings() -> Node:
	if settings != null:
		return settings
	return get_node_or_null("/root/Settings")


func _names_on() -> bool:
	var source: Node = _settings()
	if source == null:
		return false
	return source.get_value(FishSettingKeys.show_names()) as bool


func _sync() -> void:
	if _model == null or _view == null:
		return
	if not _names_on() or not _view.has_tank():
		_clear()
		_stop_following()
		visible = false
		return
	visible = true
	if not _view.poses_moved.is_connected(_on_poses_moved):
		_view.poses_moved.connect(_on_poses_moved)
	var drawn: Dictionary[String, bool] = {}
	for entry: FishInstance in _model.get_fish_list():
		var node: Node3D = _view.get_fish_node(entry.uid)
		var extents: FishExtents = _view.get_extents(entry.uid)
		if node == null or extents == null:
			continue
		drawn[entry.uid] = true
		var label: Label3D = _labels.get(entry.uid)
		if label == null:
			label = _make_label()
			_labels[entry.uid] = label
			add_child(label)
		_offsets[entry.uid] = extents.above_m + GAP_M
		label.position = node.position + Vector3.UP * _offsets[entry.uid]
		_set_text(label, entry)
	for uid: String in _labels.keys():
		if not drawn.has(uid):
			_free_label(uid)


func _make_label() -> Label3D:
	var label: Label3D = Label3D.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.no_depth_test = false
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.font_size = FONT_SIZE
	label.outline_size = OUTLINE_SIZE
	label.pixel_size = PIXEL_SIZE
	label.modulate = Color(1.0, 1.0, 1.0)
	label.outline_modulate = Color(0.05, 0.08, 0.12, 0.9)
	return label


func _set_text(label: Label3D, entry: FishInstance) -> void:
	var text: String = FishNameText.display(
		FishNameText.one_line(FishNameText.shown_name(entry, self))
	)
	if label.text != text:
		label.text = text


func _clear() -> void:
	for uid: String in _labels.keys():
		_free_label(uid)
	_offsets.clear()


func _stop_following() -> void:
	if _view != null and _view.poses_moved.is_connected(_on_poses_moved):
		_view.poses_moved.disconnect(_on_poses_moved)


## The fish moved: every existing label goes to its fish in this same call. It never creates or
## frees a label and never sets a text.
func _on_poses_moved() -> void:
	for uid: String in _labels:
		var node: Node3D = _view.get_fish_node(uid)
		if node != null:
			_labels[uid].position = node.position + Vector3.UP * _offsets[uid]


func _free_label(uid: String) -> void:
	var label: Label3D = _labels[uid]
	_labels.erase(uid)
	_offsets.erase(uid)
	remove_child(label)
	label.queue_free()


func _on_setting_changed(section: String, key: String, _value: Variant) -> void:
	var setting: SettingKey = FishSettingKeys.show_names()
	if section == setting.section and key == setting.key:
		_sync()


func _on_language_changed(_language: String) -> void:
	if _model == null:
		return
	for entry: FishInstance in _model.get_fish_list():
		var label: Label3D = _labels.get(entry.uid)
		if label != null:
			_set_text(label, entry)
