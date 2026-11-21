class_name PlacementSystem
extends Node3D
## Placement (#31, ADR 0012, ADR 0008 Amendment 1): picks, previews, places, selects, moves and
## rotates items. It is a child of RoomCorner and its transform is the tank-local frame (origin at
## the centre of the inner tank floor); the room pushes the tank frame and the shown substrate in
## with set_tank() and set_substrate().
##
## Everything the player sees before a commit lives in the views: the ghost rotation, the drag
## preview and the pending angle of a rotate hold are not in the model. The model changes through
## exactly five commands: one per placement, one per committed drop, one per rotate hold, one per
## delete and one per recolour (#32, ADR 0012 Amendment 1). The
## browser owns the pick (placement mirrors it from item_picked and item_pick_cleared and asks it to
## clear through EventBus.item_pick_clear_requested); this system owns the selection and announces
## it on the EventBus. The world is blocked while a modal dialog or photo mode is up: nothing is
## handled, running gestures end with no command and the feedback is hidden.
##
## The selected item is edited here only: the Delete key and the HUD requests
## EventBus.item_delete_requested and item_colour_requested run through the same guards. The node
## is in WorldInput.GESTURE_GROUP and answers has_running_gesture(), which undo and redo ask
## (ADR 0008 Amendment 2 rule 16).

enum Target { NONE, GHOST, DRAG, ITEM }

const ACTION_PRIMARY: StringName = &"place_primary"
const ACTION_LEFT: StringName = &"place_rotate_left"
const ACTION_RIGHT: StringName = &"place_rotate_right"
const ACTION_CANCEL: StringName = &"ui_cancel"
const ACTION_DELETE: StringName = &"item_delete"

var _model: AquariumModel = null
var _history: CommandHistory = null
var _source: ItemCatalogSource = null
var _rules: PlacementRules = null
var _uids: UidGenerator = UidGenerator.new()
var _tank: TankDefinition = null
var _substrate: SubstrateDefinition = null

var _picked_id: StringName = &""
var _ghost_rotation: float = 0.0
var _selected_uid: String = ""

var _pointer: Vector2 = Vector2.ZERO
var _pointer_known: bool = false
var _over_ui: bool = false
var _was_blocked: bool = false
var _shift_down: bool = false

var _press_active: bool = false
var _press_pos: Vector2 = Vector2.ZERO
var _press_uid: String = ""
var _dragging: bool = false
var _drag_uid: String = ""
var _drag_rotation: float = 0.0

var _hold: RotateHold = RotateHold.new()
var _hold_target: Target = Target.NONE
var _hold_action: StringName = &""
var _hold_uid: String = ""
## True when the first step of the running hold on an item was refused at the press (#33 AC 15).
var _hold_press_refused: bool = false
## True after a modifier cancelled a hold, until the cancelling chord is over (rule 16): the
## Ctrl+Z that cancelled a hold must not also undo.
var _cancel_tail: bool = false
## The first non-modifier key of the cancelling chord; 0 while none was seen.
var _tail_key: int = 0

var _ray_origin: Vector3 = Vector3.ZERO
var _ray_direction: Vector3 = Vector3.ZERO
## Scratch item for the validity check of the ghost, so a frame allocates nothing.
var _probe: PlacedItem = PlacedItem.new()

@onready var _view: PlacedItemsView = $PlacedItems
@onready var _ghost: ItemGhost = $Ghost


func _ready() -> void:
	add_to_group(WorldInput.GESTURE_GROUP)


## Connects the system to the model, the history and the shared item source. Null history, source
## and rules get fallbacks (a new history, a new source, rules for the shipped tanks).
func setup(
	model: AquariumModel, history: CommandHistory, source: ItemCatalogSource, rules: PlacementRules
) -> void:
	_model = model
	_history = history if history != null else CommandHistory.new()
	_source = source if source != null else ItemCatalogSource.new()
	_rules = (
		rules
		if rules != null
		else PlacementRules.new(TankCatalog.load_dir(), _source, SubstrateCatalog.load_dir())
	)
	_view.setup(_model, _source)
	_model.item_removed.connect(_on_item_removed)
	_model.item_changed.connect(_on_item_changed)
	_model.model_reset.connect(_on_model_reset)
	EventBus.item_picked.connect(_on_item_picked)
	EventBus.item_pick_cleared.connect(_on_item_pick_cleared)
	EventBus.tank_displayed.connect(_on_tank_displayed)
	EventBus.item_delete_requested.connect(_on_delete_requested)
	EventBus.item_colour_requested.connect(_on_colour_requested)


## The tank shown now and its frame in the world; null when no tank is shown.
func set_tank(definition: TankDefinition, origin: Transform3D) -> void:
	_tank = definition
	if definition != null:
		global_transform = origin
	_view.set_tank(definition)


## The substrate the bed shows: items and the ground plane stand on its nominal surface.
func set_substrate(definition: SubstrateDefinition) -> void:
	_substrate = definition
	_view.set_substrate(definition)


func get_selected_uid() -> String:
	return _selected_uid


func get_picked_id() -> StringName:
	return _picked_id


func get_ghost_rotation() -> float:
	return _ghost_rotation


func is_dragging() -> bool:
	return _dragging


## True while a rotate hold on the selected item runs (not for the ghost or a drag preview).
func is_holding() -> bool:
	return _hold.is_active() and _hold_target == Target.ITEM


## True while a drag, a press that may become a drag, a rotate hold or the tail of a cancelled
## hold runs. Undo and redo wait for it (ADR 0008 Amendment 2 rule 16).
func has_running_gesture() -> bool:
	return _press_active or _dragging or _hold.is_active() or _cancel_tail


func _process(delta: float) -> void:
	step(delta)


## One frame: the blocked check, the key repeat and the ghost following the pointer.
func step(delta_s: float) -> void:
	if _model == null:
		return
	if _check_blocked():
		_ghost.visible = false
		return
	if _hold.is_active():
		if _hold.tick(delta_s, _shift_down) > 0:
			_apply_hold_pending()
	_view.step_cue(delta_s)
	_update_ghost()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_cancel_gestures()
		_pointer_known = false


# --- input ---


## Gestures that must win over the GUI: releases, motion, Shift, the Esc of a drag or a hold.
func _input(event: InputEvent) -> void:
	if _model == null or _check_blocked():
		return
	var key: InputEventKey = event as InputEventKey
	if key != null:
		_on_key_early(key)
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		_on_motion(motion)
		return
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null and not button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		_on_left_release(button.position)


## Presses that start something: placing, selecting, a rotate key, and the idle Esc.
func _unhandled_input(event: InputEvent) -> void:
	if _model == null or _check_blocked():
		return
	var key: InputEventKey = event as InputEventKey
	if key != null:
		_on_key_late(key)
		return
	if event.is_action_pressed(ACTION_PRIMARY):
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button != null:
			_on_press(button.position)


func _on_key_early(key: InputEventKey) -> void:
	if key.keycode == KEY_SHIFT or key.physical_keycode == KEY_SHIFT:
		_shift_down = key.pressed
	if _cancel_tail:
		_follow_tail(key)
	if not key.pressed:
		if _hold.is_active() and key.is_action(_hold_action, false):
			_end_hold(true)
		return
	if _hold.is_active() and _is_cancel_modifier(key):
		_cancel_hold()
		_begin_tail(key)
	if key.echo or not key.is_action_pressed(ACTION_CANCEL):
		return
	if _dragging:
		_end_drag()
		get_viewport().set_input_as_handled()
	elif is_holding():
		_cancel_hold()
		get_viewport().set_input_as_handled()


## The cancelling chord goes on: its first plain key is remembered and its release ends the tail;
## so does any key event with Ctrl, Alt and Meta all up.
func _follow_tail(key: InputEventKey) -> void:
	if not (key.ctrl_pressed or key.alt_pressed or key.meta_pressed):
		_end_tail()
		return
	var id: int = _key_id(key)
	if key.pressed:
		if _tail_key == 0 and not key.echo and not _is_modifier_key(key):
			_tail_key = id
	elif _tail_key != 0 and id == _tail_key:
		_end_tail()


func _begin_tail(key: InputEventKey) -> void:
	_cancel_tail = true
	_tail_key = 0
	if not key.echo and not _is_modifier_key(key):
		_tail_key = _key_id(key)


func _end_tail() -> void:
	_cancel_tail = false
	_tail_key = 0


static func _key_id(key: InputEventKey) -> int:
	return key.physical_keycode if key.physical_keycode != 0 else key.keycode


static func _is_modifier_key(key: InputEventKey) -> bool:
	return (
		key.keycode in [KEY_CTRL, KEY_ALT, KEY_META, KEY_SHIFT]
		or key.physical_keycode in [KEY_CTRL, KEY_ALT, KEY_META, KEY_SHIFT]
	)


func _is_cancel_modifier(key: InputEventKey) -> bool:
	if key.ctrl_pressed or key.alt_pressed or key.meta_pressed:
		return true
	return (
		key.keycode in [KEY_CTRL, KEY_ALT, KEY_META]
		or key.physical_keycode in [KEY_CTRL, KEY_ALT, KEY_META]
	)


func _on_key_late(key: InputEventKey) -> void:
	if not key.pressed or key.echo:
		return
	if key.is_action_pressed(ACTION_CANCEL):
		if _picked_id != &"":
			EventBus.item_pick_clear_requested.emit()
			get_viewport().set_input_as_handled()
		elif _selected_uid != "":
			_clear_selection()
			get_viewport().set_input_as_handled()
		return
	if key.is_action_pressed(ACTION_DELETE, false, true):
		if not WorldInput.is_text_focused(get_viewport()) and _try_delete():
			get_viewport().set_input_as_handled()
		return
	var left: bool = key.is_action_pressed(ACTION_LEFT, false, false)
	var right: bool = key.is_action_pressed(ACTION_RIGHT, false, false)
	if not (left or right) or not WorldInput.allows_fine_modifier(key):
		return
	if WorldInput.is_text_focused(get_viewport()):
		return
	_shift_down = key.shift_pressed
	if _start_hold(1 if left else -1, ACTION_LEFT if left else ACTION_RIGHT):
		get_viewport().set_input_as_handled()


func _on_motion(motion: InputEventMouseMotion) -> void:
	_pointer = motion.position
	_pointer_known = true
	_over_ui = WorldInput.is_over_stop_control(get_viewport(), _pointer)
	if _press_active and not _dragging:
		if _pointer.distance_to(_press_pos) > PlacementTuning.DRAG_THRESHOLD_PX:
			_begin_drag()


func _on_press(at: Vector2) -> void:
	_pointer = at
	_pointer_known = true
	_over_ui = WorldInput.is_over_stop_control(get_viewport(), at)
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if focus_owner is LineEdit or focus_owner is TextEdit:
		get_viewport().gui_release_focus()
	if is_holding():
		_cancel_hold()
	if _over_ui or _tank == null:
		return
	if _picked_id != &"":
		_place_at(at)
		return
	var uid: String = _hit_at(at)
	if uid != "":
		_press_active = true
		_press_pos = at
		_press_uid = uid
	else:
		_press_active = false
		_clear_selection()


func _on_left_release(at: Vector2) -> void:
	if not _press_active:
		return
	_press_active = false
	var uid: String = _press_uid
	_press_uid = ""
	if _dragging:
		_finish_drag(at)
	else:
		_set_selection(uid)


# --- placing ---


func _place_at(at: Vector2) -> void:
	if _scene_for(_picked_id) == null:
		return
	var ground: Variant = _ground_position(at)
	if ground == null or not _valid(_picked_id, ground as Vector3, _ghost_rotation, 1.0, null):
		return
	var item: PlacedItem = PlacedItem.new()
	item.uid = _uids.generate(_model)
	item.catalog_id = _picked_id
	item.position = ground as Vector3
	item.rotation_y = _ghost_rotation
	item.scale = 1.0
	_history.execute(PlaceItemCommand.new(_model, item, _rules))


# --- dragging ---


func _begin_drag() -> void:
	var item: PlacedItem = _model.get_item(_press_uid)
	if item == null:
		_press_active = false
		return
	_dragging = true
	_drag_uid = _press_uid
	_drag_rotation = item.rotation_y


func _finish_drag(at: Vector2) -> void:
	var uid: String = _drag_uid
	var rotation_deg: float = _drag_rotation
	_end_drag()
	var item: PlacedItem = _model.get_item(uid)
	var ground: Variant = _ground_position(at)
	if item == null or ground == null:
		return
	if WorldInput.is_over_stop_control(get_viewport(), at):
		return
	var target: Vector3 = ground as Vector3
	if not _valid(item.catalog_id, target, rotation_deg, item.scale, item):
		return
	var same_spot: bool = (
		Vector2(target.x - item.position.x, target.z - item.position.z).length()
		< PlacementTuning.SAME_SPOT_M
	)
	if not (same_spot and _same_angle(rotation_deg, item.rotation_y)):
		var move: TransformItemCommand = TransformItemCommand.new(
			_model, uid, target, rotation_deg, _rules
		)
		if not _history.execute(move):
			return
	_set_selection(uid)


## Ends a drag with no command: the preview goes, the drawn item stays where it was.
func _end_drag() -> void:
	_dragging = false
	_drag_uid = ""
	_press_active = false
	_press_uid = ""
	if _hold_target == Target.DRAG:
		_hold.cancel()
		_hold_target = Target.NONE
	_ghost.visible = false


# --- delete and recolour ---


## True when the selected item may be edited now: the same guard for the key and the HUD requests.
func _can_edit_selection() -> bool:
	return (
		_model != null
		and _tank != null
		and _selected_uid != ""
		and _picked_id == &""
		and not has_running_gesture()
		and not WorldInput.is_blocked(get_tree())
		and not _history.is_busy()
	)


func _try_delete() -> bool:
	if not _can_edit_selection():
		return false
	return _history.execute(DeleteItemCommand.new(_model, _selected_uid))


func _try_recolour(has_colour: bool, colour: Color) -> bool:
	if not _can_edit_selection():
		return false
	var item: PlacedItem = _model.get_item(_selected_uid)
	if item == null:
		return false
	var definition: ItemDefinition = _source.get_catalog().get_definition(item.catalog_id)
	if definition == null or not definition.colourable:
		return false
	return _history.execute(RecolourItemCommand.new(_model, _selected_uid, has_colour, colour))


func _on_delete_requested() -> void:
	_try_delete()


func _on_colour_requested(has_colour: bool, colour: Color) -> void:
	_try_recolour(has_colour, colour)


# --- rotate hold ---


func _start_hold(direction: int, action: StringName) -> bool:
	if _hold.is_active():
		_end_hold(true)
	var start_deg: float = 0.0
	var target: Target = Target.NONE
	if _dragging:
		target = Target.DRAG
		start_deg = _drag_rotation
	elif _picked_id != &"":
		target = Target.GHOST
		start_deg = _ghost_rotation
	elif _selected_uid != "":
		var item: PlacedItem = _model.get_item(_selected_uid)
		if item == null:
			return false
		target = Target.ITEM
		start_deg = item.rotation_y
		_hold_uid = _selected_uid
	else:
		return false
	_hold_target = target
	_hold_action = action
	_hold.press(direction, start_deg, _shift_down)
	_hold_press_refused = false
	if target == Target.ITEM:
		# The first step is judged at the press: a refused one keeps the drawn angle and cues.
		var held: PlacedItem = _model.get_item(_hold_uid)
		var pending: float = _hold.get_pending_deg()
		if not _valid(held.catalog_id, held.position, pending, held.scale, held):
			_hold_press_refused = true
			_view.play_refusal_cue(_hold_uid)
			return true
	_apply_hold_pending()
	return true


func _apply_hold_pending() -> void:
	var pending: float = _hold.get_pending_deg()
	match _hold_target:
		Target.GHOST:
			_ghost_rotation = pending
		Target.DRAG:
			_drag_rotation = pending
		Target.ITEM:
			_view.show_pending_rotation(_hold_uid, pending)


## The key was released (or another rotate key took over): a hold on the selected item runs its
## one command now, when the final angle differs from the model angle.
func _end_hold(commit: bool) -> void:
	if not _hold.is_active():
		return
	var target: Target = _hold_target
	var uid: String = _hold_uid
	var pending: float = _hold.get_pending_deg()
	_hold.release()
	_hold_target = Target.NONE
	if target != Target.ITEM:
		return
	var item: PlacedItem = _model.get_item(uid)
	var tap_refused: bool = _hold_press_refused and _hold.get_repeat_count() == 0
	_hold_press_refused = false
	if tap_refused or item == null or not commit or _same_angle(pending, item.rotation_y):
		_view.clear_pending(uid)
		return
	if _valid(item.catalog_id, item.position, pending, item.scale, item):
		_history.execute(TransformItemCommand.new(_model, uid, item.position, pending, _rules))
		_view.clear_pending(uid)
	else:
		_view.clear_pending(uid)
		_view.play_refusal_cue(uid)


## Drops a hold with no command; a hold on the selected item shows its model angle again.
func _cancel_hold() -> void:
	if not _hold.is_active():
		return
	var target: Target = _hold_target
	var uid: String = _hold_uid
	_hold.cancel()
	_hold_target = Target.NONE
	_hold_press_refused = false
	if target == Target.ITEM:
		_view.clear_pending(uid)


func _cancel_gestures() -> void:
	if _dragging:
		_end_drag()
	_cancel_hold()
	_end_tail()
	_press_active = false
	_press_uid = ""
	_ghost.visible = false


# --- selection ---


func _set_selection(uid: String) -> void:
	if uid == _selected_uid:
		return
	_cancel_hold()
	_selected_uid = uid
	_view.set_selected(uid)
	EventBus.item_selected.emit(uid)


func _clear_selection() -> void:
	if _selected_uid == "":
		return
	_cancel_hold()
	_selected_uid = ""
	_view.set_selected("")
	EventBus.item_selection_cleared.emit()


# --- signals ---


func _on_item_picked(catalog_id: StringName) -> void:
	_clear_selection()
	_cancel_gestures()
	_picked_id = catalog_id
	_ghost_rotation = 0.0


func _on_item_pick_cleared() -> void:
	if _hold_target == Target.GHOST:
		_hold.cancel()
		_hold_target = Target.NONE
	_picked_id = &""
	_ghost_rotation = 0.0
	_ghost.visible = false


func _on_item_removed(uid: String, _index: int) -> void:
	if _dragging and uid == _drag_uid:
		_end_drag()
	if uid == _selected_uid:
		_clear_selection()


func _on_item_changed(uid: String, _index: int) -> void:
	if _dragging and uid == _drag_uid:
		_end_drag()
	if _hold_target == Target.ITEM and uid == _hold_uid:
		_cancel_hold()


func _on_model_reset() -> void:
	_cancel_gestures()
	_pointer_known = false
	_clear_selection()


func _on_tank_displayed(_tank_id: StringName) -> void:
	_cancel_gestures()
	_clear_selection()


# --- the ghost and the pointer ---


## True (and everything feedback hidden) while a modal dialog or photo mode blocks the world.
func _check_blocked() -> bool:
	var blocked: bool = WorldInput.is_blocked(get_tree())
	if blocked != _was_blocked:
		_was_blocked = blocked
		_view.set_feedback_visible(not blocked)
	if blocked:
		_cancel_gestures()
	return blocked


func _update_ghost() -> void:
	var shown: bool = false
	var item_id: StringName = &""
	var rotation_deg: float = 0.0
	var item_scale: float = 1.0
	var before: PlacedItem = null
	if _dragging:
		before = _model.get_item(_drag_uid)
		if before != null:
			item_id = before.catalog_id
			rotation_deg = _drag_rotation
			item_scale = before.scale
	elif _picked_id != &"":
		item_id = _picked_id
		rotation_deg = _ghost_rotation
	var scene: PackedScene = _scene_for(item_id) if item_id != &"" else null
	if scene != null and _pointer_known and not _over_ui:
		var ground: Variant = _ground_position(_pointer)
		if ground != null and _valid(item_id, ground as Vector3, rotation_deg, item_scale, before):
			var spot: Vector3 = ground as Vector3
			if _ghost.show_item(item_id, scene):
				_ghost.place(
					Vector3(spot.x, _surface_y() + spot.y, spot.z), rotation_deg, item_scale
				)
				shown = true
	_ghost.visible = shown


## The scene of an item id from the shared catalog, or null (unknown id, no scene).
func _scene_for(item_id: StringName) -> PackedScene:
	if item_id == &"":
		return null
	var definition: ItemDefinition = _source.get_catalog().get_definition(item_id)
	return definition.scene if definition != null else null


## The model position (x, 0, z) under a screen position on the nominal substrate plane, or null
## when there is no ground point (no camera, no tank, parallel, from below, behind the camera).
func _ground_position(screen: Vector2) -> Variant:
	if _tank == null or _substrate == null or not _aim(screen):
		return null
	var hit: Dictionary = GroundRay.intersect(_ray_origin, _ray_direction, _surface_y())
	if hit["ok"] != true:
		return null
	var point: Vector3 = hit["point"]
	return Vector3(point.x, 0.0, point.z)


## Sets the pointer ray in the tank-local frame; false without a camera.
func _aim(screen: Vector2) -> bool:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return false
	var inverse: Transform3D = global_transform.affine_inverse()
	_ray_origin = inverse * camera.project_ray_origin(screen)
	_ray_direction = inverse.basis * camera.project_ray_normal(screen)
	return true


## The height of the nominal substrate surface above the tank floor (the ground plane).
func _surface_y() -> float:
	return SubstrateSurface.height_at(
		_substrate,
		_model.get_heightmap(),
		_model.get_heightmap_size(),
		_tank.interior_size_m,
		0.0,
		0.0
	)


## The uid of the placed item under the pointer, or an empty string.
func _hit_at(screen: Vector2) -> String:
	if not _aim(screen):
		return ""
	var entries: Array = _view.get_hit_entries()
	var index: int = ItemHitTest.nearest(_ray_origin, _ray_direction, entries)
	if index < 0:
		return ""
	return (entries[index] as Dictionary)["uid"]


## What is shown is what is committed: the same rule the commands ask.
func _valid(
	item_id: StringName, spot: Vector3, rotation_deg: float, item_scale: float, before: PlacedItem
) -> bool:
	_probe.catalog_id = item_id
	_probe.scale = item_scale
	_probe.position = spot
	_probe.rotation_y = rotation_deg
	return _rules.allows(_model, _probe, before)


static func _same_angle(a: float, b: float) -> bool:
	return absf(wrapf(a - b, -180.0, 180.0)) <= PlacementTuning.SAME_ANGLE_DEG
